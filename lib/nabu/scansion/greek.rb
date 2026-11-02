# frozen_string_literal: true

module Nabu
  module Scansion
    # The Greek syllabifier (P152). The polytonic text carries more of the
    # answer than Latin does, and the rules read only what it carries:
    #
    #   nature — η ω and every diphthong (αι ει οι υι αυ ευ ηυ ου ωυ, a
    #            diaeresis or a mark on the first vowel splitting the pair)
    #            long; ε ο short; a dichronon (α ι υ) long under a
    #            circumflex, an iota subscript or a macron, short under a
    #            breve, and otherwise decided only by the ACCENT LAWS of a
    #            word bearing exactly one accent, unelided:
    #              acute on the antepenult  ⇒ the final vowel is short;
    #              circumflex on the penult ⇒ the final vowel is short;
    #              acute on a long penult   ⇒ the final vowel is long;
    #              acute on the penult, final short ⇒ the penult is short;
    #            final -αι/-οι counting short for the accent, as they do.
    #            Anything else stays anceps.
    #   position — two consonants after the vowel, ζ ξ ψ double; muta cum
    #            liquida (a stop + λ ρ μ ν within one word, or opening the
    #            next word after a final vowel) anceps.
    #   correption — a long vowel or diphthong ending a word before a
    #            vowel (epic correption), or a diphthong before a vowel
    #            inside its word, is anceps.
    #
    # Elision is written (ἄρʼ, δʼ): the apostrophe ends the word on its
    # consonant, which becomes the next word's onset. Breathings are no
    # consonant. Synizesis (θεοί, -εω), digamma, and metrical lengthening
    # are invisible to the rules — the known misses.
    module Greek
      ACUTE = "\u0301"
      GRAVE = "\u0300"
      CIRCUMFLEX = "\u0342"
      SMOOTH = "\u0313"
      ROUGH = "\u0314"
      DIAERESIS = "\u0308"
      IOTA_SUB = "\u0345"
      MACRON = "\u0304"
      BREVE = "\u0306"

      VOWELS = "αεηιουω"
      DICHRONA = "αιυ"
      DIPHTHONGS = %w[αι ει οι υι αυ ευ ηυ ου ωυ].freeze
      STOPS = "πβφτδθκγχ"
      LIQUIDS = "λρμν"
      DOUBLE = "ζξψ"
      APOSTROPHES = /[ʼ’'᾽᾿]/

      Unit = Struct.new(:kind, :text, :weight, :word, :diphthong, :nature, :marks, keyword_init: true)

      module_function

      def syllables(text)
        words = words(text)
        raise Unscannable.new("no Greek letters", reason: :unreadable) if words.empty?

        streams = words.each_with_index.map { |(word, elided), i| units(word, i, elided: elided) }
        assign(streams)
      end

      # [letters, elided?] per word, lowercased NFD, punctuation stripped.
      def words(text)
        decomposed = text.to_s.unicode_normalize(:nfd).downcase.gsub(APOSTROPHES, "' ")
        raise Unscannable.new("non-Greek script in a Greek line", reason: :foreign_script) if
          decomposed.match?(/[^\p{Greek}\p{M}\p{P}\p{S}\p{N}\s']/) || decomposed.match?(/[a-z]/)

        decomposed.split.filter_map do |raw|
          elided = raw.end_with?("'")
          word = raw.gsub(/[^\p{Greek}\p{M}]/, "").tr("ς", "σ")
          next if word.gsub(/\p{M}/, "").empty?

          [word, elided]
        end
      end

      # One word → units, then the accent laws over its nuclei.
      def units(word, index, elided:)
        letters = letters(word)
        out = []
        i = 0
        while i < letters.size
          base, marks = letters[i]
          if VOWELS.include?(base)
            nxt = letters[i + 1]
            if nxt && diphthong?(base, marks, *nxt)
              out << Unit.new(kind: :v, text: base + nxt[0], word: index, diphthong: true, nature: :long,
                              marks: marks + nxt[1])
              i += 2
              next
            end
            out << Unit.new(kind: :v, text: base, word: index, diphthong: false, nature: nature(base, marks),
                            marks: marks)
          else
            out << Unit.new(kind: :c, text: base, weight: DOUBLE.include?(base) ? 2 : 1, word: index)
          end
          i += 1
        end
        accent_laws!(out) unless elided
        out
      end

      # [[base, marks-string], …] — each base letter with its combining marks.
      def letters(word)
        word.chars.each_with_object([]) do |c, acc|
          if c.match?(/\p{M}/)
            acc.last[1] += c unless acc.empty?
          else
            acc << [c, +""]
          end
        end
      end

      def diphthong?(base, marks, next_base, next_marks)
        return false unless DIPHTHONGS.include?(base + next_base)
        return false if next_marks.include?(DIAERESIS)
        # a breathing / accent / subscript on the FIRST vowel means two
        # syllables (the marks of a diphthong sit on its second vowel)
        return false if [ACUTE, GRAVE, CIRCUMFLEX, SMOOTH, ROUGH, IOTA_SUB].any? { |m| marks.include?(m) }

        true
      end

      def nature(base, marks)
        return :long if "ηω".include?(base)
        return :short if "εο".include?(base)
        return :long if [CIRCUMFLEX, IOTA_SUB, MACRON].any? { |m| marks.include?(m) }
        return :short if marks.include?(BREVE)

        nil
      end

      # The accent laws (module note), only for a word with exactly one
      # accented nucleus and at least two nuclei; they only ever fill a
      # dichronon whose nature is still unknown.
      def accent_laws!(units)
        nuclei = units.select { |u| u.kind == :v }
        accented = nuclei.each_index.select { |i| accent(nuclei[i]) }
        return unless nuclei.size >= 2 && accented.size == 1

        final = nuclei[-1]
        penult = nuclei[-2]
        from_end = nuclei.size - 1 - accented.first
        mark = accent(nuclei[accented.first])
        final_short = short_for_accent?(final, ends_word: units.last.equal?(final))
        case [from_end, mark]
        in [2, ACUTE] | [1, CIRCUMFLEX] then fill(final, :short)
        in [1, ACUTE]
          fill(final, :long) if penult.nature == :long
          fill(penult, :short) if final_short
        else nil
        end
      end

      def accent(unit)
        return ACUTE if unit.marks.include?(ACUTE)
        return CIRCUMFLEX if unit.marks.include?(CIRCUMFLEX)

        nil
      end

      def short_for_accent?(unit, ends_word:)
        return true if unit.nature == :short && !unit.diphthong
        return true if unit.diphthong && %w[αι οι].include?(unit.text) && ends_word

        false
      end

      def fill(unit, nature)
        unit.nature ||= nature if !unit.diphthong && DICHRONA.include?(unit.text)
      end

      def assign(streams)
        stream = streams.flatten
        nuclei = stream.each_index.select { |i| stream[i].kind == :v }
        raise Unscannable.new("no syllables", reason: :unreadable) if nuclei.empty?

        last_in_word = nuclei.group_by { |i| stream[i].word }.transform_values(&:last)
        texts = Scansion.syllable_texts(stream, nuclei)
        nuclei.each_with_index.map do |pos, k|
          unit = stream[pos]
          following = k + 1 < nuclei.size ? stream[(pos + 1)...nuclei[k + 1]] : nil
          quantity = following.nil? ? :anceps : quantity(unit, following, stream[nuclei[k + 1]])
          Syllable.new(text: texts[k], quantity: quantity, word: unit.word,
                       word_final: last_in_word[unit.word] == pos, elided_before: false)
        end
      end

      def quantity(unit, following, next_nucleus)
        if following.sum(&:weight) >= 2
          return :long if unit.nature == :long

          return position(following)
        end
        return unit.nature || :anceps unless unit.nature == :long && following.empty?

        # a long before a vowel: epic correption across words, internal
        # correption of a diphthong inside its word
        return :anceps if next_nucleus.word != unit.word || unit.diphthong

        :long
      end

      # Muta cum liquida in one word (whether the vowel's own or the next
      # word's onset after a final vowel) is common; anything else long.
      def position(following)
        if following.size == 2 && following.map(&:word).uniq.size == 1 &&
           STOPS.include?(following[0].text) && LIQUIDS.include?(following[1].text)
          return :anceps
        end

        :long
      end
    end
  end
end
