# frozen_string_literal: true

module Nabu
  # The citable unit (architecture §3): a CTS line/section, a treebank
  # sentence, an ad-hoc page. Immutable, valid by construction, and free of
  # storage concerns — document linkage happens at persistence time, which is
  # why there is no document_id here.
  #
  #   Nabu::Passage.new(
  #     urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1",
  #     language: "grc",
  #     text: "μῆνιν ἄειδε θεὰ",          # NFC UTF-8 — non-NFC is rejected
  #     text_normalized: "μηνιν αειδε θεα", # search form, also NFC
  #     annotations: { "lemma" => "μῆνις" }, # JSON-serializable, default {}
  #     sequence: 0                          # non-negative order within document
  #   )
  Passage = Data.define(:urn, :language, :text, :text_normalized, :annotations, :sequence) do
    def initialize(urn:, language:, text:, text_normalized:, sequence:, annotations: {})
      super(
        urn: Model::Validation.urn!(urn),
        language: Model::Validation.language!(language),
        text: Model::Validation.nfc_text!(text, field: "text"),
        text_normalized: Model::Validation.nfc_text!(text_normalized, field: "text_normalized"),
        annotations: Model::Validation.json_hash!(annotations, field: "annotations"),
        sequence: Model::Validation.sequence!(sequence)
      )
    end
  end
end
