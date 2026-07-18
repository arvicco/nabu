# frozen_string_literal: true

require_relative "itant_epidoc_parser"

module Nabu
  module Adapters
    # The Corpus_ItAnt adapter (P29-2): "Languages and Cultures of Ancient
    # Italy" (ItAnt, PRIN 2017 — CNR-ILC + Università di Firenze; cite
    # Murano et al., JOCCH 16.3 (2023), 10.1145/3606703) — EpiDoc editions
    # of Sabellic and Lepontic inscriptions from the ordinary git repo
    # DigItAnt/Corpus_ItAnt. A thin composition of the ItantEpidocParser
    # layer machinery with GitFetch — the riig/ogham Celtic-epigraphy
    # choreography on an Italic corpus.
    #
    # == Upstream census (2026-07-18, commit b60146fe)
    #
    # Oscan_inscriptions_newEditions/ 501 records (the packet spec's "502"
    # counted the dir's README) + CelticOfItaly_inscriptions_newEditions/
    # 9 Lepontic records ("10" counted its license.txt) = 510.
    # Venetic_inscriptions_newEditions/ and Faliscan_inscriptions_
    # newEditions/ hold ONLY a README each ("will be publicly available
    # once the revision process is completed") — the journaled RE-SYNC
    # WATCH: a future `nabu sync itant` picks their records up the day
    # upstream publishes, and nothing is promised meanwhile. Drawings/ is
    # a README pointer at per-record facsimile URLs (never fetched as
    # data; the graphics' own rights ride each record's <facsimile>).
    #
    # == License (three layers, all AGREEING — CC BY-NC-SA 4.0 → nc)
    #
    # Repo README.md + license.txt + EVERY record's <availability><licence>
    # say CC BY-NC-SA 4.0 verbatim (fixture README quotes all three). The
    # NC term → class "nc": MCP default-excluded, never redistributed (the
    # GRETIL/MW posture). One layered nuance recorded, not relied on: the
    # eng translation divs carry their own CC BY-SA 4.0 <ref> — the
    # siblings keep the source-level nc (restrictive reading).
    #
    # == Second-witness doctrine
    #
    # CEIPoM (P29-1) carries Oscan sentences too; ItAnt is the EpiDoc
    # edition witness beside it — deliberately unmerged, provenance-
    # distinct (the MW-beside-kaikki precedent). Both cite Trismegistos,
    # so `nabu links` meets them at the shared tm: reference targets, no
    # code coupling.
    #
    # == Layers (see ItantEpidocParser)
    #
    # discover yields, per record: the bare-urn interpretative document;
    # a -dipl sibling where the parser's own census finds a citable
    # diplomatic layer (the 9 Lepontic records); -ita/-eng translation
    # siblings where prose exists (registry `translations: true`; 336
    # records each upstream); or ONE metadata-only bare ref for the ten
    # lost inscriptions whose editions are empty (catalogued, zero
    # passages, never quarantined — the ogham text_layer:none precedent).
    # An unreadable record also takes the metadata-only path and its parse
    # re-raises the real error as the honest quarantine.
    #
    # == Reference edges (deep extraction)
    #
    # Every record's Trismegistos id and Imagines Italicae concordance ride
    # as metadata "related" ("tm:170774", "imit:bouianum-98") and become
    # kind=reference edges after each sync (reference_edges? +
    # reference_producer "itant") — the same tm: key space the CEIPoM
    # packet mints, coordinated through the links journal, no coupling.
    #
    # == fetch / sync policy
    #
    # One git repo through the shared non-destructive GitFetch choreography
    # (#git_fetch!). The project updates as editions are revised (and the
    # Venetic/Faliscan dirs will fill) → sync_policy manual: re-syncs are
    # owner-fired.
    class Itant < Nabu::Adapter
      REPO_URL = "https://github.com/DigItAnt/Corpus_ItAnt"

      CORPUS_DIRS = %w[Oscan_inscriptions_newEditions CelticOfItaly_inscriptions_newEditions].freeze

      TRANSLATION_TITLES = { "ita" => "Italian", "eng" => "English" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "itant",
        name: "Corpus ItAnt — Languages and Cultures of Ancient Italy (PRIN 2017, CNR-ILC/UniFI)",
        license: "CC BY-NC-SA 4.0 (three agreeing layers, verbatim: repo README/license.txt \"Corpus " \
                 "ItAnt is licensed under CC-BY-NC-SA 4.0\"; every record's <licence> \"This file is " \
                 "licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 " \
                 "International license\" — cite Murano et al., JOCCH 16.3 (2023), 10.1145/3606703)",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "itant-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # The tm:/imit: concordance edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "itant")
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter for
      # the opted-in registry row.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # One DocumentRef per (record × citable layer/translation), sorted by
      # urn. A workdir without the corpus dirs yields nothing (the day-one
      # pre-fetch state); the same walk works under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        parser = ItantEpidocParser.new
        case metadata["kind"]
        when "metadata_only"
          parser.parse_metadata_only(document_ref.path, urn: document_ref.id)
        when "translation"
          parse_translation(document_ref, metadata.fetch("language"))
        else
          layer = metadata["layer"] || ItantEpidocParser::INTERPRETATIVE
          parser.parse(document_ref.path, urn: document_ref.id, layer: layer)
        end
      end

      # One git repo, the shared non-destructive choreography (fetch →
      # breaker → attic → ff-merge).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def record_paths(workdir)
        CORPUS_DIRS.flat_map { |dir| Dir.glob(File.join(workdir, dir, "*.xml")) }
      end

      def document_refs(workdir)
        record_paths(workdir).flat_map { |path| record_refs(File.expand_path(path)) }.sort_by(&:id)
      end

      # The record's citable layers + translation siblings, from the
      # parser's OWN census (class note). No citable edition at all (or an
      # unreadable record) → the single metadata-only ref.
      def record_refs(path)
        base = ItantEpidocParser::URN_PREFIX +
               File.basename(path, ".xml").delete_prefix("ItAnt_").downcase.tr("_", "-")
        census = record_census(path)
        return [metadata_only_ref(base, path)] if census.nil? || !census.interpretative

        refs = [Nabu::DocumentRef.new(source_id: manifest.id, id: base, path: path)]
        if census.diplomatic
          refs << Nabu::DocumentRef.new(source_id: manifest.id, id: "#{base}-dipl", path: path,
                                        metadata: { "layer" => ItantEpidocParser::DIPLOMATIC })
        end
        refs + translation_refs(base, path, census)
      end

      def translation_refs(base, path, census)
        return [] unless @translations

        census.translations.map do |language|
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{base}-#{language}", path: path,
            metadata: { "kind" => "translation", "language" => language }
          )
        end
      end

      def metadata_only_ref(base, path)
        Nabu::DocumentRef.new(source_id: manifest.id, id: base, path: path,
                              metadata: { "kind" => "metadata_only" })
      end

      # nil = unreadable record (malformed XML): discovery mints the
      # metadata-only ref, whose parse re-raises the real error as the
      # honest quarantine.
      def record_census(path)
        ItantEpidocParser.new.census(path)
      rescue ParseError
        nil
      end

      # The -ita/-eng sibling: one passage per translation paragraph, cited
      # by textpart subtype or ordinal (ItantEpidocParser#translations);
      # the riig -fr pattern.
      def parse_translation(document_ref, language)
        base = document_ref.id.delete_suffix("-#{language}")
        parser = ItantEpidocParser.new
        original = parser.parse(document_ref.path, urn: base)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          title: translation_title(original.title, language),
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        parser.translations(document_ref.path).fetch(language, []).each_with_index do |(cite, text), sequence|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{cite}", language: language, text: text, sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: no #{language} translation prose for #{document_ref.id}" if
          document.empty?

        document
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def translation_title(title, language)
        label = "#{TRANSLATION_TITLES.fetch(language)} translation"
        title ? "#{title} — #{label}" : label
      end
    end
  end
end
