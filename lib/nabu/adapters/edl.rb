# frozen_string_literal: true

require_relative "lila_ttl_parser"

module Nabu
  module Adapters
    # The de Vaan EDL skeleton adapter (P18-6; .docs/surveys/pie-survey.md §2.2):
    # Michiel de Vaan's *Etymological Dictionary of Latin and the other
    # Italic Languages* (Brill 2008, Leiden IEED series), published by
    # CIRCSE/LiLa as a Linked Open Data ETYMOLOGY SKELETON — entries
    # omitted (Brill copyright), the staged etymon chains included. ONE
    # source, TWO dictionaries from ONE Turtle file (the wiktionary-recon
    # one-source-many-shelves precedent):
    #
    #   edl-ine-pro  (language ine-pro) — 1,394 PIE etymons; reflexes are
    #                the PIt etymons they stage to (proto-to-proto edges,
    #                asterisk kept — the kaikki convention) plus 27 direct
    #                Latin edges with no PIt stage.
    #   edl-itc-pro  (language itc-pro) — 1,466 Proto-Italic etymons;
    #                reflexes are the Latin headwords (1,410 edges).
    #
    # With that split the existing shelf-visited etym walk runs the full
    # Leiden chain lat → PIt → PIE (rōdō ← *(w)rōde/o‑ ← *Hreh₃d‑e/o‑)
    # with ZERO new query code, and the PIt shelf stands beside kaikki's
    # itc-pro as a provenance-distinct second witness (the MW-beside-kaikki
    # precedent; the P18-3 audit: cross-entry same-word is two honest
    # witnesses, not a dupe).
    #
    # == Upstream (censused first-hand, survey §2.2 + fixture build 2026-07-14)
    #
    # github.com/CIRCSE/EtymologicalDictionaryLatin, data/BrillEDL.ttl —
    # 3.9 MB Turtle (lemonEty/Ontolex): 2,860 etymons (1,394 PIE + 1,466
    # PIt), 1,453 Brill LexicalEntry nodes over 1,429 distinct Latin
    # headwords, 2,653 EtyLink edges, ALL etyLinkType "inheritance" (a
    # /borrow/i guard still mints the flag should upstream ever add loan
    # links). Etymon labels use U+2011 NON-BREAKING HYPHEN ("*‑ne",
    # "*Hreh₃d‑e/o‑") — kept verbatim for display, translated to ASCII "-"
    # inside the §9 fold so typed lookups reach the entries. canonicalForm
    # blank nodes (writtenRep variants) duplicate the rdfs:comment variant
    # lists and are not read.
    #
    # == License (repo README, verbatim)
    #
    # "*The Etymological Dictionary of Latin and the other Italic
    # Languages*, authored by M. de Vaan, is copyrighted by Brill. The
    # dictionary entries are not represented. The data included here only
    # serve to express them according to the selected ontology and link
    # them to the Knowledge Base of Latin lemmas of LiLa." + CC BY-NC-SA
    # 4.0 badge → license_class "nc" (the GRETIL/MW posture: local
    # research + index, MCP-surface default-excluded, never redistributed).
    # Cite Mambrini & Passarotti 2020 (Globalex/LREC).
    #
    # == fetch
    #
    # Single-file Nabu::FileFetch of the raw file (sha pin, attic + guard);
    # the raw host serves no Last-Modified, so manual re-syncs refetch
    # unconditionally (3.9 MB). Completed dataset → sync_policy manual.
    class Edl < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "edl",
        name: "de Vaan — Etymological Dictionary of Latin (Brill 2008), LiLa LOD skeleton (CIRCSE)",
        license: "CC BY-NC-SA 4.0 (repo README: de Vaan's EDL \"is copyrighted by Brill… " \
                 "The dictionary entries are not represented\"; cite Mambrini & Passarotti 2020)",
        license_class: "nc",
        upstream_url: "https://raw.githubusercontent.com/CIRCSE/EtymologicalDictionaryLatin/" \
                      "master/data/BrillEDL.ttl",
        parser_family: "lila-ttl"
      )

      FILENAME = "BrillEDL.ttl"

      # One dictionary per reconstruction stage; iteration order is registry
      # order. +stage+ is the upstream lime:language marker the etymons
      # carry verbatim.
      DICTIONARIES = {
        "edl-ine-pro" => {
          language: "ine-pro", stage: "PIE",
          title: "de Vaan, Etymological Dictionary of Latin — PIE etymons (LiLa LOD skeleton)"
        }.freeze,
        "edl-itc-pro" => {
          language: "itc-pro", stage: "PIt",
          title: "de Vaan, Etymological Dictionary of Latin — Proto-Italic etymons (LiLa LOD skeleton)"
        }.freeze
      }.freeze

      # Upstream stage marker → the catalog-side shelf language the
      # crosswalk joins on (conventions §4: the -pro codes verbatim from
      # the Wiktionary namespace the recon shelves already use).
      STAGE_LANGUAGES = { "PIE" => "ine-pro", "PIt" => "itc-pro" }.freeze

      LEMON_ETY = "http://lari-datasets.ilc.cnr.it/lemonEty#"
      ETYMON_TYPE = "#{LEMON_ETY}Etymon".freeze
      ETY_LINK_TYPE = "#{LEMON_ETY}EtyLink".freeze
      ETY_LINK_KIND = "#{LEMON_ETY}etyLinkType".freeze
      ETY_SOURCE = "#{LEMON_ETY}etySource".freeze
      ETY_TARGET = "#{LEMON_ETY}etyTarget".freeze
      LABEL = "http://www.w3.org/2000/01/rdf-schema#label"
      COMMENT = "http://www.w3.org/2000/01/rdf-schema#comment"
      LIME_LANGUAGE = "http://www.w3.org/ns/lemon/lime#language"

      # The rider (P18-6): the per-stage knowledge this source carries,
      # accreted into the ledger's language_notes with provenance "edl"
      # (source-laned kind — see Liv::LANGUAGE_NOTES).
      LANGUAGE_NOTES = [
        ["itc-pro", "witness:edl",
         "Proto-Italic (upstream marker \"PIt\") is the intermediate reconstruction stage of de " \
         "Vaan's Etymological Dictionary of Latin (Brill 2008, Leiden IEED series), held here as " \
         "the CIRCSE/LiLa LOD skeleton: 1,466 PIt etymons staging 1,394 PIE roots down to 1,429 " \
         "Latin headwords — a Leiden-school reconstruction witness beside Wiktionary's itc-pro " \
         "shelf."].freeze,
        ["lat", "witness:edl",
         "de Vaan's EDL (LiLa LOD skeleton) covers, per the upstream dataset description, \"the " \
         "entire Latin lexicon of Indo-European origin… nearly 1900 entries, which altogether " \
         "discuss about 8000 Latin lemmata\"; the skeleton stages 1,429 of its Latin headwords " \
         "through Proto-Italic/PIE etymons. Entry content is Brill-copyrighted and not included " \
         "(license class nc)."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      # ONE file feeds both shelves — one probe target, not one per shelf.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def self.language_notes = LANGUAGE_NOTES

      # One DocumentRef per DICTIONARY, all pointing at the one file: parse
      # filters etymons by stage, so each shelf loads (and quarantines) as
      # its own unit.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          DICTIONARIES.each_key do |slug|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{slug}:#{FILENAME}",
              path: File.expand_path(path), metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        shelf = DICTIONARIES.fetch(slug)
        graph = LilaTtlParser::Graph.new(
          LilaTtlParser.new.statements(File.read(document_ref.path, encoding: Encoding::UTF_8))
        )
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: shelf.fetch(:language),
          title: shelf.fetch(:title), canonical_path: document_ref.path
        )
        links = links_by_source(graph)
        graph.subjects_of_type(ETYMON_TYPE).each do |etymon|
          next unless graph.first(etymon, LIME_LANGUAGE) == shelf.fetch(:stage)

          document << build_entry(graph, etymon, shelf, links.fetch(etymon, []))
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "edl: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "edl fetch failed into #{workdir}: #{e.message}"
      end

      private

      # etySource IRI → [[target IRI, link kind], …], document order. A
      # source-less link has nothing to attach to and is dropped honestly.
      def links_by_source(graph)
        graph.subjects_of_type(ETY_LINK_TYPE).each_with_object({}) do |link, map|
          source = graph.first(link, ETY_SOURCE) or next
          kind = graph.first(link, ETY_LINK_KIND).to_s
          graph.objects(link, ETY_TARGET).each { |target| (map[source] ||= []) << [target, kind] }
        end
      end

      def build_entry(graph, etymon, shelf, links)
        label = graph.first(etymon, LABEL) or
          raise Nabu::ParseError, "edl: etymon #{etymon} has no rdfs:label"
        headword = label.delete_prefix("*").strip
        Nabu::DictionaryEntry.new(
          entry_id: etymon.split("/").last, key_raw: label,
          language: shelf.fetch(:language),
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: fold(headword, shelf.fetch(:language)),
          gloss: nil,
          body: body_text(graph, etymon, label),
          reflexes: links.filter_map { |target, kind| build_reflex(graph, target, kind) }
        )
      end

      # The rdfs:comment values, variant reconstructions first, then the
      # "Etymology for: <headword> (laNNNN)" pointers — both kept verbatim
      # (canonical means canonical). Label fallback keeps body non-empty.
      def body_text(graph, etymon, label)
        variants, pointers = graph.objects(etymon, COMMENT)
                                  .partition { |comment| !comment.start_with?("Etymology for:") }
        lines = variants + pointers
        Nabu::Normalize.nfc(lines.empty? ? label : lines.join("\n"))
      end

      # A staged target (another etymon) mints a proto-to-proto edge with
      # its upstream stage marker as lang_code and the asterisk kept; a
      # Brill LexicalEntry target mints a Latin edge (lang_code "la" — the
      # upstream entry ids are la####). Label-less targets mint nothing.
      # All censused links are "inheritance"; the /borrow/i guard mirrors
      # the kaikki loan-marker rule should upstream ever add loan links.
      def build_reflex(graph, target, kind)
        word = graph.first(target, LABEL) or return nil

        stage = graph.first(target, LIME_LANGUAGE)
        lang_code = stage || "la"
        language = stage ? STAGE_LANGUAGES[stage] : "lat"
        nfc = Nabu::Normalize.nfc(word)
        Nabu::DictionaryReflex.new(
          lang_code: lang_code, language: language, word: nfc,
          word_folded: fold(nfc.delete_prefix("*"), language || "und"),
          borrowed: kind.match?(/borrow/i)
        )
      end

      # The §9 fold with the upstream U+2011 non-breaking hyphen opened to
      # ASCII first — display keeps the upstream character, lookups type "-".
      def fold(text, language)
        folded = Nabu::Normalize.search_form(text.tr("‑", "-"), language: language)
        folded.strip.empty? ? nil : folded
      end
    end
  end
end
