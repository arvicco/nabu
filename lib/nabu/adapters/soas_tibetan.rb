# frozen_string_literal: true

require "digest"

require_relative "soas_pos_parser"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # The SOAS Classical Tibetan gold POS corpus (P48-3): "A part-of-speech
    # (POS) tagged corpus of Classical Tibetan" from the AHRC project
    # "Tibetan in Digital Communication" (SOAS, 2012–2015; Hill, Garrett et
    # al.; tag set Garrett et al. 2014/2015) — four texts with hand-corrected
    # gold segmentation + gold POS, 991 lines / 318,230 form|tag tokens
    # (censused 2026-07-28): the Tibetan desk's quality anchor. A thin
    # composition of the `soas-pos` family; the adapter owns identity,
    # license and the Zenodo fetch.
    #
    # == Identity + the language ruling
    #
    #   document urn  urn:nabu:soas-tibetan:<stem>    (mdzangsblun, buston,
    #                                                  mila, marpa)
    #   passage urn   <document-urn>:<line-number>    (…:mdzangsblun:1)
    #
    # Language `xct` (ISO 639-3 Classical Tibetan) for all four texts — the
    # gretil precedent (its two xct_ files) and the honest name for 9th–15th
    # c. classical orthography: NOT `bo` (modern Tibetan — kaikki's
    # dictionary shelf) and NOT `otb` (Old Tibetan — the old-tibetan
    # source's Dunhuang lane).
    #
    # == What the annotation layer contains (and does not)
    #
    # form|tag ONLY: gold segmentation + gold POS ride as token
    # "form"/"pos"; there is NO lemma column anywhere in the deposit, so no
    # "lemma" key is ever minted and the lemma index gains ZERO rows from
    # this source — honest absence (no lemma_tier posture needed; nothing
    # exists to label). The undisambiguated `<stem>-horizontal-lex.txt`
    # renderings (every tag the lexicon allows, bracketed) are furniture:
    # censused discovery skips, never documents.
    #
    # == Upstream artifact: the Zenodo versioned record (the wold/ren posture)
    #
    # 10.5281/zenodo.574878 = one immutable Texts.zip (1,780,761 B; Zenodo
    # md5 1bac00abb7432cc26694449ef47787ef cross-checked at pin time),
    # ZipFetch + a hard sha256 pin (RELEASE_SHA256) verified BETWEEN
    # download and any tree mutation. The zip carries TWO top-level entries
    # (Texts/ + the Apple __MACOSX/ sidecar), so ZipFetch's single-top-dir
    # strip does not fire: the tree lands as Texts/… (+ inert __MACOSX/
    # junk discover never matches). A future release is a NEW DOI the owner
    # re-pins. sync_policy: manual.
    #
    # == License (verified 2026-07-28)
    #
    # Zenodo record 574878 declares cc-by-4.0 → attribution. Cite the
    # deposit (DOI) + the SOAS project (AHRC AH/J00152X/1).
    class SoasTibetan < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "soas-tibetan",
        name: "SOAS Classical Tibetan gold POS corpus (Tibetan in Digital Communication)",
        license: "CC BY 4.0 (Zenodo record 574878 license cc-by-4.0, DOI 10.5281/zenodo.574878; " \
                 "cite the deposit + the SOAS project 'Tibetan in Digital Communication', AHRC " \
                 "AH/J00152X/1; tag set Garrett et al. 2014/2015)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/574878",
        parser_family: "soas-pos"
      )

      # The immutable versioned artifact (10.5281/zenodo.574878).
      ZIP_URL = "https://zenodo.org/records/574878/files/Texts.zip?download=1"

      # sha256 of Texts.zip, pinned from the 2026-07-28 download (md5
      # cross-checked against Zenodo's 1bac00abb7432cc26694449ef47787ef).
      RELEASE_SHA256 = "738262a04d76726391a7debabf828eecb26799a3c6f4b65497c8b87190b0fc55"

      TEXTS_DIR = "Texts"
      LANGUAGE = "xct"
      URN_PREFIX = "urn:nabu:soas-tibetan:"

      # The four texts, deposit-censused: titles + periods verbatim from the
      # Zenodo record description. A stem outside this map (impossible in
      # the immutable deposit) would still parse, titled by its stem.
      TEXTS = {
        "mdzangsblun" => { title: "Mdzaṅs blun", period: "9th century, canonical" },
        "buston" => { title: "Bu ston chos ḥbyuṅ", period: "13th century, ecclesiastical history" },
        "mila" => { title: "Mi la ras paḥi rnam thar", period: "15th century, biography" },
        "marpa" => { title: "Mar paḥi rnam thar", period: "15th century, biography" }
      }.freeze

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Texts.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per Texts/<stem>-horizontal.txt, sorted by urn. The
      # glob is anchored under Texts/ so the __MACOSX AppleDouble junk never
      # matches; -lex renderings are the censused skip below. A pre-fetch
      # workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, TEXTS_DIR, "*-horizontal.txt")).map do |path|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{stem_of(path)}",
            path: File.expand_path(path),
            metadata: {}
          )
        end.sort_by(&:id).each(&block)
      end

      # The undisambiguated -lex renderings: visible skips, never silent.
      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, TEXTS_DIR, "*-horizontal-lex.txt")).size
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        stem = stem_of(document_ref.path)
        entry = TEXTS.fetch(stem, {})
        SoasPosParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: entry.fetch(:title, stem),
                             metadata: { "text_id" => stem, "period" => entry[:period] }.compact
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify the hard sha pin + unpack, phases hand-driven so
      # the pin check runs BETWEEN download and any tree mutation (the
      # wold/ren mold); a 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "soas-tibetan fetch failed into #{workdir}: #{e.message}"
      end

      private

      def stem_of(path)
        File.basename(path).delete_suffix("-horizontal.txt")
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "soas-tibetan: downloaded artifact misses the release sha256 pin (expected " \
              "#{@pin}, got #{fetch.sha}) — Zenodo record 574878 is versioned-immutable, so " \
              "this is corruption or an unannounced re-release; verify #{ZIP_URL} and re-pin " \
              "RELEASE_SHA256 only after reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo 574878 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
