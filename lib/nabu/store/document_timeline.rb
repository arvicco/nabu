# frozen_string_literal: true

module Nabu
  module Store
    # One timeline fact for a document (P15-2, migration 008): a signed
    # historical-year range (not_before..not_after, either bound NULL =
    # open-ended), an optional provenance place, and the extractor that minted
    # it. Derived from canonical by Store::TimelineBuilder; regenerated on rebuild.
    class DocumentTimeline < Sequel::Model(:document_axes)
      many_to_one :document, class: "Nabu::Store::Document", key: :document_id
    end
  end
end
