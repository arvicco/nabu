# frozen_string_literal: true

module Nabu
  module Adapters
    # The CLDF reference spine — Concepticon concept ids + Glottolog
    # languoid ids — registered as a FEATURE MODULE (kind: module), not a
    # text source (P46-6; the pleiades/lila shape): discover yields NOTHING,
    # parse is unreachable, no catalog table, no migration. `nabu sync
    # cldf-spine` (owner-run) lands two thin reference files under
    # canonical/cldf-spine/, and Nabu::CldfSpine resolves a Concepticon id →
    # {gloss, semantic field, definition} and a glottocode → {name, ISO,
    # level, family} for the comparativist shelves that cite them (WOLD
    # parameters/donors, CLICS³ nodes, IE-CoR's Concepticon-linked meanings).
    #
    # == fetch: two tag-pinned raw files (the edrdg per-subdir posture)
    #
    # THIN is the point (packet spec): NOT the multi-megabyte CLDF bundles —
    # exactly two files, each pinned to an upstream release TAG so the URL is
    # a stable git blob (byte-stable, unlike GitHub's generated zipballs):
    #
    #   concepticon/concepticon.tsv  concepticon-data v3.4.0 (453,281 B,
    #                                sha256 f96a72b8dc18…, 2026-07-26)
    #   glottolog/languages.csv      glottolog-cldf v5.3 (2,462,735 B,
    #                                sha256 1a50a393bc81…, 2026-07-26)
    #
    # Each lands via FileFetch in its own subdir with its own state file
    # (conditional GET, attic + guard contract). A new upstream release is a
    # new tag: the owner re-pins the two URL constants and re-syncs.
    #
    # == License (both verified 2026-07-26)
    #
    # Concepticon: .zenodo.json at v3.4.0 declares license CC-BY-4.0 (the
    # Zenodo releases of "CLLD Concepticon" carry the same grant). Glottolog:
    # the glottolog-cldf bundle's own dc:license is
    # https://creativecommons.org/licenses/by/4.0/ (cldf/README.md at v5.3).
    # Both → class attribution.
    class CldfSpine < Nabu::Adapter
      CONCEPTICON_URL =
        "https://raw.githubusercontent.com/concepticon/concepticon-data/v3.4.0/" \
        "concepticondata/concepticon.tsv"
      GLOTTOLOG_URL =
        "https://raw.githubusercontent.com/glottolog/glottolog-cldf/v5.3/cldf/languages.csv"

      # subdir => [url, landed filename] — the fetch table and the probe
      # table read the same rows.
      FILES = {
        "concepticon" => [CONCEPTICON_URL, "concepticon.tsv"].freeze,
        "glottolog" => [GLOTTOLOG_URL, "languages.csv"].freeze
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "cldf-spine",
        name: "Concepticon + Glottolog — the CLDF reference spine (concept/languoid resolver instrument)",
        license: "CC BY 4.0 both (Concepticon: .zenodo.json license CC-BY-4.0 at v3.4.0, cite List " \
                 "et al., CLLD Concepticon; Glottolog: glottolog-cldf dc:license " \
                 "creativecommons.org/licenses/by/4.0/ at v5.3, cite Hammarström, Forkel, " \
                 "Haspelmath & Bank, Glottolog)",
        license_class: "attribution",
        upstream_url: "https://github.com/concepticon/concepticon-data",
        parser_family: "cldf-spine"
      )

      def self.manifest
        MANIFEST
      end

      # The probe HEADs each raw file: reachability + Last-Modified drift vs
      # the per-subdir .file-fetch.json pin (the edrdg posture).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |subdir, (url, filename)|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename, zip_url: url, metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::CldfSpine), not passages. Empty by design (the lila shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: cldf-spine is a reference resolver instrument, not a " \
                          "text source — its data rides Nabu::CldfSpine (P46-6); parse is unreachable"
      end

      # Download the two reference files via FileFetch, each in its own
      # subdir with its own state + attic (conditional GET, guard contract).
      # No network in tests.
      def fetch(workdir, progress: nil, force: false)
        results = FILES.to_h do |subdir, (url, filename)|
          dir = File.join(workdir, subdir)
          [subdir, Nabu::FileFetch.sync!(
            url: url, dir: dir, filename: filename,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(dir, doomed, force: force) }
          )]
        end
        notes = results.filter_map { |subdir, result| "#{subdir} unchanged (304)" if result.not_modified }
        FetchReport.new(sha: results.fetch("glottolog").sha, fetched_at: Time.now,
                        notes: notes.empty? ? nil : notes.join("; "),
                        repos: FILES.to_h { |subdir, (url, _)| [url, results.fetch(subdir).sha] })
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "cldf-spine fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
