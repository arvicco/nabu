# frozen_string_literal: true

module Nabu
  module Adapters
    # Pedecerto — Latin metrical scansions, registered as a FEATURE MODULE
    # (kind: module), not a text source (the trismegistos/kitab precedent). It
    # mints NO catalog rows: its data is a METER ENRICHMENT layer over the held
    # Perseus-Latin texts (kind="meter" in the enrichments table), produced by
    # Nabu::PedecertoScansions and run by SyncRunner after every pedecerto sync.
    # So, like the other modules, discover yields NOTHING and parse is
    # unreachable — the value is the producer's output, not documents.
    #
    # == fetch: one zip, unpacked (the ORACC/Diorisis ZipFetch pattern)
    #
    # pedecerto.eu ships the whole scanned corpus as a single ~12 MB zip whose
    # one top directory `allpedecertoscans/` holds 469 <AUTHOR>-<work>.xml
    # files. ZipFetch downloads-and-unpacks it (extraction-on-fetch is the house
    # pattern for a zip that IS a tree of files — FileFetch would leave the
    # producer to unzip on every run), keeping the retention contract: upstream
    # deletions attic'd, the mass-deletion breaker between download and any tree
    # mutation. Unlike Diorisis's frozen figshare artifact there is NO sha pin —
    # the zip is periodically refreshed (Last-Modified 2025-08-18), so a changed
    # body is a plain update, and change detection rides ZipFetch's
    # If-Modified-Since. sync_policy manual, enabled: false permanently.
    #
    # == License (per-file <rights>, verbatim in every document + site, 2026-07-24)
    #
    # "https://creativecommons.org/licenses/by-nc-nd/4.0/legalcode" — CC
    # BY-NC-ND 4.0. The site's Italian terms restate it: no commercial use
    # without agreement, reproduction/circulation permitted for scientific/
    # didactic/documentary use provided the documents are not SUBSTANTIALLY
    # ALTERED and keep date/authorship/source. → class `nc`; the
    # no-substantial-alteration duty is satisfied by canonical-means-canonical
    # (the scansion is stored verbatim, never edited).
    class Pedecerto < Nabu::Adapter
      ZIP_URL = "https://www.pedecerto.eu/allpedecertoscans.zip"

      MANIFEST = Nabu::SourceManifest.new(
        id: "pedecerto",
        name: "Pedecerto — Digital Latin Metre (Udine/Ca' Foscari): hexameter + verse scansions",
        license: "CC BY-NC-ND 4.0 (per-file <rights>, verbatim: " \
                 "\"creativecommons.org/licenses/by-nc-nd/4.0\"; site: \"non ne è consentito alcun " \
                 "uso a scopi commerciali… purché i documenti non vengano alterati in alcun modo " \
                 "sostanziale… data, paternità e fonte originale\") — nc, no substantial alteration",
        license_class: "nc",
        upstream_url: "https://www.pedecerto.eu",
        parser_family: "pedecerto-scansions"
      )

      def self.manifest
        MANIFEST
      end

      # This module's data rides the ENRICHMENT seam (kind="meter") via
      # PedecertoScansions, refreshed by SyncRunner after every sync and
      # re-derived by rebuild. Declared here beside content_kind so SyncRunner /
      # Rebuild find the producer without special-casing the slug.
      def self.enrichment_producer? = true

      def self.enrichment_producer(catalog:)
        Nabu::PedecertoScansions.new(catalog: catalog)
      end

      # HEAD the zip: reachability + Last-Modified drift against the
      # .zip-fetch.json pin. No metadata endpoint — the governing license lives
      # inside the artifact's own <rights> (the in-file doctrine).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "allpedecertoscans.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # A feature module mints no documents — its data is meter enrichments,
      # not passages. Empty by design, not by accident (the module shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: pedecerto is a meter-enrichment instrument, not a text " \
                          "source — its scansions ride the enrichments table (P44-7, PedecertoScansions); " \
                          "parse is unreachable"
      end

      # Download-and-unpack the corpus zip, guarded (the ORACC one-shot). A
      # changed body is a plain update; upstream deletions attic first.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_corpus_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: fetch_notes(result))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "pedecerto fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The mass-deletion breaker keyed on the CORPUS xml census, not discover:
      # a feature module's discover yields nothing (it mints no documents), so
      # the base guard's discover-denominator would false-trip on any refetch
      # deletion. The meaningful population is the unpacked <AUTHOR>-<work>.xml
      # files the producer reads — trip only when a fresh unpack would drop more
      # than MASS_DELETION_THRESHOLD of them (a truncated/broken zip), never on
      # a first fetch (empty live tree → doomed empty → passes).
      def guard_corpus_deletion!(workdir, doomed_paths, force:)
        return if force || doomed_paths.empty?

        corpus = corpus_paths(workdir)
        doomed = doomed_paths.count { |path| corpus.include?(File.expand_path(path)) }
        return if doomed <= Nabu::Adapter::MASS_DELETION_THRESHOLD * corpus.size

        raise Nabu::SyncAborted.new(existing_count: corpus.size, would_withdraw_count: doomed,
                                    threshold: Nabu::Adapter::MASS_DELETION_THRESHOLD)
      end

      def corpus_paths(workdir)
        Dir.glob(File.join(workdir, Nabu::PedecertoScansions::DIRNAME, "*.xml"))
           .to_set { |path| File.expand_path(path) }
      end

      def fetch_notes(result)
        base = result.not_modified ? "not modified (304)" : "allpedecertoscans.zip unpacked"
        [base, attic_notes(result.atticked)].compact.join("; ")
      end
    end
  end
end
