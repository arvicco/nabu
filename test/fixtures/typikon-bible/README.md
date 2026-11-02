# typikon-bible fixture — the Bible layer of the typikon.info dump

Real lines of the "Выгрузка корпуса «Уставные чтения»" dump, version
2026-09-21 ([typikon.info/dump/2026-09-21/](https://typikon.info/dump/2026-09-21/),
Zenodo 10.5281/zenodo.22883965, DOI of the corpus 10.5281/zenodo.22883964).

- **Retrieved:** 2026-11-02, by plain GETs of
  `https://typikon.info/dump/2026-09-21/<path>` (paths in manifest.yml).
- **Layout:** mirrors the workdir the adapter fetches — each file in its own
  subdir (`manifest/manifest.json`, `bible-editions/…`, `bible-books/…`,
  `bible-verses-ro-1688/…`), the FileFetch state + attic per subdir.
- **Trim recipe:** `manifest.json` byte-verbatim WHOLE. Every `.jsonl.gz`
  keeps byte-verbatim JSON lines of the upstream file, selected by book,
  and is re-gzipped (mtime 0): `bible-editions` all 11 lines;
  `bible-books` the 4 book records the slices use; `bible-verses-ro-1688`
  Joel (73), Obadiah (21) and the Song of the Three Youths (67).

## Upstream delivery grains

manifest.json lists three layers: **corpus** (21 files — the liturgical
readings corpus: texts, books, calendar days/weeks/months, pericopes,
saints, places, accents …; CC BY 4.0), **bible** (16 files) and
**temples** (1 file, ODbL). This source reads only the bible layer:
`bible-editions` and `bible-books` (tables: edition records with their
mapping rules, book records with the canonical id), and the **verse files
of admitted editions** — one document per (edition, book), one passage
per verse record. Rejected inside the bible layer, each **skipped by rule**
when present in the workdir and pinned here as a specimen:

- a verse file of an edition outside the ruled set — `bible-verses-ro-1914`
  (Wikisource's Romanian Synodal Bible, CC BY-SA; Obadiah, 21 lines);
- the numbering concordance `bible-concordance` (an instrument: "Стих без
  текста" — edition, book, chapter, verse as printed → canonical address;
  ro-1688 Obadiah, 21 lines).

The CSV twin of the concordance, the other editions' verse files and
GPL-3.0.txt are not fetched. The corpus and temples layers are outside
this source.

## Census (dump 2026-09-21, read 2026-11-02)

- ro-1688: **36,312 verses / 79 books** (manifest `records` 36,312 — the
  reconciliation), native (chapter, verse) unique per book; 2,870 verses
  carry a canonical address different from their own; 33,484 ship
  non-NFC combining order.
- The concordance: 342,568 rows over eleven editions — ro-1914 36,341 ·
  la-vulgata 37,149 · zh-1910 7,538 · cv-ipb 36,735 · cv-ipb-cu 36,735 ·
  grc-lxx-pat 37,805 · ro-1688 36,312 · cs-eliz 36,961 · cs-old-rite 8,803 ·
  ka-mcxeta 32,425 · en-brenton-kjv 35,764. cs-eliz and ka-mcxeta rows are
  identity (cs-eliz IS the canon).

## License (verbatim, manifest.json, retrieved 2026-11-02)

Bible layer `"license": {"id": "CC-BY-4.0", …}`; rationale: "Румынскую
кириллицу 1688 и китайский Новый Завет 1910 набирали мы — они под
лицензией слоя."; the ro-1688 file note: "Оцифровка выполнена в проекте по
сканам издания." → source class `attribution`. The ro-1914 specimen is CC
BY-SA 4.0 (its own file license: "Вычитанный людьми текст Викитеки");
the concordance rides the layer's CC BY 4.0.
