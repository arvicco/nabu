# frozen_string_literal: true

module Nabu
  module Store
    # Journal of load/revise/withdraw and enrichment events (architecture §5,
    # §6). Attached to a passage or, for document-level events, a document.
    class Provenance < Sequel::Model(:provenance)
      many_to_one :passage, class: "Nabu::Store::Passage", key: :passage_id
      many_to_one :document, class: "Nabu::Store::Document", key: :document_id
    end
  end
end
