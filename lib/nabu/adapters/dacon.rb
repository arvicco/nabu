# frozen_string_literal: true

require "digest"

require_relative "dacon_pos_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # DACON — the Diachronic Annotated Corpus of Newar (P88-A4): segmented +
    # POS-tagged Classical Newar (nwc), 12th–19th c., by Alexander O'Neill
    # (Musashino) & Marieke Meelen (Cambridge), AHRC "The Emergence of
    # Egophoricity" (AH/V011235/1); companion to their CLAO 54.2 (2025)
    # corpus article. Four texts × (SEG, POS) = 8 files, ~641 KB, ~28.8k
    # gold-tagged tokens — the library's first Newar shelf. A thin
    # composition of the `dacon-pos` family; the adapter owns identity,
    # dating, license and the Zenodo fetch.
    #
    # == Identity + language
    #
    #   document urn  urn:nabu:dacon:<downcased-stem>  (cnew12-ukubahah, …)
    #   passage urn   <document-urn>:utt-<n>           (the <utt> block index)
    #
    # Language `nwc` (ISO 639-3 Classical Newari) — the corpus's own frame
    # (12th–19th c., file prefix `cnew`); NOT `new` (modern Newari/Nepal
    # Bhasa). No nabu-lects anchor exists yet (censused 2026-08-29): the
    # lect posture is `pending` naming nwc, queued on the P88-B3 mint.
    #
    # == The POS/SEG pair
    #
    # Each text ships twice: `*_POS.txt` (one form<sep>TAG per line — the
    # richer rendition, parsed) and `*_SEG.txt` (the same tokens as one
    # running line — recoverable from POS, so a censused discovery skip,
    # never a document). Only gold segmentation + POS exist upstream — no
    # lemma column anywhere, so the lemma index gains ZERO rows from this
    # source (the soas-tibetan honest-absence stance).
    #
    # == Dating
    #
    # The deposit's own century attributions (encoded in its `cnew<cc>`
    # stems and stated in the record description) ride as a per-document
    # `date` envelope — "12th century" → 1101–1200 — through the
    # MetadataDates `:structured` lane.
    #
    # == Upstream artifact: the Zenodo versioned record (the soas mold)
    #
    # 10.5281/zenodo.12887386 (v1 = latest, published 2024-07-26) — 8
    # per-file GETs against the immutable record API, one FileFetch subdir
    # each (a FileFetch owns its directory), every file under a hard sha256
    # pin verified BETWEEN download and any tree mutation. A future release
    # is a NEW DOI the owner re-pins. sync_policy: manual.
    #
    # == License (verified 2026-08-29)
    #
    # Zenodo record 12887386 declares cc-by-4.0 (SPDX) → attribution. Cite
    # the deposit (DOI) + O'Neill & Meelen, CLAO 54.2 (2025).
    class Dacon < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "dacon",
        name: "DACON — Diachronic Annotated Corpus of Newar (O'Neill & Meelen)",
        license: "CC BY 4.0 (Zenodo record 12887386 license cc-by-4.0, DOI " \
                 "10.5281/zenodo.12887386; cite the deposit + O'Neill & Meelen, \"The " \
                 "Diachronic Annotated Corpus of Newar: from Manuscript to Morphosyntax\", " \
                 "Cahiers de Linguistique Asie Orientale 54.2 (2025); AHRC AH/V011235/1)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/12887386",
        parser_family: "dacon-pos"
      )

      RECORD_FILES_URL = "https://zenodo.org/api/records/12887386/files"
      LANGUAGE = "nwc"
      URN_PREFIX = "urn:nabu:dacon:"

      # The 8 deposit files under their 2026-08-29 sha256 pins (md5
      # cross-checked against the record API's manifest at pin time).
      # Zenodo versioned records are immutable — a mismatch is corruption
      # or an unannounced re-release, never routine drift.
      FILES = {
        "cnew12-Ukubahah_POS.txt" => "dd9b89161501b9ae5c77f0749f4aeb40787fe605a99a7448ab7d6ac2b789e296",
        "cnew12-Ukubahah_SEG.txt" => "e0c6b55d8ae4ba52305a9d2b660ce49b030596af67da28e273d6114942f4fa9a",
        "cnew13_14-Gopala_POS.txt" => "4cc3c63abeac3d5c4c914a160b640c11e2bebe7b98e943be8e820cdee1bf7e0e",
        "cnew13_14-Gopala_SEG.txt" => "011786dc8148c3dd9d94f3bad4a775ae7670503098cbb4ac05c948b809004988",
        "cnew17-vetala-MSB-10000_POS.txt" => "187f663c1b94e474b92a0dc5c470213bf8cdf1c56e7ead10ca136412679af7c3",
        "cnew17-vetala-MSB-10000_SEG.txt" => "0a44557a5d3bc08eac53a6497a545b22a36832dd18f0a14eaae0ff1abd3c3596",
        "cnew19-manicuda-10000_POS.txt" => "ab19876c60517629dd9c03ee801c50344fcb8ccea6e00a900876f1e672988a56",
        "cnew19-manicuda-10000_SEG.txt" => "847636cf25bfa1344cd5104a442102c8032e4f0f846b2d539f6add7381db17c8"
      }.freeze

      # The four texts, deposit-censused: titles + century attributions
      # verbatim from the record description (the centuries also live in
      # the cnew<cc> stems). A stem outside this map (impossible in the
      # immutable deposit) still parses, titled by its stem and undated.
      TEXTS = {
        "cnew12-Ukubahah" => { title: "Ukubāhāḥ inscription",
                               raw: "12th century", from: 1101, to: 1200 },
        "cnew13_14-Gopala" => { title: "Gopālarājavaṃśāvalī",
                                raw: "13th–14th century", from: 1201, to: 1400 },
        "cnew17-vetala-MSB-10000" => { title: "Vetālapañcaviṃśati (MSB manuscript, first 10,000 lines)",
                                       raw: "17th century", from: 1601, to: 1700 },
        "cnew19-manicuda-10000" => { title: "Maṇicūḍāvadāna (first 10,000 lines)",
                                     raw: "19th century", from: 1801, to: 1900 }
      }.freeze

      def self.manifest
        MANIFEST
      end

      # One HEAD per file URL against its subdir's FileFetch state.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.keys.map do |filename|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename, zip_url: file_url(filename), metadata_url: nil,
            state_subdir: subdir_of(filename), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def self.file_url(filename)
        "#{RECORD_FILES_URL}/#{filename}/content"
      end

      def self.subdir_of(filename)
        filename.delete_suffix(".txt")
      end

      # +pins+ overrides the release shas (tests; a future owner re-pin drill).
      def initialize(pins: FILES)
        super()
        @pins = pins
      end

      # One DocumentRef per */*_POS.txt (fixtures sit flat — the workdir
      # glob is depth-tolerant), sorted by urn. A pre-fetch workdir yields
      # nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        pos_paths(workdir).map do |path|
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{stem_of(path).downcase}",
            path: File.expand_path(path),
            metadata: {}
          )
        end.sort_by(&:id).each(&block)
      end

      # The SEG renditions: recoverable from POS — visible skips, never
      # silent, never documents.
      def discovery_skips(workdir)
        skipped = Dir.glob(seg_globs(workdir)).size
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        stem = stem_of(document_ref.path)
        entry = TEXTS.fetch(stem, {})
        DaconPosParser.new.parse(
          document_ref.path, urn: document_ref.id, language: LANGUAGE,
                             title: entry.fetch(:title, stem),
                             metadata: { "text_id" => stem, "date" => date_of(entry) }.compact
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download all 8 + verify every hard sha pin BETWEEN download and any
      # tree mutation (the soas/wold mold, per file); the breaker sees the
      # combined doomed set; a 304 replays the stored pin and touches
      # nothing.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each { |filename, fetch| prepare_and_verify!(filename, fetch) }
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "dacon fetch failed into #{workdir}: #{e.message}"
      end

      private

      def stem_of(path)
        File.basename(path).delete_suffix("_POS.txt")
      end

      def date_of(entry)
        return nil unless entry.key?(:from)

        { "not_before" => entry.fetch(:from), "not_after" => entry.fetch(:to),
          "raw" => entry.fetch(:raw) }
      end

      def pos_paths(workdir)
        Dir.glob(File.join(workdir, "**", "*_POS.txt")).reject { |path| under_attic?(workdir, path) }
      end

      def seg_globs(workdir)
        File.join(workdir, "**", "*_SEG.txt")
      end

      def under_attic?(workdir, path)
        path.delete_prefix(File.join(workdir, "")).split(File::SEPARATOR).include?(ATTIC_DIRNAME)
      end

      def file_fetches(workdir, progress)
        FILES.keys.to_h do |filename|
          subdir = self.class.subdir_of(filename)
          [filename, Nabu::FileFetch.new(
            url: self.class.file_url(filename),
            dir: File.join(workdir, subdir), filename: filename,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
          )]
        end
      end

      def prepare_and_verify!(filename, fetch)
        fetch.prepare!
        pin = @pins.fetch(filename)
        return if fetch.not_modified? || fetch.sha == pin

        raise Nabu::FetchError,
              "dacon: #{filename} misses its release sha256 pin (expected #{pin}, got " \
              "#{fetch.sha}) — Zenodo record 12887386 is versioned-immutable, so this is " \
              "corruption or an unannounced re-release; verify the record and re-pin FILES " \
              "only after reading it"
      end

      def fetch_notes(fetches)
        modified = fetches.values.count { |fetch| !fetch.not_modified? }
        base = modified.zero? ? "not modified (304 ×#{fetches.size})" : "zenodo 12887386 sha pins verified"
        [base, attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
