# frozen_string_literal: true

require_relative "dharma_base"

module Nabu
  module Adapters
    # DHARMA Pyu (P92-2): the Corpus of Pyu Inscriptions (Griffiths et
    # al.) — 161 editions of the extinct Sino-Tibetan language of the Pyu
    # city-states of the Irrawaddy valley (~5th–13th c. CE), romanized.
    # Flat repo layout (editions at the root); no repo-level LICENSE — the
    # per-file <licence> is the whole grant, recorded verbatim.
    class DharmaPyu < DharmaBase
      SLUG = "dharma-pyu"
      NAME = "DHARMA Corpus of Pyu Inscriptions"
      CREDIT_CORPUS = "Corpus of Pyu Inscriptions (Griffiths et al.)"
      REPO_URL = "https://github.com/erc-dharma/tfc-pyu-epigraphy"
      XML_DIR = ""

      LANGUAGES = %w[pyx-Latn san-Latn].freeze
    end
  end
end
