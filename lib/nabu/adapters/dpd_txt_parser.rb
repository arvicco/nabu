# frozen_string_literal: true

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Digital Pāḷi Dictionary text-export parser family: dpd.txt from
    # the dpd-db release's dpd-txt.zip — one blank-line-separated block per
    # headword:
    #
    #   akakkasa, adj. smooth; tender; not harsh; not rough ✔
    #     IPA: /əkəkkəs̪ə/
    #     Grammar: adj, from na kakkasa, neg
    #     Construction: na > a + kakkasa
    #     Sanskrit: akarkaśa (na + karkaśa)
    #     ID: 7
    #
    # The head line is "<lemma_1>, <pos>. <meaning> <mark>" — lemma_1 the
    # lemma with DPD's homonym number ("a 1.1"), the mark DPD's own
    # completeness flag (✔ 55,060 · ✘ 25,625 · ◑ 9,078 at census). Per
    # block, one DictionaryEntry:
    #
    # - entry_id: the "ID:" field (DPD's stable integer id, unique at
    #   census over 89,763 blocks).
    # - headword: lemma_1 without its homonym number; key_raw: lemma_1.
    # - body: the head line, then every field line ("Key: value") but ID,
    #   NFC (1,035 blocks are non-NFC upstream).
    # - gloss: the meaning's first ";"-segment, a leading register label
    #   ("(gram)") dropped.
    # - annotations: "pos" — the head line's part of speech (adj 19,066 ·
    #   nt 17,392 · masc 16,372 …, 30 values); "root" — the Root field
    #   (37,132 blocks), e.g. "√kaṅkh 1 a (doubt)".
    #
    # Deliberately unmined (declared): the Sanskrit / Sanskrit Root /
    # English cognate fields are parallels printed with their analysis
    # ("akarkaśa (na + karkaśa)"), not clean reflex words — they read in
    # the body; Synonym/Antonym name headwords without DPD ids.
    class DpdTxtParser
      LANGUAGE = "pli"
      HEAD = /\A(?<lemma>.+?), (?<pos>[^.]+)\. (?<meaning>.*?)\s*[✔✘◑]?\z/
      HOMONYM = /\s\d+(?:\.\d+)?\z/
      FIELD = /\A\s+(?<key>[^:]+): (?<value>.*)\z/
      private_constant :HEAD, :HOMONYM, :FIELD

      def entries(path)
        text = SourceRead.utf8_file(path, label: "dpd-txt")
        text.split(/\n{2,}/).map(&:strip).reject(&:empty?).map { |block| build(block, path) }
      end

      private

      def build(block, path)
        head, *fields = block.lines(chomp: true)
        match = HEAD.match(head) or raise Nabu::ParseError, "dpd-txt: #{path}: unreadable head line #{head.inspect}"
        pairs = fields.filter_map { |line| FIELD.match(line)&.then { |m| [m[:key], m[:value]] } }
        id = pairs.find { |key, _| key == "ID" }&.last
        raise Nabu::ParseError, "dpd-txt: #{path}: block without an ID: #{head.inspect}" if id.nil? || id.strip.empty?

        lemma = nfc(match[:lemma])
        headword = lemma.sub(HOMONYM, "")
        Nabu::DictionaryEntry.new(
          entry_id: id.strip, key_raw: lemma, language: LANGUAGE, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(match[:meaning]),
          body: ([nfc(head)] + pairs.reject { |pair| pair.first == "ID" }.map { |k, v| nfc("#{k}: #{v}") }).join("\n"),
          annotations: annotations(match[:pos], pairs)
        )
      end

      def gloss(meaning)
        first = nfc(meaning).split(";", 2).first.to_s.sub(/\A\([^)]*\)\s*/, "").strip
        first.match?(/\p{L}/) ? first : nil
      end

      def annotations(pos, pairs)
        found = { "pos" => nfc(pos) }
        root = pairs.find { |key, _| key == "Root" }&.last
        found["root"] = nfc(root) if root && !root.strip.empty?
        found
      end

      def nfc(text) = Nabu::Normalize.nfc(text.to_s.strip)
    end
  end
end
