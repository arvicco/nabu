# BHSA fixture — ETCBC Biblia Hebraica Stuttgartensia Amstelodamensis (P30-4)

Byte-verbatim trimmed slices of the frozen `tf/2021` Text-Fabric dataset of
[github.com/ETCBC/bhsa](https://github.com/ETCBC/bhsa).

- **Retrieved:** 2026-07-18, from commit
  `4db00e2157915495e1a4d3d57e41223df24775da` (master), via raw GETs of
  `https://raw.githubusercontent.com/ETCBC/bhsa/master/tf/2021/<name>.tf`.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches
  (`tf/2021/*.tf`); the upstream repo-root `README.md` (the license grant)
  is quoted below rather than checked in — the adapter never parses it.

## Upstream census (at the pinned commit, from otype.tf — checked in WHOLE)

`tf/2021` = 118 files, 172,779,115 bytes (≈ 173 MB of the 1.6 GB repo).
otype.tf declares: **426,590 words / 39 books / 929 chapters / 23,213
verses / 88,131 clauses / 253,203 phrases / 9,230 lexemes** (also 90,704
clause_atoms, 267,532 phrase_atoms, 63,717 sentences, 64,514
sentence_atoms, 45,179 half_verses, 113,850 subphrases — not ingested; NB
the P30-4 brief's "64,514 sentences" is the sentence_ATOM count).
Corpus-wide facts the fixture books were chosen to attest: 1,892
ketiv/qere words (qere_utf8), 6,488 EMPTY g_word_utf8 values (elided
articles), 2,454 discontinuous clauses / 672 discontinuous phrases (comma
slot specs in oslots.tf), 50 clauses / 15 phrases crossing verse
boundaries. Zero backslash escapes in any fetched value (the family's
\t/\n/\\ unescaping follows the TF spec, exercised inline in tests).

## License (README.md verbatim, retrieved 2026-07-18)

> This work is licensed under a
> [Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/).

> give proper attribution to the data when you use it in new applications,
> by citing this persistent identifier:
> [10.17026/dans-z6y-skyh](http://dx.doi.org/10.17026%2Fdans-z6y-skyh).

> do not use the data for commercial applications without consent;
> for any commercial use, please contact the
> [German Bible Society](zentrale@dbg.de).

The repository's GitHub MIT badge covers the CODE only; the data grant is
the README's CC BY-NC 4.0 → source class `nc`.

## The four slices

| slice | slots | verse nodes | why |
|---|---|---|---|
| Jona (whole book, 48 verses) | 298558–299542 | 1428925–1428972 | small whole book; elided-article empty forms; discontinuous clause 487432 |
| Haggai 2:4–5 | 304536–304583 | 1429252–1429253 | the smallest cross-verse clause (488879, also discontinuous) — the partial-span witness |
| Ruth (whole book, 85 verses) | 355796–357597 | 1434050–1434134 | 18 ketiv/qere incl. Ruth 1:8 יעשׂה/יַ֣עַשׂ — the SAME K/Q instance the oshb fixture pins, so the two witnesses' qere shapes are provably in agreement; upstream ships the qere with the FB2B presentation-form śin, byte-verbatim here |
| Daniel 2:4–7 | 370602–370673 | 1434819–1434822 | the Aramaic lane: language.tf flips Hebrew→Aramaic mid-verse at 2:4 (8 H / 11 A tokens); Aramaic qere at 370616–17 |

Book nodes kept in book.tf: 426609 Jona, 426614 Haggai, 426620 Ruth,
426625 Daniel.

## Trim recipe (scripted; re-run per this table after any refresh)

Every data line kept is byte-verbatim upstream; the ONLY synthesized bytes
are explicit `<node><TAB>` anchors prefixed to the first line after each
trim gap (anchors are core .tf format — upstream itself anchors wherever
nodes are skipped, e.g. qere_utf8). Per file:

| file | upstream B → fixture B | trim |
|---|---|---|
| `otype.tf`, `otext.tf` | 667 / 958 → same | WHOLE, byte-identical (otype is the census-of-record; otext documents the text formats, incl. `text-orig-full-ketiv` = the stored rendering) |
| `g_word_utf8.tf`, `trailer_utf8.tf`, `vs/vt/gn/nu/ps.tf`, `kq_hybrid.tf`, `kq_hybrid_utf8.tf` | 0.4–5.4 MB → 3.5–37 KB | word-grain: the slice slots only |
| `gloss.tf`, `language.tf`, `lex.tf`, `freq_lex.tf`, `sp.tf` | 1.8–3.1 MB → 12–21 KB | dual-grain upstream (words 1–426590 + lex nodes 1437602–1446831): the word-grain slice slots only; the lex-node block is dropped (the adapter reads these word-grain, as upstream duplicates them) |
| `qere_utf8.tf`, `qere_trailer_utf8.tf` | 36,561 / 12,739 → 914 / 661 | the 22 in-slice K/Q entries (Ruth 18, Daniel 4) |
| `book.tf` | 199,917 → 1,227 | the 4 book-node entries + the verse-grain entries for slice verses (chapter-grain entries dropped — unread) |
| `chapter.tf`, `verse.tf` | 66,379 / 61,897 → 726 / 770 | verse-grain entries for slice verses (chapter-node entries dropped — unread) |
| `oslots.tf` | 13,526,306 → 30,431 | slice verse nodes + every clause (732) and phrase (2,046) node whose slots intersect the slices; all other node types dropped — unread |
| `kind.tf` (clauses), `function.tf` (phrases) | 264,852 / 1,266,461 → 2,676 / 10,697 | the same clause/phrase node sets as oslots |

kq_hybrid(.utf8) pins the empty-line quirk: word-grain files where most
slots carry EMPTY values (empty data lines that advance the node cursor).

Features deliberately NOT fixtured (and not read by the adapter): the
transliteration lanes (g_word, g_cons, lex0, voc_lex, …), the *_atom /
subphrase / sentence / half_verse structure, the omap@* version-map edges
(@edgeValues — refused by the family), rank/dist statistics, and the
book@<lang> translations.
