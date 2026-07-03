# frozen_string_literal: true

module Nabu
  module Store
    # Derived per-passage payloads: lemmas, glosses, etc. (architecture §5/§6).
    # Embeddings live in vectors.sqlite3, not here.
    class Enrichment < Sequel::Model(:enrichments)
      many_to_one :passage, class: "Nabu::Store::Passage", key: :passage_id
    end
  end
end
