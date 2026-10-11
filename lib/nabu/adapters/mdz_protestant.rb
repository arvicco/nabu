# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"

require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # mdz-protestant (Q102, 02-sources row 243): the 16th-century Slovene
    # (and Latin-script Croatian) Protestant prints held by the Bayerische
    # Staatsbibliothek and served by the Münchener DigitalisierungsZentrum
    # (MDZ, digitale-sammlungen.de) — Trubar's 1562 Articuli, Dalmatin's
    # 1575 Sirah and the 1584 Wittenberg catechism/hymnal and prayer book,
    # Bohorič's 1584 Arcticae horulae (the first Slovene grammar) and the
    # Urach press's Latin-script Croatian Spovid (Tübingen 1564).
    #
    # == OCR LAYER, NOT AN EDITION (declared)
    #
    # The text is MDZ's own uncorrected page OCR, served per page as hOCR
    # (api.digitale-sammlungen.de/ocr/<bsb>/<page>) and linked from every
    # IIIF canvas (seeAlso "OCR"). It is a machine reading of 16th-century
    # type — long s, ligatures, misread diacritics and margin furniture
    # ride as recognized. Every document carries text_nature
    # "machine-ocr"; nothing is corrected (canonical means canonical).
    # The one rule: the BSB scan-target label (a digits-only line in the
    # top-left scan margin, bbox x=0 — "00077342", "000") is not print
    # text; it moves out of the passage into annotations "scan_label".
    #
    # == The cone — a CURATED seed, censused 2026-10-11
    #
    # MDZ has no "Slovene Protestant prints" collection; the cone is the
    # objects the census found (MDZ search API, metadata handler, queries
    # Trubar / Dalmatin / Bohorič / Krell / Juričič / Ungnad / Windisch /
    # inu, 1550–1620) whose page OCR is LEGIBLE LATIN-SCRIPT TEXT, one
    # page sampled per object. OUT, declared: the Urach press's Glagolitic
    # and Cyrillic prints (14 objects — Tabla za dicu 1561, the 1562/63
    # New Testament, the Artikuli/Confessio, Postila, Katekizam, Crikveni
    # ordinalic …): MDZ's Latin-trained OCR returns noise on both scripts
    # (sampled: mixed Cyrillic/Tamil/Thai glyph salad), so ingesting it
    # would mint garbage passages — a future HTR lane, not this adapter.
    # OUT: the Catholic 1613 Graz Evangelia inu lystuvi (outside the
    # Protestant cone; a widening is a phase decision). OUT: Megiser's
    # Dictionarium quatuor linguarum (Graz 1592, both copies NoC-NC) — a
    # four-column dictionary whose page OCR interleaves German/Latin/
    # Slovene/Italian; as running text it would claim one language for
    # four. It belongs on a dictionary shelf with column parsing (queued).
    # Dalmatin's 1584 Bible is not at MDZ (it lives at NUK/dLib).
    #
    # == License — per object, from the manifest
    #
    # The PDM objects (manifest license
    # https://creativecommons.org/publicdomain/mark/1.0/ — "may be copied,
    # modified, distributed … including for commercial purposes") are the
    # source's open class. Two seed objects are Google-digitized copies
    # under rightsstatements.org NoC-NC 1.0 (No Copyright — Non-Commercial
    # Use Only): they ride the SAME adapter as per-document
    # license_override "nc" (the glaux per-text override precedent) — the
    # manifest's own license field decides, never the seed.
    #
    # == The paced, resumable crawl (the ndl-kotenseki mold)
    #
    # The hOCR API is rate limited (x-ratelimit-limit 5001 per window,
    # censused 2026-10-11; MDZ documents a 24 h quota). The crawl: per
    # sync, the six manifests (re-read, written only when changed) then
    # up to SLICE missing pages, DELAY seconds apart, resuming at the file
    # grain (<bsb>/hocr/<page>.hocr on disk is done). It stops cleanly —
    # never raising — when the server says 429 or the remaining quota
    # falls to RATE_FLOOR, and the next sync continues. A page the API
    # answers 404 is ledgered in .mdz-crawl.json and never retried.
    # Census: 1,551 pages across the six objects → two syncs at SLICE
    # 800 (~15 min each at 1 req/s plus latency).
    #
    # == Documents
    #
    # One document per object, discovered only once its crawl is COMPLETE
    # (every canvas has its hOCR or a ledgered 404) — a partial object
    # never mints a partial document (discovery_skips names it). urn =
    # urn:nabu:mdz-protestant:<bsb id>; one passage per canvas with text,
    # cited by the canvas number (…:bsb00078189:79), lines joined by "\n";
    # annotations carry the canvas page label ("(0079)", "74 (0076)").
    #
    # == Axes
    #
    # date — the manifest's Date (every 4-digit year; "[1562]" brackets
    # and prose kept raw) → {not_before, not_after, raw}. place — the
    # imprint place (Published before " : ", brackets stripped:
    # "V Tibingi", "Witenberga", "Lublani", "Tubingae") — named, the
    # print's own spelling. author/contributors (GND links stripped to
    # name + gnd id), VD16 number, shelfmark, URN:NBN, the MDZ details
    # permalink, the manifest license. Language per seed object (sl /
    # hrv) — MDZ itself says "Not identified" for two of the Slovene
    # prints; orthography "bohoričica" is declared for the 1584
    # Wittenberg prints (Bohorič's alphabet, codified in the same year's
    # grammar), never for Trubar's 1562 or Dalmatin's 1575 spelling.
    class MdzProtestant < Nabu::Adapter
      MANIFEST_URL = "https://api.digitale-sammlungen.de/iiif/presentation/v2/%s/manifest"
      OCR_URL = "https://api.digitale-sammlungen.de/ocr/%s/%d"
      URN_PREFIX = "urn:nabu:mdz-protestant:"
      LEDGER_FILE = ".mdz-crawl.json"
      MANIFEST_FILE = "manifest.json"
      HOCR_DIR = "hocr"

      # Polite pacing: 1 req/s, well inside the censused quota. Never lower.
      DELAY = 1.0
      # Pages per sync (one slice of the crawl).
      SLICE = 800
      # Stop the slice when the server's remaining quota falls this low.
      RATE_FLOOR = 50

      PDM = "https://creativecommons.org/publicdomain/mark/1.0/"
      NC_LICENSES = ["https://rightsstatements.org/vocab/NoC-NC/1.0/"].freeze

      Seed = Data.define(:id, :language, :orthography)

      # The censused cone (2026-10-11; canvases in parentheses).
      SEEDS = [
        Seed.new(id: "bsb00078189", language: "sl", orthography: nil),          # Trubar, Articuli 1562 (237)
        Seed.new(id: "bsb11302253", language: "sl", orthography: nil),          # Dalmatin, Sirah 1575, NoC-NC (228)
        Seed.new(id: "bsb00077342", language: "sl", orthography: "bohoričica"), # Ta celi catehismus 1584 (318)
        Seed.new(id: "bsb00077343", language: "sl", orthography: "bohoričica"), # Karszhanske lepe molitve 1584 (264)
        Seed.new(id: "bsb00078823", language: "sl", orthography: "bohoričica"), # Bohorič, Arcticae horulae 1584 (288)
        Seed.new(id: "bsb10206655", language: "hrv", orthography: nil)          # Spovid, Tübingen 1564, NoC-NC (216)
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "mdz-protestant",
        name: "MDZ — 16th-century Slovene/Croatian Protestant prints, page OCR (Bayerische Staatsbibliothek)",
        license: "Public Domain Mark 1.0 per IIIF manifest (MDZ: \"may be copied, modified, distributed … " \
                 "including for commercial purposes\"); two Google-digitized copies are rightsstatements.org " \
                 "NoC-NC 1.0 → per-document license_override nc. Credit: Bayerische Staatsbibliothek / MDZ; " \
                 "the text is MDZ's uncorrected OCR layer, not an edition",
        license_class: "open",
        upstream_url: "https://www.digitale-sammlungen.de/",
        parser_family: "mdz-hocr"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Trubar 1562 IIIF manifest", zip_url: format(MANIFEST_URL, SEEDS.first.id),
          metadata_url: nil, state_subdir: "", liveness_only: true
        )]
      end

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http, seeds: SEEDS)
        super()
        @delay = delay
        @slice = slice
        @http = http
        @seeds = seeds
        @requests = 0
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        ledger = read_ledger(workdir)
        @seeds.each { |seed| refresh_manifest!(workdir, seed.id) }
        crawled, stop = crawl_slice!(workdir, ledger, progress)
        write_ledger!(workdir, ledger)
        notes = crawl_notes(workdir, ledger, crawled, stop)
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, ledger), fetched_at: Time.now, notes: notes)
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ledger = read_ledger(workdir)
        @seeds.each do |seed|
          path = manifest_path(workdir, seed.id)
          next unless File.file?(path) && missing_pages(workdir, seed.id, ledger).empty?

          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{seed.id}",
                       path: File.expand_path(path),
                       metadata: { "bsb" => seed.id, "language" => seed.language,
                                   "orthography" => seed.orthography }.compact
                     ))
        end
      end

      def discovery_skips(workdir)
        ledger = read_ledger(workdir)
        notes = @seeds.filter_map do |seed|
          next unless File.file?(manifest_path(workdir, seed.id))

          missing = missing_pages(workdir, seed.id, ledger).size
          "crawl incomplete: #{seed.id} (#{missing} page(s) to go)" if missing.positive?
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size, notes: notes)
      end

      # -- parse -------------------------------------------------------------

      def parse(document_ref)
        iiif = read_manifest(document_ref.path)
        language = document_ref.metadata.fetch("language")
        license = iiif["license"].to_s
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: title_for(iiif),
          canonical_path: document_ref.path,
          metadata: metadata_for(iiif, document_ref.metadata),
          license_override: NC_LICENSES.include?(license) ? "nc" : nil
        )
        append_pages(document, document_ref, iiif, language)
        raise ParseError, "#{document_ref.path}: no page carries OCR text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # -- fetch internals ---------------------------------------------------

      def refresh_manifest!(workdir, id)
        response = get(format(MANIFEST_URL, id))
        unless response.status == 200
          raise Nabu::FetchError, "mdz-protestant: manifest #{id} answered HTTP #{response.status}"
        end

        body = response.body.to_s
        JSON.parse(body)
        path = manifest_path(workdir, id)
        return if File.file?(path) && File.binread(path) == body

        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.tmp", body)
        File.rename("#{path}.tmp", path)
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "mdz-protestant: manifest #{id} is not JSON: #{e.message}"
      end

      # Returns [pages fetched, stop reason or nil].
      def crawl_slice!(workdir, ledger, progress)
        crawled = 0
        @seeds.each do |seed|
          missing_pages(workdir, seed.id, ledger).each do |page|
            return [crawled, :slice] if crawled >= @slice

            case fetch_page!(workdir, seed.id, page)
            when :ok then crawled += 1
            when :ok_at_floor then return [crawled + 1, :rate_limited]
            when :missing then (ledger["missing"][seed.id] ||= []) << page
            when :rate_limited then return [crawled, :rate_limited]
            end
            progress&.call("crawl: +#{crawled} page(s)…\n") if crawled.positive? && (crawled % 50).zero?
          end
        end
        [crawled, nil]
      end

      def fetch_page!(workdir, id, page)
        response = get(format(OCR_URL, id, page))
        case response.status
        when 404 then return :missing
        when 429 then return :rate_limited
        end
        write_page!(workdir, id, page, response.body.to_s)
        remaining = response.headers["x-ratelimit-remaining"]
        remaining && Integer(remaining, 10) <= RATE_FLOOR ? :ok_at_floor : :ok
      rescue ArgumentError
        :ok
      end

      def write_page!(workdir, id, page, body)
        target = page_path(workdir, id, page)
        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
      end

      def get(url)
        sleep(@delay) if @delay.positive? && @requests.positive?
        @requests += 1
        response, = Nabu::RedirectFollow.get(
          url, http: @http, error: Nabu::FetchError, accept: [200, 404, 429],
               headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }
        )
        response
      end

      def crawl_notes(workdir, ledger, crawled, stop)
        total = 0
        held = 0
        @seeds.each do |seed|
          next unless File.file?(manifest_path(workdir, seed.id))

          pages = canvas_pages(read_manifest(manifest_path(workdir, seed.id)))
          total += pages.size
          held += pages.size - missing_pages(workdir, seed.id, ledger).size
        end
        reason = { slice: "slice limit reached", rate_limited: "rate limit reached — resume next sync" }[stop]
        ["crawl at #{held}/#{total} page(s) (+#{crawled} this sync)", reason].compact.join("; ")
      end

      def crawl_sha(workdir, ledger)
        parts = @seeds.map do |seed|
          path = manifest_path(workdir, seed.id)
          manifest_sha = File.file?(path) ? Digest::SHA256.file(path).hexdigest : ""
          pages = Dir.glob(File.join(workdir, seed.id, HOCR_DIR, "*.hocr")).map { |f| File.basename(f) }.sort
          [seed.id, manifest_sha, pages]
        end
        Digest::SHA256.hexdigest(JSON.generate([parts, ledger["missing"]]))
      end

      def read_ledger(workdir)
        path = File.join(workdir, LEDGER_FILE)
        return { "missing" => {} } unless File.file?(path)

        { "missing" => JSON.parse(File.read(path)).fetch("missing", {}) }
      rescue JSON::ParserError
        { "missing" => {} }
      end

      def write_ledger!(workdir, ledger)
        missing = ledger["missing"].transform_values { |pages| pages.uniq.sort }.sort.to_h
        File.write(File.join(workdir, LEDGER_FILE), JSON.pretty_generate({ "missing" => missing }))
      end

      # -- shared internals --------------------------------------------------

      def manifest_path(workdir, id) = File.join(workdir, id, MANIFEST_FILE)

      def page_path(workdir, id, page) = File.join(workdir, id, HOCR_DIR, format("%05d.hocr", page))

      def missing_pages(workdir, id, ledger)
        path = manifest_path(workdir, id)
        return [] unless File.file?(path)

        ledgered = Array(ledger.dig("missing", id))
        canvas_pages(read_manifest(path)).reject do |page|
          ledgered.include?(page) || File.file?(page_path(workdir, id, page))
        end
      end

      def read_manifest(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError, Errno::ENOENT => e
        raise ParseError, "#{path}: unreadable IIIF manifest: #{e.message}"
      end

      def canvases(iiif) = Array(iiif.dig("sequences", 0, "canvases"))

      def canvas_page(canvas) = canvas["@id"].to_s[%r{/canvas/(\d+)\z}, 1]&.to_i

      def canvas_pages(iiif) = canvases(iiif).filter_map { |canvas| canvas_page(canvas) }

      # -- parse internals ---------------------------------------------------

      def append_pages(document, document_ref, iiif, language)
        workdir = File.dirname(document_ref.path, 2)
        id = document_ref.metadata.fetch("bsb")
        canvases(iiif).each do |canvas|
          page = canvas_page(canvas) or next
          path = page_path(workdir, id, page)
          next unless File.file?(path)

          lines, scan_label = page_lines(path)
          next if lines.empty?

          annotations = { "canvas" => page, "page_label" => canvas["label"].to_s }
          annotations["scan_label"] = scan_label if scan_label
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{page}", language: language,
            text: Normalize.nfc(lines.join("\n")), sequence: document.size,
            annotations: annotations
          )
        end
      end

      # [text lines in reading order, the scan-target label or nil].
      def page_lines(path)
        hocr = Nokogiri::XML(File.read(path))
        hocr.remove_namespaces!
        scan_label = nil
        lines = hocr.xpath("//span[@class='ocr_line']").filter_map do |line|
          text = line.text.gsub(/[[:space:]]+/, " ").strip
          next if text.empty?

          if scan_label.nil? && scan_label?(line, text)
            scan_label = text
            next
          end
          text
        end
        [lines, scan_label]
      end

      # The BSB scan-target strip: a digits-only line hugging the left
      # scan edge (bbox x0 = 0).
      def scan_label?(line, text)
        text.match?(/\A\d+\z/) && line["title"].to_s.match?(/\bbbox 0 \d+/)
      end

      def title_for(iiif)
        label = meta_value(iiif, "Title") || iiif["label"].to_s
        label.empty? ? nil : Normalize.nfc(label)
      end

      def metadata_for(iiif, ref_meta)
        meta = {
          "text_nature" => "machine-ocr",
          "bsb" => ref_meta["bsb"],
          "orthography" => ref_meta["orthography"],
          "license" => iiif["license"],
          "permalink" => related(iiif, "Details"),
          "opac" => related(iiif, "OPAC"),
          "statement_of_responsibility" => meta_value(iiif, "By"),
          "imprint" => meta_value(iiif, "Published"),
          "shelfmark" => meta_value(iiif, "Call number"),
          "urn_nbn" => strip_html(meta_value(iiif, "URN")),
          "vd16" => meta_values(iiif, "Identifier").map { |v| strip_html(v) }.find { |v| v.start_with?("VD16") },
          "canvas_count" => canvases(iiif).size
        }
        meta.merge!(people(iiif))
        meta["place"] = imprint_place(meta["imprint"])
        meta["date"] = date_envelope(meta_value(iiif, "Date"))
        meta.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      def people(iiif)
        creators = meta_values(iiif, "Creator").map { |value| person(value) }
        contributors = meta_values(iiif, "Contributor").map { |value| person(value) }
        out = {}
        out["author"] = creators.map { |p| p["name"] }.join("; ") unless creators.empty?
        out["creators"] = creators unless creators.empty?
        out["contributors"] = contributors unless contributors.empty?
        out
      end

      # "Trubar, Primož, 1508-1586 -- (GND: <a …>118761005</a>)" →
      # {"name" => "Trubar, Primož, 1508-1586", "gnd" => "118761005"}.
      def person(value)
        name, gnd = value.to_s.split(" -- ", 2)
        { "name" => Normalize.nfc(name.to_s.strip), "gnd" => strip_html(gnd.to_s)[/\d[\dX-]+/] }.compact
      end

      def imprint_place(imprint)
        return nil if imprint.nil?

        place = imprint.split(" : ").first.to_s.delete("[]").strip
        place.empty? || place.casecmp?("s.l.") ? nil : place
      end

      def date_envelope(raw)
        return nil if raw.nil?

        years = raw.scan(/\b(1[0-9]{3})\b/).flatten.map { |year| Integer(year, 10) }
        return nil if years.empty?

        { "not_before" => years.min, "not_after" => years.max, "raw" => raw }
      end

      def related(iiif, label)
        Array(iiif["related"]).find { |entry| entry["label"] == label }&.fetch("@id", nil)
      end

      def meta_values(iiif, label)
        Array(iiif["metadata"]).select { |entry| english(entry["label"]) == label }
                               .map { |entry| english(entry["value"]) }
      end

      def meta_value(iiif, label) = meta_values(iiif, label).first

      def english(value)
        return value.to_s unless value.is_a?(Array)

        (value.find { |v| v["@language"] == "en" } || value.first || {})["@value"].to_s
      end

      def strip_html(value)
        return nil if value.nil?

        Nokogiri::HTML.fragment(value).text.strip
      end
    end
  end
end
