# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The san/form-lemma builder (P50-W2) — the first REAL nabu-data feature:
    # the Sanskrit form→lemma table swept from the Digital Corpus of
    # Sanskrit's gold annotations.
    #
    # == Read path: the catalog (owner-ratified recipe, decided here)
    #
    # Every field the sweep needs reaches the catalog verbatim: the dcs
    # adapter's ConlluParser stores each token's FORM/LEMMA/UPOS plus the raw
    # MISC string (LemmaId=…|Unsandhied=…) inside passages.annotations_json —
    # the exact read path the fulltext Indexer already trusts for the lemma
    # index. Reading the catalog (read-only Sequel datasets, streaming) beats
    # re-walking canonical/dcs because the catalog already IS the gold-gated
    # corpus: only chapters chapter-info.xml declares gold-lexicon are ever
    # ingested (the adapter quarantines the rest, and the automatic
    # .conllu_parsed siblings are never discovered), and withdrawn rows are
    # excluded here exactly as the Indexer excludes them. The catalog is a
    # pure function of canonical/dcs, so the cone sha the Runner records
    # honestly names the derivation input — the builder's README note tells
    # the owner to sync before building so the two cannot drift.
    #
    # == The sweep
    #
    # One pass over the dcs passages' token blobs; a token mints a count iff
    # it BEARS A LEMMA. That one rule is the sandhi-surface exclusion: DCS
    # writes the sandhi surface (compound/multiword chunks, ~15% of raw token
    # lines upstream) as lemma-less lines — CoNLL-U `_`, dropped at parse, so
    # no "lemma" key — while every analyzed token carries the gold lemma plus
    # MISC Unsandhied (padapāṭha form) and LemmaId (DCS's permanent numeric
    # lemma id, the interop key back into DCS/its web interface).
    #
    # Aggregation grains — each CSV's declared primary key IS its grain,
    # test-pinned so the manifest never claims a key the data violates:
    #   form-lemma.csv  (Form, Unsandhied, Lemma, Lemma_ID, Part_Of_Speech)
    #   lemmas.csv      (Lemma_ID, Lemma)   — the per-lemma sidecar
    #
    # == Determinism
    #
    # Rows are emitted in byte-order of their grain tuple, and IDs are minted
    # from row content (readable head + a 12-hex digest of the exact tuple —
    # the digest disambiguates tuples whose readable parts fold identically
    # under mint_id, e.g. IAST forms differing only in diacritics), so a
    # rebuild over unchanged inputs is byte-identical and a new upstream row
    # never renumbers its neighbours. Memory stays flat at corpus scale
    # (5.7M gold tokens): passages stream, only the ~480K aggregate tuples
    # are held, and CSV rows are yielded lazily.
    class FormLemma
      SOURCE_SLUG = "dcs"
      # The sources.bib key every row's Source column cites.
      BIB_KEY = "dcs"
      LANGUAGE_ID = "san"

      FORM_FILENAME = "form-lemma.csv"
      FORM_COLUMNS = %w[ID Language_ID Form Unsandhied Lemma Lemma_ID Part_Of_Speech Count Source].freeze
      FORM_PRIMARY_KEY = %w[Form Unsandhied Lemma Lemma_ID Part_Of_Speech].freeze

      LEMMAS_FILENAME = "lemmas.csv"
      LEMMA_COLUMNS = %w[ID Language_ID Lemma_ID Lemma Count].freeze
      LEMMA_PRIMARY_KEY = %w[Lemma_ID Lemma].freeze

      # Part of the derivation fingerprint: changing the sweep MUST change
      # this string (builder contract).
      RECIPE = "san/form-lemma v1: sweep the stored gold token annotations of every live DCS " \
               "passage in the catalog (annotations_json; the dcs adapter's chapter-info.xml " \
               "gold gate admits only gold-lexicon chapters, so every token is " \
               "human-verified); keep exactly the tokens bearing a lemma — lemma-less " \
               "sandhi-surface lines (CoNLL-U `_`, ~15% of raw token lines upstream) mint no " \
               "row; read Unsandhied and LemmaId from MISC; count gold attestations at the " \
               "distinct (Form, Unsandhied, Lemma, Lemma_ID, UPOS) grain into form-lemma.csv " \
               "and at the (Lemma_ID, Lemma) grain into lemmas.csv."

      # Grain-tuple separator inside the aggregation hash keys. A literal tab
      # can never occur in a CoNLL-U field (the format is tab-separated).
      SEPARATOR = "\t"

      # 12 hex chars = 48 bits: collision-free in practice at the ~480K-row
      # corpus scale (expected collisions ~4e-4; CsvWriter would refuse
      # loudly rather than publish if the astronomically unlikely happened).
      DIGEST_LENGTH = 12

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "san/form-lemma reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        forms, lemmas = aggregate(catalog)
        if forms.empty?
          raise Error, "the catalog has no dcs gold tokens — sync dcs (bin/nabu sync dcs) " \
                       "before building san/form-lemma"
        end

        form_rows = write_forms(forms, out_dir)
        lemma_rows = write_lemmas(lemmas, out_dir)
        BuildResult.new(resources: [form_resource(form_rows), lemma_resource(lemma_rows)],
                        recipe: RECIPE, citations: [citation], notes: notes)
      end

      private

      # -- the sweep ----------------------------------------------------------

      # { "form\tunsandhied\tlemma\tlemma_id\tupos" => count } and
      # { "lemma_id\tlemma" => count }, streamed from the catalog.
      def aggregate(catalog)
        forms = Hash.new(0)
        lemmas = Hash.new(0)
        dcs_passages(catalog).each do |row|
          each_gold_token(row[:annotations_json]) do |form, unsandhied, lemma, lemma_id, upos|
            forms[[form, unsandhied, lemma, lemma_id, upos].join(SEPARATOR)] += 1
            lemmas[[lemma_id, lemma].join(SEPARATOR)] += 1
          end
        end
        [forms, lemmas]
      end

      # Every live dcs passage's token blob — the Indexer's two-level
      # visibility rule (neither the passage nor its document withdrawn),
      # scoped to the dcs source, annotations only. The dataset streams.
      def dcs_passages(catalog)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:sources][:slug] => SOURCE_SLUG)
          .select(Sequel[:passages][:annotations_json])
      end

      # Yield (form, unsandhied, lemma, lemma_id, upos) for each lemma-bearing
      # token. Lemma-less tokens — DCS's sandhi-surface lines and MWT ranges,
      # whose `_` columns the parser dropped — are the exclusion. The JSON is
      # our own canonical_json output (Indexer precedent): the substring probe
      # skips the parse for lemma-less blobs, and a parse failure is real
      # corruption, honestly raised.
      def each_gold_token(json)
        return if json.nil? || !json.include?('"lemma"')

        tokens = JSON.parse(json)["tokens"]
        return unless tokens.is_a?(Array)

        tokens.each do |token|
          next unless token.is_a?(Hash)

          lemma = token["lemma"]
          next if lemma.nil? || lemma.empty?

          misc = misc_fields(token["misc"])
          yield token["form"].to_s, misc.fetch("Unsandhied", ""), lemma,
                misc.fetch("LemmaId", ""), token["upos"].to_s
        end
      end

      # "LemmaId=57749|OccId=…|Unsandhied=ātmā|…" → { "LemmaId" => "57749", … }.
      def misc_fields(misc)
        return {} if misc.nil? || misc.empty?

        misc.split("|").to_h do |pair|
          key, value = pair.split("=", 2)
          [key, value.to_s]
        end
      end

      # -- emission -----------------------------------------------------------

      def write_forms(forms, out_dir)
        keys = forms.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |key|
            form, unsandhied, lemma, lemma_id, upos = key.split(SEPARATOR, -1)
            yielder << { "ID" => mint_row_id(form, lemma, key), "Language_ID" => LANGUAGE_ID,
                         "Form" => form, "Unsandhied" => unsandhied, "Lemma" => lemma,
                         "Lemma_ID" => lemma_id, "Part_Of_Speech" => upos,
                         "Count" => forms.fetch(key), "Source" => BIB_KEY }
          end
        end
        CsvWriter.write(path: File.join(out_dir, FORM_FILENAME), columns: FORM_COLUMNS, rows: rows)
      end

      def write_lemmas(lemmas, out_dir)
        keys = lemmas.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |key|
            lemma_id, lemma = key.split(SEPARATOR, -1)
            yielder << { "ID" => mint_row_id(lemma, lemma_id, key), "Language_ID" => LANGUAGE_ID,
                         "Lemma_ID" => lemma_id, "Lemma" => lemma, "Count" => lemmas.fetch(key) }
          end
        end
        CsvWriter.write(path: File.join(out_dir, LEMMAS_FILENAME), columns: LEMMA_COLUMNS, rows: rows)
      end

      # Deterministic content-derived ID: readable head + the tuple digest
      # (class note). The digest guarantees identifier-worthy material even
      # when the readable parts fold away entirely.
      def mint_row_id(*head, key)
        CsvWriter.mint_id(*head, Digest::SHA256.hexdigest(key)[0, DIGEST_LENGTH])
      end

      def form_resource(rows)
        Resource.new(name: "form-lemma", path: FORM_FILENAME, rows: rows,
                     fields: fields_for(FORM_COLUMNS), primary_key: FORM_PRIMARY_KEY)
      end

      def lemma_resource(rows)
        Resource.new(name: "lemmas", path: LEMMAS_FILENAME, rows: rows,
                     fields: fields_for(LEMMA_COLUMNS), primary_key: LEMMA_PRIMARY_KEY)
      end

      def fields_for(columns)
        columns.map { |name| { name: name, type: name == "Count" ? "integer" : "string" } }
      end

      # The citation the project already records for DCS (adapter manifest +
      # docs/02-sources.md row): Hellwig, CC BY 4.0, the sanskrit repo.
      def citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "author" => "Hellwig, Oliver",
            "title" => "The Digital Corpus of Sanskrit (DCS)",
            "year" => "2010--2024",
            "url" => "https://github.com/OliverHellwig/sanskrit",
            "note" => "Gold lemmatized CoNLL-U (dcs/data/conllu); license CC BY 4.0"
          }
        )
      end

      # Appended to the Runner's README — the scholar-facing part: columns,
      # loading, citing, and the catalog-read honesty note.
      def notes
        <<~NOTES.strip
          ## Using this dataset

          `form-lemma.csv` maps attested surface forms to dictionary lemmas, on gold
          (human-verified) evidence only. Columns: `Form` — the surface form as attested
          (IAST, sandhi applied); `Unsandhied` — the padapāṭha analysis form (DCS MISC
          `Unsandhied`); `Lemma` — the DCS dictionary headword; `Lemma_ID` — DCS's
          permanent numeric lemma id, verbatim (the interop key back into DCS);
          `Part_Of_Speech` — DCS's UPOS tag; `Count` — gold attestation count.
          `lemmas.csv` is the per-lemma sidecar at the (`Lemma_ID`, `Lemma`) grain.

          Load with pandas:

              df = pd.read_csv("form-lemma.csv", dtype=str).astype({"Count": int})

          How to cite: cite the annotations' source — Oliver Hellwig, *The Digital Corpus
          of Sanskrit (DCS)*, 2010–2024, https://github.com/OliverHellwig/sanskrit
          (CC BY 4.0; the `dcs` key in `sources.bib`) — alongside this dataset's
          `datapackage.json` provenance block.

          Derivation note: rows are read from Nabu's catalog — the ingested, gold-gated
          DCS chapters, a pure function of `canonical/dcs` — so run `nabu sync dcs`
          before building; the recorded cone sha then names exactly the ingested bytes.
        NOTES
      end
    end
  end
end
