# frozen_string_literal: true

module Nabu
  module Store
    # The citable unit (architecture §3/§5): line, section, or sentence.
    class Passage < Sequel::Model(:passages)
      many_to_one :document, class: "Nabu::Store::Document", key: :document_id
      one_to_many :enrichments, class: "Nabu::Store::Enrichment", key: :passage_id
      one_to_many :provenance, class: "Nabu::Store::Provenance", key: :passage_id
    end
  end
end
