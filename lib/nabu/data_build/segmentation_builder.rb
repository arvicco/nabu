# frozen_string_literal: true

require "digest"
require "json"
require "sequel"

require_relative "../errors"
require_relative "builder"
require_relative "csv_writer"
require_relative "tibetan_segmenter"
require_relative "segmentation_eval"

module Nabu
  module DataBuild
    # The xct/segmentation builder (P51-W5) — segmented Classical Tibetan,
    # CURATED SLICE ONLY (owner-ratified design): every live soas-tibetan
    # document (the ready-made eval set — gold segmentation + gold POS,
    # verbatim from the deposit) plus ONE small Kangyur text silver-segmented
    # by TibetanSegmenter, with the segmenter's error rate measured against
    # the SOAS gold (leave-one-text-out) and published in-band — the
    # manifest's nabu.eval block and the README both carry it. The full canon
    # is explicitly out of scope; this dataset is the calibration ground for
    # any future full-canon layer.
    #
    # == The slice definition (explicit and stable, part of the recipe)
    #
    # - All soas-tibetan documents: mdzangsblun, buston, mila, marpa — the
    #   gold rows (Tier=gold), tokens verbatim from the deposit's form|tag
    #   lines, POS riding only the CoNLL-U projection (XPOS).
    # - urn:nabu:derge-kangyur:toh21 — Shes rab snying po (Heart Sutra,
    #   Prajñāpāramitāhṛdaya), the one Kangyur text in this release: small
    #   (19 passages), complete, and the most-studied text in the canon, so
    #   a human can actually review every silver segmentation decision.
    #
    # == Read path
    #
    # The catalog (read-only Sequel, the FormLemma precedent): soas passages
    # carry the gold tokens in annotations_json exactly as parsed, derge
    # passages carry text + content_sha256 — the anchoring contract's sha
    # (rows apply only where the passage sha matches). The Runner's
    # stale-ingest guard (P50-r1) keeps catalog rows and the recorded cone
    # shas honest with each other.
    class SegmentationBuilder
      SOAS_SLUG = "soas-tibetan"
      DERGE_SLUG = "derge-kangyur"

      # The production Kangyur slice: Toh 21 (see the class note). The
      # keyword seam exists for fixture-scale tests (the adapter pin:
      # pattern); `nabu data build` always constructs with the default.
      KANGYUR_SLICE = ["urn:nabu:derge-kangyur:toh21"].freeze

      CSV_FILENAME = "segmentation.csv"
      CONLLU_FILENAME = "segmentation.conllu"
      COLUMNS = %w[ID URN Passage_SHA256 Position Form Offset Tier Source].freeze

      SOAS_BIB_KEY = "soas574878"
      DERGE_BIB_KEY = "derge"

      GOLD_TIER = "gold"
      SILVER_TIER = "silver"

      # Part of the derivation fingerprint: changing the slice, the
      # segmenter, or the eval protocol MUST change this string.
      RECIPE = "xct/segmentation v1: curated slice = every live soas-tibetan document " \
               "(gold segmentation + POS verbatim from Zenodo 574878) + %<slice>s " \
               "silver-segmented by a pure-Ruby unigram-cost Viterbi segmenter over tsheg-bar " \
               "units (closed attached-clitic class འིས/འི/འོ/འང/འམ/ར/ས split only on a known " \
               "stem, max word span #{TibetanSegmenter::MAX_SPAN} tsheg-bars, unknown " \
               "pseudo-count #{TibetanSegmenter::UNKNOWN_PSEUDO_COUNT}) trained on the SOAS gold " \
               "token counts alone (external lexica measured unhelpful or harmful in the " \
               "2026-07-29 spike and deliberately excluded); eval = leave-one-text-out " \
               "cross-validation against the SOAS gold, boundary F1 over line-interior token " \
               "starts, published in the manifest nabu.eval block. Offsets index the passage's " \
               "NFC text; Passage_SHA256 anchors each row to the exact catalog passage bytes.".freeze

      def initialize(kangyur_slice: KANGYUR_SLICE)
        @kangyur_slice = kangyur_slice
      end

      def build(catalog:, out_dir:)
        if catalog.nil?
          raise Error, "xct/segmentation reads the catalog and no catalog is open on this box — " \
                       "build where db/catalog.sqlite3 exists"
        end

        gold_docs = load_gold(catalog)
        slice_passages = load_slice(catalog)
        evaluation = SegmentationEval.leave_one_text_out(eval_docs(gold_docs))
                                     .merge("against" => "soas-tibetan gold segmentation (Zenodo 574878)")
        segmenter = TibetanSegmenter.train(SegmentationEval.counts(eval_docs(gold_docs)))

        rows = gold_rows(gold_docs) + silver_rows(slice_passages, segmenter)
        csv_count = CsvWriter.write(path: File.join(out_dir, CSV_FILENAME), columns: COLUMNS,
                                    rows: rows.map { |row| row.except("XPOS") })
        write_conllu(File.join(out_dir, CONLLU_FILENAME), rows, passage_texts(gold_docs, slice_passages))

        BuildResult.new(resources: [csv_resource(csv_count), conllu_resource],
                        recipe: format(RECIPE, slice: slice_label),
                        citations: citations, notes: notes(evaluation), evaluation: evaluation)
      end

      private

      # -- catalog reads ------------------------------------------------------

      def live_passages(catalog, source_slug)
        catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:withdrawn] => false,
                 Sequel[:documents][:withdrawn] => false,
                 Sequel[:sources][:slug] => source_slug)
          .select(Sequel[:passages][:urn], Sequel[:passages][:sequence], Sequel[:passages][:text],
                  Sequel[:passages][:annotations_json], Sequel[:passages][:content_sha256],
                  Sequel[:documents][:urn].as(:document_urn))
      end

      # { document_urn => [passage row, ...] } in passage order; each row
      # gains :tokens (the gold form/pos pairs) with offsets validated
      # against the passage text.
      def load_gold(catalog)
        rows = live_passages(catalog, SOAS_SLUG).order(:document_urn, Sequel[:passages][:sequence]).all
        if rows.empty?
          raise Error, "the catalog has no soas-tibetan passages — sync the gold corpus " \
                       "(bin/nabu sync soas-tibetan) before building xct/segmentation"
        end

        rows.each { |row| row[:tokens] = gold_tokens(row) }
        rows.group_by { |row| row[:document_urn] }
      end

      # The stored gold tokens, re-anchored: cumulative form offsets must
      # reconstruct the passage text exactly, or the row set would lie about
      # its own anchoring.
      def gold_tokens(row)
        tokens = JSON.parse(row[:annotations_json] || "{}")["tokens"]
        raise Error, "#{row[:urn]}: soas-tibetan passage carries no gold tokens" unless tokens.is_a?(Array)

        offset = 0
        anchored = tokens.map do |token|
          form = token.fetch("form")
          anchored_token = { form: form, pos: token["pos"], offset: offset }
          offset += form.length
          anchored_token
        end
        unless anchored.map { |token| token[:form] }.join == row[:text]
          raise Error, "#{row[:urn]}: gold forms do not reconstruct the passage text — " \
                       "the offsets would be dishonest; re-ingest soas-tibetan"
        end
        anchored
      end

      # The Kangyur slice passages, in slice order then passage order. A
      # slice document missing from the catalog refuses by name.
      def load_slice(catalog)
        @kangyur_slice.flat_map do |document_urn|
          rows = live_passages(catalog, DERGE_SLUG)
                 .where(Sequel[:documents][:urn] => document_urn)
                 .order(Sequel[:passages][:sequence]).all
          if rows.empty?
            raise Error, "slice document #{document_urn} has no passages in this catalog — " \
                         "sync derge-kangyur (bin/nabu sync derge-kangyur) before building " \
                         "xct/segmentation"
          end
          rows
        end
      end

      # -- eval + segmentation ------------------------------------------------

      def eval_docs(gold_docs)
        @eval_docs ||= gold_docs.transform_values do |passages|
          passages.map do |row|
            { text: row[:text], forms: row[:tokens].map { |token| token[:form] } }
          end
        end
      end

      # -- rows ---------------------------------------------------------------

      def gold_rows(gold_docs)
        gold_docs.keys.sort.flat_map do |document_urn|
          gold_docs.fetch(document_urn).flat_map do |row|
            row[:tokens].each_with_index.map do |token, index|
              csv_row(urn: row[:urn], sha: row[:content_sha256], position: index + 1,
                      form: token[:form], offset: token[:offset], tier: GOLD_TIER,
                      source: SOAS_BIB_KEY, pos: token[:pos])
            end
          end
        end
      end

      def silver_rows(slice_passages, segmenter)
        slice_passages.flat_map do |row|
          segmenter.segment(row[:text]).each_with_index.map do |token, index|
            csv_row(urn: row[:urn], sha: row[:content_sha256], position: index + 1,
                    form: token.form, offset: token.offset, tier: SILVER_TIER,
                    source: DERGE_BIB_KEY, pos: nil)
          end
        end
      end

      # XPOS rides along for the CoNLL-U projection and is stripped before
      # CSV emission (POS stays out of the table: the gold tags live in the
      # projection, silver rows have none to publish).
      def csv_row(urn:, sha:, position:, form:, offset:, tier:, source:, pos:)
        {
          "ID" => mint_id(urn, position),
          "URN" => urn,
          "Passage_SHA256" => sha,
          "Position" => position,
          "Form" => form,
          "Offset" => offset,
          "Tier" => tier,
          "Source" => source,
          "XPOS" => pos
        }
      end

      # Deterministic and content-derived: the passage URN digest + the
      # 1-based token position (URNs are unique; Tibetan forms cannot survive
      # the CLDF identifier class, so the URN is digested, not folded).
      def mint_id(urn, position)
        CsvWriter.mint_id("s", Digest::SHA256.hexdigest(urn)[0, 12], position.to_s)
      end

      # -- CoNLL-U projection -------------------------------------------------

      # One sentence per passage: sent_id = the passage URN, one token per
      # line, `_` for every absent field — never invented lemmas or POS; gold
      # rows carry their real SOAS tag as XPOS. Tokens join with nothing in
      # Tibetan, hence SpaceAfter=No on every token but the sentence-final.
      def write_conllu(path, rows, texts)
        File.open(path, "w", encoding: Encoding::UTF_8) do |io|
          rows.group_by { |row| row["URN"] }.each do |urn, passage_rows|
            io.puts "# sent_id = #{urn}"
            io.puts "# text = #{texts.fetch(urn)}"
            passage_rows.each_with_index do |row, index|
              misc = index == passage_rows.size - 1 ? "_" : "SpaceAfter=No"
              io.puts [row["Position"], row["Form"], "_", "_", row["XPOS"] || "_",
                       "_", "_", "_", "_", misc].join("\t")
            end
            io.puts
          end
        end
      end

      def passage_texts(gold_docs, slice_passages)
        texts = {}
        gold_docs.each_value { |passages| passages.each { |row| texts[row[:urn]] = row[:text] } }
        slice_passages.each { |row| texts[row[:urn]] = row[:text] }
        texts
      end

      # -- furniture ----------------------------------------------------------

      def slice_label
        @kangyur_slice.join(", ")
      end

      def csv_resource(count)
        Resource.new(
          name: "segmentation", path: CSV_FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: integer_column?(name) ? "integer" : "string" } },
          primary_key: ["ID"]
        )
      end

      def integer_column?(name)
        %w[Position Offset].include?(name)
      end

      def conllu_resource
        Resource.new(name: "segmentation-conllu", path: CONLLU_FILENAME,
                     format: "conllu", mediatype: "text/plain")
      end

      def citations
        [
          Citation.new(
            key: SOAS_BIB_KEY, type: "misc",
            fields: {
              "author" => "Hill, Nathan W. and Garrett, Edward and others",
              "title" => "A part-of-speech (POS) tagged corpus of Classical Tibetan",
              "year" => "2017",
              "doi" => "10.5281/zenodo.574878",
              "note" => "CC BY 4.0; SOAS project 'Tibetan in Digital Communication' " \
                        "(AHRC AH/J00152X/1); tag set Garrett et al. 2014/2015"
            }
          ),
          Citation.new(
            key: DERGE_BIB_KEY, type: "misc",
            fields: {
              "title" => "Digital Derge Kangyur (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur)",
              "howpublished" => "https://github.com/Esukhia/derge-kangyur",
              "note" => "Public Domain (upstream README declaration); " \
                        "ཆོས་ཀྱི་འབྱུང་" \
                        "གནས། [1721--31], Derge woodblock Kangyur"
            }
          )
        ]
      end

      def notes(evaluation)
        <<~NOTES.strip
          ## The slice — and why it is small

          This release is deliberately a CURATED SLICE, not the canon: the four
          SOAS gold texts (the eval set itself, published with their gold
          segmentation) plus one complete Kangyur text, Toh 21 — Shes rab snying
          po (the Heart Sutra) — chosen because it is short (19 passages),
          complete, and studied enough that every silver segmentation decision
          can actually be reviewed by a human. The segmenter's error rate below
          is the calibration number any full-canon layer would have to answer to.

          ## The eval — the headline number

          Boundary F1 **#{format('%.4f', evaluation.fetch('boundary_f1'))}**
          (precision #{format('%.4f', evaluation.fetch('boundary_precision'))},
          recall #{format('%.4f', evaluation.fetch('boundary_recall'))}; exact-token
          F1 #{format('%.4f', evaluation.fetch('token_f1'))}) against
          #{evaluation.fetch('against')} — #{evaluation.fetch('texts')} texts,
          #{evaluation.fetch('lines')} lines, #{evaluation.fetch('tokens')} gold tokens.
          Protocol: #{evaluation.fetch('protocol')}. Contamination:
          #{evaluation.fetch('contamination')}. The same numbers ride
          `datapackage.json` under `nabu.eval`.

          ## Columns

          `URN` + `Passage_SHA256` are the anchoring contract: rows apply only to
          a passage whose Nabu content sha matches. `Position` is the 1-based
          token index in the passage; `Offset` the 0-based character offset of
          `Form` in the passage's NFC text (the token is always the exact
          substring at its offset). `Tier` is `gold` for SOAS rows (segmentation
          verbatim from the deposit) and `silver` for segmenter output. Gold POS
          tags are NOT columns here — they ride the CoNLL-U projection
          (`segmentation.conllu`, XPOS field) so nothing invented ever sits next
          to something gold.

          ## Loading

              import pandas as pd
              df = pd.read_csv("segmentation.csv", keep_default_na=False)
        NOTES
      end
    end
  end
end
