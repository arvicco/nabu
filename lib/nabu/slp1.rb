# frozen_string_literal: true

module Nabu
  # SLP1 ↔ IAST transcoder (P17-4). The Cologne CDSL Monier-Williams carries
  # ALL its Sanskrit — headword keys, in-body <s> text — in SLP1 (Sanskrit
  # Library Phonetic encoding, one ASCII character per phoneme); the
  # dictionary shelf needs IAST for display and for folded-headword keying
  # (GRETIL is san-Latn IAST, and the generic conventions-§9 fold then joins
  # the two shelves), so the transcoding happens once, at the adapter
  # boundary — the Betacode precedent exactly (mw-survey §2: a TRANSCODE,
  # not a fold rule; no conventions-§9 addition).
  #
  # Deliberately minimal and DETERMINISTIC BOTH WAYS where possible: the
  # inventory is the SLP1 alphabet the MW files use (mwheader langUsage
  # "sa-Latn-x-SLP1"; Cologne's own transcoder tables):
  #
  #   vowels    a A i I u U f F x X e E o O   → a ā i ī u ū ṛ ṝ ḷ ḹ e ai o au
  #   marks     M H ~                          → ṃ ḥ m̐
  #   gutturals k K g G N                      → k kh g gh ṅ
  #   palatals  c C j J Y                      → c ch j jh ñ
  #   cerebrals w W q Q R                      → ṭ ṭh ḍ ḍh ṇ
  #   dentals   t T d D n                      → t th d dh n
  #   labials   p P b B m                      → p ph b bh m
  #   sonants   y r l v L                      → y r l v ḻ (Vedic retroflex)
  #   sibilants S z s h                        → ś ṣ s h
  #
  # The vocalic-ḷ / retroflex-ḻ split (x → ḷ, L → ḻ) keeps the reverse map
  # unambiguous — classical IAST overloads ḷ for both; ISO-15919-style ḻ for
  # the retroflex is what Cologne's own slp1→iast table uses. Digraphs in
  # the REVERSE direction (kh, ai, …) are resolved longest-match-first, the
  # standard reading — Sanskrit romanization always spells the aspirate as
  # the digraph, and the generic fold makes ḷ/ḻ meet at "l" anyway.
  #
  # Accents (the MW key2/<s> apparatus): SLP1 marks udātta "/" and svarita
  # "\" AFTER the vowel; they transcode to combining acute/grave on that
  # vowel, NFC-composed ("a/MSa" → "áṃśa", "BA/zate" → "bhā́ṣate" — the
  # print's own forms). The reverse direction peels ONLY those two marks
  # back off (ś/ṃ/ā stay composed single characters), so accent-bearing
  # forms round-trip exactly.
  #
  # Anything outside the inventory — compound seams (—, -), √, ˚ (elision),
  # digits, punctuation, whitespace — passes through unchanged: an unknown
  # character is more honestly kept than guessed at (the Betacode stance).
  module Slp1
    LETTERS = {
      "a" => "a", "A" => "ā", "i" => "i", "I" => "ī", "u" => "u", "U" => "ū",
      "f" => "ṛ", "F" => "ṝ", "x" => "ḷ", "X" => "ḹ",
      "e" => "e", "E" => "ai", "o" => "o", "O" => "au",
      "M" => "ṃ", "H" => "ḥ", "~" => "m̐",
      "k" => "k", "K" => "kh", "g" => "g", "G" => "gh", "N" => "ṅ",
      "c" => "c", "C" => "ch", "j" => "j", "J" => "jh", "Y" => "ñ",
      "w" => "ṭ", "W" => "ṭh", "q" => "ḍ", "Q" => "ḍh", "R" => "ṇ",
      "t" => "t", "T" => "th", "d" => "d", "D" => "dh", "n" => "n",
      "p" => "p", "P" => "ph", "b" => "b", "B" => "bh", "m" => "m",
      "y" => "y", "r" => "r", "l" => "l", "v" => "v", "L" => "ḻ",
      "S" => "ś", "z" => "ṣ", "s" => "s", "h" => "h"
    }.freeze

    # SLP1 accent sign (written after the vowel) → combining mark.
    ACCENTS = { "/" => "́", "\\" => "̀" }.freeze
    ACCENTS_REVERSE = ACCENTS.invert.freeze

    # Reverse letter map, longest IAST token first so digraphs (kh, ai, m̐)
    # win over their prefixes. The two maps are exact inverses.
    REVERSE = LETTERS.invert.sort_by { |iast, _| -iast.length }.freeze

    module_function

    # SLP1 → IAST, NFC. Characters outside the SLP1 inventory pass through.
    def to_iast(text)
      out = +""
      text.to_s.each_char do |char|
        out << (LETTERS[char] || ACCENTS[char] || char)
      end
      out.unicode_normalize(:nfc)
    end

    # IAST → SLP1, longest-match-first. Characters outside the IAST
    # inventory pass through — the same honesty as the forward direction.
    def from_iast(text)
      src = peel_accents(text.to_s.unicode_normalize(:nfc))
      out = +""
      index = 0
      while index < src.length
        token, length = match_reverse(src, index)
        out << token
        index += length
      end
      out
    end

    # Detach ONLY the acute/grave accents from precomposed characters ("á" →
    # "a" + U+0301) so the SLP1 accent sign can be restored after the vowel.
    # Characters that are themselves IAST letters (ś — whose canonical
    # decomposition also ends in an acute) stay composed; a combining
    # acute/grave already standing alone (ā́ has no precomposed form) is
    # left in place for the match loop.
    def peel_accents(text)
      text.each_char.map do |char|
        next char if LETTERS.value?(char)

        nfd = char.unicode_normalize(:nfd)
        if nfd.length > 1 && ACCENTS_REVERSE.key?(nfd[-1])
          nfd[0..-2].unicode_normalize(:nfc) + nfd[-1]
        else
          char
        end
      end.join
    end

    def match_reverse(src, index)
      REVERSE.each do |iast, slp1|
        return [slp1, iast.length] if src[index, iast.length] == iast
      end
      accent = ACCENTS_REVERSE[src[index]]
      accent ? [accent, 1] : [src[index], 1]
    end
  end
end
