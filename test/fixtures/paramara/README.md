# Paramāra fixtures — the Siddham network's Zenodo community `paramara`

Real upstream data retrieved **2026-11-02** from the Zenodo REST API:
`GET https://zenodo.org/api/communities/paramara/records?size=25&page=N`
(the community's own total: 153 records) and, per text record,
`GET https://zenodo.org/api/records/<id>/files/<key>/content`.

## Delivery grains (community census 2026-11-02, 153 records)

- TEXT RECORD — one `PMR###.txt` (114): the accepted grain, one document
  each. A "Key: value" header, a `Text{1}` marker, the line-numbered IAST
  edition (plate/side headings between), a dashed rule, `{n}` footnotes.
- EPIDOC HYBRID — `IN060027.txt` (1): a Siddham EpiDoc file pasted under
  a PMR14 header; the same inscription as `PMR14.txt` → skipped by rule.
  Specimen: `18416373/IN060027.txt`.
- IMAGE / PDF RECORD — estampage photographs and scans (36, incl. the 3
  cc-by-nc-nd records) and FILE-LESS records (2): never downloaded,
  skipped by rule from the listing. Specimens: records 447273 (one .jpg,
  cc-by-nc-nd-4.0) and 8189595 (no files) in `records.json`.

114 + 1 + 38 = 153.

## Files

- `records.json` — TRIMMED listing: six real record objects (verbatim
  from the API pages, ids 447273, 8189595, 18416373, 19562560, 22934821,
  22938192), sorted by id — the shape the fetch writes (the full listing
  holds all 153).
- `22938192/PMR203.txt` — WHOLE (1,851 B). Būdhērā pillar inscription of
  the time of Gaṇapati: header, 7 numbered lines, 10 footnotes.
- `22934821/PMR198.txt` — WHOLE (10,813 B). Rājpur copper-plate charter
  of Raṇadhavala: "First Plate" / "Second Plate: First Side" sections,
  56 lines, a two-date Period ("VS 1148 and 1127").
- `19562560/PMR47.txt` — WHOLE (7,035 B). Pipliānagar copper plate of
  Arjunavarman: the verse-laid edition WITHOUT line numbers (three files
  of the community).
- `18416373/IN060027.txt` — WHOLE (3,069 B). The rejected EpiDoc hybrid.

## License

Each record's `metadata.license.id`: `cc-by-4.0` on all 114 text records
(the 3 `cc-by-nc-nd-4.0` records are image-only). → class `attribution`.
