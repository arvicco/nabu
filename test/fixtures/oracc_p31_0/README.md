# ORACC P31-0 expansion fixtures — ario + the four ePSD2 corpora

Real trimmed slices for the five PROJECTS rows added by packet P31-0
(config expansion; the oracc_p14_9 own-tree precedent, so the
discover-walked `test/fixtures/oracc/` corpus stays byte-stable). All
content is real upstream ORACC JSON — never hand-written.

Retrieved **2026-07-19** from the per-project open-data zips at
`https://oracc.museum.upenn.edu/json/<slug>.zip` (ORACC serves no raw
per-file JSON URLs; the zip is the delivery unit, so every entry here is
`refetchable: false` zip-extract provenance):

| Zip | Size | Last-Modified | sha256 |
|---|---|---|---|
| `ario.zip` | 2,689,695 B | Tue, 23 Jan 2024 14:04:35 GMT | `87860f36d65fefbb0fd5a3710f4b6f3e0081dd51481ce47b97af162abc094d12` |
| `epsd2-literary.zip` | 39,510,771 B | Wed, 13 Mar 2024 09:36:46 GMT | `7bc5b6d1ab4919cf64ce305fb33474d3ab2272a003ffe4d20928574f0151ea31` |
| `epsd2-royal.zip` | 15,095,615 B | Wed, 13 Mar 2024 09:36:46 GMT | `f94bacbfecaed8741aa5cdd0239075d122976fdff2729ddac84303cfde6b997e` |
| `epsd2-earlylit.zip` | 1,260,256 B | Wed, 13 Mar 2024 09:36:43 GMT | `1beb382b812178e80cde4f4481bac83cd1333ef3201ec17c4230aa41301355fb` |
| `epsd2-admin-ur3.zip` | 561,755,376 B | Wed, 13 Mar 2024 09:36:36 GMT | *(not downloaded whole — see below)* |

The four smaller zips were downloaded whole and members extracted; the
561.8 MB **epsd2-admin-ur3.zip was never downloaded** (owner guidance:
fixture slices only). Its members were extracted by **HTTP ranged reads**
(the server sends `Accept-Ranges: bytes`): fetch the tail, locate the
EOCD/ZIP64-EOCD, fetch the central directory (80,195 entries), then fetch
each wanted member's local header + compressed bytes and inflate. So there
is no whole-zip sha to record; the per-zip pin at sync time is ZipFetch's
Last-Modified + body sha mechanism, as for every other project.

## Layout (mirrors the real unpacked workdir — the load-bearing fact)

ZipFetch strips the single shared top-level dir from each zip. The epsd2
zips carry their FULL project path as the root, so the live trees nest:

- `ario.zip` → root `ario/` → `<workdir>/ario/…` (top-level shape)
- `epsd2-literary.zip` → root `epsd2/literary/` → `<workdir>/epsd2-literary/literary/…`
  (the P11-7 saao-saa01 nested shape; likewise royal, earlylit)
- `epsd2-admin-ur3.zip` → root `epsd2/admin/ur3/` → `<workdir>/epsd2-admin-ur3/admin/ur3/…`
  — **DOUBLY nested**: the true ORACC project path is `epsd2/admin/ur3`
  (three segments; the site's `/epsd2/admin-ur3/` answers a soft-404
  `404\n`, while `/epsd2/admin/ur3/metadata.json` is 200). The PROJECTS row
  is therefore `epsd2/admin/ur3`, and `Oracc#project_dir`'s nested fallback
  resolves the multi-segment root (`nested_root`) — the one code change in
  this config packet, regression-tested against this tree.

## License (recorded verbatim, machine-read at every sync)

Every one of the five projects' `metadata.json` (and every non-empty
corpusjson) carries the identical machine-readable statement:

