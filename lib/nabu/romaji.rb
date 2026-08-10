# frozen_string_literal: true

module Nabu
  # Hepburn-ish romaji → hiragana (P65 gate feedback): the reading lane
  # accepts on/kun readings typed WITHOUT a kana input method — `nabu char
  # TAI` (CAPS = on'yomi, the dictionary convention) and `nabu char hito`
  # (lowercase = kun'yomi). Kunrei spellings (syou, tya) fold too; macron
  # long vowels read as their kana spellings (kō → こう). Anything the
  # table cannot parse answers nil — the lane finds nothing, never guesses.
  # wi/we are deliberately OUT: their absence keeps pinyin syllables (wen)
  # from converting.
  module Romaji
    DIGRAPHS = {
      "kya" => "きゃ", "kyu" => "きゅ", "kyo" => "きょ",
      "gya" => "ぎゃ", "gyu" => "ぎゅ", "gyo" => "ぎょ",
      "sha" => "しゃ", "shu" => "しゅ", "sho" => "しょ",
      "sya" => "しゃ", "syu" => "しゅ", "syo" => "しょ",
      "cha" => "ちゃ", "chu" => "ちゅ", "cho" => "ちょ",
      "tya" => "ちゃ", "tyu" => "ちゅ", "tyo" => "ちょ",
      "nya" => "にゃ", "nyu" => "にゅ", "nyo" => "にょ",
      "hya" => "ひゃ", "hyu" => "ひゅ", "hyo" => "ひょ",
      "bya" => "びゃ", "byu" => "びゅ", "byo" => "びょ",
      "pya" => "ぴゃ", "pyu" => "ぴゅ", "pyo" => "ぴょ",
      "mya" => "みゃ", "myu" => "みゅ", "myo" => "みょ",
      "rya" => "りゃ", "ryu" => "りゅ", "ryo" => "りょ",
      "jya" => "じゃ", "jyu" => "じゅ", "jyo" => "じょ",
      "zya" => "じゃ", "zyu" => "じゅ", "zyo" => "じょ",
      "shi" => "し", "chi" => "ち", "tsu" => "つ",
      "ja" => "じゃ", "ju" => "じゅ", "jo" => "じょ", "ji" => "じ",
      "fu" => "ふ"
    }.freeze

    BASE = {
      "a" => "あ", "i" => "い", "u" => "う", "e" => "え", "o" => "お",
      "ka" => "か", "ki" => "き", "ku" => "く", "ke" => "け", "ko" => "こ",
      "ga" => "が", "gi" => "ぎ", "gu" => "ぐ", "ge" => "げ", "go" => "ご",
      "sa" => "さ", "si" => "し", "su" => "す", "se" => "せ", "so" => "そ",
      "za" => "ざ", "zi" => "じ", "zu" => "ず", "ze" => "ぜ", "zo" => "ぞ",
      "ta" => "た", "ti" => "ち", "tu" => "つ", "te" => "て", "to" => "と",
      "da" => "だ", "di" => "ぢ", "du" => "づ", "de" => "で", "do" => "ど",
      "na" => "な", "ni" => "に", "nu" => "ぬ", "ne" => "ね", "no" => "の",
      "ha" => "は", "hi" => "ひ", "hu" => "ふ", "he" => "へ", "ho" => "ほ",
      "ba" => "ば", "bi" => "び", "bu" => "ぶ", "be" => "べ", "bo" => "ぼ",
      "pa" => "ぱ", "pi" => "ぴ", "pu" => "ぷ", "pe" => "ぺ", "po" => "ぽ",
      "ma" => "ま", "mi" => "み", "mu" => "む", "me" => "め", "mo" => "も",
      "ya" => "や", "yu" => "ゆ", "yo" => "よ",
      "ra" => "ら", "ri" => "り", "ru" => "る", "re" => "れ", "ro" => "ろ",
      "wa" => "わ", "wo" => "を"
    }.freeze

    MACRONS = { "ā" => "aa", "ī" => "ii", "ū" => "uu", "ē" => "ee", "ō" => "ou" }.freeze

    SOKUON_CONSONANTS = "kstpgzdbc"

    def self.to_hiragana(input)
      text = input.to_s.downcase.gsub(/[āīūēō]/, MACRONS)
      return nil if text.empty? || text.match?(/[^a-z']/)

      out = +""
      until text.empty?
        chunk, kana = next_kana(text)
        return nil unless kana

        out << kana
        text = text[chunk..]
      end
      out
    end

    # One leading mora: [consumed length, kana] — moraic ん (n before a
    # non-vowel, n' explicitly, or final n), sokuon っ (a doubled
    # consonant), then the longest table match. [0, nil] = unparseable.
    def self.next_kana(text)
      if text[0] == "n" && (text.size == 1 || !"aiueoy".include?(text[1]))
        return [text[1] == "'" ? 2 : 1, "ん"]
      end
      return [1, "っ"] if text[0] == text[1] && SOKUON_CONSONANTS.include?(text[0])

      [3, 2, 1].each do |length|
        next if text.size < length

        kana = DIGRAPHS[text[0, length]] || BASE[text[0, length]]
        return [length, kana] if kana
      end
      [0, nil]
    end
  end
end
