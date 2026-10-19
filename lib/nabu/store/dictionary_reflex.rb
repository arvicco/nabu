# frozen_string_literal: true

module Nabu
  module Store
    # One descendant edge of a reconstruction entry (P14-1): flattened from
    # the kaikki descendants tree in depth-first order (seq), keyed for the
    # crosswalk by (language, word_folded/roman_folded). Resolved against
    # passage_lemmas and the other reconstruction shelves at QUERY time only.
    # Since migration 046 a row may carry a typed relation — see
    # Store::ReflexDescent for the direction rule every walk honors.
    class DictionaryReflex < Sequel::Model(:dictionary_reflexes)
      many_to_one :dictionary_entry, class: "Nabu::Store::DictionaryEntry", key: :dictionary_entry_id
    end
  end
end
