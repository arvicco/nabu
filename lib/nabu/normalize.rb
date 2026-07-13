# frozen_string_literal: true

module Nabu
  # Text normalization at the adapter boundary. Nabu stores text as UTF-8 NFC
  # internally; upstream sources vary (decomposed accents, precomposed, mixed).
  # Normalize once here, never downstream.
  module Normalize
    # Raised when input is not valid UTF-8 and therefore cannot be normalized.
    # The offending byte sequence is included so a regression fixture can be
    # captured from the error.
    class EncodingError < Nabu::Error; end

    # Return the UTF-8 NFC-normalized form of +str+. Raises
    # Nabu::Normalize::EncodingError if the bytes are not valid UTF-8.
    def self.nfc(str)
      utf8 = str.encoding == Encoding::UTF_8 ? str : str.encode(Encoding::UTF_8)
      unless utf8.valid_encoding?
        raise EncodingError,
              "input is not valid UTF-8: #{str.b.inspect}"
      end

      utf8.unicode_normalize(:nfc)
    rescue ::EncodingError => e
      # Re-tag transcoding failures (bytes tagged as another encoding that cannot
      # map cleanly to UTF-8) as our own error type.
      raise EncodingError, "input is not valid UTF-8: #{str.b.inspect} (#{e.message})"
    end

    # Bare mark strip (the generic fold primitive). Decompose to NFD, drop
    # every nonspacing combining mark (\p{Mn} — Greek accents, breathings,
    # iota subscript, dialytika; Latin accents; Cyrillic titlo U+0483 and
    # palatalization U+0484; IAST dots and macrons), recompose to NFC. The
    # result keeps bare letters so a diacritic-insensitive query matches
    # regardless of the marks the source carried.
    #
    # Why this lives in application code and not in the FTS5 tokenizer: the
    # index's `unicode61 remove_diacritics 2` provably does NOT fold precomposed
    # polytonic Greek (SQLite 3.53.2 leaves ά/ῆ/ἀ/ῃ untouched — it only strips a
    # handful of *combining* marks, and only when the text is already NFD;
    # perispomeni/breathings/iota-subscript are never removed). Our corpus is
    # stored NFC, so the tokenizer alone cannot deliver Greek diacritic-insensitive
    # search. Folding application-side is the reliable mechanism.
    def self.fold_diacritics(str)
      nfc(str).unicode_normalize(:nfd).gsub(/\p{Mn}/, "").unicode_normalize(:nfc)
    end

    # == The per-language search-form rule table (P6-4; conventions.md §9)
    #
    # Extra folds applied ON TOP of the generic fold (downcase + mark strip),
    # keyed by the primary language subtag ("grc-Grek" → "grc"). Languages not
    # listed — got, san, chu, orv, and anything unknown — get the generic fold
    # only, the conservative baseline (rationale + open questions documented
    # in conventions.md §9):
    #
    #   grc  final-sigma normalization ς→σ, so word-internal vs word-final
    #        sigma never splits a search (TLG Beta Code encodes both as one
    #        letter "S"). Iota subscript already falls to the Mn strip.
    #   lat  v→u and j→i, the classical-orthography merge every major Latin
    #        search tool performs (PHI: "not case-sensitive, nor does it
    #        distinguish i from j or u from v").
    #   akk/sux  the cuneiform-transliteration fold (P10-1): sign-join
    #        punctuation (. and -) and determinative braces ({d}, {ki}) open
    #        to spaces, so every sign reading becomes its own searchable
    #        token; subscript index digits (₂ ₃ … and ₓ) normalize to ASCII
    #        (ZI₃ → zi3). Strictly per-codepoint (tr only — no squeeze/strip)
    #        so fold_with_map's char-by-char equality holds; the resulting
    #        double/leading/trailing spaces are FTS-invisible (unicode61
    #        treats separator runs as one). š/ṣ/ṭ and vowel macrons fall to
    #        the generic mark strip. Trade-off documented in conventions.md
    #        §9: a determinative sits as its own token between the signs it
    #        classifies.
    #   sl   Bohorič long s ſ→s (P13-9): plain downcase leaves U+017F alone
    #        (only Unicode FULL case folding maps it to s), so without this
    #        rule every pre-19th-c. Slovene word containing ſ is unfindable
    #        by a modern query. Exactly the grc ς→σ situation: one letter,
    #        two positional glyphs. Bohorič digraphs (zh=č, ſh=š) are NOT
    #        rewritten — that is orthographic modernization, an enrichment,
    #        not a fold; haček letters fall to the generic mark strip.
    #   ang  æ→"ae", þ→"th", ð→"th" (P12-3): the ASCII transliterations a
    #        user actually types, and Bosworth-Toller's own alphabetization —
    #        B-T interfiles þ/ð as ONE letter and its dump's <sort> field
    #        folds æ to "ae" and buckets ð/þ identically (æðele → "aetþele",
    #        þing → "tþing"). ð→"d" was rejected: it would split the pair
    #        B-T unifies. Vowel length (á, ǣ) falls to the generic mark
    #        strip. gsub, not tr — these are 1→2 expansions (fold_with_map
    #        handles non-length-preserving folds; downcase runs first, so
    #        Æ/Þ/Ð reach the rule lowercased).
    CUNEIFORM_FOLD = ->(str) { str.tr("₀₁₂₃₄₅₆₇₈₉ₓ", "0123456789x").tr("{}.-", "    ") }
    private_constant :CUNEIFORM_FOLD

    OLD_ENGLISH_FOLD = ->(str) { str.gsub(/[æþð]/, "æ" => "ae", "þ" => "th", "ð" => "th") }
    private_constant :OLD_ENGLISH_FOLD

    #   gem/ine/sla/itc/iir  the reconstruction/proto fold (P14-10, extended
    #        P17-3): modifier-letter superscripts ʰ (U+02B0) → h, ʷ (U+02B7)
    #        → w — the phonetic marks of aspirates and labiovelars
    #        (*bʰewgʰ-, *gʷʰew-) — plus, from the P17-3 shelf census, ˢ
    #        (U+02E2) → s and ᶻ (U+1DBB) → z (Proto-Indo-Iranian sibilant
    #        clusters: *adᶻdʰáH, *witˢtás; ˢ ×12, ᶻ ×9 measured) and the
    #        glottal-stop letter ˀ (U+02C0) → "" (Proto-Balto-Slavic
    #        laryngeal notation, *wárˀnāˀ, ×310 in headwords — dropped
    #        entirely: no ASCII typist spells it; gsub 1→0,
    #        fold_with_map-safe because the character contributes nothing).
    #        The original census of all 13,053 sla-pro/ine-pro/gem-pro
    #        headwords found ʰ/ʷ as the ONLY Lm letters there; the four
    #        P17-3 extracts add ˢ/ᶻ/ˀ, and Proto-West Germanic (gmw-pro)
    #        carries none — measured — so "gmw" deliberately has no key
    #        (generic fold suffices; ine-bsl-pro folds under "ine" via
    #        primary subtag). The generic fold does NOT touch Lm, so an
    #        ASCII typist's "bhewgh" could never reach *bʰewgʰ- without
    #        this rule. Scoped to the reconstruction pseudo-languages only —
    #        no attested corpus carries those collective codes.
    PROTO_FOLD = ->(str) { str.tr("ʰʷˢᶻ", "hwsz").gsub("ˀ", "") }
    private_constant :PROTO_FOLD

    #   cop  Coptic (P17-1): delete the morphological divider ⳿ (U+2CFF,
    #        category Po — an editorial mark attached to its letter, e.g.
    #        ⲙⲏⲣ⳿, not text). It is the ONLY non-Mn editorial mark the
    #        fixture census found in the diplomatic layer: the supralinear
    #        strokes and overlines (U+0304/0305/0307/0308, U+FE24–FE26
    #        combining half marks) are all Mn and fall to the generic strip
    #        (the improvements §2.2 "supralinear strokes" question,
    #        answered; conventions §9). 1→0 deletion — fold_with_map
    #        handles chars that fold away entirely.
    LANGUAGE_FOLDS = {
      "grc" => ->(str) { str.tr("ς", "σ") },
      "cop" => ->(str) { str.delete("⳿") },
      "lat" => ->(str) { str.tr("vj", "ui") },
      "akk" => CUNEIFORM_FOLD,
      "sux" => CUNEIFORM_FOLD,
      "ang" => OLD_ENGLISH_FOLD,
      "sl" => ->(str) { str.tr("ſ", "s") },
      "gem" => PROTO_FOLD,
      "ine" => PROTO_FOLD,
      "sla" => PROTO_FOLD,
      "itc" => PROTO_FOLD,
      "iir" => PROTO_FOLD
    }.freeze

    # The TRUE search form stored in Passage#text_normalized, minted ONCE at
    # the adapter boundary (Passage.new defaults to this — the single place
    # folding happens). Generic fold (NFC → downcase → strip \p{Mn} → NFC)
    # plus the language's extra rules from LANGUAGE_FOLDS. The pristine text
    # is never touched; this is a derived, per-passage search column.
    def self.search_form(text, language:)
      folded = fold_diacritics(nfc(text).downcase)
      extra = LANGUAGE_FOLDS[primary_subtag(language)]
      extra ? extra.call(folded) : folded
    end

    # Query-side folding (P4-2's Search): queries carry NO language, so one
    # per-language fold cannot be picked. Instead return the UNION — the
    # generic form first, then each language rule's variant when it differs.
    # Search ORs the variants in the FTS MATCH. Why this cannot miss: a
    # passage in language L is indexed as search_form(text, L) =
    # extra_L(generic(text)), and this union always contains
    # extra_L(generic(query)) — so a query spelled the way the source spells
    # it folds, on that variant, exactly the way the document was folded.
    # And why it cannot break other languages: the variants are ORed, so the
    # generic variant still matches languages whose rule table is empty
    # (Gothic "jah" stays findable even though the lat variant folds the
    # query to "iah").
    def self.query_forms(query)
      generic = fold_diacritics(nfc(query).downcase)
      [generic, *LANGUAGE_FOLDS.values.map { |extra| extra.call(generic) }].uniq
    end

    # Fold +text+ exactly as search_form does, but return a CHARACTER-INDEX
    # MAP alongside the folded string so a match located in the folded form
    # can be pointed back at the pristine display text (P8-3 KWIC concordance).
    #
    # Returns [folded, map] where folded == search_form(text, language:) and
    # map[i] is the index, into nfc(text).chars, of the source character that
    # produced folded[i]. The fold is NOT length-preserving (NFD + \p{Mn}
    # strip drops combining marks; a decomposed accent vanishes), so a naive
    # "same index" mapping would be wrong — hence the explicit map.
    #
    # It folds one NFC character at a time and concatenates. This is
    # byte-identical to the whole-string fold because, once every nonspacing
    # mark is stripped, no bare letters recombine under NFC across character
    # boundaries and the per-language rules (ς→σ, v→u/j→i) and downcase are
    # per-codepoint for our scripts — an equality the Normalize test pins
    # against Greek with combining marks. A character that folds away entirely
    # (a lone combining mark) contributes nothing to folded/map, keeping the
    # surviving indices exact.
    def self.fold_with_map(text, language:)
      src = nfc(text)
      extra = LANGUAGE_FOLDS[primary_subtag(language)]
      folded = +""
      map = []
      src.each_char.with_index do |char, i|
        piece = fold_diacritics(char.downcase)
        piece = extra.call(piece) if extra
        piece.each_char do |folded_char|
          folded << folded_char
          map << i
        end
      end
      [folded, map]
    end

    # "grc-Grek" → "grc": rule-table keys are primary subtags only.
    def self.primary_subtag(language)
      language.to_s.split("-").first
    end
  end
end
