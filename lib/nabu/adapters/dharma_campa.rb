# frozen_string_literal: true

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Campā (P92-2): the corpus of the inscriptions of Campā —
    # ~121 editions of Old Cham and Sanskrit epigraphy from the Cham
    # polities of coastal Vietnam; absorbs and supersedes the ISAW–EFEO
    # CIC corpus (repo description records the reuse). Old Cham's Đông Yên
    # Châu inscription is the oldest attested Austronesian text anywhere.
    class DharmaCampa < DharmaBase
      SLUG = "dharma-campa"
      NAME = "DHARMA Campā inscriptions (Old Cham epigraphy)"
      CREDIT_CORPUS = "Corpus of the Inscriptions of Campā"
      REPO_URL = "https://github.com/erc-dharma/tfc-campa-epigraphy"
      XML_DIR = "xml"

      LANGUAGES = %w[ocm-Latn san-Latn].freeze
    end
  end
end
