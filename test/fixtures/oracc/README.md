# ORACC fixtures — rimanum (Akkadian, P-numbers) + etcsri (Sumerian, Q-numbers)

Real ORACC JSON extracts for the OraccJsonParser family and the Oracc
adapter (P10-1, executing the owner-approved P9-5a fixture plan). Retrieved
**2026-07-09** from the two per-project open-data zips (the fetch unit —
ORACC serves no raw per-file URLs; delivery is **zip over HTTP, not git**):

- `https://oracc.museum.upenn.edu/json/rimanum.zip` (2.9 MB)
- `https://oracc.museum.upenn.edu/json/etcsri.zip` (12.9 MB)

## License (recorded verbatim, machine-read)

Both projects' `metadata.json`, `catalogue.json` AND every non-empty
`corpusjson/*.json` carry the identical machine-readable statement:

> This data is released under the CC0 license
> (https://creativecommons.org/publicdomain/zero/1.0/)

→ `license_class: open`. The adapter READS the per-project `license` field
and maps it (CC0 → open, CC BY-SA → attribution); it never hardcodes —
future projects may differ from the 2014 blanket CC BY-SA 3.0 the ORACC
website footer still shows.

## Files and extract procedure

corpusjson texts and metadata.json are kept **whole** (a cdl tree is atomic
— trimming would break the JSON and the sentence/lemma structure; metadata
carries the license + project config the adapter reads). Note the plan
estimated etcsri metadata.json at ~30 KB; upstream reality is 377 KB (large
`formats`/`witnesses` blocks) — kept whole anyway, per plan rationale.
catalogue.json is **trimmed**: the envelope keys (`type`/`project`/`source`/
`license`/`license-url`/`more-info`/`UTC-timestamp`) kept verbatim,
`members` and `summaries` reduced to the fixtured ids only, re-serialized
well-formed (`json.dump(..., ensure_ascii=False, indent=1)`).

### rimanum/ (Akkadian `akk-x-oldbab`, P-numbers, 378 texts upstream)

| File | Whole? | Why this one |
|---|---|---|
| `metadata.json` | whole | license (CC0) + project name/config |
| `catalogue.json` | trimmed | members/summaries reduced to the 3 fixtured P-numbers (designation → doc titles) |
| `corpusjson/P405432.json` | whole | the rich exemplar: obverse+reverse surfaces, 25 lemmas, determinatives (`{d}EN.ZU-še-mi`), subscripts (`ZI₃`), full `norm`/`cf`/`gw`, Sumerian year-name lines (`lang:"sux"` inside an Akkadian text), a `cof-head`/`cof-tails` pair (one written form `NIG₂.ŠU` = two lemma words ša + qātu) |
| `corpusjson/P405134.json` | whole | shorter second Akkadian text; primed line labels (`r 1’`), a `seal 1` surface |
| `corpusjson/P405254.json` | whole (0 B) | **empty** — catalog-only artifact, no transliteration (40 such in rimanum). The upstream norm the adapter must skip honestly, not quarantine |

### etcsri/ (Sumerian `sux`, Q-numbers, 1456 texts upstream)

| File | Whole? | Why this one |
|---|---|---|
| `metadata.json` | whole | license (CC0) + config (377 KB — see note above) |
| `catalogue.json` | trimmed | members/summaries reduced to the 2 fixtured Q-numbers (`id_composite`, not `id_text`, keys the members here) |
| `corpusjson/Q004151.json` | whole | Sumerian royal inscription (Amar-Suena seal), 6 lines, plain numeric labels (no surface d-nodes), lemmatized (`cf`/`gw`/`norm`) |
| `corpusjson/Q001299.json` | whole | second Sumerian text — **the smallest non-empty Q at extraction time** (2,980 B, "Anonymous Nippur 45", Early Dynastic): single line, single lemma, the minimal-document case |

## Honest findings recorded here

- **Prose translations are NOT in the JSON** — 0 translation nodes; running
  English lives only in the ATF source (`#tr.en:`) and rendered HTML.
  Aligned translations are a future separate acquisition, out of the v1
  JSON adapter (`translations: false` in the registry).
- **The fetch is an HTTP zip, not a git clone** — the first non-git fetch
  path (`Nabu::ZipFetch`); `Last-Modified`/`If-Modified-Since` is the
  change-detection mechanism (no shas upstream).
- Node vocabulary across BOTH whole projects: `c`/`d`/`l` only, plus a
  single node-less `linkbase` hash in some rimanum texts (skipped). `d`
  types: `object`, `surface`, `line-start`, `nonw` (inline fragment, e.g.
  `"/"`), `nonx` (illegible/excised stretches). Every `line-start` carries
  a `label`, unique within its text (verified project-wide).
