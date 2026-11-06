# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "faraday"

module Nabu
  module Adapters
    # The paced per-find LIDO harvest for RuneS-DB (P160): one GET of
    # https://www.runesdb.de/lido/<id> per text-bearing find (613 at the
    # v1.0.0 census), landing <workdir>/lido/<id>.xml — upstream's bytes
    # verbatim, beside the zip's TEI tree (Runesdb.materialized_paths).
    #
    # == Pacing + resume
    #
    # Sequential, DELAY seconds between requests (1 s — ~613 requests ≈
    # 10–11 min plus response time on a first harvest). A record already
    # on disk is NOT re-fetched (resume at the file grain, the AIO/SEAL
    # posture): an interrupted harvest resumes where it stopped, and a
    # re-sync costs only what is missing. This matters beyond politeness:
    # every LIDO GET restamps the record's recordMetadataDate, so a refetch
    # would churn the canonical bytes without any upstream change.
    # Refreshing a revised record = deleting its file and re-syncing
    # (declared — the LIDO surface carries no revision field to compare).
    #
    # Never-delete: a record whose find left the deposit stays on disk
    # (inert — discovery reads LIDO only for discovered finds).
    #
    # == Failure taxonomy
    #
    # 5xx and transport failures retry MAX_ATTEMPTS times with backoff; a
    # 404 or a redirect (upstream 302s an unknown id to the site) or a 200
    # whose body is not this find's LIDO record is CENSUSED as missing and
    # the harvest continues; a SYSTEMIC miss rate (above 1 %, floor 5)
    # aborts with Error after the crawl (files landed so far stay — the
    # resume posture). Each write is tmp+rename.
    #
    # The ledger (lido/.lido-fetch.json) is deterministic — record count,
    # missing ids and an aggregate sha256 over the sorted (file, body-sha)
    # set, no timestamp — so a re-sync that fetches nothing leaves the tree
    # byte-identical.
    class RunesdbLidoFetch
      # Persistent HTTP failure or a systemic miss. Runesdb wraps it in
      # Nabu::FetchError.
      class Error < Nabu::Error; end

      URL = "https://www.runesdb.de/lido/%s"
      DIRNAME = "lido"
      STATE_FILE = ".lido-fetch.json"

      # Seconds between HTTP requests (sequential, polite — an academy host).
      # const: crawl politeness pause, not a corpus claim
      DELAY = 1.0

      # const: retry ceiling, not a corpus claim
      MAX_ATTEMPTS = 3

      # const: HTTP semantics, not a corpus claim
      RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

      # const: abort threshold, not a corpus claim
      MISSING_CAP_FRACTION = 0.01
      MISSING_CAP_FLOOR = 5

      USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; RuneS-DB LIDO under CC BY-SA 4.0; " \
                   "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

      Result = Data.define(:sha, :records, :fetched, :cached, :missing)

      def self.record_relpath(find_id) = File.join(DIRNAME, "#{find_id}.xml")

      def self.sync!(dir:, find_ids:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
        new(dir: dir, find_ids: find_ids, http: http, delay: delay, progress: progress).run!
      end

      def initialize(dir:, find_ids:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
        @dir = dir
        @find_ids = find_ids.map(&:to_s).uniq.sort_by { |id| Integer(id, 10) }
        @http = http
        @delay = delay
        @progress = progress
        @fetched = 0
        @cached = 0
        @missing = []
        @requests = 0
      end

      def run!
        FileUtils.mkdir_p(File.join(@dir, DIRNAME))
        @find_ids.each_with_index do |id, index|
          @progress&.call("RuneS-DB LIDO #{index + 1}/#{@find_ids.size} (find #{id})…\n") if (index % 50).zero?
          harvest_one!(id)
        end
        sha = aggregate_sha
        write_state!(sha)
        check_missing!
        Result.new(sha: sha, records: @find_ids.size, fetched: @fetched, cached: @cached, missing: @missing)
      end

      private

      def harvest_one!(id)
        target = File.join(@dir, self.class.record_relpath(id))
        return @cached += 1 if File.file?(target)

        body = get_with_retry(format(URL, id), id: id)
        if body.nil? || !lido_record?(body, id)
          @missing << id
          @progress&.call("RuneS-DB LIDO find #{id}: no LIDO record (censused, harvest continues)\n")
          return
        end
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
        @fetched += 1
      end

      # A well-formed LIDO document whose recordID is this find — anything
      # else (a maintenance page, a mis-routed record) is not landed.
      def lido_record?(body, id)
        xml = Nokogiri::XML(body, &:strict)
        record = xml.at_xpath("/lido:lido/lido:administrativeMetadata/lido:recordWrap/lido:recordID",
                              RunesdbLido::NS)
        record&.text.to_s.strip == id
      rescue Nokogiri::XML::SyntaxError
        false
      end

      # The body on 200; nil on 404 or a redirect (no record); retries
      # 5xx/transport failures, raising Error when they persist.
      def get_with_retry(url, id:)
        attempt = 0
        begin
          attempt += 1
          pause
          response = begin
            @http.get(url, nil, { "User-Agent" => USER_AGENT })
          rescue Faraday::Error => e
            raise RetriableFailure, "#{e.class}: #{e.message} for #{url}"
          end
          status = response.status
          return response.body.to_s.b if status == 200
          return nil if status == 404 || (300..399).cover?(status)
          raise RetriableFailure, "HTTP #{status} for #{url}" if RETRIABLE_STATUSES.include?(status)

          raise Error, "HTTP #{status} for #{url} (find #{id})"
        rescue RetriableFailure => e
          raise Error, "#{e.message} (after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

          sleep(@delay * (2**attempt)) if @delay.positive?
          retry
        end
      end

      # Internal retry marker; never escapes get_with_retry.
      class RetriableFailure < StandardError; end
      private_constant :RetriableFailure

      def pause
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
      end

      def check_missing!
        cap = [(@find_ids.size * MISSING_CAP_FRACTION).ceil, MISSING_CAP_FLOOR].max
        return if @missing.size <= cap

        raise Error, "#{@missing.size} of #{@find_ids.size} finds have no LIDO record — a systemic miss, " \
                     "not holes: the URL scheme moved upstream (first: #{@missing.first(3).join(', ')})"
      end

      def record_files
        @find_ids.map { |id| self.class.record_relpath(id) }.select { |rel| File.file?(File.join(@dir, rel)) }
      end

      def aggregate_sha
        lines = record_files.sort.map { |rel| "#{rel}\0#{Digest::SHA256.file(File.join(@dir, rel)).hexdigest}" }
        Digest::SHA256.hexdigest(lines.join("\n"))
      end

      def write_state!(sha)
        state = { "url" => URL, "records" => @find_ids.size, "held" => record_files.size,
                  "missing" => @missing, "sha256" => sha }
        path = File.join(@dir, DIRNAME, STATE_FILE)
        body = "#{JSON.pretty_generate(state)}\n"
        unchanged = File.file?(path) && SourceRead.utf8_file(path, label: "runesdb lido ledger") == body
        File.write(path, body) unless unchanged
      end
    end
  end
end
