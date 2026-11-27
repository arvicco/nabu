# lane-lexicon fixtures — Lane's Arabic-English Lexicon (alpheios-project/lan)

Real upstream samples (CLAUDE.md fixture rules): every kept line is a
verbatim line of the upstream file, cut by line ranges; nothing is
hand-written.

- **Retrieved:** 2026-11-26 from github.com/alpheios-project/lan, a full
  clone **pinned at commit `7dd04e1182c13a4b0883978867d2a3b04616542a`**
  (master HEAD, "Update README.md", 2026-04-19; the data files last changed
  2019-04-22). Upstream paths are mirrored exactly (`db/lexica/ara/lan/…`,
  `db/indexes/…`, `dat/…`).
- **License:** README verbatim: "This work is licensed under a Creative
  Commons Attribution-ShareAlike 3.0 United States License.
  http://creativecommons.org/licenses/by-sa/3.0/us/" — "Original
  Digitization provided by the Perseus Digital Library at Tufts University,
  under the support of the U.S. Department of Education and the Max Planck
  Society. Corrections to digitization added by the Alpheios Project, Ltd."
  No LICENSE file; GitHub reports no license (README-only grant).

## Delivery grains upstream serves (whole-repo census at the pin)

| Grain | Upstream | Taken? |
|---|---|---|
| letter-bucket file `db/lexica/ara/lan/u*.xml` | 38 files, 49,473 `entryFree` | **ACCEPTED** — one document per file; the entry is the `entryFree` |
| `entryFree` with `@id`/`@key` | 46,146 (44,829 distinct ids) | entry, id = `@id` |
| `entryFree` without `@id`/`@key` | 3,327 (3,056 numbered derived-form paragraphs, 59 quadriliteral, 199 "See Supplement" stubs, 13 others) | entry, id = preceding id + ordinal |
| `ua0.xml` | whole-file copy of `u_0.xml` (678 entries; 639 byte-identical, n14061 differs by one trailing space) | REJECTED by rule while whitespace-equivalent (collapsed) |
| `uq2.xml` | an earlier copy of the ق–ك Supplement pages, re-using ids n42477–n43153 of uq1 (436) / uk1 (213) / u_Y0 (28) for other words | accepted, ids stem-prefixed (`uq2.n…`) |
| `db/indexes/ara-lan-index.xml` | Alpheios lemma → id index, 61,899 lemmas | REJECTED (derived lookup aid) |
| `dat/ara-lan-ids.dat` | the same index as `form|id` lines, 218,721 | REJECTED |
| `__contents__.xml` | 5 eXist-db collection descriptors | REJECTED (packaging) |
| `README.md` | the licence statement | documentation, not censused |

All 28 letters are present (u_Y0.xml is ي, filed under div1 n="Y" with an
alif-maqsura head); the eight `…1.xml` files are the Supplement (pp.
2984–3064). Reconciliation: 49,473 − 678 (ua0) = **48,795 entries**
loaded; 8 files skipped by rule; nothing unrecognized.

## Files (8)

| File | Cut (upstream line ranges) | Why |
|---|---|---|
| `db/lexica/ara/lan/u_0.xml` (ذ, 11,641 lines) | 1–25 (letter article n13600), 8031–8426 (roots ذمر, ذمل, ذمى), last line | a normal entry, a bare derived-form pointer paragraph ("2 ذَمَّرَ see 1, in three places"), `<pb n="978">`/`<pb n="979">` inside entries, entries before the file's first kept `<pb>`, "see ‹Arabic›" pointers, and n14061 — the one whitespace-differing duplicate |
| `db/lexica/ara/lan/ua0.xml` | the same ranges | the duplicated id pair (collapses only while whitespace-equivalent) |
| `db/lexica/ara/lan/u_Y0.xml` (ي) | 1–42 (letter article n42419), 601–606 (root يتم "See Supplement" stub), last line | an id-less, orth-less stub |
| `db/lexica/ara/lan/uq1.xml` (Supplement ق, pretty-printed) | 1–46 (letter n42505, roots قبس, قبع), last 4 lines | owner of the bare ids n42506–n42508 |
| `db/lexica/ara/lan/uq2.xml` | 1–34 (id-less ق, قبس, قبع), 661–680 (roots قبن n42507, قبو n42508), 5007–5012 (root قو: the one text-less `entryFree`, its heading "قو: see قوى" the whole article), last line | the colliding id pair: n42507/n42508 are قَبَعَ السِّقَاءَ / قَبِيعَةٌ in uq1 but قَبَّانٌ / قَبَآءٌ here |
| `db/indexes/ara-lan-index.xml` | 1–9 + the closing `</entrylist>` | rejected-grain specimen |
| `dat/ara-lan-ids.dat` | 1–10 | rejected-grain specimen |
| `db/lexica/ara/lan/__contents__.xml` | 1–5 + last line | rejected-grain specimen |
