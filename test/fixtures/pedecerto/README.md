# pedecerto fixtures — Latin metrical scansions (P44-7)

Two files trimmed from the pedecerto bulk artifact
`https://www.pedecerto.eu/allpedecertoscans.zip` (12 MB, 469 XML files, one
per author-work), downloaded and unpacked **2026-07-24**. The zip's single
top directory is `allpedecertoscans/`; each file is `<AUTHOR>-<work>.xml`.

Both files are **trimmed** (head kept verbatim, only the first few lines of
each division retained) — they are NOT independently refetchable (there is no
per-file URL; re-acquiring means downloading the whole zip and re-trimming),
so the manifest records them `refetchable: false` with the zip as `upstream`.

## Shape (what the parser reads)

```
<document>
  <head><author>…</author><title>…</title>
        <rights><licence>…by-nc-nd/4.0…</licence></rights></head>
  <body>
    <division title="1">                          # book number (absent in single-book works)
      <line name="1" meter="H" pattern="DSDS">    # line number · meter code · foot pattern
        <word sy="1A" wb="CM">Quid</word>         # per-word syllable positions + word-boundary type
        …
```

- `division/@title` is the book number (a clean integer for the held classical
  works); `line/@name` is the line number within it. The pedecerto citation is
  therefore `book.line` (`1.1`) when a division wraps the line, or bare `line`
  (`1`) for single-book works. This maps directly onto Perseus's CTS
  `book.line` passage citation.
- `line/@meter`: `H` hexameter (dominant: 227,791 of ~300k lines), `P`
  pentameter (elegiac couplet second verse), plus ~20 other verse codes.
- `line/@pattern`: the dactyl/spondee pattern of the line's resolvable feet
  (`D`/`S`), empty on some non-hexameter lines.

## The two fixtures

- `allpedecertoscans/VERG-geor.xml` — Vergil, *Georgica* (`VERG-geor`),
  hexameter, trimmed to book 1 lines 1–3 + book 2 lines 1–2. Exercises the
  `book.line` citation path and multi-division resolution. Crosswalks to the
  held Perseus work `phi0690.phi002` (Vergil textgroup, Georgics).
- `allpedecertoscans/OV-ibis.xml` — Ovid, *Ibis* (`OV-ibis`), an **elegiac**
  poem with NO `<division>`, trimmed to lines 1–3. Exercises the bare-`line`
  citation path and a mixed `H`/`P` meter run. Crosswalks to `phi0959.phi010`.

License (per-file, verbatim in each `<rights>`): CC BY-NC-ND 4.0 — matches the
site license read for the packet → class `nc`, attribution + no-substantial-
alteration (satisfied by canonical-means-canonical).
