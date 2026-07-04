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

    # Diacritic-folded search form (architecture §3: text_normalized is the
    # "search form: lowercased, diacritic-folded"). Decompose to NFD, drop every
    # nonspacing combining mark (\p{Mn} — Greek accents, breathings, iota
    # subscript, dialytika; Latin accents), recompose to NFC. The result keeps
    # bare letters so a diacritic-insensitive query matches regardless of the
    # polytonic marks the source carried.
    #
    # Why this lives in application code and not in the FTS5 tokenizer: the
    # index's `unicode61 remove_diacritics 2` provably does NOT fold precomposed
    # polytonic Greek (SQLite 3.53.2 leaves ά/ῆ/ἀ/ῃ untouched — it only strips a
    # handful of *combining* marks, and only when the text is already NFD;
    # perispomeni/breathings/iota-subscript are never removed). Our corpus is
    # stored NFC, so the tokenizer alone cannot deliver Greek diacritic-insensitive
    # search. Folding here is the reliable mechanism; the Indexer folds passage
    # text before indexing and search must fold the query the same way.
    def self.fold_diacritics(str)
      nfc(str).unicode_normalize(:nfd).gsub(/\p{Mn}/, "").unicode_normalize(:nfc)
    end
  end
end
