# frozen_string_literal: true

require_relative "seal_html_parser"
require_relative "../seal_fetch"

module Nabu
  module Adapters
    # SEAL — Sources of Early Akkadian Literature (P89-3; seal.huji.ac.il;
    # Michael P. Streck & Nathan Wasserman): the edition of record for
    # third/second-millennium Akkadian literature — 1,065 texts (scout
    # census 2026-08-30). A thin composition of the SealHtmlParser family
    # with the SealFetch advanced-search crawl.
    #
    # == The grant (N. Wasserman, by email, 2026-08-30)
    #
    # Local personal-research use ONLY (CC BY-NC-ND terms): local machine,
    # NO redistribution/mirroring/derivative publication, attribution on
    # display, scholarly references by the fixed SEAL number + permanent
    # URL, TEXT ONLY (third-party visual material excluded — the crawl
    # never touches images). license_class research_private: never on a
    # redistribution surface; fixtures live in gitignored local/fixtures/.
    #
    # == Identity
    #
    # urn = urn:nabu:seal:<SEAL no.> — the page's own "SEAL no." field, the
    # citation-stable key the grant names (node ids are NOT SEAL numbers;
    # the node id rides metadata as the permanent URL). discover reads the
    # SEAL no. from each crawled page with a cheap byte scan; a page
    # without one is censused unrecognized, never minted from its node id.
    #
    # == fetch / sync policy
    #
    # SealFetch: ~54 search-page GETs (page count from page 0's own pager)
    # + one GET per listed node page at 1 req/s (~1,120 requests ≈ 20 min
    # first sync), resume at the file grain, retention via the attic + the
    # mass-deletion breaker. sync_policy: manual, wired: false until the
    # owner-fired first sync.
    class Seal < Nabu::Adapter
      BASE_URL = "https://seal.huji.ac.il"

      # The project citation — the grant's attribution condition, verbatim;
      # rides the manifest credit seam and every document's metadata.
      CITATION = "Michael P. Streck and Nathan Wasserman, " \
                 "Sources of Early Akkadian Literature (SEAL), http://seal.huji.ac.il"

      MANIFEST = Nabu::SourceManifest.new(
        id: "seal",
        name: "SEAL — Sources of Early Akkadian Literature",
        license: "Local personal research per N. Wasserman's email grant 2026-08-30 " \
                 "(CC BY-NC-ND terms): local machine only, no redistribution, " \
                 "mirroring or derivative publication; attribution on display; scholarly " \
                 "reference by the fixed SEAL number + permanent URL; text only — " \
                 "third-party visual material excluded, never fetched or stored. " \
                 "Cite: #{CITATION}",
        license_class: "research_private",
        upstream_url: BASE_URL,
        parser_family: "seal-html",
        credit: CITATION
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe GETs the first search page
      # (reachability; the fetch ledger holds the content pin).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "advanced-search?page=0",
          zip_url: Nabu::SealFetch.search_url(BASE_URL, 0),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::SealFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::SealFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per crawled node page carrying a readable SEAL no.,
      # in numeric SEAL-number order. A workdir without pages yields
      # nothing (the day-one pre-fetch state); numberless pages are
      # censused by discovery_skips, never minted.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The censused skip classes (first-sync census 2026-08-30 — the
      # live site holds three numbered series plus text-less entries):
      # - the persisted search-index sidecars (content-pattern files);
      # - SISTER SERIES pages ("DLL no.", "LBPL no.") — the grant names
      #   SEAL, so the ~89 sister texts are HELD OUT pending a widened
      #   blessing, by rule, never minted;
      # - CATALOG-ONLY pages (a SEAL no. but no Text field) — ~474
      #   entries whose editions are not online; nothing to parse.
      # A node page matching NONE of the series is a defect —
      # unrecognized, censused prominently.
      def discovery_skips(workdir)
        sidecars = Dir.glob(File.join(workdir, "*.html"))
                      .count { |path| Nabu::SealFetch::INDEX_FILENAME.match?(File.basename(path)) }
        sisters = 0
        catalog_only = 0
        stubs = 0
        numberless = []
        record_paths(workdir).each do |path|
          bytes = File.binread(path)
          if seal_number_in(bytes)
            if !text_field?(bytes)
              catalog_only += 1
            elsif stub_page?(bytes)
              stubs += 1
            end
          elsif sister_series?(bytes)
            sisters += 1
          else
            numberless << path
          end
        end
        notes = numberless.map { |path| "#{File.basename(path)}: no series number — identity unreadable" }
        notes << "#{sisters} sister-series pages (DLL/LBPL) held out — the grant names SEAL" if sisters.positive?
        notes << "#{catalog_only} catalog-only pages skipped — no online transliteration" if catalog_only.positive?
        notes << "#{stubs} stub pages skipped — Text field holds only a pointer/fragment note" if stubs.positive?
        DiscoverySkips.new(
          skipped_by_rule: sidecars + sisters + catalog_only + stubs,
          unrecognized: numberless.size,
          notes: notes
        )
      end

      def parse(document_ref)
        SealHtmlParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the
      # network): ~54 search-page GETs + per-node page GETs, polite,
      # resumable, non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::SealFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::SealFetch::Error => e
        raise Nabu::FetchError, "seal fetch failed into #{workdir}: #{e.message}"
      end

      private

      def record_paths(workdir)
        Dir.glob(File.join(workdir, Nabu::SealFetch::RECORDS_DIR, "*.html"))
           .select { |path| Nabu::SealFetch.record?(File.basename(path)) }
      end

      def document_refs(workdir)
        pages = record_paths(workdir).filter_map do |path|
          bytes = File.binread(path)
          number = seal_number_in(bytes)
          # sisters / catalog-only / stubs skip by rule (discovery_skips)
          next unless number && text_field?(bytes) && !stub_page?(bytes)

          [number, path]
        end
        pages.sort_by { |number, _path| sort_key(number) }.map do |number, path|
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{SealHtmlParser::URN_PREFIX}#{number}",
                                path: File.expand_path(path))
        end
      end

      # The cheap discover-time identity scan: the page's own "SEAL no."
      # heading, read from raw bytes (the pattern is ASCII; the number
      # itself is digits). Parse re-reads it properly and cross-checks.
      def seal_number(path)
        seal_number_in(File.binread(path))
      end

      def seal_number_in(bytes)
        number = bytes[/<h4>\s*SEAL no\.\s*([^<]+)</, 1]
        number&.force_encoding(Encoding::UTF_8)&.strip
      end

      # The site's sister series (first-sync census): DLL and LBPL pages
      # ride the same search listing but number their texts in their own
      # id spaces.
      def sister_series?(bytes)
        bytes.match?(/<h4>\s*(?:DLL|LBPL) no\./)
      end

      # The Text-field byte needle: the class TOKEN with its trailing
      # space, so `field--name-field-texts-hierarchy` (present on every
      # page) can never false-positive.
      def text_field?(bytes)
        bytes.include?("field--name-field-text ")
      end

      # A STUB Text field (first-sync census): no tables, fewer than the
      # parser's fallback threshold of paragraphs, and NO line-labeled
      # paragraph — an external pointer ("ARET 5, 5 from Ebla Digital
      # Archives") or a bare fragment note. Nothing to parse; skipped by
      # rule, never quarantined. Conservative on purpose: any table, ≥3
      # paragraphs, or one label-led line (node 7044's one-line fragment
      # is a REAL text) goes to the parser.
      def stub_page?(bytes)
        start = bytes.index("field--name-field-text ")
        return false unless start

        stop = bytes.index('<div id="tabs-3"', start) || bytes.length
        segment = bytes[start...stop].dup.force_encoding(Encoding::UTF_8)
        return false unless segment.scan("<table").empty?
        return false if segment.scan("<p").size >= SealHtmlParser::MIN_FALLBACK_PARAGRAPHS

        segment.split(/<p[ >]/).drop(1).none? do |chunk|
          text = chunk.gsub(/<[^>]+>/, " ").gsub("&nbsp;", " ").strip
          text.match?(/\A[A-Za-z]?\d+[ʹ′']*\s+\S/)
        end
      end

      # Numeric SEAL numbers sort numerically; any non-numeric stranger
      # sorts after them, lexically — visible, never crashing discover.
      def sort_key(number)
        number.match?(/\A\d+\z/) ? [0, Integer(number, 10), number] : [1, 0, number]
      end

      def fetch_notes(result)
        base = "#{result.pages} search pages verified (#{result.manifest_count} texts; " \
               "#{result.fetched} fetched, #{result.cached} already on disk)"
        [base, missing_notes(result.missing), attic_notes(result.atticked)].compact.join("; ")
      end

      # P47-i1 posture: listed-but-missing upstream pages, censused by the
      # fetch — named (first 3) so the tail is honest.
      def missing_notes(missing)
        return nil if missing.empty?

        named = missing.first(3).join(", ")
        tail = missing.size > 3 ? ", …" : ""
        "#{missing.size} listed page#{'s' if missing.size > 1} 404 upstream (node #{named}#{tail})"
      end
    end
  end
end
