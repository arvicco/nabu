# frozen_string_literal: true

require_relative "otdo_html_parser"
require_relative "../otdo_fetch"

module Nabu
  module Adapters
    # OTDO — Old Tibetan Documents Online (P48-5): 414 critically edited
    # Old Tibetan texts (otdo.aa-ken.jp; Research Institute for Languages
    # and Cultures of Asia and Africa, Tokyo) in Wylie transliteration —
    # the Dunhuang manuscripts (Pelliot tibétain, IOL Tib J, Or.15000,
    # Stein), the imperial-period inscriptions (Zhol, Treaty, Ldan-ma
    # rocks…), and the five Old Zhangzhung texts. A thin composition of
    # the OtdoHtmlParser family with the OtdoFetch page crawl.
    #
    # == The corpus (census 2026-07-28, ~12 polite requests, verified)
    #
    # The /archives catalog is ONE numbered table: 414 rows, one per
    # document, each with a /archives?p=<slug> link, a datatxt[] checkbox
    # and a content summary. Slug prefixes: Or_15000 (234) · Pt (84) ·
    # ITJ (39) · insc (34) · S (18) · OZ (5). Slugs carry apostrophes
    # (insc_'Bis2) and hyphens (ITJ_0737-1). No robots.txt (404).
    #
    # == Identity
    #
    # urn = urn:nabu:otdo:<slug> — the catalog's own document id, also the
    # page's <h2> header. discover mints from the filename; parse
    # cross-checks the in-page header (drift quarantines).
    #
    # == License (P47-s2 scouting, re-verified live 2026-07-28)
    #
    # The /about page's Site Policy: "The materials published on this site
    # is licensed under a Creative Commons Attribution 4.0 International
    # License (CC-BY)" with the CC BY badge linked to
    # creativecommons.org/licenses/by/4.0/deed.en → class attribution.
    #
    # == fetch / sync policy
    #
    # OtdoFetch: one catalog GET (count-assertion defense on the table's
    # own 1..N numbering) + per-slug GETs at 1 req/s (~7 min whole
    # corpus), resume at the file grain, 404-on-a-promised-slug censused
    # (P47-i1), retention via the attic + the mass-deletion breaker.
    # sync_policy: manual, wired: false until the owner-fired first sync.
    class Otdo < Nabu::Adapter
      BASE_URL = "https://otdo.aa-ken.jp"

      MANIFEST = Nabu::SourceManifest.new(
        id: "otdo",
        name: "OTDO — Old Tibetan Documents Online",
        license: "CC BY 4.0 — the site policy (/about): \"The materials published on this " \
                 "site is licensed under a Creative Commons Attribution 4.0 International " \
                 "License (CC-BY)\" (verified 2026-07-28; the P47-s2 scouting reading)",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "otdo-html"
      )

      def self.manifest
        MANIFEST
      end

      # P11-2: no git repo — the probe GETs one stable edition page
      # (reachability only: the live app serves no Last-Modified/ETag, so
      # the ledger pin never drifts from a probe).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "archives?p=Pt_1287",
          zip_url: Nabu::OtdoFetch.record_url(BASE_URL, "Pt_1287"),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::OtdoFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::OtdoFetch::DELAY)
        super()
        @delay = delay
      end

      # One DocumentRef per crawled page file, sorted by urn. A workdir
      # without pages yields nothing (the day-one pre-fetch state); the
      # catalog sidecar never matches.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The persisted catalog sidecar is a content-pattern file discover
      # deliberately skips — an explicit, benign rule, censused here so the
      # accounting never hides it.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, "*.html"))
                     .count { |path| !Nabu::OtdoFetch.record?(File.basename(path)) }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        OtdoHtmlParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired catalog crawl (never in tests — WebMock blocks the
      # network): catalog GET + per-slug page GETs, polite, resumable,
      # non-destructive (attic + breaker).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::OtdoFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::OtdoFetch::Error => e
        raise Nabu::FetchError, "otdo fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        Dir.glob(File.join(workdir, "*.html")).filter_map do |path|
          name = File.basename(path)
          next unless Nabu::OtdoFetch.record?(name)

          match = Nabu::OtdoFetch::RECORD_FILENAME.match(name)
          urn = "#{OtdoHtmlParser::URN_PREFIX}#{match[1]}"
          Nabu::DocumentRef.new(source_id: manifest.id, id: urn, path: File.expand_path(path))
        end.sort_by(&:id)
      end

      def fetch_notes(result)
        base = "archives catalog verified (#{result.manifest_count} documents, #{result.records} pages; " \
               "#{result.fetched} fetched, #{result.cached} already on disk)"
        [base, missing_notes(result.missing), attic_notes(result.atticked)].compact.join("; ")
      end

      # P47-i1 posture: promised-but-missing upstream pages, censused by
      # the fetch — named (first 3) so the tail is honest.
      def missing_notes(missing)
        return nil if missing.empty?

        named = missing.first(3).join(", ")
        tail = missing.size > 3 ? ", …" : ""
        "#{missing.size} promised page#{'s' if missing.size > 1} 404 upstream (#{named}#{tail})"
      end
    end
  end
end
