# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # The TEXT-COLUMN projection of a Hugging Face dataset, fetched page by
  # page through the datasets-server /rows API (P153; first consumer the
  # BDRC Tibetan transcription releases). Built for datasets whose parquet
  # shards embed page IMAGES beside the text: BDRC's three releases are
  # 17.5 GB of parquet, almost all of it image bytes, around ~0.3 GB of
  # Unicode transcription. The parquet shards are never downloaded.
  #
  # == Why images CANNOT be pulled
  #
  # The fetch issues exactly three kinds of GET, and no code path builds
  # any other URL:
  #
  #   1. https://huggingface.co/api/datasets/<repo> — the revision (sha);
  #   2. https://datasets-server.huggingface.co/rows?… — one JSON page of
  #      rows, in which an Image feature is only a signed asset URL (the
  #      "src" of the cell), never bytes;
  #   3. https://huggingface.co/datasets/<repo>/resolve/<sha>/<sidecar> —
  #      the small text files the caller names (the dataset card).
  #
  # Every cell whose FEATURE is an Image/Audio type is deleted from the row
  # before anything is staged, so not even the asset URL reaches disk; the
  # test suite asserts no asset or parquet URL is ever requested.
  #
  # == Integrity
  #
  # Every rows page carries an X-Revision header; a page answering for a
  # revision other than the one the API reported at the start aborts the
  # fetch (upstream pushed mid-crawl: the next run starts clean on the new
  # revision). A row whose KEPT cell the API truncated (truncated_cells)
  # aborts too — a partial transcription must never pass for a page.
  #
  # == Pacing, resume, retention
  #
  # One sequential request per +delay+ seconds; HTTP 429 and 5xx retry with
  # exponential back-off (honouring Retry-After) up to +max_attempts+.
  # Pages stage under <dir>/.rows-staging/ (keyed by revision), so an
  # interrupted crawl resumes at the page grain. The house retention
  # contract holds: prepare! downloads and groups with the live tree
  # untouched; the caller's guard sees the doomed documents; complete!
  # attics them (GitFetch manifest shape), lands the regrouped tree, the
  # sidecars and the state file, and clears the staging.
  #
  # The caller decides the document grain: +document_path+ maps a row to
  # the workdir-relative file it belongs to (nil = no home: counted in
  # +unkeyed+, never staged), +sort_key+ orders each file's rows. Files are
  # JSON Lines, one row per line, keys in upstream column order.
  class HfRowsFetch
    class Error < Nabu::Error; end

    API_BASE = "https://huggingface.co/api/datasets"
    ROWS_URL = "https://datasets-server.huggingface.co/rows"
    RESOLVE_BASE = "https://huggingface.co/datasets"
    STATE_FILE = ".hf-rows-fetch.json"
    STAGING_DIR = ".rows-staging"

    # const: the datasets-server /rows page cap (API maximum), not a corpus count
    PAGE_LENGTH = 100
    # const: crawl politeness pause between requests, not a corpus claim
    DELAY = 1.0
    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 8
    # const: back-off ceiling in seconds, not a corpus claim
    BACKOFF_CAP = 300
    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [429, 500, 502, 503, 504].freeze
    # const: the datasets-library feature types that carry media, not a corpus claim
    MEDIA_TYPES = %w[Image Audio Video Pdf].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                 "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:revision, :sha, :rows, :documents, :unkeyed, :atticked, :not_modified)

    def self.sync!(repo:, dir:, attic_dir:, document_path:, sort_key:, guard: nil, **)
      fetch = new(repo: repo, dir: dir, attic_dir: attic_dir, document_path: document_path,
                  sort_key: sort_key, **)
      fetch.prepare!
      guard&.call(fetch.doomed_paths) unless fetch.not_modified?
      fetch.complete!
      fetch.result
    end

    def initialize(repo:, dir:, attic_dir:, document_path:, sort_key:, sidecars: [], config: "default",
                   split: "train", page_length: PAGE_LENGTH, delay: DELAY, max_attempts: MAX_ATTEMPTS,
                   http: ZipFetch.default_http, progress: nil, sleeper: ->(seconds) { Kernel.sleep(seconds) })
      @repo = repo
      @dir = dir
      @attic_dir = attic_dir
      @document_path = document_path
      @sort_key = sort_key
      @sidecars = sidecars
      @config = config
      @split = split
      @page_length = page_length
      @delay = delay
      @max_attempts = max_attempts
      @http = http
      @progress = progress
      @sleeper = sleeper
      @requests = 0
      @doomed = []
      @atticked = []
      @unkeyed = 0
      @rows = 0
      @not_modified = false
    end

    attr_reader :atticked

    def not_modified? = @not_modified

    def doomed_paths = @doomed.map { |rel| File.join(@dir, rel) }

    def result
      Result.new(revision: @revision, sha: @sha, rows: @rows, documents: @documents, unkeyed: @unkeyed,
                 atticked: @atticked, not_modified: @not_modified)
    end

    # Phase 1 — revision, every rows page, the regrouped staged tree; the
    # live tree untouched.
    def prepare!
      @revision = fetch_revision
      if unchanged?
        @not_modified = true
        state = read_state
        @sha = state["sha256"]
        @rows = state["rows"]
        @documents = state["documents"]
        return
      end

      reset_staging!
      crawl_pages!
      regroup!
      @doomed = live_documents - staged_documents
    end

    # Phase 2 — attic the vanished, land the tree, sidecars, state.
    def complete!
      return if @not_modified

      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      land_tree!
      @sidecars.each { |name| land_sidecar!(name) }
      @documents = staged_documents.size
      @sha = aggregate_sha
      write_state!
      FileUtils.rm_rf(staging_root)
    end

    private

    # -- revision -----------------------------------------------------------------

    def fetch_revision
      body = get_with_retry("#{API_BASE}/#{@repo}")
      JSON.parse(body).fetch("sha")
    rescue JSON::ParserError, KeyError => e
      raise Error, "#{@repo}: the dataset API answered without a revision sha (#{e.message})"
    end

    def unchanged?
      state = read_state
      return false unless state["revision"] == @revision && state["repo"] == @repo

      Array(state["files"]).all? { |rel| File.file?(File.join(@dir, rel)) }
    end

    # -- the page crawl -----------------------------------------------------------

    def staging_root = File.join(@dir, STAGING_DIR)
    def pages_dir = File.join(staging_root, "pages")
    def tree_dir = File.join(staging_root, "tree")
    def page_file(offset) = File.join(pages_dir, format("%09d.jsonl", offset))

    # Staged pages survive an interruption only for the SAME revision.
    def reset_staging!
      marker = File.join(staging_root, "revision")
      FileUtils.rm_rf(staging_root) unless File.file?(marker) && File.read(marker).strip == @revision
      FileUtils.mkdir_p(pages_dir)
      File.write(marker, @revision)
      FileUtils.rm_rf(tree_dir)
    end

    def crawl_pages!
      total = staged_total
      offset = 0
      while total.nil? || offset < total
        unless File.file?(page_file(offset))
          page = get_page(offset)
          total ||= page.fetch("num_rows_total")
          stage_page!(offset, page)
          File.write(File.join(staging_root, "num_rows_total"), total.to_s)
          report(offset, total)
        end
        offset += @page_length
      end
      @rows = total
    end

    def staged_total
      path = File.join(staging_root, "num_rows_total")
      File.file?(path) ? Integer(File.read(path).strip) : nil
    end

    def get_page(offset)
      query = URI.encode_www_form(dataset: @repo, config: @config, split: @split, offset: offset,
                                  length: @page_length)
      body, headers = get_with_retry("#{ROWS_URL}?#{query}", with_headers: true)
      served = headers["x-revision"]
      if served && served != @revision
        raise Error, "#{@repo}: rows page #{offset} answers for revision #{served}, not #{@revision} — " \
                     "upstream moved mid-fetch; re-run to start clean on the new revision"
      end
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "#{@repo}: rows page #{offset} is not JSON (#{e.message})"
    end

    def stage_page!(offset, page)
      media = page.fetch("features").filter_map do |feature|
        feature["name"] if MEDIA_TYPES.include?(feature.dig("type", "_type"))
      end
      lines = page.fetch("rows").map do |entry|
        truncated = Array(entry["truncated_cells"]) - media
        unless truncated.empty?
          raise Error, "#{@repo}: row #{entry['row_idx']} came back with truncated cell(s) " \
                       "#{truncated.join(', ')} — a partial text never passes for a page"
        end
        JSON.generate(entry.fetch("row").except(*media))
      end
      tmp = "#{page_file(offset)}.tmp"
      File.write(tmp, lines.map { |line| "#{line}\n" }.join)
      File.rename(tmp, page_file(offset))
    end

    def report(offset, total)
      return unless (offset % (@page_length * 20)).zero?

      @progress&.call("#{@repo}: rows #{offset}/#{total}…\n")
    end

    # -- regrouping ---------------------------------------------------------------

    def regroup!
      FileUtils.mkdir_p(tree_dir)
      handles = {}
      Dir.glob(File.join(pages_dir, "*.jsonl")).each do |page|
        File.foreach(page) do |line|
          row = JSON.parse(line)
          rel = @document_path.call(row)
          if rel.nil?
            @unkeyed += 1
            next
          end
          target = File.join(tree_dir, rel)
          handles[rel] ||= begin
            FileUtils.mkdir_p(File.dirname(target))
            File.open(target, "w")
          end
          handles[rel].write(line)
        end
      end
      handles.each_value(&:close)
      handles.each_key { |rel| sort_file!(File.join(tree_dir, rel)) }
    end

    def sort_file!(path)
      rows = File.readlines(path).map { |line| [JSON.parse(line), line] }
      File.write(path, rows.sort_by { |row, _line| @sort_key.call(row) }.map(&:last).join)
    end

    def staged_documents
      @staged_documents ||= Dir.glob("**/*.jsonl", base: tree_dir).sort
    end

    # Live document files: every .jsonl under dir outside dot directories.
    def live_documents
      return [] unless Dir.exist?(@dir)

      Dir.glob("**/*.jsonl", base: @dir).sort
    end

    # -- landing ------------------------------------------------------------------

    def land_tree!
      staged_documents.each do |rel|
        target = File.join(@dir, rel)
        FileUtils.mkdir_p(File.dirname(target))
        File.rename(File.join(tree_dir, rel), target)
      end
    end

    def land_sidecar!(name)
      body = get_with_retry("#{RESOLVE_BASE}/#{@repo}/resolve/#{@revision}/#{name}")
      target = File.join(@dir, name)
      FileUtils.mkdir_p(File.dirname(target))
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
    end

    def aggregate_sha
      lines = staged_documents.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
      Digest::SHA256.hexdigest("#{@revision}\n#{lines.join("\n")}")
    end

    def read_state
      path = File.join(@dir, STATE_FILE)
      File.file?(path) ? JSON.parse(File.read(path)) : {}
    rescue JSON::ParserError
      {}
    end

    def write_state!
      state = { "repo" => @repo, "revision" => @revision, "sha256" => @sha, "rows" => @rows,
                "documents" => @documents, "unkeyed" => @unkeyed, "fetched_at" => Time.now.utc.iso8601,
                "url" => "#{ROWS_URL}?dataset=#{@repo}", "last_modified" => nil,
                "files" => staged_documents }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    # -- retention ----------------------------------------------------------------

    def attic_doomed!
      @doomed.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next unless File.file?(source)
        next if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
      record_attic_manifest! unless @atticked.empty?
    end

    def record_attic_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      pin = read_state["revision"] || "pre-#{@revision}"
      @atticked.each { |rel| manifest[rel] ||= pin }
      FileUtils.mkdir_p(@attic_dir)
      File.write(path, JSON.pretty_generate(manifest))
    end

    # -- HTTP -----------------------------------------------------------------------

    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def get_with_retry(url, with_headers: false)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure, headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        raise RetriableFailure, "HTTP #{response.status} for #{url}" unless response.status == 200

        body = response.body.to_s.dup.force_encoding(Encoding::UTF_8)
        with_headers ? [body, response.headers] : body
      rescue RetriableFailure => e
        raise Error, "#{e.message} (after #{attempt} attempt(s))" if attempt >= @max_attempts

        @sleeper.call(backoff(attempt, response))
        retry
      end
    end

    def backoff(attempt, response)
      asked = response&.headers&.[]("retry-after").to_s
      return asked.to_i.clamp(0, BACKOFF_CAP) if asked.match?(/\A\d+\z/)

      [@delay.positive? ? @delay * (2**attempt) : 0, BACKOFF_CAP].min
    end

    def pause
      @sleeper.call(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end
  end
end
