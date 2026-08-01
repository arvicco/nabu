# frozen_string_literal: true

module Nabu
  module Adapters
    # ACTib v2.0 — The Annotated Corpus of Classical Tibetan (Meelen, Hill &
    # Faggionato; Zenodo record 3951503), registered as a FEATURE MODULE
    # (kind: module), not a text source (the pedecerto/hypotactic precedent):
    # it mints NO catalog rows. The canonical text already lives on the
    # derge-kangyur shelf; ACTib contributes the word-segmented (seg/) and
    # POS-tagged (pos/) layers over the same eKangyur, 103 volume files each
    # with inline p<N>/ln<N> page/line markers and <utt> utterance breaks.
    # So, like the other modules, discover yields NOTHING and parse is
    # unreachable — the value is the xct/actib-anchors nabu-data builder
    # (lib/nabu/data-build land, docs/nabu-data.md), which anchors every
    # derge-kangyur passage to its ACTib line and publishes the anchor table
    # (the layer content itself is never republished; consumers join the
    # DOI-cited artifact).
    #
    # == fetch: one zip, unpacked (the pedecerto ZipFetch pattern)
    #
    # The record file SegPOS-eKangyur_July2020.zip (~200 MB, ~830 MB
    # unpacked) carries exactly ONE top-level directory
    # (SegPOS-eKangyur_July2020/{seg,pos}), so ZipFetch's single-top-dir
    # strip lands the layer trees at canonical/actib/{seg,pos} — where the
    # anchors builder reads them. The record is a frozen versioned deposit;
    # change detection rides ZipFetch's If-Modified-Since, upstream
    # deletions attic first, the mass-deletion breaker keys on the unpacked
    # volume-file census. Only this artifact is taken — the record's other
    # collections (Old Tibetan, tagged-only sets) are not.
    #
    # == License (the record, NOT the zip — recorded honestly, 2026-07-31)
    #
    # The Zenodo RECORD declares cc-by-4.0 (API-verified); the zip itself
    # contains NO license files. The record's declared license is the
    # grant basis — that asymmetry is stated wherever the license is
    # recorded (here, sources.yml, docs/02-sources.md, and the published
    # dataset's README). → class `attribution`.
    class Actib < Nabu::Adapter
      ZIP_URL = "https://zenodo.org/records/3951503/files/SegPOS-eKangyur_July2020.zip"

      LAYER_DIRNAMES = %w[seg pos].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "actib",
        name: "ACTib v2.0 — The Annotated Corpus of Classical Tibetan (eKangyur seg + POS layers)",
        license: "CC BY 4.0 — declared on the Zenodo record (DOI 10.5281/zenodo.3951503, " \
                 "API-verified 2026-07-31); the zip itself contains no license file, so the " \
                 "record's declared license is the grant basis (recorded honestly). Cite: " \
                 "Meelen, Hill & Faggionato, The Annotated Corpus of Classical Tibetan (ACTib) " \
                 "v2.0, doi:10.5281/zenodo.3951503.",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.3951503",
        parser_family: "actib"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the zip: reachability + Last-Modified drift against the
      # .zip-fetch.json pin. No metadata endpoint — the record page carries
      # the license; the artifact carries the data.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "SegPOS-eKangyur_July2020.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # A feature module mints no documents — its data is the anchor layer
      # the xct/actib-anchors builder reads. Empty by design, not by
      # accident (the module shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: actib is the anchor-layer cone for the " \
                          "xct/actib-anchors dataset, not a text source — the canonical text is " \
                          "the derge-kangyur shelf (P55-4); parse is unreachable"
      end

      # Download-and-unpack the record artifact, guarded (the pedecerto
      # one-shot). A changed body is a plain update; upstream deletions
      # attic first.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_corpus_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: fetch_notes(result))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "actib fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The mass-deletion breaker keyed on the unpacked LAYER census, not
      # discover (a module's discover yields nothing): trip only when a
      # fresh unpack would drop more than MASS_DELETION_THRESHOLD of the
      # seg/pos volume files (a truncated/broken zip), never on a first
      # fetch.
      def guard_corpus_deletion!(workdir, doomed_paths, force:)
        return if force || doomed_paths.empty?

        corpus = corpus_paths(workdir)
        doomed = doomed_paths.count { |path| corpus.include?(File.expand_path(path)) }
        return if doomed <= Nabu::Adapter::MASS_DELETION_THRESHOLD * corpus.size

        raise Nabu::SyncAborted.new(existing_count: corpus.size, would_withdraw_count: doomed,
                                    threshold: Nabu::Adapter::MASS_DELETION_THRESHOLD)
      end

      def corpus_paths(workdir)
        LAYER_DIRNAMES.flat_map { |layer| Dir.glob(File.join(workdir, layer, "*.txt")) }
                      .to_set { |path| File.expand_path(path) }
      end

      def fetch_notes(result)
        base = result.not_modified ? "not modified (304)" : "SegPOS-eKangyur_July2020.zip unpacked"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
