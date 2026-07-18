# frozen_string_literal: true

require "json"

require_relative "../date_axis"

module Nabu
  module Adapters
    # The `tla-jsonl` family reader (P28-2): one record per line of the TLA's
    # official Hugging Face train.jsonl artifacts. ONE reader shared by the
    # adapter (Adapters::TlaHf) and the date-axis extractor
    # (Store::AxisBuilder::TlaHfDates), so record numbering and date parsing
    # can never drift between the two.
    #
    # == Record shape (censused 2026-07-18 on both full artifacts;
    #    test/fixtures/tla-hf/README.md)
    #
    # Shared fields: `transliteration` (Leiden Unified, space-separated),
    # `lemmatization` (space-separated `<TLA lemma ID>|<lemma>` pairs —
    # demotic ids `d`/`dm`-prefixed, late-Egyptian ids bare numbers, one
    # lemma space with AED/AES), `UPOS`, `glossing`, `translation` (German),
    # `dateNotBefore`/`dateNotAfter` (strings holding signed historical
    # integers or empty — no year 0, no inverted range upstream). Optional:
    # `hieroglyphs` (late Egyptian; Unicode v15 + `<g>JSesh</g>` fallbacks),
    # `authors` (demotic). The four token-bearing fields split to IDENTICAL
    # counts on every upstream record (censused: 0 misalignments) — a
    # mismatch here is damage and raises Nabu::ParseError, never a shrug.
    #
    # == Identity is the line number
    #
    # Upstream ships NO sentence/text ids (censused), so a record's identity
    # is its 1-based line number in the canonical file — deterministic and
    # stable while the sha-pinned artifact is unchanged, which is the honest
    # best available (the starling file-order precedent). +number+ carries it.
    class TlaJsonlParser
      # One lemmatized token: the aligned four-way split plus the TLA lemma
      # id — the join key into the TLA lemma space.
      Token = Data.define(:form, :lemma_id, :lemma, :upos, :gloss)

      # One sentence record. Dates are signed historical integers or nil
      # (empty upstream strings); hieroglyphs/authors nil where the dataset
      # ships none.
      Record = Data.define(:number, :transliteration, :tokens, :translation,
                           :not_before, :not_after, :hieroglyphs, :authors)

      # `<TLA lemma ID>|<lemma transliteration>` — ids are censused as
      # optionally-letter-prefixed numbers (d2779, dm2809, 851513).
      LEMMA_PAIR = /\A([a-z]*\d+)\|(.+)\z/

      # Yield each line of +path+ as a Record (or return an Enumerator).
      # Damage — malformed JSON, a missing field, misaligned token fields, a
      # malformed lemma pair, a bad year — raises Nabu::ParseError naming the
      # line, which quarantines the whole dataset document: the artifact is
      # sha-pinned and censused clean, so a defect is corruption, not a rule.
      def each_record(path)
        return enum_for(:each_record, path) unless block_given?

        File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
          yield record(line, number, path)
        end
      end

      private

      def record(line, number, path)
        fields = parse_json(line, number, path)
        Record.new(
          number: number,
          transliteration: fetch(fields, "transliteration", number, path),
          tokens: tokens(fields, number, path),
          translation: fetch(fields, "translation", number, path),
          not_before: year(fields, "dateNotBefore", number, path),
          not_after: year(fields, "dateNotAfter", number, path),
          hieroglyphs: fields["hieroglyphs"],
          authors: fields["authors"]
        )
      end

      def parse_json(line, number, path)
        fields = JSON.parse(line)
        raise ParseError, "#{path}: line #{number}: not a JSON object" unless fields.is_a?(Hash)

        fields
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: line #{number}: malformed JSON — #{e.message}"
      end

      def fetch(fields, key, number, path)
        value = fields[key]
        return value if value.is_a?(String) && !value.empty?

        raise ParseError, "#{path}: line #{number}: missing or empty #{key.inspect}"
      end

      # The aligned four-way split. Upstream is censused at 0 misalignments
      # across both corpora, so a count mismatch is loud damage.
      def tokens(fields, number, path)
        forms = fetch(fields, "transliteration", number, path).split
        pairs = fetch(fields, "lemmatization", number, path).split
        upos = fetch(fields, "UPOS", number, path).split
        glosses = fetch(fields, "glossing", number, path).split
        unless [pairs.length, upos.length, glosses.length].all?(forms.length)
          raise ParseError, "#{path}: line #{number}: misaligned token fields " \
                            "(#{forms.length} forms / #{pairs.length} lemmata / " \
                            "#{upos.length} UPOS / #{glosses.length} glosses)"
        end

        forms.each_with_index.map do |form, index|
          lemma_id, lemma = split_lemma(pairs[index], number, path)
          Token.new(form: form, lemma_id: lemma_id, lemma: lemma,
                    upos: upos[index], gloss: glosses[index])
        end
      end

      def split_lemma(pair, number, path)
        match = LEMMA_PAIR.match(pair)
        raise ParseError, "#{path}: line #{number}: malformed lemma pair #{pair.inspect}" if match.nil?

        [match[1], match[2]]
      end

      # A signed historical year, or nil for upstream's empty string. Both
      # corpora are censused free of year 0 — DateAxis's tripwire would
      # surface one as damage (ParseError), never a silent skip.
      def year(fields, key, number, path)
        raw = fields[key]
        return nil if raw.nil? || raw.to_s.strip.empty?

        DateAxis.parse_year(raw) or
          raise ParseError, "#{path}: line #{number}: unparseable #{key} #{raw.inspect}"
      rescue DateAxis::InvalidYear => e
        raise ParseError, "#{path}: line #{number}: #{e.message}"
      end
    end
  end
end
