# frozen_string_literal: true

require_relative "calfa_tsv_parser"
require_relative "calfa_etymology_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The Calfa Classical Armenian dictionary (calfa-co/lexical-databases):
    # the source files of dictionary.calfa.fr, the Classical Armenian–
    # French–English dictionary digitized, OCR-proofread and standardized by
    # the Calfa team (2014–2017; Calouste Gulbenkian Foundation and
    # Ghoukassiantz Brothers support). The library's FIRST Armenian
    # dictionary shelf, dictionary-shaped (the lexica / dillmann molds),
    # language xcl — the registry anchor (nabu-lects: xcl "Classical
    # Armenian" → axm → hy); the "*"-marked middle/pre-modern forms ride as
    # an entry annotation, not a second lect (upstream marks them only
    # coarsely, "middle or pre-modern forms and translations").
    #
    # == What upstream compiled (README, "bold references are fully
    # included")
    #
    # Awetikʿean–Siwrmēlean–Awgerean, Nor baṙgirkʿ haykazean lezui (NBHL,
    # Venice 1836–37); Bedrossian, New Dictionary Armenian-English (Venice
    # 1875); Calfa, Dictionnaire arménien-français (Paris 1861); plus
    # Ačaṙean's etymological dictionary (1926, an AI-processed working
    # document) and Łazarean's synonyms dictionary (2006). Upstream gives NO
    # per-row attribution to the printed dictionaries: the repo is split by
    # FUNCTION and LANGUAGE, and that is the split this shelf keeps — one
    # dictionary slug per (the lexica precedent):
    #
    #   calfa-en        definitions/en-definitions01.tsv        41,317 rows
    #                   definitions_proper/en-definitions01.tsv    918 (np:)
    #   calfa-fr        definitions/fr-definitions01.tsv        31,586 rows
    #                   definitions_proper/fr-definitions01.tsv    920 (np:)
    #   calfa-acharian  etymology/etymology01.xml               11,326 entries
    #
    # The English table is built chiefly on Bedrossian, the French on Calfa
    # 1861, both enriched from NBHL (its Armenian-language notes surface in
    # places, e.g. the proper-name prose) — a compilation, so the titles
    # say "compiled", never a single print.
    #
    # == Grains + reconciliation (census 2026-10-21, upstream 71109ce)
    #
    # Upstream serves one git repo: six data files, each a table of one
    # ENTRY per row (the XML: per <entry>). Accepted: the five files above,
    # 86,067 entries. REJECTED by rule: synonyms/synonyms01.tsv (31,449
    # rows) — Łazarean 2006 is in-copyright material carried under Calfa's
    # grant; held back until ruled on, counted in discovery_skips with its
    # note. Any OTHER *.tsv/*.xml (a new language table, a 02 split) is
    # UNRECOGNIZED — loud, never silently ingested or dropped. The README's
    # headline "65,430 entries" reconciles to no file sum or headword union
    # (all six files' headwords, marks stripped and case-folded: 60,058) —
    # it counts the web dictionary's compiled entries, not the repo's rows;
    # the accepted+skipped rows (117,516) account for every data row
    # upstream serves.
    #
    # == License
    #
    # README verbatim: "These data can be freely used under a CC BY-NC 4.0
    # license" (linked to creativecommons.org/licenses/by-nc/4.0/; no
    # LICENSE file, the GitHub license field is empty; re-verified
    # 2026-10-21) → class nc (never redistributed — the MW/Dillmann
    # posture). Citation per upstream: the website, the repo, and
    # Vidal-Gorène & Decours-Perez, LREC 2020.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (~23 MB working tree) through the
    # attic + breaker contract. Upstream takes small corrections every few
    # weeks (last push 2026-09-29) → sync_policy manual.
    class CalfaLexicon < Nabu::Adapter
      REPO_URL = "https://github.com/calfa-co/lexical-databases"
      LANGUAGE = "xcl"

      # The three dictionaries, slug → title (files map to slugs by
      # TABLE/ETYMOLOGY below; the proper-name tables share their language's
      # slug under np: ids).
      DICTIONARIES = {
        "calfa-en" => "Calfa — Classical Armenian–English dictionary (compiled: NBHL 1836–37, " \
                      "Bedrossian 1875)",
        "calfa-fr" => "Calfa — Classical Armenian–French dictionary (compiled: NBHL 1836–37, " \
                      "Calfa 1861)",
        "calfa-acharian" => "Ačaṙean, Hayerēn armatakan baṙaran (Erevan 1926) — Calfa working document"
      }.freeze

      TABLE = %r{\A(definitions|definitions_proper)/(en|fr)-definitions\d+\.tsv\z}
      ETYMOLOGY = %r{\Aetymology/etymology\d+\.xml\z}
      SYNONYMS = %r{\Asynonyms/[^/]+\.tsv\z}
      DATA_GLOB = "*/*.{tsv,xml}"

      SYNONYMS_NOTE = "synonyms held back by rule — Łazarean, Dictionary of Classical Armenian " \
                      "Synonyms (Antelias 2006), in-copyright material carried under Calfa's grant"

      MANIFEST = Nabu::SourceManifest.new(
        id: "calfa-lexicon",
        name: "Calfa — Classical Armenian dictionary databases (NBHL, Bedrossian, Calfa 1861, Ačaṙean)",
        license: "CC BY-NC 4.0 (class nc). README verbatim: \"These data can be freely used under a " \
                 "CC BY-NC 4.0 license\" (github.com/calfa-co/lexical-databases, no LICENSE file; " \
                 "verified 2026-10-21). Caveat: the synonyms table is Łazarean 2006, in-copyright " \
                 "material carried under Calfa's grant — not ingested. Credit Calfa " \
                 "(dictionary.calfa.fr) and Vidal-Gorène & Decours-Perez, LREC 2020",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "calfa-tsv",
        credit: "Calfa (dictionary.calfa.fr; github.com/calfa-co/lexical-databases) — after NBHL " \
                "(1836–37), Bedrossian (1875), Calfa (1861) and Ačaṙean (1926)"
      )

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild load
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        data_files(workdir).filter_map { |relative| document_ref(workdir, relative) }
                           .sort_by(&:id).each(&block)
      end

      # The rejected synonyms grain (skipped by rule) and anything else
      # data-shaped discover does not recognize (loud).
      def discovery_skips(workdir)
        files = data_files(workdir).reject { |relative| accepted?(relative) }
        synonyms, strays = files.partition { |relative| SYNONYMS.match?(relative) }
        notes = synonyms.map { |relative| "#{relative}: #{SYNONYMS_NOTE}" } +
                strays.map { |relative| "#{relative}: not a recognized calfa data file" }
        DiscoverySkips.new(skipped_by_rule: synonyms.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        relative = document_ref.metadata.fetch("path")
        document = Nabu::DictionaryDocument.new(slug: slug, language: LANGUAGE, title: DICTIONARIES.fetch(slug),
                                                canonical_path: document_ref.path)
        entries(document_ref.path, relative).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "calfa-lexicon: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url = REPO_URL

      def data_files(workdir)
        Dir.glob(DATA_GLOB, base: workdir).select { |relative| File.file?(File.join(workdir, relative)) }.sort
      end

      def accepted?(relative) = TABLE.match?(relative) || ETYMOLOGY.match?(relative)

      def document_ref(workdir, relative)
        slug = slug_for(relative) or return nil
        Nabu::DocumentRef.new(source_id: manifest.id, id: "#{slug}:#{relative}",
                              path: File.expand_path(relative, workdir),
                              metadata: { "dictionary" => slug, "path" => relative })
      end

      def slug_for(relative)
        return "calfa-acharian" if ETYMOLOGY.match?(relative)

        match = TABLE.match(relative) or return nil
        "calfa-#{match[2]}"
      end

      def entries(path, relative)
        text = SourceRead.utf8_file(path, label: "calfa-lexicon")
        if ETYMOLOGY.match?(relative)
          CalfaEtymologyParser.new.entries(text, language: LANGUAGE, label: relative)
        else
          prefix = relative.start_with?("definitions_proper/") ? "np" : nil
          CalfaTsvParser.new.entries(text, language: LANGUAGE, label: relative, id_prefix: prefix)
        end
      end
    end
  end
end
