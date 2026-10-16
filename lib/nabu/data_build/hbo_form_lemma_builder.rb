# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The hbo/form-lemma builder — the Biblical Hebrew form→lemma table
    # swept from the Open Scriptures Hebrew Bible's word annotations, the
    # san/form-lemma mold transposed to OSHB's lemma identity.
    #
    # == Read path: the catalog, the oshb source ALONE
    #
    # The oshb adapter's OshbOsisParser stores every running-text <w> as a
    # token in passages.annotations_json: "form" (the word's bytes with
    # OSHB's "/" morpheme divider removed), "lemma" = @lemma VERBATIM — an
    # augmented Strong's id, prefix morphemes slash-joined and homograph
    # letters suffixed ("b/7225", "c/d/776", "1254 a"; "+" marks a
    # proper-name component) — "morph" = the OSHM code verbatim
    # ("HC/Td/Ncbsa"), and "lang" from the OSHM language prefix. The sweep
    # is scoped to the oshb source by slug: the catalog ALSO holds BHSA
    # Hebrew (CC BY-NC, license class nc), and no row of it may contribute
    # — the census names every other source's Hebrew documents so the
    # exclusion is visible, never silent. The oshb row's own license class
    # is gated too (open/attribution only), so a reclassification can
    # never let an nc lane through.
    #
    # == The sweep
    #
    # A running-text token mints a count iff it bears a lemma AND is
    # Hebrew (OSHM `H`). Aramaic words (OSHM `A` — Gen 31:47, Jer 10:11,
    # the Aramaic chapters of Daniel/Ezra) are a different language and
    # are excluded and censused. Ketiv/qere: the running text carries the
    # ketiv <w> (counted, as written); the qere readings ride the token's
    # "qere" apparatus and are excluded and censused.
    #
    # Grains (each CSV's declared primary key IS its grain):
    #   form-lemma.csv (Form, Lemma, Morph) — Head_Lemma is a function of
    #                  Lemma: the composite's final "/" segment (OSHB lists
    #                  prefix morphemes first), the word's content lemma
    #   lemmas.csv     (Head_Lemma) — the per-content-lemma sidecar
    #
    # == Bytes: verbatim, never NFC
    #
    # hbo is NFC-EXEMPT (Normalize::NFC_EXEMPT_LANGUAGES, owner ruling
    # 2026-07-18): the WLC's Masoretic combining-mark order is not
    # NFC-stable and upstream forbids normalizing. Forms are carried exactly
    # as the catalog holds them — nothing here normalizes.
    #
    # == Determinism
    #
    # Rows emit in byte-order of their grain tuple; IDs are a readable head
    # plus a 12-hex digest of the exact tuple (the mold's minting — Hebrew
    # forms fold away under mint_id, so the digest carries the identity).
    class HboFormLemmaBuilder
      SOURCE_SLUG = "oshb"
      BIB_KEY = "oshb"
      LANGUAGE_ID = "hbo"
      HEBREW = "hbo"
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      FORM_FILENAME = "form-lemma.csv"
      FORM_COLUMNS = %w[ID Language_ID Form Lemma Head_Lemma Morph Count Source].freeze
      FORM_PRIMARY_KEY = %w[Form Lemma Morph].freeze

      LEMMAS_FILENAME = "lemmas.csv"
      LEMMA_COLUMNS = %w[ID Language_ID Head_Lemma Count].freeze
      LEMMA_PRIMARY_KEY = %w[Head_Lemma].freeze

      RECIPE = "hbo/form-lemma v1: sweep the stored token annotations of every live passage of " \
               "the oshb source ALONE (no other source's Hebrew — BHSA is CC BY-NC and contributes " \
               "nothing); keep the running-text tokens bearing a lemma whose OSHM language prefix " \
               "is Hebrew — Aramaic tokens and the qere apparatus readings mint no row, both " \
               "censused; carry Form/Lemma/Morph byte-verbatim (hbo is NFC-exempt, never " \
               "re-normalized); count attestations at the distinct (Form, Lemma, Morph) grain " \
               "into form-lemma.csv and at the Head_Lemma (final \"/\" segment of the augmented " \
               "Strong's lemma) grain into lemmas.csv."

      SEPARATOR = "\t"
      DIGEST_LENGTH = 12

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "hbo/form-lemma reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        source = oshb_source!(catalog)
        forms, heads, census = aggregate(catalog, source[:id])
        census["excluded_hebrew_documents"] = excluded_hebrew_documents(catalog, source[:id])

        form_rows = write_forms(forms, out_dir)
        lemma_rows = write_lemmas(heads, out_dir)
        BuildResult.new(resources: [form_resource(form_rows), lemma_resource(lemma_rows)],
                        recipe: RECIPE, citations: [citation], notes: notes, evaluation: census)
      end

      private

      def oshb_source!(catalog)
        source = catalog[:sources].where(slug: SOURCE_SLUG).select(:id, :license_class).first
        if source.nil?
          raise Error, "the catalog has no oshb rows — sync oshb (bin/nabu sync oshb) " \
                       "before building hbo/form-lemma"
        end
        unless PUBLISHABLE_LICENSE_CLASSES.include?(source[:license_class])
          raise Error, "hbo/form-lemma: #{SOURCE_SLUG} license class #{source[:license_class].inspect} " \
                       "is not publishable (#{PUBLISHABLE_LICENSE_CLASSES.join('/')})"
        end

        source
      end

      # -- the sweep ----------------------------------------------------------

      def aggregate(catalog, source_id)
        forms = Hash.new(0)
        heads = Hash.new(0)
        census = { "input_source" => SOURCE_SLUG, "passages_scanned" => 0, "hebrew_tokens_counted" => 0,
                   "aramaic_tokens_excluded" => 0, "qere_readings_excluded" => 0,
                   "lemma_less_tokens_excluded" => 0 }
        live_passages(catalog, source_id).each do |row|
          census["passages_scanned"] += 1
          each_token(row[:annotations_json]) do |token|
            next unless countable?(token, census)

            lemma = token["lemma"]
            forms[[token["form"].to_s, lemma, token["morph"].to_s].join(SEPARATOR)] += 1
            heads[head_lemma(lemma)] += 1
            census["hebrew_tokens_counted"] += 1
          end
        end
        if forms.empty?
          raise Error, "the catalog has no oshb Hebrew tokens — sync oshb (bin/nabu sync oshb) " \
                       "before building hbo/form-lemma"
        end

        [forms, heads, census]
      end

      def countable?(token, census)
        census["qere_readings_excluded"] += Array(token["qere"]).size
        if token["lemma"].to_s.empty?
          census["lemma_less_tokens_excluded"] += 1
          false
        elsif token["lang"] != HEBREW
          census["aramaic_tokens_excluded"] += 1
          false
        else
          true
        end
      end

      # The Indexer's two-level visibility rule, scoped to the oshb source.
      def live_passages(catalog, source_id)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:documents][:source_id] => source_id)
          .order(Sequel[:passages][:id])
          .select(Sequel[:passages][:annotations_json])
      end

      def each_token(json, &)
        return if json.nil? || !json.include?('"tokens"')

        tokens = JSON.parse(json)["tokens"]
        return unless tokens.is_a?(Array)

        tokens.each { |token| yield token if token.is_a?(Hash) }
      end

      # The composite's final "/" segment — OSHB lists prefix morphemes
      # (b, c, d, k, l, m …) first, the content lemma last.
      def head_lemma(lemma) = lemma.split("/").last.to_s

      # Every OTHER source's live Hebrew documents, per slug — the
      # exclusion census (BHSA's nc Hebrew among them). Documents, not
      # passages: a cheap count that still names who was left out.
      def excluded_hebrew_documents(catalog, source_id)
        catalog[:documents]
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:documents][:language] => HEBREW, Sequel[:documents][:withdrawn] => false)
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
            form, lemma, morph = key.split(SEPARATOR, -1)
            yielder << { "ID" => mint_row_id(lemma, morph, key), "Language_ID" => LANGUAGE_ID,
                         "Form" => form, "Lemma" => lemma, "Head_Lemma" => head_lemma(lemma),
                         "Morph" => morph, "Count" => forms.fetch(key), "Source" => BIB_KEY }
          end
        end
        CsvWriter.write(path: File.join(out_dir, FORM_FILENAME), columns: FORM_COLUMNS, rows: rows)
      end

      def write_lemmas(heads, out_dir)
        keys = heads.keys.sort
        rows = Enumerator.new(keys.size) do |yielder|
          keys.each do |head|
            yielder << { "ID" => mint_row_id(head, head), "Language_ID" => LANGUAGE_ID,
                         "Head_Lemma" => head, "Count" => heads.fetch(head) }
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

      # The credit OSHB's README asks for, with the per-layer license.
      def citation
        Citation.new(
          key: BIB_KEY, type: "misc",
          fields: {
            "author" => "{Open Scriptures Hebrew Bible Project}",
            "title" => "Open Scriptures Hebrew Bible (Westminster Leningrad Codex + OSHM morphology)",
            "url" => "https://github.com/openscriptures/morphhb",
            "note" => "WLC text public domain; lemma and morphology data CC BY 4.0"
          }
        )
      end

      def notes
        <<~NOTES.strip
          ## Using this dataset

          `form-lemma.csv` maps attested Biblical Hebrew word forms to their OSHB lemmas.
          Columns: `Form` — the pointed word as the Westminster Leningrad Codex writes it
          (OSHB's `/` morpheme divider removed; bytes verbatim — **never NFC-normalize**,
          the Masoretic mark order is not NFC-stable); `Lemma` — OSHB's augmented Strong's
          lemma verbatim (prefix morphemes slash-joined, homograph letters suffixed:
          `c/d/776`, `1254 a`); `Head_Lemma` — its final segment, the content lemma;
          `Morph` — the OSHM morphology code verbatim; `Count` — attestations.
          `lemmas.csv` re-buckets the same tokens per `Head_Lemma`. Aramaic words and qere
          readings are excluded (counts in `datapackage.json` → `nabu.eval`).

          Load with pandas:

              df = pd.read_csv("form-lemma.csv", dtype=str).astype({"Count": int})

          How to cite: credit the Open Scriptures Hebrew Bible Project,
          https://github.com/openscriptures/morphhb (lemma/morphology CC BY 4.0; the `oshb`
          key in `sources.bib`) — alongside this dataset's `datapackage.json` provenance block.
        NOTES
      end
    end
  end
end
