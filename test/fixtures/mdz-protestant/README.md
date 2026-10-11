# mdz-protestant fixtures (MDZ / Bayerische Staatsbibliothek)

Retrieved 2026-10-11 from the MDZ APIs:

- IIIF Presentation v2 manifests —
  `https://api.digitale-sammlungen.de/iiif/presentation/v2/<bsb>/manifest`
- per-page hOCR (the OCR layer every canvas links as seeAlso "OCR") —
  `https://api.digitale-sammlungen.de/ocr/<bsb>/<page>`

Three real objects. Each `manifest.json` is the upstream manifest with
its `sequences[0].canvases` array TRIMMED to the canvases whose hOCR is
checked in (every other field verbatim, re-serialized compactly); each
`hocr/<page, 5-digit>.hocr` is a whole, byte-verbatim API response.

| object | print | license (manifest) | canvases kept |
|---|---|---|---|
| `bsb00078189` | Trubar, *Articuli oli Deili*, V Tibingi 1562 — Slovene | Public Domain Mark 1.0 | 1 (cover: the "000" scan label + "PRIMUS TRV BER-CARNO"), 79, 80 (of 237) |
| `bsb11302253` | Dalmatin, *Jesus Sirah*, Lublani 1575 — Slovene (Google copy) | rightsstatements NoC-NC 1.0 | 76, 77 (of 228) |
| `bsb10206655` | *Spovid ispoznanie pravê kriztianszke vere*, Tubingae 1564 — Latin-script Croatian (Google copy) | rightsstatements NoC-NC 1.0 | 72 (of 216) |

What the trio pins: the BSB scan-target label (a digits-only first
line at bbox x=0 — "00078189", "000") moving to annotations; Google
copies carrying no label and keeping the printed folio number; the
manifest license deciding per-document `nc`; imprint place parsing
("Tubingae : [Morhart]"); GND-linked creators/contributors.

Re-cut recipe: GET the manifest, keep the listed canvases (match the
number at the end of each canvas `@id`), GET those pages' hOCR. The
API is rate limited (x-ratelimit-limit 5001) — a fixture re-cut is a
handful of requests.
