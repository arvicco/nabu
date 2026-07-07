# frozen_string_literal: true

module Nabu
  module Query
    # `nabu show URN:<start>-<end>` (P7-6): resolve a range urn to an
    # inclusive, sequence-ordered slice of ONE document between two citation
    # suffixes. Shared by Show (plain listing) and Parallel (range + --parallel).
    #
    # == What a range urn is
    #
    #   <document-urn>:<start-suffix>-<end-suffix>
    #
    # The full start passage urn is `<document-urn>:<start-suffix>`; the end is
    # named by its suffix alone and reconstructed against the SAME document
    # (`<document-urn>:<end-suffix>`). Both endpoints must resolve to existing
    # passages of that one document; the slice is every passage whose STORED
    # sequence falls between them, inclusive — whatever citation shapes lie
    # between (papyri restart blocks included: `…:240:1-b2:2` slices across the
    # implicit-block boundary, P5-1).
    #
    # == The split rule (deliberate; documented; tested)
    #
    # Citation suffixes are made of dots and colons (1.1, b2:5, r:3) but never
    # hyphens, whereas document urns routinely carry a hyphen in their version
    # segment (perseus-grc2) or slug (gothic-proiel). So:
    #
    #   1. LITERAL FIRST. The caller (Show/Parallel) tries the whole string as a
    #      real passage or document urn before ever calling Range. A urn that
    #      contains a hyphen but IS a real passage therefore stays reachable and
    #      is never misparsed as a range. Range is only reached once the literal
    #      lookup has failed.
    #   2. Then split on the LAST hyphen: everything before it is the start
    #      passage urn, everything after is the end suffix. The last hyphen is
    #      the range separator because real suffixes hold no hyphens, while the
    #      version-segment hyphen sits to the LEFT of the citation.
    #   3. A range is RECOGNISED only when the head names a real passage, or a
    #      real document is a prefix of the head (so a bad START can be named).
    #      Otherwise the string is not a range → nil (the caller reports "urn
    #      not found"), so a genuinely unknown urn is never dressed up as one.
    class Range
      # A range urn resolved into its document + inclusive sequence bounds.
      # start_urn/end_urn are the absolute passage urns of the two endpoints.
      Slice = Data.define(
        :document_id, :document_urn, :start_urn, :end_urn, :start_seq, :end_seq, :total
      )

      # A range that names two endpoints but cannot be honoured: an endpoint
      # doesn't exist, or start comes after end. Surfaced by the CLI as exit 1.
      class Error < Nabu::Error; end

      SEPARATOR = "-"
      private_constant :SEPARATOR

      def initialize(catalog:)
        @catalog = catalog
      end

      # Resolve +urn+ to a Slice, or nil when it is not range-shaped. Raises
      # Range::Error (naming the endpoint) when it IS a range but an endpoint is
      # unresolvable, or when the endpoints are reversed.
      def resolve(urn)
        return nil unless urn.include?(SEPARATOR)

        head, _sep, end_suffix = urn.rpartition(SEPARATOR)
        start_row = passage(head)
        return nil if start_row.nil? && document_prefix_of(head).nil?
        raise Error, "range start not found: #{head}" if start_row.nil?

        document_id = start_row.fetch(:document_id)
        document_urn = start_row.fetch(:document_urn)
        end_urn = "#{document_urn}:#{end_suffix}"
        end_row = passage(end_urn)
        same_document = end_row && end_row.fetch(:document_id) == document_id
        raise Error, "range end not found: #{end_urn}" unless same_document

        build_slice(start_row, end_row, document_id: document_id, document_urn: document_urn,
                                        start_urn: head, end_urn: end_urn)
      end

      private

      def build_slice(start_row, end_row, document_id:, document_urn:, start_urn:, end_urn:)
        start_seq = start_row.fetch(:sequence)
        end_seq = end_row.fetch(:sequence)
        if start_seq > end_seq
          raise Error, "reversed range: start #{start_urn} (sequence #{start_seq}) comes after " \
                       "end #{end_urn} (sequence #{end_seq}); swap the endpoints"
        end

        Slice.new(
          document_id: document_id, document_urn: document_urn,
          start_urn: start_urn, end_urn: end_urn, start_seq: start_seq, end_seq: end_seq,
          total: @catalog[:passages].where(document_id: document_id).count
        )
      end

      # A passage urn → its document id/urn and stored sequence, or nil.
      def passage(urn)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .where(Sequel[:passages][:urn] => urn)
          .select(
            Sequel[:passages][:document_id].as(:document_id),
            Sequel[:documents][:urn].as(:document_urn),
            Sequel[:passages][:sequence].as(:sequence)
          )
          .first
      end

      # The longest document urn that +str+ extends as `<document-urn>:…`, or
      # nil. Lets a bad START endpoint be named honestly (the head has the shape
      # of a passage of a known document, that passage just doesn't exist)
      # without misclassifying an unknown non-range urn as a range.
      def document_prefix_of(str)
        @catalog[:documents]
          .where(Sequel.lit("? LIKE ? || ':%'", str, Sequel[:documents][:urn]))
          .select_map(:urn)
          .max_by(&:length)
      end
    end
  end
end
