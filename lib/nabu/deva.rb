# frozen_string_literal: true

module Nabu
  # Devanagari → IAST transcoder (P26-2). SARIT carries 40+ editions with a
  # native Devanagari passage surface; MW and GRETIL are IAST. The canonical
  # text keeps its script untouched — this transcoder exists for the SEARCH
  # layer only: the Sarit adapter derives text_normalized from the IAST form
  # of a Devanagari passage (Normalize.search_form over Deva.to_iast, the
  # ccmh-txt documented-derivation precedent), so one IAST query lands on
  # both scripts and the folded headword join with MW keeps working.
  #
  # A TRANSCODE, not a fold rule (the Slp1/Betacode precedent, mw-survey §2):
  # Devanagari's inherent "a" (a consonant not followed by a vowel sign or
  # virāma reads with "a") makes the mapping context-sensitive, so it cannot
  # live in the per-codepoint conventions-§9 fold table — and must run BEFORE
  # the generic fold, which strips the virāma (U+094D, category Mn) that
  # distinguishes क्त (kta) from कत (kata).
  #
  # ONE WAY by design: nothing needs IAST → Devanagari (display keeps the
  # native surface; search folds everything to bare ASCII-ish anyway).
  #
  # Inventory: the standard Sanskrit alphabet plus the marks the SARIT corpus
  # census (2026-07-18) actually observed — anusvāra/visarga/candrabindu,
  # avagraha, oṃ, daṇḍas, digits, the two Vedic accents (→ the same combining
  # marks GRETIL's Ṛgveda carries). Anything outside the inventory passes
  # through unchanged — an unknown character is more honestly kept than
  # guessed at (the Betacode stance). ZWJ/ZWNJ are layout, not text: dropped.
  module Deva
    INDEPENDENT_VOWELS = {
      "अ" => "a", "आ" => "ā", "इ" => "i", "ई" => "ī", "उ" => "u", "ऊ" => "ū",
      "ऋ" => "ṛ", "ॠ" => "ṝ", "ऌ" => "ḷ", "ॡ" => "ḹ",
      "ए" => "e", "ऐ" => "ai", "ओ" => "o", "औ" => "au"
    }.freeze

    CONSONANTS = {
      "क" => "k", "ख" => "kh", "ग" => "g", "घ" => "gh", "ङ" => "ṅ",
      "च" => "c", "छ" => "ch", "ज" => "j", "झ" => "jh", "ञ" => "ñ",
      "ट" => "ṭ", "ठ" => "ṭh", "ड" => "ḍ", "ढ" => "ḍh", "ण" => "ṇ",
      "त" => "t", "थ" => "th", "द" => "d", "ध" => "dh", "न" => "n",
      "प" => "p", "फ" => "ph", "ब" => "b", "भ" => "bh", "म" => "m",
      "य" => "y", "र" => "r", "ल" => "l", "व" => "v",
      "श" => "ś", "ष" => "ṣ", "स" => "s", "ह" => "h", "ळ" => "ḻ"
    }.freeze

    VOWEL_SIGNS = {
      "ा" => "ā", "ि" => "i", "ी" => "ī", "ु" => "u", "ू" => "ū",
      "ृ" => "ṛ", "ॄ" => "ṝ", "ॢ" => "ḷ", "ॣ" => "ḹ",
      "े" => "e", "ै" => "ai", "ो" => "o", "ौ" => "au"
    }.freeze

    # Spacing signs and symbols with a fixed IAST value. The two Vedic accent
    # marks map to the same combining marks GRETIL's accented Ṛgveda uses
    # (U+030D udātta/svarita, U+0331 anudātta).
    OTHERS = {
      "ं" => "ṃ", "ः" => "ḥ", "ँ" => "m̐", "ऽ" => "'", "ॐ" => "oṃ",
      "।" => "|", "॥" => "||",
      "॑" => "̍", "॒" => "̱",
      "०" => "0", "१" => "1", "२" => "2", "३" => "3", "४" => "4",
      "५" => "5", "६" => "6", "७" => "7", "८" => "8", "९" => "9"
    }.freeze

    VIRAMA = "्"
    DROPPED = "‌‍" # ZWNJ / ZWJ — layout, not text

    module_function

    # Transcode +text+ to IAST, NFC-normalized. Characters outside the
    # inventory pass through unchanged.
    def to_iast(text)
      out = +""
      pending_a = false
      text.to_s.each_char do |char|
        if (vowel = VOWEL_SIGNS[char])
          out << vowel
          pending_a = false
        elsif char == VIRAMA
          pending_a = false
        else
          out << "a" if pending_a
          pending_a = false
          next if DROPPED.include?(char)

          if (consonant = CONSONANTS[char])
            out << consonant
            pending_a = true
          else
            out << (INDEPENDENT_VOWELS[char] || OTHERS[char] || char)
          end
        end
      end
      out << "a" if pending_a
      out.unicode_normalize(:nfc)
    end
  end
end
