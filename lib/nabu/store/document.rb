# frozen_string_literal: true

module Nabu
  module Store
    # One work/edition ingested from a source (architecture §5).
    class Document < Sequel::Model(:documents)
      many_to_one :source, class: "Nabu::Store::Source", key: :source_id
      one_to_many :passages, class: "Nabu::Store::Passage", key: :document_id
    end
  end
end
