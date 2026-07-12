# frozen_string_literal: true

require_relative "../normalize"

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
  #     annotations: { "lemma" => "μῆνις" }, # JSON-serializable, default {}
  #     sequence: 0                          # non-negative order within document
  #   )
  #
  # text_normalized — the search form ("μηνιν αειδε θεα" above) — is minted
  # HERE by default, via Normalize.search_form with the passage's own
  # language: construction is the one folding boundary (P6-4), so the
  # per-language rule table lives in exactly one place instead of being
  # duplicated across adapters. An adapter may pass an explicit value ONLY
  # as Normalize.search_form over a documented, deterministic derivation of
  # the pristine text that is recomputable from the stored passage alone
  # (conventions §9 — ccmh-txt's diplomatic line-break rejoining is the one
  # case); the conformance suite pins every adapter's output to the minted
  # form of its declared derivation (default: the pristine text). Tests and
  # store plumbing may supply an explicit value, validated as usual.
  Passage = Data.define(:urn, :language, :text, :text_normalized, :annotations, :sequence) do
    def initialize(urn:, language:, text:, sequence:, text_normalized: nil, annotations: {})
      language = Model::Validation.language!(language)
      text = Model::Validation.nfc_text!(text, field: "text")
      text_normalized ||= Normalize.search_form(text, language: language)
      super(
        urn: Model::Validation.urn!(urn),
        language: language,
        text: text,
        text_normalized: Model::Validation.nfc_text!(text_normalized, field: "text_normalized"),
        annotations: Model::Validation.json_hash!(annotations, field: "annotations"),
        sequence: Model::Validation.sequence!(sequence)
      )
    end
  end
end
