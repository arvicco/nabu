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
    # == The grant (email thread №21, N. Wasserman 2026-08-30)
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
                 "(thread №21; CC BY-NC-ND terms): local machine only, no redistribution, " \
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

      # The persisted search-index sidecars are content-pattern files
      # discover deliberately skips (benign, by rule); a node page WITHOUT
      # a SEAL no. is a defect — unrecognized, censused prominently.
      def discovery_skips(workdir)
        sidecars = Dir.glob(File.join(workdir, "*.html"))
                      .count { |path| Nabu::SealFetch::INDEX_FILENAME.match?(File.basename(path)) }
        numberless = record_paths(workdir).reject { |path| seal_number(path) }
        DiscoverySkips.new(
          skipped_by_rule: sidecars,
          unrecognized: numberless.size,
          notes: numberless.map { |path| "#{File.basename(path)}: no \"SEAL no.\" field — identity unreadable" }
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
          number = seal_number(path)
          number && [number, path]
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
        number = File.binread(path)[/<h4>\s*SEAL no\.\s*([^<]+)</, 1]
        number&.force_encoding(Encoding::UTF_8)&.strip
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
