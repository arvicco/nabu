# frozen_string_literal: true

module Nabu
  module Store
    # One (dictionary, lang_code, name) census row of the derived language-
    # name layer (P18-4, migration 011): how many worded descendant nodes of
    # this dictionary's entries called +lang_code+ +name+. Written wholesale
    # per dictionary by DictionaryLoader; read (filtered + mode-reduced) by
    # Nabu::Languages. No business logic here.
    class LanguageName < Sequel::Model(:language_names)
    end
  end
end
