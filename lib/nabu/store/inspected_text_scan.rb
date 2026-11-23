# frozen_string_literal: true

require_relative "../inspected_text"

module Nabu
  module Store
    # The catalog half of `scrub:inspect_text` (Ops::InspectTextScrub): every
    # LIVE passage of one source whose text is an inspected Ruby object
    # (Nabu::InspectedText — the conformance invariant's own detector). A
    # SQL prefilter keeps the walk to the rows whose whitespace-trimmed text
    # opens like an inspect (InspectedText::OPENERS); the Ruby PATTERN
    # decides. Read-only.
    class InspectedTextScan
      Hit = Data.define(:document_urn, :passage_urn, :text)

      # ltrim's character set: the whitespace PATTERN's leading \s admits.
      TRIM = " \t\n\r\f\v"

      def initialize(db:)
        @db = db
      end

      # => [Hit, …] in document, then sequence order; [] for an unknown slug.
      def call(slug:)
        source_id = @db[:sources].where(slug: slug).get(:id)
        return [] if source_id.nil?

        trimmed = Sequel.function(:ltrim, Sequel[:passages][:text], TRIM)
        opens = InspectedText::OPENERS.map { |opener| Sequel.like(trimmed, "#{opener}%") }.inject(:|)
        @db[:passages]
          .join(:documents, id: :document_id)
          .where(Sequel[:documents][:source_id] => source_id, Sequel[:documents][:withdrawn] => false,
                 Sequel[:passages][:withdrawn] => false)
          .where(opens)
          .order(Sequel[:documents][:urn], Sequel[:passages][:sequence])
          .select(Sequel[:documents][:urn].as(:document_urn), Sequel[:passages][:urn].as(:passage_urn),
                  Sequel[:passages][:text])
          .map { |row| Hit.new(**row) }
          .select { |hit| InspectedText.match?(hit.text) }
      end
    end
  end
end
