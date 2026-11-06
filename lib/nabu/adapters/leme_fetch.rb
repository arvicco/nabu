# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../version"
require_relative "source_read"

module Nabu
  module Adapters
    # The polite walk over LEME's TSpace collection (Lexicons of Early Modern
    # English, University of Toronto; handle 1807/99021) through the DSpace 7
    # REST API at utoronto.scholaris.ca/server/api. Three request shapes:
    #
    # 1. the discovery listing — /discover/search/objects scoped to the
    #    collection uuid, dsoType=ITEM, 100 per page, sorted by accession
    #    date; its searchResult.page says how many pages and how many items
    #    upstream advertises (314 at the 2026-11-05 census, four pages);
    # 2. per item, /core/items/<uuid>?embed=bundles/bitstreams — the item's
    #    Dublin Core metadata AND its bundle/bitstream inventory in one body,
    #    held verbatim at items/<handle suffix>.json;
    # 3. the item's ONE accepted bitstream's /content — the ORIGINAL-bundle
    #    file whose name ends ".xml" (exactly one per item at census), held at
    #    xml/<handle suffix>.xml and checked against the listed MD5 before it
    #    replaces anything.
    #
    # Unnamed ORIGINAL bitstreams (26 on 20 items at census: earlier or
    # duplicate uploads of the same XML) and the CC-LICENSE / LICENSE bundles
    # (DSpace's deposit furniture) are NEVER fetched; the held item JSON
    # records them, and the adapter's discovery accounting counts them.
    #
    # == Incremental posture
    #
    # The listing is read on every sync. An item JSON is re-fetched only when
    # the listed lastModified differs from the held one (state file
    # .leme-fetch.json) or the file is absent; an XML only when the held
    # bytes' MD5 differs from the bitstream's listed checksum. Nothing is
    # ever deleted: an item that leaves the listing keeps its held files
    # (no mass-deletion breaker is needed — there is no deletion).
    #
    # == Failures
    #
    # Each GET retries up to ATTEMPTS times with a growing pause. An item
    # still unreachable (or a body failing its MD5) is reported and retried
    # next sync; the sync proceeds with what landed. A listing that fails, or
    # names no item, aborts (Error) before anything is written.
    class LemeFetch
      class Error < Nabu::Error; end

      API = "https://utoronto.scholaris.ca/server/api"
      COLLECTION_HANDLE = "1807/99021"
      COLLECTION_UUID = "10df91bc-8c9e-4ce1-b291-f02ad5715538"
      ITEMS_DIR = "items"
      XML_DIR = "xml"
      STATE_FILE = ".leme-fetch.json"
      ACCEPTED_BUNDLE = "ORIGINAL"

      # const: listing page size (the API's own maximum is larger), not a corpus claim
      PAGE_SIZE = 100
      # const: crawl politeness pause, not a corpus claim
      DELAY = 1.0
      # const: retry ceiling, not a corpus claim
      ATTEMPTS = 4
      # const: listing pagination guard, not a corpus claim
      MAX_LIST_PAGES = 50

      USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; " \
                   "+https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)".freeze

      HANDLE = %r{\A1807/(\d+)\z}

      Result = Data.define(:sha, :advertised, :listed, :items_fetched, :xml_fetched, :held, :failed)

      def self.list_url(page)
        "#{API}/discover/search/objects?scope=#{COLLECTION_UUID}&dsoType=ITEM" \
          "&sort=dc.date.accessioned,ASC&page=#{page}&size=#{PAGE_SIZE}"
      end

      def self.item_url(uuid) = "#{API}/core/items/#{uuid}?embed=bundles/bitstreams"

      def self.content_url(bitstream_uuid) = "#{API}/core/bitstreams/#{bitstream_uuid}/content"

      def self.item_path(dir, key) = File.join(dir, ITEMS_DIR, "#{key}.json")

      def self.xml_path(dir, key) = File.join(dir, XML_DIR, "#{key}.xml")

      # The item's handle suffix ("125731" for 1807/125731) — the on-disk key.
      def self.key_for(handle)
        match = HANDLE.match(handle.to_s) or raise Error, "item handle outside 1807/: #{handle.inspect}"
        match[1]
      end

      # The ORIGINAL-bundle bitstreams of a held item JSON (embedded shape).
      def self.original_bitstreams(item)
        bundles = item.dig("_embedded", "bundles", "_embedded", "bundles") || []
        bundles.select { |b| b["name"] == ACCEPTED_BUNDLE }
               .flat_map { |b| b.dig("_embedded", "bitstreams", "_embedded", "bitstreams") || [] }
      end

      # The accepted bitstream: the one ORIGINAL file named *.xml. Raises
      # Error when there is none or more than one (a reshaped deposit).
      def self.accepted_bitstream(item)
        xml = original_bitstreams(item).select { |b| b["name"].to_s.downcase.end_with?(".xml") }
        unless xml.size == 1
          raise Error,
                "item #{item['handle']} carries #{xml.size} named .xml bitstreams (expected 1)"
        end

        xml.first
      end

      def self.sync!(dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
        new(dir: dir, http: http, delay: delay, progress: progress).sync!
      end

      def initialize(dir:, http: ZipFetch.default_http, delay: DELAY, progress: nil)
        @dir = dir
        @http = http
        @delay = delay
        @progress = progress
      end

      def sync!
        advertised, rows = listed_items
        FileUtils.mkdir_p(@dir)
        state = read_state
        counts = { items: 0, xml: 0 }
        failed = []
        rows.each do |row|
          sync_item(row, state, counts)
        rescue Error => e
          failed << row[:handle]
          @progress&.call("#{row[:handle]}: unreachable this sync (#{e.message})\n")
        end
        write_state(state)
        held = rows.count { |row| held?(row[:key]) }
        raise Error, "no item held after the walk (#{failed.first(3).join(', ')})" if held.zero?

        Result.new(sha: tree_sha, advertised: advertised, listed: rows.size, items_fetched: counts[:items],
                   xml_fetched: counts[:xml], held: held, failed: failed)
      end

      private

      # [advertised total, item rows] over every listing page, deduplicated
      # by uuid in listing order.
      def listed_items
        rows = {}
        advertised = nil
        page = 0
        total_pages = 1
        while page < total_pages
          body = parse_json(get(self.class.list_url(page)).body, what: "listing page #{page}")
          result = body.dig("_embedded", "searchResult") or raise Error, "listing page #{page} carries no searchResult"
          paging = result["page"] || {}
          total_pages = Integer(paging["totalPages"] || 0, exception: false) || 0
          advertised = Integer(paging["totalElements"] || 0, exception: false)
          if total_pages > MAX_LIST_PAGES
            raise Error,
                  "listing reports #{total_pages} pages (over the #{MAX_LIST_PAGES} guard)"
          end

          (result.dig("_embedded", "objects") || []).each do |object|
            item = object.dig("_embedded", "indexableObject")
            row = item_row(item) or next
            rows[row[:uuid]] ||= row
          end
          page += 1
        end
        raise Error, "the listing names no item (collection #{COLLECTION_HANDLE} reshaped?)" if rows.empty?

        [advertised, rows.values]
      end

      def item_row(item)
        return nil unless item.is_a?(Hash) && item["type"] == "item" && item["uuid"].is_a?(String)

        { uuid: item["uuid"], handle: item["handle"].to_s, key: self.class.key_for(item["handle"]),
          modified: item["lastModified"].to_s }
      end

      def sync_item(row, state, counts)
        held = state[row[:key]] || {}
        path = self.class.item_path(@dir, row[:key])
        if !File.file?(path) || held["modified"] != row[:modified]
          body = get(self.class.item_url(row[:uuid])).body.to_s.b
          parse_json(body, what: "item #{row[:handle]}")
          write_atomically(path, body)
          counts[:items] += 1
        end
        bitstream = self.class.accepted_bitstream(parse_json(held_text(path), what: "item #{row[:handle]}"))
        fetch_xml(row, bitstream, counts)
        state[row[:key]] = { "handle" => row[:handle], "uuid" => row[:uuid], "modified" => row[:modified],
                             "bitstream" => bitstream["uuid"], "md5" => md5_of(bitstream) }
      end

      def fetch_xml(row, bitstream, counts)
        xml = self.class.xml_path(@dir, row[:key])
        want = md5_of(bitstream)
        return if File.file?(xml) && Digest::MD5.file(xml).hexdigest == want

        body = get(self.class.content_url(bitstream["uuid"])).body.to_s.b
        got = Digest::MD5.hexdigest(body)
        raise Error, "bitstream #{bitstream['uuid']} MD5 #{got} != listed #{want}" if want && got != want

        write_atomically(xml, body)
        counts[:xml] += 1
      end

      def md5_of(bitstream)
        sum = bitstream["checkSum"] || {}
        sum["checkSumAlgorithm"] == "MD5" ? sum["value"].to_s.downcase : nil
      end

      def held?(key) = File.file?(self.class.item_path(@dir, key)) && File.file?(self.class.xml_path(@dir, key))

      def get(url)
        attempt = 0
        begin
          attempt += 1
          sleep(@delay * attempt * attempt) if @delay.positive?
          @progress&.call("GET #{url}\n") if attempt == 1
          response, = RedirectFollow.get(url, http: @http, error: Error,
                                              headers: { "User-Agent" => USER_AGENT, "Accept" => "application/json" })
          response
        rescue Error
          raise if attempt >= ATTEMPTS

          retry
        end
      end

      def parse_json(body, what:)
        data = JSON.parse(body.to_s)
        raise Error, "#{what} is not a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise Error, "#{what} is not JSON: #{e.message}"
      end

      def write_atomically(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.part", body)
        File.rename("#{path}.part", path)
      end

      def state_path = File.join(@dir, STATE_FILE)

      def read_state
        return {} unless File.file?(state_path)

        data = JSON.parse(held_text(state_path))
        data.is_a?(Hash) ? (data["items"] || {}) : {}
      rescue JSON::ParserError, Error
        {}
      end

      # A held file's text through the encoding belt; bad bytes are this
      # walk's Error (the item is re-fetched / the state rebuilt).
      def held_text(path)
        SourceRead.utf8_file(path, label: "leme fetch")
      rescue Nabu::ParseError => e
        raise Error, e.message
      end

      def write_state(state)
        write_atomically(state_path, JSON.pretty_generate({ "items" => state.sort.to_h }))
      end

      # The tree's identity: sha256 over every held item JSON and XML
      # (relative path + body sha), in path order. The state file is
      # bookkeeping, not content — excluded.
      def tree_sha
        files = Dir.glob(File.join(@dir, "{#{ITEMS_DIR},#{XML_DIR}}", "*")).select { |p| File.file?(p) }
        rows = files.reject { |p| p.end_with?(".part") }.map do |p|
          "#{p.delete_prefix("#{@dir}/")}\t#{Digest::SHA256.file(p).hexdigest}"
        end
        Digest::SHA256.hexdigest(rows.sort.join("\n"))
      end
    end
  end
end
