# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # The Arabic root crosswalk: one comparison key for a consonantal root
  # however a source writes it — Lane's Lexicon heads in Arabic script
  # (كتب, some vocalized أَكَرَ, geminates as ربّ or رب), the Quranic Arabic
  # Corpus's ROOT in Buckwalter ASCII (rHm, Amn, Elm, rbb), Corpus
  # Coranicum's root in DMG-style Latin (rḥm, ʾmn, ʿlm, ǧʿl). Pure: no
  # catalog, no IO. Store::EntryFacetBuilder projects the dictionary
  # side's keys (the root_key / root_loose_key entry facets), and
  # Query::RootLink folds a token's root the SAME way and probes them.
  #
  # == Transliteration (one-to-one tables)
  #
  # BUCKWALTER is Tim Buckwalter's standard table — every letter and
  # every vowel/shadda/sukun sign, one ASCII character per Arabic code
  # point. QAC's extended Quranic annotation marks (small high/low signs)
  # never occur in a root and are deliberately absent. DMG covers the 28
  # consonants of the DMG/ISO 233-style transliteration Corpus Coranicum
  # uses (ʾ ʿ ṯ ǧ ḥ ḫ ḏ š ṣ ḍ ṭ ẓ ġ beside the plain letters); vowels are
  # not radicals and are absent on purpose. A character a table does not
  # map makes the whole root a clean miss (nil) — never a guessed letter.
  #
  # == The comparison key — three named rules, applied IDENTICALLY to both sides
  #
  # Rule 1 (orthography): +strip_vowels+ drops harakat, tanwin, sukun,
  # superscript alif and tatweel; +fold_seats+ folds every hamza seat and
  # alif (ء أ إ آ ؤ ئ ٱ ا) to ء, and alif maqsura ى to ي (Lane writes a
  # y-final root كفى, QAC kfy).
  # Rule 2 (gemination): +expand_shadda+ writes a shadda as its doubled
  # letter, then +collapse_geminate+ collapses a doubled FINAL radical —
  # QAC rbb, Lane ربّ and رب all key رب.
  # Rule 3 (weak radicals): +fold_weak+ lets و ي ء interchange (one class,
  # written ء) — QAC dwr vs Lane's دير, wjl vs اجل.
  # Rule 4 (reduplication): +collapse_reduplication+ folds a reduplicated
  # quadriliteral C1C2C1C2 to its biliteral C1C2 — Lane files زلزل under
  # زل, وسوس under وس, صلصل under صل.
  #
  # Rules 3 and 4 over-merge by design (قول and قيل, نسأ and نسو are
  # separate Lane articles), so they form a FALLBACK TIER: the strict key
  # (rules 1–2) is tried first, and the loose key (rules 1–4) answers only
  # a strict miss — a lookup says which tier answered.
  #
  # Known mismatch classes (live census 2026-11-27 — Lane's 5,087 root
  # headings against QAC's 1,642 and Corpus Coranicum's 1,697 roots):
  # - vocalized heads (أَكَرَ, جَهِلَ), hamza on alif (أمن vs QAC Amn),
  #   alif maqsura (كفى vs kfy) — rule 1;
  # - geminates (رب/ربّ vs rbb, مدّ vs mdd; حيى vs Hyy needs 1+2) — rule 2;
  # - a w↔y↔hamza disagreement between Lane's head and the corpus's
  #   analysis (dwr ↔ دير, Amw ↔ اما/ومأ) — rule 3, loose tier;
  # - reduplicated quadriliterals (zlzl, wsws, SlSl, rfrf, hdhd …) —
  #   rule 4, loose tier;
  # - roots the digitized Lane lacks (QAC dbr, jHm, jHd, Hrv, gwy, nzg —
  #   absent from its 5,087 headings) or files under another radical set
  #   (Corpus Coranicum's ṭmʾn — Lane طمن; its biliteral analyses ḏ, m,
  #   ll) — no rule; honest misses;
  # - non-root analyses upstream (Corpus Coranicum's pronoun "roots" hu,
  #   kum, its vowel-bearing ʾūl/ʾumm and the literal "ḥelpinġVowel") —
  #   unmapped characters, clean misses by construction.
  #
  # Lane heads: a heading that lists several UNVOCALIZED roots
  # (كتع كتف كتل كتم كتن — Lane's run of minor roots) yields one key per
  # root; a vocalized heading with a space (مَشَقَ الخَطَّ, a phrase) stays
  # one head.
  module ArabicRoots
    BUCKWALTER = {
      "'" => "ء", "|" => "آ", ">" => "أ", "&" => "ؤ", "<" => "إ",
      "}" => "ئ", "A" => "ا", "b" => "ب", "p" => "ة", "t" => "ت",
      "v" => "ث", "j" => "ج", "H" => "ح", "x" => "خ", "d" => "د",
      "*" => "ذ", "r" => "ر", "z" => "ز", "s" => "س", "$" => "ش",
      "S" => "ص", "D" => "ض", "T" => "ط", "Z" => "ظ", "E" => "ع",
      "g" => "غ", "_" => "ـ", "f" => "ف", "q" => "ق", "k" => "ك",
      "l" => "ل", "m" => "م", "n" => "ن", "h" => "ه", "w" => "و",
      "Y" => "ى", "y" => "ي", "F" => "ً", "N" => "ٌ", "K" => "ٍ",
      "a" => "َ", "u" => "ُ", "i" => "ِ", "~" => "ّ", "o" => "ْ",
      "`" => "ٰ", "{" => "ٱ"
    }.freeze

    DMG = {
      "ʾ" => "ء", "b" => "ب", "t" => "ت", "ṯ" => "ث", "ǧ" => "ج",
      "ḥ" => "ح", "ḫ" => "خ", "d" => "د", "ḏ" => "ذ", "r" => "ر",
      "z" => "ز", "s" => "س", "š" => "ش", "ṣ" => "ص", "ḍ" => "ض",
      "ṭ" => "ط", "ẓ" => "ظ", "ʿ" => "ع", "ġ" => "غ", "f" => "ف",
      "q" => "ق", "k" => "ك", "l" => "ل", "m" => "م", "n" => "ن",
      "h" => "ه", "w" => "و", "y" => "ي"
    }.freeze

    TABLES = { buckwalter: BUCKWALTER, dmg: DMG }.freeze
    SCHEMES = (TABLES.keys + [:arabic]).freeze

    # Rule 1's dropped marks: fathatan … kasra (U+064B–0650), sukun
    # (U+0652), maddah/hamza above/below as combining marks (U+0653–0655),
    # superscript alif (U+0670) and tatweel (U+0640). Shadda (U+0651) is
    # rule 2's, kept here.
    VOWEL_MARKS = /[ً-ِْ-ٰٕـ]/
    SHADDA = "ّ"
    HAMZA = "ء"
    # Rule 1's seats: hamza on alif/waw/ya, madda alif, wasla alif, bare alif.
    SEATS = /[آأؤإئاٱ]/
    ALIF_MAQSURA = "ى"
    YA = "ي"
    # Rule 3's weak class: waw, ya, hamza — written as hamza in the key.
    WEAK = /[ويء]/
    # Arabic letters (hamza … ya, wasla alif) — what a key may hold.
    LETTER = /[ء-غف-يٱ]/
    ARABIC_SCRIPT = /\p{Arabic}/

    module_function

    # +root+ in +scheme+ (:buckwalter, :dmg, :arabic) as Arabic script, or
    # nil when any character is outside the table (a clean miss).
    def to_arabic(root, scheme:)
      text = Normalize.nfc(root.to_s.strip)
      return nil if text.empty?
      return text if scheme == :arabic

      table = TABLES.fetch(scheme) { raise ArgumentError, "arabic roots: unknown scheme #{scheme.inspect}" }
      out = +""
      text.each_char do |char|
        letter = table[char] or return nil
        out << letter
      end
      out
    end

    # The characters of +root+ the +scheme+'s table does not map (the
    # tests' loud census; runtime callers just get nil from #to_arabic).
    def unmapped(root, scheme:)
      table = TABLES.fetch(scheme)
      Normalize.nfc(root.to_s).each_char.reject { |char| table.key?(char) }.uniq
    end

    # The scheme a typed root is written in: Arabic script; DMG when every
    # character is a DMG letter (the plain letters DMG shares with
    # Buckwalter — b t d r z s f q k l m n h w y — map to the same Arabic
    # letters in both, so "ktb" is unambiguous); else Buckwalter.
    def detect_scheme(root)
      text = Normalize.nfc(root.to_s.strip)
      return :arabic if text.match?(ARABIC_SCRIPT)
      return :dmg if !text.empty? && text.each_char.all? { |char| DMG.key?(char) }

      :buckwalter
    end

    # -- rule 1 ---------------------------------------------------------------

    def strip_vowels(arabic) = arabic.gsub(VOWEL_MARKS, "")

    def fold_seats(arabic) = arabic.gsub(SEATS, HAMZA).tr(ALIF_MAQSURA, YA)

    # -- rule 2 ---------------------------------------------------------------

    # A shadda doubles the letter it sits on (a leading stray shadda drops).
    def expand_shadda(arabic) = arabic.gsub(/(.)?#{SHADDA}/o) { ::Regexp.last_match(1).to_s * 2 }

    def collapse_geminate(arabic) = arabic.sub(/(.)\1\z/, '\1')

    # -- rule 3 ---------------------------------------------------------------

    def fold_weak(arabic) = arabic.gsub(WEAK, HAMZA)

    # -- rule 4 ---------------------------------------------------------------

    def collapse_reduplication(arabic) = arabic.sub(/\A(..)\1\z/, '\1')

    # -- keys -----------------------------------------------------------------

    # The strict key (rules 1–2) of one Arabic-script root, or nil when
    # nothing letter-shaped is left. Non-letters (punctuation, stray
    # Latin) are dropped after the rules.
    def strict_key(arabic)
      return nil if arabic.nil?

      text = fold_seats(expand_shadda(strip_vowels(Normalize.nfc(arabic))))
      letters = collapse_geminate(text.scan(LETTER).join)
      letters.empty? ? nil : letters
    end

    # The loose-tier key (rules 1–4) derived from a strict key.
    def loosen(strict) = fold_weak(collapse_reduplication(strict))

    # The loose-tier key (rules 1–4) of one Arabic-script root.
    def loose_key(arabic)
      key = strict_key(arabic)
      key && loosen(key)
    end

    # The [strict, loose] keys of a root written in +scheme+, or nil.
    def keys(root, scheme:)
      strict = strict_key(to_arabic(root, scheme: scheme))
      strict && [strict, loosen(strict)]
    end

    # The individual roots one Lane heading names: an unvocalized heading
    # listing several roots splits on whitespace; anything else is one
    # head. Punctuation is dropped by the key itself.
    def heads(heading)
      text = Normalize.nfc(heading.to_s.strip)
      parts = text.split(/\s+/)
      return [text] if parts.size < 2 || text.match?(VOWEL_MARKS)

      parts
    end

    # The distinct [strict, loose] key pairs of one Lane heading.
    def heading_keys(heading)
      heads(heading).filter_map { |head| (strict = strict_key(head)) && [strict, loosen(strict)] }.uniq
    end
  end
end
