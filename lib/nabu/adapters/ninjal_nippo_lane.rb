# frozen_string_literal: true

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # ninjal-textdb's declared secondary dictionary lane (Adapter.dictionary_lane,
    # the multi-shelf seam): the Nippo Jisho entry-word data — NINJAL's
    # "Entry Words Data of Nippojisho Ver.202510" (OHSHIMA Hideyuki, assisted
    # by AIDA Taichi; released 2025-10-30), one tab-separated row per headword
    # of the Jesuit Vocabulario da Lingoa de Iapam (1603–04), keyed from the
    # Bodleian copy via the Bensei colour facsimile (the readme's 底本).
    #
    # The data carries HEADWORDS, not definitions: the romanized headword as
    # printed (vel variants "l" rewritten as "|" by upstream), a mechanical
    # katakana transcription, the modern dictionary form for verbs, the
    # folio+column (001a–331d the body, 332a–402d the Supplemento), the
    # facsimile and Japanese-translation page numbers, a Gallica image URL
    # for the Paris copy (which lacks the supplement), upstream's own notes,
    # and the Nihon Kokugo Daijiten ids it matched. The Portuguese
    # definitions are not in the data — a future source, not a parse gap.
    #
    # Entry shape (dictionary slug nippo-jisho, language jpn):
    # - entry_id: upstream's 見出し語ID (folio + column + order, "001a03" —
    #   unique, 32,878 of 32,878, census 2026-11-04);
    # - headword / key_raw: the printed romanization verbatim
    #   ("Aara.|,ara.", "Abaqi,u,aita.");
    # - headword_folded: the FIRST form (before the first "|" or ",", its
    #   closing period dropped), long ſ → s, then the jpn search fold —
    #   "Abaqi,u,aita." → "abaqi" (the verb's stem form, the paradigm tail
    #   stays in the headword);
    # - gloss: nil (no definitions upstream — declared, never faked);
    # - body: headword, katakana and the folio citation;
    # - annotations: every remaining column (see #annotations).
    #
    # Language jpn — the lect override (config/lect_overrides.yml) reads it as
    # jpn:lmj~latn, the registry's Late Middle Japanese held in Latin script.
    class NinjalNippoLane < Nabu::Adapter
      LANGUAGE = "jpn"
      SLUG = "nippo-jisho"
      REF_ID = "ninjal-textdb-dictionary:#{SLUG}".freeze
      DIR = "nipp"
      TSV = "ew-nippo-202510.txt"
      TITLE = "Vocabulario da Lingoa de Iapam (日葡辞書, 1603) — NINJAL entry-word data Ver.202510"

      HEADER = %w[整理番号 見出し語ID 見出し語 見出し語（片仮名） 動詞終止形（現代） 原本所在 影印本所在
                  邦訳本所在 BnF画像 備考 日国ID 日国ID（参考）].freeze

      # 001–331 are the dictionary proper, 332–402 the Supplemento (readme [F]).
      SUPPLEMENT_FROM = 332

      def self.manifest = NinjalTextdb::MANIFEST

      def self.content_kind = :dictionary

      def self.tsv_path(workdir) = File.join(workdir, DIR, TSV)

      def self.fold(form) = Normalize.search_form(form.tr("ſ", "s"), language: LANGUAGE)

      # The first printed form: before the first vel "|" or paradigm ",",
      # without its closing period.
      def self.first_form(headword)
        headword.split("|").first.to_s.split(",").first.to_s.strip.delete_suffix(".").strip
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        path = self.class.tsv_path(workdir)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: NinjalTextdb::SLUG, id: REF_ID, path: File.expand_path(path),
                                    metadata: { "dictionary" => SLUG })
      end

      def parse(document_ref)
        rows = rows(document_ref.path)
        document = Nabu::DictionaryDocument.new(slug: SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        rows.each { |row| document << entry(row) }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def rows(path)
        text = SourceRead.utf8_file(path, label: "nippo-jisho")
        lines = text.delete_prefix("﻿").split(/\r\n|\r|\n/).reject(&:empty?)
        header = lines.shift.to_s.split("\t", -1)
        raise Nabu::ParseError, "#{path}: header drifted from the censused 12 columns" unless header == HEADER

        lines.map do |line|
          cells = line.split("\t", -1).map { |cell| Normalize.nfc(cell.strip) }
          raise Nabu::ParseError, "#{path}: row #{cells.first} has #{cells.size} columns" unless cells.size == 12

          cells
        end
      end

      def entry(cells)
        seq, id, headword, katakana, _verb, folio = cells
        raise Nabu::ParseError, "nippo-jisho row #{seq}: empty headword" if headword.empty?

        first = self.class.first_form(headword)
        part = Integer(folio[/\A\d+/] || "0", 10) >= SUPPLEMENT_FROM ? "supplement" : "main"
        citation = "f. #{folio}#{' (Supplemento)' if part == 'supplement'}"
        Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: headword, language: LANGUAGE, headword: headword,
          headword_folded: self.class.fold(first.empty? ? headword : first),
          body: Normalize.nfc("#{headword}  #{katakana}\nVocabulario da Lingoa de Iapam (1603), #{citation}"),
          annotations: annotations(cells, part)
        )
      end

      def annotations(cells, part)
        seq, _id, _headword, katakana, verb, folio, facsimile, translation, bnf, note, nikkoku, related = cells
        {
          "seq" => Integer(seq, 10), "katakana" => presence(katakana), "verb_modern" => presence(verb),
          "folio" => folio, "part" => part,
          "facsimile_page" => presence(facsimile), # 『キリシタン版 日葡辞書 カラー影印版』(勉誠出版 2013)
          "translation_page" => presence(translation), # 『邦訳日葡辞書』(岩波書店 1980)
          "bnf_image" => presence(bnf), "note" => presence(note),
          "nikkoku_ids" => ids(nikkoku), "nikkoku_related_ids" => ids(related)
        }.compact
      end

      def presence(value) = value.empty? ? nil : value

      def ids(value)
        list = value.split(";").map(&:strip).reject(&:empty?)
        list.empty? ? nil : list
      end
    end
  end
end
