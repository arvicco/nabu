# frozen_string_literal: true

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Nusantara epigraphy (P92-2): ~309 editions from the
    # Indonesian archipelago and beyond — Old Javanese sīma charters
    # (Sangguran, Mantyasih), the Borobudur inscriptions, Old Sundanese
    # (Kawali, Batutulis), Old Malay (Sojomerto; the Laguna copperplate,
    # the Philippines' oldest document) and Sanskrit. The library's whole
    # Old Malay coverage rides here — no separate corpus exists.
    class DharmaNusantara < DharmaBase
      SLUG = "dharma-nusantara"
      NAME = "DHARMA Nusantara epigraphy (Old Javanese/Malay/Sundanese charters)"
      CREDIT_CORPUS = "Nusantara epigraphy corpus"
      REPO_URL = "https://github.com/erc-dharma/tfc-nusantara-epigraphy"
      XML_DIR = "xml"

      # The full-repo census (2026-09-01): 345 san-Latn · 196 kaw-Latn ·
      # 21 omy-Latn · 15 osn-Latn divs, with eng/nld/ind translation
      # matter outside editions. The one "languageb-Latn" div
      # (INSIDENK00050) is upstream's template-placeholder bug — it
      # quarantines loudly by design.
      LANGUAGES = %w[kaw-Latn omy-Latn osn-Latn san-Latn].freeze
    end
  end
end
