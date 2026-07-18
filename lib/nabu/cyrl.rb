# frozen_string_literal: true

module Nabu
  # Cyrillic ↔ scholarly-Latin transliteration (P27-2). One table, two uses:
  #
  #   - Cyrl.to_translit    — `--display translit` rendering for the Cyrillic
  #                           shelves (case-aware, marks preserved, Latin text
  #                           untouched — render-only honesty).
  #   - Cyrl.neutralize     — the chu/orv/bul SEARCH-side script neutralization
  #                           (Normalize::SCRIPT_NEUTRALIZATIONS): both the
  #                           Latin-diplomatic and the Cyrillic spelling of a
  #                           Slavic word fold to ONE skeleton, applied
  #                           symmetrically at index and query time.
  #
  # == Census-first (2026-07-18, fixture bytes, not assumptions)
  #
  # The LATIN side of the table is damaskini's own ingested diplomatic layer
  # (conllu FORM/lemma columns): š ž č ě ę ź, x for х ("xodinie", "xva"),
  # literal jers ъ/ь, "št" for щ ("šte"), j-iotation ("ljubovъ"), "ou" for оу
  # ("oubi" = оуби — upstream's own lemma column folds it to "ubija"), and
  # literal Cyrillic residues (ѯ ѳ ћ џ ꙫ) for sounds without Latin letters.
  # The CYRILLIC side is the TOROT + UD-orv + wiktionary-cu inventory
  # (ѣ ѧ ѫ ѩ ѭ ѥ ꙗ ꙇ ꙑ ꙋ ѿ ѡ ѵ ѕ й я ю …).
  #
  # == The widenings (ambiguity → ONE skeleton, never a guess)
  #
  #   щ ≡ шт ≡ "št"   — щ expands to the digraph both spellings share.
  #   оу ≡ у ≡ ou ≡ u — the u-digraphs collapse (veles "oubi"/"ouboja",
  #                     upstream lemmas "ubija"/"uboja"); a genuine o+u hiatus
  #                     (по-учение) conflates IDENTICALLY on both sides, so
  #                     the fold stays symmetric.
  #   ю/ꙗ/я/ѥ/ѩ/ѭ/й → ju/ja/je/ję/jǫ/j — iotation spelled with j, the
  #                     skeleton damaskini itself writes ("ljubovъ").
  #   ѵ → v           — damaskini's own diplomatic renders izhitsa v
  #                     (Параскеѵи → Paraskevi); the i-reading is context the
  #                     fold cannot recover, journaled, not guessed.
  #
  # == Deliberate NON-rules (evidence said no)
  #
  #   ѳ/ћ/џ/ꙫ  — BOTH layers carry the literal character (damaskini keeps
  #              them in Latin text), so identity already crosses the scripts;
  #              mapping ѳ→f or →th would guess between two readings.
  #   ʼ/ʹ/ʺ    — no apostrophe-jer in any INGESTED surface (the "kól'koto"
  #              convention lives only in the non-ingested accented TSV
  #              column); ъ and ь stay distinct skeleton letters.
  #   х → x only — the ISO h/ch spellings are not widened (h is a real Latin
  #              letter in the corpus); x is the corpus's own convention.
  #   Glagolitic — no neutralization (wiktionary-cu carries Glagolitic only as
  #              headword variants); the zero-hit script hint names it.
  module Cyrl
    # Lowercase Cyrillic letter → scholarly-Latin value. Multi-char values are
    # real digraphs both spellings share (št, ju, dz, ot…). Letters absent
    # here (ѳ ћ џ ꙫ …) pass through as their own cross-script skeleton.
    TRANSLIT = {
      "а" => "a", "б" => "b", "в" => "v", "г" => "g", "д" => "d", "е" => "e",
      "ж" => "ž", "з" => "z", "и" => "i", "і" => "i", "к" => "k", "л" => "l",
      "м" => "m", "н" => "n", "о" => "o", "п" => "p", "р" => "r", "с" => "s",
      "т" => "t", "у" => "u", "ф" => "f", "х" => "x", "ц" => "c", "ч" => "č",
      "ш" => "š", "щ" => "št", "ъ" => "ъ", "ы" => "y", "ь" => "ь", "ѣ" => "ě",
      "ю" => "ju", "я" => "ja", "й" => "j", "є" => "e", "ѕ" => "dz",
      "ѡ" => "o", "ѿ" => "ot", "ѧ" => "ę", "ѩ" => "ję", "ѫ" => "ǫ",
      "ѭ" => "jǫ", "ѥ" => "je", "ѯ" => "ks", "ѱ" => "ps", "ѵ" => "v",
      "ѻ" => "o", "ѹ" => "u", "ꙁ" => "z", "ꙃ" => "dz", "ꙇ" => "i",
      "ꙋ" => "u", "ꙑ" => "y", "ꙗ" => "ja"
    }.freeze

    # The two-character u-digraphs the SEARCH skeleton collapses to "u" (see
    # the widenings above); display collapses only the Cyrillic one — it
    # never rewrites Latin the source wrote.
    U_DIGRAPHS = %w[оу ou].freeze
    CYRILLIC_U_DIGRAPHS = %w[оу].freeze

    module_function

    # Search-side neutralization with a character-index map (the KWIC
    # contract): returns [skeleton, map] where map[i] is the index, into
    # +str+'s characters, of the character that produced skeleton[i].
    # Digraph collapses (оу/ou → u) attribute to the digraph's first char;
    # expansions (щ → št) attribute every output char to the source char.
    # Input is expected lowercase (Normalize downcases before neutralizing).
    def neutralize_with_map(str)
      out = +""
      map = []
      chars = str.each_char.to_a
      i = 0
      while i < chars.length
        if U_DIGRAPHS.include?(chars[i, 2].join)
          out << "u"
          map << i
          i += 2
          next
        end
        neutral_piece(chars[i]).each_char do |produced|
          out << produced
          map << i
        end
        i += 1
      end
      [out, map]
    end

    # The search skeleton alone (neutralize_with_map's first element).
    def neutralize(str)
      neutralize_with_map(str).first
    end

    # Display transliteration: Cyrillic renders scholarly Latin (case-aware,
    # Щ → Št), the Cyrillic оу digraph renders u, and EVERYTHING the source
    # wrote in Latin stays byte-identical — the display layer never rewrites
    # the source's own surface (no ou→u, no jer conflation).
    def to_translit(text)
      out = +""
      chars = text.each_char.to_a
      i = 0
      while i < chars.length
        pair = chars[i, 2].join
        if CYRILLIC_U_DIGRAPHS.include?(pair.downcase)
          out << (pair == pair.downcase ? "u" : "U")
          i += 2
          next
        end
        out << translit_char(chars[i])
        i += 1
      end
      out
    end

    # One lowercase char → its skeleton piece: table first; an unlisted
    # precomposed Cyrillic letter decomposes so its BASE maps and its marks
    # ride through (torot's ӑ → a + breve; the generic fold strips marks
    # later); anything else passes through untouched.
    def neutral_piece(char)
      TRANSLIT.fetch(char) do
        decomposed = char.unicode_normalize(:nfd)
        if decomposed.length > 1 && TRANSLIT.key?(decomposed[0])
          TRANSLIT.fetch(decomposed[0]) + decomposed[1..]
        else
          char
        end
      end
    end
    private_class_method :neutral_piece

    # One char for display: lowercase maps straight; an uppercase Cyrillic
    # letter maps via its lowercase and re-capitalizes (Щ → Št). Uppercase
    # that maps to itself (Latin, unlisted residues) keeps its case.
    def translit_char(char)
      lower = char.downcase
      return neutral_piece(lower) if char == lower

      mapped = neutral_piece(lower)
      mapped == lower ? char : mapped.capitalize
    end
    private_class_method :translit_char
  end
end
