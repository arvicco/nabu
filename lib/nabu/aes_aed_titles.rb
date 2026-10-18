# frozen_string_literal: true

require_relative "aed_text_headers"

module Nabu
  # The AES ← AED title join: the AES corpus JSON carries no title field,
  # so the aes shelf mints its documents title-less; the AED stand-off
  # header for the same TLA text id (AedTextHeaders) names every text
  # ("Szene Rinderzug durchs Wasser, Rede"). This pass fills
  # documents.title on the loaded aes rows.
  #
  # The join is EXACT-KEY only: the text id is the last urn segment the
  # AES adapter mints (urn:nabu:aes:<subcorpus>:<text id>), and the -de
  # German sibling of a text takes the same title (it is that text in
  # translation — the elephantine -en sibling precedent). Placeholder
  # titles leave the row untitled.
  #
  # Derived by construction: f(canonical/aed + loaded aes rows) —
  # documents.title on the aes shelf is NULL from the loader, the pass
  # re-fills idempotently, and it re-runs at rebuild, in the builder
  # refresh, and after aes/aed syncs (the E84000DergeTitles mold: a
  # cross-source read lives in a post-load pass, never in an adapter's
  # parse, so neither source's per-source identity stamp has to cover
  # the other's tree). An absent aed tree is a clean no-op.
  class AesAedTitles
    AES_SLUG = "aes"
    AED_SLUG = "aed"
    URN_PREFIX = "urn:nabu:aes:"
    TRANSLATION_SUFFIX = "-de"

    Result = Data.define(:titled, :untitled)

    def initialize(catalog:, canonical_dir:)
      @catalog = catalog
      @headers = AedTextHeaders.new(aed_dir: File.join(canonical_dir, AED_SLUG))
      @aed_present = Dir.exist?(File.join(canonical_dir, AED_SLUG))
    end

    def run
      return Result.new(titled: 0, untitled: 0) unless @aed_present

      titled = 0
      untitled = 0
      @catalog.transaction do
        aes_documents.each do |id, urn|
          title = @headers.header(text_id(urn))&.title
          if title.nil?
            untitled += 1
            next
          end

          @catalog[:documents].where(id: id).update(title: title)
          titled += 1
        end
      end
      Result.new(titled: titled, untitled: untitled)
    end

    private

    def aes_documents
      source_id = @catalog[:sources].where(slug: AES_SLUG).get(:id)
      return [] if source_id.nil?

      @catalog[:documents].where(source_id: source_id)
                          .where(Sequel.like(:urn, "#{URN_PREFIX}%"))
                          .select_map(%i[id urn])
    end

    def text_id(urn)
      urn.split(":").last.delete_suffix(TRANSLATION_SUFFIX)
    end
  end
end
