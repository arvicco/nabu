# ebible-pacific fixtures

Real upstream files from **eBible.org**'s per-translation USFM zips
(`https://ebible.org/Scriptures/<id>_usfm.zip`), retrieved 2026-11-02
(zips Last-Modified 30 Oct 2026; eBible's HTML stamp: "HTML generated with
Haiola by eBible.org 30 Oct 2026 from source files dated 12 Dec 2025").
Three public-domain Pacific Bibles, each in its own subdirectory exactly
as its zip unpacks (flat, no top-level directory):

| zip | sha256 at retrieval | size |
|---|---|---|
| `haw1868_usfm.zip` | `63fd9c80bda2556137e234037fe7353264f4869267b9905fcbdef3bc98bbdf43` | 1,352,247 B |
| `cha_usfm.zip` | `bbfbac258e541334ad0db4430d83559bbbe9fd5451d374e91174349b1bdd8fb0` | 286,167 B |
| `pon_usfm.zip` | `19ff144e80bc7a25c77640674c4ff242b4881f5da3414ea2cd92667ec98eec91` | 390,999 B |

| File | Shape |
|---|---|
| `haw1868/32-OBAhaw1868.usfm` | verbatim — Obadiah (OT), 21 verses |
| `haw1868/73-JHNhaw1868.usfm` | TRIMMED — John, header + chapter 1 (lines 1–118; 51 verses) |
| `haw1868/94-3JNhaw1868.usfm` | verbatim — 3 John, 14 verses |
| `cha/20-PSAcha.usfm` | TRIMMED — Psalms, header + Psalms 1–2 (lines 1–43) |
| `cha/49-JHNcha.usfm` | TRIMMED — John, header + chapter 1 (lines 1–57; 50 verses — upstream bridges 1:43-44) |
| `pon/49-JHNpon.usfm` | TRIMMED — John, header + chapter 1 (lines 1–60; 51 verses) |
| `pon/69-2JNpon.usfm` | verbatim — 2 John, 13 verses |
| `*/copr.htm` | verbatim — the zip's rights page (rejected grain, pinned in all three: the license evidence) |
| `haw1868/latin.css`, `keys.asc`, `signature.txt.asc` | verbatim — the zip's stylesheet, eBible's signing key and the detached signature (rejected grains, one specimen each) |

## Upstream's delivery grains (enumerated 2026-11-02)

eBible serves each translation as: the USFM zip (taken), plus USFX,
OSIS, HTML, readaloud text, PDF, ePub, Sword and Paratext packages of
the same text (not taken — one text, one format), the per-translation
`copyright.htm` page, and the catalog `Scriptures/translations.csv`
(1,552 rows; read at fixture time for the census, not fetched by the
adapter). Inside the USFM zip:

- `NN-<BOOK><id>.usfm` — one book per file → **THE DOCUMENT GRAIN**
  (`urn:nabu:ebible-pacific:<id>-<book>`), passages `<chapter>.<verse>`.
- `copr.htm`, `*.css`, `keys.asc`, `signature.txt.asc` — the rights page,
  stylesheet and signing material: skipped by rule, counted in
  `discovery_skips`.

Census (the usfm parser over the full zips, 2026-11-02): haw1868 66 books
/ 31,102 verses (eBible's catalog: OT 23,145 + NT 7,957); cha 6 books
(PSA, MAT, MRK, LUK, JHN, ACT) / 7,245 verses (catalog 2,461 + 4,784);
pon 28 books (PSA + the NT) / 10,415 verses (catalog 2,460 + 7,955).
Total 100 documents / 48,762 passages — accepted + skipped-by-rule (4
non-book files per zip) account for every zip entry.

## Refused translations (the survey's Pacific rows)

- `kos` (Kosraean, "BIBLE MUTAL", eBible: "This work is in the Public
  Domain because the copyright has expired." — "Translation by: Elizabeth
  Baldwin"): REFUSED. The zip's own front matter (`00-FRTkos.usfm`) states
  a NEW translation ("leng sasu"): work begun September 15, 1992, from
  the NRSV and the Good News Bible, published by the Bible Society of
  Micronesia; the text carries footnotes, cross-references, book
  introductions and a glossary (`109-NDXkos.usfm`). Not the 1928
  Baldwin print — the srp1868 modernization precedent.
- `pon-pdn` (respelled into the new alphabet), `pon2006`/`pon2006a`
  (© 2006 Bible Society of the South Pacific), `ton` (the modern Revised
  West Version), `mri`/`mri2012` (© Bible Society New Zealand): refused
  per the survey.

## License

Each translation's `copyright.htm`, verbatim: haw1868 — "Public Domain"
· "Translation by: na na misionari i pai"; cha — "Public Domain" ·
"Translation by: American Bible Society"; pon — "Public Domain" (the
description: "old translation, using old alphabet"). → class `open`.
