# ottoman-ocr fixture — OttomanOCR-search, trimmed

- **Upstream:** https://github.com/koras0ff/OttomanOCR-search (Enes Yılandiloğlu,
  University of Helsinki), branch `main` at commit
  `bac65b67166cd55033263c0d5f4b204b3d6d81e1` ("Fix LICENSE text; add volume numbers
  to Peçevî and New Testament titles", 2026-10-31) — the adapter's `PINNED_SHA`.
- **Retrieved:** 2026-11-28 (a full clone, every file censused).
- **Licence (README verbatim):** "Creative Commons Attribution-NonCommercial 4.0
  International (CC BY-NC 4.0). https://creativecommons.org/licenses/by-nc/4.0/ The
  original images are in the public domain. The license applies to the layout and OCR
  data." `LICENSE` is the CC BY-NC 4.0 legal code. → `license_class: nc`. The fixture
  is a small excerpt redistributed under the same terms, with this attribution.
- **What it is:** uncorrected machine OCR (the Ottoman-Print-OCR-Qwen4B vision-language
  model; regions and lines by two YOLO26s models) of 59 printed Ottoman Turkish works.

## Delivery grains upstream serves (and which the adapter takes)

| Grain | Where | Taken? |
|---|---|---|
| Work (one book volume or serial run) | `data/<work>.js` — `window.__W=window.__W\|\|{};window.__W["<work>"]=` + a JSON object `{id, title, nw, nc, pages}` + `;` | **TAKEN** — one document per work |
| Page `{n, im, w, h, R, L}` | inside each work file; `n` the page label (image ordinal, `"3–4"` for a two-page spread, `"-"` for a calibration chart) | **TAKEN** — one passage per page with text |
| Line / region entry `[class, polygon, text, region index]` in `L` | inside each page | text joined by `\n` in upstream order (not a passage: 8,599 entries hold a whole region's text with embedded newlines, so upstream is not line-grained throughout); `page_number` entries ride the `printed_page` annotation; polygons, region boxes `R`, region index and image size dropped |
| Catalogue | `data/manifest.js` — `window.__MANIFEST=` + `{works, hasText, imageBase, dataBase, author, email}` | read for metadata, not a document |
| Colour-calibration chart page | pages with `"cal": true` (9 in the pin, all textless) | **REJECTED by rule** — counted per document (`calibration_pages`); specimen: `esariziyapasa.js` page `-` |
| Earlier per-line transcription | `transcriptions_ziyapasa.json` (root; 73 pages of the Eşʿâr-ı Ziyâ as `{page_N: {lines: [{transcription, polygon, bbox, inferred}]}}`) | **REJECTED by rule** — `discovery_skips` (superseded by `data/esariziyapasa.js`; only 931 of its 3,615 distinct lines recur verbatim; the viewer never loads it); specimen: page_10 only |
| Viewer, models | `index.html`, `yolo26s_region_printed_24_06_2026.pt`, `.nojekyll` | rejected at the fetch (outside the sparse cone) |

## Census of the pin (2026-11-28, full clone, through the adapter)

- 59 manifest works = 59 `data/*.js` (none unlisted, none missing); pages 24,375 (= the
  manifest's per-work `pages`), L entries 868,783 (= the manifest's `lines`), words
  2,501,215 (= the manifest's `words` and the files' `nw`).
- Pages: 7,470 with text → passages; 16,837 segmented but textless (680,866 empty L
  entries — upstream OCR'd only part of most volumes, e.g. Evliyâ vol. 1: 130 of 698
  pages); 59 with only a page number; 9 calibration charts.
- Passage text: 270,810 lines, 2,485,641 words (the rest of the 2,501,215 are page
  numbers).
- Scan order: 18 works have printed page numbers descending through upstream's image
  order (the back-to-front Toronto scans and four more) — kept, flagged
  `page_order: descending`.
- Dates in the manifest: `year_g`/`year_min`/`year_max` typed on 52 works; a Hijri label
  alone on 5 (`Kanunnamei_Ali_Osman` 1329, `kamus__turki` 1317, `katip_celebi_tuhfe`
  1141, `nzhetlerv00usayuoft` 1320, `tevarihiliosma00lutfuoft` 1341); neither on 2
  (`divan__nedim`, `kavaidi_esasiye_harbiyye`). Upstream types no place.

## OCR quality (measured 2026-11-28)

- Of 10,895,872 non-space characters: 95.7 % Arabic-script, 0.20 % Latin letters,
  0.95 % ZWNJ/ZWJ, the rest punctuation and digits; 0 U+FFFD; 0 control or bidi
  characters; 427 entries change under NFC.
- 3,188 of 270,810 passage lines (1.18 %) carry a Latin letter: 910 of 10,374 in the
  Kâmûsü'l-aʿlâm (8.77 % — printed French name forms), 2,278 of 260,436 elsewhere
  (0.87 % — library plates, plus mid-word hallucinations like `قضanak`, `منزelnی`).
- 24 entries repeat one token four times running — all table-of-contents dot leaders,
  no generation loops.

## The fixture (cut with a scratch script from the clone)

Each work file keeps upstream's exact serialization (`json.dumps(…, ensure_ascii=False,
separators=(",", ":"))` round-trips the originals byte for byte), its pages array cut to
the listed indices; nothing else changed (the `nw`/`nc` totals stay the whole work's).

| File | Pages kept (array index → `n`) | Why |
|---|---|---|
| `data/tarihipeevi01peuoft.js` (Tarih-i Peçevî vol. 1, 1866) | 4 → `5`, 6 → `7`, 200 → `201` | printed pp. 504 then 502 (a back-to-front scan), a heading region, and a segmented but untranscribed page |
| `data/esariziyapasa.js` (Eşʿâr-ı Ziyâ, 1881) | 0 → `-`, 7 → `7`, 8 → `8` | the calibration chart (rejected grain), the title page, the first poems (41 line entries) |
| `data/Kanunnamei_Ali_Osman.js` (Kanunname-i Âl-i Osman, 1329 AH) | 0 → `1–2`, 1 → `3–4` | two-page spreads; header, footnote and page-number classes on one page |
| `data/manifest.js` | the three works' entries, top-level keys intact (upstream's `json.dumps(…, ensure_ascii=False)` form) | |
| `transcriptions_ziyapasa.json` | `page_10` only (upstream's `indent=2` form) | the rejected root grain |

Recipe: `git clone https://github.com/koras0ff/OttomanOCR-search` at the pin, then for
each work file strip the `window.__W…=` prefix and trailing `;`, `json.loads`, keep the
pages listed above, re-dump with the separators above and re-wrap; trim the manifest's
`works` to the same three ids.
