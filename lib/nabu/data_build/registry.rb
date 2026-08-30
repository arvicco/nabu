# frozen_string_literal: true

require_relative "feature"
require_relative "actib_anchors_builder"
require_relative "aozora_gaiji_builder"
require_relative "cantigas_builder"
require_relative "char_postings_builder"
require_relative "document_dates_builder"
require_relative "form_lemma"
require_relative "hani_fold_builder"
require_relative "hiero_frequency_builder"
require_relative "kanripo_gaiji_builder"
require_relative "kyujitai_fold_builder"
require_relative "language_dossiers_builder"
require_relative "lect_assignments_builder"
require_relative "meter_builder"
require_relative "place_refs_builder"
require_relative "places_lpf_builder"
require_relative "segmentation_builder"
require_relative "sabellic_loans_builder"
require_relative "script_dossiers_builder"
require_relative "sign_table_builder"
require_relative "unikemet_signs_builder"
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
    # oldp1257 = Old Portuguese — Glottolog's languoid for the medieval
    # Galician-Portuguese stage (level: dialect under port1283; Glottolog
    # files historical Romance stages that way, cf. medi1250 Medieval Latin
    # under lati1261), checked 2026-08-02 (P56-2) against the same cone.
    # ISO 639-3 assigns NO code to Old Galician-Portuguese: roa-opt is the
    # BCP 47 collective-tag convention (roa Romance + opt) Wiktionary and
    # Nabu's catalog already use (D55-a), so the ISO static is honestly nil.
    # mul is ISO 639-3's SPECIAL code "Multiple languages" (scope S) — it
    # names content, not a languoid, so Glottolog carries no row for it
    # (checked 2026-08-11 against the same cone: no languages.csv row has
    # ISO639P3code mul) and the glottocode is honestly nil. The
    # cross-language corpus-layer datasets file under mul/ (№R-25, P73-0).
    LANGUAGES = {
      "jpn" => Language.new(id: "jpn", name: "Japanese", glottocode: "nucl1643", iso639p3: "jpn"),
      "san" => Language.new(id: "san", name: "Sanskrit", glottocode: "sans1269", iso639p3: "san"),
      "xct" => Language.new(id: "xct", name: "Classical Tibetan", glottocode: "clas1254", iso639p3: "xct"),
      "zho" => Language.new(id: "zho", name: "Chinese", glottocode: nil, iso639p3: "zho"),
      "lat" => Language.new(id: "lat", name: "Latin", glottocode: "lati1261", iso639p3: "lat"),
      "grc" => Language.new(id: "grc", name: "Ancient Greek", glottocode: "anci1242", iso639p3: "grc"),
      "lzh" => Language.new(id: "lzh", name: "Classical Chinese", glottocode: "lite1248", iso639p3: "lzh"),
      "sux" => Language.new(id: "sux", name: "Sumerian", glottocode: "sume1241", iso639p3: "sux"),
      "roa-opt" => Language.new(id: "roa-opt", name: "Old Galician-Portuguese",
                                glottocode: "oldp1257", iso639p3: nil),
      "mul" => Language.new(id: "mul", name: "Multiple languages", glottocode: nil, iso639p3: "mul"),
      # egyp1246 = Egyptian (Ancient), ISO egy, level: language — checked
      # 2026-08-11 (P73-9) against the same cone.
      "egy" => Language.new(id: "egy", name: "Egyptian (Ancient)", glottocode: "egyp1246",
                            iso639p3: "egy")
    }.freeze

    # The explicit feature census (no discovery magic — the sources.yml
    # doctrine). The rail landed first (P50-W1) with every feature :planned;
    # builder packets flip their feature to :available as each builder lands
    # (P50-W2 san/form-lemma, P50-W3 xct/wylie-fold, P50-W4 xct/verb-lemma,
    # P51-W5 xct/segmentation, P52-3 zho/hani-fold + jpn/aozora-gaiji,
    # P53-3 sux/value-signs, P55-4 xct/actib-anchors, P56-2
    # roa-opt/cantigas), and
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
      ),
      Feature.new(
        slug: "xct/actib-anchors", language: LANGUAGES.fetch("xct"),
        title: "ACTib ↔ Derge Kangyur anchor table (stable anchors for the segmented eKangyur)",
        # gold-DERIVED about the MAPPING only: the anchor derivation is
        # deterministic and its quality is measured in-band (nabu.eval);
        # ACTib's own seg/POS layers stay labeled automatic upstream.
        status: :available, tier: "gold-derived", anchoring: "urn+sha",
        inputs: %w[derge-kangyur actib], canonical_cones: %w[derge-kangyur actib],
        builder: ActibAnchorsBuilder,
        rationale: "nabu-data's first re-publication: ACTib's known weakness is that its seg/POS " \
                   "layers carry no stable anchors into their source etexts (an upstream update " \
                   "orphans the whole layer — the concept doc's prior-art verdict), so this " \
                   "dataset publishes the anchor table that fixes it — one row per derge-kangyur " \
                   "passage tying URN + Passage_SHA256 to ACTib's (volume, page, line), with the " \
                   "measured match census as the in-band eval and the near/partial divergences " \
                   "republished as a proofreading table. The mapping is deterministic and " \
                   "measured (gold-derived); ACTib's own annotation layers stay labeled " \
                   "automatic upstream, and their 800 MB content is never republished — " \
                   "consumers join the DOI-cited Zenodo artifact on the anchor key.",
        maintenance: "re-derive after a derge-kangyur or actib re-sync (the stale-ingest guard " \
                     "enforces freshness); every build re-measures the anchoring census into " \
                     "nabu.eval"
      ),
      Feature.new(
        slug: "roa-opt/cantigas", language: LANGUAGES.fetch("roa-opt"),
        title: "Cantigas Medievais Galego-Portuguesas — the Littera edition as structured tables " \
               "(verse lines, cantigas, authors, cancioneiro concordance)",
        # GOLD: a faithful structured projection of the field's critical
        # edition, published under the coordinator's written grant — the
        # curation is Littera's, carried losslessly.
        status: :available, tier: "gold", anchoring: "urn+sha",
        inputs: ["cantigas"], canonical_cones: ["cantigas"], builder: CantigasBuilder,
        rationale: "The first full-corpus re-publication: the complete secular lyric of medieval " \
                   "Galician-Portuguese — ~1,680 cantigas, ~34K verse lines from the three great " \
                   "cancioneiros — projected from the Littera critical edition " \
                   "(cantigas.fcsh.unl.pt) into the corpus's first machine-readable form (the " \
                   "scholarly database is superb and browser-only: no TEI, no export), under the " \
                   "coordinator's written any-use grant of 2026-07-27 with the project's own citation " \
                   "format riding every file — verse lines anchored urn+sha into the catalog, the " \
                   "cantiga/author registries, and the corpus-wide cancioneiro concordance parsed " \
                   "from the edition's manuscript sigla, with the citation-fidelity census " \
                   "(printed-number confirmations, refrain gaps, empty lines, the unattributed " \
                   "page) published in-band as nabu.eval.",
        maintenance: "re-derive after a cantigas re-sync (Littera is a living edition that " \
                     "corrects pages in place; the stale-ingest guard enforces freshness); every " \
                     "build re-derives the citation-fidelity census into nabu.eval"
      ),
      Feature.new(
        slug: "mul/lect-assignments", language: LANGUAGES.fetch("mul"),
        title: "Per-document historical-stage (lect) assignments across the multilingual catalog",
        # gold-DERIVED about the projection; the per-row basis column IS the
        # tier honesty — rule: rows read upstream period metadata, date-band
        # rows are inference over dates, and the consumer sees which is
        # which (the survey §2.3 posture).
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "document-urn",
        # No inputs/cones: the lect journal is the source of truth (the
        # aozora posture) — rows cite documents at URN grain, stable across
        # syncs by the conformance contract, so no cone sha is load-bearing;
        # the recipe embeds the published-slice sha256 instead. Contributing
        # corpora are cited in sources.bib per build.
        inputs: [], canonical_cones: [], builder: LectAssignmentsBuilder,
        rationale: "Publishes the per-document journal behind Nabu's lect facet — ~482K (URN, " \
                   "language-code) → historical-stage assignments (Old vs Neo-Babylonian, Ur III " \
                   "vs OB Sumerian, Vedic vs Classical Sanskrit, ...) with the basis and note " \
                   "in-band per row — the corpus-scale stage stratification no other project " \
                   "publishes; the id grammar and registry are public in nabu-lects (cited). " \
                   "License classes open+attribution only (nc/odbl/research_private slices " \
                   "excluded row-by-row, censused in nabu.eval); CC BY-SA 4.0 — the №R-24 " \
                   "carve-out dataset carrying the share-alike lanes (edh, aes, ...).",
        maintenance: "re-derive after journal-moving events (a sync wave re-running lect rules, " \
                     "new owner rulings, a rebuild) — the published-slice digest makes an " \
                     "unchanged journal a fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/place-refs", language: LANGUAGES.fetch("mul"),
        title: "Per-document place references across the multilingual catalog, gazetteer-ready",
        # gold-DERIVED: the claims are upstream assertions and registry
        # decisions carried mechanically; the per-row Basis column says
        # which is which (the survey §2.1 posture).
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "document-urn",
        # nabu-places is the ONE declared input: the Basis column cites its
        # decisions, so its cone sha rides the manifest and the stale-ingest
        # guard covers it. The doc→name pairs come from the catalog at URN
        # grain (the lect-assignments posture) — the recipe embeds the
        # published-slice sha256.
        inputs: ["nabu-places"], canonical_cones: ["nabu-places"], builder: PlaceRefsBuilder,
        rationale: "Publishes the compiled doc→place projection behind Nabu's places desk — " \
                   "~586K (URN, claim) rows, every historical ref spelling (verbatim upstream " \
                   "URLs, multi-URL fields, namespaced mints) folded to clean namespace:id form " \
                   "(pleiades:, tm:, geonames:, cigs:, np:) ready to join gazetteer geometry, " \
                   "with the verbatim upstream name and the Basis (upstream-asserted vs " \
                   "nabu-places-applied) in-band per row. License classes open+attribution only " \
                   "(the iip nc slice excluded row-by-row, censused in nabu.eval); CC BY-SA 4.0 " \
                   "— the №R-24 carve-out (edh/aes/elephantine/ceipom share-alike lanes and the " \
                   "conservative tm:-index inheritance ride inside it).",
        maintenance: "re-derive after place-moving events (a sync wave, a nabu-places registry " \
                     "sync + apply, a rebuild) — the published-slice digest makes an unchanged " \
                     "projection a fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/places-lpf", language: LANGUAGES.fetch("mul"),
        title: "Referenced places as Linked Places Format v1.3 + LP-TSV (the gazetteer-exchange shape)",
        # gold-DERIVED: a mechanical projection of held index/crosswalk/axis
        # data into the LPF shape; the fclass keyword mapping is the one
        # interpretive move and its unmapped remainder is censused in-band.
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "none",
        # The gazetteer cones ARE load-bearing here (titles and coordinates
        # republish from place_index), so all three ride the manifest under
        # the stale-ingest guard.
        inputs: %w[pleiades trismegistos cigs],
        canonical_cones: %w[pleiades trismegistos cigs], builder: PlacesLpfBuilder,
        rationale: "Publishes every place the catalog's documents reference as an LPF v1.3 " \
                   "FeatureCollection plus the LP-TSV v0.5 upload table (the World Historical " \
                   "Gazetteer's intake shapes): one Feature per claim (merging identities is " \
                   "entity resolution — the crosswalk rides as closeMatch links instead), " \
                   "attested spellings cited to their corpora, titles/coordinates from " \
                   "place_index (never invented), when-spans aggregated from document dates. " \
                   "The P69-2 GeoNames rider resolved NOT WANTED (recorded in the builder): " \
                   "geonames claims publish at document grain in mul/place-refs. CC BY-SA 4.0 " \
                   "— the TM lane's share-alike inheritance (№R-24).",
        maintenance: "re-derive after gazetteer syncs (pleiades/trismegistos/cigs — the " \
                     "stale-ingest guard enforces freshness) or place-moving catalog events; " \
                     "the collection digest in the recipe makes an unchanged projection a " \
                     "fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/document-dates", language: LANGUAGES.fetch("mul"),
        title: "Normalized document datings across the multilingual catalog, verbatim raw in-band",
        # gold-DERIVED: upstream-structured bounds carried mechanically
        # alongside band-inferred ones; Precision and Date_Raw are the
        # per-row honesty (the survey §2.4 posture).
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "document-urn",
        # The catalog dating projection is the source of truth at URN grain
        # (the lect-assignments posture); the recipe embeds the
        # published-slice sha256. №R-28 (regnal precision) re-derives in.
        inputs: [], canonical_cones: [], builder: DocumentDatesBuilder,
        rationale: "Publishes the dating layer behind Nabu's timeline — ~700K dated documents " \
                   "as normalized signed year spans (negative = BCE) with the VERBATIM upstream " \
                   "dating string riding every row, so each normalization is checkable against " \
                   "its source. License classes open+attribution only — the nc slices AND the " \
                   "rundata ODbL lane (a copyleft class of its own) are excluded row-by-row, " \
                   "censused in nabu.eval; CC BY-SA 4.0 — the №R-24 carve-out carrying the " \
                   "share-alike lanes (edh, tla-hf, aes, ...).",
        maintenance: "re-derive after dating-moving events (sync waves, infer-dates rule " \
                     "changes — the №R-28 regnal upgrade lands here on its next build); the " \
                     "published-slice digest makes an unchanged projection a fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/char-postings", language: LANGUAGES.fetch("mul"),
        title: "Han character × corpus doc-frequency census (the graded-reading substrate)",
        # gold-DERIVED: a mechanical census over ingested corpora — no
        # interpretation, no sampling.
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "none",
        # The fulltext census is the source of truth (derived from the
        # whole ingested corpus set — no single cone sha is load-bearing);
        # the recipe embeds the published-slice sha256.
        inputs: [], canonical_cones: [], builder: CharPostingsBuilder,
        rationale: "Publishes the char_postings census behind Nabu's Han cards and graded-" \
                   "reading lane — one row per (character, corpus) with the attesting document " \
                   "count, spanning lzh/jpn/otb/ojp collections (hence mul/ — the naming the " \
                   "survey left TBD, settled here). The Edubba P-1 rider's character half: " \
                   "frequency data any school can consume, derived from Nabu's ingested " \
                   "corpora only (Edubba's own TSVs are NEVER an input — the circularity " \
                   "guard). nc slices (cbeta, ud, e84000, openiti) excluded row-by-row, " \
                   "censused; CC BY-SA 4.0 — the kanripo lane's share-alike grant (№R-24).",
        maintenance: "re-derive after CJK-lane syncs (the census rebuilds with the fulltext " \
                     "index); the published-slice digest makes an unchanged census a " \
                     "fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/language-dossiers", language: LANGUAGES.fetch("mul"),
        title: "Curated language dossiers — the human-written name/family/context per language",
        # CURATED: hand-authored prose, not a mechanical derivation — the
        # honest tier for the overlay layer (№R-47/48).
        status: :available, tier: "curated", license: "CC-BY-SA-4.0",
        anchoring: "language-code",
        # The local dossier files are the source of truth (own authorship, no
        # canonical cone); the recipe embeds the published-slice sha256.
        inputs: [], canonical_cones: [], builder: LanguageDossiersBuilder,
        rationale: "Fixes the replicability gap the curated dossiers left behind: the hand-" \
                   "authored name/family/context lanes lived only in the originating instance's " \
                   "local/ shelf, so a fresh install saw bare language codes. Published as an " \
                   "overlay (re-consumed via `nabu sync nabu-data`), every install composes the " \
                   "same curated context beneath its live holdings and lect ladder. Only the " \
                   "non-derivable curated layer travels — section accretions (iecor varieties, " \
                   "corpus witnesses, the lect stage ladder) are excluded, each install rebuilds " \
                   "them from its own synced sources. CC BY-SA 4.0: ~71% of the context prose is " \
                   "Wikipedia-derived (share-alike), so the whole dataset inherits it (№R-48); " \
                   "the Wikipedia-derived share is censused in nabu.eval, and personal notes ride " \
                   "the private `nabu note` layer, never here.",
        maintenance: "re-derive after curating dossiers (owner front-matter/context edits, the " \
                     "coming `nabu note` language layer); the published-slice digest makes an " \
                     "unchanged dossier corpus a fingerprint no-op"
      ),
      Feature.new(
        slug: "mul/script-dossiers", language: LANGUAGES.fetch("mul"),
        title: "Curated script dossiers — the human-written context per writing system",
        # CURATED: hand-authored prose (own authorship, no Wikipedia text —
        # hence plain CC BY, unlike language-dossiers' inherited BY-SA).
        status: :available, tier: "curated", license: "CC-BY-4.0",
        anchoring: "script-tag",
        # config/script_dossiers.yml is the source of truth (the wylie-fold
        # pattern: git-shared config, dataset = its public mirror); the
        # recipe embeds the published-slice sha256.
        inputs: [], canonical_cones: [], builder: ScriptDossiersBuilder,
        rationale: "The char desk's script layer (P86, №R-49): every writing system in the " \
                   "registry's scripts table gets a human-written dossier — what the script " \
                   "IS, and the desk conventions a working library actually uses for it " \
                   "(transliteration surfaces, fold tables, honest gaps). Unlike the language " \
                   "dossiers (curated per-instance in local/), the source of truth is the " \
                   "git-shared config fact file, so every install answers identically and this " \
                   "dataset is the citable public mirror. The suite's drift guard pins dossier " \
                   "tags to the nabu-lects scripts table, so registry mints and dossiers " \
                   "cannot diverge silently.",
        maintenance: "re-derive after editing config/script_dossiers.yml (a new registry " \
                     "script mint forces a dossier via the drift guard); the published-slice " \
                     "digest makes an unchanged table a fingerprint no-op"
      ),
      Feature.new(
        slug: "sux/sign-table", language: LANGUAGES.fetch("sux"),
        title: "Compiled cuneiform sign cards — OSL identity, concordances, attestation counts",
        # gold-DERIVED: a mechanical join of CC0 curation plus a measured
        # counting pass whose scope is stated and censused in-band.
        status: :available, tier: "gold-derived", anchoring: "none",
        inputs: ["osl"], canonical_cones: ["osl"], builder: SignTableBuilder,
        rationale: "The per-sign reference card compiled from what sux/value-signs flattens " \
                   "value-wise: one row per top-level OSL sign with codepoints, every print-" \
                   "list number, the CDLI reading concordance, AND per-source attestation doc-" \
                   "counts over the open cuneiform corpora (cdli/oracc/tlhdig — the Edubba P-1 " \
                   "rider's sign half, true sign-counts at last). Counting scope stated and " \
                   "censused (value/logogram tokens; compounds out); nc lanes (etcsl, ebl) " \
                   "have NO count columns, so no nc contribution can hide in an integer — the " \
                   "lemma_frequencies lesson. Core CC BY 4.0; the Wiktionary/aes BY-SA sense " \
                   "lanes are deliberately deferred to a later sidecar dataset so the core " \
                   "stays BY (survey §2.6).",
        maintenance: "re-derive after `nabu sync osl` or cuneiform-lane syncs (counts move " \
                     "with the catalog); the counts digest in the recipe makes an unchanged " \
                     "state a fingerprint no-op"
      ),
      Feature.new(
        slug: "egy/unikemet-signs", language: LANGUAGES.fetch("egy"),
        title: "The Egyptian sign spine — Unikemet codepoints with Gardiner codes and tool concordances",
        # gold-DERIVED: a lossless verbatim flattening of the Unicode
        # consortium's curated data file.
        status: :available, tier: "gold-derived", anchoring: "none",
        inputs: ["unikemet"], canonical_cones: ["unikemet"], builder: UnikemetSignsBuilder,
        rationale: "Flattens Unikemet.txt to one row per encoded Egyptian hieroglyph — the " \
                   "Gardiner-style kEH_Cat code, the original Hieroglyphica-era kEH_UniK code, " \
                   "core/legacy status, description, functions, sound values, and the JSesh/" \
                   "Hieroglyphica/IFAO concordances every Egyptological tool joins on (the " \
                   "same spine Nabu's hiero card and the Edubba overlay key against). Every " \
                   "cell verbatim; absent tags stay empty. Permissive input (Unicode License " \
                   "V3) → clean CC BY 4.0.",
        maintenance: "re-derive after `nabu sync unikemet` (upstream moves at annual Unicode " \
                     "releases); mechanical, no review needed beyond spot-checks"
      ),
      Feature.new(
        slug: "egy/hiero-frequency", language: LANGUAGES.fetch("egy"),
        title: "Egyptian hieroglyph frequencies — Gardiner codes censused from AES, per subcorpus",
        # gold-DERIVED: a mechanical census over TLA gold annotation — no
        # interpretation, no sampling.
        status: :available, tier: "gold-derived", license: "CC-BY-SA-4.0",
        anchoring: "none",
        inputs: ["aes"], canonical_cones: [],
        builder: HieroFrequencyBuilder,
        rationale: "The sign-learning survey's P-1 Egyptian half (P77-r17): Gardiner-code " \
                   "token and document frequencies censused from AES's per-word hiero_inventar " \
                   "annotations, overall and per subcorpus (frequency is genre-dependent — " \
                   "Pyramid Texts vs Amarna letters vs medical papyri). To the survey's " \
                   "knowledge the first public hieroglyph frequency list anywhere. Joins " \
                   "egy/unikemet-signs on the Gardiner column. CC BY-SA 4.0 — derived from " \
                   "AES's share-alike grant, the №R-24/D51-a carve-out (the char-postings " \
                   "precedent).",
        maintenance: "re-derive after `nabu sync aes`; the doc-attestation digest in the " \
                     "recipe makes an unchanged census a fingerprint no-op"
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
