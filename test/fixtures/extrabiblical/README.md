# ETCBC extrabiblical fixture — Non-Masoretic texts related to the Hebrew Bible

Byte-verbatim trimmed slices of the frozen `tf/0.2` Text-Fabric dataset of
[github.com/ETCBC/extrabiblical](https://github.com/ETCBC/extrabiblical),
plus the superseded `tf/0.1` dataset's `otype.tf` and book-node block as
the rejected-grain specimen.

- **Retrieved:** 2026-10-22, from commit
  `9a56288e6777bad6328856acf055c780e65dd5d9` (master, committed
  2026-08-10), via the codeload tarball of `master`.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches
  (`tf/<version>/*.tf`); the upstream `README.md` (the license grant) is
  quoted below rather than checked in — the adapter never parses it.

## Upstream's delivery grains (all of them, at the pinned commit)

| grain | what it is | verdict |
|---|---|---|
| `tf/0.2/*.tf` (80 files, 9.1 MB) | the current Text-Fabric dataset (written 2019-01-24 from MQL source v0.2) | **ACCEPTED** — document = book node (13) |
| `tf/0.1/*.tf` (80 files, 3.1 MB) | the superseded 2017 dataset (MQL v0.1; 10 books — no 1QHa, Pirqe, Shirata) | fetched, **skipped by rule** per book node (specimen: `tf/0.1/otype.tf` whole + `tf/0.1/book.tf` book-node block) |
| `source/0.1`, `source/0.2` `extraBiblical.mql.bz2` (609 KB, 1.9 MB) | the ETCBC MQL exports the TF data was converted from — the same corpus in its pre-conversion form | refused at fetch (outside the sparse cone) |
| `programs/` | the conversion notebook (`tfFromMql.ipynb`), `utils.py`, images, a stray `__pycache__` and notebook checkpoint | code — refused at fetch |
| `README.md`, `LICENSE`, dotfiles | the data grant (README) and the code license (MIT) | README in the cone; nothing parsed |

Within the accepted dataset the section grains are book (13) → chapter
(79: the inscription, column or chapter number) → verse (1,800: the
line; most ostraca are ONE undivided verse). The linguistic grains
(clause 8,908, phrase 22,770) ride as passage spans; clause_atom,
phrase_atom, sentence(_atom), subphrase and half_verse are not
ingested. **Reconciliation:** tf/0.2's otype.tf declares 13 book nodes
= 13 documents; tf/0.1's 10 book nodes are skipped by rule; residue 0.

## Upstream census (tf/0.2 otype.tf — checked in WHOLE)

39,862 words / 13 books / 79 chapters / 1,800 verses / 8,908 clauses /
22,770 phrases (also 9,160 clause_atoms, 23,370 phrase_atoms, 6,429
sentences, 6,665 sentence_atoms, 15,351 subphrases, 1,800 half_verses).
Per book (words): 1QHa 10,999 · 1QM 5,964 · 1QS 6,107 · Ajrud 76 ·
Arad 172 · Balaam 372 · Ketef Hinnom 89 · Lachish 391 · Mesa 492 ·
Mesad Hashavyahu 123 · Pirqe 6,201 · Shirata 8,788 · Siloam 88.
`language.tf` says `Hebrew` on all 39,862 words. All 39,416 non-empty
`g_word_utf8` forms are NFC-stable (Hebrew letters + U+05C1/U+05C2 only).
`qere.tf`/`qere_utf8.tf` are header-only; `g_prs.tf`/`g_prs_utf8.tf`
ship as empty `@config` files; `lexeme_count.tf` is `0` on every word.

## License (README.md verbatim, retrieved 2026-10-22)

> This dataset is licensed under a [Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)](https://creativecommons.org/licenses/by-nc/4.0/).

The repository's `LICENSE` file (MIT, "Copyright (c) 2019 Dirk Roorda")
covers the conversion code. Confirmed by the ETCBC directorate (W. van
Peursen), by email, 2026-10-15: all ETCBC-created data — the BHSA and
the extrabiblical corpora — are CC BY-NC 4.0, software MIT → class `nc`.

## The slice

| book | book node | verse nodes | slots | why |
|---|---|---|---|---|
| Lachish (letters 3–6, whole) | 39870 | 4 | 23780–24170 | multi-chapter book, one verse per ostracon; elided-article empty forms (slot 23809) |
| Mesa (the Mesha Stele, whole) | 39871 | 39 | 24171–24662 | the Moabite language lane; line-grain verses |
| Siloam (whole) | 39875 | 1 | 39775–39862 | the smallest book; the known opening "דבר הנקבה" |

173 clauses and 560 phrases intersect the slice, none straddling it.

## Trim recipe (scripted; re-run per this table after any refresh)

Every data line kept is byte-verbatim upstream; the ONLY synthesized
bytes are explicit `<node><TAB>` anchors prefixed to the first line after
each trim gap (core .tf format). No range line was partially covered.

| file | trim |
|---|---|
| `otype.tf`, `otext.tf` | WHOLE, byte-identical |
| `book.tf` | the 3 book-node entries + the slice's 44 verse-grain entries (chapter-grain dropped — unread) |
| `book@en.tf` | the 3 book-node entries |
| `chapter.tf`, `verse.tf` | the slice's verse-grain entries |
| `oslots.tf` | the slice verse nodes + the 173 clause / 560 phrase nodes (all other node types dropped — unread) |
| word-grain (42 files): `g_word_utf8`, `g_suffix_utf8`, `language`, `lex`, `lex_utf8`, `sp`, `pdp`, `vs`, `vt`, `gn`, `nu`, `ps`, `st`, `ls`, `number`, `g_word`, `g_cons(_utf8)`, `g_lex(_utf8)`, `g_nme(_utf8)`, `g_pfm(_utf8)`, `g_uvf(_utf8)`, `g_vbe(_utf8)`, `g_vbs(_utf8)`, `nme`, `pfm`, `prs`, `prs_gn/nu/ps`, `uvf`, `vbe`, `vbs`, `suffix_gender/number/person` | the slice slots only (`number`'s clause/phrase/atom/sentence blocks dropped) |
| span lane (11 files): `kind`, `function`, `typ`, `txt`, `domain`, `rela`, `det`, `dist`, `dist_unit`, `mother_object_type`, and the `mother` EDGE | the 733 slice clause/phrase nodes (atom/subphrase entries dropped — unread) |
| `tf/0.1/otype.tf` | WHOLE (the rejected grain's census) |
| `tf/0.1/book.tf` | header + the 10 book-node entries |

Not fixtured (and not read by the adapter — each named with its reason
in `Extrabiblical::DECLINED_TOKEN_FEATURES`): `g_suffix`, `qere`,
`qere_utf8`, `g_prs`, `g_prs_utf8`, `lexeme_count`, `label`, `code`,
`is_root`, `tab`, `functional_parent`, `distributional_parent`.
