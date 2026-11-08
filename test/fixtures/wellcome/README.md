# wellcome fixtures

Real captures, retrieved 2026-11-08. The fixture tree has the shape the
adapter's fetch leaves in `canonical/wellcome/`.

## Upstream's delivery grains (enumerated at fixture time)

| Grain | Where | Taken? |
|---|---|---|
| Catalogue snapshot: one JSON work per line, every work type | `https://data.wellcomecollection.org/catalogue/v2/works.json.gz` (530,379,348 bytes, Last-Modified 2026-11-08) | **yes, as the census** — derived into `census.tsv` |
| Work → digitised item: the `iiif-presentation` location (bnumber in its URL) | inside each catalogue line | yes, one census row per digitised bnumber |
| Per-bnumber text zip, one `.txt` member per volume (`<b>.txt`, or `<b>_0001.txt …` for a multi-part work) | `https://api.wellcomecollection.org/text/v1/<bnumber>.zip` | **yes — the document grain is the member (volume)** |
| Per-volume raw text | `https://api.wellcomecollection.org/text/v1/<bnumber>_0001` | no — byte-identical to the zip member (checked on b33275154_0001) |
| Per-page ALTO / per-page line annotations | `api.wellcomecollection.org/text/alto/<vol>/<canvas>`, `iiif…/annotations/v3/<vol>/<canvas>/line` | no — one request per canvas (636 for b33275154_0001 = 5 h at the 30 s pace); no whole-volume line list exists (`/annotations/v3/<vol>/line` → 404) |
| PDF, images, IIIF manifests | `iiif.wellcomecollection.org/pdf/…`, `/presentation/v3/…` | no — not text; the bnumber→zip mapping comes from the census, never a manifest GET |

The text in a zip member is ONE unbroken line (b33275154_0001: 1,294,416
bytes, no line terminator, no page break) — the passage is therefore a
~2,000-character segment, not a page (see the adapter header).

## Files

- `works.json.gz` — 11 WHOLE lines cut from the 2026-11-08 catalogue
  snapshot, re-gzipped: the in-scope works of the three text zips
  below (cdhzsjf3 → b30773490, a22hs5j3 → b33275154, b3ktjk2u →
  b30765808), plus the scope specimens: rb4zrs5g (b14583288, a ProQuest Galen 1543 — the text
  service answers 404 "No text resource found for b14583288.zip"),
  pffwuy2k (b30095852, "1302 [1886]" — the Hijri year beside its CE
  bracket), k66dr7hm (b31973073, Roman-numeral "M.DCC.XLV"),
  cpv42s4b (b20391109, 1895 — in the census, outside the cone),
  k2rqaq5v (b28749029, "[185?-?]"), and three REJECTED by rule:
  hp73uzt6 (b30251151, cc-by licence), jafxheby (b15813733, workType
  l — not a book) and one "[date of publication not identified]" book.
- `census.tsv` — the adapter's own derivation of `works.json.gz`
  (`Wellcome#derive_census!`; the test asserts byte equality).
- `zips/b30773490.zip` — WHOLE (8,680 bytes): Leonardus Smeur,
  *Disputatio … de origine lymphae*, Utrecht 1719 (UKMHL scan), member
  `b30773490.txt`.
- `zips/b33275154.zip` — TRIMMED: Boyle, *Exercitationes circa
  utilitatem philosophiae naturalis experimentalis*, Geneva 1694
  (digearly scan; upstream zip 574,819 bytes). The one member
  `b33275154_0001.txt` (a multi-part work's manifestation name) cut to
  its first 6,499 characters at a space and re-zipped under the same
  member name.
- `zips/b30765808.zip` — TRIMMED: Theodor Zwinger III, *Paidatrophia*
  dissertation, Basel 1680 (catalogue languages gre, lat; real Greek
  letters in the OCR); upstream zip 32,926 bytes, member
  `b30765808.txt` (upstream stores it with Unix mode 000) cut to its
  first 5,999 characters at a space and re-zipped.
- `zips/b33011564.zip` — WHOLE (129 bytes), the REJECTED grain: a 1741
  French print whose zip holds one 0-byte member. The crawl ledgers such
  a zip "empty"; a held 0-byte member is skipped by rule at discovery
  (the multi-part case).

## Re-cut

Fetch `https://api.wellcomecollection.org/text/v1/<bnumber>.zip` (one
request per 30 s — Wellcome's robots Request-rate), keep the member
prefix as above (`zip -X -9` with the same member name); cut the
catalogue lines by bnumber from the snapshot and gzip them; re-derive
`census.tsv` through the adapter.

Licence: Public Domain Mark 1.0 (catalogue location licence `pdm`,
manifest rights http://creativecommons.org/publicdomain/mark/1.0/).
