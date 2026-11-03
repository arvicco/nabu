# frozen_string_literal: true

require_relative "aio_record_parser"
require_relative "../aio_fetch"

module Nabu
  module Adapters
    # AIO — Attic Inscriptions Online (P154; www.atticinscriptions.com;
    # British School at Athens, ed. Stephen Lambert): English translations
    # of the inscriptions of Attica — decrees, laws, dedications, funerary
    # monuments, accounts, ephebic lists — with AIO's own Greek editions for
    # the AIO/AIUK papers. A thin composition of the AioRecordParser family
    # with the AioFetch REST-listing crawl.
    #
    # == License (first-hand, 2026-11-02)
    #
    # Every inscription page carries the CC badge <a rel="license"
    # href="http://creativecommons.org/licenses/by-sa/3.0/deed.en_GB"> (alt
    # "Creative Commons Licence") on BOTH the translation view and the
    # ?text_type=greek view; the REST API's own per-record field is IPR:
    # "Creative Commons". No page states a different term → CC BY-SA 3.0,
    # license_class attribution. Images are never fetched.
    #
    # == Grains (enumerated 2026-11-02 against the live site + the Swagger spec)
    #
    #   listing page   list_all_inscriptions.json?page=n — the manifest;
    #                  persisted as list-page-<n>.json sidecars, SKIPPED BY
    #                  RULE at discover (counted in discovery_skips).
    #   API record     <path>.json — references, title, translators, the
    #                  Base64 EpiDoc texts.           } TOGETHER the record =
    #   inscription    <path> — Date, Monument/Inscription } the document
    #   page           type, Original location, Findspot, footnotes.
    #   Greek view     <path>?text_type=greek — never fetched (the API record
    #                  carries the same Greek as EpiDoc).
    #   images, AIO/AIUK Papers (PDF commentary volumes), browse/search
    #                  pages — never fetched (not text records).
    # A record yields the -en translation document always and the Greek
    # document where AIO publishes its own text (AioRecordParser class note).
    #
    # == Count reconciliation
    #
    # Upstream's own advertised total: the listing's "count" = 3,466
    # (2026-11-02), 35 pages × 100. AioFetch refuses a listing whose
    # distinct aio_keys disagree with "count", so on a clean sync accepted
    # records = 3,466 = advertised, the residue being only censused 404s.
    # Expected first parse: 3,466 translation documents + one Greek document
    # per AIO-edited record (the 18-record sample: 7 with Greek, biased
    # toward AIO/AIUK keys — the real share is measured at the first sync).
    #
    # == fetch / sync policy
    #
    # AioFetch: ~35 listing GETs + 2 GETs per inscription (~6,970 requests)
    # at 0.5 s → roughly 1–1.5 h first crawl, resumable at the file grain —
    # REBUILD-CLASS duration: owner-scheduled. sync_policy manual, wired:
    # false until the first real sync is verified.
    class Aio < Nabu::Adapter
      BASE_URL = Nabu::AioFetch::BASE_URL

      CITATION = "Attic Inscriptions Online (AIO), ed. S. D. Lambert, https://www.atticinscriptions.com " \
                 "— translations and texts under CC BY-SA 3.0"

      MANIFEST = Nabu::SourceManifest.new(
        id: "aio",
        name: "AIO — Attic Inscriptions Online (British School at Athens)",
        license: "CC BY-SA 3.0 (every inscription page's CC badge, rel=license → " \
                 "creativecommons.org/licenses/by-sa/3.0/deed.en_GB, on both the translation and " \
                 "the Greek view; the REST API's per-record IPR field: \"Creative Commons\"). " \
                 "Images are not fetched.",
        license_class: "attribution",
        upstream_url: BASE_URL,
        parser_family: "aio-record",
        credit: CITATION
      )

      def self.manifest
        MANIFEST
      end

      # No git repo — the probe GETs the first listing page (reachability;
      # the fetch ledger holds the content pin).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "list_all_inscriptions page=1",
          zip_url: Nabu::AioFetch.listing_url(BASE_URL, 1),
          metadata_url: nil, state_subdir: "",
          state_file: Nabu::AioFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::AioFetch::DELAY)
        super()
        @delay = delay
      end

      # One ref per layer per record (Greek base, -en translation), in
      # numeric key order. An unfetched workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        record_paths(workdir).each do |path|
          number = AioRecordParser.number_of(path)
          next unless File.file?(path.sub(/\.json\z/, ".html"))

          layers = AioRecordParser.layers(path)
          if layers.include?("greek")
            yield Nabu::DocumentRef.new(source_id: manifest.id, id: AioRecordParser.base_urn(number), path: path)
          end
          next unless layers.include?("translation")

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: AioRecordParser.translation_urn(number),
                                      path: path, metadata: { "kind" => "translation" })
        end
      end

      # Censused skips: the listing sidecars (the manifest grain, by rule);
      # records whose JSON carries no translation text (by rule — nothing
      # to mint for the translation layer); unrecognized = a half pair (a
      # JSON without its page, or a page without its JSON — a fetch hole).
      def discovery_skips(workdir)
        sidecars = Dir.glob(File.join(workdir, "*.json"))
                      .count { |path| Nabu::AioFetch::LISTING_FILENAME.match?(File.basename(path)) }
        untranslated = 0
        half_pairs = []
        record_paths(workdir).each do |path|
          html = path.sub(/\.json\z/, ".html")
          next half_pairs << File.basename(path) unless File.file?(html)

          untranslated += 1 unless AioRecordParser.layers(path).include?("translation")
        end
        Dir.glob(File.join(workdir, Nabu::AioFetch::RECORDS_DIR, "aio-*.html")).each do |html|
          half_pairs << File.basename(html) unless File.file?(html.sub(/\.html\z/, ".json"))
        end
        notes = half_pairs.sort.map { |name| "#{name}: half a record pair (JSON + page) — a fetch hole" }
        notes << "#{sidecars} listing pages (the manifest grain) skipped by rule" if sidecars.positive?
        notes << "#{untranslated} records without translation EpiDoc skipped by rule" if untranslated.positive?
        DiscoverySkips.new(skipped_by_rule: sidecars + untranslated, unrecognized: half_pairs.size, notes: notes)
      end

      def parse(document_ref)
        AioRecordParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The owner-fired crawl (never in tests — WebMock blocks the network).
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::AioFetch.sync!(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::AioFetch::Error => e
        raise Nabu::FetchError, "aio fetch failed into #{workdir}: #{e.message}"
      end

      private

      def record_paths(workdir)
        Dir.glob(File.join(workdir, Nabu::AioFetch::RECORDS_DIR, "aio-*.json"))
           .select { |path| AioRecordParser.number_of(path) }
           .sort_by { |path| Integer(AioRecordParser.number_of(path), 10) }
           .map { |path| File.expand_path(path) }
      end

      def fetch_notes(result)
        base = "#{result.pages} listing pages (#{result.records} records of #{result.advertised} advertised; " \
               "#{result.fetched} files fetched, #{result.cached} already on disk)"
        named = result.missing.first(3).join(", ")
        missing = result.missing.empty? ? nil : "#{result.missing.size} listed files 404 (#{named})"
        [base, missing, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
