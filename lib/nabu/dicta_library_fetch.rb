# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "zip_reader"
require_relative "version"

module Nabu
  # The per-book download for Dicta's library (dicta-library; the PomaFetch
  # mold — resumable, written at once, a polite sequential crawl). The
  # manifest is upstream's books.json, already on disk (the adapter
  # git-fetches the Dicta-Library-Download repo that carries it); this class
  # materializes, per manifest entry, into <books dir>:
  #
  #   <fileName>.json                    the manifest entry verbatim (a sidecar:
  #                                      every book self-describing, so a book
  #                                      upstream later drops keeps its
  #                                      metadata — retention by construction)
  #   <fileName>__text_files.zip         the plain-text zip (textFileURL)
  #   <fileName>__nikud_meteg_files.zip  ONLY when the text zip is EMPTY
  #                                      (an upstream packaging gap: 3 of 1,205
  #                                      at the 2026-11-16 census) — the
  #                                      vocalized zip is then the book's one
  #                                      text witness
  #
  # == Resume + re-sync posture
  #
  # A zip already on disk is NOT re-fetched; every download is written at
  # once (tmp + rename), so an interrupted first crawl resumes at the book
  # grain. Upstream versions its paths (library-1-0/), so a content change
  # arrives as new URLs, not a silent overwrite; refreshing one book means
  # deleting its zip. Sidecars are rewritten when the manifest entry changes
  # (metadata corrections land), never deleted.
  #
  # Retention is ADDITIVE: nothing under the books dir is ever deleted, so
  # there is no doomed set and no attic step (the git-tracked manifest's own
  # history rides GitFetch's attic/breaker in the adapter).
  #
  # A 404 is CENSUSED and skipped (one missing book is upstream damage); a
  # SYSTEMIC miss rate aborts. 5xx and transport failures retry 3× with
  # exponential backoff. A malformed manifest aborts BEFORE any write.
  class DictaLibraryFetch
    # HTTP failure, a malformed manifest, or a systemic miss. The adapter
    # wraps it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".dicta-library-fetch.json"
    TEXT_SUFFIX = "__text_files.zip"
    NIKUD_SUFFIX = "__nikud_meteg_files.zip"

    # Upstream's file names: transliterated stems with (h)/(z) letter marks,
    # "=" before a catalogue number — never a path separator or dot-segment.
    FILE_NAME = /\A[A-Za-z0-9()_=-]+\z/
    URL_HOST = "https://files.dicta.org.il/"

    # Seconds between HTTP requests (sequential, polite — a non-profit's CDN;
    # 1,205 books ≈ 5 min of pauses on top of the transfer).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 0.25

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    # const: abort threshold, not a corpus claim
    MISSING_CAP_FRACTION = 0.01
    MISSING_CAP_FLOOR = 5

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:books, :fetched, :cached, :fallbacks, :missing)

    def self.sync!(manifest_path:, dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
      new(manifest_path: manifest_path, dir: dir, http: http, delay: delay, progress: progress).sync!
    end

    # The parsed manifest's entries, each checked for the fields the crawl
    # and the adapter rely on (Error on the first bad one — loud, pre-write).
    def self.entries(manifest_path)
      parsed = JSON.parse(File.read(manifest_path))
      raise Error, "#{manifest_path}: the manifest is not a JSON array" unless parsed.is_a?(Array)

      parsed.each_with_index { |entry, index| check_entry!(entry, index, manifest_path) }
      names = parsed.map { |entry| entry["fileName"] }
      duplicate = names.tally.find { |_name, count| count > 1 }
      raise Error, "#{manifest_path}: fileName #{duplicate.first.inspect} listed twice" if duplicate

      parsed
    rescue JSON::ParserError => e
      raise Error, "#{manifest_path}: malformed manifest JSON: #{e.message}"
    rescue Errno::ENOENT
      raise Error, "#{manifest_path}: no manifest on disk (the repo fetch did not land books.json)"
    end

    def self.check_entry!(entry, index, manifest_path)
      name = entry.is_a?(Hash) ? entry["fileName"] : nil
      unless name.is_a?(String) && name.match?(FILE_NAME)
        raise Error, "#{manifest_path}: entry #{index} has no safe fileName (#{name.inspect})"
      end

      { "textFileURL" => TEXT_SUFFIX, "nikudMetegFileURL" => NIKUD_SUFFIX }.each do |key, suffix|
        url = entry[key]
        next if url.is_a?(String) && url.start_with?(URL_HOST) && url.end_with?("/#{name}#{suffix}")

        raise Error, "#{manifest_path}: #{name} #{key} #{url.inspect} is not the files.dicta.org.il " \
                     "#{name}#{suffix} the crawl expects"
      end
    end
    private_class_method :check_entry!

    # An empty archive is its 22-byte end record; only a file this small is
    # opened to make sure (the gate keeps re-syncs and discovery off the
    # ~536 MB of real zips).
    # const: ZIP format size bound (EOCD 22 B + slack), not a corpus claim
    EMPTY_ZIP_GATE = 64

    # True when the zip at +path+ holds no member (upstream's 22-byte empty
    # archive), or is a tiny file unreadable as a zip at all.
    def self.empty_zip?(path)
      return false if File.size(path) > EMPTY_ZIP_GATE

      Nabu::ZipReader.new(File.binread(path)).entries.empty?
    rescue Nabu::ZipReader::Error
      true
    end

    def initialize(manifest_path:, dir:, http:, delay:, progress:)
      @manifest_path = manifest_path
      @dir = dir
      @http = http
      @delay = delay
      @progress = progress
      @fetched = 0
      @cached = 0
      @fallbacks = []
      @missing = []
      @requests = 0
    end

    def sync!
      entries = self.class.entries(@manifest_path)
      FileUtils.mkdir_p(@dir)
      entries.each_with_index do |entry, index|
        @progress&.call("Dicta library book #{index + 1}/#{entries.size}…\n") if (index % 50).zero?
        write_sidecar!(entry)
        crawl_book!(entry)
      end
      cap = [(entries.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
      if @missing.size > cap
        raise Error, "#{@missing.size} of #{entries.size} book zips 404 — a systemic miss, not holes: " \
                     "the file host has moved (first missing: #{@missing.first(3).join(', ')})"
      end
      write_state!(entries.size)
      Result.new(books: entries.size, fetched: @fetched, cached: @cached, fallbacks: @fallbacks, missing: @missing)
    end

    private

    def write_sidecar!(entry)
      body = "#{JSON.pretty_generate(entry)}\n"
      path = File.join(@dir, "#{entry['fileName']}.json")
      write!(path, body) unless File.file?(path) && File.read(path) == body
    end

    # The text zip; the vocalized zip only when the text zip is empty.
    def crawl_book!(entry)
      name = entry["fileName"]
      text = File.join(@dir, "#{name}#{TEXT_SUFFIX}")
      return unless held_after_download?(entry["textFileURL"], text, name)
      return unless self.class.empty_zip?(text)

      @fallbacks << name
      held_after_download?(entry["nikudMetegFileURL"], File.join(@dir, "#{name}#{NIKUD_SUFFIX}"), name)
    end

    # true when the file is on disk afterwards (cached or fetched).
    def held_after_download?(url, path, name)
      if File.file?(path)
        @cached += 1
        return true
      end

      body = get_with_retry(url)
      if body.nil?
        @missing << name
        @progress&.call("Dicta library #{name}: 404 at #{url} (censused, crawl continues)\n")
        return false
      end
      write!(path, body)
      @fetched += 1
      true
    end

    def get_with_retry(url)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure,
                                  headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, 404, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        case response.status
        when 200 then response.body.to_s.b
        when 404 then nil
        else raise RetriableFailure, "HTTP #{response.status} for #{url}"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Never escape get_with_retry.
    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    def write!(path, body)
      File.binwrite("#{path}.tmp", body.b)
      File.rename("#{path}.tmp", path)
    end

    def write_state!(books)
      state = { "manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
                "fetched_at" => Time.now.utc.iso8601, "books" => books, "fetched" => @fetched,
                "cached" => @cached, "fallbacks" => @fallbacks, "missing" => @missing }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end
  end
end
