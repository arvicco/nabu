# osbct fixture

Retrieved 2026-11-02 from Zenodo record 23541744 (v2.11.0, 2026-10-21;
concept record 21495338), file `bthar-mx/OSBCT-v2.11.0.zip`
(463,341,640 bytes, md5 8d89920db175cd59ddd50025434f2d21 = the record's
checksum; central-directory sha256 3d1c2b1b…5f77, the adapter's pin), via
https://zenodo.org/api/records/23541744/files/bthar-mx/OSBCT-v2.11.0.zip/content

The tree is the zip as ZipRangeFetch lands it (the single top directory
`bthar-mx-OSBCT-abfd4f7/` stripped). This README replaces the deposit's own
README.md (same path); `.zenodo.json` (in the fetch cone) is not copied.

## Delivery grains (every grain the deposit serves; 46,326 members)

| grain | file(s) | taken? |
|---|---|---|
| volume | `site/<VOL>.json` (118: 40 canon, 52 commentary, 26 subcommentary — data/concordance.json's placement) | TAKEN — the document; one passage per paragraph (89,512) |
| apparatus, ordinal-keyed | `site/reader/apparatus/<VOL>.appk.json` (118; 73,431 notes) | TAKEN — per-paragraph annotations |
| volume tables | `data/concordance.json` (layer + work group), `site/downloads.data.json` (work title, PDF key) | read as metadata; the latter, with `site/build.json`, `site/concordance.json` (a copy) and `site/errata.json`, are the non-volume `site/*.json`, skipped by rule (counted) |
| apparatus, id-keyed | `site/reader/apparatus/<VOL>.app.json` (the same notes keyed by the hierarchical id, which is not unique) | rejected — outside the Range cone; one specimen pinned |
| reader side maps | `site/reader/{verse,bold,nav,sections,toc,…}` | rejected — outside the cone |
| search index | `site/index/` (per-volume shards, postings) | rejected — derived, outside the cone |
| lookup stores | `stores/lookup*/` (word lookups built with DPD) | rejected — outside the cone |
| working files | `_xc/`, `_review/`, `_panel/`, `_gloss/`, `pipeline/`, `docs/`, the HTML reader, `*.js` | rejected — outside the cone |
| license / citation | `LICENSE.md`, `README.md`, `CITATION.cff`, `.zenodo.json` | fetched (license evidence); not text |

## The cuts

Three volumes, one per layer, each cut to its first K paragraphs (entries
verbatim; `headings` kept up to the last kept paragraph's printed page; the
JSON re-serialized with one-space indent), and each volume's `.appk.json`
cut to the kept ordinals:

- `site/08Di03.json` — canon, Pāthikavaggapāḷi (Dīgha III), 6 paragraphs;
  paragraph 0 carries two inline note markers (`nāma1`, `Anupiyāyaṁ2`)
  and two apparatus notes with Syā / Ka variant readings.
- `site/44KhuA25.json` — commentary, Cūḷaniddesaṭṭhakathā, 8 paragraphs;
  three unnumbered heading-like paragraphs, ordinal 5 with one marker and
  two notes. `site/reader/apparatus/44KhuA25.app.json` is the id-keyed
  twin, cut to the kept paragraph ids — the out-of-cone specimen.
- `site/24AbhiT03.json` — subcommentary, Pañcapakaraṇamūlaṭīkā, 5
  paragraphs; one of the 25 volumes WITHOUT the `vol`/`source` keys, and
  ordinal 3's note is a pure cross-reference (`Abhi-Ṭṭha 1. 8 piṭṭhe.`).

Kept whole: `LICENSE.md`, `CITATION.cff`, `data/concordance.json`,
`site/concordance.json`, `site/downloads.data.json`, `site/build.json`.

## Reconciliation (full unpack, 2026-11-02)

118 volumes accepted = the record's 118; 89,512 paragraphs = the record's
89,512; no empty paragraph text. Non-volume `site/*.json`: 4, skipped by
rule. Paragraph keys are unique per volume (ordinal on 114 volumes;
21KhuT01, 22AbhiT01, 23AbhiT02, 24AbhiT03 skip numbers from ordinals 138 /
261 / 277 / 534 on — the apparatus stays ordinal-keyed there, verified by
marker/note agreement). 70,599 inline markers; 75.4M characters.
