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
    LANGUAGE_FOLDS = {
      "grc" => ->(str) { str.tr("ς", "σ") },
      "lat" => ->(str) { str.tr("vj", "ui") }
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

    # "grc-Grek" → "grc": rule-table keys are primary subtags only.
    def self.primary_subtag(language)
      language.to_s.split("-").first
    end
  end
end
