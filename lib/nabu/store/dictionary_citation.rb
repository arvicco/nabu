# frozen_string_literal: true

module Nabu
  module Store
    # One CTS citation a dictionary entry makes (P11-4). cts_work + citation
    # are the query-time resolution keys; display is the human-readable text.
    # Replaced wholesale when the owning entry is revised.
    class DictionaryCitation < Sequel::Model(:dictionary_citations)
      many_to_one :entry, class: "Nabu::Store::DictionaryEntry", key: :dictionary_entry_id
    end
  end
end
