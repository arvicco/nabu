# frozen_string_literal: true

require_relative "feature"
require_relative "form_lemma"
require_relative "segmentation_builder"
require_relative "verb_lemma_builder"
require_relative "wylie_fold_builder"

module Nabu
  module DataBuild
    # The languages.csv statics, one entry per language the registered
    # features publish. Verified against the owner's Glottolog cone
    # (canonical/cldf-spine/glottolog/languages.csv, checked 2026-07-28):
    # sans1269 = Sanskrit (ISO san), clas1254 = Classical Tibetan (ISO xct).
    LANGUAGES = {
      "san" => Language.new(id: "san", name: "Sanskrit", glottocode: "sans1269", iso639p3: "san"),
      "xct" => Language.new(id: "xct", name: "Classical Tibetan", glottocode: "clas1254", iso639p3: "xct")
    }.freeze

    # The explicit feature census (no discovery magic — the sources.yml
    # doctrine). The rail landed first (P50-W1) with every feature :planned;
    # builder packets flip their feature to :available as each builder lands
    # (P50-W2 san/form-lemma, P50-W3 xct/wylie-fold, P50-W4 xct/verb-lemma,
    # P51-W5 xct/segmentation), and `nabu data build` refuses the
    # still-planned politely. The doc table in docs/nabu-data.md is
    # drift-guarded against this list.
    REGISTRY = [
      Feature.new(
        slug: "san/form-lemma", language: LANGUAGES.fetch("san"),
        title: "Sanskrit form→lemma table derived from DCS gold annotations",
        status: :available, tier: "gold-derived", anchoring: "none",
        inputs: ["dcs"], canonical_cones: ["dcs"], builder: FormLemma,
        rationale: "Bridges inflected surface forms (and unsandhied padapāṭha forms) to lemmas " \
                   "using only human-annotated gold data — powers dictionary-headword lookup for " \
                   "query expansion (the successor to Nabu's rule-generated Sanskrit stem variants).",
        maintenance: "re-derive after each dcs sync (upstream updates infrequently); mechanical, " \
                     "no review needed beyond spot-checks"
      ),
      Feature.new(
        slug: "xct/wylie-fold", language: LANGUAGES.fetch("xct"),
        title: "Tibetan script ↔ EWTS (Wylie) neutralization rule table",
        status: :available, tier: "gold", anchoring: "none",
        inputs: [], canonical_cones: [], # own authorship + Unicode character data
        rationale: "A hand-curated transliteration rule table letting Tibetan-script and " \
                   "Wylie-romanized text meet in one query space — doubles as the source for " \
                   "Nabu's generated Tibetan transcoder module.",
        maintenance: "on rule corrections only; each change re-derives the Tibetan shelves " \
                     "(fold modules are fingerprinted derivation inputs)",
        builder: WylieFoldBuilder
      ),
      Feature.new(
        slug: "xct/verb-lemma", language: LANGUAGES.fetch("xct"),
        title: "Tibetan verb stem → paradigm-lemma map (from the Tibetan Verb Database)",
        status: :available, tier: "gold-derived", anchoring: "none",
        inputs: ["tibetan-verbs"], canonical_cones: ["tibetan-verbs"],
        rationale: "Maps the 2,491 TVD stem tuples (present/past/future/imperative, grammarians' " \
                   "disagreements kept uncollapsed) to a paradigm lemma, enabling verb-form-aware " \
                   "lookup across Classical Tibetan. The table half only: the anchored layer over " \
                   "the canon is deferred behind xct/segmentation.",
        maintenance: "re-derive after tibetan-verbs sync; upstream is stable (CC0)",
        builder: VerbLemmaBuilder
      ),
      Feature.new(
        slug: "xct/segmentation", language: LANGUAGES.fetch("xct"),
        title: "Segmented Classical Tibetan, curated slice (eval'd against SOAS gold)",
        status: :available, tier: "silver", anchoring: "passage-urn",
        inputs: %w[derge-kangyur soas-tibetan], canonical_cones: %w[derge-kangyur soas-tibetan],
        rationale: "Tsheg-bar/word segmentation over a curated Derge slice with the segmenter's " \
                   "error rate measured against the SOAS gold corpus and published in-band — the " \
                   "calibration ground for any full-canon layer.",
        maintenance: "re-derive on canonical text revisions or segmenter upgrades; each release " \
                     "republishes the eval number",
        builder: SegmentationBuilder
      )
    ].freeze

    class << self
      # The census the CLI serves — a method, not the bare constant, so tests
      # can swap in a rigged census (the with_config singleton-swap pattern).
      def features = REGISTRY

      # slug -> Feature, nil when unregistered (the CLI words the refusal).
      def feature(slug) = features.find { |feature| feature.slug == slug }
    end
  end
end
