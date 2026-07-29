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
| `slug` | `<lang>/<feature>`, lower-case hyphen-joined segments; also the dataset directory path |
| `language` | a `Language` value: Nabu's code + the `languages.csv` statics (Name, Glottocode, ISO 639-3) |
| `title` | the dataset's human title (the manifest `title`) |
| `status` | `:available` (builder landed) or `:planned` (build refuses) |
| `tier` | provenance tier: `gold`, `gold-derived`, `silver` |
| `license` | the dataset's license: `CC-BY-4.0` (default) or `CC-BY-SA-4.0` (share-alike inputs — D51-a); see Licensing below |
| `anchoring` | how rows anchor into corpora: `none`, `passage-urn` |
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
carve-out: the repository's default license does not apply to them). The
set is closed by construction (`Nabu::DataBuild::LICENSES`; the `Feature`
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
through the sanctioned GitFetch gateway, and `Nabu::FormLemma` serves the
`san/form-lemma` table to `nabu define`'s Sanskrit query expansion. The
producer rail above and the consumer row never touch: the rail writes the
owner's working clone, the source syncs the published repo — the
reproducibility loop closes only through a public commit.
