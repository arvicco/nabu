# ben-yehuda fixtures

Project Ben-Yehuda's public-domain dump —
<https://github.com/projectbenyehuda/public_domain_dump>, **release tag
`2026-03`** (the tenth release, published 2026-03-07; annotated tag object
`ae21f28c`, commit `5e4277fead7b565f32cc4b352abd3565023a77d8`). Retrieved
2026-11-18 by raw GET from
`https://raw.githubusercontent.com/projectbenyehuda/public_domain_dump/2026-03/<path>`;
the period browse pages from `https://benyehuda.org/authors?ckb_periods[]=<band>`
the same day.

License (`LICENSE`, verbatim): "The data files in this repository are in the
public domain, so you are free to make any use of them, and do not need to
ask for permission. If you would like to give credit, please credit "Project
Ben-Yehuda volunteers", and include a link to the site." The credit is
requested, not required; the adapter carries it.

## Upstream's delivery grains

The dump serves every work three ways, each tree one directory per author
(`p<authority id>/m<work id>.*`):

| Grain | Taken? | Specimen here |
|---|---|---|
| `txt/` — plain text **with nikud** | **TAKEN** (the document) | five works, below |
| `txt_stripped/` — the same text, pointing removed | rejected, skipped by rule | `txt_stripped/p161/m2245.txt` |
| `html/` — the same text as HTML | rejected, skipped by rule | `html/p161/m2245.html` |
| the release zips (`txt.zip`, `txt_stripped.zip`, `html.zip`, 246–284 MB) | not used — the same bytes as the trees; the fetch is git | — |
| `pseudocatalogue.csv` — the catalogue (ID, path, title, authors, translators, author_uris, translator_uris, original_language, genre, source_edition) | read for metadata + the band join | five-row excerpt |

No epub/pdf/docx in the dump (the site renders those on demand through its
API). The fetch's sparse cone never materializes the rejected trees or any
out-of-band author directory; a rejected-variant file found on disk is
counted in `discovery_skips` with its note.

**The period** is not in the dump at all (no catalogue column; the html head
names only title + author). The site's API serves it but needs a key; the
public author browse filters by the same period enum keylessly — the four
`site/` trims are real pages of that browse, and `periods.json` is what the
adapter's period fetch wrote from them.

## Files

- `txt/p1470/m34427.txt` — Yannai, "יוֹדֵעַ מִנֶּפֶשׁ" (ancient band): the
  title line, a tab line, the superscription "לאחד הסדרים שבפרשת נח", six
  verse blocks, the volunteers' closing credit line. 7 passages.
- `txt/p1470/m34421.txt` — Yannai, "אָב לִבּוֹ כְּלִבָּךְ": section numerals
  (א, ב, …) on lines of their own → annotation `section`; one line carrying
  nothing but a lone rafe (U+05BF) — upstream's stray point, counted in
  `stray_blocks`, never a passage.
- `txt/p161/m2245.txt` — Yehuda Halevi, "[דוד מתקו מליו]" (medieval band):
  four verses, each its own block; non-NFC pointing (the NFC-exemption
  regression).
- `txt/p161/m8750.txt` — an anonymous Arabic poem in Halevi's Hebrew
  (`translators` יהודה הלוי, `original_language` ar): a translation sits
  under its TRANSLATOR's directory, so the band judges the Hebrew.
- `txt/p141/m19.txt` — Rachel Bluwstein, "הֲלָךְ נֶפֶשׁ": out of band (p141 is
  in neither pre-modern band), skipped by rule. Also shows upstream's
  strophic layout (lines run together, stanzas split by whitespace-only lines).
- `pseudocatalogue.csv` — the header + the five rows for the works above,
  byte-identical lines.
- `LICENSE`, `VERSION` (`2026-03`) — whole.
- `site/authors-ancient.html`, `site/authors-medieval-{1,2,3}.html` — the
  browse pages cut to two entries each (page chrome dropped, the list items
  and the paging row byte-identical); medieval walks three pages through
  the "לדף הבא" cursor, page 3 carrying no next button.
- `periods.json` — the sidecar (2 ancient + 6 medieval authors).

## Census at the pin (2026-11-18)

The dump: 26,455 catalogue rows under 949 author directories (1,203 distinct
author strings). The site's bands: 13 ancient + 202 medieval authors. In
band in the dump: 206 directories / 6,043 works (ancient 9 / 84; medieval
197 / 5,959); 9 band authors hold no dump directory (the anonymous paytan's
578 site works among them).
