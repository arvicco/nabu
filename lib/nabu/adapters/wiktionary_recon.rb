# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # The reconstruction shelf source (P14-1, architecture §12): English
    # Wiktionary's reconstruction pseudo-languages via the kaikki.org
    # wiktextract extraction — ONE source shipping THREE dictionaries
    # (Proto-Slavic sla-pro, Proto-Indo-European ine-pro, Proto-Germanic
    # gem-pro), each its own JSONL through the SAME wiktionary-jsonl family
    # as wiktionary-cu, with `reflexes: true`: the records' `descendants`
    # trees flatten into DictionaryReflex edges — the crosswalk that links
    # reconstructed headwords to attested in-catalog lemmas (`nabu etym`).
    #
    # == Upstream (verified page-level + ranged reads, docs/backlog.md P14-1
    # Phase A, 2026-07-12; full downloads at fixture build)
    #
    # kaikki.org per-language extracts, built from the enwiktionary dump
    # dated 2026-07-06 (wiktextract, Tatu Ylönen): Proto-Slavic 47.6 MB /
    # 5,431 records, PIE 12.0 MB / 1,905, Proto-Germanic 65.3 MB / 5,717.
    # The `word` field carries NO asterisk (display prefixes it back);
    # `lang_code` is the Wiktionary etymology-language code the registry
    # adopts verbatim (conventions §4: sla-pro/ine-pro/gem-pro are not ISO
    # 639-3, but pass the shape-only tag validation unchanged).
    #
    # DEPRECATION CAVEAT: like the OCS extract, the per-language JSONL is
    # labelled "DEPRECATED, will be removed in the near future" (wiktextract
    # issue #1178) yet is what the site itself serves. A future 404 is a
    # clean FetchError; the durable fallback is filtering the full
    # enwiktionary extract by lang_code — recorded in docs/02-sources.md.
    #
    # == License
    #
    # Verbatim, https://kaikki.org/dictionary/ "Copyright and license"
    # (re-verified 2026-07-12): "This data is made available under the same
    # licenses as Wiktionary - both CC-BY-SA and GFDL." → attribution,
    # MCP-surface-safe; wiktextract asks for the academic citation (Ylönen,
    # LREC 2022) — carried in 02-sources.
    #
    # == fetch / sync policy
    #
    # Three FileFetch single-file syncs, one per extract, each in ITS OWN
    # subdir (FileFetch is one-file-per-dir by design: any other file in
    # the dir is doomed, and there is one state file per dir), attics under
    # the shared top-level <workdir>/.attic/<subdir>/ so discover_with_attic
    # finds retained files — the UD multi-repo choreography: ALL extracts
    # prepare (tree untouched), the mass-deletion breaker sees the whole
    # SET, then all complete. sync_policy: manual, enabled: false until the
    # owner-fired first real sync (~125 MB across three GETs).
    class WiktionaryRecon < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-recon",
        name: "Wiktionary reconstructions — kaikki.org machine-readable extracts " \
              "(Proto-Slavic, PIE, Proto-Germanic)",
        license: "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                 "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")",
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/",
        parser_family: "wiktionary-jsonl"
      )

      # One dictionary per extract; iteration order is registry order
      # (discover/parse/probe all speak it). Slugs mint the urn namespaces
      # (urn:nabu:dict:wiktionary-sla-pro:<entry_id>); `language` is the
      # Wiktionary etymology-language code adopted verbatim.
      EXTRACTS = {
        "wiktionary-sla-pro" => {
          subdir: "proto-slavic",
          filename: "kaikki.org-dictionary-ProtoSlavic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Slavic/kaikki.org-dictionary-ProtoSlavic.jsonl",
          language: "sla-pro",
          title: "Wiktionary — Proto-Slavic (kaikki.org extract)"
        }.freeze,
        "wiktionary-ine-pro" => {
          subdir: "proto-indo-european",
          filename: "kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Indo-European/" \
               "kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
          language: "ine-pro",
          title: "Wiktionary — Proto-Indo-European (kaikki.org extract)"
        }.freeze,
        "wiktionary-gem-pro" => {
          subdir: "proto-germanic",
          filename: "kaikki.org-dictionary-ProtoGermanic.jsonl",
          url: "https://kaikki.org/dictionary/Proto-Germanic/kaikki.org-dictionary-ProtoGermanic.jsonl",
          language: "gem-pro",
          title: "Wiktionary — Proto-Germanic (kaikki.org extract)"
        }.freeze
      }.freeze

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One HEAD per extract, each against its own subdir's FileFetch state
      # (Last-Modified drift + the DEPRECATED-file early warning).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        EXTRACTS.values.map do |extract|
          Nabu::Adapter::HttpProbeTarget.new(
            label: extract.fetch(:filename), zip_url: extract.fetch(:url), metadata_url: nil,
            state_subdir: extract.fetch(:subdir), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # One DocumentRef per extract file, in EXTRACTS order. A workdir
      # without a file simply yields fewer refs (the day-one pre-fetch
      # state); the same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        EXTRACTS.each do |slug, extract|
          Dir.glob(File.join(workdir, "**", extract.fetch(:filename))).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id,
              id: "#{slug}:#{extract.fetch(:filename)}",
              path: File.expand_path(path),
              metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        extract = EXTRACTS.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: extract.fetch(:language),
          title: extract.fetch(:title), canonical_path: document_ref.path
        )
        WiktionaryJsonlParser.new(language: extract.fetch(:language), reflexes: true)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "wiktionary-recon: #{document_ref.id}: #{e.message}"
      end

      # Download the three extracts two-phase (the UD choreography): all
      # prepare with the live tree untouched, the breaker sees the combined
      # doomed set, then all complete. Report: last extract's sha (the
      # single-pin convention), per-extract shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wiktionary-recon fetch failed into #{workdir}: #{e.message}"
      end

      private

      def file_fetches(workdir, progress)
        EXTRACTS.transform_values do |extract|
          Nabu::FileFetch.new(
            url: extract.fetch(:url), dir: File.join(workdir, extract.fetch(:subdir)),
            filename: extract.fetch(:filename),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, extract.fetch(:subdir)),
            progress: progress
          )
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map do |slug, fetch|
          "#{EXTRACTS.fetch(slug).fetch(:language)} #{fetch.sha[0, 8]}"
        end
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
