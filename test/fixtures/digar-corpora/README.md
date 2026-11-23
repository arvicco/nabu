# digar-corpora fixture

Real members of the National Library of Estonia's (Eesti
Rahvusraamatukogu) DIGAR open-data corpora, retrieved 2026-11-23 from
`https://data.digar.ee/` — read out of the remote zips with HTTP range
requests (central directory, then each member's local entry); neither
body was downloaded whole:

- `https://data.digar.ee/processed_pdf_tsv.zip` — 972,354,373 B,
  Last-Modified 2018-10-09, 3,416 members, all Deflate64 (method 9 —
  the system `unzip` reads it; Ruby's zlib does not);
- `https://data.digar.ee/processed_txt_tsv.zip` — 121,540,205 B,
  Last-Modified 2018-10-09, 5 members, Deflate.

License: the data.digar.ee page-wide statement, verbatim: "Avaandmete
kasutamisel nõustute Creative Commons Public Domain (CC BY-SA 3.0 EE)
litsentsitingimustega" (read as CC BY-SA 3.0 EE, the stricter reading);
the prints themselves are DIGAR "Vabakasutus" items (CC PDM 1.0) and the
ERB metadata is CC0 (digilab.rara.ee rights page, 30.03.2023).

## Layout (as it lands in canonical/digar-corpora/)

`processed_pdf_tsv/` — the text zip's flat tree, one EstNLTK token table
per book, named by its ERB/ESTER record id:

| File | Book | Why | Bytes |
|---|---|---|---|
| `b17885899.pdf.txt.tsv` | *Enne pihti* — hymn sheet, Riga 1819 (W. F. Häcker), Fraktur | the Fraktur tail; bad OCR (prop_nopunct_unsolved 0.742); no stamp; MARC 542 Vabakasutus | whole (14,054) |
| `b1275075x.pdf.txt.tsv` | Grünfeldt, *Kodulinnud lastele*, Tallinn 1923 | interwar children's verse; a conjectured imprint place `[Tallinn? :`; NO 542 rights field | **trimmed** to the header + its first 300 token rows (of 798) |
| `b20396119.pdf.txt.tsv` | Oro, *Nuku majake*, s.l. 193-? | 008 date1 `193u`; the digitizer's stamp on every page in both renderings, one of them OCR-mangled; absent from Tinits's processed ERB table (one of the 6 of 3,416) | whole (23,317) |
| `b1623912x.pdf.txt.tsv` | Schmid/Lorenzsonn, *Jenowewa*, Perno 1841 | REJECTED grain, skipped by rule at parse: an image-only PDF whose only text layer is the stamp (108 tokens = 27 stamps); its MARC record carries 041 `$aest$hger` and 752 `$dPärnu.` | whole (12,280) |
| `b10014949.pdf.txt.tsv` | Vaigur, *Lõukoerte koopas*, Tallinn 1938 | REJECTED grain, skipped by rule at discovery: a header-only table (pdf2txt found no text) — 531 of the 3,416 tables are exactly this, 186 bytes each | whole (186) |

`processed_txt_tsv/` — the metadata zip's five members, each trimmed
(header kept; rows below), structure untouched:

| File | Trim | Read? |
|---|---|---|
| `ERB_eestikeelne_raamat_July_2018.tsv` | the raw MARC rows (RecordNumber, Tags, Indicators, Content; blank row between records) of the five fixture books + record 1 (`b10000306`, a 1993 Roskilde print with no table — the catalogue-only record every non-corpus ERB book is) | yes — THE metadata join (001 id) |
| `fileinfo_stored_pub.tsv` | the five fixture books' rows (filesize, nrows, nrows_unsolved, prop_unsolved, nrows_nopunct, nrows_nopunct_unsolved, prop_nopunct_unsolved) | yes — the OCR census |
| `ERB_works_processed_v_29.07.2018.tsv` | the four fixture books it carries + `b10000306` | no (Tinits's cleaning of the same MARC; misses 6 corpus books) |
| `ERB_works_v_29.07.2018.tsv` | header + 2 rows | no |
| `ERB_genres_processed_v_29.07.2018.tsv` | header + 2 rows | no |

## Delivery grains upstream serves (data.digar.ee + digilab.rara.ee, 2026-11-23)

- **book token table** (`processed_pdf_tsv.zip`) — ACCEPTED: document =
  book. The table is a flat token stream (row index 0..n-1, no page,
  line or sentence boundary), so passages are deterministic token
  windows (the estnltk-tsv family note).
- **header-only table** — rejected, skipped by rule at discovery
  (`b10014949`).
- **stamp-only table** — rejected, skipped by rule at parse
  (`b1623912x`).
- **ERB bibliographic record** (`processed_txt_tsv.zip`) — a metadata
  sidecar, never a document (`b10000306` pinned).
- **n-gram lists** (`token_*_grams.tsv`, `lemm*_grams.tsv` — modern
  fiction frequency tables) — not fetched: no running text.
- **Kratt prototype** (`meta.jsonl`; `full_texts.zip` and
  `morphological_data.zip` now serve a 178-byte stub) — not fetched.
- **raw .txt export** of the same 3,416 books ("Küsi allikmaterjali .txt
  kujul (3416 faili kokku 196MB) data@nlib.ee") — email-gated, not
  fetched.
- **DEA newspaper articles** (dea.digar.ee, 1821–) — not in this asset:
  the article-text-XML endpoint is behind a Cloudflare challenge; bulk
  access is the University of Tartu HPC OnDemand environment by request.
- **"Vaba juurdepääsuga keelekorpus"** (digilab.rara.ee, 2026; 526 M
  tokens over books, newspapers, journals) — no download link published.

## Count reconciliation

Upstream advertises 3,416 files (the page's "3416 faili", the zip's
3,416 members, fileinfo's 3,416 rows). Expected first sync: 3,416 = 531
header-only (skip at discovery) + 2,885 non-empty tables, of which the
stamp-only share skips at parse (censused at the first real sync).
