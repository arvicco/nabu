# frozen_string_literal: true

module Nabu
  module Adapters
    # The shared Leiden vocabulary of the Celtic epigraphy pair (P25-1):
    # RiigEpidocParser (Gaulish, RIIG) and OghamEpidocParser (Primitive
    # Irish, OG(H)AM) are SIBLING parser families in the EDH/DDbDP sense —
    # each owns its walk and its per-source policies — but unlike those
    # streaming giants they parse SMALL corpora (428 + ~500 files, ≤70 KB
    # each; the freising DOM precedent, not the >5 MB Reader rule), and the
    # Leiden *reading-text* decisions they share are genuinely one policy,
    # so it lives here once:
    #
    # - <choice> keeps exactly ONE branch — corr > reg > lem > expan > first
    #   child (DDbDP's print-edition doctrine: the editor's accepted,
    #   regularized, expanded reading is the main text; sic/orig/rdg are
    #   apparatus). RIIG's orig/reg pairs pick reg; OG(H)AM's corr/sic pairs
    #   pick corr whichever order upstream wrote them; a choice of two
    #   <unclear> alternatives (OG(H)AM) reads the first.
    # - <gap> contributes the single GAP_MARKER regardless of extent — the
    #   marker sits exactly where the lost letters sat (fused mid-word when
    #   the damage is mid-word); the length data goes to annotations.
    # - <del> is KEPT, wrapped in Leiden double brackets ⟦…⟧ — the direction
    #   the EDH parser's per-source divergence recorded for new sources with
    #   no frozen urns (conventions §5): erased-but-legible text is reading
    #   text.
    # - <surplus> is kept wrapped in Leiden braces {…} — letters the carver
    #   cut in error, printed but excluded from the regularized reading.
    # - <supplied>/<unclear> read through; their non-whitespace grapheme
    #   counts ride as annotations ("letters restored"/"letters dotted").
    module CelticLeiden
      GAP_MARKER = "[…]"
      CANCELLATION_OPEN = "⟦"
      CANCELLATION_CLOSE = "⟧"
      SURPLUS_OPEN = "{"
      SURPLUS_CLOSE = "}"

      # The kept branch of a <choice>, by name preference then document
      # order (see module note).
      CHOICE_PREFERENCE = %w[corr reg lem expan].freeze

      # Upstream ISO 639-1 tags → Nabu's ISO 639-3 (conventions §4); script
      # subtags survive (la-Latn → lat-Latn). Tags already 639-3 (xtg, pgl,
      # sga, mga, xpi, non, und, cel) pass through.
      LANGUAGE_MAP = { "la" => "lat", "ga" => "gle", "gd" => "gla", "en" => "eng", "fr" => "fra" }.freeze

      module_function

      # Map an upstream xml:lang tag to Nabu's ISO 639-3 form. nil-safe,
      # nil/empty → nil.
      def normalize_language(tag)
        return nil if tag.nil? || tag.empty?

        primary, rest = tag.split("-", 2)
        mapped = LANGUAGE_MAP.fetch(primary, primary)
        rest ? "#{mapped}-#{rest}" : mapped
      end

      # The kept child element of a +choice+ node (Nokogiri element), or nil
      # for an empty choice.
      def choice_branch(choice)
        elements = choice.element_children
        CHOICE_PREFERENCE.each do |name|
          found = elements.find { |element| element.name == name }
          return found if found
        end
        elements.first
      end

      # A <gap>'s annotation hash: reason/quantity/extent/unit attributes,
      # integers where numeric (the DdbdpParser shape).
      def gap_annotation(node)
        %w[reason quantity extent unit].each_with_object({}) do |attribute, gap|
          value = node[attribute]
          next if value.nil? || value.empty?

          gap[attribute] = value.match?(/\A\d+\z/) ? Integer(value, 10) : value
        end
      end

      # House line folding: whitespace runs collapse to one space, ends
      # strip, NFC (the P6-4 boundary; text_normalized is minted downstream
      # by Passage.new).
      def fold(text)
        Normalize.nfc(text.gsub(/[[:space:]]+/, " ").strip)
      end

      # Non-whitespace grapheme clusters — "letters restored", the number a
      # print edition's brackets would enclose.
      def grapheme_count(text)
        text.gsub(/[[:space:]]/, "").grapheme_clusters.size
      end

      # A folded line whose only content is gap markers is not citable text.
      def gap_only?(text)
        text.gsub(GAP_MARKER, "").gsub(/[[:space:]]/, "").empty?
      end

      # The lean leiden annotation hash for one accumulated line/state:
      # gaps list, supplied/unclear counts, cancellation flag — only
      # non-empty keys (honest sparsity).
      def leiden_annotations(gaps:, supplied:, unclear:, cancelled:)
        result = {}
        result["gaps"] = gaps unless gaps.empty?
        result["supplied_chars"] = supplied if supplied.positive?
        result["unclear_chars"] = unclear if unclear.positive?
        result["cancelled"] = true if cancelled
        result
      end
    end
  end
end
