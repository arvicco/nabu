# socinian-letters fixture

Retrieved 2026-11-05 from the public GitLab project
https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump (Die
sozinianischen Briefwechsel, Akademie der Wissenschaften und der Literatur
Mainz), branch `main` at commit `5d9180784b3b2b6798b131b51e240a1ab1feb29f`
(the folder zip's own comment; last activity upstream 2026-04-29).

The adapter fetches two artifacts:

- the folder archive
  `https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/archive/main/csv-data-dump-main.zip?path=data/xml/letters`
  (13 MB, 2,221 members under ONE top directory
  `csv-data-dump-main-data-xml-letters/` — 2,217 letter files + 4 directory
  entries; ZipFetch strips the top directory, so the tree lands as
  upstream's own `data/xml/letters/`);
- the register `https://gitlab.rlp.net/adwmainz/digicademy/sbw/csv-data-dump/-/raw/main/data/csv/indices.csv`
  (1,053,733 bytes) into `data/csv/`.

This directory mirrors the landed tree: `data/xml/letters/*.xml` are whole,
byte-identical copies of the raw files (each GET from
`…/-/raw/main/data/xml/letters/<name>` and compared against the zip member);
`data/csv/indices.csv` is a TRIM (below).

## Delivery grains (every grain upstream serves)

| grain | where | taken? |
|---|---|---|
| letters folder zip | `data/xml/letters/` (2,217 files; the tree listing's X-Total) | TAKEN — the one text artifact |
| letter file | `LETTER_<id>.xml`, a `teiCorpus` | TAKEN — document = file, keyed by the cover TEI's xml:id |
| cover letter | `TEI n="cover_letter"` (2,217) | TAKEN — the document's first component |
| attachment | `TEI n="attachment"` (470 occurrences, 439 distinct ids) | TAKEN — held by ONE file, deduped by TEI id (56 ids are themselves cover letters, held by their own file; 16 more repeat across files, held by the first transcribed carrier); others list it in `attachments` with `held_in` |
| witness | `TEI n="reference_witness"` (2,687) + further witnesses (644, no `@n`, `@corresp` to the reference) | the reference witness is THE text; a further witness only when the reference is untranscribed (3 cover letters); never both |
| text block | p / head / opener / closer / dateline / postscript / address / lg / list / table inside the witness `<text>` | TAKEN — passage = block |
| editorial note | `<note>` without `@hand` (the editors' German commentary, 6,204 with xml:id) | not text — rides the block's `notes` annotation |
| metadata-only letter | a file none of whose held components has a transcribed witness (revisionDesc "Metadaten publikationsbereit" only) | REJECTED — skipped by rule (counted in `discovery_skips` with its note); pinned here: `LETTER_MAIN_ed_nnl_xb5_r5b.xml` |
| register | `data/csv/indices.csv` | TAKEN as lookups (GND, GeoNames, life dates) — skipped by rule as a document |
| single-TEI texts | `data/xml/texts/` (2,689 files — the same components unbundled) | REJECTED — never fetched (every one rides inside a letter file) |
| CMIF | `data/cmif/corresp.xml`, `corresp-attachments.xml` | REJECTED — never fetched (the same correspDesc; the register join carries the same GeoNames/GND refs) |
| derived tables | `data/csv/{letters,corresp,relations}.csv`, `data/json/*`, `data/beacon/*` | REJECTED — never fetched (views generated from the same TEI) |
| project texts | `meta-texts/` (introductions, guidelines, section introductions) | REJECTED — never fetched (modern editorial prose, not edition text) |

Reconciliation (through the adapter over the whole zip, 2026-11-05):
upstream's 2,217 letter files = **1,869 accepted + 348 skipped by rule**
(metadata-only). 1,869 documents / 18,067 passages, 0 errors.

## The fixture files

- `LETTER_MAIN_ckw_qlm_zdb.xml` — Johann Ernst von Rautenstein (Regensburg)
  to Stanisław Lubieniecki (Hamburg), 15 October 1665 (Theatrum cometicum
  print): the plain case — one reference witness, Latin, a page break,
  GeoNames-linked sending and receiving places.
- `LETTER_MAIN_lfw_qlm_zdb.xml` — Lubieniecki to Nicolaus Heinsius
  (Stockholm), 23 October 1665: carries `MAIN_ckw_qlm_zdb` as its
  ATTACHMENT — the dedup case (held by its own letter file above; the test
  removes that file to show the attachment riding its cover letter, and
  twins this file to show a repeated attachment held once).
- `LETTER_MAIN_anw_qlm_zdb.xml` — Lubieniecki to Christiaan Huygens,
  16 February 1667: the reference witness is UNTRANSCRIBED (`<p/>`), the
  second print witness carries the text — the witness-rule fallback.
- `LETTER_MAIN_u3w_qlm_zdb.xml` — an anonymous writer (NN, Küstrin) to
  Lubieniecki, 14 March 1665: a French letter (langUsage `fra`) whose Latin
  version sits in `<foreign xml:lang="lat">` (passage-grain language); no
  sender persName; the register's place label (Küstrin) against the header's
  (Kostrzyn).
- `LETTER_MAIN_ydw_qlm_zdb.xml` — Fausto Sozzini (Kraków) to Krzysztof
  Morsztyn the Elder, 12 March 1597: the reference witness is licensed
  **CC BY-SA 3.0** while the corpus and cover headers say CC BY 4.0 — the
  per-TEI licence case.
- `LETTER_MAIN_dq3_2dc_b2b.xml` — Ismaël Boulliau (Paris) to Lubieniecki,
  30 March 1663 (a manuscript draft): the markup-rich case — `<del>`/`<add>`,
  `<gap>`, `<choice><sic>/<corr>`, a marginal `<note hand="#author">`, an
  editorial `<seg type="comment">` note, a postscript, `<rs>` persons/places.
- `LETTER_MAIN_ed_nnl_xb5_r5b.xml` — Calvin (Geneva) to Lelio Sozzini, 5
  June 1555: the REJECTED grain's specimen — metadata only (`<p/>` body,
  revisionDesc "Metadaten publikationsbereit"), asserted skipped by rule.
- `data/csv/indices.csv` — TRIM of the 12,029-row register: the header plus
  every row (entry, altName, normdata) whose `sbw_id` is a correspDesc
  persName/placeName key of the fixture letters (56 rows), verbatim and in
  upstream order.

## Census of the whole zip (through the adapter, 2026-11-05)

Document language (the chosen witness's langUsage): lat 1,561 · fra 207 ·
deu 77 · pol 13 · nld 6 (upstream writes "Niederländisch") · ita 5. Passage
language: lat 14,235 · fra 2,170 · deu 1,339 · ita 186 · pol 116 · nld 21.
Licence of the chosen witnesses: CC BY 4.0 on 1,779 documents, CC BY-SA 3.0
on 90. Dated (sent date) 1,850; sending place named 1,761, GeoNames-linked
1,685; sender named 1,801 (GND 1,663). #sbw classCode: Brief 1,495 ·
Brief/Briefexzerpt 291 · Briefexzerpt 44 · none 20 · Beobachtungen 6 · and
nine singletons/pairs (kind_map.yml).
