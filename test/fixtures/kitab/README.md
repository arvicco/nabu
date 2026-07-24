# kitab fixtures — KITAB Text Reuse Data (passim alignments over OpenITI)

Two REAL pairwise-alignment TSV files, retrieved **2026-07-24** from the
GitHub mirror

    https://github.com/kitab-project-org/pairwise-light
    (raw path: data/<book1-version-id>/<book1-vid>_<book2-vid>.csv)

laid out under `pairwise/<folder>/` exactly as the canonical tree stores
them (`canonical/kitab/pairwise/<folder>/…`). The folder name is one held
book's version id (`ALCorpus00001-ara2`); every file in it is one leaf of
that book's complete pairwise fan.

Both are the FULL upstream files, byte-for-byte (whole: true):

- `pairwise/ALCorpus00001-ara2/ALCorpus00001-ara2_Shia004016-ara1.csv` —
  a single alignment row. Header + one row. Exercises the fully-resolved
  passage-grain edge (both milestones present in the seeded catalog).
- `pairwise/ALCorpus00001-ara2/ALCorpus00001-ara2_PV20230224-ara1.completed.csv` —
  83 alignment rows, an adjacent-milestone run (`seq1` = 1,1,2,2,… ; `seq2`
  = 449,450,450,451,…). Exercises the passage-grain edge AND the
  document-grain downgrade (milestones outside the seeded parse fall back to
  the book's document urn). The `.completed` suffix is cosmetic — the bytes
  are a plain TSV.

Each file is TAB-separated (`.csv` extension notwithstanding). Header
(verified upstream): `b1 b2 bw1 bw2 e1 e2 ew1 ew2 seq1 seq2` — character
offsets (b/e), Arabic-word-token offsets (bw/ew), and `seq` = the mARkdown
MILESTONE number in each book. Trimmed: none (verbatim upstream files).

The three version ids named here — `ALCorpus00001`, `Shia004016`,
`PV20230224` — all resolve to held OpenITI documents in the live catalog
(`urn:nabu:openiti:<author>.<book>.<version-id>`; the KITAB vid is the
version_uri's last dotted segment).

## License

AUTHORITATIVE: the Zenodo record **"KITAB Text Reuse Data"**, DOI
`10.5281/zenodo.11501559`, **CC BY-NC-SA 4.0**, versioned per OpenITI corpus
release (the current version matches our held OpenITI 2025.1.9) → class
`nc`. The GitHub mirror (`kitab-project-org/pairwise-light`) carries NO
in-repo license file; it is the same dataset's per-file access path. Both
facts are recorded verbatim in `config/sources.yml` and the adapter.
