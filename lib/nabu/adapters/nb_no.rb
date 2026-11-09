# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "stringio"
require "uri"
require "zlib"

require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # nb-no (P165): Nasjonalbiblioteket — the National Library of Norway's
    # digitized public-domain books, through its keyless catalog API
    # (api.nb.no/catalog/v1): the item record (metadata) plus the per-page
    # ALTO OCR every digitized book serves. The slug names the library,
    # not a collection (the ndl-kotenseki/mdz-protestant shape names one
    # because those adapters ARE one collection): the cone below is this
    # source's FIRST ERA, and later eras widen the same census rather
    # than mint siblings.
    #
    # == License (read first-hand 2026-11-08)
    #
    # Every cone item answers accessInfo {"isPublicDomain": true,
    # "license": "publicdomain", "accessAllowedFrom": "EVERYWHERE"}; its
    # IIIF manifest (license https://www.nb.no/lisens/#public-domain)
    # carries the attribution, verbatim: "Du kan kopiere, endre, spre,
    # vise og fremføre dette verket, selv for kommersielle formål, uten å
    # spørre om tillatelse." ("You may copy, modify, distribute, display
    # and perform this work, even for commercial purposes, without asking
    # permission.") → open. The fetch re-reads accessInfo per item and
    # never crawls a page of an item that is not public domain (ledgered
    # "not-public-domain"; discovery skips it by rule).
    #
    # == The cone (the first era, declared)
    #
    # Books (mediatype bøker) in content class publicdomain that are
    # EITHER printed before 1700 (year ≤ PRE_YEAR) OR catalogued in one
    # of CONE_LANGUAGES at any date: Old Norse (non), Latin (lat), Greek
    # (grc, and gre — the catalogue's Modern-Greek code, which NB's
    # cataloguers also put on Septuagint and inscription editions) and
    # the Sámi languages (sme/sma/smj; smn/sms/sje/sju/smi held in the
    # filter so a later-catalogued item joins). One query (CONE_FILTER),
    # paged at CENSUS_PAGE rows.
    #
    # Census 2026-11-08 (the API's own totals, reconciled: 1,910 unique
    # ids = totalElements 1,910; 530,042 pages by the records' pageCount):
    #
    #   arm / language       items   pages     <1600 1600s 1700s 1800s 1900+
    #   pre-1700, any lang    1,077  344,976   (598 of them in no cone language)
    #   lat                   1,005             232   239   273   240    21
    #   non (Old Norse)         153               —     1     9   106    37
    #   sme (North Sámi)        139               —     —    13    35    91
    #   grc                      45              12    10     3    20     —
    #   gre                      12               2     —     1     8     1
    #   sma / smj                 8 / 4           —     —     —     —  8 / 4
    #
    # (an item counts under every cone language it carries.) Counts over
    # content class "public" run larger (lat 1,193, non 133 ≤ 1899): that
    # class also holds catalogue records with no scan
    # (isDigital false, license "copyrighted" — 200 pre-1700 such rows
    # censused); publicdomain is the class that is both scanned and free.
    # Crawl order (CRAWL_CLASSES): non (153 items / 46,622 pages) → Greek
    # (55 / 19,446) → Sámi (147 / 31,359) → lat (957 / 247,876) → the
    # remaining pre-1700 prints (598 / 184,739), each oldest first — the
    # cone's rarest material lands in the first slices. The Sámi arm is
    # mostly 1900+ (Sámi Parliament publications, free under NB's own
    # class); the non arm is mostly 19th-century editions and grammars
    # (Unger, Gislason; many written in Norwegian about Old Norse — the
    # record's FIRST language code leads, see Language below).
    #
    # == Delivery grains (census 2026-11-08)
    #
    # search answer (/catalog/v1/items) → the census (census.tsv, the one
    # declared materialization); item record (/items/<id>) → document
    # metadata; ALTO list (/metadata/<id>/altos) → the page list; ALTO
    # page (/metadata/<id>/altos/<URN>_<tail>) → PASSAGE. Not taken: the
    # IIIF manifest (page labels and images only; its license line is
    # quoted above), MODS/MARCXML/Dublin Core (the item record carries the
    # same catalogue fields as JSON), contentfragments (search snippets).
    # No whole-book text route is documented (accessInfo names a "text"
    # action; no public endpoint answers it — probed), and the DH-lab API
    # serves wordbags/concordances only: per-page ALTO is the route.
    #
    # == The paced, resumable crawl (the ndl-kotenseki / korpus16 mold)
    #
    # No robots.txt (404), no rate-limit headers, no documented quota:
    # request STARTS are spaced DELAY (1 s) apart — never faster — and the
    # API's own latency (~1.1 s per ALTO page, measured) sets the real
    # pace. Per sync: the census (~20 requests; aborts when its unique ids
    # do not reconcile with the answer's totalElements), then up to SLICE
    # requests through the census in crawl order — per item, the record,
    # the ALTO list, then every missing page. Resume is at the file grain:
    # items/<id>/item.json, altos.json and alto/<tail>.xml.gz on disk are
    # done; pages land GZIP-compressed (mtime 0, byte-stable — the raw
    # ALTO is ~50–80 KB a page, ~37 GB for the cone uncompressed; gzip
    # takes ~5×). The ledger (.nb-crawl.json) holds {"items" => {id =>
    # reason}} for items never to retry ("missing" 404, "not-public-domain",
    # "no-alto") and {"pages" => {id => [tails]}} for pages that answered
    # 404 or not-ALTO. A held record is never re-fetched (an accessInfo
    # change after the first fetch goes unseen — a deliberate re-census is
    # a phase decision), but it is re-checked before any page request, so
    # a lost ledger can never page a not-public-domain item. 429 stops the
    # slice cleanly; a 5xx or transport
    # failure retries RETRIES times with backoff, then aborts the sync
    # (the next one resumes there).
    #
    # Sizing: 530,042 page requests + 2 per item ≈ 534k requests ≈ 165 h
    # at ~1.1 s — a multi-phase crawl (~350 slices of SLICE 1,500 ≈ 28 min
    # each). The first slice (crawl order above): the oldest ~25 non
    # items (the 1600s–1840s Old Norse editions), ~28 min.
    #
    # == Documents and passages
    #
    # One document per item, discovered only once its crawl is COMPLETE
    # (every listed page on disk or ledgered); a partial item never mints
    # a partial document (discovery_skips names it). urn =
    # urn:nabu:nb-no:<the URN:NBN tail, e.g. digibok_2016101048209>; one
    # passage per page with text, cited by the page's own URN tail
    # (…:0011; covers and inserts keep NB's C1/I1/I3/C3 tails — on a
    # leaflet the "cover" IS the title page, so no tail is skipped by
    # rule). Text = the ALTO TextLines in order, each line's String
    # CONTENTs space-joined and the HYP hyphen kept on its line (the
    # SUBS_CONTENT dehyphenation is NOT applied — canonical means the
    # line as printed); lines joined by "\n".
    #
    # OCR LAYER, NOT AN EDITION: NB's own library OCR, uncorrected —
    # Fraktur and pre-1700 type read with the errors the engine made,
    # noise pages (blank versos, binding) ride as recognized. The engine
    # differs per scan campaign (the fixtures alone: ABBYY FineReader 11
    # and 12 under CCS docWorks/docWizz, and Tesseract 5.2 on a
    # re-processed 1837 Sámi primer), so each document names its own in
    # ocr_software (the first page's ALTO header). Every document carries
    # text_nature "machine-ocr" and the ocr_note.
    #
    # == Language
    #
    # The record's own language codes (MARC 639-2, verbatim — the codemap
    # aliases dan→da, ger→de, fre→fr, swe→sv, nor→no; lat, non, grc, sme,
    # sma, smj, nob, nno stay their own codes; dut, ice and gre carry no
    # alias row and ride bare — declared). The document and its passages
    # take the FIRST code that is not a collective (mul/und/zxx; a record
    # with only collectives keeps its first); every code rides metadata
    # "languages". Space-joined codes ("lat heb") split. Pages are not
    # language-tagged: a Latin dedication inside a Danish print rides the
    # record's code — deliberately coarse.
    #
    # == Axes (aggressive mining)
    #
    # date — originInfo.issued (+ the untouched imprint date where the
    # record keeps one, e.g. "MDCLVII [1657]" beside issued 1652 — both
    # claims span the envelope), class edition (:structured): the print's
    # year, never the text's composition. place — the imprint place in
    # the print's own form (placeString or city, whichever is not the
    # cataloguer's "Land - By" authority form: "Christianiae",
    # "Kristianiast", "Lugduni Batavorum"; bracketed supplied places
    # unbracketed), named; the authority form rides place_normalized.
    # author — the record's people (name, life dates, roles, bibsys
    # authority id), the creator/author-role and primary names joined.
    # kind — subject.genres (NB's genre headings: Likprekener,
    # Leilighetstrykk, Lærebøker …) faceted as "genre", folded in
    # config/kind_map.yml (open vocabulary). subject topics, DDC/UDC,
    # publisher, extent and statement of responsibility ride metadata.
    class NbNo < Nabu::Adapter
      API = "https://api.nb.no/catalog/v1"
      SEARCH_URL = "#{API}/items".freeze
      ITEM_URL = "#{API}/items/%s".freeze
      ALTOS_URL = "#{API}/metadata/%s/altos".freeze
      PERMALINK = "https://www.nb.no/items/%s"

      CENSUS_TSV = "census.tsv"
      CENSUS_HEADER = %w[id urn year languages pages class].freeze
      ITEMS_DIRNAME = "items"
      ITEM_FILE = "item.json"
      ALTOS_FILE = "altos.json"
      ALTO_DIRNAME = "alto"
      LEDGER_FILE = ".nb-crawl.json"
      URN_PREFIX = "urn:nabu:nb-no:"

      # The cone (the source's first era — see the header).
      PRE_YEAR = 1699
      CONE_LANGUAGES = %w[non lat grc gre sme sma smj smn sms sje sju smi].freeze
      SAMI = %w[sme sma smj smn sms sje sju smi].freeze
      CONE_FILTER = "year:[* TO #{PRE_YEAR}] OR languages:(#{CONE_LANGUAGES.join(' OR ')})".freeze
      BASE_FILTERS = ["mediatype:bøker", "contentClasses:publicdomain"].freeze
      # Crawl priority, first match wins; "pre1700" is the rest of the cone.
      CRAWL_CLASSES = [["non", %w[non]], ["greek", %w[grc gre]], ["sami", SAMI], ["lat", %w[lat]]].freeze
      CLASS_ORDER = [*CRAWL_CLASSES.map(&:first), "pre1700"].freeze
      COLLECTIVE_LANGUAGES = %w[mul und zxx].freeze

      # const: census page size — the API answers empty past ~page 50, so
      # one query holds at most ~5,000 rows (the cone is 1,910; the guard
      # below aborts rather than truncate).
      CENSUS_PAGE = 100
      # const: crawl politeness, request STARTS ≥ 1 s apart. Never lower.
      DELAY = 1.0
      # Requests per sync: ~28 min at the measured ~1.1 s per request (the
      # no-silent-passes ceiling is ~30 min a pass).
      SLICE = 1_500
      RETRIES = 3
      BACKOFF = 5.0
      PROGRESS_EVERY = 100

      PUBLIC_DOMAIN = "publicdomain"
      OCR_NOTE = "Nasjonalbiblioteket's own library OCR (per-page ALTO; the engine is named in " \
                 "ocr_software), uncorrected: early type, Fraktur and damaged pages read as the engine " \
                 "read them, hyphenation as printed. Cite the scan (permalink)."
      # The cataloguer's authority form of a place ("Norge - Oslo",
      # "Danmark - København") — not the print's own spelling.
      AUTHORITY_PLACE = /\A[[:alpha:]]+ - \S/
      AUTHOR_ROLES = %w[aut cre].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "nb-no",
        name: "Nasjonalbiblioteket — public-domain books, page OCR (National Library of Norway)",
        license: "Public domain (accessInfo license \"publicdomain\", accessAllowedFrom EVERYWHERE, per item). " \
                 "The IIIF manifest's attribution, verbatim: \"Du kan kopiere, endre, spre, vise og fremføre " \
                 "dette verket, selv for kommersielle formål, uten å spørre om tillatelse.\" " \
                 "(https://www.nb.no/lisens/#public-domain). Credit: Nasjonalbiblioteket; the text is NB's " \
                 "uncorrected OCR layer, not an edition",
        license_class: "open",
        upstream_url: "https://api.nb.no/",
        parser_family: "nb-alto"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "NB catalog item (Edda Snorra Sturlusonar)",
          zip_url: format(ITEM_URL, "0148f6ba555e6d8ec9b5aaea23d39cbc"),
          metadata_url: nil, state_subdir: "", liveness_only: true
        )]
      end

      # census.tsv is derived from the search answers at fetch (the
      # declared-materializations rule); items/ holds upstream's own
      # answers (the ALTO gzipped verbatim).
      def self.materialized_paths = [CENSUS_TSV]

      # The census URL for one page of the cone.
      def self.census_url(page)
        query = [["q", "*"], *[*BASE_FILTERS, CONE_FILTER].map { |filter| ["filter", filter] },
                 ["size", CENSUS_PAGE.to_s], ["page", page.to_s], ["sort", "date,asc"]]
        "#{SEARCH_URL}?#{URI.encode_www_form(query)}"
      end

      # The record's language codes in order, space-joined codes split.
      def self.language_codes(metadata)
        Array(metadata["languages"]).flat_map { |entry| entry["code"].to_s.split }.reject(&:empty?)
      end

      # The document's code: the first non-collective, else the first.
      def self.primary_language(codes)
        codes.find { |code| !COLLECTIVE_LANGUAGES.include?(code) } || codes.first || "und"
      end

      # The crawl class (CLASS_ORDER) for a census row's codes.
      def self.crawl_class(codes)
        CRAWL_CLASSES.find { |_, members| codes.intersect?(members) }&.first || "pre1700"
      end

      # +items+ narrows the crawl to the named ids (the fixture recipe and
      # the tests' seam); nil crawls the whole census.
      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http, items: nil, backoff: BACKOFF)
        super()
        @delay = delay
        @slice = slice
        @http = http
        @items = items&.map(&:to_s)
        @backoff = backoff
        @last_request_at = nil
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        rows = refresh_census!(workdir, progress)
        ledger = read_ledger(workdir)
        crawl = @items ? rows.select { |row| @items.include?(row["id"]) } : rows
        begin
          written, stop = crawl_slice!(workdir, crawl, ledger, progress)
        ensure
          # An aborted slice (a 5xx run) still keeps what it ledgered.
          write_ledger!(workdir, ledger)
        end
        notes = crawl_notes(workdir, rows, crawl, ledger, written, stop)
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, ledger), fetched_at: Time.now, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ledger = read_ledger(workdir)
        item_dirs(workdir).each do |id|
          next unless complete?(workdir, id, ledger)

          item = read_json(item_path(workdir, id), label: "item record")
          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{urn_key(item, id)}",
                       path: File.expand_path(item_path(workdir, id)), metadata: { "item" => id }
                     ))
        end
      end

      def discovery_skips(workdir)
        ledger = read_ledger(workdir)
        by_rule = []
        strays = []
        item_dirs(workdir).each do |id|
          if File.file?(item_path(workdir, id))
            note = skip_note(workdir, id, ledger)
            by_rule << note if note
          else
            strays << "item directory without an item record: #{ITEMS_DIRNAME}/#{id}"
          end
        end
        strays += stray_files(workdir).map { |rel| "non-corpus file: #{rel}" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: by_rule.size, unrecognized: strays.size,
                                          notes: by_rule + strays)
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        workdir = File.dirname(document_ref.path, 3)
        id = document_ref.metadata.fetch("item")
        item = read_json(document_ref.path, label: "item record")
        meta = item.fetch("metadata", {})
        codes = self.class.language_codes(meta)
        language = self.class.primary_language(codes)
        pages, accounting = read_pages(workdir, id, read_ledger(workdir))
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: title_for(meta),
          canonical_path: document_ref.path,
          metadata: metadata_for(item, codes).merge(accounting)
        )
        pages.each do |tail, page|
          document << Nabu::Passage.new(urn: "#{document.urn}:#{tail}", language: language, text: page[:text],
                                        sequence: document.size, annotations: page[:annotations])
        end
        raise ParseError, "#{document_ref.path}: no page carries OCR text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # One ALTO page → {text:, printed:, confidence:, software:}; text ""
      # when the page holds no String.
      def self.flatten_alto(xml)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        lines = doc.xpath("//TextLine").filter_map do |line|
          words = []
          line.element_children.each do |node|
            case node.name
            when "String" then words << node["CONTENT"].to_s
            when "HYP" then words.empty? ? words << node["CONTENT"].to_s : words[-1] += node["CONTENT"].to_s
            end
          end
          text = words.join(" ").gsub(/[[:space:]]+/, " ").strip
          text unless text.empty?
        end
        page = doc.at_xpath("//Page")
        software = doc.at_xpath("//ocrProcessingStep/processingSoftware")
        { text: Normalize.nfc(lines.join("\n")), printed: page&.[]("PRINTED_IMG_NR"), confidence: page&.[]("PC"),
          software: software && [software.at_xpath("softwareName")&.text, software.at_xpath("softwareVersion")&.text]
                                .compact.join(" ").strip }
      end

      private

      # -- census ------------------------------------------------------------

      # Pages the cone query; returns the rows in crawl order and writes
      # census.tsv when its bytes change.
      def refresh_census!(workdir, progress)
        progress&.call("nb-no census (the cone query)…\n")
        items = {}
        total = nil
        page = 0
        loop do
          answer = JSON.parse(utf8_body(get_with_retries!(self.class.census_url(page), accept: [200])))
          total ||= answer.dig("page", "totalElements")
          Array(answer.dig("_embedded", "items")).each { |item| items[item["id"]] ||= census_row(item) }
          page += 1
          break if page >= answer.dig("page", "totalPages").to_i
        end
        unless total.is_a?(Integer) && items.size == total
          raise FetchError, "nb-no: the census holds #{items.size} unique id(s) but the API counts #{total.inspect} " \
                            "— a truncated or shifting answer; nothing crawled"
        end
        rows = items.values.sort_by { |row| [CLASS_ORDER.index(row["class"]), row["year"].to_i, row["id"]] }
        write_if_changed!(File.join(workdir, CENSUS_TSV), census_tsv(rows))
        rows
      rescue JSON::ParserError => e
        raise FetchError, "nb-no: the census answer is not JSON: #{e.message}"
      end

      def census_row(item)
        meta = item.fetch("metadata", {})
        codes = self.class.language_codes(meta)
        { "id" => item["id"].to_s, "urn" => meta.dig("identifiers", "urn").to_s,
          "year" => meta.dig("originInfo", "issued").to_s[/\d{4}/].to_s, "languages" => codes.join(" "),
          "pages" => meta["pageCount"].to_s, "class" => self.class.crawl_class(codes) }
      end

      def census_tsv(rows)
        lines = rows.map { |row| CENSUS_HEADER.map { |key| row[key].to_s.tr("\t\n", "  ") }.join("\t") }
        "#{[CENSUS_HEADER.join("\t"), *lines].join("\n")}\n"
      end

      # -- the crawl ---------------------------------------------------------

      # Returns [files written, stop reason or nil].
      def crawl_slice!(workdir, rows, ledger, progress)
        @made = 0
        written = 0
        rows.each do |row|
          id = row["id"]
          next if ledger["items"].key?(id)

          outcome = crawl_item!(workdir, id, ledger) { written += 1 }
          return [written, outcome] if outcome

          report_progress(progress, written, id)
        end
        [written, nil]
      end

      # Walks one item; yields once per file written. Returns a stop
      # reason (:slice / :rate_limited) or nil when the item is done.
      def crawl_item!(workdir, id, ledger)
        unless File.file?(item_path(workdir, id))
          return :slice if spent?

          case (outcome = fetch_item!(workdir, id, ledger))
          when :rate_limited then return outcome
          when :ok then yield
          end
          return nil if ledger["items"].key?(id)
        end
        # A held record is re-checked (a lost ledger must never page a
        # not-public-domain item).
        unless public_domain?(read_json(item_path(workdir, id), label: "item record"))
          refuse_item!(ledger, id, "not-public-domain")
          return nil
        end

        unless File.file?(altos_path(workdir, id))
          return :slice if spent?

          case (outcome = fetch_altos!(workdir, id, ledger))
          when :rate_limited then return outcome
          when :ok then yield
          end
          return nil if ledger["items"].key?(id)
        end
        missing_pages(workdir, id, ledger).each do |tail, href|
          return :slice if spent?

          case (outcome = fetch_page!(workdir, id, tail, href))
          when :rate_limited then return outcome
          when :ok then yield
          else (ledger["pages"][id] ||= []) << tail
          end
        end
        nil
      end

      def spent? = @made >= @slice

      def fetch_item!(workdir, id, ledger)
        response = request!(format(ITEM_URL, id))
        return :rate_limited if response.status == 429
        return refuse_item!(ledger, id, "missing") if response.status == 404

        body = utf8_body(response)
        item = JSON.parse(body)
        write_atomic!(item_path(workdir, id), body)
        refuse_item!(ledger, id, "not-public-domain") unless public_domain?(item)
        :ok
      rescue JSON::ParserError
        refuse_item!(ledger, id, "missing")
      end

      def fetch_altos!(workdir, id, ledger)
        response = request!(format(ALTOS_URL, id))
        return :rate_limited if response.status == 429
        return refuse_item!(ledger, id, "no-alto") if response.status == 404

        body = utf8_body(response)
        return refuse_item!(ledger, id, "no-alto") if alto_hrefs(JSON.parse(body)).empty?

        write_atomic!(altos_path(workdir, id), body)
        :ok
      rescue JSON::ParserError
        refuse_item!(ledger, id, "no-alto")
      end

      def fetch_page!(workdir, id, tail, href)
        response = request!(href)
        return :rate_limited if response.status == 429
        return :refused if response.status == 404

        body = utf8_body(response)
        return :refused unless body.include?("<alto")

        write_gz!(page_path(workdir, id, tail), body)
        :ok
      end

      def refuse_item!(ledger, id, reason)
        ledger["items"][id] = reason
        :refused
      end

      def request!(url)
        @made += 1
        get_with_retries!(url, accept: [200, 404, 429])
      end

      def report_progress(progress, written, id)
        return unless progress && written.positive? && (written % PROGRESS_EVERY).zero?

        progress.call("crawl: +#{written} file(s) this sync (item #{id})…\n")
      end

      def get_with_retries!(url, accept:)
        attempt = 0
        begin
          attempt += 1
          get!(url, accept: accept)
        rescue Nabu::FetchError
          raise if attempt >= RETRIES

          pause = @backoff * (2**(attempt - 1))
          sleep(pause) if pause.positive?
          retry
        end
      end

      # Request STARTS are spaced DELAY apart (latency counts toward the
      # pause): ~1 req/s, never faster.
      def get!(url, accept:)
        if @delay.positive? && @last_request_at
          pause = @delay - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at)
          sleep(pause) if pause.positive?
        end
        @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response, = Nabu::RedirectFollow.get(
          url, http: @http, error: Nabu::FetchError, accept: accept,
               headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        response
      end

      def utf8_body(response) = response.body.to_s.dup.force_encoding(Encoding::UTF_8)

      def write_if_changed!(path, body)
        return if File.file?(path) && Digest::SHA256.file(path).hexdigest == Digest::SHA256.hexdigest(body)

        write_atomic!(path, body)
      end

      def write_atomic!(path, body)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.tmp", body)
        File.rename("#{path}.tmp", path)
      end

      # Byte-stable gzip (mtime 0): the same page gzips to the same file.
      def write_gz!(path, body)
        io = StringIO.new(+"", "wb")
        gz = Zlib::GzipWriter.new(io)
        gz.mtime = 0
        gz.write(body)
        gz.close
        write_atomic!(path, io.string)
      end

      def crawl_notes(workdir, rows, crawl, ledger, written, stop)
        complete = crawl.count { |row| complete?(workdir, row["id"], ledger) }
        listed = crawl.sum { |row| File.file?(altos_path(workdir, row["id"])) ? page_list(workdir, row["id"]).size : 0 }
        held = crawl.sum { |row| held_tails(workdir, row["id"]).size }
        parts = ["census #{rows.size} item(s) / #{rows.sum { |row| row['pages'].to_i }} page(s) by pageCount",
                 "#{complete}/#{crawl.size} item(s) complete, #{held}/#{listed} listed page(s) held " \
                 "(+#{written} file(s) this sync)"]
        parts << { slice: "slice limit reached — resume next sync",
                   rate_limited: "rate limited — resume next sync" }[stop]
        refused = ledger["items"].values.tally.sort.map { |reason, count| "#{count} #{reason}" }
        parts << "item(s) ledgered: #{refused.join(', ')}" unless refused.empty?
        ledgered = ledger["pages"].values.sum(&:size)
        parts << "#{ledgered} page(s) ledgered" if ledgered.positive?
        parts.compact.join("; ")
      end

      def crawl_sha(workdir, ledger)
        census = File.join(workdir, CENSUS_TSV)
        files = Dir.glob(File.join(workdir, ITEMS_DIRNAME, "**", "*"))
                   .select { |path| File.file?(path) }.map { |path| path.delete_prefix("#{workdir}/") }.sort
        Digest::SHA256.hexdigest(JSON.generate([File.file?(census) ? Digest::SHA256.file(census).hexdigest : "",
                                                files, ledger]))
      end

      def read_ledger(workdir)
        path = File.join(workdir, LEDGER_FILE)
        blank = { "items" => {}, "pages" => {} }
        return blank unless File.file?(path)

        stored = JSON.parse(SourceRead.utf8_file(path, label: "nb-no crawl ledger"))
        { "items" => stored.fetch("items", {}).to_h { |id, reason| [id.to_s, reason.to_s] },
          "pages" => stored.fetch("pages", {}).to_h { |id, tails| [id.to_s, Array(tails).map(&:to_s)] } }
      rescue JSON::ParserError
        blank
      end

      def write_ledger!(workdir, ledger)
        stored = { "items" => ledger["items"].sort.to_h,
                   "pages" => ledger["pages"].transform_values { |tails| tails.uniq.sort }.sort.to_h }
        File.write(File.join(workdir, LEDGER_FILE), JSON.pretty_generate(stored))
      end

      # -- the item tree -----------------------------------------------------

      def item_dir(workdir, id) = File.join(workdir, ITEMS_DIRNAME, id)
      def item_path(workdir, id) = File.join(item_dir(workdir, id), ITEM_FILE)
      def altos_path(workdir, id) = File.join(item_dir(workdir, id), ALTOS_FILE)
      def page_path(workdir, id, tail) = File.join(item_dir(workdir, id), ALTO_DIRNAME, "#{tail}.xml.gz")

      def item_dirs(workdir)
        root = File.join(workdir, ITEMS_DIRNAME)
        return [] unless Dir.exist?(root)

        Dir.children(root).select { |child| File.directory?(File.join(root, child)) }.sort
      end

      def held_tails(workdir, id)
        Dir.glob(File.join(item_dir(workdir, id), ALTO_DIRNAME, "*.xml.gz"))
           .map { |path| File.basename(path, ".xml.gz") }
      end

      def alto_hrefs(altos) = Array(altos.dig("_links", "alto")).filter_map { |link| link["href"]&.to_s }

      # [[tail, href]] in upstream's list order. The tail is the page's
      # own URN suffix (…_0011 → "0011"; covers C1/C3, inserts I1/I3).
      def page_list(workdir, id)
        alto_hrefs(read_json(altos_path(workdir, id), label: "ALTO list")).map do |href|
          name = URI.decode_www_form_component(href.split("/").last.to_s)
          [name[/_([^_]+)\z/, 1] || name, href]
        end
      end

      def missing_pages(workdir, id, ledger)
        done = held_tails(workdir, id) + Array(ledger["pages"][id])
        page_list(workdir, id).reject { |pair| done.include?(pair.first) }
      end

      def public_domain?(item)
        access = item["accessInfo"] || {}
        access["isPublicDomain"] == true && access["license"] == PUBLIC_DOMAIN
      end

      def complete?(workdir, id, ledger)
        return false if ledger["items"].key?(id)
        return false unless File.file?(item_path(workdir, id)) && File.file?(altos_path(workdir, id))
        return false unless public_domain?(read_json(item_path(workdir, id), label: "item record"))

        missing_pages(workdir, id, ledger).empty?
      end

      def skip_note(workdir, id, ledger)
        return "item #{id}: ledgered #{ledger['items'][id]}" if ledger["items"].key?(id)
        unless public_domain?(read_json(item_path(workdir, id), label: "item record"))
          return "item #{id}: not public domain (accessInfo) — never crawled"
        end
        return "crawl incomplete: item #{id} (ALTO list not yet fetched)" unless File.file?(altos_path(workdir, id))

        missing = missing_pages(workdir, id, ledger).size
        "crawl incomplete: item #{id} (#{missing} page(s) to go)" if missing.positive?
      end

      def stray_files(workdir)
        Dir.glob(File.join(workdir, "**", "*"))
           .select { |path| File.file?(path) }
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") || File.basename(path).start_with?(".") }
           .reject { |path| [CENSUS_TSV, "README.md"].include?(path.delete_prefix("#{workdir}/")) }
           .grep_v(%r{/#{ITEMS_DIRNAME}/[^/]+/(#{ITEM_FILE}|#{ALTOS_FILE}|#{ALTO_DIRNAME}/[^/]+\.xml\.gz)\z})
           .map { |path| path.delete_prefix("#{workdir}/") }
           .sort
      end

      def read_json(path, label:)
        JSON.parse(SourceRead.utf8_file(path, label: "nb-no #{label}"))
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable #{label}: #{e.message}"
      end

      def read_alto(path)
        SourceRead.utf8(Zlib.gunzip(File.binread(path)), label: "nb-no ALTO page #{path}")
      rescue Zlib::Error, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable ALTO page: #{e.message}"
      end

      # -- parse internals ---------------------------------------------------

      # The URN:NBN tail ("digibok_2016101048209") keys the document; an
      # item without one falls back to its API id.
      def urn_key(item, id)
        item.dig("metadata", "identifiers", "urn").to_s[/\AURN:NBN:no-nb_(\w+)\z/, 1] || id
      end

      # [[tail, {text:, annotations:}] for every held page with text, the
      # page accounting + the OCR engine for the document metadata].
      def read_pages(workdir, id, ledger)
        blank = []
        software = nil
        listed = page_list(workdir, id)
        pages = listed.filter_map do |tail, _|
          path = page_path(workdir, id, tail)
          next unless File.file?(path)

          page = self.class.flatten_alto(read_alto(path))
          software ||= page[:software] unless page[:software].to_s.empty?
          blank << tail if page[:text].empty?
          [tail, { text: page[:text], annotations: page_annotations(tail, page) }] unless page[:text].empty?
        end
        accounting = { "page_count" => listed.size, "blank_pages" => blank,
                       "ledgered_pages" => Array(ledger["pages"][id]).sort, "ocr_software" => software }
        [pages, accounting.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }]
      end

      def page_annotations(tail, page)
        printed = page[:printed].to_s.strip
        { "page" => tail, "printed_page" => printed.empty? || printed == tail ? nil : printed,
          "ocr_confidence" => page[:confidence] }.compact
      end

      def title_for(meta)
        title = meta["title"].to_s.strip
        title.empty? ? nil : Normalize.nfc(title)
      end

      def metadata_for(item, codes)
        meta = item.fetch("metadata", {})
        ids = meta.fetch("identifiers", {})
        origin = meta.fetch("originInfo", {})
        place, normalized = places(meta)
        out = {
          "text_nature" => "machine-ocr", "ocr_note" => OCR_NOTE,
          "sesam_id" => ids["sesamId"], "urn_nbn" => ids["urn"], "oai_id" => ids["oaiId"],
          "permalink" => ids["urn"] ? format(PERMALINK, ids["urn"]) : nil,
          "license" => item.dig("accessInfo", "license"),
          "languages" => codes, "publisher" => origin["publisher"],
          "place" => place, "place_normalized" => normalized,
          "date" => date_envelope(meta),
          "extent" => meta.dig("physicalDescription", "extent"),
          "statement_of_responsibility" => Array(meta["statementOfResponsibility"]).first,
          "ddc" => meta.dig("classification", "ddc"), "udc" => meta.dig("classification", "udc"),
          "literary_form" => meta["literaryform"]
        }
        out.merge!(people_for(meta))
        facets = facets_for(meta)
        out["facets"] = facets unless facets.empty?
        deep_nfc(out.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) })
      end

      def people_for(meta)
        people = Array(meta["people"]).filter_map do |person|
          name = person["name"].to_s.strip
          next if name.empty?

          { "name" => name, "dates" => person["date"], "roles" => Array(person["roles"]).filter_map { |r| r["name"] },
            "authority" => person["identifier"], "primary" => person["usage"] == "primary" || nil }
            .reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
        end
        authors = people.select { |p| p["primary"] || p["roles"].to_a.intersect?(AUTHOR_ROLES) }.map { |p| p["name"] }
        out = {}
        out["people"] = people unless people.empty?
        out["author"] = authors.join("; ") unless authors.empty?
        out
      end

      def facets_for(meta)
        subject = meta.fetch("subject", {}) || {}
        facets = {
          "genre" => Array(subject["genres"]), "subject" => Array(subject["topics"]),
          "author" => Array(meta["people"]).filter_map { |p| p["name"].to_s.strip.then { |n| n.empty? ? nil : n } },
          "ddc" => Array(meta.dig("classification", "ddc")), "udc" => Array(meta.dig("classification", "udc"))
        }
        facets.transform_values { |values| values.map { |v| v.to_s.strip }.reject(&:empty?).uniq }
              .reject { |_, values| values.empty? }
              .transform_values { |values| { "values" => values } }
      end

      # [the print's own place form, the cataloguer's authority form].
      def places(meta)
        geo = meta.fetch("geographic", {}) || {}
        forms = [geo["placeString"], geo["city"]].map { |value| value.to_s.strip }.reject(&:empty?).uniq
        own = forms.find { |form| !form.match?(AUTHORITY_PLACE) }
        authority = forms.find { |form| form.match?(AUTHORITY_PLACE) }
        [own && unbracket(own), authority]
      end

      # "[Christiania]" → "Christiania"; "Lugduni Batavorum [Leiden]" →
      # "Lugduni Batavorum" (the cataloguer's gloss, not the imprint).
      def unbracket(place)
        whole = place[/\A\[(.+)\]\z/, 1]
        value = whole || place.sub(/\s*\[[^\]]*\]\z/, "")
        value.strip.empty? ? nil : value.strip
      end

      def date_envelope(meta)
        origin = meta.fetch("originInfo", {})
        issued = origin["issued"].to_s
        publication = Array(meta["originInfoTypes"]).find { |type| type["eventType"] == "publication" } || {}
        untouched = publication["issuedUntouched"] || origin["issuedUntouched"]
        issued_years = years_in(issued)
        all = (issued_years + years_in(untouched.to_s)).uniq
        return nil if all.empty?

        raw = untouched.to_s.strip.empty? ? issued : untouched.to_s.strip
        raw = "#{raw} (catalogue: #{issued})" unless (issued_years - years_in(raw)).empty?
        { "not_before" => all.min, "not_after" => all.max, "raw" => raw, "class" => "edition" }
      end

      def years_in(value) = value.scan(/(?<!\d)(1[0-9]{3}|20[0-9]{2})(?!\d)/).flatten.map { |year| Integer(year, 10) }

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Array then value.map { |v| deep_nfc(v) }
        when Hash then value.transform_values { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
