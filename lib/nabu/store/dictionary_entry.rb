# frozen_string_literal: true

module Nabu
  module Store
    # One dictionary entry (P11-4): urn-keyed (urn:nabu:dict:<slug>:<id>),
    # looked up by headword_folded (the conventions §9 both-sides fold), with
    # the same revision/withdrawn bookkeeping as documents/passages.
    class DictionaryEntry < Sequel::Model(:dictionary_entries)
      many_to_one :dictionary, class: "Nabu::Store::Dictionary", key: :dictionary_id
      one_to_many :citations, class: "Nabu::Store::DictionaryCitation", key: :dictionary_entry_id
    end
  end
end
