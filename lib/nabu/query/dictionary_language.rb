# frozen_string_literal: true

require "sequel"
require_relative "../languages"

module Nabu
  module Query
    # The one dictionary-language filter every dictionary-keyed lookup
    # shares (P153) — define's --lang, the passage-keyed gloss batch, the
    # lemma profile's dictionary hop, list's entry pages. Two folds, both
    # query-side (stored codes stay whatever the adapter minted):
    #
    # 1. Spelling: the code expands through .codes, the symmetric closure
    #    of Languages.code_variants — GPC stores Welsh "cy" while the held
    #    Welsh text keys "wel" (eebo-tcp) and "cym" (cy-wikisource);
    #    before the fold a Welsh-keyed lookup never reached the
    #    89,386-entry shelf.
    # 2. Grain: the store keys ONE language per dictionary, but a shelf can
    #    carry entries of a second language (the OSHB lexicon's BDB and
    #    augmented-Strong shelves register hbo and hold 852 + 710 Aramaic
    #    entries). Such an entry records its own language as the
    #    annotation "language", and the filter matches it too — so arc
    #    reaches exactly the Aramaic entries, never the Hebrew ones.
    #
    # Lives in query/ on purpose: the fold is read-side only, so it stays
    # out of the shared derivation core (lib/nabu/languages.rb is in the
    # global fingerprint; an edit there would dirty every stamp).
    module DictionaryLanguage
      # 639-3/639-2 code → the 639-1 tags that name it (the reverse hop).
      ISO_639_1_BY_CANONICAL = Nabu::Languages::ISO_639_1.group_by(&:last)
                                                         .transform_values { |pairs| pairs.map(&:first) }.freeze
      private_constant :ISO_639_1_BY_CANONICAL

      module_function

      # code_variants PLUS every 639-1 tag naming a member of the set — the
      # symmetric closure. code_variants stays one-directional for the
      # passage filters (its own contract: a two-letter tag widens to its
      # 639-2/3 pair, never the reverse), but a dictionary shelf may STORE
      # the two-letter tag, and a lookup keyed by a passage's language must
      # reach it from every spelling.
      def codes(code)
        variants = Nabu::Languages.code_variants(code)
        variants | variants.flat_map { |member| ISO_639_1_BY_CANONICAL.fetch(member, []) }
      end

      # The WHERE expression for +lang+ over a dataset joining
      # dictionary_entries to dictionaries.
      def filter(catalog, lang)
        wanted = codes(lang)
        shelf = { Sequel[:dictionaries][:language] => wanted }
        return shelf unless annotations_column?(catalog)

        entry = Sequel.function(:json_extract, Sequel[:dictionary_entries][:annotations_json], "$.language")
        Sequel.|(shelf, { entry => wanted })
      end

      def annotations_column?(catalog)
        catalog.schema(:dictionary_entries).any? { |name, _| name == :annotations_json }
      rescue Sequel::Error
        false
      end
    end
  end
end
