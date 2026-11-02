# frozen_string_literal: true

require "sequel"
require_relative "../languages"

module Nabu
  module Query
    # The one dictionary-language filter every dictionary-keyed lookup
    # shares (P153) — define's --lang, the passage-keyed gloss batch, the
    # lemma profile's dictionary hop, list's entry pages. The fold is
    # query-side (stored codes stay whatever the adapter minted):
    #
    # Spelling: the code expands through .codes, the symmetric closure
    #    of Languages.code_variants — GPC stores Welsh "cy" while the held
    #    Welsh text keys "wel" (eebo-tcp) and "cym" (cy-wikisource);
    #    before the fold a Welsh-keyed lookup never reached the
    #    89,386-entry shelf.
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
      def filter(_catalog, lang)
        { Sequel[:dictionaries][:language] => codes(lang) }
      end
    end
  end
end
