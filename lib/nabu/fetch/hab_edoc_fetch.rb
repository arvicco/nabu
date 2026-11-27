# frozen_string_literal: true

require "digest"
require "erb"
require "fileutils"
require "json"
require "time"

require_relative "../redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "../version"

module Nabu
  # Polite crawl of the Herzog August Bibliothek's digital editions
  # (diglib.hab.de/edoc/; architecture §8) — the ScriptaBulgaricaFetch
  # mold (an HTML-crawl sibling, deliberately mirrored, not extracted).
  #
  # Upstream has no complete list: the site's sitemap.xml names
  # ed000001–ed000229 only, the HAB's "Digitale Editionen" page links 54
  # editions, and editions run to ed000284 (census 2026-11-27). The ids
  # are sequential, so the manifest is the id walk itself: GET
  # ed<NNNNNN>/mets.xml from 1 upward, through the last id the census
  # knows, then on until MISS_RUN consecutive misses (a 404, or a body
  # that is not METS — some ids answer with a portal page). Then, for
  # every edition the caller admits, each transcript its METS lists
  # (+want+ decides) is fetched unless already on disk — resume at the
  # file grain; a 404 is recorded in the state file's "missing" map (a
  # listed-but-unserved file, censused, never a hole).
  #
  # Mirror layout = upstream's own paths: <workdir>/<id>/mets.xml and
  # <workdir>/<id>/<href as the METS gives it>. Retention: METS of an id
  # that stopped answering and transcripts no longer listed are doomed —
  # the caller's breaker runs on them first, then they go to the attic.
  # robots.txt (re-read 2026-11-27) disallows /wdb/, /rights/, /rules/,
  # /images/, /cache/ — never /edoc/.
  class HabEdocFetch
    class Error < Nabu::Error; end

    BASE_URL = "https://diglib.hab.de/edoc"
    STATE_FILE = ".hab-edoc-fetch.json"
    METS_FILENAME = "mets.xml"
    EDITION_ID = /\Aed\d{6}\z/

    # const: the last edition id the 2026-11-27 census found answering
    # (ed000282–284 are placeholder copies of ed000280)
    LAST_KNOWN_ID = 284
    # const: walk terminator past LAST_KNOWN_ID, not a corpus claim (the
    # census saw no gap longer than 4 ids: ed000262–ed000265)
    MISS_RUN = 20
    # const: crawl politeness pause, not a corpus claim (≤ 1 request/s)
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3
    # const: HTTP semantics, not a corpus claim (the census met one 503)
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze
    # const: HTTP semantics — every 4xx is answered, never retried
    CLIENT_STATUSES = (400..499).to_a.freeze

    USER_AGENT = "nabu-research-library/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu)".freeze

    Result = Data.define(:sha, :atticked, :editions, :fetched, :cached, :missing)

    def self.edition_id(number) = format("ed%06d", number)

    def self.mets_url(id) = "#{BASE_URL}/#{id}/#{METS_FILENAME}"

    def self.file_url(id, href)
      "#{BASE_URL}/#{id}/#{href.split('/').map { |part| ERB::Util.url_encode(part) }.join('/')}"
    end

    # +want+ (id, href) → true for every transcript to hold (the adapter's
    # admitted editions and files).
    def self.sync!(dir:, attic_dir:, want:, http: ZipFetch.default_http, delay: DELAY,
                   progress: nil, guard: nil, last_known: LAST_KNOWN_ID)
      fetch = new(dir: dir, attic_dir: attic_dir, want: want, http: http, delay: delay,
                  progress: progress, last_known: last_known)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, atticked: fetch.atticked, editions: fetch.editions,
                 fetched: fetch.fetched, cached: fetch.cached, missing: fetch.missing)
    end

    def self.state(dir)
      path = File.join(dir, STATE_FILE)
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    rescue JSON::ParserError
      {}
    end

    def initialize(dir:, attic_dir:, want:, http: ZipFetch.default_http, delay: DELAY,
                   progress: nil, last_known: LAST_KNOWN_ID)
      @dir = dir
      @attic_dir = attic_dir
      @want = want
      @http = http
      @delay = delay
      @progress = progress
      @last_known = last_known
      @mets = {}
      @doomed = []
      @atticked = []
      @fetched = 0
      @cached = 0
      @requests = 0
      @missing = {}
    end

    attr_reader :atticked, :sha, :fetched, :cached, :missing

    def editions = @mets.size

    # Phase 1 — the METS walk, held in memory; live tree untouched.
    def prepare!
      number = 0
      misses = 0
      loop do
        number += 1
        break if number > @last_known && misses >= MISS_RUN

        id = self.class.edition_id(number)
        @progress&.call("HAB edoc METS #{id}…\n") if (number % 25).zero?
        body = get(self.class.mets_url(id))
        if body&.include?("<mets:mets") || body&.match?(/<mets[\s>]/)
          @mets[id] = body
          misses = 0
        else
          misses += 1
        end
      end
      raise Error, "no edition answered with a METS file — the URL scheme moved upstream" if @mets.empty?

      @doomed = doomed_relpaths
    end

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    # Phase 2 — attic the vanished, land the METS, crawl missing transcripts.
    def complete!
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      @mets.each { |id, body| write!("#{id}/#{METS_FILENAME}", body) }
      crawl_transcripts!
      @sha = aggregate_sha
      write_state!
    end

    private

    def wanted
      @wanted ||= @mets.flat_map do |id, body|
        Adapters::HabEdocMets.new(body).transcripts.map(&:href)
                             .select { |href| safe?(href) && @want.call(id, href) }
                             .map { |href| [id, href] }
      end
    end

    def safe?(href) = !href.start_with?("/") && !href.split("/").include?("..")

    def crawl_transcripts!
      wanted.each_with_index do |(id, href), index|
        rel = "#{id}/#{href}"
        if File.file?(File.join(@dir, rel))
          @cached += 1
          next
        end

        @progress&.call("HAB edoc transcript #{index + 1}/#{wanted.size} (#{rel})…\n") if (index % 25).zero?
        body = get(self.class.file_url(id, href))
        if body.nil?
          (@missing[id] ||= []) << href
          next
        end
        write!(rel, body)
        @fetched += 1
      end
    end

    # The body on 200, nil on 404; retriable statuses back off and retry;
    # anything else (403, 429, …) aborts — a wall is never crawled past.
    def get(url)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure,
                                  headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, *CLIENT_STATUSES, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        case response.status
        when 200 then response.body.to_s
        when 404 then nil
        when *RETRIABLE_STATUSES then raise RetriableFailure, "HTTP #{response.status} for #{url}"
        else raise Error, "HTTP #{response.status} for #{url} — a wall (403/429/…): the crawl stops here"
        end
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    def write!(rel, body)
      target = File.join(@dir, rel)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    # Every mirrored file: <id>/mets.xml and the transcripts beneath.
    def held_relpaths
      return [] unless Dir.exist?(@dir)

      Dir.children(@dir).grep(EDITION_ID).sort.flat_map do |id|
        Dir.glob("**/*.xml", base: File.join(@dir, id)).sort.map { |rel| "#{id}/#{rel}" }
      end
    end

    def keep_set
      Set.new(@mets.keys.map { |id| "#{id}/#{METS_FILENAME}" } + wanted.map { |id, href| "#{id}/#{href}" })
    end

    def doomed_relpaths
      keep = keep_set
      held_relpaths.reject { |rel| keep.include?(rel) }
    end

    def aggregate_sha
      lines = held_relpaths.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      state = { "url" => BASE_URL, "fetched_at" => Time.now.utc.iso8601, "sha256" => @sha,
                "editions" => @mets.keys.sort, "transcripts" => wanted.size,
                "fetched" => @fetched, "cached" => @cached,
                "missing" => @missing.transform_values(&:sort).sort.to_h }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    def attic_doomed!
      @doomed.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next if !File.file?(source) || File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
      record_attic_manifest! unless @atticked.empty?
    end

    def record_attic_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      pin = self.class.state(@dir)["sha256"] || "pre-#{Time.now.utc.iso8601}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
