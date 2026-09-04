# frozen_string_literal: true

require_relative "perseus"

module Nabu
  module Adapters
    # PerseusDL canonical-angLit (P95-4, the long-tail sweep): the
    # namespace-shift subclass, the PerseusLatin shape — plus the ONE
    # thing the legacy repo needs that greekLit/latinLit do not. One
    # textgroup/one work upstream — Beowulf (Klaeber 1922) beside its
    # aligned English translation; the registry opts the source into
    # `translations: true`, which is the point: the OE original joins the
    # held ASPR witness as a provenance-distinct second edition (the
    # diorisis stance), and the translation is the germanic desk's first
    # aligned parallel doc.
    #
    # == The legacy-entity decode (P95-4 census, 2026-09-04)
    #
    # The Klaeber file predates the P5 cleanups: it references Perseus
    # P4-era character entities with NO DTD to define them, so a strict
    # XML read dies at the first &aeligmacr;. The exact inventory was
    # censused (1,062 aeligmacr + 3 ycirc + 2 AEligmacr + 1 rmacr +
    # 1 ecedil; the eng file uses only predefined &amp;) and each is a
    # plain CHARACTER IDENTITY — decoding them to their Unicode
    # codepoints is transcription, not text cleanup. Unknown entities
    # are left untouched to die loudly in the parser.
    class PerseusAnglit < Perseus
      NAMESPACE = "angLit"

      # The censused legacy entities and their Unicode identities.
      LEGACY_ENTITIES = {
        "&aeligmacr;" => "ǣ",   # U+01E3 latin small ae with macron
        "&AEligmacr;" => "Ǣ",   # U+01E2 latin capital AE with macron
        "&ycirc;" => "ŷ",       # U+0177 latin small y with circumflex
        "&rmacr;" => "r̄", # r + combining macron (no precomposed form)
        "&ecedil;" => "ȩ" # U+0229 latin small e with cedilla
      }.freeze

      # The parent's parse over a legacy-entity-decoded reading of the
      # file; canonical_path keeps every error message and provenance
      # trail on the real on-disk file.
      def parse(document_ref)
        decoded = File.read(document_ref.path).gsub(/&[A-Za-z]+;/) do |entity|
          LEGACY_ENTITIES.fetch(entity, entity)
        end
        language = document_ref.metadata["language"]
        options = if language == TRANSLATION_LANGUAGE
                    { division_types: TRANSLATION_DIVISION_TYPES }
                  else
                    {}
                  end
        EpidocParser.new.parse(
          StringIO.new(decoded),
          urn: document_ref.id, language: language,
          title: document_ref.metadata["title"],
          canonical_path: document_ref.path, **options
        )
      end
    end
  end
end
