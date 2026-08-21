# Corpus Córporum fixtures — mlat.uzh.ch (Patrologia Latina)

Real upstream responses snapshotted **2026-08-19** from the de-facto XML API
of Corpus Córporum (Univ. of Zurich, dir. Philipp Roelli) — both endpoints
re-verified live that day (robots.txt: `Allow: /`).

## texts/ — three whole PL documents (`download.php?idno=<i>&type=file-xml`)

Small opuscula chosen via the catalog's per-author word counts, each the
upstream response byte-for-byte:

- `texts/10454.xml` — Petrus Bibliothecarius, *Abbrevatia historia
  Francorum* (PL vol. 151, Migne 1853; ~15 KB). The prose-block bulk shape:
  one `div1`, 71 `<p>`.
- `texts/10468.xml` — Wido monachus, *Epistola ad Heribertum* (PL vol. 151;
  ~8 KB). The two load-bearing quirks in one file: the ENTIRE reading text —
  Migne's "NOTA." preface AND the letter — wrapped in `<body><note><div1>`
  (a blanket drop-`<note>` rule parses the document to ZERO passages), plus
  seven INLINE `<note>` source citations inside the letter's `<p>` (real
  apparatus — dropped). Migne column milestones `<pb n="0637A"/>`.
- `texts/10821.xml` — Abbaudus abbas, *De fractione corporis Christi* (PL
  vol. 166, Migne 1854; ~20 KB). The same `body > note > div1` wrapper,
  `<head>MONITUM.</head>` apparatus, 12 `<p>`.

All three teiHeaders are **license-silent** (no `availability`/`licence`
element — the censused PL norm; the source-level nc class governs) and carry
the provenance the 80-1 gate captures: titleStmt author (+ floruit `<date>`,
`@ref` VIAF), editionStmt editor (Migne), publicationStmt (J. P. Migne,
Parisiis, year), seriesStmt (PL volume + the corpus's own work id).

## catalog/ — the navigate.php walk (`navigate.php?path=<p>`)

- `catalog/root.xml` — `path=/`, WHOLE: all 30 corpora with idno/name/
  texts_count/words_count (PL = idno 38, NOT its display nr 2: 5,277 texts /
  85,539,587 words).
- `catalog/corpus-38.xml` — `path=/38`, **documented trim**: the navigation
  head, path_steps and the corpus `<item>` block are byte-intact; the 1,528
  `<author>` entries in `<contents>` are trimmed to the three fixture
  authors (2028 Petrus Bibliothecarius, 2034 Wido monachus, 2173 Abbaudus
  abbas), each entry byte-intact.
- `catalog/author-{2028,2034,2173}.xml` — `path=/38/<author>`, WHOLE: the
  author item (VIAF/DNB externals, time_data) + `<work>` contents.
- `catalog/work-{5420,5434,5783}.xml` — `path=/38/<author>/<work>`, WHOLE:
  the work item + `<text>` contents carrying the text idno and the
  `<accessible>` flag. (work-5783 also documents the upstream quirk of a
  leaked XQuery fragment in `<extra_informations>` — real bytes.)

## refusal.txt — the download refusal body

`download.php?idno=999999999&type=file-xml`, WHOLE (65 bytes): the polite
plain-text refusal ("We are sorry, this XML file doesn't exist or can't be
downloaded.") served with HTTP 200 for restricted/missing texts — the
machine-detectable recorded-skip signal the fetch tests pin.

## License

Homepage License section (mlat.uzh.ch/home, read live 2026-08-19): own
transcriptions "published under Creative Commons Share-Alike and may thus be
reused freely (but non-commercially) as long as the source is indicated";
most texts "either in the public domain or their use was granted us by their
owners"; project goal: "Texts may be downloaded as TEI xml for non-commercial
use" → source class `nc`.
