# frozen_string_literal: true

require "digest"
require "yaml"

require_relative "../normalize"
require_relative "../adapters/sabellic_loans"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The lat/sabellic-loans builder (P52-5): publishes the hand-curated
    # Sabellic (Oscan osc / Umbrian xum / Sabine sbv) → Latin loan rows as a
    # nabu-data dataset. OWN CURATION — no canonical corpus inputs: the table
    # is config/sabellic_loans.yml, the SAME repo-vendored curation the
    # sabellic-osc/xum/sbv dictionary shelves parse (one source of truth,
    # two consumers; en.wiktionary category pages are the cited provenance,
    # retrieval date in the file header).
    #
    # == License (owner ruling D51-a)
    #
    # The curation derives from en.wiktionary's dual CC BY-SA 4.0 + GFDL
    # grant — share-alike, so the dataset publishes as CC-BY-SA-4.0 (the one
    # honest single choice among the dual grant's options); the dual upstream
    # grant is noted in every citation and in the README notes. The feature's
    # manifest is authoritative over nabu-data's repo-default CC BY.
    #
    # == The language call (slug lat/…)
    #
    # Every row carries a Latin lemma — the loans LIVE in Latin (only 23 of
    # 85 rows cite a Sabellic form at all, and Sabine survives almost only
    # through these Latin glosses) — so languages.csv lists lat and
    # Language_ID is "lat" throughout; the Sabellic source language rides in
    # the Etymon_Language column (osc/xum/sbv), documented in the notes (the
    # wylie-fold precedent for stating wider language scope in prose).
    #
    # Because the feature has no canonical cones, the derivation fingerprint
    # has exactly one moving part — the recipe — so the recipe embeds the
    # curation file's sha256: a re-curation re-fingerprints the dataset (the
    # wylie-fold precedent).
    class SabellicLoansBuilder
      CONFIG_PATH = Adapters::SabellicLoans::CONFIG_PATH
      FILENAME = "loans.csv"
      COLUMNS = %w[ID Language_ID Form Relation Etymon_Language Etymon Etymon_Translit Source].freeze
      LANGUAGE_ID = "lat"

      # sources.bib keys, one per source language — cited from every row's
      # Source cell.
      BIB_KEYS = { "osc" => "wiktionary-oscan", "xum" => "wiktionary-umbrian",
                   "sbv" => "wiktionary-sabine" }.freeze

      # The curation's closed relation vocabulary (the P17-3 semantics): a
      # value outside it is a curation typo and must fail the build, never
      # publish as data.
      RELATIONS = %w[borrowed derived].freeze

      NOTES = <<~NOTES.strip
        ## The curation

        Rows are curated by hand from the en.wiktionary category pages
        "Latin terms borrowed from / derived from Oscan · Umbrian · Sabine"
        (member lists via the MediaWiki API; retrieval date in every
        citation), with each Latin entry's OWN {{bor|la|…}}/{{der|la|…}}
        etymology template read for the source-language etymon. Census:
        85 rows — Oscan 48 (23 borrowed), Umbrian 11 (6), Sabine 26 (13).
        The same curation file powers Nabu's sabellic-osc/xum/sbv dictionary
        shelves and their borrowed-flag etymology edges.

        ## Columns and semantics

        `Form` is the Latin lemma; `Language_ID` is `lat` throughout — the
        loans live in Latin, and `languages.csv` carries that one row.
        `Etymon_Language` names the Sabellic source in ISO 639-3: `osc`
        Oscan (osca1244), `xum` Umbrian (umbr1253), `sbv` Sabine
        (sabi1245). `Relation` is the curation's closed vocabulary,
        verbatim: `borrowed` = the lemma sits in the explicit "borrowed
        from X" category; `derived` = only in the "derived from X" superset
        (indirect or unspecified transmission — never a guess). `Etymon`
        carries the cited source-language form verbatim (Old Italic script
        where en.wiktionary gives it; a leading `*` marks a reconstructed
        etymon); an empty cell means no source-language form is cited —
        absence is honest, never filled in. `Etymon_Translit` is the
        curated transliteration where one is recorded.

        ## Licensing

        Upstream is dual-licensed CC BY-SA 4.0 + GFDL (the Wiktionary
        grant); this dataset publishes under CC BY-SA 4.0, the one honest
        single choice — see the License line above and each citation's note.

        ## Loading

            import pandas as pd
            df = pd.read_csv("loans.csv", keep_default_na=False)
      NOTES

      def initialize(config_path: CONFIG_PATH)
        @config_path = config_path
      end

      # The builder contract: read the curation, write loans.csv into
      # out_dir, describe the derivation. The catalog is deliberately unused
      # — the curation file is the whole input.
      def build(catalog:, out_dir:) # rubocop:disable Lint/UnusedMethodArgument
        data = read_config
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS,
                                rows: table_rows(data))
        BuildResult.new(resources: [resource(count)], recipe: recipe,
                        citations: citations(data), notes: NOTES)
      end

      private

      def read_config
        raise Error, "curation file missing: #{@config_path}" unless File.file?(@config_path)

        YAML.safe_load_file(@config_path) || {}
      rescue Psych::SyntaxError => e
        raise Error, "sabellic-loans curation is malformed YAML (#{@config_path}): #{e.message}"
      end

      # YAML order kept throughout (osc → xum → sbv, lemmas in curation
      # order): the build is a pure function of the file, so build-twice is
      # byte-identical.
      def table_rows(data)
        data.fetch("sources").flat_map do |key, source|
          source.fetch("words").map { |word| row(key, word) }
        end
      rescue KeyError => e
        raise Error, "sabellic-loans curation is missing a required key: #{e.message}"
      end

      def row(key, word)
        latin = Normalize.nfc(word.fetch("latin"))
        relation = word.fetch("relation")
        unless RELATIONS.include?(relation)
          raise Error, "sabellic-loans: #{latin.inspect} carries relation #{relation.inspect} — " \
                       "the curation vocabulary is #{RELATIONS.inspect}"
        end

        { "ID" => CsvWriter.mint_id(key, latin), "Language_ID" => LANGUAGE_ID,
          "Form" => latin, "Relation" => relation, "Etymon_Language" => key,
          "Etymon" => optional(word["etymon"]), "Etymon_Translit" => optional(word["translit"]),
          "Source" => bib_key(key) }
      end

      def optional(value)
        value && Normalize.nfc(value)
      end

      # Part of the derivation fingerprint: with no canonical cones the
      # recipe is the only moving part, so it embeds the curation's sha256 —
      # a re-curation re-fingerprints the dataset.
      def recipe
        "sabellic-loans v1: config/sabellic_loans.yml (sha256 " \
          "#{Digest::SHA256.file(@config_path).hexdigest}) flattened to one row per curated " \
          "Latin lemma × Sabellic source language, YAML order kept; Relation verbatim from the " \
          "curation (borrowed = explicit category membership, derived = superset-only), etyma " \
          "and transliterations verbatim (leading * = reconstructed, empty = no form cited), " \
          "values NFC-normalized; ID = <source language>-<Latin lemma>."
      end

      def bib_key(key)
        BIB_KEYS.fetch(key) { raise Error, "sabellic-loans: unexpected source language #{key.inspect}" }
      end

      # One citation per source language, carrying the category-page
      # provenance the curation records (both category URLs + the retrieval
      # date) and the dual upstream grant.
      def citations(data)
        retrieved = data.fetch("retrieved")
        data.fetch("sources").map do |key, source|
          name = source.fetch("name")
          Citation.new(
            key: bib_key(key), type: "misc",
            fields: {
              "title" => "en.wiktionary — Latin terms borrowed from / derived from #{name} " \
                         "(category pages)",
              "howpublished" => source.fetch("derived_category"),
              "note" => "explicit borrowings: #{source.fetch('borrowed_category')}; member lists " \
                        "retrieved #{retrieved} via the MediaWiki API, etyma from each entry's " \
                        "own etymology template; upstream dual grant CC BY-SA 4.0 + GFDL — " \
                        "this dataset publishes under CC BY-SA 4.0"
            }
          )
        end
      end

      def resource(count)
        Resource.new(
          name: "loans", path: FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end
    end
  end
end
