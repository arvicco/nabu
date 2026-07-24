# frozen_string_literal: true

module Nabu
  module Adapters
    # Pleiades — the ancient-world gazetteer, registered as a FEATURE MODULE
    # (kind: module), not a text source. It mints NO catalog rows and needs
    # NO migration: v1 is a pure READ seam. `nabu sync pleiades` (owner-run)
    # lands the gazetteer dump under canonical/pleiades/, and Nabu::Pleiades
    # resolves a place id → {title, representative point, place types, time
    # periods} straight off that dump. A later packet consumes it on display
    # surfaces (an isicily/itant record's place metadata already carries an
    # "ancient_ref" Pleiades id). So, like bridging, discover yields NOTHING
    # and parse is unreachable.
    #
    # == fetch: the pinnable quarterly release (the openiti Zenodo posture)
    #
    # The canonical asset is the numbered quarterly archival release
    # (Zenodo, release 4.1, 2025-05-28 — pinnable, versioned), the openiti
    # md5-pinned Zenodo pattern. The fetch here uses Nabu::FileFetch (single
    # file, conditional GET, sha256 pin, attic + guard contract). Two honest
    # caveats the owner resolves at first sync:
    #
    #   - DUMP_URL below is the DOCUMENTED rolling gazetteer dump endpoint
    #     (the mechanism); for reproducibility the owner PINS it to the
    #     specific Zenodo 4.1 file URL (+ optional md5, the openiti drill)
    #     before the first real fetch — a one-line constant swap.
    #   - the dump's outer container (FeatureCollection vs "@graph" vs
    #     JSON-lines, and the .json.gz wrapping) is confirmed against the
    #     downloaded file at first sync; Nabu::Pleiades.load already accepts
    #     every plausible container + gzip, so the resolver needs no change —
    #     this is the clearly-marked dump-iteration seam (P43-3 spec).
    #
    # == License (verbatim, downloads page, 2026-07-24)
    #
    # "Creative Commons Attribution 3.0 License (cc-by)" → class attribution.
    class Pleiades < Nabu::Adapter
      # The documented gazetteer JSON dump (the fetch MECHANISM). Owner pins
      # to the Zenodo 4.1 file URL for a reproducible snapshot (class note).
      DUMP_URL = "https://atlantides.org/downloads/pleiades/json/pleiades-places-latest.json.gz"
      FILENAME = "pleiades-places.json.gz"

      MANIFEST = Nabu::SourceManifest.new(
        id: "pleiades",
        name: "Pleiades — ancient-world gazetteer (place resolver instrument)",
        license: "CC BY 3.0 (downloads page verbatim: \"Creative Commons Attribution 3.0 License " \
                 "(cc-by)\")",
        license_class: "attribution",
        upstream_url: "https://pleiades.stoa.org/",
        parser_family: "pleiades-json"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::Pleiades), not passages. Empty by design (the bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: pleiades is a resolver instrument, not a text source — " \
                          "its gazetteer rides Nabu::Pleiades (P43-3); parse is unreachable"
      end

      # Download the single dump file via FileFetch (conditional GET, sha
      # pin, attic + guard contract), returning a FetchReport pinning the
      # body sha256. No network in tests.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: dump_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date" : nil)
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "pleiades fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Seam for tests / the owner's Zenodo re-pin (class note).
      def dump_url
        DUMP_URL
      end
    end
  end
end
