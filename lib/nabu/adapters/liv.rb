# frozen_string_literal: true

require_relative "lila_ttl_parser"

module Nabu
  module Adapters
    # The LIV adapter (P18-6; docs/pie-survey.md §2.1): Helmut Rix's *Lexikon
    # der indogermanischen Verben* (2nd ed. 2001) as Linked Open Data,
    # published by CIRCSE (Università Cattolica Milan, the LiLa: Linking
    # Latin project) — the FIRST non-Wiktionary reconstruction shelf, the
    # reference PIE VERB inventory second-witnessing kaikki's ine-pro roots
    # on the lat axis. One dictionary (slug liv, language ine-pro): one
    # entry per LIV etymon (headword = the laryngeal-notation root), Latin
    # continuations as DictionaryReflex rows joining gold lat through the
    # conventions-§9 u/v fold (LIV writtenReps are u-spelling — uireo).
    #
    # == Upstream (censused first-hand, survey §2.1 + fixture build 2026-07-14)
    #
    # github.com/CIRCSE/LIV, ttl/LIV.ttl — 657 KB Turtle (lemonEty/Ontolex),
    # 305 PIE etymons / 385 Latin lexical entries / 340 writtenReps / 426
    # stem-typed themes, Latin slice ONLY (the print dictionary's 550 Latin
    # word forms; the Germanic/Greek/etc. reflex columns are not included).
    # The dataset is a completed publication (CLiC-it 2023 paper); no
    # release cadence — sync_policy manual.
    #
    # == License (repo README, verbatim — the publisher-permission quote)
    #
    # "The publisher of the dictionary allowed us to model and publish the
    # etymological relations between PIE roots, stems and Latin word forms
    # contained in the data." + the CC BY-SA 4.0 badge ("These resources are
    # licensed under a Creative Commons Attribution-ShareAlike 4.0
    # International License") → attribution, MCP-surface-safe. Credit:
    # Rix/Kümmel/Zehnder/Lipp/Schirmer (creators); Boano/Passarotti/
    # Mambrini/Ginevra/Moretti (LiLa modellers; cite Boano et al.,
    # CLiC-it 2023).
    #
    # == The stem-type layer (the packet's NEW annotation axis)
    #
    # LIV's per-root verbal-stem formations (present/aorist/perfect/
    # causative/desiderative/essive… themes) are an annotation layer no
    # kaikki shelf carries and nabu has no schema surface for. Verdict:
    # the minimal honest home is the ENTRY BODY — one line per theme,
    # "<stem type> <reconstructed theme> → <tense-tag Latin continuation>"
    # ("present stem *dʰu̯éh₂-/dʰuh₂- → pres suffio") — rendered by define
    # with ZERO new schema or query code. Not gloss (these are formations,
    # not meanings — the LOD ships no meanings, and nil gloss is honest);
    # not a new table (a one-source schema for a 426-row layer fails the
    # don't-over-build bar; revisit if a second stem-typed source lands).
    # A shared placeholder theme (label "–", IRI …/Themes/-) is reused
    # across etymons: links are scoped per THIS etymon's etymologies, so
    # the placeholder never leaks other verbs' continuations.
    #
    # == fetch
    #
    # Single-file Nabu::FileFetch of the raw.githubusercontent URL (sha256
    # pin, attic + mass-deletion guard) — a git clone would drag the repo's
    # history and side files for one data file (the kaikki/MW precedent;
    # the survey: "Both are single-file FileFetch syncs"). GitHub's raw host
    # serves no Last-Modified, so a manual re-sync refetches unconditionally
    # — 657 KB, acceptable.
    class Liv < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "liv",
        name: "LIV — Lexikon der indogermanischen Verben (Rix 2001), LiLa LOD (CIRCSE)",
        license: "CC BY-SA 4.0 (repo README: \"The publisher of the dictionary allowed us to model " \
                 "and publish the etymological relations between PIE roots, stems and Latin word " \
                 "forms contained in the data.\"; credit Rix et al. + CIRCSE/LiLa, Boano et al. CLiC-it 2023)",
        license_class: "attribution",
        upstream_url: "https://raw.githubusercontent.com/CIRCSE/LIV/master/ttl/LIV.ttl",
        parser_family: "lila-ttl"
      )

      FILENAME = "LIV.ttl"
      DICTIONARY_SLUG = "liv"
      LANGUAGE = "ine-pro"
      TITLE = "LIV — Lexikon der indogermanischen Verben (LiLa LOD, Latin slice)"

      # lemonEty/Ontolex vocabulary, expanded (the lila-ttl reader returns
      # full IRIs).
      LEMON_ETY = "http://lari-datasets.ilc.cnr.it/lemonEty#"
      ETYMON_TYPE = "#{LEMON_ETY}Etymon".freeze
      ETYMOLOGY_TYPE = "#{LEMON_ETY}Etymology".freeze
      ETYMOLOGY_OF_ENTRY = "#{LEMON_ETY}etymology".freeze
      ETYMON_OF_ETYMOLOGY = "#{LEMON_ETY}etymon".freeze
      HAS_ETY_LINK = "#{LEMON_ETY}hasEtyLink".freeze
      ETY_SOURCE = "#{LEMON_ETY}etySource".freeze
      LEXICAL_ENTRY_TYPE = "http://www.w3.org/ns/lemon/ontolex#LexicalEntry"
      LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
      LEXICAL_REL = "http://www.w3.org/ns/lemon/vartrans#lexicalRel"
      STEM_TYPE = "http://lila-erc.eu/ontologies/prinparlat/stemType"
      LINK_LABEL_PREFIX = "Etymology link: "

      # The rider (P18-6, the P18-4 accretion layer): what this source says
      # about its language stage, appended to the ledger's language_notes by
      # DictionaryLoader with per-record provenance (source "liv"). The kind
      # is source-laned ("witness:liv") so witnesses never supersede each
      # other or the seed's curated "context" under the latest-per-(code,
      # kind) read.
      LANGUAGE_NOTES = [
        ["ine-pro", "witness:liv",
         "LIV — Lexikon der indogermanischen Verben (Rix et al., 2nd ed. 2001) as LiLa Linked " \
         "Open Data (CIRCSE, publisher-permitted skeleton): 305 laryngeal-notation PIE verbal " \
         "roots with their stem formations (present/aorist/perfect/causative/desiderative…), " \
         "Latin slice only — 385 Latin continuations of the print dictionary's 550 Latin word " \
         "forms. The reference PIE verb inventory, a Rix-school witness beside kaikki's ine-pro."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{FILENAME}",
            path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        graph = LilaTtlParser::Graph.new(
          LilaTtlParser.new.statements(File.read(document_ref.path, encoding: Encoding::UTF_8))
        )
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        entry_by_etymology = latin_entries_by_etymology(graph)
        etymologies = etymologies_by_etymon(graph)
        graph.subjects_of_type(ETYMON_TYPE).each do |etymon|
          document << build_entry(graph, etymon, etymologies.fetch(etymon, []), entry_by_etymology)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "liv: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "liv fetch failed into #{workdir}: #{e.message}"
      end

      private

      # etymology IRI → the Latin LexicalEntry label naming it (the reflex
      # word; LIV entry labels ARE the u-spelling Latin lemmas).
      def latin_entries_by_etymology(graph)
        graph.subjects_of_type(LEXICAL_ENTRY_TYPE).each_with_object({}) do |entry, map|
          label = graph.first(entry, LABEL) or next
          graph.objects(entry, ETYMOLOGY_OF_ENTRY).each { |etymology| map[etymology] ||= label }
        end
      end

      # etymon IRI → its etymology IRIs, file order (one etymon can back
      # several Latin entries — 305 etymons over 385 etymologies).
      def etymologies_by_etymon(graph)
        graph.subjects_of_type(ETYMOLOGY_TYPE).each_with_object({}) do |etymology, map|
          etymon = graph.first(etymology, ETYMON_OF_ETYMOLOGY) or next
          (map[etymon] ||= []) << etymology
        end
      end

      def build_entry(graph, etymon, etymologies, entry_by_etymology)
        label = graph.first(etymon, LABEL) or
          raise Nabu::ParseError, "liv: etymon #{etymon} has no rdfs:label"
        headword = clean_headword(label)
        Nabu::DictionaryEntry.new(
          entry_id: etymon.split("/").last, key_raw: label,
          language: LANGUAGE,
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: nil,
          body: body_text(graph, etymon, etymologies, label),
          reflexes: reflexes(graph, etymologies, entry_by_etymology)
        )
      end

      # The LIV lemma markers, stripped for lookup/display and kept in
      # key_raw: a leading homonym index ("1.*u̯ei̯s-{1}"), the
      # reconstruction asterisk (display re-adds it — the kaikki
      # convention), an uncertainty "?", and the trailing "{n}" homonym
      # disambiguator.
      def clean_headword(label)
        label.sub(/\A\d+\./, "").sub(/\A\?/, "").delete_prefix("*").sub(/\{\d+\}\z/, "").strip
      end

      # One body line per stem-typed theme of the etymon, document order,
      # each with the tense-tagged Latin continuations of THIS etymon's
      # etymology links ("present stem *dʰu̯éh₂-/dʰuh₂- → pres suffio").
      # Scoping the links per etymon is what keeps the shared placeholder
      # theme ("–") honest. A linkless theme renders bare; an etymon with
      # no themes falls back to its verbatim label.
      def body_text(graph, etymon, etymologies, label)
        tails = link_tails_by_theme(graph, etymologies)
        themes = graph.objects(etymon, LEXICAL_REL) | tails.keys
        lines = themes.map do |theme|
          head = [stem_type_label(graph, theme), graph.first(theme, LABEL)].compact.join(" ")
          continuation = tails.fetch(theme, [])
          continuation.empty? ? head : "#{head} → #{continuation.join(', ')}"
        end
        Nabu::Normalize.nfc(lines.reject(&:empty?).join("\n").then { |text| text.empty? ? label : text })
      end

      # theme IRI → the link-label tails ("pres suffio", "perf peperci") of
      # this etymon's etymologies' links sourced at that theme.
      def link_tails_by_theme(graph, etymologies)
        etymologies.flat_map { |etymology| graph.objects(etymology, HAS_ETY_LINK) }
                   .each_with_object({}) do |link, map|
          theme = graph.first(link, ETY_SOURCE) or next
          tail = graph.first(link, LABEL).to_s.delete_prefix(LINK_LABEL_PREFIX).strip
          (map[theme] ||= []) << tail unless tail.empty?
        end
      end

      def stem_type_label(graph, theme)
        stem_type = graph.first(theme, STEM_TYPE) or return nil

        graph.first(stem_type, LABEL)
      end

      # One reflex per (etymon, Latin entry) pair: lang_code/language "lat"
      # (the dataset IS the Latin slice — upstream marks only the etymons'
      # "PIE"), u-spelling word folded through §9 lat (v→u already unified).
      def reflexes(_graph, etymologies, entry_by_etymology)
        etymologies.filter_map { |etymology| entry_by_etymology[etymology] }.uniq.map do |word|
          nfc = Nabu::Normalize.nfc(word)
          Nabu::DictionaryReflex.new(
            lang_code: "lat", language: "lat", word: nfc,
            word_folded: Nabu::Normalize.search_form(nfc, language: "lat"),
            borrowed: false
          )
        end
      end
    end
  end
end
