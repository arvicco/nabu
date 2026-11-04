# GregoBase fixtures — trimmed `gregobase_online.sql`

A real, structurally intact trim of GregoBase's canonical bulk artifact:
the phpMyAdmin dump `gregobase_online.sql` (17,173,291 bytes, sha256
`3759c60b529b57fa13f696bfacf748d40a285a847d859276667749caa76de080`) that
the site's maintainer commits to the site's code repository. Retrieved
**2026-11-04** from

- repo: `https://github.com/gregorio-project/GregoBase` (branch `master`,
  HEAD `8851677efaccf0dccd4eb05ebff28d6f4018584c`, 2026-10-24, "PHP 8.3
  compatibility" — code only)
- the dump's last commit: `2ebcda3f523f9b19933d59fa32bb4215cd8e7675`
  (2024-01-05, "Update DB"; the dump header reads "Généré le : ven. 05 jan.
  2024"). The dump has 17 commits, 2016-01-13 → 2024-01-05: an irregular,
  maintainer-driven cadence.
- raw URL: `https://raw.githubusercontent.com/gregorio-project/GregoBase/2ebcda3f523f9b19933d59fa32bb4215cd8e7675/gregobase_online.sql`

## License (recorded verbatim)

The site's About page, `https://gregobase.selapa.net/?page_id=2`
(read 2026-11-04):

> All chant transcriptions are released under CC0 (a.k.a. Public Domain)
> license.

with "CC0" linking `http://creativecommons.org/publicdomain/zero/1.0/` →
`license_class: open`. The repo itself carries no LICENSE file (its PHP
code is not ingested). The rows upstream flags `copyrighted = 1` are the
exception the site itself makes: `chant.php` prints "This tune is still
under copyright." and offers no download for them — the adapter skips
them by that flag.

## Upstream's delivery grains

The dump carries data for five tables (`gregobase_chants`,
`gregobase_chant_sources`, `gregobase_sources`, `gregobase_chant_tags`,
`gregobase_tags`) and only the STRUCTURE of the editorial tables
(`gregobase_changes`, `gregobase_changesets`, `gregobase_pleasefix`,
`gregobase_proofreading` — no rows: user data is not exported).

| Grain | Taken as | In the fixture |
|---|---|---|
| a `gregobase_chants` row | **the document** (one chant) | 507, 8761, 13466, 14738, 17418, 18115 |
| a row with `copyrighted = 1` (33 in the dump) | skipped by rule | 8093 (melody redacted, below) |
| a row with `duplicateof > 0` (276) — a retired duplicate; `chant.php` 301-redirects to the kept chant | skipped by rule | 7774 (→ 7782) |
| a row with `duplicateof = -1` (19) — withdrawn; `chant.php` redirects to the score list | skipped by rule | 16117 |
| a row with an empty `gabc` column (17; 13 are also duplicates) | skipped by rule | 18651 |
| a chant whose scores carry no syllable text (8) | skipped by rule at parse (DocumentSkipped) | doctored in the test from 14738 |
| `gregobase_sources` (68 books) + `gregobase_chant_sources` | metadata of the chant (title, editor, year, period, page) | the 7 books the kept chants cite |
| `gregobase_tags` (386) + `gregobase_chant_tags` | metadata of the chant | tag 457 |
| the editorial tables | not data (structure only) | structure kept |
| the site's per-chant downloads (`download.php` gabc / pdf / svg / eps / png) | never fetched — renderings of the same rows | — |
| `gregobase_structure.sql`, the PHP site code | never ingested | — |

Inside a chant row, the `gabc` column is JSON: a string (one score) or an
array of `[layer, content, {}]` elements interleaving `"gabc"` scores with
`"tex"` blocks (mostly layout commands). Of the accepted rows 1,668 are
arrays, 37 of them with more than one score. `gabc_verses` holds further
stanzas in GABC, `tex_verses` verses typeset in TeX; the `headers` column
is NULL on every row.

**Reconciliation (full dump at 2ebcda3, through the adapter, 2026-11-04):**
18,762 chant rows (upstream's AUTO_INCREMENT = 18,931; ids 1–18,930 with
gaps) − 332 skipped by rule (33 copyrighted + 276 duplicates + 19
withdrawn + 4 further empty-GABC rows) = 18,430 refs discovered → 18,422
documents / 20,810 passages + 8 notation-only skips, 0 errors. The live
site has grown past the dump (a third-party scrape,
github.com/bbloomf/gregobase-backup, lists 20,805 chant ids at
2026-10-28); the dump is the export upstream itself publishes and the only
bulk route carrying the `copyrighted` flag.

## The kept chants (each one shape)

- **507** "Confitemini... quoniam" (Alleluia) — the element-array form:
  layout TeX, two scores (upstream's Element 1/2), a `\greannotation`
  TeX element; `{ia}` centering braces, `<clear>`.
- **8761** "Litania 06 Sancte Joannes" (Supplicatio) — `<b>`/`<i>` accent
  marks, a `tex_verses` block.
- **13466** "Vere tu es" (Palmer & Burgess) — an English chant; `<sp>V/</sp>`,
  the `ij.` repeat rubric, textless melisma groups.
- **14738** "Factus est adiutor" (Antiphona, Cantus ID 002846) — NABC
  neumes after `|`; cited in Antiphonale monasticum I (2005) and the
  Hartker antiphoner, Cod. Sang. 390 ("around 990-1000").
- **17418** "Maria castis osculis" (Hymnus, Cantus ID a01571) — a
  `gabc_verses` stanza.
- **18115** "Mirabile mysterium" (Antiphona, Cantus ID 003763) — an inline
  GABC header (`initial-style: 1;` + `%%`), a tag, the E u o u a e
  differentia.

## Trim procedure

Every line of the dump that is not a data tuple (the header comments, SET
statements, CREATE TABLE / ALTER TABLE structure, the trailing COMMIT) is
kept verbatim. Of the data, only the tuples of the ten chants above, their
`gregobase_chant_sources` / `gregobase_chant_tags` rows, the referenced
`gregobase_sources` rows (2, 3, 17, 23, 50, 53, 59) and tag 457 are kept,
each line VERBATIM, under its original `INSERT INTO … VALUES` header (a
statement with no kept row is dropped; only the `,`/`;` tuple terminators
are adjusted where a statement's last kept row changed).

**One deliberate edit:** chant 8093's `gabc` value is cut to its clef,
`'\"(c4)\"'`. Upstream flags the melody as still under copyright; it is
not ours to republish, and the skip rule reads only the flag (the test
proves it by clearing the flag on a doctored copy).

## Re-acquiring

Clone the repo (or GET the raw URL above) and re-apply this trim.
