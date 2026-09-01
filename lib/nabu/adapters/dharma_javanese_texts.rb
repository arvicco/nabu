# frozen_string_literal: true

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Nusantara philology (P92-4): the Old Javanese literary corpus —
    # kakawin critical editions of the first rank (Deśavarṇana, Sutasoma,
    # Arjunavivāha, Pararaton, Calon Arang…), prose critical editions
    # (Bhīma Svarga's four-witness apparatus), Old Sundanese treatises, and
    # diplomatic manuscript transcriptions at folio-line grain. The desk's
    # literary wing; canto @met rides each verse passage's annotations —
    # the meter axis's SEA feed.
    #
    # The repo is ~2.9 GB of facsimile images — the sparse cone materializes
    # editions/ only (the survey's instruction).
    class DharmaJavaneseTexts < DharmaBase
      SLUG = "dharma-javanese-texts"
      NAME = "DHARMA Nusantara philology (the kakawin library and Old Sundanese texts)"
      CREDIT_CORPUS = "Nusantara philology corpus (critical editions and diplomatic transcriptions)"
      REPO_URL = "https://github.com/erc-dharma/tfd-nusantara-philology"
      XML_DIR = "editions"

      # Measured: kaw-Latn (the kakawin mass), osn-Latn (Sanghyang Hayu and
      # the Old Sundanese prose), san-Latn (mantras, opening stanzas).
      LANGUAGES = %w[kaw-Latn osn-Latn san-Latn].freeze
    end
  end
end
