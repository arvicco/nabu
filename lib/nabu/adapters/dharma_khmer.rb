# frozen_string_literal: true

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Old Khmer (P92-1, the SEA desk's anchor): the Corpus des
    # inscriptions khmères — the Cœdès K-number corpus digitized, 1,187
    # live editions (survey census 2026-07-26) of pre-Angkorian and
    # Angkorian epigraphy in Old Khmer and Sanskrit, romanized. The first
    # DHARMA source; mints the family the four siblings compose.
    class DharmaKhmer < DharmaBase
      SLUG = "dharma-khmer"
      NAME = "DHARMA Corpus des inscriptions khmères (Old Khmer epigraphy)"
      CREDIT_CORPUS = "Corpus des inscriptions khmères (the Cœdès K-numbers)"
      REPO_URL = "https://github.com/erc-dharma/tfc-khmer-epigraphy"
      XML_DIR = "texts/xml"

      # The measured code set (fixture census + the 2026-09-01 first-sync
      # census of all 1,254 files): Old Khmer and Sanskrit carry the
      # corpus; the sync surfaced khm-Latn (Modern Khmer editions, 23),
      # xhm-Latn (Middle Khmer, 3), pli-Latn (Pali, 3) and pra-Latn
      # (Prakrit, 3) — all real ISO codes, classified. Still quarantined
      # honestly: "und" (1) and "thai-Thai" (1, not a valid tag).
      LANGUAGES = %w[okz-Latn san-Latn khm-Latn xhm-Latn pli-Latn pra-Latn].freeze
    end
  end
end
