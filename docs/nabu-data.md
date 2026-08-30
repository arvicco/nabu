# The nabu-data production rail

The producer-side contract for [nabu-data](https://github.com/arvicco/nabu-data)
— the public repository of derived datasets (CSV + Frictionless Data Package
manifests) built from Nabu's canonical corpora and enrichments. The split is
absolute: **nabu-data is 100% passive data; ALL production code lives here**,
in `lib/nabu/data_build/`, driven by the `nabu data` command family. The rail
writes files into the owner's nabu-data working clone and **never runs git
operations there** — reviewing, committing, and pushing the public repo is the
owner's explicit act. Being producer-only, `lib/nabu/data_build/` is excluded
from the shared derivation-core digest (owner ruling D50-b): it cannot change
any stored row, so its changes never dirty source fingerprints — pinned by a
purity guard test (no derivation code references `DataBuild`; the rail may
consume the rest of Nabu freely).

## The commands

```
nabu data list                                  # the self-documentation surface
nabu data build <lang>/<feature> --into PATH    # build one dataset (files only)
nabu data build --all --into PATH               # rebuild every available dataset
```

`build --all` sweeps the registry in order: available features build,
planned ones are skipped by name, and a failing feature is reported
without aborting the sweep (census-and-continue) — the exit is nonzero
iff any failed. The stale-ingest guard applies per feature as always.

`data list` documents every artifact the rail is able to produce — slug,
status (available | planned), title, language, tier, license, anchoring
kind, input sources, the rationale for the dataset's existence, and the
recommended maintenance/periodicity — and, for every available feature,
the **exact copy-paste command sequence** (input syncs chained into the build; the
stale-ingest guard makes the syncs mandatory anyway). Planned features are
listed too: the census is the roadmap.

`data build` runs the feature's builder and writes the dataset directory
`PATH/<lang>/<feature>/`, prints an honest summary (rows written, files,
derivation fingerprint), and stops. It refuses, by name: a `planned` feature
(builder not yet landed), an unknown slug (listing the valid ones), a missing
canonical input (with a sync hint), and a **dirty git cone** — a canonical
tree with local modifications has no honest sha, and refusing beats
misdescribing (the `DerivationFingerprint` weak-identity doctrine, hardened
from "never skip" to "never publish").

**The stale-ingest guard** (owner ruling D50-a): catalog-reading builders
derive rows from the last *ingest* of an input source, while the manifest
records the cone's *current* sha — so if `canonical/<slug>` advanced without
a re-ingest, the dataset would cite bytes its rows were not derived from.
The build therefore refuses, hard, whenever a declared input's recorded
last-ingest identity (`sources.last_ingest_identity`, written by `nabu sync`
and both rebuild flavors alike) does not equal the cone's current identity —
naming the source, both identities, and the remedy (`nabu sync <slug>`, or
`nabu sync <slug> --parse-only` for a no-network re-load). The check is
uniform across all declared inputs, whatever the builder's read path, and
there is deliberately **no `--force`**: drifted provenance is never
publishable. "Run sync before building" is no longer advice — it is
enforced. On a box with no catalog nothing is guarded (there are no catalog
rows to drift); a builder that needs the catalog still refuses on its own.

## The Feature record

Features are registered explicitly in `Nabu::DataBuild::REGISTRY`
(`lib/nabu/data_build/registry.rb`) — no discovery magic. Each is a
valid-by-construction `Feature` value:

| field | meaning |
| --- | --- |
| `slug` | `<lang>/<feature>`, lower-case hyphen-joined segments; also the dataset directory path. Single-language datasets lead with the language code; datasets spanning the whole catalog file under `mul/` — ISO 639-3's special code "Multiple languages" (№R-25, P73-0) |
| `language` | a `Language` value: Nabu's code + the `languages.csv` statics (Name, Glottocode, ISO 639-3) |
| `title` | the dataset's human title (the manifest `title`) |
| `status` | `:available` (builder landed) or `:planned` (build refuses) |
| `tier` | provenance tier: `gold`, `gold-derived`, `silver` |
| `license` | the dataset's license: `CC-BY-4.0` (default) or `CC-BY-SA-4.0` (share-alike inputs — D51-a); see Licensing below |
| `anchoring` | how rows anchor into corpora: `none`, `passage-urn`, `urn+sha` |
| `inputs` | source slugs consumed (empty = own authorship) |
| `canonical_cones` | canonical path prefixes whose shas are recorded at derivation |
| `rationale` | one paragraph: why the dataset exists |
| `maintenance` | the recommended re-derivation periodicity |
| `builder` | the builder class (`nil` while planned) |

A builder is a plain class with one method, `#build(catalog:, out_dir:)`,
returning a `BuildResult` (resources written, the recipe string, citations,
optional README notes). Builders write their own data files into `out_dir`
(CSVs through `CsvWriter`); the Runner owns `languages.csv`, `sources.bib`,
`datapackage.json`, and `README.md`.

## The dataset directory

```
<lang>/<feature>/
  datapackage.json    Frictionless Data Package v2 manifest + nabu block
  *.csv               the data (CLDF nomenclature, see below)
  languages.csv       ID, Name, Glottocode, ISO639P3code (ID = Nabu's code)
  sources.bib         structured citations; keys citable from Source columns
  README.md           title, rationale, maintenance, provenance, fingerprint
```

`datapackage.json` carries the standard Frictionless fields (`$schema`,
`name`, `title`, `version`, `licenses`, `contributors`, `sources`,
`resources`) plus a namespaced `nabu` block:

```jsonc
"nabu": {
  "producer": "nabu data build san/form-lemma",
  "nabu_version": "<Nabu::VERSION>",
  "derivation": {
    "inputs": { "dcs": { "canonical_sha": "<sha>", "cone": "dcs" } },
    "recipe": "<builder-supplied derivation description>",
    "fingerprint": "<sha256 over sorted cone:sha tokens + recipe>"
  },
  "anchoring": { "kind": "none" },
  "tier": "gold-derived",
  "counts": { "rows": 12345 },
  "eval": { "boundary_f1": 0.9622, "...": "…" }  // only when the builder measures itself
}
```

The fingerprint follows the `DerivationFingerprint` token discipline: it
changes iff an input cone's canonical bytes or the recipe change. A builder
that measures its own output quality (xct/segmentation's segmenter, scored
against the SOAS gold by leave-one-text-out cross-validation) returns an
evaluation hash on its `BuildResult`; the Runner publishes it verbatim as
`nabu.eval` — the honesty stat rides in-band with the data it describes,
and the dataset README quotes the same numbers. `sources[]`
entries carry each input's title/homepage/license (from the source's adapter
manifest) and `version` = the cone's sha at derivation. Git-backed cones
record their HEAD sha; non-git cones record the content identity
`DerivationFingerprint.canonical_identity` computes. Non-tabular resources (a
`.bib`, a CoNLL-U projection) are legal resource entries: no `schema`, a
`format`/`mediatype` instead.

