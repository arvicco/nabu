# pgp-geniza fixture

Real rows of the Princeton Geniza Project data export, trimmed: every
`data/*.csv` keeps upstream's header row and its UTF-8 BOM (upstream ships
`utf-8-sig`), and holds only the rows named below, re-serialized with Ruby's
CSV (minimal quoting, `\n` rows — upstream's own separator). Cell content is
never edited.

- Retrieved: 2026-11-16, `main` at `2234d35ec1d2f269eaa99f51832878ad873f57e7`
- Repository: https://github.com/princetongenizalab/pgp-metadata
  (raw files: `https://raw.githubusercontent.com/princetongenizalab/pgp-metadata/refs/heads/main/data/<name>.csv`)
- Dataset DOI (concept): https://doi.org/10.5281/zenodo.15839055 (latest deposit v1.2,
  10.5281/zenodo.22663982)
- License: CC BY-NC 4.0 — README "Sharing / access information" ("Dataset is released
  under the noncommercial Creative Commons Attribution 4.0 license (CC-BY-NC.4.0)"),
  `pgp_datapackage.json` `licenses: CC-BY-NC-4.0`, Zenodo license field `cc-by-nc-4.0`.
  Credit: Princeton Geniza Project, Princeton Geniza Lab, Princeton University.
- Cut recipe: select the documents.csv rows by pgpid, every footnotes.csv row naming
  those pgpids (plus the specimens below), the fragments.csv rows whose `pgpids` list
  names them, the sources.csv rows their footnotes cite, the places.csv rows their place
  relations name, and the first two people.csv rows.

## Grain enumeration (what upstream serves, what the adapter takes)

| Grain | Upstream file | Adapter |
|---|---|---|
| PGP document (pgpid) | `data/documents.csv` | **THE DOCUMENT** when it carries text: `urn:nabu:pgp-geniza:<pgpid>` (≥ 1 Digital Edition) and one `-<lang>` translation sibling per translation language |
| text footnote — Digital Edition / Digital Translation with `content` | `data/footnotes.csv` | the passages (one per non-blank line), keyed by the edition's source slug |
| citation-only footnote (Discussion, Edition, Translation … without content) | `data/footnotes.csv` | bibliography — not text; no passage (the document's `scholarship_records` already names them) |
| fragment / shelfmark (material support) | `data/fragments.csv` | joined by pgpid → `provenance` class + `material`; never a document |
| bibliographic source | `data/sources.csv` | joined by slug → a Latin-script translation's language; never a document |
| place authority | `data/places.csv` | joined by name → the origin's WGS84 point; never a document |
| person authority | `data/people.csv` | not joined (the export carries counts only, no document links) |
| dataset documentation | `README.md`, `CHANGELOG.md`, `CITATION.cff`, `pgp_datapackage.json` | never text (not in the fixture) |

### Rejected-grain specimens, each skipped by rule and counted in `discovery_skips`

- **metadata-only document** — PGPID 30423 (AIU VII.E.129, a dated 1807 letter with an
  origin): no Digital Edition or Translation → no ref.
- **text footnote whose relation names no digital layer** — PGPID 723's two blank-relation
  rows (Gil, *In the Kingdom of Ishmael* #454: one Judaeo-Arabic edition, one Hebrew
  translation, but upstream does not say which is which). 723 itself stays a document
  through its Udovitch Digital Edition.
- **text footnote naming a pgpid absent from documents.csv** — PGPID 3513 (T-S 18J1.24;
  its Goitein Digital Edition and two Discussion rows) — a suppressed/merged record.
- **text footnote with no document_id** — the Goitein unpublished edition
  (`goitein-s-d-unpublished-editions-7`, "עשרין / ויהבנא למרנ' ורב' מצליח…").

### The accepted documents

| pgpid | why it is here |
|---|---|
| 723 | Udovitch edition with Oded Zinger's emendations; also the undecidable-relation specimen |
| 1071 | Judaeo-Arabic edition + a **Hebrew-script** translation (→ the `-heb` sibling); `location` relation |
| 4737 | Judaeo-Arabic letter (Messina → Mazara), inferred date, edition + English translation; side labels ("Verso, address:") |
| 8339 | Arabic list in four columns ("First column" … labels) with Coptic epact numerals (𐋡 𐋬𐋤) and bare tatweel runs that fold to nothing (→ the `marks` annotation) |
| 8742 | Judaeo-Arabic book-sale record, Seleucid-dated, fragment material "Paper"; a run of four side labels with no text between |
| 16766 | Arabic Fatimid tax receipt (Hijri-dated) with **two** Digital Editions + English translation |
| 28363 | Aramaic ketubba — the NFC-exempt `arc` path (byte-verbatim); inferred 1790–1840; a closing no-break-space line |
| 36492 | translation-only (Goitein's English, no edition) — the axes ride the `-en` sibling |

## Reconciliation (live export, 2026-11-16)

36,512 documents.csv rows = 7,669 edition documents + 115 translation-only documents
+ 28,728 metadata-only skips. 10,601 text footnotes = 8,365 Digital Editions + 2,222
Digital Translations attached to live documents + 14 skipped by rule (7
undecidable-relation rows, 2 naming absent pgpids, 5 with no document_id). Upstream's own
flags agree to the residue: has_transcription Y 7,680 vs 7,669 edition documents. Translation siblings: 2,179
(en 1,396 · heb 775 · fr 7 · de 1). A full dry parse of the export: 9,848 refs,
303,860 passages, 0 parse errors.
