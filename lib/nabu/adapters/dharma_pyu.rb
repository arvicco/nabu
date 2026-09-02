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

      # The full-corpus census (2026-09-02, 162 editions): Pyu and
      # Sanskrit carry the corpus; Pali, romanized Old Burmese, Prakrit
      # AND Old Mon (omx — the survey's "no digital Old Mon corpus
      # exists" gap has two inscriptions living right here) are real
      # members: Bagan's multilingual epigraphic world. 56 editions
      # carry no xml:lang at all: this corpus is monolingual by charter
      # (the Corpus of PYU Inscriptions), so the default claims them.
      LANGUAGES = %w[pyx-Latn san-Latn pli-Latn obr-Latn pra-Latn omx-Latn].freeze
      DEFAULT_LANGUAGE = "pyx-Latn"

      private

      # Flat repo: the editions live at the ROOT, so a sparse cone of
      # named paths materializes nothing (the first-sync failure) — the
      # ~1 MB repo clones whole.
      def sparse_paths
        nil
      end
    end
  end
end
