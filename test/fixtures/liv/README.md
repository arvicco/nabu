# LIV fixtures (P18-6 — the LiLa LOD reconstruction shelf, Rix-school witness)

Real upstream sample from **CIRCSE/LIV** — Rix's *Lexikon der
indogermanischen Verben* (2nd ed. 2001) as LiLa Linked Open Data
(lemonEty/Ontolex Turtle). Every kept statement block is **byte-verbatim**
upstream data (the P14-1 recipe); only the block SET was trimmed, per the
fixture sketch approved in docs/pie-survey.md §7.

- **Upstream:** <https://github.com/CIRCSE/LIV>, `ttl/LIV.ttl`.
- **Retrieved:** 2026-07-14, from
  `https://raw.githubusercontent.com/CIRCSE/LIV/master/ttl/LIV.ttl`
  (672,757 bytes, sha256
  `5940d47a27ec634b6679f3b138c944b867e778b3d65923f6eee6a2585b0b4b31`;
  the raw host serves an ETag but NO Last-Modified). Full-file census:
  305 `lemonEty:Etymon` / 385 `ontolex:LexicalEntry` / 385
  `lemonEty:Etymology` / 505 `lemonEty:EtyLink` / 426 `morph:Morph`
  themes / 340 `ontolex:Form` writtenReps / 11 stem-type nodes; the only
  `lime:language` value is "PIE".
- **License (repo README, verbatim):** "The publisher of the dictionary
  allowed us to model and publish the etymological relations between PIE
  roots, stems and Latin word forms contained in the data." + "These
  resources are licensed under a Creative Commons Attribution-ShareAlike
  4.0 International License." → CC BY-SA 4.0, license_class `attribution`.
- **Credit:** Rix, Kümmel, Zehnder, Lipp, Schirmer (creators); Boano,
  Passarotti, Mambrini, Ginevra, Moretti (LiLa modelling — cite Boano et
  al., *CLiC-it 2023*).

## What the fixture holds (and the quirks it pins)

Prefix block + the `liv_base:Lexicon` header, three stem-type
declarations (present/essive/aorist), and three complete etymon clusters
(entry → theme → etymon → etymology → etylink → prinparlat stem → form):

| etymon (verbatim label) | Latin entry | pins |
|---|---|---|
| `*dʰu̯eh₂-{1}` | suffio | the survey-sketch block; `{1}` homonym marker; stem-type body line |
| `1.*u̯ei̯s-{1}` | uireo | the **u/v fold** pin (u-spelling writtenRep joins gold `lat` via §9 v→u); LEADING homonym index `1.` |
| `*lei̯d-` | ludo | the SHARED placeholder theme `…/Themes/-` (label "–", an IRI whose local name is "-") typed "aorist stem" and reused across etymons — link scoping per etymon; a perfect-stem link (`perf lusi`) whose prinparlat stem has no `ontolex:Form` |

Also pinned: the `liv_base:Lexicon` subject REAPPEARING mid-file to
accrete more `lime:entry` values (repeated subjects), numeric local names
(the etymon ids are ~40-digit decimals — adopted verbatim as entry ids),
unicode inside `<>`-wrapped IRIs, and dangling `lime:entry` references to
entries the trim dropped (the parser must not care).
