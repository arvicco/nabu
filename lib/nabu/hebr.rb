# frozen_string_literal: true

module Nabu
  # Pointed Hebrew/Aramaic → SBL-style romanization (P27-2), for
  # `--display translit` on the hbo/arc shelves. RENDER-ONLY: search folding
  # never passes through here (Hebrew search folds script-internally — the
  # index and the query are both Hebrew script).
  #
  # Census-scoped like Deva: the inventory is exactly the codepoint census of
  # the OSHB fixtures (letters U+05D0–05EA; points U+05B0–05BC, 05C1/05C2;
  # meteg 05BD; maqaf 05BE; paseq 05C0; sof pasuq 05C3; cantillation
  # U+0591–05AF) plus qamats qatan U+05C7 (in the corpus at large; part of
  # the display "points" class). Anything else passes through unchanged.
  #
  # == Style (journaled choices, P27-2)
  #
  # SBL "general-purpose" base with the academic letters kept where
  # general-purpose would MERGE distinct Hebrew letters: ʾ/ʿ (alef/ayin),
  # ḥ (khet, vs kh spirant kaf), ṭ (tet, vs tav t), ś (sin, vs samek s).
  # Choices general-purpose forces are taken as-is: begadkefat plosive/spirant
  # split only where it is audible in the style (b/v, k/kh, p/f — g/d/t do
  # not split); dagesh forte is NOT doubled; vocal-vs-silent shewa is not
  # inferred — every shewa renders ə; matres lectionis render as consonants
  # (bəreʾshiyt, not bereshit) — a per-codepoint transcoder, not a
  # vocalization engine. Cantillation and meteg leave no residue; maqaf → "-",
  # sof pasuq → ".", paseq → "|". Shuruq (vav + dagesh, no vowel) → u;
  # holam male (vav + holam alone) → o.
  #
  # The OSHB bytes are NFC-EXEMPT (Masoretic mark order, architecture §3):
  # the transcoder reads each consonant's whole mark CLUSTER before deciding
  # (dagesh/dots first, vowels in written order), so it never depends on the
  # order upstream chose.
  module Hebr
    # Consonant → [plain, with_dagesh]; single-value letters repeat.
    CONSONANTS = {
      "א" => %w[ʾ ʾ], "ב" => %w[v b], "ג" => %w[g g], "ד" => %w[d d],
      "ה" => %w[h h], "ו" => %w[w w], "ז" => %w[z z], "ח" => %w[ḥ ḥ],
      "ט" => %w[ṭ ṭ], "י" => %w[y y], "כ" => %w[kh k], "ך" => %w[kh k],
      "ל" => %w[l l], "מ" => %w[m m], "ם" => %w[m m], "נ" => %w[n n],
      "ן" => %w[n n], "ס" => %w[s s], "ע" => %w[ʿ ʿ], "פ" => %w[f p],
      "ף" => %w[f p], "צ" => %w[ts ts], "ץ" => %w[ts ts], "ק" => %w[q q],
      "ר" => %w[r r], "ש" => %w[sh sh], "ת" => %w[t t]
    }.freeze

    # Vowel point → value (shewa renders ə — vocal/silent is not inferred).
    VOWELS = {
      0x05B0 => "ə", 0x05B1 => "e", 0x05B2 => "a", 0x05B3 => "o",
      0x05B4 => "i", 0x05B5 => "e", 0x05B6 => "e", 0x05B7 => "a",
      0x05B8 => "a", 0x05B9 => "o", 0x05BB => "u", 0x05C7 => "o"
    }.freeze

    # Marks that read as part of the preceding consonant's cluster.
    DAGESH = 0x05BC
    SHIN_DOT = 0x05C1
    SIN_DOT = 0x05C2
    CANTILLATION = (0x0591..0x05AF)
    METEG = 0x05BD
    CLUSTER_MARKS = [CANTILLATION, DAGESH, SHIN_DOT, SIN_DOT, METEG, *VOWELS.keys].freeze

    # Standalone punctuation with a fixed value.
    PUNCTUATION = { 0x05BE => "-", 0x05C0 => "|", 0x05C3 => "." }.freeze

    module_function

    # Romanize +text+. Hebrew consonants are read with their whole following
    # mark cluster; everything outside the inventory passes through.
    def to_sbl(text)
      transcode(text.to_s.each_char.to_a)
    end

    def transcode(chars)
      out = +""
      i = 0
      while i < chars.length
        char = chars[i]
        unless CONSONANTS.key?(char)
          out << standalone(char)
          i += 1
          next
        end
        cluster = []
        cluster << chars[i + 1 + cluster.length] while cluster_mark?(chars[i + 1 + cluster.length])
        out << emit(char, cluster)
        i += 1 + cluster.length
      end
      out
    end
    private_class_method :transcode

    def cluster_mark?(char)
      return false if char.nil?

      ord = char.ord
      CLUSTER_MARKS.any? { |mark| mark.is_a?(Range) ? mark.cover?(ord) : mark == ord }
    end
    private_class_method :cluster_mark?

    def standalone(char)
      PUNCTUATION[char.ord] || VOWELS[char.ord] ||
        (cluster_mark?(char) ? "" : char)
    end
    private_class_method :standalone

    # One consonant + its mark cluster → romanized syllable piece.
    def emit(consonant, cluster)
      ords = cluster.map(&:ord)
      dagesh = ords.include?(DAGESH)
      vowels = ords.filter_map { |ord| VOWELS[ord] }
      return "u" if consonant == "ו" && dagesh && vowels.empty?
      return "o" if consonant == "ו" && !dagesh && vowels == ["o"]

      consonant_value(consonant, dagesh: dagesh, ords: ords) + vowels.join
    end
    private_class_method :emit

    def consonant_value(consonant, dagesh:, ords:)
      return ords.include?(SIN_DOT) ? "ś" : "sh" if consonant == "ש"

      CONSONANTS.fetch(consonant)[dagesh ? 1 : 0]
    end
    private_class_method :consonant_value
  end
end
