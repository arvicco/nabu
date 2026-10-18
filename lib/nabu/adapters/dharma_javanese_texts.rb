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
      # Still quarantined honestly: "und" (6) and "nld" (2) editions.
      LANGUAGES = %w[kaw-Latn osn-Latn san-Latn].freeze

      # First-sync censused tag dirt (2026-09-01): "kaw-Latin" is a typo'd
      # script suffix (3 files); "kaw-ban" tags the Balinese-manuscript
      # tradition (2 files) whose transcription is nonetheless ROMANIZED —
      # the held surface is Latin either way, so both resolve to kaw-Latn
      # (the manuscript's own script is the artifact fact).
      ALIASES = { "kaw-Latin" => "kaw-Latn", "kaw-ban" => "kaw-Latn" }.freeze

      # The edition template's unfilled placeholder (7 witnesses carry
      # "..." in every msIdentifier part — census 2026-10-18).
      PLACEHOLDER = "..."

      # One witness msIdentifier → its filled parts (settlement,
      # institution, repository, collection, idno — or a bare msName)
      # verbatim, joined in element order; nil when nothing is filled.
      def self.shelfmark(node)
        parts = node.element_children.map { |child| child.text.gsub(/[[:space:]]+/, " ").strip }
                                     .reject { |part| part.empty? || part == PLACEHOLDER }
        parts.empty? ? nil : Normalize.nfc(parts.join(", "))
      end

      private

      # The header (census 2026-10-18, 98 editions): the titleStmt
      # <author> — the WORK's attributed poet (11 editions: Mpu Prapañca,
      # Mpu Tantular, Vararuci …; the digital editors ride respStmt, never
      # here) — and every witness msIdentifier in sourceDesc as a
      # shelfmark string (85 editions, 189 witnesses). The author facets
      # via config/facet_map.yml; the shelfmarks are metadata only.
      def corpus_header(doc)
        author = doc.at_xpath("/TEI/teiHeader/fileDesc/titleStmt/author")&.text.to_s
                    .gsub(/[[:space:]]+/, " ").strip
        shelfmarks = doc.xpath("/TEI/teiHeader/fileDesc/sourceDesc//msIdentifier")
                        .filter_map { |node| self.class.shelfmark(node) }
        { "author" => (author.empty? ? nil : Normalize.nfc(author)),
          "shelfmarks" => (shelfmarks.empty? ? nil : shelfmarks) }
      end
    end
  end
end
