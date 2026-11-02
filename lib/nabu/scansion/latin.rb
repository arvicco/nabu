# frozen_string_literal: true

module Nabu
  module Scansion
    # The Latin syllabifier (P152). A line becomes a stream of vowel nuclei
    # and consonants (h is no consonant), elision drops the final vowel /
    # vowel+m before a vowel or h+vowel, and each surviving nucleus gets the
    # quantity the rules license (Scansion module note):
    #
    #   long   — a diphthong (ae au oe always; ui ei eu only in the closed
    #            word lists below, plus Eu+consonant opening a proper name:
    #            Europa, Eurus; never the Greek word-final -oe(s) of Troes,
    #            Cymothoe, nor aer), or position: two consonants after the
    #            vowel, x and z counting double, an intervocalic consonantal
    #            i counting double (Troia = Troi-ia, maior, eius);
    #   short  — a vowel directly before another vowel of its own word
    #            (vocalis ante vocalem corripitur; h between does not
    #            count), minus the closed exceptions (fio, -ius genitives,
    #            -ei of the fifth declension) and minus PROPER NAMES (a
    #            capitalized word past the line's first — mostly Greek,
    #            where the native rule does not hold: Aenēās, Lāïs);
    #   anceps — everything else: muta cum liquida inside a word (patris),
    #            a final vowel before an initial s+consonant or z, every
    #            open syllable, the line's last syllable.
    #
    # == The grammar-defaults tier (never a hard constraint)
    #
    # An anceps WORD-FINAL syllable additionally carries the textbook
    # final-syllable default (Allen & Greenough §§604-606): a vowel-final
    # monosyllable long; final -o, -i (bar mihi tibi sibi ibi ubi nisi
    # quasi), -u, -as, -es, -os long; final -e, -us and the closing
    # consonants -t, -r short; -a and -is (where the endings collide)
    # nothing. Defaults never make a template fail — Meters only consults
    # them to break a tie the hard rules and the metrical laws leave, and
    # such a scan says so (basis :defaults). Proper names get none.
    #
    # Consonantal i/u: j and v are consonants outright; in u/i-only editions
    # an initial i/u before a vowel, an intervocalic i/u, qu, ngu+vowel,
    # l/r + uu (seruus, paruus), the suad-/suav-/sues-/suet- stems and the
    # ad-/ab-/ob-/con-/in-/sub-/per-/dis- + i + vowel compounds (adiacet,
    # coniunx, periurus, disiectus). What the orthography hides (silua for silva) is a
    # known miss.
    module Latin
      VOWELS = "aeiouy"
      MUTES = %w[b c d g p t f].freeze
      LIQUIDS = %w[l r].freeze
      DIPHTHONGS = %w[ae au oe].freeze

      # Closed lists — never patterns that could over-reach.
      UI_WORDS = /\A(?:cui|huic|cuique|huicine)\z/
      EI_WORDS = /\A(?:dein|deinde|deinceps|proin|proinde|e?hei|ei)\z/
      EU_WORDS = /\A(?:e?heu|heus|seu|neu|ceu|neuter|neutr\w*|neutiquam)\z/
      CONSONANTAL_SU = /\Asu(?=a[dsv]|e[st])/
      PREFIX_I = /\A(?:ad|ab|ob|con|in|sub|per|dis)(?=i[aeou])/
      # Vowel-before-vowel exceptions: the vowel stays anceps, not short.
      LONG_BEFORE_VOWEL = /\A(?:fi(?!er)[aeou]\w*|
                              (?:ill|ist|ips|un|tot|sol|null|ull|alter|utr|neutr)ius|(?:di|r|fid|sp)ei)\z/x
      # Words whose initial i is a vowel despite the following vowel.
      VOCALIC_INITIAL_I = %w[io].freeze
      # Pairs that look like diphthongs but are hiatus: Greek -oe/-oes at
      # word end (Troes, heroes, Cymothoe), and aer (ἀήρ).
      HIATUS_OE = /oes?\z/
      HIATUS_WORDS = %w[aer].freeze
      # Interjections never elide (hiatus).
      NO_ELISION = %w[o heu io ei a ah].freeze

      # The grammar defaults (module note).
      SHORT_FINAL_I = %w[mihi tibi sibi ibi ubi nisi quasi].freeze
      SHORT_FINAL_O = %w[ego duo modo cito immo].freeze
      SHORT_MONOSYLLABLES = %w[et in ad ab ob sub per nec sed at an ut id is it quid quod quis vir].freeze
      LONG_MONOSYLLABLES = %w[non sic sol cur].freeze
      FINAL_DEFAULTS = {
        "o" => :long, "i" => :long, "u" => :long, "as" => :long, "es" => :long, "os" => :long,
        "e" => :short, "us" => :short
      }.freeze

      Unit = Struct.new(:kind, :text, :weight, :word, :diphthong, keyword_init: true)

      # One prepared word: its lowercased letters, and whether it is a
      # proper name (capitalized, past the line's first word).
      Word = Data.define(:text, :proper)

      module_function

      def syllables(text)
        words = words(text)
        raise Unscannable.new("no Latin letters", reason: :unreadable) if words.empty?

        streams = words.each_with_index.map { |word, i| units(word, i) }
        nuclei_per_word = streams.map { |units| units.count { |u| u.kind == :v } }
        elided = elide!(streams, words)
        assign(streams, words, elided, nuclei_per_word)
      end

      # Letter-only words (diaeresis kept as "¨"); a non-Latin letter
      # refuses the line.
      def words(text)
        decomposed = text.to_s.gsub("æ", "ae").gsub("œ", "oe").gsub("Æ", "Ae").gsub("Œ", "Oe")
                         .unicode_normalize(:nfd)
        raise Unscannable.new("non-Latin script in a Latin line", reason: :foreign_script) if
          decomposed.match?(/[^\p{Latin}\p{M}\p{P}\p{S}\p{N}\s]/)

        cleaned = decomposed.gsub("̈", "¨").gsub(/\p{M}/, "").gsub(/[^A-Za-z¨\s]/, " ")
        cleaned.split.each_with_index.map do |raw, i|
          Word.new(text: raw.downcase, proper: i.positive? && raw.match?(/\A[A-Z]/))
        end
      end

      # One word → its units. +index+ the word index.
      def units(word, index)
        plain = word.text.delete("¨")
        chars = plain.chars
        hiatus = hiatus_marks(word.text)
        vowel = classify(chars, plain)
        out = []
        i = 0
        while i < chars.size
          c = chars[i]
          if c == "h"
            i += 1
          elsif c == "q" && chars[i + 1] == "u"
            out << Unit.new(kind: :c, text: "qu", weight: 1, word: index)
            i += 2
          elsif vowel[i]
            if diphthong?(chars, i, word, vowel, hiatus)
              out << Unit.new(kind: :v, text: chars[i, 2].join, word: index, diphthong: true)
              i += 2
            else
              out << Unit.new(kind: :v, text: c, word: index, diphthong: false)
              i += 1
            end
          else
            out << Unit.new(kind: :c, text: c, weight: consonant_weight(chars, i, vowel), word: index)
            i += 1
          end
        end
        out
      end

      # Indices (in the diaeresis-free word) of vowels marked with ¨.
      def hiatus_marks(text)
        marks = []
        offset = 0
        text.chars.each_with_index do |c, i|
          next unless c == "¨"

          marks << (i - offset - 1)
          offset += 1
        end
        marks
      end

      # Per-char vowel? flags after the consonantal-i/u decisions.
      def classify(chars, plain)
        flags = chars.map { |c| VOWELS.include?(c) }
        chars.each_with_index do |c, i|
          next unless %w[i u].include?(c) && flags[i]

          # the u of qu is part of the consonant, never a nucleus
          flags[i] = false if (c == "u" && i.positive? && chars[i - 1] == "q") ||
                              consonantal?(chars, i, plain, flags)
        end
        flags
      end

      def consonantal?(chars, idx, plain, flags)
        nxt = chars[idx + 1]
        nxt_vowel = nxt && VOWELS.include?(nxt)
        prev = idx.positive? ? chars[idx - 1] : nil
        prev_vowel = prev && VOWELS.include?(prev) && flags[idx - 1]
        if chars[idx] == "u"
          return true if idx.zero? && nxt_vowel
          return true if prev == "g" && chars[idx - 2] == "n" && nxt_vowel
          return true if prev_vowel && nxt_vowel
          return true if LIQUIDS.include?(prev) && nxt == "u"
          return true if prev == "s" && CONSONANTAL_SU.match?(plain[(idx - 1)..])
        else
          return false if nxt == "i"
          return false if idx.zero? && VOCALIC_INITIAL_I.include?(plain)
          return true if idx.zero? && nxt_vowel
          return true if prev_vowel && nxt_vowel
          return true if nxt_vowel && (prefix = plain[PREFIX_I]) && idx == prefix.size
        end
        false
      end

      def diphthong?(chars, idx, word, vowel, hiatus)
        pair = chars[idx, 2].join
        return false unless vowel[idx + 1]
        return false if hiatus.include?(idx + 1)

        plain = word.text.delete("¨")
        return false if HIATUS_WORDS.include?(plain)
        return false if pair == "oe" && idx.positive? && HIATUS_OE.match?(plain[idx..])
        return true if DIPHTHONGS.include?(pair)
        return true if pair == "ui" && UI_WORDS.match?(plain) && chars[idx - 1] != "q"
        return true if pair == "ei" && EI_WORDS.match?(plain)
        return true if pair == "eu" && EU_WORDS.match?(plain)
        return true if pair == "eu" && idx.zero? && word.proper && chars[2] && !VOWELS.include?(chars[2])

        false
      end

      # x and z are double; an intervocalic consonantal i is double too.
      def consonant_weight(chars, idx, vowel)
        c = chars[idx]
        return 2 if %w[x z].include?(c)
        return 2 if c == "i" && idx.positive? && vowel[idx - 1] && vowel[idx + 1]

        1
      end

      # Elide the final vowel (or vowel+m) of a word before a word that
      # opens on a vowel (h already dropped). Returns the indices of the
      # words that lost their ending.
      def elide!(streams, words)
        elided = {}
        streams.each_with_index do |units, i|
          nxt = streams[i + 1]
          next if nxt.nil? || nxt.empty? || units.empty?
          next unless nxt.first.kind == :v
          next if NO_ELISION.include?(words[i].text)

          if units.last.kind == :v
            units.pop
          elsif units.last.text == "m" && units.size >= 2 && units[-2].kind == :v
            units.pop(2)
          else
            next
          end
          elided[i] = true
        end
        elided
      end

      # Assign quantities (and the grammar defaults) over the flat stream.
      def assign(streams, words, elided, nuclei_per_word)
        stream = streams.flatten
        nuclei = stream.each_index.select { |i| stream[i].kind == :v }
        raise Unscannable.new("no syllables", reason: :unreadable) if nuclei.empty?

        last_in_word = nuclei.group_by { |i| stream[i].word }.transform_values(&:last)
        texts = Scansion.syllable_texts(stream, nuclei)
        seen = {}
        nuclei.each_with_index.map do |pos, k|
          unit = stream[pos]
          following = k + 1 < nuclei.size ? stream[(pos + 1)...nuclei[k + 1]] : nil
          quantity = quantity(unit, following, words, stream, nuclei[k + 1])
          final = last_in_word[unit.word] == pos
          default = if quantity == :anceps && final && following && !elided[unit.word]
                      default_for(words[unit.word], streams[unit.word], nuclei_per_word[unit.word])
                    end
          before = elided[unit.word - 1] && !seen[unit.word]
          seen[unit.word] = true
          Syllable.new(text: texts[k], quantity: quantity, word: unit.word, word_final: final,
                       elided_before: before ? true : false, default: default)
        end
      end

      def quantity(unit, following, words, stream, next_pos)
        return :anceps if following.nil? # the line's last syllable
        return :long if unit.diphthong
        return position(unit, following) if following.sum(&:weight) >= 2

        if following.empty? && stream[next_pos].word == unit.word
          word = words[unit.word]
          return word.proper || LONG_BEFORE_VOWEL.match?(word.text) ? :anceps : :short
        end

        :anceps
      end

      # Two or more consonants after the vowel: long, unless the cluster is
      # muta cum liquida inside one word, or a word-final vowel meets an
      # initial s+consonant / z (common syllables).
      def position(unit, following)
        if following.size == 2 && following.map(&:word).uniq.size == 1 &&
           MUTES.include?(following[0].text) && LIQUIDS.include?(following[1].text)
          return :anceps
        end

        word_final_vowel = following.none? { |c| c.word == unit.word }
        if word_final_vowel
          first = following[0].text
          return :anceps if first == "z" || (first == "s" && following.size >= 2)
        end
        :long
      end

      # The textbook final-syllable default for an unelided word (module
      # note), or nil.
      def default_for(word, units, nuclei)
        return nil if word.proper

        text = word.text.delete("¨")
        if nuclei == 1
          return :short if SHORT_MONOSYLLABLES.include?(text)
          return :long if LONG_MONOSYLLABLES.include?(text) || units.last.kind == :v

          return nil
        end
        last_vowel = units.rindex { |u| u.kind == :v }
        ending = units[last_vowel..].map(&:text).join
        return nil if ending == "i" && SHORT_FINAL_I.include?(text)
        return nil if ending == "o" && SHORT_FINAL_O.include?(text)
        return :short if ending.match?(/\A[aeiou][tr]\z/)

        FINAL_DEFAULTS[ending]
      end
    end
  end
end
