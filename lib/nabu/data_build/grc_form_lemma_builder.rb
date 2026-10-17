# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The grc/form-lemma builder — the Ancient Greek form→lemma table swept
    # from the GLAUx treebank annotations, the hbo/form-lemma mold
    # transposed to GLAUx's token shape.
    #
    # == Read path: the catalog, the glaux source ALONE
    #
    # The glaux adapter's GlauxParser stores every <word> as a token in
    # passages.annotations_json: "form" and "lemma" (NFC at the adapter
    # boundary — GLAUx ships NFD), "postag" (the AGDT 9-place positional
    # tag VERBATIM, "n-s---nn-"), plus head/relation/animacy/sense; the
    # passage (= sentence) carries "analysis" — "auto" or "manual". The
    # parser already drops the lemma of artificial elliptic nodes and of
    # punctuation, so a lemma-bearing token is a real word.
    #
    # The sweep is scoped to the glaux source by slug: the catalog ALSO
    # holds PROIEL Greek (CC BY-NC-SA, license class nc), and no row of it
    # may contribute — the census names every other source's Greek
    # documents so the exclusion is visible. Within GLAUx, each document's
    # EFFECTIVE license class (license_override, else the source's) is
    # gated to open/attribution: the adapter's census mints nc overrides on
    # the texts whose source text is NC or whose manual annotation comes
    # from PROIEL or the Gorman trees, and those never contribute either.
    #
    # == Tier: silver, with the manual share counted
    #
    # Most of GLAUx is automatically annotated (sources.yml lemma_tier:
    # silver). Every lemma-bearing token counts in Count; the tokens of
    # hand-annotated sentences (analysis="manual" — the Perseus AGDT,
    # Pedalion and Harrington trees among the publishable texts) count in
    # Manual_Count as well, so a consumer can keep the gold share alone.
    #
    # Grains (each CSV's declared primary key IS its grain):
    #   form-lemma.csv (Form, Lemma, Postag) — Postag is load-bearing
    #                  (accusative vs nominative σῶμα share Form and Lemma)
    #   lemmas.csv     (Lemma) — the per-lemma sidecar
    #
    # == Bytes: verbatim
    #
    # grc is NFC-normal (no exemption): the adapter normalized at its
    # boundary and nothing here re-normalizes.
    #
    # == Determinism
    #
    # Rows emit in byte-order of their grain tuple; IDs are a readable head
    # plus a 12-hex digest of the exact tuple (the hbo minting — Greek
    # forms fold away under mint_id, so the digest carries the identity).
    class GrcFormLemmaBuilder
      SOURCE_SLUG = "glaux"
      BIB_KEY = "glaux"
      LANGUAGE_ID = "grc"
      MANUAL = "manual"
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      FORM_FILENAME = "form-lemma.csv"
      FORM_COLUMNS = %w[ID Language_ID Form Lemma Postag Count Manual_Count Source].freeze
      FORM_PRIMARY_KEY = %w[Form Lemma Postag].freeze

      LEMMAS_FILENAME = "lemmas.csv"
      LEMMA_COLUMNS = %w[ID Language_ID Lemma Count Manual_Count].freeze
      LEMMA_PRIMARY_KEY = %w[Lemma].freeze

      RECIPE = "grc/form-lemma v1: sweep the stored token annotations of every live passage of " \
               "the glaux source ALONE (no other source's Greek — PROIEL is CC BY-NC-SA and " \
               "contributes nothing) whose document's effective license class is open/attribution " \
               "(the nc-overridden GLAUx texts — NC source texts, PROIEL- and Gorman-annotated " \
               "trees — are excluded, censused); keep the tokens bearing a lemma (artificial " \
               "elliptic nodes and punctuation carry none, censused); carry Form/Lemma/Postag " \
               "byte-verbatim; count attestations at the distinct (Form, Lemma, Postag) grain into " \
               "form-lemma.csv and at the Lemma grain into lemmas.csv, each with a Manual_Count of " \
               "the attestations in sentences GLAUx marks analysis=\"manual\"."

      SEPARATOR = "\t"
      DIGEST_LENGTH = 12

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "grc/form-lemma reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        source = glaux_source!(catalog)
        forms, lemmas, census = aggregate(catalog, source)
        census["excluded_greek_documents"] = excluded_greek_documents(catalog, source[:id])

        form_rows = write_forms(forms, out_dir)
        lemma_rows = write_lemmas(lemmas, out_dir)
        BuildResult.new(resources: [form_resource(form_rows), lemma_resource(lemma_rows)],
                        recipe: RECIPE, citations: [citation], notes: notes, evaluation: census)
      end

      private

      def glaux_source!(catalog)
        source = catalog[:sources].where(slug: SOURCE_SLUG).select(:id, :license_class).first
        if source.nil?
          raise Error, "the catalog has no glaux rows — sync glaux (bin/nabu sync glaux) " \
                       "before building grc/form-lemma"
        end
        unless PUBLISHABLE_LICENSE_CLASSES.include?(source[:license_class])
          raise Error, "grc/form-lemma: #{SOURCE_SLUG} license class #{source[:license_class].inspect} " \
                       "is not publishable (#{PUBLISHABLE_LICENSE_CLASSES.join('/')})"
        end

        source
      end

      # The live glaux documents whose effective license class publishes;
      # the census records every one left out, per class.
      def publishable_documents(catalog, source, census)
        catalog[:documents].where(source_id: source[:id], withdrawn: false)
                           .order(:id).select(:id, :license_override).filter_map do |doc|
          klass = doc[:license_override] || source[:license_class]
          next doc[:id] if PUBLISHABLE_LICENSE_CLASSES.include?(klass)

          census["license_excluded_documents"][klass] += 1
          nil
        end
      end

      # -- the sweep ----------------------------------------------------------

      def aggregate(catalog, source)
        forms = Hash.new { |hash, key| hash[key] = [0, 0] }
        lemmas = Hash.new { |hash, key| hash[key] = [0, 0] }
        census = empty_census
        live_passages(catalog, publishable_documents(catalog, source, census)).each do |row|
          census["passages_scanned"] += 1
          annotations = parse(row[:annotations_json]) or next
          analysis = annotations["analysis"].to_s
          census["sentences_by_analysis"][analysis] += 1
          manual = analysis == MANUAL ? 1 : 0
          each_token(annotations) do |token|
            next unless countable?(token, census)

            tally(forms[[token["form"].to_s, token["lemma"], token["postag"].to_s].join(SEPARATOR)], manual)
            tally(lemmas[token["lemma"]], manual)
            census["lemma_tokens_counted"] += 1
            census["manual_tokens_counted"] += manual
          end
        end
        if forms.empty?
          raise Error, "the catalog has no publishable glaux lemma tokens — sync glaux " \
                       "(bin/nabu sync glaux) before building grc/form-lemma"
        end

        [forms, lemmas, finalize(census)]
      end

      def tally(counts, manual)
        counts[0] += 1
        counts[1] += manual
      end

      def empty_census
        { "input_source" => SOURCE_SLUG, "passages_scanned" => 0, "lemma_tokens_counted" => 0,
          "manual_tokens_counted" => 0, "sentences_by_analysis" => Hash.new(0),
          "artificial_tokens_excluded" => 0, "punctuation_tokens_excluded" => 0,
          "lemma_less_words_excluded" => 0, "license_excluded_documents" => Hash.new(0) }
      end

      # Plain sorted hashes for the manifest (no default procs, stable order).
      def finalize(census)
        census.transform_values { |value| value.is_a?(Hash) ? value.sort.to_h : value }
      end

      # A lemma-bearing token counts; the lemma-less are censused by kind
      # (the parser drops the lemma of elliptic nodes and punctuation).
      def countable?(token, census)
        return true unless token["lemma"].to_s.empty?

        if token.key?("artificial")
          census["artificial_tokens_excluded"] += 1
        elsif token["postag"].to_s.start_with?("u")
          census["punctuation_tokens_excluded"] += 1
        else
          census["lemma_less_words_excluded"] += 1
        end
        false
      end

      # The Indexer's two-level visibility rule, scoped to the documents
      # already admitted (live, glaux, publishable).
      def live_passages(catalog, document_ids)
        catalog[:passages]
          .where(withdrawn: false, document_id: document_ids)
          .order(:id)
          .select(:annotations_json)
      end

      def parse(json)
        return nil if json.nil? || !json.include?('"tokens"')

        annotations = JSON.parse(json)
        annotations.is_a?(Hash) ? annotations : nil
      end

      def each_token(annotations, &)
        tokens = annotations["tokens"]
        return unless tokens.is_a?(Array)

        tokens.each { |token| yield token if token.is_a?(Hash) }
      end

      # Every OTHER source's live Greek documents, per slug — the exclusion
      # census (PROIEL's nc Greek among them).
      def excluded_greek_documents(catalog, source_id)
        catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:language] => LANGUAGE_ID, Sequel[:documents][:withdrawn] => false)
          .exclude(Sequel[:documents][:source_id] => source_id)
          .group_and_count(Sequel[:sources][:slug])
          .order(Sequel[:sources][:slug])
          .to_h { |row| [row[:slug], row[:count]] }
      end

      # -- emission -----------------------------------------------------------

      def write_forms(forms, out_dir)
        keys = forms.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |key|
            form, lemma, postag = key.split(SEPARATOR, -1)
            count, manual = forms.fetch(key)
            yielder << { "ID" => mint_row_id(lemma, postag, key), "Language_ID" => LANGUAGE_ID,
                         "Form" => form, "Lemma" => lemma, "Postag" => postag,
                         "Count" => count, "Manual_Count" => manual, "Source" => BIB_KEY }
          end
        end
        CsvWriter.write(path: File.join(out_dir, FORM_FILENAME), columns: FORM_COLUMNS, rows: rows)
      end

      def write_lemmas(lemmas, out_dir)
        keys = lemmas.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |lemma|
            count, manual = lemmas.fetch(lemma)
            yielder << { "ID" => mint_row_id(lemma, lemma), "Language_ID" => LANGUAGE_ID,
                         "Lemma" => lemma, "Count" => count, "Manual_Count" => manual }
          end
        end
        CsvWriter.write(path: File.join(out_dir, LEMMAS_FILENAME), columns: LEMMA_COLUMNS, rows: rows)
      end

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
        columns.map { |name| { name: name, type: name.end_with?("Count") ? "integer" : "string" } }
      end

      # The citation GLAUx's README asks for.
      def citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "author" => "Keersmaekers, Alek",
            "title" => "The GLAUx corpus: methodological issues in designing a long-term, diverse, " \
                       "multi-layered corpus of Ancient Greek",
            "year" => "2021",
            "howpublished" => "Proceedings of the 2nd International Workshop on Computational " \
                              "Approaches to Historical Language Change 2021, 39--50",
            "doi" => "10.18653/v1/2021.lchange-1.6",
            "url" => "https://github.com/alekkeersmaekers/glaux",
            "note" => "GLAUx data CC BY-SA (per-text licenses in metadata.txt; NC texts excluded here)"
          }
        )
      end

      def notes
        <<~NOTES.strip
          ## Using this dataset

          `form-lemma.csv` maps attested Ancient Greek word forms to their GLAUx lemmas.
          Columns: `Form` — the word as the edition writes it (NFC); `Lemma` — the GLAUx
          lemma; `Postag` — the AGDT 9-place positional tag verbatim (`n-s---nn-` = noun,
          singular, neuter, nominative); `Count` — attestations; `Manual_Count` — the
          attestations from hand-annotated sentences. **Most of GLAUx is annotated
          automatically** (lemma accuracy ~98.8% per the GLAUx README), so `Count` is a
          silver figure; keep `Manual_Count > 0` for the hand-verified share. `lemmas.csv`
          re-buckets the same tokens per `Lemma`. Texts whose source or manual annotation is
          non-commercial (PROIEL, Gorman trees) are excluded (counts in `datapackage.json` →
          `nabu.eval`).

          Load with pandas:

              df = pd.read_csv("form-lemma.csv", dtype=str).astype({"Count": int, "Manual_Count": int})
              gold = df[df.Manual_Count > 0]

          How to cite: Keersmaekers (2021), doi:10.18653/v1/2021.lchange-1.6 (the `glaux` key
          in `sources.bib`; GLAUx data CC BY-SA) — alongside this dataset's `datapackage.json`
          provenance block.
        NOTES
      end
    end
  end
end
