# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "uri"

require_relative "wikisource_han_parser"
require_relative "../redirect_follow"
require_relative "../wiki_fetch"
require_relative "../zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # The viet-wikisource adapter (P78-5): the Vietnamese classical shelf,
    # riding the SINITIC axis — deliberately no vietnamese axis (the P47-s4
    # survey ruling: Vietnam gets a shelf, not a desk). Everything here is
    # Literary Chinese (lzh) as written in Đại Việt; the vernacular chữ
    # Nôm corpus waits for a source that actually serves it.
    #
    # == The curated list (title-list scoping, censused 2026-08-18)
    #
    # Wikisource is an ocean; this shelf is per-work curation — PAGES names
    # every page fetched, nothing is crawled:
    #
    # - 大越史記全書 (Đại Việt sử ký toàn thư), COMPLETE from zh.wikisource:
    #   the index page's own tree is 卷首 (front matter) + 29 quyển —
    #   外紀卷之一…五, 本紀卷之一…十九, 續編卷之一…五 — as subpages
    #   "大越史記全書/<part>". The index page itself is a TOC, not text
    #   (never a document); its {{Textquality|50%}} is the wiki's own
    #   whole-work proofreading status. vi.wikisource's DVSKTT is
    #   quốc-ngữ-only — never used for the text.
    # - 平吳大誥 (Bình Ngô đại cáo) from vi.wikisource ("Bình Ngô đại cáo"):
    #   full chữ Hán in a two-column layout beside its Hán-Việt phiên âm —
    #   the original script is the passage text, the phiên âm rides as
    #   annotation (part of the same licensed page, honestly labeled).
    # - 諭諸裨將檄文 (Hịch tướng sĩ) from ZH.wikisource: vi.wikisource's
    #   "bản gốc" link for it is a redlink — the original script lives on
    #   zh.wikisource (censused 2026-08-18), so that is where we fetch it.
    #
    # == Grain
    #
    # Document = one wikisource page (one quyển / one showpiece): the quyển
    # is the work's own citation unit and the page is upstream's revision
    # unit, so document identity tracks upstream change detection. Passage =
    # one paragraph (prose mode) or one stanza (parallel-poem mode), the
    # units the pages' own blank-line structure draws. Ids come from the
    # curated table (dvsktt-ngoai-ky-1 … binh-ngo-dai-cao), never from
    # title mangling — the table IS the naming authority.
    #
    # Ext-B-heavy Nôm/rare-Han codepoints (䚟, the DVSKTT's variant forms)
    # ride as-is — display is not the adapter's problem.
    #
    # == Fetch (the WikiFetch mold, title-list shaped)
    #
    # One batched api.php revisions request per 50 curated titles per wiki
    # (2 requests total today), throttled and UA-identified; envelopes are
    # WikiFetch's per-page shape plus a "wiki" provenance key, filed by
    # curated id (pages/<id>.json). NON-DESTRUCTIVE by construction: the
    # fetch only ever adds or replaces single pages — a curated title
    # upstream stops serving is counted missing and its local file kept, so
    # no attic or deletion breaker is needed.
    class VietWikisource < Nabu::Adapter
      LANGUAGE = "lzh"
      STATE_FILE = ".wikisource-fetch.json"
      PAGES_DIRNAME = "pages"

      WIKIS = {
        "zh" => "https://zh.wikisource.org/w/api.php",
        "vi" => "https://vi.wikisource.org/w/api.php"
      }.freeze

      # One curated page: +id+ the stable local name (urn segment and
      # filename), +wiki+/+title+ the upstream address, +mode+ the parser
      # layout, +work+/+part+ the human citation.
      CuratedPage = Data.define(:id, :wiki, :title, :mode, :work, :part)

      DVSKTT = "大越史記全書"
      # The quyển numerals as the subpage titles spell them (censused).
      CJK_NUMERALS = %w[一 二 三 四 五 六 七 八 九 十
                        十一 十二 十三 十四 十五 十六 十七 十八 十九].freeze
      # The three DVSKTT series: local series slug → [title prefix, count].
      DVSKTT_SERIES = { "ngoai-ky" => ["外紀卷之", 5],
                        "ban-ky" => ["本紀卷之", 19],
                        "tuc-bien" => ["續編卷之", 5] }.freeze

      def self.dvsktt_pages
        front = CuratedPage.new(id: "dvsktt-quyen-thu", wiki: "zh", title: "#{DVSKTT}/卷首",
                                mode: :prose, work: DVSKTT, part: "卷首")
        quyen = DVSKTT_SERIES.flat_map do |series, (prefix, count)|
          (1..count).map do |number|
            part = "#{prefix}#{CJK_NUMERALS[number - 1]}"
            CuratedPage.new(id: "dvsktt-#{series}-#{number}", wiki: "zh", title: "#{DVSKTT}/#{part}",
                            mode: :prose, work: DVSKTT, part: part)
          end
        end
        [front, *quyen]
      end

      PAGES = [
        *dvsktt_pages,
        CuratedPage.new(id: "hich-tuong-si", wiki: "zh", title: "諭諸裨將檄文",
                        mode: :prose, work: "諭諸裨將檄文", part: nil),
        CuratedPage.new(id: "binh-ngo-dai-cao", wiki: "vi", title: "Bình Ngô đại cáo",
                        mode: :parallel_poem, work: "平吳大誥", part: nil)
      ].freeze

      PAGES_BY_ID = PAGES.to_h { |page| [page.id, page] }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "viet-wikisource",
        name: "Đại Việt classical shelf — 大越史記全書 + chữ Hán showpieces (Wikisource)",
        license: "Texts in the public domain ({{PD-old}} on every curated work); the Wikisource " \
                 "transcription layer CC BY-SA 4.0 (zh/vi.wikisource.org rightsinfo, verified " \
                 "2026-08-18) → attribution",
        license_class: "attribution",
        upstream_url: "https://zh.wikisource.org/wiki/%E5%A4%A7%E8%B6%8A%E5%8F%B2%E8%A8%98%E5%85%A8%E6%9B%B8",
        parser_family: "wikisource-han",
        credit: "Wikisource contributors (zh.wikisource.org / vi.wikisource.org), CC BY-SA 4.0"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe HEADs each wiki's api.php
      # (reachability; the API serves no useful Last-Modified, so drift
      # honestly reads unknown against the revid-pinned state file).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        WIKIS.map do |wiki, api_url|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "#{wiki}.wikisource api.php",
            zip_url: "#{api_url}?action=query&meta=siteinfo&format=json",
            metadata_url: nil, state_subdir: ".", state_file: STATE_FILE
          )
        end
      end

      # +delay+/+http+ exist for the WebMock'd tests (0 / stubbed); real
      # syncs keep the polite defaults.
      def initialize(delay: Nabu::WikiFetch::DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes,
      # so there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        fetched = 0
        PAGES.group_by(&:wiki).each do |wiki, pages|
          pages.each_slice(Nabu::WikiFetch::CONTENT_BATCH) do |batch|
            progress&.call("Fetching #{batch.size} #{wiki}.wikisource page(s)…\n")
            fetched += fetch_batch!(workdir, wiki, batch)
          end
        end
        write_state!(workdir, sha = pin_sha(workdir))
        report(sha, fetched)
      rescue Nabu::FetchError => e
        raise Nabu::FetchError, "viet-wikisource fetch failed into #{workdir}: #{e.message}"
      end

      # -- discover ------------------------------------------------------------------

      # One DocumentRef per curated page whose envelope is on disk, in
      # curated (reading) order. A workdir without pages/ yields nothing
      # (pre-fetch state); a title upstream never answered is simply absent.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        PAGES.each do |page|
          path = page_path(workdir, page.id)
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn_for(page),
                                      path: File.expand_path(path), metadata: { "page" => page.id })
        end
      end

      # The census: curated envelopes are recognized; state file and other
      # dotfiles are mechanics; README is documentation; anything else is a
      # stray — loud.
      def discovery_skips(workdir)
        strays = stray_files(workdir)
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      # -- parse -------------------------------------------------------------------

      def parse(document_ref)
        page = PAGES_BY_ID[File.basename(document_ref.path, ".json")]
        raise ParseError, "#{document_ref.path}: not a curated viet-wikisource page" if page.nil?

        envelope = read_envelope(document_ref.path)
        result = parser.parse(envelope["wikitext"], mode: page.mode)
        raise ParseError, "#{document_ref.path}: no passages extracted for #{document_ref.id}" if result.passages.empty?

        build_document(document_ref, page, envelope, result)
      end

      private

      def parser
        @parser ||= WikisourceHanParser.new
      end

      def urn_for(page)
        "urn:nabu:#{MANIFEST.id}:#{page.id}"
      end

      def page_path(workdir, id)
        File.join(workdir, PAGES_DIRNAME, "#{id}.json")
      end

      # -- fetch internals -----------------------------------------------------------

      # One api.php revisions request for a ≤50-title batch; every answered
      # title's envelope is written tmp+rename. Unanswered titles cost
      # nothing local (retention by construction).
      def fetch_batch!(workdir, wiki, batch)
        response = get_json(WIKIS.fetch(wiki),
                            "action" => "query", "format" => "json", "prop" => "revisions",
                            "rvprop" => "content|ids|timestamp", "rvslots" => "main",
                            "titles" => batch.map(&:title).join("|"))
        by_title = batch.to_h { |page| [page.title, page] }
        written = 0
        (response.dig("query", "pages") || {}).each_value do |page|
          curated = by_title[page["title"]] or next
          revision = page.dig("revisions", 0) or next

          write_envelope!(workdir, curated, page, revision)
          written += 1
        end
        written
      end

      def write_envelope!(workdir, curated, page, revision)
        envelope = {
          "title" => page.fetch("title"), "pageid" => page["pageid"], "ns" => page["ns"] || 0,
          "revid" => revision["revid"], "timestamp" => revision["timestamp"],
          "wiki" => curated.wiki, "wikitext" => revision.dig("slots", "main", "*").to_s
        }
        FileUtils.mkdir_p(File.join(workdir, PAGES_DIRNAME))
        target = page_path(workdir, curated.id)
        File.binwrite("#{target}.tmp", "#{JSON.pretty_generate(envelope)}\n")
        File.rename("#{target}.tmp", target)
      end

      # The fetch pin: curated id → revid over every envelope on disk.
      def pin_sha(workdir)
        pin = PAGES.filter_map do |page|
          path = page_path(workdir, page.id)
          [page.id, JSON.parse(File.read(path))["revid"]] if File.file?(path)
        rescue JSON::ParserError
          nil
        end
        Digest::SHA256.hexdigest(JSON.generate(pin.sort.to_h))
      end

      def write_state!(workdir, sha)
        FileUtils.mkdir_p(workdir)
        state = { "last_modified" => nil, "sha256" => sha, "url" => WIKIS.values.join(" ") }
        File.write(File.join(workdir, STATE_FILE), JSON.pretty_generate(state))
      end

      def report(sha, fetched)
        missing = PAGES.size - fetched
        notes = "pages: #{fetched} fetched, #{missing} missing upstream (#{PAGES.size} curated)"
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: notes,
                              repos: WIKIS.values.to_h { |api_url| [api_url, sha] })
      end

      # One throttled, UA-identified api.php GET (the WikiFetch mold); an
      # API-level error payload is as fatal as a transport one.
      def get_json(api_url, params)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        url = "#{api_url}?#{URI.encode_www_form(params)}"
        response, = RedirectFollow.get(url, http: @http, error: Nabu::FetchError,
                                            headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT })
        payload = JSON.parse(response.body.to_s)
        raise Nabu::FetchError, "api.php error for #{api_url}: #{payload['error']}" if payload.key?("error")

        payload
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "api.php returned unparseable JSON for #{api_url}: #{e.message}"
      end

      # -- discover internals ----------------------------------------------------------

      def stray_files(workdir)
        known = PAGES.map { |page| File.join(PAGES_DIRNAME, "#{page.id}.json") }
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| File.basename(path).start_with?(".") }
           .reject { |path| File.basename(path).downcase == "readme.md" }
           .map { |path| path.delete_prefix("#{workdir}/") }
           .reject { |rel| known.include?(rel) }
           .sort
      end

      # -- parse internals ------------------------------------------------------------

      def read_envelope(path)
        envelope = JSON.parse(File.read(path))
        raise ParseError, "#{path}: page envelope has no wikitext" unless envelope["wikitext"].is_a?(String)

        envelope
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable page envelope: #{e.message}"
      end

      def build_document(document_ref, page, envelope, result)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE,
          title: Nabu::Normalize.nfc(envelope.fetch("title")),
          canonical_path: document_ref.path,
          metadata: document_metadata(page, result)
        )
        result.passages.each_with_index do |passage, index|
          document << build_passage(document_ref, passage, index)
        end
        document
      end

      def document_metadata(page, result)
        header = result.header
        {
          "work" => page.work, "part" => page.part,
          "author" => header.author && Nabu::Normalize.nfc(header.author),
          "date" => date_envelope(header.year),
          "textquality" => header.textquality,
          "phien_am" => result.unpaired_phien_am && Nabu::Normalize.nfc(result.unpaired_phien_am)
        }.compact
      end

      # The MetadataDates :structured shape: the header's own year param as
      # a one-year envelope (the hịch: 1284). Pages without one — every
      # DVSKTT quyển — claim nothing.
      def date_envelope(year)
        return nil if year.nil?

        { "not_before" => year, "not_after" => year, "raw" => year.to_s }
      end

      def build_passage(document_ref, passage, index)
        annotations = {
          "section" => passage.section && Nabu::Normalize.nfc(passage.section),
          "phien_am" => passage.phien_am && Nabu::Normalize.nfc(passage.phien_am)
        }.compact
        Nabu::Passage.new(
          urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE,
          text: Nabu::Normalize.nfc(passage.text), sequence: index, annotations: annotations
        )
      end
    end
  end
end
