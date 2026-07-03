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
  end
end
