# med-headwords fixture

A trimmed real sample of the Middle English Dictionary editors' entry list,
"Headwords, variant spellings, and IDs" — the "Most recent version (October
2023)" listed on <https://medictionary.info/pages/headwords.html>.

- **File**: `headwords_202310.xml`, retrieved 2026-11-26 from
  <https://medictionary.info/pages/headwords_202310.xml>
  (HTTP 200, `Content-Type: application/xml`, 19,396,721 bytes,
  `Last-Modified: Mon, 23 Feb 2026 18:34:10 GMT`,
  ETag `"127f871-64b8204492c80"`).
- **Full-file sha256** (the adapter's `LIST_SHA256` pin):
  `e530ecacd3b94d79327882cdc32f1e1a0fcbbf32183bdb18a0a46f3eff56b268`
- **List vintage**: 2023-10 (the file-name stamp and the page's own heading).
  The editors note each list reflects their working copy — it may include
  entries not yet in the online MED, and its `@DEL` entries may still be live
  there — and that a refreshed list is planned.

## The trim

The XML declaration, stylesheet PI, DOCTYPE and `<HEADWORDS>` wrapper are
kept verbatim, with 15 of the 57,094 `<ENTRY>` lines, each copied byte for
byte (every non-empty line of this file occurs verbatim in the upstream
file — checked at cut time). Upstream serves one entry per line, so a line
cut keeps every entry structurally whole. The entries were chosen to pin the
upstream quirks:

| Entry | Pins |
|---|---|
| MED1, MED2 | homographs (ā n.(1) / n.(2)); the NCR-encoded macron |
| MED2.5 | a decimal (post-print) id with `@RESP` |
| MED3 | the long "Also … Early forms: …" prose with many ORTHs |
| MED28 | two HDORTHs, the second an abbreviated ORIG (`-ǒunen`) |
| MED84.5 | `@DUB="Y"` (queried entry) |
| MED261, MED927 | `<HI REND="B">` / `<HI REND="I">` runs; ȝ in MED927 |
| MED979, MED1431 | the `<!-- maybe -->` doubtful-REG mark; MED1431's two PS |
| MED1519 | an empty `<POS/>` |
| MED2039 | `@DEL="Y"` (flagged for deletion) |
| MED5005.5 | an ORTH carrying two ORIGs |
| MED20283 | an ORTH with no ORIG at all |
| MED54083 | the last entry (SEQ 57094) |

## Grain census (whole upstream file, 2026-11-26)

What medictionary.info serves on the headwords page — every grain:

- **Accepted**: `headwords_202310.xml` — one XML file, the document; one
  `<ENTRY>` = one dictionary entry.
- **Not fetched** (superseded vintages of the same list, linked from the same
  page): `headwords_202210.xml` (October 2022, same format),
  `headwords_forms_and_IDs.202112.xml` (December 2021, same format),
  `MED_heads_and_ids_202108.html` (September 2021, HTML `<dl>`),
  `heads_with_diacritics.ncr.html` (September 2020, HTML, no variants),
  `MED_lemmata_with_ids.update201712.xml` (December 2017, no variants), the
  August 2007 `MED_lemmata_with_ids.xml` and `MED_all-forms_with_ids.xml`.
  The adapter fetches only the pinned file; another vintage dropped into the
  workdir is skipped by rule (tested with a renamed copy of this file — no
  older vintage was downloaded). The DTD (`headwords.xml.dtd`) and CSS are
  referenced by URL and never fetched (the entities are numeric NCRs).

Inside the file:

- 57,094 `<ENTRY>` (= the advertised SEQ range 1–57,094, in order), 57,094
  unique `@ID` values, all `MED<n>` or `MED<n>.<m>` (2,587 decimal).
- `@SEQ` on every entry; the preceding `<!-- SORT>nnnnn</SORT -->` comment
  equals SEQ zero-padded on all 57,094 (not mined twice).
- `@RESP` 2,564 (lattaj 1,492 · pfs 681 · monall 386 · alyalden 4 ·
  lattajandpfs 1); `@DUB="Y"` 398; `@DEL="Y"` 91 (all kept, flagged).
- Inside `<FORM>`: `HDORTH` 57,790 (636 entries carry more than one), `ORTH`
  136,618, `POS` 57,094 (one per entry; 8 empty), `PS` 57,959 with `@EXPAN`
  on all (noun 27,098 · verb 10,323 · adjective 8,732 · adverb 4,167 ·
  gerund 4,032 · participle 2,183 · preposition 257 · phrase 220 · …
  33 classes), `HI` 698 (`@REND` B 482 · I 216).
- Each HDORTH/ORTH: one `ORIG` (display, as printed) + one or more `REG`
  (search forms) — REG 239,481, ORIG 194,408; one ORTH has two ORIGs
  (MED5005.5), one has none (MED20283); 721 REGs carry a `<!-- maybe -->`
  comment.

Fields mined per entry: `@ID` (entry id + the online URL
`https://quod.lib.umich.edu/m/middle-english-dictionary/dictionary/<ID>`),
`@SEQ`, `@RESP`, `@DUB`, `@DEL`, every HDORTH/ORTH ORIG and REG, the maybe
marks, the POS text and every PS `@EXPAN`, and the form-section prose (HI
text in place).

## License

Granted by email, 2026-11-06, by Paul F. Schaffner (Middle English
Dictionary, University of Michigan): "to be used in whatever way you choose.
No conditions whatever" — with one courtesy request, that the list is never
re-posted for download, and credit to the MED. This 15-entry excerpt is a
test sample, not the list.
