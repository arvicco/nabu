# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"

require_relative "../redirect_follow"
require_relative "../fetch/zip_fetch"
require_relative "../version"
require_relative "hrcak_record"

module Nabu
  module Adapters
    # The polite harvest of Colloquia Maruliana from Hrčak, the Croatian
    # journal portal (hrcak.srce.hr). Two request shapes:
    #
    # 1. OAI-PMH ListRecords over the journal's set (journal:43) in two
    #    metadata formats — oai_openaire (titles, creators, issue date,
    #    volume/issue/pages, resource type, the record's own licence
    #    condition, and every full-text PDF as an oaire:file URL) and oai_dc
    #    (the journal's rights statement, carried on every record). 100
    #    records per response, resumptionToken paging; the final response
    #    carries no token. Each record is held verbatim on its own at
    #    records/<hrcak-id>.<prefix>.xml (the <record> element re-rooted as a
    #    standalone document — the response envelope and the page split are
    #    harvest furniture, never content). A record whose bytes did not
    #    change is not rewritten.
    # 2. GET https://hrcak.srce.hr/file/<id> — each full-text PDF a record
    #    lists, held at files/<id>.pdf. Fetched only when absent (Hrčak file
    #    ids are permanent; a revised PDF is a new id). The body must be a
    #    PDF (%PDF magic): anything else — the human-verification page the
    #    portal served before 2026-11 (HTTP 418), an HTML error — is a
    #    failure for that file, reported and retried next sync.
    #
    # Records the licence gate excludes (HrcakRecord#license_class nil —
    # an in-copyright statement or an unknown licence) have their XML held
    # (the census needs it) but their PDFs are NEVER downloaded.
    #
    # == Politeness
    #
    # Serial, DELAY seconds before every request, a named User-Agent. The
    # portal rate-limits bursts with HTTP 429 and no Retry-After (seen
    # 2026-11-25 after ~150 requests in ~15 minutes at ~1.2 s pacing): a
    # 429 backs off RATE_LIMIT_PAUSE × attempt seconds and retries, up to
    # ATTEMPTS; any other failure retries with a short growing pause.
    #
    # == Never deletes
    #
    # A record that leaves the set keeps its held files (OAI deletedRecord
    # is "no" for this repository: the portal does not announce deletions),
    # so no mass-deletion breaker is needed. A harvest that fails or yields
    # no record aborts (Error) before anything is written.
    class HrcakMarulanaFetch
      class Error < Nabu::Error; end

      OAI_BASE = "https://hrcak.srce.hr/oai/"
      SET = "journal:43"
      PREFIXES = %w[oai_openaire oai_dc].freeze
      FILE_URL = %r{\Ahttps://hrcak\.srce\.hr/file/(\d+)\z}
      RECORDS_DIR = "records"
      FILES_DIR = "files"

      # const: crawl politeness pause, not a corpus claim
      DELAY = 1.5
      # const: retry ceiling, not a corpus claim
      ATTEMPTS = 5
      # const: the 429 back-off unit in seconds (no Retry-After is sent), not a corpus claim
      RATE_LIMIT_PAUSE = 60
      # const: resumption guard (681 records = 7 pages at the 2026-11-25 census), not a corpus claim
      MAX_PAGES = 100

      USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                   "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

      OAI_NS = { "oai" => "http://www.openarchives.org/OAI/2.0/" }.freeze

      Result = Data.define(:sha, :records, :records_written, :pdfs_fetched, :pdfs_held, :gated, :failed)

      def self.list_url(prefix) = "#{OAI_BASE}?verb=ListRecords&metadataPrefix=#{prefix}&set=#{SET}"

      def self.resume_url(token) = "#{OAI_BASE}?verb=ListRecords&resumptionToken=#{token}"

      def self.record_path(dir, id, prefix) = File.join(dir, RECORDS_DIR, "#{id}.#{prefix}.xml")

      def self.pdf_path(dir, file_id) = File.join(dir, FILES_DIR, "#{file_id}.pdf")

      # The Hrčak file id of an oaire:file URL; raises Error on any other
      # shape (a reshaped portal, never a guess).
      def self.file_id(url)
        match = FILE_URL.match(url.to_s.strip) or raise Error, "unrecognized full-text URL #{url.inspect}"
        match[1]
      end

      def self.sync!(dir:, http: ZipFetch.default_http, delay: DELAY, rate_limit_pause: RATE_LIMIT_PAUSE,
                     progress: nil)
        new(dir: dir, http: http, delay: delay, rate_limit_pause: rate_limit_pause, progress: progress).sync!
      end

      def initialize(dir:, http: ZipFetch.default_http, delay: DELAY, rate_limit_pause: RATE_LIMIT_PAUSE,
                     progress: nil)
        @dir = dir
        @http = http
        @delay = delay
        @rate_limit_pause = rate_limit_pause
        @progress = progress
      end

      def sync!
        harvested = PREFIXES.to_h { |prefix| [prefix, harvest(prefix)] }
        openaire = harvested.fetch("oai_openaire")
        raise Error, "the #{SET} harvest yielded no record" if openaire.empty?

        written = harvested.sum { |prefix, records| records.count { |id, xml| record_rewritten?(id, prefix, xml) } }
        counts = { fetched: 0, gated: 0 }
        failed = []
        openaire.each do |id, xml|
          fetch_pdfs(id, xml, counts, failed)
        end
        Result.new(sha: tree_sha, records: openaire.size, records_written: written, pdfs_fetched: counts[:fetched],
                   pdfs_held: Dir.glob(File.join(@dir, FILES_DIR, "*.pdf")).size, gated: counts[:gated],
                   failed: failed)
      end

      private

      # { hrcak id => standalone record XML } over every response page.
      def harvest(prefix)
        records = {}
        url = self.class.list_url(prefix)
        MAX_PAGES.times do
          doc = Nokogiri::XML(get(url).body.to_s)
          error = doc.at_xpath("//oai:error", OAI_NS)
          raise Error, "OAI error #{error['code']}: #{error.text.strip}" if error

          doc.xpath("//oai:ListRecords/oai:record", OAI_NS).each do |record|
            id = record.at_xpath("oai:header/oai:identifier", OAI_NS).text.strip.split(":").last
            records[id] = standalone(record)
          end
          token = doc.at_xpath("//oai:resumptionToken", OAI_NS)&.text.to_s.strip
          return records if token.empty?

          url = self.class.resume_url(token)
        end
        raise Error, "#{prefix} harvest ran past #{MAX_PAGES} pages"
      end

      def standalone(record)
        doc = Nokogiri::XML::Document.new
        doc.encoding = "UTF-8"
        doc.root = record.dup
        doc.to_xml
      end

      def record_rewritten?(id, prefix, xml)
        path = self.class.record_path(@dir, id, prefix)
        return false if File.file?(path) && File.binread(path) == xml.b

        write_atomically(path, xml.b)
        true
      end

      def fetch_pdfs(id, xml, counts, failed)
        record = HrcakRecord.new(openaire: xml)
        unless record.license_class
          counts[:gated] += 1
          return
        end

        record.files.each do |url|
          file_id = self.class.file_id(url)
          path = self.class.pdf_path(@dir, file_id)
          next if File.file?(path)

          body = get(url).body.to_s.b
          raise Error, "file #{file_id} is not a PDF (#{body[0, 40].inspect})" unless body.start_with?("%PDF")

          write_atomically(path, body)
          counts[:fetched] += 1
        rescue Error => e
          failed << "#{id}/#{file_id}"
          @progress&.call("record #{id}: file unreachable this sync (#{e.message})\n")
        end
      end

      # A 200 response, after up to ATTEMPTS tries: a 429 backs off
      # RATE_LIMIT_PAUSE × attempt, a 5xx/408/transport failure the short
      # growing pause; any other 4xx (the 418 challenge, a 404) is final.
      def get(url)
        attempt = 0
        loop do
          attempt += 1
          sleep(@delay) if @delay.positive?
          @progress&.call("GET #{url}\n") if attempt == 1
          response, failure = fetch_once(url)
          return response if response&.status == 200

          failure ||= "HTTP 429 for #{url}"
          raise Error, failure if attempt >= ATTEMPTS

          pause = response ? @rate_limit_pause * attempt : @delay * attempt * attempt
          sleep(pause) if pause.positive?
        end
      end

      # [response (200 or 429), nil] or [nil, failure message] for an
      # error worth another try.
      def fetch_once(url)
        response, = RedirectFollow.get(url, http: @http, error: Error, accept: [200, 429],
                                            headers: { "User-Agent" => USER_AGENT })
        [response, nil]
      rescue Error => e
        raise if e.message.start_with?("HTTP 4") && !e.message.start_with?("HTTP 408")

        [nil, e.message]
      end

      def write_atomically(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.part", body)
        File.rename("#{path}.part", path)
      end

      # The tree's identity: sha256 over every held record and PDF
      # (relative path + body sha), in path order.
      def tree_sha
        files = Dir.glob(File.join(@dir, "{#{RECORDS_DIR},#{FILES_DIR}}", "*")).select { |p| File.file?(p) }
        rows = files.reject { |p| p.end_with?(".part") }.map do |p|
          "#{p.delete_prefix("#{@dir}/")}\t#{Digest::SHA256.file(p).hexdigest}"
        end
        Digest::SHA256.hexdigest(rows.sort.join("\n"))
      end
    end
  end
end
