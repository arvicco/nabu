# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  # One citation a dictionary entry makes (P11-4). Minted only for <bibl>
  # elements whose @n carries a urn:cts: value; the human-readable display
  # ("Il. 1.1", "Cic. Off. 1, 2, 4") also flows into the entry body as plain
  # text, so URN-less citations are not lost — they simply mint no row.
  #
  # - +urn_raw+: the upstream @n verbatim (edition tokens, malformations and
  #   all — canonical means canonical).
  # - +cts_work+: the work-level prefix (urn:cts:<namespace>:<tg>.<work>),
  #   the resolution key — upstream edition tokens are dropped here because
  #   the lexica cite editions we may not hold (LSJ cites perseus-grc1, the
  #   catalog holds grc2); resolution re-anchors to whatever in-catalog
  #   edition of the WORK exists, at query time.
  # - +citation+: the dot-joined citation suffix ("1.1"), nil for bare work
  #   references.
  # - +label+: the human-readable citation text.
  DictionaryCitation = Data.define(:urn_raw, :cts_work, :citation, :label) do
    def initialize(urn_raw:, cts_work:, citation:, label:)
      super(
        urn_raw: Model::Validation.present_string!(urn_raw, field: "urn_raw"),
        cts_work: cts_work.nil? ? nil : Model::Validation.present_string!(cts_work, field: "cts_work"),
        citation: citation.nil? ? nil : Model::Validation.present_string!(citation, field: "citation"),
        label: Model::Validation.present_string!(label, field: "label")
      )
    end
  end

  # One dictionary entry (P11-4): what the lexicon-tei parser yields and the
  # DictionaryLoader persists. NOT a passage — dictionaries are a separate
  # surface (improvements §1.3) with their own storage shape.
  #
  # - +entry_id+: the upstream entry id (@id, e.g. "n67485") — the stable
  #   upsert key within a dictionary.
  # - +key_raw+: the upstream @key verbatim (betacode in LSJ, homograph
  #   digits in Lewis & Short).
  # - +headword+: the Unicode NFC display form (betacode decoded).
  # - +headword_folded+: the lookup key, folded per conventions §9 with the
  #   entry's language — the same both-sides contract as lemma search, which
  #   is what lets a treebank lemma hit find its gloss.
  # - +gloss+: a short first gloss (best-effort; nil when the entry has none).
  # - +body+: the whole entry as structured plain text (sense labels on their
  #   own lines), Greek decoded, NFC.
  # - +citations+: DictionaryCitation values in entry order.
  DictionaryEntry = Data.define(:entry_id, :key_raw, :language, :headword,
                                :headword_folded, :gloss, :body, :citations) do
    def initialize(entry_id:, key_raw:, language:, headword:, headword_folded:, body:,
                   gloss: nil, citations: [])
      unless citations.is_a?(Array) && citations.all?(Nabu::DictionaryCitation)
        raise ValidationError, "citations must be an Array of Nabu::DictionaryCitation"
      end

      super(
        entry_id: Model::Validation.present_string!(entry_id, field: "entry_id"),
        key_raw: Model::Validation.present_string!(key_raw, field: "key_raw"),
        language: Model::Validation.language!(language),
        headword: Model::Validation.nfc_text!(headword, field: "headword"),
        headword_folded: Model::Validation.nfc_text!(headword_folded, field: "headword_folded"),
        gloss: gloss.nil? ? nil : Model::Validation.nfc_text!(gloss, field: "gloss"),
        body: Model::Validation.nfc_text!(body, field: "body"),
        citations: citations.freeze
      )
    end
  end
end
