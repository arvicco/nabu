# frozen_string_literal: true

require "fileutils"
require "yaml"

module Nabu
  module Adapters
    # The sabellic-loans adapter (P29-2 rider): curated Sabellic → Latin
    # loan edges — the P17-3 `borrowed` pattern as three tiny dictionary
    # shelves (Oscan osc, Umbrian xum, Sabine sbv), companions to the
    # ItAnt/CEIPoM epigraphic witnesses: `nabu etym rufus` now answers with
    # the Oscan/Umbrian etyma and the loan flag on each Latin edge.
    #
    # == The curation (config/sabellic_loans.yml — the artifact itself)
    #
    # Word lists curated 2026-07-18 from the en.wiktionary category pages
    # ("Latin terms borrowed from Oscan" ×23 / "derived from Oscan" ×48 ·
    # Umbrian 6/11 · Sabine 13/26 — the borrowed sets are subsets), member
    # lists via the MediaWiki API, each Latin entry's OWN {{bor}}/{{der}}
    # etymology template read for the source-language etymon (Old Italic
    # script forms verbatim — 𐌓𐌖𐌚𐌓𐌉𐌉𐌔; the U+10300 display note in
    # docs/display.md is these headwords' terminal story). Explicit
    # borrowings mint borrowed=true reflex edges; derived-only lemmas
    # (indirect or unspecified transmission) mint borrowed=false — the
    # P17-3 no-marker semantics, never a guess. Where en.wiktionary cites
    # no source-language form the LATIN lemma stands as the entry headword
    # and the body says so honestly.
    #
    # == Shape
    #
    # One DictionaryDocument per source language: slugs sabellic-osc /
    # sabellic-xum / sabellic-sbv (urn:nabu:dict:sabellic-osc:rufus…),
    # entry per Latin lemma, one lat reflex row each — the reflex-roots
    # walk and `etym`/`cognates` light up with zero new query code.
    #
    # == fetch / sync policy — a REPO-CURATED shelf
    #
    # No upstream and no network, ever: en.wiktionary is the cited
    # PROVENANCE (retrieval date in the file header), not a fetch target —
    # re-curation is a deliberate repo change, not a sync. `Adapter#fetch`
    # (the one sanctioned canonical writer) materializes the vendored file
    # under canonical/sabellic-loans/ (tmp+rename, byte-identical copy),
    # then the house LocalFetch scan pins it — sync_policy `local`, the
    # §16 posture: probe short-circuits, `nabu health` holds the tree
    # against the pins.
    #
    # == License
    #
    # Wiktionary's dual grant (the kaikki/wiktionary-recon precedent) →
    # attribution, MCP-surface-safe.
    class SabellicLoans < Nabu::Adapter
      CONFIG_PATH = File.expand_path("../../../config/sabellic_loans.yml", __dir__)
      FILENAME = "sabellic_loans.yml"

      MANIFEST = Nabu::SourceManifest.new(
        id: "sabellic-loans",
        name: "Sabellic → Latin loans — en.wiktionary curation (Oscan/Umbrian/Sabine)",
        license: "CC BY-SA + GFDL (the Wiktionary dual grant; curated word lists from the " \
                 "en.wiktionary 'Latin terms borrowed/derived from Oscan/Umbrian/Sabine' " \
                 "category pages, retrieved 2026-07-18)",
        license_class: "attribution",
        upstream_url: "https://en.wiktionary.org/wiki/Category:Latin_terms_derived_from_Oscan",
        parser_family: "curated-yaml"
      )

      # One dictionary shelf per source language, registry order (discover/
      # parse speak it). Slugs mint the urn namespaces
      # (urn:nabu:dict:sabellic-osc:<latin lemma>).
      SHELVES = {
        "sabellic-osc" => { key: "osc", language: "osc", name: "Oscan",
                            title: "Sabellic loans — Oscan → Latin (en.wiktionary curation)" }.freeze,
        "sabellic-xum" => { key: "xum", language: "xum", name: "Umbrian",
                            title: "Sabellic loans — Umbrian → Latin (en.wiktionary curation)" }.freeze,
        "sabellic-sbv" => { key: "sbv", language: "sbv", name: "Sabine",
                            title: "Sabellic loans — Sabine → Latin (en.wiktionary curation)" }.freeze
      }.freeze

      # The P18-6 language-notes rider ([lang_code, kind, body] rows,
      # accreted by DictionaryLoader under the writer-owned witness lane).
      LANGUAGE_NOTES = [
        ["osc", "witness:sabellic-loans",
         "en.wiktionary loan curation (retrieved 2026-07-18): 48 Latin lemmas derived from " \
         "Oscan, 23 of them explicit borrowings (rufus, tofus, prope, the Pompeii names…) — " \
         "loan edges with Old Italic etyma where the entries cite them, beside the ItAnt and " \
         "CEIPoM epigraphic witnesses."].freeze,
        ["xum", "witness:sabellic-loans",
         "en.wiktionary loan curation (retrieved 2026-07-18): 11 Latin lemmas derived from " \
         "Umbrian, 6 explicit borrowings (omentum, gumia, Iguvium…) — the lexical shadow of " \
         "Rome's Umbrian neighbors."].freeze,
        ["sbv", "witness:sabellic-loans",
         "en.wiktionary loan curation (retrieved 2026-07-18): 26 Latin lemmas derived from " \
         "Sabine, 13 explicit borrowings (hirpus, strena, Quirites, Nero…). Sabine survives " \
         "almost only through such Latin glosses — this shelf IS most of its attestation."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      # No git upstream (P39-0): config/sabellic_loans.yml IS the vendored
      # artifact and the manifest url is the en.wiktionary PROVENANCE page, not
      # a repo. Declaring [] keeps the remote probe from ls-remoting it — the
      # frozen source reads as vendored (alive by its canonical tree) instead.
      def self.upstream_repo_urls = []

      def self.content_kind = :dictionary

      def self.language_notes = LANGUAGE_NOTES

      # One DocumentRef per shelf, SHELVES order — all three parse the one
      # curated file. A workdir without it yields nothing (pre-fetch).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        SHELVES.each_key do |slug|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{slug}:#{FILENAME}",
            path: File.expand_path(path), metadata: { "dictionary" => slug }
          )
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        shelf = SHELVES.fetch(slug)
        data = read_config(document_ref.path)
        source = data.fetch("sources").fetch(shelf.fetch(:key))
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: shelf.fetch(:language),
          title: shelf.fetch(:title), canonical_path: document_ref.path
        )
        source.fetch("words").each do |word|
          document << build_entry(shelf, word, retrieved: data.fetch("retrieved"))
        end
        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "sabellic-loans: #{document_ref.id}: #{e.message}"
      end

      # Materialize the vendored curation under canonical/ (tmp+rename,
      # write only when the bytes differ), then the house LocalFetch scan
      # pins it (class note).
      def fetch(workdir, progress: nil, force: false)
        FileUtils.mkdir_p(workdir)
        target = File.join(workdir, FILENAME)
        bytes = File.binread(CONFIG_PATH)
        unless File.file?(target) && File.binread(target) == bytes
          progress&.call("Vendoring #{FILENAME}…\n")
          File.binwrite("#{target}.tmp", bytes)
          File.rename("#{target}.tmp", target)
        end
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force)
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        repos: result.files.merge(result.vanished).transform_keys { |rel| "local:#{rel}" })
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      private

      def read_config(path)
        YAML.safe_load_file(path) || {}
      rescue Psych::SyntaxError => e
        raise Nabu::ParseError, "sabellic-loans: malformed YAML at #{path}: #{e.message}"
      end

      # One entry per curated Latin lemma: headword = the cited etymon
      # (lemma fallback), one lat reflex carrying the borrowed flag.
      def build_entry(shelf, word, retrieved:)
        latin = Nabu::Normalize.nfc(word.fetch("latin"))
        etymon = word["etymon"] && Nabu::Normalize.nfc(word["etymon"])
        headword = etymon || latin
        borrowed = word.fetch("relation") == "borrowed"
        Nabu::DictionaryEntry.new(
          entry_id: latin, key_raw: latin, language: shelf.fetch(:language),
          headword: headword,
          headword_folded: folded(headword, shelf.fetch(:language)) || latin.downcase,
          body: body_for(shelf, word, latin: latin, etymon: etymon, borrowed: borrowed, retrieved: retrieved),
          reflexes: [Nabu::DictionaryReflex.new(
            lang_code: "la", language: "lat", word: latin,
            word_folded: folded(latin, "lat"), borrowed: borrowed
          )]
        )
      end

      def folded(text, language)
        form = Nabu::Normalize.search_form(text.delete_prefix("*"), language: language)
        form.empty? ? nil : form
      end

      def body_for(shelf, word, latin:, etymon:, borrowed:, retrieved:)
        name = shelf.fetch(:name)
        relation = borrowed ? "an explicit borrowing from" : "derived (transmission unspecified) from"
        origin = if etymon
                   translit = word["translit"] && Nabu::Normalize.nfc(word["translit"])
                   "#{name} #{etymon}#{" (#{translit})" if translit}"
                 else
                   "#{name} — no #{name} form is cited"
                 end
        "Latin #{latin} is #{relation} #{origin}. Curated from the en.wiktionary category " \
          "\"Latin terms #{borrowed ? 'borrowed' : 'derived'} from #{name}\", retrieved #{retrieved}."
      end
    end
  end
end
