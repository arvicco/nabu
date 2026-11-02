# hexapla fixture — the Göttingen Hexapla Database in Text-Fabric (tf/0.1)

Gap-anchored trimmed slices of the pinned `tf/0.1` Text-Fabric dataset of
[github.com/rdtaylorjr/hexapla](https://github.com/rdtaylorjr/hexapla) (R.
Taylor's conversion of the Göttingen Hexapla Database, NAWG, API v3).

- **Retrieved:** 2026-11-02, from commit
  `02bf17c3fe0520112cf42c5a11d62c0808aea08c` (main, 2026-10-10), via raw GETs
  of `https://raw.githubusercontent.com/rdtaylorjr/hexapla/main/tf/0.1/<name>.tf`.
- **Layout:** mirrors the sparse workdir the adapter fetches (`tf/0.1/*.tf`);
  docs/about.md, docs/transcription.md and LICENSE (also in the cone) are
  quoted below, not checked in.
- **Trim recipe:** headers byte-verbatim; data lines byte-verbatim for every
  node whose slots lie inside the kept chapters, written gap-anchored;
  empty values drop. Column (`text`) and book nodes keep their `oslots`
  line CLIPPED to the kept slots — the one non-verbatim edit. `otype.tf`
  and `otext.tf` ride WHOLE — the census of record. All 17 feature files
  are included.

## Upstream delivery grains

The repository serves the database twice: the raw API responses
(`source/0.1/<book>/<nnn>/<versekey>.json`, one per passage — 696 of 2
Samuel, 2,678 of the Psalms) and their Text-Fabric conversion (`tf/0.1`,
taken). The raw JSON is outside the sparse cone. Inside Text-Fabric the
node types are word (slot), word_group (a reading), stichos, verse,
chapter, book, text (a database column). The adapter takes **column ×
book** as the document and **verse** as the passage. Rejected, skipped by
rule and pinned here: the **Notes** column (both books — editorial notes
in mixed Latin and Greek, no languageISO), and **placeholder-only verses**
(every word the database's "-"; Field Ps 45:8, Field Latin Ps 45:8 and
45:12 in these slices), named in `omitted_verses`.

## Upstream census (at the pin, from otype.tf — checked in WHOLE)

182,462 words / 21 column books / 1,630 chapters / 18,048 verses / 36,929
stichoi / 13 columns / 131,805 readings. Full-data parse (2026-11-02): 19
documents / 16,302 passages / 169,420 tokens; the Notes column holds 314
verses; 1,432 verses are placeholder-only (Field 707, Field Latin 721,
LXX 1, MT 1, Aquila 2). about.md's count reconciles: 696 + 2,678 = 3,374
passages = the LXX edition column's 3,374 verse records. No verse address
repeats within a column book; no node is discontiguous.

## License (verbatim, retrieved 2026-11-02)

Live API response (versekey 1010001001, 2 Samuel 1:1): `"copyright": "Die
Editio critica maior des griechischen Psalters. Niedersächsische Akademie
der Wissenschaften zu Göttingen."`, `"license": {"label": "CC BY-NC-SA 4.0",
"url": "https://creativecommons.org/licenses/by-nc-sa/4.0/"}`. NAWG imprint
(septuaginta.uni-goettingen.de/imprint/): "Die Erschließungsdaten
einschließlich statistischer Auswertungen und Visualisierungen werden
unter CC BY-NC-SA 4.0 veröffentlicht." TF headers:
`@license=Creative Commons Attribution-NonCommercial-ShareAlike 4.0
International`. docs/about.md: "The source files and the Text-Fabric data
are licensed under the CC BY-NC-SA 4.0 license" → source class `nc`.

## The slices (2,008 words)

| book | chapters kept | columns (book nodes) | why |
|---|---|---|---|
| Psalms | 45 (Greek numbering) | all 13 | the one psalm every column covers, the Secunda included; title = verse 0 |
| 2 Samuel | 0 (inscriptio) + 9 | LXX, MT, Aquila, Symmachus, Origen, Others, Notes | chapter 0 verse 0 = the book's inscriptio |
