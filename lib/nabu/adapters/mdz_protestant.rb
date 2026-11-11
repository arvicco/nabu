# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "nokogiri"

require_relative "../paced_crawl"
require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../normalize"

module Nabu
  module Adapters
    # mdz-protestant (02-sources row 243): the 16th-century Slovene
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
    # == The paced, resumable crawl (the paced-crawl rail, architecture §19)
    #
    # The hOCR API is rate limited (x-ratelimit-limit 5001 per window,
    # censused 2026-10-11; MDZ documents a 24 h quota). Per sync: the six
    # manifests (re-read, written only when changed), then one page lane
    # per object on Nabu::PacedCrawl, in seed order, under ONE budget of
    # SLICE requests. A lane's universe is its manifest's canvas numbers;
    # held = <bsb>/hocr/<page>.hocr on disk; the engine owns selection,
    # pacing (DELAY between requests), the timeout policy and the ledger.
    # Terminal answers are ledgered in .mdz-crawl.json and never retried:
    # a 404 "missing", 401/403/410 "denied", a 200 with an empty body
    # "empty" (never written), a page timing out TIMEOUT_ATTEMPTS times
    # "timeout-stuck". The clean stop (Outcome.halt — never raising, the
    # page stays selectable, the next sync continues): a 429, or the
    # remaining quota read off a good answer's x-ratelimit-remaining
    # falling to RATE_FLOOR — that page is kept and the NEXT ask halts
    # without a request, across objects, since the quota is the API's.
    # Each lane's LedgerCodec reads and writes only its own object's
    # entry in the shared per-object maps ({"missing": {bsb: [pages]}},
    # the hand-rolled crawl's shape), every other object passing through.
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
      TIMEOUT_ATTEMPTS = 3
      TIMEOUT_BACKOFF = 5.0
      MISSING_STATUSES = [404].freeze
      DENIED_STATUSES = [401, 403, 410].freeze
      RATE_LIMITED = 429
      TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i
      STUCK = "timeout-stuck"

      # One object's page lane ledger on disk: every class is a map
      # {bsb => [pages]} shared by all the objects' lanes (the hand-rolled
      # crawl wrote "missing" so); the codec owns only its object's entry
      # and passes every other object and section through. A page id in
      # canonical integer form is stored as a number, anything else
      # verbatim (the codec is total and lossless).
      class LedgerCodec
        CLASSES = ["missing", "denied", "empty", STUCK].freeze
        # Always written, as the hand-rolled crawl did.
        STANDING = "missing"
        INTEGER = /\A(?:0|[1-9]\d*)\z/

        attr_reader :object

        def initialize(object)
          @object = object.to_s
        end

        def load(raw)
          CLASSES.to_h do |klass|
            section = raw[klass]
            [klass, (section.is_a?(Hash) ? Array(section[object]) : []).to_set(&:to_s)]
          end
        end

        def dump(classes, raw)
          doc = raw.dup
          CLASSES.each do |klass|
            section = raw[klass].is_a?(Hash) ? raw[klass].dup : {}
            ids = classes.fetch(klass, [])
            ids.empty? ? section.delete(object) : section[object] = encode(ids)
            next unless klass == STANDING || !section.empty? || raw.key?(klass)

            doc[klass] = section.sort.to_h
          end
          doc
        end

        private

        def encode(ids)
          ids.map { |id| id.match?(INTEGER) ? Integer(id, 10) : id }
             .uniq.sort_by { |page| page.is_a?(Integer) ? [0, page, ""] : [1, 0, page] }
        end
      end

      # The lanes' declared schedule: the rail's default (two syncs cover
      # the census; a phase spends at most a few slices).
      PAGE_SCHEDULE = Nabu::PacedCrawl::Schedule.new(cadence: :per_phase, slices_per_phase: 3,
                                                     stop_after_zero_slices: 3)

      # One object's page lane (see the header).
      def self.page_crawl_spec(bsb)
        Nabu::PacedCrawl::Spec.new(
          name: bsb, ledger_file: LEDGER_FILE,
          classes: { denied: "denied", empty: "empty", timeout: STUCK }, subclasses: { denied: ["missing"] },
          delay: DELAY, slice: SLICE, timeout_attempts: TIMEOUT_ATTEMPTS, timeout_backoff: TIMEOUT_BACKOFF,
          codec: LedgerCodec.new(bsb), schedule: PAGE_SCHEDULE
        )
      end

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

      def initialize(delay: DELAY, slice: SLICE, http: Nabu::ZipFetch.default_http, seeds: SEEDS,
                     backoff: TIMEOUT_BACKOFF)
        super()
        @delay = delay
        @slice = slice
        @http = http
        @seeds = seeds
        @backoff = backoff
        @last_request_at = nil
        @quota_halt = nil
      end

      # -- fetch -------------------------------------------------------------

      # +force+ is part of the fetch interface; nothing here ever deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        @seeds.each { |seed| refresh_manifest!(workdir, seed.id) }
        reports = crawl_slices!(workdir, progress)
        ledger = ledger_view(workdir)
        notes = crawl_notes(workdir, ledger, reports)
        progress&.call("#{notes}\n")
        notes = [notes, *reports.select { |report| active?(report) }.flat_map(&:lines)].join("; ")
        Nabu::FetchReport.new(sha: crawl_sha(workdir, ledger), fetched_at: Time.now, notes: notes)
      end

      # The chain runner's seam (rake crawl:chain): one page lane per
      # object, in seed order.
      def paced_crawls(workdir, progress: nil)
        @seeds.to_h { |seed| [seed.id, page_crawl(workdir, seed.id, progress: progress)] }
      end

      # Object +bsb+'s page lane over +workdir+ (its spec retuned by this
      # instance's knobs; +slice+ overrides the budget). Public so an
      # offline surface can #diagnose the crawl without crawling.
      def page_crawl(workdir, bsb, progress: nil, slice: @slice)
        Nabu::PacedCrawl::Engine.new(
          spec: self.class.page_crawl_spec(bsb).with(delay: @delay, slice: slice, timeout_backoff: @backoff),
          dir: workdir, progress: progress,
          universe: -> { page_universe(workdir, bsb) },
          held: ->(page) { File.file?(page_path(workdir, bsb, Integer(page, 10))) },
          fetch_one: ->(page) { fetch_page!(workdir, bsb, Integer(page, 10)) }
        )
      end

      # -- discover ----------------------------------------------------------

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ledger = ledger_view(workdir)
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
        ledger = ledger_view(workdir)
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

      # Every object's lane in seed order under ONE budget of @slice
      # requests; a clean stop ends the sync's crawl (the quota is the
      # API's, not the object's).
      def crawl_slices!(workdir, progress)
        @quota_halt = nil
        budget = @slice
        reports = []
        @seeds.each do |seed|
          break if budget <= 0

          report = page_crawl(workdir, seed.id, progress: progress, slice: budget).slice!
          reports << report
          report.lines.each { |line| progress&.call("#{line}\n") } if active?(report)
          budget -= report.attempted
          break if report.halted?
        end
        reports
      end

      # A slice that asked something or stopped — a complete object's
      # cone-exhausted slice says nothing worth a line.
      def active?(report) = report.attempted.positive? || report.halted?

      # The object's canvas numbers, manifest order (none before its
      # manifest is on disk).
      def page_universe(workdir, bsb)
        path = manifest_path(workdir, bsb)
        File.file?(path) ? canvas_pages(read_manifest(path)).map(&:to_s) : []
      end

      # One hOCR GET → a PacedCrawl::Outcome. The quota floor seen on an
      # earlier answer halts at once, without a request. An already-held
      # page (the engine's held-id re-probe) is never overwritten.
      def fetch_page!(workdir, bsb, page)
        return @quota_halt if @quota_halt

        response = get(format(OCR_URL, bsb, page),
                       accept: [200, RATE_LIMITED, *MISSING_STATUSES, *DENIED_STATUSES])
        return rate_limited(response) if response.status == RATE_LIMITED
        return page_outcome(:denied, response, ledger_class: "missing") if MISSING_STATUSES.include?(response.status)
        return page_outcome(:denied, response) if DENIED_STATUSES.include?(response.status)

        body = response.body.to_s
        return page_outcome(:empty, response) if body.strip.empty?

        write_page!(workdir, bsb, page, body)
        note_quota!(bsb, page, response)
        page_outcome(:ok, response)
      rescue Nabu::FetchError => e
        raise unless e.message.match?(TIMEOUT_PATTERN)

        Nabu::PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: Nabu::PacedCrawl.body_head(e.message) })
      end

      # The remaining quota at RATE_FLOOR: this page is kept, the next ask
      # is the clean stop. An unreadable header reads as no floor.
      def note_quota!(bsb, page, response)
        remaining = Integer(response.headers["x-ratelimit-remaining"].to_s, 10)
        return if remaining > RATE_FLOOR

        @quota_halt = Nabu::PacedCrawl::Outcome.halt(
          reason: "quota floor", evidence: { after: "#{bsb}:#{page}", remaining: remaining, floor: RATE_FLOOR }
        )
      rescue ArgumentError
        nil
      end

      def rate_limited(response)
        Nabu::PacedCrawl::Outcome.halt(reason: "HTTP 429 (rate limited)",
                                       evidence: { http_status: response.status,
                                                   remaining: response.headers["x-ratelimit-remaining"] }.compact)
      end

      def page_outcome(status, response, ledger_class: nil)
        Nabu::PacedCrawl::Outcome.from_body(status, http_status: response.status, body: response.body,
                                                    ledger_class: ledger_class)
      end

      def write_page!(workdir, id, page, body)
        target = page_path(workdir, id, page)
        return if File.file?(target)

        FileUtils.mkdir_p(File.dirname(target))
        File.binwrite("#{target}.tmp", body)
        File.rename("#{target}.tmp", target)
      end

      # Request STARTS are spaced DELAY apart (latency counts toward the
      # pause): the manifests and the page lanes share one pace.
      def get(url, accept: [200, 404, 429])
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

      def crawl_notes(workdir, ledger, reports)
        total = 0
        held = 0
        @seeds.each do |seed|
          next unless File.file?(manifest_path(workdir, seed.id))

          pages = canvas_pages(read_manifest(manifest_path(workdir, seed.id)))
          total += pages.size
          held += pages.size - missing_pages(workdir, seed.id, ledger).size
        end
        stop = if reports.any?(&:halted?) || @quota_halt then :rate_limited
               elsif held < total && reports.sum(&:attempted) >= @slice then :slice
               end
        reason = { slice: "slice limit reached", rate_limited: "rate limit reached — resume next sync" }[stop]
        ["crawl at #{held}/#{total} page(s) (+#{reports.sum(&:ok)} this sync)", reason].compact.join("; ")
      end

      def crawl_sha(workdir, ledger)
        parts = @seeds.map do |seed|
          path = manifest_path(workdir, seed.id)
          manifest_sha = File.file?(path) ? Digest::SHA256.file(path).hexdigest : ""
          pages = Dir.glob(File.join(workdir, seed.id, HOCR_DIR, "*.hocr")).map { |f| File.basename(f) }.sort
          [seed.id, manifest_sha, pages]
        end
        Digest::SHA256.hexdigest(JSON.generate([parts, ledger]))
      end

      # Every ledger class, read through each object's codec:
      # {bsb => sorted ledgered pages} (objects with none left out — the
      # hand-rolled crawl's "missing" map shape, so an unchanged ledger
      # keeps its crawl sha). An unreadable ledger reads blank, as the
      # engine reads it.
      def ledger_view(workdir)
        path = File.join(workdir, LEDGER_FILE)
        raw = File.file?(path) ? JSON.parse(File.read(path)) : {}
        raw = {} unless raw.is_a?(Hash)
        objects = LedgerCodec::CLASSES.flat_map { |klass| raw[klass].is_a?(Hash) ? raw[klass].keys : [] }.uniq
        view = objects.sort.to_h do |bsb|
          ids = LedgerCodec.new(bsb).load(raw).values.reduce(Set.new, :|)
          [bsb, ids.filter_map { |id| Integer(id, 10) if id.match?(LedgerCodec::INTEGER) }.sort]
        end
        view.reject { |_, pages| pages.empty? }
      rescue JSON::ParserError
        {}
      end

      # -- shared internals --------------------------------------------------

      def manifest_path(workdir, id) = File.join(workdir, id, MANIFEST_FILE)

      def page_path(workdir, id, page) = File.join(workdir, id, HOCR_DIR, format("%05d.hocr", page))

      def missing_pages(workdir, id, ledger)
        path = manifest_path(workdir, id)
        return [] unless File.file?(path)

        ledgered = ledger.fetch(id, [])
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
