# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The non/form-lemma builder — the Old Norse form→lemma table swept from
    # Menota's gold word annotations, the hbo/form-lemma mold transposed to
    # Menota-TEI's multi-level transcription.
    #
    # == Read path: the catalog, the menota source ALONE
    #
    # The menota adapter's MenotaTeiParser stores every token in
    # passages.annotations_json: "kind" (w / pc / me:punct), "lemma" (the
    # encoder's @lemma, a normalized Old Norse headword), "msa" (the
    # me:msa morphosyntactic analysis VERBATIM — "xNC gM nS cN sI"), and
    # one key per transcription level the word attests: "facs"
    # (facsimile — glyph-level, MUFI private-use characters and unexpanded
    # abbreviation marks), "dipl" (diplomatic — abbreviations expanded,
    # scribal spelling kept), "norm" (normalized Old Norse orthography).
    # The sweep is scoped to the menota source by slug, and each document's
    # EFFECTIVE license class (its license_override, else the source's) is
    # gated to open/attribution: Menota's per-text licence gate can mint nc
    # or restricted overrides, and none may contribute.
    #
    # == Language scope: Old West Norse (isl, nor, non)
    #
    # Menota's documents name their own language verbatim: isl (Old
    # Icelandic), nor (Old Norwegian), non (Old Norse), swe (Old Swedish),
    # dan (Old Danish). The dataset is Old Norse as Glottolog's oldn1244
    # bounds it: Old Icelandic and Old Norwegian are its Old West Norse
    # branch, while Glottolog files Old Swedish (olds1252) and Old Danish
    # (oldd1239) under modern Swedish and Danish, not under oldn1244. So
    # swe/dan documents are out of scope, censused per language.
    #
    # == The level decision
    #
    # The three levels share ONE lemma + msa analysis per word, but they are
    # not a fixed pair: dipl-only documents carry lemmatized words with no
    # normalized reading. Each lemmatized word contributes one count PER
    # LEVEL it attests, and the Level column names which (facs / dipl /
    # norm) — no empty key, no level privileged, nothing dropped. The
    # per-level counts each sum to the tokens attesting that level; the
    # lemmas sidecar counts each token once.
    #
    # Grains (each CSV's declared primary key IS its grain):
    #   form-lemma.csv (Level, Form, Lemma, Msa) — Msa is load-bearing
    #                  (genitive vs dative kastala share Form and Lemma)
    #   lemmas.csv     (Lemma) — the per-lemma token sidecar
    #
    # == Bytes: verbatim
    #
    # non is NFC-normal (no exemption): the adapter normalized at its
    # boundary and nothing here re-normalizes — forms, lemmas and msa are
    # carried exactly as the catalog holds them, MUFI private-use glyphs
    # included.
    #
    # == Determinism
    #
    # Rows emit in byte-order of their grain tuple; IDs are a readable head
    # plus a 12-hex digest of the exact tuple (the hbo minting).
    class NonFormLemmaBuilder
      SOURCE_SLUG = "menota"
      BIB_KEY = "menota"
      LANGUAGE_ID = "non"
      OLD_NORSE_LANGUAGES = %w[isl nor non].freeze
      LEVELS = %w[facs dipl norm].freeze
      WORD_KIND = "w"
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      FORM_FILENAME = "form-lemma.csv"
      FORM_COLUMNS = %w[ID Language_ID Level Form Lemma Msa Count Source].freeze
      FORM_PRIMARY_KEY = %w[Level Form Lemma Msa].freeze

      LEMMAS_FILENAME = "lemmas.csv"
      LEMMA_COLUMNS = %w[ID Language_ID Lemma Count].freeze
      LEMMA_PRIMARY_KEY = %w[Lemma].freeze

      RECIPE = "non/form-lemma v1: sweep the stored token annotations of every live passage of " \
               "the menota source ALONE whose document language is Old West Norse (isl, nor, non — " \
               "swe/dan documents are out of scope, censused) and whose effective license class is " \
               "open/attribution; keep the <w> tokens bearing a lemma (lemma-less words and " \
               "punctuation mint nothing, censused); for each level the word attests (facs, dipl, " \
               "norm) count one attestation at the distinct (Level, Form, Lemma, Msa) grain into " \
               "form-lemma.csv, carrying every value byte-verbatim (never re-normalized); count each " \
               "token once at the Lemma grain into lemmas.csv."

      SEPARATOR = "\t"
      DIGEST_LENGTH = 12

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "non/form-lemma reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        source = menota_source!(catalog)
        forms, lemmas, census = aggregate(catalog, source)
        census["excluded_old_norse_documents"] = excluded_old_norse_documents(catalog, source[:id])

        form_rows = write_forms(forms, out_dir)
        lemma_rows = write_lemmas(lemmas, out_dir)
        BuildResult.new(resources: [form_resource(form_rows), lemma_resource(lemma_rows)],
                        recipe: RECIPE, citations: [citation], notes: notes, evaluation: census)
      end

      private

      def menota_source!(catalog)
        source = catalog[:sources].where(slug: SOURCE_SLUG).select(:id, :license_class).first
        if source.nil?
          raise Error, "the catalog has no menota rows — sync menota (bin/nabu sync menota) " \
                       "before building non/form-lemma"
        end
        unless PUBLISHABLE_LICENSE_CLASSES.include?(source[:license_class])
          raise Error, "non/form-lemma: #{SOURCE_SLUG} license class #{source[:license_class].inspect} " \
                       "is not publishable (#{PUBLISHABLE_LICENSE_CLASSES.join('/')})"
        end

        source
      end

      # -- document scope -----------------------------------------------------

      # document id => language, for the in-scope documents; the census
      # records every live menota document left out, and why.
      def scoped_documents(catalog, source, census)
        scoped = {}
        catalog[:documents].where(source_id: source[:id], withdrawn: false)
                           .order(:id).select(:id, :language, :license_override).each do |doc|
          klass = doc[:license_override] || source[:license_class]
          if !OLD_NORSE_LANGUAGES.include?(doc[:language])
            census["out_of_scope_documents_by_language"][doc[:language].to_s] += 1
          elsif !PUBLISHABLE_LICENSE_CLASSES.include?(klass)
            census["license_excluded_documents"][klass] += 1
          else
            scoped[doc[:id]] = doc[:language]
          end
        end
        scoped
      end

      # -- the sweep ----------------------------------------------------------

      def aggregate(catalog, source)
        forms = Hash.new(0)
        lemmas = Hash.new(0)
        census = empty_census
        documents = scoped_documents(catalog, source, census)
        live_passages(catalog, documents.keys).each do |row|
          census["passages_scanned"] += 1
          language = documents.fetch(row[:document_id])
          each_token(row[:annotations_json]) do |token|
            next unless countable?(token, census)

            count_token(token, forms, census)
            lemmas[token["lemma"]] += 1
            census["lemmatized_tokens_counted"] += 1
            census["tokens_by_document_language"][language] += 1
          end
        end
        if forms.empty?
          raise Error, "the catalog has no lemmatized Old Norse menota tokens — sync menota " \
                       "(bin/nabu sync menota) before building non/form-lemma"
        end

        [forms, lemmas, finalize(census)]
      end

      def empty_census
        { "input_source" => SOURCE_SLUG, "passages_scanned" => 0, "lemmatized_tokens_counted" => 0,
          "level_tokens" => LEVELS.to_h { |level| [level, 0] },
          "tokens_by_document_language" => Hash.new(0),
          "lemma_less_words_excluded" => 0, "punctuation_tokens_skipped" => 0,
          "out_of_scope_documents_by_language" => Hash.new(0),
          "license_excluded_documents" => Hash.new(0) }
      end

      # Plain sorted hashes for the manifest (no default procs, stable order).
      def finalize(census)
        census.transform_values { |value| value.is_a?(Hash) ? value.sort.to_h : value }
      end

      def countable?(token, census)
        if token["kind"] != WORD_KIND
          census["punctuation_tokens_skipped"] += 1
          false
        elsif token["lemma"].to_s.empty?
          census["lemma_less_words_excluded"] += 1
          false
        else
          true
        end
      end

      def count_token(token, forms, census)
        LEVELS.each do |level|
          form = token[level]
          next if form.to_s.empty?

          forms[[level, form, token["lemma"], token["msa"].to_s].join(SEPARATOR)] += 1
          census["level_tokens"][level] += 1
        end
      end

      # The Indexer's two-level visibility rule, scoped to the documents
      # already admitted (live, in scope, publishable).
      def live_passages(catalog, document_ids)
        catalog[:passages]
          .where(withdrawn: false, document_id: document_ids)
          .order(:id)
          .select(:document_id, :annotations_json)
      end

      def each_token(json, &)
        return if json.nil? || !json.include?('"tokens"')

        tokens = JSON.parse(json)["tokens"]
        return unless tokens.is_a?(Array)

        tokens.each { |token| yield token if token.is_a?(Hash) }
      end

      # Every OTHER source's live Old Norse (non) documents, per slug — the
      # exclusion census, so a second Norse lane is visible, never silent.
      def excluded_old_norse_documents(catalog, source_id)
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
            level, form, lemma, msa = key.split(SEPARATOR, -1)
            yielder << { "ID" => mint_row_id(lemma, level, key), "Language_ID" => LANGUAGE_ID,
                         "Level" => level, "Form" => form, "Lemma" => lemma, "Msa" => msa,
                         "Count" => forms.fetch(key), "Source" => BIB_KEY }
          end
        end
        CsvWriter.write(path: File.join(out_dir, FORM_FILENAME), columns: FORM_COLUMNS, rows: rows)
      end

      def write_lemmas(lemmas, out_dir)
        keys = lemmas.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |lemma|
            yielder << { "ID" => mint_row_id(lemma, lemma), "Language_ID" => LANGUAGE_ID,
                         "Lemma" => lemma, "Count" => lemmas.fetch(lemma) }
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
        columns.map { |name| { name: name, type: name == "Count" ? "integer" : "string" } }
      end

      # The credit Menota's catalogue and every teiHeader ask for.
      def citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "author" => "{Medieval Nordic Text Archive}",
            "title" => "Menota — the Medieval Nordic Text Archive",
            "url" => "https://www.menota.org",
            "note" => "CC BY-SA 4.0; texts served at https://clarino.uib.no/menota/catalogue/menota — " \
                      "cite the editor(s) named in each text's teiHeader"
          }
        )
      end

      def notes
        <<~NOTES.strip
          ## Using this dataset

          `form-lemma.csv` maps attested Old Norse word forms — Old Icelandic and Old
          Norwegian manuscripts transcribed by Menota — to their lemmas. Columns: `Level` —
          the transcription level the form comes from: `facs` (facsimile: the glyphs as
          written, MUFI private-use characters and abbreviation marks included — a MUFI font
          renders them), `dipl` (diplomatic: abbreviations expanded, the scribe's spelling
          kept), `norm` (normalized Old Norse orthography, the dictionary-facing form);
          `Form` — the word at that level, verbatim; `Lemma` — Menota's headword; `Msa` — the
          `me:msa` morphosyntactic analysis verbatim (`xNC gM nS cN sI`); `Count` —
          attestations. One word attested at three levels counts once in each, so filter on
          `Level` before summing. `lemmas.csv` counts each lemmatized word once per `Lemma`.
          Old Swedish and Old Danish documents are out of scope (counts in
          `datapackage.json` → `nabu.eval`).

          Load with pandas:

              df = pd.read_csv("form-lemma.csv", dtype=str, keep_default_na=False).astype({"Count": int})
              norm = df[df.Level == "norm"]

          How to cite: credit the Medieval Nordic Text Archive, https://www.menota.org, and
          the editor(s) named in each text's teiHeader (CC BY-SA 4.0; the `menota` key in
          `sources.bib`) — alongside this dataset's `datapackage.json` provenance block.
        NOTES
      end
    end
  end
end
