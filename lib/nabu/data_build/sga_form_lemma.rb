# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The sga/form-lemma builder — the Old Irish form→lemma table derived from
    # TWO independent gold-annotated editions of the SAME St Gall Priscian
    # glosses (St Gallen, Stiftsbibliothek 904): the St Gall Priscian Glosses
    # edition (Hofman, Moran, Bauer; the stgall-priscian source) and CorPH's
    # St Gall text (ChronHib, Bauer; corph document 0007). The san/form-lemma
    # mold, with one addition: a two-edition AGREEMENT CENSUS.
    #
    # == Read path: the catalog
    #
    # Both adapters store each analysed word as a P7-5 token in
    # passages.annotations_json ("form", "lemma" with the homonym index split
    # into "homonym", "analysis"; St Gall adds "wordclass", CorPH a "lang"
    # from its LEMMATA join). The Runner's stale-ingest guard covers both
    # declared inputs, so the cone shas the manifest records name exactly the
    # ingested bytes.
    #
    # == The form-lemma table
    #
    # A token mints a count iff it bears a lemma AND is Old Irish: every
    # St Gall word_instances row is an Old Irish analysis (the adapter tags
    # them sga); CorPH's text 0007 also analyses the glosses' Latin words and
    # the ".i." abbreviation, so only tokens whose LEMMATA language is Early
    # Irish (lang "sga") count. CorPH's other 77 texts are out of scope: this
    # dataset is the St Gall gloss corpus seen through both editions.
    # Grain: (Edition, Form, Lemma, Homonym, Part_Of_Speech, Analysis) — the
    # declared primary key. Forms are VERBATIM as each edition stores them
    # (St Gall keeps its editorial marks, e.g. "ṡe(i)rc").
    #
    # == The agreement census (nabu.eval + divergences.csv)
    #
    # Join key: the Thesaurus Palaeohibernicus (vol. ii) reference. St Gall
    # stores it per gloss as annotations "thesaurus" in its own display form
    # ("001a01" → "1a1"); CorPH stores it as the unit's first locus
    # ("Sg 001a01"). Both are normalized by the same rule (drop the "Sg "
    # siglum, drop zero padding exactly as the St Gall display does), so the
    # key is the edition's own display form. Measured on the full corpora
    # (2026-10-16): 3,529 St Gall refs, 3,527 CorPH refs, 3,420 matched; a
    # few dozen refs carry two or more glosses on one side, whose tokens are
    # POOLED per ref (censused as matched_pooled).
    #
    # Within a matched ref, the two editions' sga tokens are aligned
    # greedily in edition order by FOLDED form (NFD, combining marks
    # stripped, lower-cased, letters only — so "at·tá"/"at·tá" and
    # "ṡe(i)rc"/"ṡeirc" pair, an empty fold never pairs). Each aligned pair
    # compares lemmas: identical strings, equal once folded (length marks,
    # diaereses, hyphens, middots, case), or divergent. Divergent pairs —
    # chiefly the editions' different headword conventions — are published
    # one row per pair in divergences.csv, the proofreading/concordance
    # surface. Unaligned tokens (different word division, a form only one
    # edition analysed) are counted, never guessed at.
    class SgaFormLemma
      STGALL_SLUG = "stgall-priscian"
      CORPH_SLUG = "corph"
      CORPH_DOCUMENT = "urn:nabu:corph:0007"
      LANGUAGE_ID = "sga"
      EDITIONS = [STGALL_SLUG, CORPH_SLUG].freeze

      FORM_FILENAME = "form-lemma.csv"
      FORM_COLUMNS = %w[ID Language_ID Edition Form Lemma Homonym Part_Of_Speech Analysis Count Source].freeze
      FORM_PRIMARY_KEY = %w[Edition Form Lemma Homonym Part_Of_Speech Analysis].freeze

      DIVERGENCES_FILENAME = "divergences.csv"
      DIVERGENCE_COLUMNS = %w[ID Thesaurus_Ref Stgall_Form Stgall_Lemma Stgall_Homonym Stgall_Analysis
                              Corph_Form Corph_Lemma Corph_Homonym Corph_Analysis Stgall_URN Corph_URN].freeze

      RECIPE = "sga/form-lemma v1: sweep the stored gold token annotations of every live " \
               "stgall-priscian passage and of CorPH's St Gall text (document 0007) in the catalog; " \
               "keep the lemma-bearing Old Irish tokens (every St Gall analysis; CorPH tokens whose " \
               "LEMMATA language is Early Irish); count attestations at the distinct " \
               "(Edition, Form, Lemma, Homonym, Part_Of_Speech, Analysis) grain into form-lemma.csv. " \
               "Agreement census: join the editions on the Thesaurus Palaeohibernicus reference " \
               "(St Gall annotations thesaurus; CorPH locus 1 minus the Sg siglum; zero padding " \
               "dropped on both sides), pool tokens per ref, align greedily in edition order by " \
               "folded form (NFD, marks stripped, lower-cased, letters only), compare lemmas as " \
               "identical / equal folded / divergent; census into nabu.eval, divergent pairs into " \
               "divergences.csv."

      JOIN = "Thesaurus Palaeohibernicus ii reference (St Gall annotations.thesaurus; CorPH " \
             "annotations.locus[0] minus \"Sg \"; zero padding dropped on both sides)"

      SEPARATOR = "\t"
      DIGEST_LENGTH = 12

      # One token as the census handles it.
      Token = Data.define(:form, :lemma, :homonym, :analysis, :urn)
      private_constant :Token

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "sga/form-lemma reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        forms = Hash.new(0)
        stgall = sweep_stgall(catalog, forms)
        corph = sweep_corph(catalog, forms)
        { STGALL_SLUG => stgall, CORPH_SLUG => corph }.each do |slug, sweep|
          next unless sweep[:tokens].zero?

          raise Error, "the catalog has no #{slug} gold tokens — sync #{slug} (bin/nabu sync #{slug}) " \
                       "before building sga/form-lemma"
        end

        census, divergences = agreement(stgall, corph)
        form_rows = write_forms(forms, out_dir)
        divergence_rows = write_divergences(divergences, out_dir)
        BuildResult.new(resources: [form_resource(form_rows), divergence_resource(divergence_rows)],
                        recipe: RECIPE, citations: citations, notes: notes(census),
                        evaluation: census)
      end

      private

      # -- the sweeps ---------------------------------------------------------

      # { tokens:, by_ref: { key => [Token, ...] } }; aggregates into +forms+.
      def sweep_stgall(catalog, forms)
        sweep = { tokens: 0, by_ref: {}, passages_by_ref: Hash.new(0) }
        passages(catalog, STGALL_SLUG).each do |row|
          annotations = parse(row[:annotations_json])
          tokens = gold_tokens(annotations, row[:urn]) { true }
          tokens.each { |token, raw| count(forms, STGALL_SLUG, token, raw["wordclass"].to_s) }
          sweep[:tokens] += tokens.size
          collect(sweep, annotations["thesaurus"], tokens.map(&:first))
        end
        sweep
      end

      def sweep_corph(catalog, forms)
        sweep = { tokens: 0, by_ref: {}, passages_by_ref: Hash.new(0) }
        passages(catalog, CORPH_SLUG).where(Sequel[:documents][:urn] => CORPH_DOCUMENT).each do |row|
          annotations = parse(row[:annotations_json])
          tokens = gold_tokens(annotations, row[:urn]) { |raw| raw["lang"] == LANGUAGE_ID }
          tokens.map(&:first).each { |token| count(forms, CORPH_SLUG, token, "") }
          sweep[:tokens] += tokens.size
          collect(sweep, Array(annotations["locus"]).first, tokens.map(&:first))
        end
        sweep
      end

      # Live passages of +slug+ (the Indexer's two-level visibility rule), in
      # document/sequence order so the census's pooling and alignment order is
      # each edition's own order.
      def passages(catalog, slug)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:sources][:slug] => slug)
          .order(Sequel[:documents][:urn], Sequel[:passages][:sequence])
          .select(Sequel[:passages][:urn], Sequel[:passages][:annotations_json])
      end

      def parse(json)
        return {} if json.nil? || json.empty?

        parsed = JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      end

      # [[Token, raw_hash], ...] for the lemma-bearing tokens the block admits.
      def gold_tokens(annotations, urn)
        tokens = annotations["tokens"]
        return [] unless tokens.is_a?(Array)

        tokens.filter_map do |raw|
          next unless raw.is_a?(Hash)

          lemma = raw["lemma"].to_s
          next if lemma.empty? || !yield(raw)

          [Token.new(form: raw["form"].to_s, lemma: lemma, homonym: raw["homonym"].to_s,
                     analysis: raw["analysis"].to_s, urn: urn), raw]
        end
      end

      def count(forms, edition, token, part_of_speech)
        key = [edition, token.form, token.lemma, token.homonym, part_of_speech, token.analysis].join(SEPARATOR)
        forms[key] += 1
      end

      def collect(sweep, ref, tokens)
        key = thesaurus_key(ref)
        return if key.nil?

        sweep[:passages_by_ref][key] += 1
        (sweep[:by_ref][key] ||= []).concat(tokens)
      end

      # The shared join-key normalization (class note): the St Gall adapter's
      # own display rule applied to both sides — idempotent on St Gall's
      # already-displayed refs, and turns CorPH's "Sg 001a01" into "1a1".
      def thesaurus_key(ref)
        key = ref.to_s.strip.delete_prefix("Sg ").strip
        return nil if key.empty?

        key.gsub(/(^|a|b|\s)0{0,2}/, '\1')
      end

      # -- the agreement census ----------------------------------------------

      def agreement(stgall, corph)
        matched = (stgall[:by_ref].keys & corph[:by_ref].keys).sort
        tally = Hash.new(0)
        divergences = []
        matched.each { |key| align(key, stgall[:by_ref][key], corph[:by_ref][key], tally, divergences) }
        [census(stgall, corph, matched, tally), divergences]
      end

      def align(key, stgall_tokens, corph_tokens, tally, divergences)
        tally[:matched_with_tokens] += 1 unless stgall_tokens.empty? || corph_tokens.empty?
        tally[:stgall_in_matched] += stgall_tokens.size
        tally[:corph_in_matched] += corph_tokens.size
        pool = stgall_tokens.dup
        corph_tokens.each do |corph_token|
          folded = fold(corph_token.form)
          index = folded.empty? ? nil : pool.index { |token| fold(token.form) == folded }
          next tally[:unaligned_corph] += 1 if index.nil?

          stgall_token = pool.delete_at(index)
          tally[:aligned] += 1
          compare(key, stgall_token, corph_token, tally, divergences)
        end
        tally[:unaligned_stgall] += pool.size
      end

      def compare(key, stgall_token, corph_token, tally, divergences)
        if stgall_token.lemma == corph_token.lemma
          tally[:identical] += 1
        elsif fold(stgall_token.lemma) == fold(corph_token.lemma)
          tally[:equal_folded] += 1
        else
          divergences << [key, stgall_token, corph_token]
        end
      end

      def fold(text)
        text.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.gsub(/[^\p{L}]/, "")
      end

      def census(stgall, corph, matched, tally)
        diverge = tally[:aligned] - tally[:identical] - tally[:equal_folded]
        agree = tally[:identical] + tally[:equal_folded]
        {
          "join" => JOIN,
          "refs" => {
            "stgall_priscian" => stgall[:by_ref].size, "corph" => corph[:by_ref].size,
            "matched" => matched.size,
            "stgall_only" => stgall[:by_ref].size - matched.size,
            "corph_only" => corph[:by_ref].size - matched.size,
            "matched_pooled" => matched.count do |key|
              stgall[:passages_by_ref][key] > 1 || corph[:passages_by_ref][key] > 1
            end,
            "matched_with_tokens" => tally[:matched_with_tokens]
          },
          "tokens" => {
            "stgall_priscian" => stgall[:tokens], "corph" => corph[:tokens],
            "stgall_priscian_in_matched_refs" => tally[:stgall_in_matched],
            "corph_in_matched_refs" => tally[:corph_in_matched],
            "aligned" => tally[:aligned],
            "unaligned_stgall_priscian" => tally[:unaligned_stgall],
            "unaligned_corph" => tally[:unaligned_corph]
          },
          "lemmas" => {
            "identical" => tally[:identical], "equal_folded" => tally[:equal_folded],
            "agree" => agree, "diverge" => diverge,
            "agreement_rate" => tally[:aligned].zero? ? 0.0 : (agree.to_f / tally[:aligned]).round(4)
          }
        }
      end

      # -- emission -----------------------------------------------------------

      def write_forms(forms, out_dir)
        keys = forms.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |key|
            edition, form, lemma, homonym, part_of_speech, analysis = key.split(SEPARATOR, -1)
            yielder << { "ID" => mint_row_id(edition, form, lemma, key), "Language_ID" => LANGUAGE_ID,
                         "Edition" => edition, "Form" => form, "Lemma" => lemma,
                         "Homonym" => presence(homonym), "Part_Of_Speech" => presence(part_of_speech),
                         "Analysis" => presence(analysis), "Count" => forms.fetch(key), "Source" => edition }
          end
        end
        CsvWriter.write(path: File.join(out_dir, FORM_FILENAME), columns: FORM_COLUMNS, rows: rows)
      end

      def write_divergences(divergences, out_dir)
        minter = IdMinter.new
        rows = divergences.map do |key, stgall_token, corph_token|
          { "ID" => minter.mint("d", key, stgall_token.form), "Thesaurus_Ref" => key,
            "Stgall_Form" => stgall_token.form, "Stgall_Lemma" => stgall_token.lemma,
            "Stgall_Homonym" => presence(stgall_token.homonym),
            "Stgall_Analysis" => presence(stgall_token.analysis),
            "Corph_Form" => corph_token.form, "Corph_Lemma" => corph_token.lemma,
            "Corph_Homonym" => presence(corph_token.homonym),
            "Corph_Analysis" => presence(corph_token.analysis),
            "Stgall_URN" => stgall_token.urn, "Corph_URN" => corph_token.urn }
        end
        CsvWriter.write(path: File.join(out_dir, DIVERGENCES_FILENAME), columns: DIVERGENCE_COLUMNS, rows: rows)
      end

      def presence(value) = value.empty? ? nil : value

      def mint_row_id(*head, key)
        CsvWriter.mint_id(*head, Digest::SHA256.hexdigest(key)[0, DIGEST_LENGTH])
      end

      def form_resource(rows)
        Resource.new(name: "form-lemma", path: FORM_FILENAME, rows: rows,
                     fields: FORM_COLUMNS.map { |name| { name: name, type: name == "Count" ? "integer" : "string" } },
                     primary_key: FORM_PRIMARY_KEY)
      end

      def divergence_resource(rows)
        Resource.new(name: "divergences", path: DIVERGENCES_FILENAME, rows: rows,
                     fields: DIVERGENCE_COLUMNS.map { |name| { name: name, type: "string" } },
                     primary_key: ["ID"])
      end

      # The citations the adapters' manifests and fixture READMEs record.
      def citations
        [
          Citation.new(
            key: STGALL_SLUG, type: "misc",
            fields: {
              "author" => "Hofman, Rijcklof and Moran, Pádraic and Bauer, Bernhard",
              "title" => "St Gall Priscian Glosses, version 2.1",
              "year" => "2023",
              "url" => "https://www.stgallpriscian.ie",
              "note" => "Database dump db_priscian_v2.sql, github.com/padraicmoran/stgallpriscian; " \
                        "MIT License, Copyright (c) 2023 Pádraic Moran"
            }
          ),
          Citation.new(
            key: CORPH_SLUG, type: "misc",
            fields: {
              "author" => "{Chronologicon Hibernicum}",
              "title" => "CorPH: Corpus PalaeoHibernicum (text 0007, St Gall Priscian, ed. Bernhard Bauer)",
              "year" => "2020",
              "url" => "https://github.com/chronhib-MU/Chronhib-Website",
              "note" => "Database dump chronhibdev_2020.sql; MIT License, Copyright (c) 2020 " \
                        "Chronologicon Hibernicum"
            }
          )
        ]
      end

      def notes(census)
        lemmas = census.fetch("lemmas")
        tokens = census.fetch("tokens")
        <<~NOTES.strip
          ## Using this dataset

          `form-lemma.csv` maps attested Old Irish surface forms to dictionary lemmas, on gold
          (human-annotated) evidence only, from two independent editions of the St Gall Priscian
          glosses (St Gallen, Stiftsbibliothek 904). Columns: `Edition` — `stgall-priscian` (the St
          Gall Priscian Glosses v2.1, Hofman/Moran/Bauer) or `corph` (CorPH's St Gall text, ChronHib);
          `Form` — the analysed form verbatim as the edition stores it (St Gall keeps its editorial
          marks); `Lemma` — the edition's headword, its homonym index split into `Homonym` (each
          edition numbers homonyms its own way); `Part_Of_Speech` — St Gall's word class (CorPH
          carries none per token); `Analysis` — the edition's morphological analysis; `Count` — gold
          attestations of the tuple. Only Old Irish tokens count (CorPH's Latin and `.i.` analyses
          are excluded).

          Load with pandas:

              df = pd.read_csv("form-lemma.csv", dtype=str).astype({"Count": int})

          ## The two-edition agreement census

          The editions are joined on the Thesaurus Palaeohibernicus reference (`nabu.eval.join` in
          `datapackage.json`). Within each matched reference the editions' tokens are aligned by
          folded form; of #{tokens.fetch('aligned')} aligned token pairs, #{lemmas.fetch('identical')} carry
          identical lemmas, #{lemmas.fetch('equal_folded')} more agree once length marks, hyphens and
          case are folded, and #{lemmas.fetch('diverge')} diverge (agreement rate
          #{lemmas.fetch('agreement_rate')}). `divergences.csv` lists every divergent pair side by
          side with both passage URNs — mostly the editions' different headword conventions, a
          concordance between the two lemmatizations as much as a proofreading list. Unaligned
          tokens (different word division, a word only one edition analysed) are counted in
          `nabu.eval.tokens`, never guessed at.

          How to cite: cite both editions — Rijcklof Hofman, Pádraic Moran, Bernhard Bauer, *St
          Gall Priscian Glosses*, version 2.1 (2023), https://www.stgallpriscian.ie (MIT; the
          `stgall-priscian` key in `sources.bib`) and *CorPH — Corpus PalaeoHibernicum*
          (Chronologicon Hibernicum, Maynooth; MIT; the `corph` key) — alongside this dataset's
          `datapackage.json` provenance block.
        NOTES
      end
    end
  end
end
