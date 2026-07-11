# ORACC fixtures — rimanum (Akkadian, P-numbers) + etcsri (Sumerian, Q-numbers) + saao/saa01 + translations

Real ORACC JSON extracts for the OraccJsonParser family and the Oracc
adapter (P10-1, executing the owner-approved P9-5a fixture plan). Retrieved
**2026-07-09** from the two per-project open-data zips (the fetch unit —
ORACC serves no raw per-file JSON URLs; delivery is **zip over HTTP, not
git**):

- `https://oracc.museum.upenn.edu/json/rimanum.zip` (2.9 MB)
- `https://oracc.museum.upenn.edu/json/etcsri.zip` (12.9 MB)

P13-4 (retrieved **2026-07-11**, owner-approved fixture plan) adds the
**translation fixtures**: real per-text rendered-HTML fragments from the
official endpoint `https://oracc.museum.upenn.edu/<project>/<textid>/html`
(the ONE public machine-readable carrier of ORACC's running English — the
JSON has none, `oracc/catf` on GitHub is transliteration-only C-ATF with 0
`#tr` lines, and per-text `.atf`/`.xtf` endpoints are soft-404s: a 200 whose
body is a literal `404\n`), plus a saao/saa01 slice with its REAL NESTED zip
root (`saao-saa01/saa01/…`, the P11-7 shape).

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

### saao-saa01/ (Neo-Assyrian letters — the P13-4 translation pair)

Layout is the REAL nested zip root: `saao-saa01/saa01/…` (subproject zips
unpack one level deep — the P11-7 discovery defect this now regression-tests
at fixture level).

| File | Whole? | Why this one |
|---|---|---|
| `saa01/corpusjson/P224395.json` | whole | SAA 01 175 (letter, Adda-hati to Sargon II): 39 lines over obverse/reverse — the tablet side of the translation pair; byte-identical to the copy in `saao-saa01.zip` |
| `saa01/metadata.json` | trimmed | envelope + config verbatim; `formats` lists reduced to P224395 + P224485 (both `tr-en`) and X010028 (`atf` but **no** `tr-en` — the real untranslated saa01 text, exercising the crawl's tr-en gate) |
| `saa01/catalogue.json` | trimmed | members/summaries reduced to P224395, P224485 |

### html-en/ (P13-4 translation fragments, raw-GET-able)

| File | Whole? | Why this one |
|---|---|---|
| `html-en/saao-saa01/P224395.html` | whole | the paragraph-grain fable case: 39 transliteration lines, 6 translation units (anchored at o 1, o 4, o 11, r 30 + two prose-free state-notice cells "(Break)"/"(Rest destroyed)" — the skip rule's regression case) |
| `html-en/rimanum/P405432.html` | whole | translation of an already-fixtured tablet; full-label anchors ("(o 1)"), 4 units |
| `html-en/rimanum/P405134.html` | whole | primed/seal label anchors (`r 1’`, `seal 1 1’`), 3 units |

Fixture layout mirrors the workdir layout: crawled fragments live under
`<workdir>/html-en/<slug>/`, OUTSIDE the zip-managed project trees (a zip
swap must never attic them).

## Translation license (P13-4, the layered reality — recorded verbatim)

The CC0 statement above attaches to the **JSON build files**, which carry NO
prose translations. The prose is ORACC/SAAo project **content**:

> Content released under a CC BY-SA 3.0 license, 2007-20.
> — https://oracc.museum.upenn.edu/saao/ footer

and `oracc/catf`'s README says the quiet part: "Canonical ATF version of
Oracc data **which is permitted to be released under CC0**" — and catf
excludes exactly the translations. → translation documents carry
`license_override: "attribution"` (CC BY-SA 3.0) while the source stays
`open` (CC0).

## Honest findings recorded here

- **Prose translations are NOT in the JSON** — 0 translation nodes; running
  English lives only in the ATF source (`#tr.en:`/`@translation labeled`)
  and rendered HTML. P13-4 ingests it from the per-text HTML fragments as
  `-en` sibling documents (`translations: true` in the registry; stage-1
  crawl scope = the saao projects).
- **The fetch is an HTTP zip, not a git clone** — the first non-git fetch
  path (`Nabu::ZipFetch`); `Last-Modified`/`If-Modified-Since` is the
  change-detection mechanism (no shas upstream).
- Node vocabulary across BOTH whole projects: `c`/`d`/`l` only, plus a
  single node-less `linkbase` hash in some rimanum texts (skipped). `d`
  types: `object`, `surface`, `line-start`, `nonw` (inline fragment, e.g.
  `"/"`), `nonx` (illegible/excised stretches). Every `line-start` carries
  a `label`, unique within its text (verified project-wide).
