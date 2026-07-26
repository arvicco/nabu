# WOLD fixtures (P46-6 — the loanword-flow layer)

Real upstream samples from the **World Loanword Database** (Haspelmath,
Martin & Tadmor, Uri (eds.) 2009, MPI-EVA; wold.clld.org) — the CLDF
bundle `lexibank/wold` **v4.2**. Every kept CSV record is
**byte-verbatim** upstream data (rows were filtered with a CSV-aware
line tap that preserves each record's raw bytes, embedded-newline-safe);
only the record SET was trimmed.

- **Retrieved:** 2026-07-26, from the Zenodo versioned record
  <https://zenodo.org/records/21415389> (DOI 10.5281/zenodo.21415389 =
  v4.2; concept DOI 10.5281/zenodo.1299889), file
  `lexibank/wold-v4.2.zip` — 16,079,041 B, md5
  `841e4f39fb64b7486fe29b1802c8f087` (Zenodo's published checksum,
  matched), sha256
  `ada4e5a4e20bfcd3afe253e602b8bb8eb353521f5785d92136cf56ad166cda3c`
  (the adapter's `RELEASE_SHA256` pin). Full-file census at retrieval:
  41 vocabularies / 1,814 parameters / 65,332 forms / 21,624 borrowing
  events (20,625 with a Source_word). Raw per-file snapshots for the
  trim came from the same content at the v4.2 tag of
  github.com/lexibank/wold (identical bytes).
- **License:** CC BY 4.0 — cldf/README.md verbatim: "This dataset is
  licensed under a CC-BY-4.0 license"; Zenodo record cc-by-4.0.
- The bundle's `cldf-metadata.json`, `sources.bib` and auxiliary tables
  (contributors.csv, media.csv, descriptions/) are **not snapshotted**:
  the adapter reads the five data tables by their fixed CLDF names.

## What was kept (3 vocabularies, 9 forms, 9 borrowing events)

- `cldf/languages.csv` — 3 of 41 vocabularies: **English** (stan1293,
  ISO eng), **OldHighGerman** (oldh1241, ISO column BLANK upstream — the
  `VOCAB_TAG_MAP` goh pin; blank-ISO census: OldHighGerman, Sakha,
  SeliceRomani), **Swahili** (swah1253, swh).
- `cldf/parameters.csv` — the 6 meanings the kept forms cite (1-1 the
  world / 1-51 the sky / 3-47 the mule / 3-77 the elephant / 5-92 the
  wine / 23-395 the street), each with its Concepticon id+gloss — the
  cldf-spine resolution pins (965 WORLD, 1524 WINE, …).
- `cldf/forms.csv` — 9 of 65,332 lexemes:
  - **English-1-1-1** world — "5. no evidence for borrowing", age
    Proto-Germanic (the native-entry pin: status without an event);
  - **English-1-51-1** sky — ← Old Norse ský ‘cloud’, with the
    replaced-its-OE-cognate comment_on_borrowed;
  - **English-5-92-1** wine — ← Latin vīnum (immediate) AND ← Greek
    (w)oînos (earlier): the two-event, relation-flag, Latin-fold
    round-trip star;
  - **English-23-395-1** street — ← Latin "(via) strāta" (the
    parenthesized donor form);
  - **OldHighGerman-1-1-1** weralt (native), **-3-47-1** mûl ← mūlus,
    **-3-77-1** helfant ← elephantus (immediate) + ← Greek "elephas,
    -ntos" (earlier — the unsplittable comma-multiform pin: splitting
    would mint the bare tail "-ntos");
  - **Swahili-1-1-1** dunia ← Arabic dunyā (the WOLD website's own
    flagship example), **Swahili-1-1-2** ulimwengu — "4. very little
    evidence" WITH a curated event (status and event both ride).
- `cldf/borrowings.csv` — the 9 events targeting those forms. NOTE the
  donor glottocodes: "Old Norse" is tagged **noon1243** — which
  Glottolog resolves to Noone (Atlantic-Congo); real Old Norse is
  oldn1244 (upstream defect, pinned in test/cldf_spine_test.rb — the
  reason the adapter's DONOR_MAP keys on languoid NAMES); "Greek" is
  tagged mode1248 (Modern Greek) even for ancient (w)oînos.
- `cldf/contributions.csv` — the 3 vocabularies' contributor citations
  (Schadeberg / Schuhmann / Grant — each shelf's title credit).

## Refresh recipe

Download the Zenodo zip above (immutable — a byte drift is an incident,
not an update), unzip, and re-trim with the ID sets in `manifest.yml`
(languages/contributions by vocabulary; parameters by ID; forms by form
ID; borrowings by Target_Form_ID). LF line endings upstream, preserved.
