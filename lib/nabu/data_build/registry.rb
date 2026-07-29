# frozen_string_literal: true

require_relative "feature"
require_relative "aozora_gaiji_builder"
require_relative "form_lemma"
require_relative "hani_fold_builder"
require_relative "segmentation_builder"
require_relative "sabellic_loans_builder"
require_relative "verb_lemma_builder"
require_relative "wylie_fold_builder"

module Nabu
  module DataBuild
    # The languages.csv statics, one entry per language the registered
    # features publish. Verified against the owner's Glottolog cone
    # (canonical/cldf-spine/glottolog/languages.csv, checked 2026-07-28;
    # re-checked 2026-07-29 for P52-3/P52-5): sans1269 = Sanskrit (ISO san),
    # clas1254 = Classical Tibetan (ISO xct), nucl1643 = Japanese (ISO jpn),
    # lati1261 = Latin (ISO lat).
    # zho is an ISO 639-3 MACROLANGUAGE: Glottolog deliberately assigns
    # macrolanguages no glottocode (the cone carries no row with ISO zho;
    # the nearest node, sini1245 Sinitic, is a family — claiming it would
    # misstate the level), so the static is honestly nil. zho is the same
    # pan-CJK macro tag Nabu's unihan shelf files under
    # (Adapters::Unihan::LANGUAGE).
    LANGUAGES = {
      "jpn" => Language.new(id: "jpn", name: "Japanese", glottocode: "nucl1643", iso639p3: "jpn"),
      "san" => Language.new(id: "san", name: "Sanskrit", glottocode: "sans1269", iso639p3: "san"),
      "xct" => Language.new(id: "xct", name: "Classical Tibetan", glottocode: "clas1254", iso639p3: "xct"),
      "zho" => Language.new(id: "zho", name: "Chinese", glottocode: nil, iso639p3: "zho"),
      "lat" => Language.new(id: "lat", name: "Latin", glottocode: "lati1261", iso639p3: "lat")
    }.freeze

    # The explicit feature census (no discovery magic — the sources.yml
    # doctrine). The rail landed first (P50-W1) with every feature :planned;
    # builder packets flip their feature to :available as each builder lands
    # (P50-W2 san/form-lemma, P50-W3 xct/wylie-fold, P50-W4 xct/verb-lemma,
    # P51-W5 xct/segmentation, P52-3 zho/hani-fold + jpn/aozora-gaiji), and
    # `nabu data build` refuses the still-planned politely. The doc table in
    # docs/nabu-data.md is drift-guarded against this list.
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
      ),
      Feature.new(
        slug: "zho/hani-fold", language: LANGUAGES.fetch("zho"),
        title: "Han traditional↔simplified↔z-variant fold table (from Unihan)",
        # gold-DERIVED, not gold: a mechanical, deterministic resolution of
        # upstream-declared variant relations — the xct/verb-lemma posture;
        # "gold" stays reserved for own-authored/hand-curated tables.
        status: :available, tier: "gold-derived", anchoring: "none",
        inputs: ["unihan"], canonical_cones: ["unihan"], builder: HaniFoldBuilder,
        rationale: "The 6,050-pair Han fold resolved conservatively from Unihan's declared " \
                   "kTraditionalVariant/kSimplifiedVariant/kZVariant relations — the table that " \
                   "lets simplified-script queries reach the traditional-script canon " \
                   "(kanripo/cbeta), the same resolution `rake fold:hani` compiles into Nabu::Hani; " \
                   "every ambiguous fold is refused and published per-row with its reason, " \
                   "because the refusal census IS the curation.",
        maintenance: "re-derive after each unihan sync (upstream /latest/ moves at annual Unicode " \
                     "releases); a changed table also re-derives Nabu's own Han fold via " \
                     "`rake fold:hani` — the conventions §9 rebuild caveat applies"
      ),
      Feature.new(
        slug: "jpn/aozora-gaiji", language: LANGUAGES.fetch("jpn"),
        title: "Aozora Bunko gaiji composition census with derived IDS lane",
        # No inputs/cones: the checked-in census TSV is the source of truth
        # (the wylie-fold precedent — the recipe embeds its sha256); the
        # corpus linkage is provenance, not a cone. See AozoraGaijiBuilder.
        status: :available, tier: "gold", anchoring: "none",
        inputs: [], canonical_cones: [], builder: AozoraGaijiBuilder,
        rationale: "The census of composition formulas Aozora Bunko transcribers wrote for glyphs " \
                   "Unicode cannot encode (582 distinct formulas, 1,129 occurrences at the " \
                   "2026-07-22 snapshot), each with its occurrence count and resolution status, " \
                   "plus the 244-entry IDS lane a conservative structural grammar can prove — " \
                   "refusals classified per formula, never guessed: the gaiji display-honesty " \
                   "ladder, published.",
        maintenance: "re-census on the owner's schedule as the corpus grows (the checked-in TSV " \
                     "header carries the snapshot provenance); each re-census re-fingerprints the " \
                     "dataset through the recipe's embedded sha256"
      ),
      Feature.new(
        slug: "lat/sabellic-loans", language: LANGUAGES.fetch("lat"),
        title: "Sabellic → Latin loanword table (en.wiktionary curation)",
        status: :available, tier: "gold", license: "CC-BY-SA-4.0", anchoring: "none",
        inputs: [], canonical_cones: [], # own curation: config/sabellic_loans.yml
        rationale: "Flattens the hand-curated Sabellic (Oscan/Umbrian/Sabine) → Latin loan rows — " \
                   "85 Latin lemmas with borrowed/derived relation flags and the Old Italic etyma " \
                   "en.wiktionary cites — into one reusable table; the same curation powers Nabu's " \
                   "sabellic-osc/xum/sbv dictionary shelves and their loan-flagged etymology edges. " \
                   "CC BY-SA (the Wiktionary share-alike grant — owner ruling D51-a).",
        maintenance: "on re-curation of config/sabellic_loans.yml only (a deliberate repo change, " \
                     "not a sync); each curation change re-fingerprints the dataset via the " \
                     "recipe's embedded file sha",
        builder: SabellicLoansBuilder
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
