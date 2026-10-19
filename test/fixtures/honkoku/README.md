# honkoku fixtures

Retrieved 2026-09-29 from github.com/yuta1984/honkoku-data (README
license CC BY-SA 4.0 verbatim) — real files, uncut:

- `v3/21dzk/info.tsv` — the project index's first 3 material rows
  (head -4 with header): 006BC…/052D… have NO transcription dir in
  the fixture (the skip-counted case); 0A67… does.
- `v3/21dzk/0A678AA21E602F6A3FFF3329B090920C/` — the 目次 material
  whole: 001.txt + 002.txt (NDL 大蔵経 volume front matter) + its
  own info.tsv (filename → status + IIIF image URL).

Layout truth pinned: page texts carry full-width layout whitespace
served verbatim; attribution rides the project index per material.

- `v3/zukan/info.tsv` (head -3 + the EBA1C… row) and
  `v3/zukan/EBA1C…/` — a REAL untranscribed material: empty
  placeholder page files (trimmed to 2 of its 57), cut 2026-09-29
  from the box's canonical clone. The all-pages-empty skip case.
- The 21dzk index additionally carries the REAL ainu-project row
  whose attribution cell is raw HTML with bare quotes — the
  TSV-is-not-quoted-CSV poison, verbatim.
- `v3/21dzk/0A678AA21E602F6A3FFF3329B090920C/translations/` (added
  2026-10-19, copied whole from the box's canonical clone) — the
  material's real `001_en/001_ja/002_en/002_ja.txt`: the platform's
  machine-generated modern-Japanese and English renderings. Pins the
  DECLINE: the adapter must never read this layer (the adapter header
  carries the provenance evidence).
