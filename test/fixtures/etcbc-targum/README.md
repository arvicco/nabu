# etcbc-targum fixture — the ETCBC Targum Corpus (Text-Fabric tf/0.1)

Gap-anchored trimmed slices of the pinned `tf/0.1` Text-Fabric dataset of
[github.com/ETCBC/targum](https://github.com/ETCBC/targum) ("Graph Datasets
of the Jewish Aramaic Pentateuch", S. P. Swire; Zenodo
10.5281/zenodo.23785216, v1.0.0, 2026-10-29).

- **Retrieved:** 2026-11-02, from commit
  `15f97ab469feeae12ccbd5b02acbb02d9ba37126` (main; `tf/0.1` is
  byte-identical at tag `v1.0.0`, `f4efa2e7`), via raw GETs of
  `https://raw.githubusercontent.com/ETCBC/targum/main/tf/0.1/<name>.tf`.
- **Layout:** mirrors the sparse workdir the adapter fetches (`tf/0.1/*.tf`);
  README.md and LICENSE.md (also in the cone) are quoted below, not checked in.
- **Trim recipe:** headers byte-verbatim; data lines byte-verbatim for every
  node whose slots lie inside the kept slot ranges below, written
  gap-anchored (an explicit `node<TAB>` anchor after every gap); empty values
  drop. Text, book and chapter nodes that extend past a kept range keep their
  `oslots` line CLIPPED to the kept slots (the Neofiti and Pseudo-Jonathan
  slices) — the one non-verbatim edit, so a slice reads as a whole text.
  Lexeme nodes are not kept. `otype.tf` and `otext.tf` ride WHOLE — the
  census of record. Only the features the adapter reads are included.

## Upstream delivery grains

Upstream serves the corpus three ways: Text-Fabric (`tf/0.1`, taken), a
PostgreSQL dump (`sql/*.zip`, `*.gz`) and XML (`xml/`) — the same dataset
in other serializations, outside the sparse cone and never fetched. Inside
Text-Fabric the node types are word (slot), word_group, segment, verse,
chapter, book, text, lexeme. The adapter takes **text** as the document
(one manuscript witness under one editorial view) and **verse** as the
passage; words ride as tokens with their segment type and word-group
reading rank; lexeme nodes (7,023 — lexical statistics) are not a text
grain. One verse-record shape is **skipped by rule**: a record holding only
the edition's omission dots (line `...`, rendered in `line_utf8` as bare
U+05BC). Its specimen is pinned here (Pseudo-Jonathan Gen 1:22, slot 532)
and the adapter test asserts it is skipped and named in `omitted_verses`.

## Upstream census (at the pin, from otype.tf — checked in WHOLE)

624,612 words / 47 texts / 91 books / 1,225 chapters / 25,447 verses /
70,389 segments / 461,201 word groups / 7,023 lexemes. Full-data parse
(2026-11-02): 47 documents / 25,430 passages / 624,595 tokens — the 17
omission records (PJ 8, Neofiti full 9) account for the difference.
Reconciled against the README's text list: Pseudo-Jonathan, Fragment
Targums P/V/N (+ a PA text the README does not name), the 38 Genizah
sigla (+ a second AA text `aa(2)`), Neofiti 1 under two views, Onqelos.

Corpus-wide facts:

- Three addresses carry repeat verse records within one text (crossref
  `same_witness`): Genizah DD Deut 24:6 ×2 (in this fixture), FF Exod
  15:12 ×4, FF Exod 17:12 ×3 → the `:b2`/`:b3` collision suffix.
- Genizah X, Y and FF alternate book nodes (Exodus, Genesis, Exodus …) —
  festival compilations; X rides this fixture whole.
- `line_utf8` ≠ the `{voc_utf8}{trailer}` slot render on ~740 verses:
  `line_utf8` excludes readings transcribed on a line of their own
  (marginalia), while short interlinear variants run inline without a space
  (Neofiti full Gen 2:1 `בריתחילוות`). The adapter takes `line_utf8`.
- Upstream defects kept verbatim: both Deut 24:6 records of Genizah DD carry
  the SAME `line_utf8` (the whole verse, both records' words), and DD's Deut
  33:6 record carries that line too (its own slots hold only `ולא`). The
  tokens show each record's own words.
- `vt`, `ps` and `vo` are listed in the README but ship no `.tf` file.
- `trailer.tf` has 3 values: space, two spaces, and absent.

## License (verbatim, retrieved 2026-11-02)

README badge: "License: CC BY-NC 4.0"; LICENSE.md: "Attribution-NonCommercial
4.0 International" (the CC legal code); every feature header:
`@license=Attribution-NonCommercial 4.0 International` /
`@licenseUrl=https://creativecommons.org/licenses/by-nc/4.0/deed.en`; Zenodo
record license `cc-by-nc-4.0` → source class `nc`.

## The slices (2,653 words / 94 verse records)

| text | node | kept | verses | why |
|---|---|---|---|---|
| pseudo_jonathan | 703341 | Gen 1:21–23 (slots 473–540), clipped | 3 (1 omission) | the omission-record specimen (1:22) |
| fragment_targum_n | 703345 | whole (175 words) | 7 | three books in one fragment |
| cairo_genizah_targum_fragment_dd | 703364 | whole (381 words) | 28 | the repeated address Deut 24:6 + the 33:6 line defect |
| cairo_genizah_targum_fragment_x | 703377 | whole (770 words) | 6 | alternating Exodus/Genesis book nodes |
| neofiti_base | 703385 | Gen 2 (slots 204987–205570), clipped | 25 | the base_raw view |
| neofiti_full | 703386 | Gen 2 (slots 339248–339922), clipped | 25 | the full_text view: inline variants, segment types, readings |
