# frozen_string_literal: true

require "digest"

require_relative "iecor_cldf_parser"

module Nabu
  module Adapters
    # IE-CoR — the Indo-European Cognate Relationships database (P18-5;
    # .docs/surveys/pie-survey.md §1 is the survey of record): the dataset behind
    # Heggarty, Anderson & Scarborough et al. 2023 (*Science* 381), 160
    # varieties × 170 Concepticon-linked meanings, 25,731 lexemes in 4,981
    # member-bearing expert-curated cognate sets, 1,036 curated loan events.
    # The library's first CLDF source and its first cognacy MATRIX — an
    # independent second witness beside the kaikki shelves, landing on ten
    # held gold languages at once (grc lat got chu orv sl ang san xcl hit,
    # 2,261 measured held-pair edges) with laryngeal-notated PIE roots that
    # cross-join kaikki's under the §9 fold (*k̑erd- ≡ *ḱerd- → "kerd-").
    #
    # == Surface (survey §1, argued Option A): reflex rows, not a new table
    #
    # ONE dictionary (slug iecor), one entry per cognate set (headword =
    # Root_Form, laryngeal notation verbatim), each member form a
    # DictionaryReflex row — so etym/define/cognates, the reflex-roots
    # closure and MCP light up with zero new query code. Singleton sets
    # (2,341) ARE included: a set with one witness still carries a curated
    # root and a concept — a define surface — and can only ever surface when
    # queried by its own forms, so it costs nothing in noise. The 58 live
    # sets with no membership judgment at all mint nothing (parser rule).
    #
    # == The dictionary language: `ine`, argued
    #
    # Sets root in 40+ languages (PIE 1,596, but also Latin 123, Sanskrit
    # 102, Greek 102, per-clade protos, and 639 with no curated root).
    # Per-clade dictionaries would splinter one upstream table into dozens
    # of shelves AND — decisive — key an entry's identity to Root_Language,
    # a curatable field, so an upstream revision would MOVE entries between
    # dictionaries and break the frozen-URN guarantee. `ine` (ISO 639-2
    # collective, "Indo-European languages") covers every set honestly, is
    # shape-valid, and is already a PROTO_FOLD key (conventions §9). Costs,
    # stated: not a -pro code, so renderers add no display asterisk (the
    # upstream Root_Form carries its own asterisk verbatim — display honesty
    # is free) and `etym *root` / `define *root` direct-asterisk lookups
    # scope to -pro shelves and skip iecor — entries are reached from the
    # attested side (`etym срьдьце`) and by bare define (`define kerd-`),
    # which is where the cognacy value lives. Per-set root language stays
    # verbatim in the entry body.
    #
    # == Upstream artifact: the Zenodo release zip, argued
    #
    # Three candidates censused (survey + 2026-07-14 verification):
    # (a) the GitHub repo via GitFetch pinned to tag v1.2 — works, but pulls
    #     git history and machinery for a dataset that only moves by minting
    #     a NEW versioned DOI; (b) GitHub's release zipball — generated
    #     on the fly, NOT byte-stable (compression drift has broken sha pins
    #     ecosystem-wide), unpinnable; (c) the Zenodo VERSIONED record
    #     10.5281/zenodo.13304537 (= v1.2, 2024-08-12), one immutable
    #     6.4 MB zip with a published checksum — archival-grade, citation-
    #     grade, byte-stable. (c) wins: ZipFetch + a hard sha256 pin
    #     (RELEASE_SHA256, verified against the fresh download AND Zenodo's
    #     own md5 2d4e742ab755c0f506e91a74e6b6e2ad). A body that misses the
    #     pin aborts BEFORE any tree mutation. A future v1.3 is a new DOI:
    #     the owner re-pins URL + sha (the Coptic RELEASE_TAG pattern) and
    #     fires the re-sync. sync_policy: manual.
    #
    # == License (read three ways, all agreeing — survey §1)
    #
    # GitHub license field CC-BY-4.0; README verbatim "This dataset is
    # licensed under a https://creativecommons.org/licenses/by/4.0/
    # license"; Zenodo record license cc-by-4.0 → attribution,
    # MCP-surface-safe. Cite: Heggarty, Anderson, Scarborough et al. 2023,
    # Science 381, eabg0818 (DOI 10.1126/science.abg0818).
    class Iecor < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "iecor",
        name: "IE-CoR — Indo-European Cognate Relationships database (lexibank/iecor v1.2)",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a " \
                 "https://creativecommons.org/licenses/by/4.0/ license\"; Zenodo record cc-by-4.0; " \
                 "cite Heggarty, Anderson, Scarborough et al. 2023, Science 381, eabg0818)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/13304537",
        parser_family: "cldf-csv"
      )

      # The immutable versioned artifact (10.5281/zenodo.13304537 = v1.2;
      # the concept DOI 10.5281/zenodo.8089433 always resolves to latest).
      ZENODO_ZIP_URL = "https://zenodo.org/records/13304537/files/lexibank/iecor-v1.2.zip?download=1"

      # sha256 of the release zip, pinned from the 2026-07-14 fixture
      # snapshot download (md5 cross-checked against Zenodo's published
      # 2d4e742ab755c0f506e91a74e6b6e2ad). A mismatch aborts the fetch with
      # the live tree untouched — Zenodo files are immutable, so a mismatch
      # means corruption or tampering, never a routine update.
      RELEASE_SHA256 = "ff249cffc1bba75048d9eace3f9d95bf723f5a5c406f75ec739ab97586cc03c4"

      DICTIONARY_SLUG = "iecor"
      TITLE = "IE-CoR — Indo-European cognate sets (Heggarty et al. 2023)"
      CLDF_DIR = "cldf"
      ANCHOR_FILE = "cognatesets.csv"

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # HEAD the Zenodo artifact: reachability + Last-Modified drift against
      # the .zip-fetch.json pin. metadata_url nil — the license travels
      # inside the bundle (LICENSE + cldf/README.md) and on the record page.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "iecor-v1.2.zip", zip_url: ZENODO_ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef for the one CLDF bundle: the cldf/ table dir,
      # located by its anchor table wherever the unpack put it (the Zenodo
      # zip nests everything under lexibank-iecor-<sha>/ when unpacked by
      # hand; ZipFetch flattens that single top-level dir away — both
      # shapes, and the fixture's plain cldf/, discover identically under
      # ONE stable ref id). A workdir without the bundle yields nothing
      # (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        anchor = Dir.glob(File.join(workdir, "**", CLDF_DIR, ANCHOR_FILE)).min
        return unless anchor

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{CLDF_DIR}",
          path: File.expand_path(File.dirname(anchor)), metadata: {}
        )
      end

      def parse(document_ref)
        result = IecorCldfParser.new.read(document_ref.path)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: IecorCldfParser::DICTIONARY_LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        result.entries.each { |entry| document << entry }
        result.language_notes.each { |note| document.add_language_note(note) }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "iecor: #{document_ref.id}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (prepare → verify pin →
      # mass-deletion breaker → complete); a 304 replays the stored pin and
      # touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZENODO_ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "iecor fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "iecor: downloaded artifact misses the release sha256 pin " \
              "(expected #{@pin}, got #{fetch.sha}) — Zenodo records are immutable, so this is " \
              "corruption or an unannounced re-release; verify #{ZENODO_ZIP_URL} and re-pin " \
              "RELEASE_SHA256 only after reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo v1.2 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
