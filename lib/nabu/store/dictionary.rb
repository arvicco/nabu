# frozen_string_literal: true

module Nabu
  module Store
    # One dictionary of the reference shelf (P11-4, architecture §11):
    # lsj, lewis-short — owned by the source that syncs it (lexica carries
    # both). `language` is the object language of the headwords.
    class Dictionary < Sequel::Model(:dictionaries)
      many_to_one :source, class: "Nabu::Store::Source", key: :source_id
      one_to_many :entries, class: "Nabu::Store::DictionaryEntry", key: :dictionary_id
    end
  end
end
