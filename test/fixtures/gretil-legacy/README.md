# gretil-legacy fixture

Trimmed REAL members of GRETIL's three legacy (pre-TEI) download zips,
retrieved 2026-10-21 from https://gretil.sub.uni-goettingen.de/gretil/:

| zip | bytes | Last-Modified |
|---|---|---|
| `2_prakrt.zip` | 1,477,038 | 2020-06-05 |
| `3_nia.zip` | 945,626 | 2020-06-05 |
| `4_drav.zip` | 8,753,197 | 2020-06-26 |

The tree is laid out exactly as `Nabu::ZipFetch` lands each zip in its
collection subdir: `3_nia.zip` and `4_drav.zip` carry one top dir each,
which the unpack strips; `2_prakrt.zip` carries TWO top dirs
(`2_prakrt/` and `home/mmehner/Spiegel_P/2_prakrt/`), so both stay.

## Delivery grains (every grain upstream serves, and the verdict)

| grain | upstream count | verdict | fixture specimen |
|---|---|---|---|
| legacy e-text `*.htm` with a language row (Prakrit, NIA) | 8 + 13 | **document** | `2_prakrt/2_prakrt/dasaveyu.htm`, `…/halsatsu.htm`, `3_nia/marathi/kutmir_u.htm` |
| the Malayalam e-text (Jyotsnikā) | 1 | document, **quarantined** (no Malayalam registry node) | `4_drav/malayalam/jyotsniu.htm` |
| `home/mmehner/Spiegel_P/2_prakrt/*.htm` — byte-identical second copy | 8 | skip by rule (packaging duplicate) | `2_prakrt/home/mmehner/Spiegel_P/2_prakrt/dasaveyu.htm` |
| `tamil/pm/*.htm` — Project Madurai e-texts in GRETIL's romanization | 199 | skip by rule (held in Tamil script by the madurai source) | `4_drav/tamil/pm/pm001__u.htm` |
| the Tamil TEI file, top level and `tei/` (byte-identical to the gretil TEI source's) | 2 | skip by rule | `4_drav/ta-sa_…xml`, `4_drav/tei/ta-sa_…xml` |
| `tei/transformations/` html + plaintext + css renditions of it | 3 | skip by rule | all three |
| Bachchan's Madhuśālā (1935; modern, in copyright) | 1 | skip by rule | `3_nia/hindi/bacmadhu.htm` |
| the CSX-based Ardhakathānaka (the CSX+ twin is kept) | 1 | skip by rule | `3_nia/hindi/bardhkcu.htm` |

Reconciliation with GRETIL's own index (gretil.html): Prakrit lists 8
files (8 in the zip, plus the 8 duplicates); New Indo-Aryan 15 (15);
Dravidian 200 Project Madurai links + Jyotsnikā — the zip holds 199 PM
files (pm013 is index-listed, absent from the zip) + 1. Full-zip census
through the adapter: 22 refs → 21 documents / 81,251 line passages
(2_prakrt 8 / 31,400; 3_nia 13 / 49,851), 1 quarantined, 214 skipped by
rule, 0 unrecognized.

## Trims

Every `*.htm` keeps its whole header and GRETIL notice block (through the
second `<hr>`) plus the first 16–32 body lines, then the file's own
closing `</body></html>`; line endings are upstream's (CRLF in
2_prakrt). The two specimens whose text may not ride a public tree keep
NO body lines — the Madhuśālā (in copyright) and the Project Madurai file
(Project Madurai's distribution condition; the madurai source keeps its
fixtures local) — the skip rule reads their path, never their text. The duplicate under `home/` is the same trim of the same
bytes. The two TEI copies keep the header and the text through the first
verse group (495 lines), closed with the file's own end tags (checked
well-formed). The plaintext rendition keeps its first 40 lines, the html
rendition its first 164 (closed); the css is whole.

## Refresh

Re-fetch the three zips (or the per-file URLs in manifest.yml), unpack as
above, and re-cut the same trims (the line counts are in manifest.yml).
