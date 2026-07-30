# frozen_string_literal: true

require_relative "feature"
require_relative "aozora_gaiji_builder"
require_relative "form_lemma"
require_relative "hani_fold_builder"
require_relative "kanripo_gaiji_builder"
require_relative "kyujitai_fold_builder"
require_relative "meter_builder"
require_relative "segmentation_builder"
require_relative "sabellic_loans_builder"
require_relative "value_signs_builder"
require_relative "verb_lemma_builder"
require_relative "wylie_fold_builder"

module Nabu
  module DataBuild
    # The languages.csv statics, one entry per language the registered
    # features publish. Verified against the owner's Glottolog cone
    # (canonical/cldf-spine/glottolog/languages.csv, checked 2026-07-28;
    # re-checked 2026-07-29 for P52-3/P52-5): sans1269 = Sanskrit (ISO san),
    # clas1254 = Classical Tibetan (ISO xct), nucl1643 = Japanese (ISO jpn),
    # lati1261 = Latin (ISO lat), anci1242 = Ancient Greek (ISO grc).
    # zho is an ISO 639-3 MACROLANGUAGE: Glottolog deliberately assigns
    # macrolanguages no glottocode (the cone carries no row with ISO zho;
    # the nearest node, sini1245 Sinitic, is a family — claiming it would
    # misstate the level), so the static is honestly nil. zho is the same
    # pan-CJK macro tag Nabu's unihan shelf files under
    # (Adapters::Unihan::LANGUAGE).
    # lite1248 = Classical Chinese (ISO lzh), checked 2026-07-29 (P52-4).
    # sume1241 = Sumerian (ISO sux, level: language — an isolate, no
    # family), checked 2026-07-29 (P53-3) against the same cone.
    LANGUAGES = {
      "jpn" => Language.new(id: "jpn", name: "Japanese", glottocode: "nucl1643", iso639p3: "jpn"),
      "san" => Language.new(id: "san", name: "Sanskrit", glottocode: "sans1269", iso639p3: "san"),
      "xct" => Language.new(id: "xct", name: "Classical Tibetan", glottocode: "clas1254", iso639p3: "xct"),
      "zho" => Language.new(id: "zho", name: "Chinese", glottocode: nil, iso639p3: "zho"),
      "lat" => Language.new(id: "lat", name: "Latin", glottocode: "lati1261", iso639p3: "lat"),
      "grc" => Language.new(id: "grc", name: "Ancient Greek", glottocode: "anci1242", iso639p3: "grc"),
      "lzh" => Language.new(id: "lzh", name: "Classical Chinese", glottocode: "lite1248", iso639p3: "lzh"),
      "sux" => Language.new(id: "sux", name: "Sumerian", glottocode: "sume1241", iso639p3: "sux")
    }.freeze

    # The explicit feature census (no discovery magic — the sources.yml
    # doctrine). The rail landed first (P50-W1) with every feature :planned;
    # builder packets flip their feature to :available as each builder lands
    # (P50-W2 san/form-lemma, P50-W3 xct/wylie-fold, P50-W4 xct/verb-lemma,
    # P51-W5 xct/segmentation, P52-3 zho/hani-fold + jpn/aozora-gaiji,
    # P53-3 sux/value-signs), and
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
      ),
      Feature.new(
        slug: "grc/meter", language: LANGUAGES.fetch("grc"),
        title: "Greek metrical scansions (Hypotactic) anchored to Perseus CTS passages",
        status: :available, tier: "gold-derived", anchoring: "passage-urn",
        # The anchor corpora are DECLARED inputs on purpose: Passage_SHA256
        # anchors are only honest against the perseus-greek / first1k-greek
        # trees the catalog last ingested, so the stale-ingest guard must
        # cover all three cones. No BY-SA text enters the dataset —
        # Primary_Text is Hypotactic's own CC BY bytes (MeterBuilder's
        # class note); the corpora contribute URNs and shas, which are facts.
        inputs: %w[hypotactic perseus-greek first1k-greek],
        canonical_cones: %w[hypotactic perseus-greek first1k-greek],
        rationale: "Publishes D. Chamberlain's Hypotactic scansions (CC BY 4.0) as rows citable " \
                   "at urn:cts:greekLit grain: upstream has no citation scheme (work = filename, " \
                   "line = file order), so the URN + Passage_SHA256 anchoring Nabu derives by " \
                   "exact folded-text match IS the added value — with the matched/unmatched " \
                   "census published in-band and the row text taken from Hypotactic's own bytes, " \
                   "never the CC BY-SA Perseus text.",
        maintenance: "re-derive after hypotactic / perseus-greek / first1k-greek syncs (the " \
                     "stale-ingest guard enforces freshness); each release republishes the " \
                     "resolution census in nabu.eval",
        builder: MeterBuilder
      ),
      Feature.new(
        slug: "jpn/kyujitai-fold", language: LANGUAGES.fetch("jpn"),
        title: "Japanese kyūjitai↔shinjitai reform-pair census (Unihan jinmeiyō + KANJIDIC2 jōyō lanes)",
        status: :available, tier: "gold", license: "CC-BY-SA-4.0", anchoring: "none",
        inputs: %w[unihan edrdg], canonical_cones: %w[unihan edrdg], builder: KyujitaiFoldBuilder,
        rationale: "The two-lane old↔new kanji pair table (Unihan kJinmeiyoKanji reform pairs + " \
                   "KANJIDIC2 jōyō-target variant edges, reform merges admitted, refusals censused) " \
                   "rendered through the same resolution seam `rake fold:jpn` compiles into Nabu::Jpn " \
                   "— one seam, two consumers. BY-SA: the load-bearing KANJIDIC2 lane is EDRDG " \
                   "share-alike (CC BY-SA 4.0).",
        maintenance: "re-derive after each unihan/edrdg sync (EDRDG rebuilds nightly, Unihan " \
                     "annually); regenerate together with `rake fold:jpn` so the shipped fold " \
                     "module and the dataset never drift"
      ),
      Feature.new(
        slug: "lzh/kanripo-gaiji", language: LANGUAGES.fetch("lzh"),
        title: "Kanripo gaiji display ladder — faithful/IDS/substitute resolutions for &KR…; references",
        status: :available, tier: "gold", license: "CC-BY-SA-4.0", anchoring: "none",
        inputs: [], canonical_cones: [], # own curation over KR-Gaiji, pinned to the charlist commit
        rationale: "The hand-curated resolution ladder for the Kanseki Repository's not-yet-encoded " \
                   "character references (427 faithful codepoints, 562 labeled substitutes, the IDS " \
                   "lane empty by census, everything else an honest ⬚ placeholder) — the same three " \
                   "TSVs Nabu's `--display reading` mode loads for lzh kanripo passages. BY-SA: " \
                   "curated from KR-Gaiji's charlist under the kanripo org grant (CC BY-SA 4.0).",
        maintenance: "re-curate by hand after a `nabu sync kr-gaiji` advances charlist.org.txt (the " \
                     "P38-1 procedure); the curation is pinned to the charlist commit its file " \
                     "headers record, deliberately never auto-derived",
        builder: KanripoGaijiBuilder
      ),
      Feature.new(
        slug: "sux/value-signs", language: LANGUAGES.fetch("sux"),
        title: "Cuneiform value→sign table from the Oracc Sign List (readings, codepoints, concordances)",
        # GOLD: the OSL is the field's hand-curated sign registry (Veldhuis &
        # Tinney), and this build is a lossless flattening of its curation.
        status: :available, tier: "gold", anchoring: "none",
        inputs: ["osl"], canonical_cones: ["osl"], builder: ValueSignsBuilder,
        rationale: "Flattens the Oracc Sign List (ex-OGSL, Veldhuis & Tinney, CC0 — the field's " \
                   "hand-curated sign registry) to one row per (value, sign) pair — OSL-spelled " \
                   "readings with stable @oid interop keys, Unicode codepoints (absence kept " \
                   "honest), value-level deprecation flags and in-band ambiguity, plus " \
                   "signs.csv/concordances.csv sidecars (variant forms, MZL/LAK/ABZL print-list " \
                   "numbers) — the table that upgrades Edubba's frequency instrument from " \
                   "value-counts to true sign-counts. The slug leads sux (Sumerian); the ~55 " \
                   "%akk-qualified readings ride the Language_Qualifier column — the scope call " \
                   "is stated in the dataset README.",
        maintenance: "re-derive after each `nabu sync osl` (rolling master, no tags — a re-sync " \
                     "is an owner call; the stale-ingest guard enforces freshness); mechanical, " \
                     "no review needed beyond spot-checks"
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
