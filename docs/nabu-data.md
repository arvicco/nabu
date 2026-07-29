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
```

`data list` documents every artifact the rail is able to produce — slug,
status (available | planned), title, language, tier, anchoring kind, input
sources, the rationale for the dataset's existence, and the recommended
maintenance/periodicity. Planned features are listed too: the census is the
roadmap.

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
  "counts": { "rows": 12345 }
}
```

The fingerprint follows the `DerivationFingerprint` token discipline: it
changes iff an input cone's canonical bytes or the recipe change. `sources[]`
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

## The features

The census below is written from `Nabu::DataBuild::REGISTRY` and
drift-guarded by `test/docs/nabu_data_page_test.rb` — a registry change with
no page update is a red suite, and vice versa.

| Feature | Status | Tier | Language | Inputs |
| --- | --- | --- | --- | --- |
| `san/form-lemma` | available | gold-derived | san | dcs |
| `xct/wylie-fold` | available | gold | xct | — |
| `xct/verb-lemma` | available | gold-derived | xct | tibetan-verbs |
| `xct/segmentation` | planned | silver | xct | derge-kangyur, soas-tibetan |

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

**Status**: planned · **Tier**: silver · **Anchoring**: passage-urn · **Inputs**: derge-kangyur, soas-tibetan

Tsheg-bar/word segmentation over a curated Derge slice with the segmenter's error rate measured against the SOAS gold corpus and published in-band — the calibration ground for any full-canon layer.

**Maintenance**: re-derive on canonical text revisions or segmenter upgrades; each release republishes the eval number

## What the rail never does

- **Git in the nabu-data clone.** Files are written; `git status` there is
  the owner's review surface. No add, no commit, no push, ever.
- **Write into Nabu's own stores.** Builders are read-only on `canonical/`
  and the catalog; a build derives outward.
- **Publish an input it cannot name.** No sha, no dataset — a dirty or
  missing cone refuses with the reason.