> This data is released under the CC0 license
> (https://creativecommons.org/publicdomain/zero/1.0/)

with `license-url` `https://creativecommons.org/publicdomain/zero/1.0/`
→ `license_class: open`, matching the source class. Verified from the zip
payloads 2026-07-19 (the standalone per-project `metadata.json` HTTP
endpoints still serve an empty body — the standing live quirk — so the zip
is the license carrier, and the adapter's per-project gate at sync is the
guarantee).

## Files and extract procedure

corpusjson texts are **byte-verbatim whole zip members** (a cdl tree is
atomic). catalogue.json is **trimmed** per the P10-1 recipe: envelope keys
verbatim, `members`/`summaries` reduced to the fixtured ids, re-serialized
well-formed (`json.dump(..., ensure_ascii=False, indent=1)` + newline).
metadata.json is kept **whole** where small (ario 16.5 KB, earlylit
4.9 KB, literary 55.9 KB) and **trimmed** where the formats/witnesses
blocks dominate (the P13-4 saa01 recipe): royal (519.5 KB → 1.4 KB;
formats lists + `witnesses` reduced to the fixtured ids) and admin-ur3
(4.08 MB → 1.1 KB; formats lists reduced — NB its `lem` list honestly
excludes the unlemmatized P119709).

### ario/ (Achaemenid royal trilinguals; Q-numbers; 175 corpusjson, 2 empty)

Old Persian (`peo`) and Elamite (`elx`) enter the library here — tagged
per l-node BY UPSTREAM, so the languages are data, not config. Line labels
carry the VERSION name (`Persian 1`, `Elamite 2`, `Akkadian 1` →
`Persian.1`…). Whole-project census (every non-empty corpusjson walked):
l-node langs `peo` ×7,758 · `akk` ×2,607 · `elx` ×1,348; node vocabulary
`c`/`d`/`l` only; d-types object/surface/line-start/nonw/nonx.

| File | Why this one |
|---|---|
| `corpusjson/Q007149.json` | DPd ("Darius I  16"): pure Old Persian, 4 lines, lemmatized (`Dārayava.u-_I`, `xšāyaθiya-`, `vazṛka-`) — the peo primary-language + lemma-row case |
| `corpusjson/Q007203.json` | DPa ("Darius I 69"): the royal TRILINGUAL — Persian/Elamite/Akkadian versions in one text; majority base subtag (akk, 4 vs 3/3) is the per-text primary, every token keeps its per-word tag |
| `corpusjson/Q007267.json` | A2Sa ("Artaxerxes II 02"): pure Elamite, 4 lines — elx primary; honestly UNLEMMATIZED (see findings) |

### epsd2-literary/literary/ (the ETCSL literary corpus, ORACC-lemmatized; 1,022 corpusjson, 0 empty)

Whole-project census: langs `sux` ×194,959 · `sux-x-emesal` ×2,617 ·
`akk` ×1,429 · `akk-x-oldbab` ×579 · `qcu` ×8; d-types add
`column`/`cell-start`/`cell-end`/`field-start`/`field-end` (tabular
layout markers — structural, not reading text; the parser reads only
`line-start`, so they pass through silently by design).

| File | Why this one |
|---|---|
| `corpusjson/Q000553.json` | composite: "Letter from Šulgi (?) to Aradĝu about troops", 8 lines, plain numeric labels, lemmatized (`Aradŋu`, `Šulgir`) |
| `corpusjson/P411270.json` | manuscript witness (CUNES 51-02-036), 6 lines over obverse/reverse WITH `field-start` d-nodes — the tabular-marker shape in a real text |

### epsd2-royal/royal/ (Sumerian royal inscriptions; 1,928 corpusjson, 0 empty)

Census: langs `sux` ×53,044 · `sux-x-emesal` ×39 · `akk` ×1,798 ·
`akk-x-oldbab` ×6; d-types as literary minus cell/field (column present).

| File | Why this one |
|---|---|
| `corpusjson/Q001016.json` | "Ur-Nanše 01": minimal composite, 3 lines, lemmatized (`Urnanše`, `lugal`, `Lagaš`) |

### epsd2-earlylit/earlylit/ (Early Dynastic literature; 43 corpusjson, 0 empty)

Census: langs `sux` ×5,756 · `akk-x-oldbab` ×60 · `akk` ×2; d-types
include column and cell/field markers.

| File | Why this one |
|---|---|
| `corpusjson/P323472.json` | CUNES 49-08-067 (CUSAS 23, 205): 10 lines, 9 lemmatized words |
| `corpusjson/P010246.json` | 824-byte **object/surface skeleton** — catalogued, never transcribed (6 such in earlylit); parses to zero lines → skipped by rule (`catalog-only (no content)`), never quarantined |

### epsd2-admin-ur3/admin/ur3/ (ePSD2/CDLI Ur III Corpus; 80,181 corpusjson, 0 empty)

The Ur III administrative mass (owner-approved 2026-07-19): 80,181 texts,
`lem` format on 79,664 of them, **no `tr-en`** (the translation crawl is
provably inert here). Expect this project to dominate library counts.

| File | Why this one |
|---|---|
| `corpusjson/P133815.json` | "TÉL 297 = L ---": a typical barley-fodder receipt, 4 lines, gold-lemmatized (`gur`, `šaggal` "fodder", `šu teŋ` "receive") |
| `corpusjson/P119709.json` | BM 012339: 456-byte **EMPTY-cdl skeleton** (`"cdl": [{…"cdl": []}]`) — the admin-ur3 catalog-only shape, skipped by rule |

## Honest findings recorded here

- **Elamite is unlemmatized in ario** — the project ships `gloss-akk.json`
  and `gloss-peo.json` but NO `gloss-elx`; elx l-nodes carry `lang` but no
  `cf`, so elx enters the library with zero lemma rows (pinned by test).
  peo IS lemmatized (144 texts in ario's `lem` format list).
- **Trilinguals index under their primary** — the standing per-passage
  rule: DPa's `adam` (peo) rides a passage whose majority language is akk,
  so its lemma row is filed under akk, per-word tag intact in annotations
  (the rimanum Sumerian-year-name precedent; pinned by test).
- **New d-types in the epsd2 corpora**: `column`, `cell-start`/`cell-end`,
  `field-start`/`field-end` (tabular layout). The parser's line-start-only
  rule handles them correctly (structure, not reading text); node
  vocabulary is still exactly `c`/`d`/`l` across ALL FIVE whole projects
  (census above) — the standing unknown-node guard saw nothing new.
- **`qcu` tokens** (×8, epsd2/literary): ORACC's cuneiform-sign-name
  "language" tag on sign-name spellings — rides annotations verbatim,
  never a document language (never a majority).
- **Translation-crawl deltas** (`formats["tr-en"]` counts, machine-read):
  ario 173 (of 175; also 149 `tr-de` — German, out of scope like etcsri's
  Hungarian), literary 90, royal 101, earlylit 1, admin-ur3 0 — ~365 new
  fragments for the crawl at the next owner-fired sync.
- **ario empties**: 2 zero-byte corpusjson (the rimanum P405254 shape) and
  14 more texts whose cdl carries no l-nodes at all (skeletons); both skip
  by rule.
