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

      # The measured code set (per-file xml:lang census): Old Khmer and
      # Sanskrit edition divs, both romanized. Anything else quarantines.
      LANGUAGES = %w[okz-Latn san-Latn].freeze
    end
  end
end
