# frozen_string_literal: true

module Nabu
  # The gloss-lines test rig: the four token-gloss sources
  # (Query::TokenGlosses) loaded from their REAL fixtures through the real
  # Loader — BHSA's English (Hebrew + Aramaic), achemenet's English over
  # Akkadian, aes' German over Egyptian, tlhdig's German over Hittite and
  # Akkadian.
  module TestSupport
    GLOSS_CORPUS = {
      "bhsa" => "Nabu::Adapters::Bhsa",
      "aes" => "Nabu::Adapters::Aes",
      "achemenet" => "Nabu::Adapters::Achemenet",
      "tlhdig" => "Nabu::Adapters::Tlhdig"
    }.freeze

    # Load the four sources into +catalog+; returns {slug => Store::Source}.
    def self.load_gloss_corpus(catalog)
      GLOSS_CORPUS.to_h do |slug, class_name|
        klass = Object.const_get(class_name)
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: class_name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: catalog, source: source).load_from(klass.new, workdir: fixtures(slug), full: true)
        [slug, source]
      end
    end
  end
end
