# makhzan fixture

Retrieved 2026-11-27 from OpenITI MAKHZAN, version 2026.1.2 — Zenodo
record https://zenodo.org/records/19861912, DOI 10.5281/zenodo.19861912
(published 2026-04-28; Parkes Allen, Mullan, Nigst, Barber, Shahid Khan,
Seydi, Chen, Weng, Vogler, Murel, Eshera, Berg-Kirkpatrick, Smith, Bowen
Savant, Thomas Miller, Verkinderen).

License, verbatim from the record's license field: `cc-by-nc-sa-4.0`
(Creative Commons Attribution Non Commercial Share Alike 4.0
International). The release notes and the deposited files state no other
terms.

The record's files (API https://zenodo.org/api/records/19861912):

| file | size | md5 |
|---|---|---|
| OpenITI-Makhzan_Data_2026-1-2.zip | 6,109,859,716 | 347a06a5714091665b7292775840a0f0 |
| OpenITI-Makhzan_Metadata_2026-1-2.tsv | 568,495 | 26e448803e90274a228ebee2a9df7e96 |
| OpenITI-Makhzan_ReleaseNotes_2026-1-2.pdf | 86,921 | 490b22ec83b5e445c191c0bf671233e5 |

The zip is a zip64 archive of 208 STORED per-document zips (`Doc<id>.zip`),
each holding the page images, one ALTO v4 XML per page (eScriptorium's
export) and a `METS.xml` giving the page order. The zip's central
directory sha256 is `23d6c81b85dcd514394806d369aa59b1fa5a3fc6b2cc252acc9cc9fe2a8bb544`.

## The workdir as `Nabu::MakhzanFetch` lands it

- `OpenITI-Makhzan_Metadata_2026-1-2.tsv` — the record's TSV TRIMMED to its
  header and the rows of the documents below plus two Persian documents
  (Doc 37, 38 — the rejected-grain specimen); bytes and CRLF line ends
  otherwise upstream's.
- `Doc102/` — Leiden Or. 1076, Vâhidi's Kitāb-i Ṭavāʾif-i ʿaşere (1569,
  taliq): its one page `102_14122.xml` and `METS.xml`, both WHOLE.
- `Doc3178/` — Leiden Or. 1094, a mecmūʿa ("c. 1500", Arabic/Ottoman/
  Persian, `LANG="mul"`): its one page `3178_748159.xml` and `METS.xml`,
  both WHOLE.
- `Doc3262/` — Leipzig B. or. 232, the Revnaḳ-ı Būstān ("17th c.", Place of
  Origin "Ottoman Empire"): TWO of its ten pages (`3262_759523.xml`,
  `3262_759525.xml`, whole) and its `METS.xml` trimmed to those two pages
  (the `<file>` entries and `<div TYPE="page">` of pages 3–10 removed,
  structure otherwise intact); the TSV keeps only those two parts' rows.

Each member was read out of the deposit zip by HTTP Range (no per-file URL
exists). No page image is checked in: the images are the grain this source
rejects, and their bulk is what the Range read avoids.

## `fetch/` — the fetch test's real bytes

- `fetch/record.json` — the record API response, WHOLE.
- `fetch/metadata.tsv` — the TSV trimmed to its header and the rows of Doc
  37, 38 (Persian), 102 and 3213 (Ottoman).
- `fetch/ranges/<first>-<last>.bin` — every byte range `Nabu::RemoteZip`
  read off the real zip to land Doc102 and Doc3213 (the size probe, the
  zip64 tail, the outer directory, each nested zip's local header, tail and
  directory, and each XML member's local header + data), byte-identical.
  `test/support/makhzan_ranges.rb` serves them as the 6.1 GB file; a range
  no capture covers answers 416.

## Delivery grains (everything the record serves)

| grain | taken? |
|---|---|
| ALTO v4 page XML (`Doc<id>/<doc>_<part>.xml`) of an Ottoman document | TAKEN — passage = transcribed TextLine, cited `<part>.<line ordinal>` |
| METS.xml (page order) of an Ottoman document | TAKEN — the reading order of the pages |
| metadata TSV (one row per page) | TAKEN — document metadata, the selection, the line-count reconciliation |
| documents in other languages (Arabic, Persian, Urdu, Malay, Javanese) | rejected, skipped by rule — the TSV rows of Doc 37/38 are the specimen; never fetched |
| page images (jpg/png inside each document zip) | never fetched (the zip's bulk) |
| release-notes PDF | never fetched (no text; it states no terms) |
| empty TextLines (segmented, untranscribed) | mint nothing; their ordinals stay reserved |

## Census (2026-11-27, the whole record)

208 documents in the zip and the TSV alike (the release notes: "1,497 page
images across 208 documents"). Ottoman Turkish (a TSV Language naming it,
four mixed: "Arabic, Ottoman Turkish, Persian", "Ottoman Turkish,
Baleybelen", "Ottoman Turkish, Persian", "Ottoman Turkish, Arabic,
Persian"): 30 documents / 248 pages / 3,868 TextLines, 3,762 transcribed
— equal, page by page, to the TSV's Transcribed Lines Count. Volume dates
1438–1869. The other 178 documents: Arabic 121, Persian 44, Urdu 8, and
mixed Arabic-Persian, Malay and Javanese. Reading the 30 documents' XML by
Range transferred 2,152,395 bytes in 372 requests (the TSV and record JSON
included) of a 6.1 GB archive.
