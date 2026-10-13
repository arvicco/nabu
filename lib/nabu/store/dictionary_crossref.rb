# frozen_string_literal: true

module Nabu
  module Store
    # One entry→entry cross-reference (P123-1, migration 039): the pointer
    # verbatim (label), its kind, and the resolved TO entry when exactly
    # one live headword of the same dictionary answers target_folded.
    # Replaced wholesale when the owning entry is revised.
    class DictionaryCrossref < Sequel::Model(:dictionary_crossrefs)
      many_to_one :dictionary_entry, class: "Nabu::Store::DictionaryEntry", key: :dictionary_entry_id
    end
  end
end
