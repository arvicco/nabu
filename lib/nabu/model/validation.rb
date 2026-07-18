# frozen_string_literal: true

module Nabu
  module Model
    # Internal construction-time validators shared by the domain value objects
    # (Passage, DocumentRef, SourceManifest, Document). Every check raises
    # Nabu::ValidationError with a message that names the offending field, so
    # a failed parse points straight at the bad data. Validators return the
    # (frozen) value so constructors can assign in one expression.
    #
    # This module is an implementation detail of lib/nabu/model/ — application
    # code should never call it directly.
    module Validation
      # Closed enum, architecture §5. Drives query/export filters downstream.
      LICENSE_CLASSES = %w[open attribution nc research_private restricted].freeze

      # Shape check only (BCP-47 primary subtag in ISO-639 form plus optional
      # subtags, e.g. "grc", "chu", "grc-Grek"). Deliberately not a registry
      # lookup: adapters ingest obscure languages faster than registries move.
      LANGUAGE_SHAPE = /\A[a-z]{2,3}(-[A-Za-z0-9]{1,8})*\z/

      # Identifier shape for source ids and parser families: lowercase slug,
      # safe as a directory name under canonical/ and as a registry key.
      SLUG_SHAPE = /\A[a-z0-9][a-z0-9_-]*\z/

      module_function

      # A non-empty, non-blank String. Returns a frozen copy.
      def present_string!(value, field:)
        unless value.is_a?(String) && !value.strip.empty?
          raise ValidationError, "#{field} must be a non-empty String, got #{value.inspect}"
        end

        -value
      end

      def urn!(value)
        present_string!(value, field: "urn")
      end

      def language!(value)
        unless value.is_a?(String) && value.match?(LANGUAGE_SHAPE)
          raise ValidationError,
                "language must look like a BCP-47/ISO-639 tag (e.g. \"grc\", \"grc-Grek\"), got #{value.inspect}"
        end

        -value
      end

      def slug!(value, field:)
        unless value.is_a?(String) && value.match?(SLUG_SHAPE)
          raise ValidationError,
                "#{field} must be a lowercase slug ([a-z0-9_-], e.g. \"perseus-greek\"), got #{value.inspect}"
        end

        -value
      end

      # Valid UTF-8 in NFC form, non-empty. Non-NFC input is *rejected*, not
      # normalized: normalization is the adapter's job at the boundary
      # (Nabu::Normalize.nfc); silently fixing it here would let unnormalized
      # text slip through untested code paths. Returns a frozen UTF-8 copy.
      def nfc_text!(value, field:)
        raise ValidationError, "#{field} must be a String, got #{value.inspect}" unless value.is_a?(String)

        utf8 = coerce_utf8(value, field: field)
        raise ValidationError, "#{field} must not be empty" if utf8.empty?

        unless utf8.unicode_normalized?(:nfc)
          raise ValidationError,
                "#{field} is not NFC-normalized (normalize at the adapter boundary via Nabu::Normalize.nfc): " \
                "#{utf8.inspect}"
        end

        -utf8
      end

      # Valid UTF-8, non-empty — WITHOUT the NFC check: the P26-3 per-language
      # NFC exemption (Normalize::NFC_EXEMPT_LANGUAGES — Biblical Hebrew/
      # Aramaic, whose Masoretic combining-mark order NFC would reorder).
      # Passage construction routes exempt-language text here so the bytes are
      # stored exactly as upstream ships them; every other caller keeps
      # nfc_text!. Returns a frozen UTF-8 copy.
      def verbatim_text!(value, field:)
        raise ValidationError, "#{field} must be a String, got #{value.inspect}" unless value.is_a?(String)

        utf8 = coerce_utf8(value, field: field)
        raise ValidationError, "#{field} must not be empty" if utf8.empty?

        -utf8
      end

      def sequence!(value)
        unless value.is_a?(Integer) && value >= 0
          raise ValidationError, "sequence must be a non-negative Integer, got #{value.inspect}"
        end

        value
      end

      def license_class!(value)
        candidate = value.is_a?(Symbol) ? value.to_s : value
        unless candidate.is_a?(String) && LICENSE_CLASSES.include?(candidate)
          raise ValidationError,
                "license_class must be one of #{LICENSE_CLASSES.join(', ')}; got #{value.inspect}"
        end

        -candidate
      end

      # A license_class, or nil for "no per-document override" (the common
      # case). The db CHECK on documents.license_override is the backstop; this
      # rejects a bad class at the domain boundary so it never reaches a write.
      def license_class_or_nil!(value)
        value.nil? ? nil : license_class!(value)
      end

      # A Hash of pure JSON data (String/Symbol keys; String, Integer, finite
      # Float, true/false/nil, Array, Hash values). Returns a deep, deeply
      # frozen copy so the value object shares no mutable state with the
      # caller. Symbols are rejected as *values* because a JSON round-trip
      # would silently turn them into Strings.
      def json_hash!(value, field:)
        raise ValidationError, "#{field} must be a Hash, got #{value.inspect}" unless value.is_a?(Hash)

        json_value!(value, field: field)
      end

      def json_value!(value, field:)
        case value
        when nil, true, false, Integer
          value
        when Float
          raise ValidationError, "#{field} contains non-finite Float #{value.inspect}" unless value.finite?

          value
        when String
          unless value.valid_encoding?
            raise ValidationError, "#{field} contains a String that is not valid in its encoding: #{value.b.inspect}"
          end

          -value
        when Array
          value.map { |element| json_value!(element, field: field) }.freeze
        when Hash
          value.each_with_object({}) do |(key, element), copy|
            copy[json_key!(key, field: field)] = json_value!(element, field: field)
          end.freeze
        else
          raise ValidationError,
                "#{field} must be JSON-serializable data; #{value.inspect} (#{value.class}) is not"
        end
      end

      def json_key!(key, field:)
        case key
        when String then -key
        when Symbol then key
        else
          raise ValidationError, "#{field} keys must be Strings or Symbols, got #{key.inspect} (#{key.class})"
        end
      end

      # Accept UTF-8 (and US-ASCII, a strict subset) only; anything else must
      # be transcoded by the adapter before it reaches the domain.
      def coerce_utf8(value, field:)
        utf8 =
          case value.encoding
          when Encoding::UTF_8 then value
          when Encoding::US_ASCII then value.encode(Encoding::UTF_8)
          else
            raise ValidationError,
                  "#{field} must be UTF-8 (got #{value.encoding.name}): #{value.b.inspect}"
          end
        raise ValidationError, "#{field} is not valid UTF-8: #{value.b.inspect}" unless utf8.valid_encoding?

        utf8
      end
      private_class_method :coerce_utf8
    end
  end
end