## CLDF nomenclature

CSV columns use CLDF's exact Title_Snake spellings where a CLDF term exists:
`ID`, `Language_ID`, `Form`, `Segments`, `Parameter_ID`, `Value`, `Headword`,
`Part_Of_Speech`, `Entry_ID`, `Description`, `Primary_Text`, `Position`,
`Comment`, `Source`. Nabu extension columns, spelled consistently across all
datasets: `URN`, `Passage_SHA256`, `Tier`, `Count`.

The ID discipline (`Nabu::DataBuild::CsvWriter` enforces it; violations
raise rather than publish):

- `ID` is **always the first column**, and its values are unique.
- Every `ID` matches the CLDF identifier regex `\A[a-zA-Z0-9\-_]+\z`.
- **A URN is never an ID** — colons are illegal. Mint one with
  `CsvWriter.mint_id` (deterministic, idempotent: components joined with
  `-`, illegal runs folded to a single `-`) and keep the URN in a `URN`
  column.
- `Source` cells cite `sources.bib` keys, `;`-separated; the keys obey the
  same identifier regex.

## Licensing

nabu-data is a **mixed-license repository** (owner ruling D51-a,
2026-07-29). The repo default is **CC BY 4.0**; each dataset's
`datapackage.json` `licenses` entry is **authoritative** for that dataset,
and its README states the dataset's own license explicitly. The allowed set
is exactly two values — `CC-BY-4.0` (the default) and `CC-BY-SA-4.0`
(datasets derived from share-alike inputs, whose READMEs add the one-line
carve-out: the repository's default license does not apply to them). A
BY-SA dataset additionally ships its **own `LICENSE` file** (the canonical
CC BY-SA 4.0 plaintext, emitted by the runner — №R-24, P73-0), so the
carve-out is visible in the dataset directory itself; default-license
datasets ship none, because the repository-level LICENSE already covers
them. The set is closed by construction (`Nabu::DataBuild::LICENSES`; the `Feature`
record refuses anything else): **NC/ND can never join it** — every dataset
here is a derivative work built to be reused, so non-commercial or
no-derivatives inputs are disqualifying at intake, and no NC/ND value is
ever a legal output license.

## The features

The census below is written from `Nabu::DataBuild::REGISTRY` and
drift-guarded by `test/docs/nabu_data_page_test.rb` — a registry change with
no page update is a red suite, and vice versa.

| Feature | Status | Tier | License | Language | Inputs |
| --- | --- | --- | --- | --- | --- |
| `san/form-lemma` | available | gold-derived | CC-BY-4.0 | san | dcs |
| `xct/wylie-fold` | available | gold | CC-BY-4.0 | xct | — |
| `xct/verb-lemma` | available | gold-derived | CC-BY-4.0 | xct | tibetan-verbs |
| `xct/segmentation` | available | silver | CC-BY-4.0 | xct | derge-kangyur, soas-tibetan |
| `zho/hani-fold` | available | gold-derived | CC-BY-4.0 | zho | unihan |
| `jpn/aozora-gaiji` | available | gold | CC-BY-4.0 | jpn | — |
| `lat/sabellic-loans` | available | gold | CC-BY-SA-4.0 | lat | — |
| `grc/meter` | available | gold-derived | CC-BY-4.0 | grc | hypotactic, perseus-greek, first1k-greek |
| `jpn/kyujitai-fold` | available | gold | CC-BY-SA-4.0 | jpn | unihan, edrdg |
| `lzh/kanripo-gaiji` | available | gold | CC-BY-SA-4.0 | lzh | — |
| `sux/value-signs` | available | gold | CC-BY-4.0 | sux | osl |
| `xct/actib-anchors` | available | gold-derived | CC-BY-4.0 | xct | derge-kangyur, actib |
| `roa-opt/cantigas` | available | gold | CC-BY-4.0 | roa-opt | cantigas |
| `mul/lect-assignments` | available | gold-derived | CC-BY-SA-4.0 | mul | — |
| `mul/place-refs` | available | gold-derived | CC-BY-SA-4.0 | mul | nabu-places |
| `mul/places-lpf` | available | gold-derived | CC-BY-SA-4.0 | mul | pleiades, trismegistos, cigs |
| `mul/document-dates` | available | gold-derived | CC-BY-SA-4.0 | mul | — |
| `mul/char-postings` | available | gold-derived | CC-BY-SA-4.0 | mul | — |
| `mul/language-dossiers` | available | curated | CC-BY-SA-4.0 | mul | — |
| `mul/script-dossiers` | available | curated | CC-BY-4.0 | mul | — |
| `sux/sign-table` | available | gold-derived | CC-BY-4.0 | sux | osl |
| `egy/unikemet-signs` | available | gold-derived | CC-BY-4.0 | egy | unikemet |
| `egy/hiero-frequency` | available | gold-derived | CC-BY-SA-4.0 | egy | aes |

### `san/form-lemma` — Sanskrit form→lemma table derived from DCS gold annotations

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: dcs

Bridges inflected surface forms (and unsandhied padapāṭha forms) to lemmas using only human-annotated gold data — powers dictionary-headword lookup for query expansion (the successor to Nabu's rule-generated Sanskrit stem variants).

**Maintenance**: re-derive after each dcs sync (upstream updates infrequently); mechanical, no review needed beyond spot-checks

### `xct/wylie-fold` — Tibetan script ↔ EWTS (Wylie) neutralization rule table

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: —

A hand-curated transliteration rule table letting Tibetan-script and Wylie-romanized text meet in one query space — doubles as the source for Nabu's generated Tibetan transcoder module.

**Maintenance**: on rule corrections only; each change re-derives the Tibetan shelves (fold modules are fingerprinted derivation inputs)

### `xct/verb-lemma` — Tibetan verb stem → paradigm-lemma map (from the Tibetan Verb Database)

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: tibetan-verbs

Maps the 2,491 TVD stem tuples (present/past/future/imperative, grammarians' disagreements kept uncollapsed) to a paradigm lemma, enabling verb-form-aware lookup across Classical Tibetan. The table half only: the anchored layer over the canon is deferred behind xct/segmentation.

**Maintenance**: re-derive after tibetan-verbs sync; upstream is stable (CC0)

### `xct/segmentation` — Segmented Classical Tibetan, curated slice (eval'd against SOAS gold)

**Status**: available · **Tier**: silver · **Anchoring**: passage-urn · **Inputs**: derge-kangyur, soas-tibetan

Tsheg-bar/word segmentation over a curated Derge slice with the segmenter's error rate measured against the SOAS gold corpus and published in-band — the calibration ground for any full-canon layer.

**Maintenance**: re-derive on canonical text revisions or segmenter upgrades; each release republishes the eval number

### `zho/hani-fold` — Han traditional↔simplified↔z-variant fold table (from Unihan)

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: unihan

The 6,050-pair Han fold resolved conservatively from Unihan's declared kTraditionalVariant/kSimplifiedVariant/kZVariant relations — the table that lets simplified-script queries reach the traditional-script canon (kanripo/cbeta), the same resolution `rake fold:hani` compiles into Nabu::Hani; every ambiguous fold is refused and published per-row with its reason, because the refusal census IS the curation.

**Maintenance**: re-derive after each unihan sync (upstream /latest/ moves at annual Unicode releases); a changed table also re-derives Nabu's own Han fold via `rake fold:hani` — the conventions §9 rebuild caveat applies

### `jpn/aozora-gaiji` — Aozora Bunko gaiji composition census with derived IDS lane

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: —

The census of composition formulas Aozora Bunko transcribers wrote for glyphs Unicode cannot encode (582 distinct formulas, 1,129 occurrences at the 2026-07-22 snapshot), each with its occurrence count and resolution status, plus the 244-entry IDS lane a conservative structural grammar can prove — refusals classified per formula, never guessed: the gaiji display-honesty ladder, published.

**Maintenance**: re-census on the owner's schedule as the corpus grows (the checked-in TSV header carries the snapshot provenance); each re-census re-fingerprints the dataset through the recipe's embedded sha256

### `lat/sabellic-loans` — Sabellic → Latin loanword table (en.wiktionary curation)

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: —

Flattens the hand-curated Sabellic (Oscan/Umbrian/Sabine) → Latin loan rows — 85 Latin lemmas with borrowed/derived relation flags and the Old Italic etyma en.wiktionary cites — into one reusable table; the same curation powers Nabu's sabellic-osc/xum/sbv dictionary shelves and their loan-flagged etymology edges. CC BY-SA (the Wiktionary share-alike grant — owner ruling D51-a).

**Maintenance**: on re-curation of config/sabellic_loans.yml only (a deliberate repo change, not a sync); each curation change re-fingerprints the dataset via the recipe's embedded file sha

### `grc/meter` — Greek metrical scansions (Hypotactic) anchored to Perseus CTS passages

**Status**: available · **Tier**: gold-derived · **Anchoring**: passage-urn · **Inputs**: hypotactic, perseus-greek, first1k-greek

Publishes D. Chamberlain's Hypotactic scansions (CC BY 4.0) as rows citable at urn:cts:greekLit grain: upstream has no citation scheme (work = filename, line = file order), so the URN + Passage_SHA256 anchoring Nabu derives by exact folded-text match IS the added value — with the matched/unmatched census published in-band and the row text taken from Hypotactic's own bytes, never the CC BY-SA Perseus text.

**Maintenance**: re-derive after hypotactic / perseus-greek / first1k-greek syncs (the stale-ingest guard enforces freshness); each release republishes the resolution census in nabu.eval

### `jpn/kyujitai-fold` — Japanese kyūjitai↔shinjitai reform-pair census (Unihan jinmeiyō + KANJIDIC2 jōyō lanes)

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: unihan, edrdg

The two-lane old↔new kanji pair table (Unihan kJinmeiyoKanji reform pairs + KANJIDIC2 jōyō-target variant edges, reform merges admitted, refusals censused) rendered through the same resolution seam `rake fold:jpn` compiles into Nabu::Jpn — one seam, two consumers. BY-SA: the load-bearing KANJIDIC2 lane is EDRDG share-alike (CC BY-SA 4.0).

**Maintenance**: re-derive after each unihan/edrdg sync (EDRDG rebuilds nightly, Unihan annually); regenerate together with `rake fold:jpn` so the shipped fold module and the dataset never drift

### `lzh/kanripo-gaiji` — Kanripo gaiji display ladder — faithful/IDS/substitute resolutions for &KR…; references

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: —

The hand-curated resolution ladder for the Kanseki Repository's not-yet-encoded character references (427 faithful codepoints, 562 labeled substitutes, the IDS lane empty by census, everything else an honest ⬚ placeholder) — the same three TSVs Nabu's `--display reading` mode loads for lzh kanripo passages. BY-SA: curated from KR-Gaiji's charlist under the kanripo org grant (CC BY-SA 4.0).

**Maintenance**: re-curate by hand after a `nabu sync kr-gaiji` advances charlist.org.txt (the P38-1 procedure); the curation is pinned to the charlist commit its file headers record, deliberately never auto-derived

### `sux/value-signs` — Cuneiform value→sign table from the Oracc Sign List (readings, codepoints, concordances)

**Status**: available · **Tier**: gold · **Anchoring**: none · **Inputs**: osl

Flattens the Oracc Sign List (ex-OGSL, Veldhuis & Tinney, CC0 — the field's hand-curated sign registry) to one row per (value, sign) pair — OSL-spelled readings with stable @oid interop keys, Unicode codepoints (absence kept honest), value-level deprecation flags and in-band ambiguity, plus signs.csv/concordances.csv sidecars (variant forms, MZL/LAK/ABZL print-list numbers) — the table that upgrades Edubba's frequency instrument from value-counts to true sign-counts. The slug leads sux (Sumerian); the ~55 %akk-qualified readings ride the Language_Qualifier column — the scope call is stated in the dataset README.

**Maintenance**: re-derive after each `nabu sync osl` (rolling master, no tags — a re-sync is an owner call; the stale-ingest guard enforces freshness); mechanical, no review needed beyond spot-checks

### `xct/actib-anchors` — ACTib ↔ Derge Kangyur anchor table (stable anchors for the segmented eKangyur)

**Status**: available · **Tier**: gold-derived · **Anchoring**: urn+sha · **Inputs**: derge-kangyur, actib

nabu-data's first re-publication: ACTib's known weakness is that its seg/POS layers carry no stable anchors into their source etexts (an upstream update orphans the whole layer — the concept doc's prior-art verdict), so this dataset publishes the anchor table that fixes it — one row per derge-kangyur passage tying URN + Passage_SHA256 to ACTib's (volume, page, line), with the measured match census as the in-band eval and the near/partial divergences republished as a proofreading table. The mapping is deterministic and measured (gold-derived); ACTib's own annotation layers stay labeled automatic upstream, and their 800 MB content is never republished — consumers join the DOI-cited Zenodo artifact on the anchor key.

**Maintenance**: re-derive after a derge-kangyur or actib re-sync (the stale-ingest guard enforces freshness); every build re-measures the anchoring census into nabu.eval

### `roa-opt/cantigas` — Cantigas Medievais Galego-Portuguesas — the Littera edition as structured tables (verse lines, cantigas, authors, cancioneiro concordance)

**Status**: available · **Tier**: gold · **Anchoring**: urn+sha · **Inputs**: cantigas

The first full-corpus re-publication: the complete secular lyric of medieval Galician-Portuguese — ~1,680 cantigas, ~34K verse lines from the three great cancioneiros — projected from the Littera critical edition (cantigas.fcsh.unl.pt) into the corpus's first machine-readable form (the scholarly database is superb and browser-only: no TEI, no export), under the coordinator's written any-use grant of 2026-07-27 with the project's own citation format riding every file — verse lines anchored urn+sha into the catalog, the cantiga/author registries, and the corpus-wide cancioneiro concordance parsed from the edition's manuscript sigla, with the citation-fidelity census (printed-number confirmations, refrain gaps, empty lines, the unattributed page) published in-band as nabu.eval.

**Maintenance**: re-derive after a cantigas re-sync (Littera is a living edition that corrects pages in place; the stale-ingest guard enforces freshness); every build re-derives the citation-fidelity census into nabu.eval

### `mul/lect-assignments` — Per-document historical-stage (lect) assignments across the multilingual catalog

**Status**: available · **Tier**: gold-derived · **Anchoring**: document-urn · **Inputs**: —

Publishes the per-document journal behind Nabu's lect facet — ~482K (URN, language-code) → historical-stage assignments (Old vs Neo-Babylonian, Ur III vs OB Sumerian, Vedic vs Classical Sanskrit, ...) with the basis and note in-band per row — the corpus-scale stage stratification no other project publishes; the id grammar and registry are public in nabu-lects (cited). License classes open+attribution only (nc/odbl/research_private slices excluded row-by-row, censused in nabu.eval); CC BY-SA 4.0 — the №R-24 carve-out dataset carrying the share-alike lanes (edh, aes, ...).

**Maintenance**: re-derive after journal-moving events (a sync wave re-running lect rules, new owner rulings, a rebuild) — the published-slice digest makes an unchanged journal a fingerprint no-op

### `mul/place-refs` — Per-document place references across the multilingual catalog, gazetteer-ready

**Status**: available · **Tier**: gold-derived · **Anchoring**: document-urn · **Inputs**: nabu-places

Publishes the compiled doc→place projection behind Nabu's places desk — ~586K (URN, claim) rows, every historical ref spelling (verbatim upstream URLs, multi-URL fields, namespaced mints) folded to clean namespace:id form (pleiades:, tm:, geonames:, cigs:, np:) ready to join gazetteer geometry, with the verbatim upstream name and the Basis (upstream-asserted vs nabu-places-applied) in-band per row. License classes open+attribution only (the iip nc slice excluded row-by-row, censused in nabu.eval); CC BY-SA 4.0 — the №R-24 carve-out (edh/aes/elephantine/ceipom share-alike lanes and the conservative tm:-index inheritance ride inside it).

**Maintenance**: re-derive after place-moving events (a sync wave, a nabu-places registry sync + apply, a rebuild) — the published-slice digest makes an unchanged projection a fingerprint no-op

### `mul/places-lpf` — Referenced places as Linked Places Format v1.3 + LP-TSV (the gazetteer-exchange shape)

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: pleiades, trismegistos, cigs

Publishes every place the catalog's documents reference as an LPF v1.3 FeatureCollection plus the LP-TSV v0.5 upload table (the World Historical Gazetteer's intake shapes): one Feature per claim (merging identities is entity resolution — the crosswalk rides as closeMatch links instead), attested spellings cited to their corpora, titles/coordinates from place_index (never invented), when-spans aggregated from document dates. The P69-2 GeoNames rider resolved NOT WANTED (recorded in the builder): geonames claims publish at document grain in mul/place-refs. CC BY-SA 4.0 — the TM lane's share-alike inheritance (№R-24).

**Maintenance**: re-derive after gazetteer syncs (pleiades/trismegistos/cigs — the stale-ingest guard enforces freshness) or place-moving catalog events; the collection digest in the recipe makes an unchanged projection a fingerprint no-op

### `mul/document-dates` — Normalized document datings across the multilingual catalog, verbatim raw in-band

**Status**: available · **Tier**: gold-derived · **Anchoring**: document-urn · **Inputs**: —

Publishes the dating layer behind Nabu's timeline — ~700K dated documents as normalized signed year spans (negative = BCE) with the VERBATIM upstream dating string riding every row, so each normalization is checkable against its source. License classes open+attribution only — the nc slices AND the rundata ODbL lane (a copyleft class of its own) are excluded row-by-row, censused in nabu.eval; CC BY-SA 4.0 — the №R-24 carve-out carrying the share-alike lanes (edh, tla-hf, aes, ...).

**Maintenance**: re-derive after dating-moving events (sync waves, infer-dates rule changes — the №R-28 regnal upgrade lands here on its next build); the published-slice digest makes an unchanged projection a fingerprint no-op

### `mul/char-postings` — Han character × corpus doc-frequency census (the graded-reading substrate)

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: —

Publishes the char_postings census behind Nabu's Han cards and graded-reading lane — one row per (character, corpus) with the attesting document count, spanning lzh/jpn/otb/ojp collections (hence mul/ — the naming the survey left TBD, settled here). The Edubba P-1 rider's character half: frequency data any school can consume, derived from Nabu's ingested corpora only (Edubba's own TSVs are NEVER an input — the circularity guard). nc slices (cbeta, ud, e84000, openiti) excluded row-by-row, censused; CC BY-SA 4.0 — the kanripo lane's share-alike grant (№R-24).

**Maintenance**: re-derive after CJK-lane syncs (the census rebuilds with the fulltext index); the published-slice digest makes an unchanged census a fingerprint no-op

### `mul/language-dossiers` — Curated language dossiers — the human-written name/family/context per language

**Status**: available · **Tier**: curated · **Anchoring**: language-code · **Inputs**: —

Fixes the replicability gap the curated dossiers left behind: the hand-authored name/family/context lanes lived only in the originating instance's local/ shelf, so a fresh install saw bare language codes. Published as an overlay (re-consumed via `nabu sync nabu-data`), every install composes the same curated context beneath its live holdings and lect ladder. Only the non-derivable curated layer travels — section accretions (iecor varieties, corpus witnesses, the lect stage ladder) are excluded, each install rebuilds them from its own synced sources. CC BY-SA 4.0: ~71% of the context prose is Wikipedia-derived (share-alike), so the whole dataset inherits it (№R-48); the Wikipedia-derived share is censused in nabu.eval, and personal notes ride the private `nabu note` layer, never here.

**Maintenance**: re-derive after curating dossiers (owner front-matter/context edits, the coming `nabu note` language layer); the published-slice digest makes an unchanged dossier corpus a fingerprint no-op

### `mul/script-dossiers` — Curated script dossiers — the human-written context per writing system

**Status**: available · **Tier**: curated · **Anchoring**: script-tag · **Inputs**: —

The char desk's script layer (P86, №R-49): every writing system in the registry's scripts table gets a human-written dossier — what the script IS, and the desk conventions a working library actually uses for it (transliteration surfaces, fold tables, honest gaps). Unlike the language dossiers (curated per-instance in local/), the source of truth is the git-shared config fact file, so every install answers identically and this dataset is the citable public mirror. The suite's drift guard pins dossier tags to the nabu-lects scripts table, so registry mints and dossiers cannot diverge silently.

**Maintenance**: re-derive after editing config/script_dossiers.yml (a new registry script mint forces a dossier via the drift guard); the published-slice digest makes an unchanged table a fingerprint no-op

### `sux/sign-table` — Compiled cuneiform sign cards — OSL identity, concordances, attestation counts

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: osl

The per-sign reference card compiled from what sux/value-signs flattens value-wise: one row per top-level OSL sign with codepoints, every print-list number, the CDLI reading concordance, AND per-source attestation doc-counts over the open cuneiform corpora (cdli/oracc/tlhdig — the Edubba P-1 rider's sign half, true sign-counts at last). Counting scope stated and censused (value/logogram tokens; compounds out); nc lanes (etcsl, ebl) have NO count columns, so no nc contribution can hide in an integer — the lemma_frequencies lesson. Core CC BY 4.0; the Wiktionary/aes BY-SA sense lanes are deliberately deferred to a later sidecar dataset so the core stays BY (survey §2.6).

**Maintenance**: re-derive after `nabu sync osl` or cuneiform-lane syncs (counts move with the catalog); the counts digest in the recipe makes an unchanged state a fingerprint no-op


### `egy/unikemet-signs` — The Egyptian sign spine — Unikemet codepoints with Gardiner codes and tool concordances

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: unikemet

Flattens Unikemet.txt to one row per encoded Egyptian hieroglyph — the Gardiner-style kEH_Cat code, the original Hieroglyphica-era kEH_UniK code, core/legacy status, description, functions, sound values, and the JSesh/Hieroglyphica/IFAO concordances every Egyptological tool joins on (the same spine Nabu's hiero card and the Edubba overlay key against). Every cell verbatim; absent tags stay empty. Permissive input (Unicode License V3) → clean CC BY 4.0.

**Maintenance**: re-derive after `nabu sync unikemet` (upstream moves at annual Unicode releases); mechanical, no review needed beyond spot-checks

### `egy/hiero-frequency` — Egyptian hieroglyph frequencies — Gardiner codes censused from AES, per subcorpus

**Status**: available · **Tier**: gold-derived · **Anchoring**: none · **Inputs**: aes

The sign-learning survey's P-1 Egyptian half (P77-r17): Gardiner-code token and document frequencies censused from AES's per-word hiero_inventar annotations, overall and per subcorpus (frequency is genre-dependent — Pyramid Texts vs Amarna letters vs medical papyri). To the survey's knowledge the first public hieroglyph frequency list anywhere. Joins egy/unikemet-signs on the Gardiner column. CC BY-SA 4.0 — derived from AES's share-alike grant, the №R-24/D51-a carve-out (the char-postings precedent).

**Maintenance**: re-derive after `nabu sync aes`; the doc-attestation digest in the recipe makes an unchanged census a fingerprint no-op

## What the rail never does

- **Git in the nabu-data clone.** Files are written; `git status` there is
  the owner's review surface. No add, no commit, no push, ever.
- **Write into Nabu's own stores.** Builders are read-only on `canonical/`
  and the catalog; a build derives outward.
- **Publish an input it cannot name.** No sha, no dataset — a dirty or
  missing cone refuses with the reason.

## The loop closes: nabu-data as a source

Since P51-W6 the published repo is also a REGISTERED SOURCE (`nabu-data`
in config/sources.yml, `kind: module` — docs/02-sources.md row 141): `nabu
sync nabu-data` clones the publication back under `canonical/nabu-data/`
through the sanctioned GitFetch gateway, where THREE read seams consume
it (P54 widened the original one):

- **`Nabu::FormLemma`** serves the `san/form-lemma` table to `nabu
  define`'s Sanskrit query expansion (P51-W6).
- **`Nabu::TibetanWords`** trains the shared-core `Nabu::TibetanSegmenter`
  on the `xct/segmentation` dataset's token counts, so `show --segmented`
  and `search --words` segment ANY Tibetan text at read time (P54-1/2/4).
- **`Nabu::VerbLemma`** serves the `xct/verb-lemma` paradigm table to
  define's Tibetan verb lane — a queried tense stem reaches its lemma's
  dictionary entry, suppletion included (P54-3).

All three share the FormLemma posture: feature-detected at query time,
absent file = lane off with byte-identical behavior, no catalog table, no
migration. The remaining features are single-truth PROJECTIONS — their
internal consumers read the same upstream truth the builders flatten
(the fold tables, the hypotactic and cantigas catalog rows,
canonical/osl, the canonical/actib layer cone), so consuming the
published CSV back would be a circle; they are one-way by design. The producer rail above and the consumer rows never touch: the
rail writes the owner's working clone, the source syncs the published
repo — the reproducibility loop closes only through a public commit.
