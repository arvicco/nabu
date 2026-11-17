# dtucph-sp fixture — the CACCHT Samaritan Pentateuch (DT-UCPH/sp)

Byte-verbatim trimmed slices of the `tf/7.5.0` Text-Fabric dataset of
[github.com/DT-UCPH/sp](https://github.com/DT-UCPH/sp).

- **Retrieved:** 2026-11-16, at release tag **`v7.5.0`** = commit
  `e8a120f2e92b6558fd39bbe72f830ded871a0a47` (published 2026-11-13, the
  latest release on retrieval day; release note: "Variations between
  Dublin 751 and Nablus 6 were added"), via a sparse clone of
  `tf/7.5.0` at the tag. Raw URL shape:
  `https://raw.githubusercontent.com/DT-UCPH/sp/v7.5.0/tf/7.5.0/<name>.tf`.
- **Layout:** mirrors the sparse workdir the adapter fetches
  (`tf/7.5.0/*.tf`); `README.md` and `LICENSE` (also in the cone) are
  quoted below rather than checked in — the adapter never parses them.
- **All 50 feature files of `tf/7.5.0` are present** (trimmed), so the
  adapter test reconciles its routed/declined feature lists against
  upstream's own file list.

## Upstream census (at the pin, from otype.tf — checked in WHOLE)

`tf/7.5.0` = 50 files ≈ 20 MB. otype.tf declares: **399,393 signs (the
slot type) / 5 books / 187 chapters / 5,841 verses / 114,891 words /
21,736 clauses / 22,530 clause_atoms / 66,043 phrases / 69,905
phrase_atoms**. Facts censused over the whole dataset at the pin:

- `sign.tf`: 28 distinct values — the 27 Hebrew letters (finals
  distinct) + U+0020. No shin/sin dots. The `{sign}` render
  (`otext.tf` `text-orig-full`) is NFC-stable.
- Every sign lies in exactly one word; words are contiguous and never
  cross a verse; every verse render ends in a space; a word's render
  ends in a space exactly where `trailer.tf` says `" "` (82,335 words).
- A word's sign render equals its `g_cons_utf8` with the shin/sin dots
  removed; `g_cons_utf8`/`g_lex_utf8`/`lex_utf8` write the dotted shin/sin
  as presentation forms U+FB2A/U+FB2B (12,507 + 3,475 in g_cons_utf8 —
  non-NFC, kept verbatim; hbo is NFC-exempt).
- `book`/`chapter`/`verse` label only their own node grain; (book,
  chapter, verse) is unique over all 5,841 verses. Gen 30:36 holds the
  grouped additions (90 words — README: 36a–c grouped under 36).
- `language.tf`: Hebrew 114,889 / Aramaic 2 (Gen 31:47).
- `vs` (verbal stem) is annotated in Genesis only (5,098 words) —
  upstream work in progress.
- `mt_feat` ("features imposed from MT"): "True" on 105,833 words.
- Tal–Florentin layer: `var_ft_utf8`/`var_ft`/`var_ft_type`/`var_ft_span`
  on 1,074 words (types: plene_defective 647, other 170, conjunction_waw
  75, guttural_interchange 70, aleph_plus_minus 42, final_he_yod 32,
  article_he 22, word_division 12, plus_caccht 2, plus_ft 2);
  `verse_ft` on 58 verses.
- `grammar_note`: 72 words + 1 phrase. `typ`/`function`: all 66,043
  phrases.
- Constituents: 720 discontinuous clauses / 284 phrases; 29 clauses / 9
  phrases / 7 clause_atoms cross a verse boundary; none cuts a word.
- The witness is NOT marked per node: only the feature headers'
  `@manuscripts=MS Dublin Chester Beatty Library 751 (Gen 1-Deut 32:36) +
  MS Garizim 1 (Deut 32:36b-34)`.

## Delivery grains (checklist step 2)

Upstream serves: the Text-Fabric dataset in 64 version directories
`tf/<version>/` (0.x Genesis-only through 7.5.0); a `complete.zip`
release asset (the same data zipped); notebooks, an app, scripts, review
TSVs, textual-issue notes and the `ml_data_phrase_atoms_phrases` ML
training set. **Accepted:** the pinned `tf/7.5.0` directory; within it the
**book** node is the document (the bhsa precedent; 5 books), the verse the
passage. **Rejected:** every other version dir, the zip, and the
non-dataset trees — none of them is inside the sparse GitFetch cone
(`tf/7.5.0`, `README.md`, `LICENSE`), so nothing reaches discover and no
skip specimen is pinnable; the atom grains (clause_atom, phrase_atom)
carry no feature of their own and ride no span (bhsa precedent).
Expected first sync: 5 documents / 5,841 passages / 114,891 tokens /
87,819 spans (78 partial), 0 skipped — verified by a full parse of the
pinned tree on 2026-11-16 (≈ 12 s).

## License (verbatim, retrieved 2026-11-16)

README.md badge: `License: CC BY-NC 4.0` (links
creativecommons.org/licenses/by-nc/4.0/). README prose:

> You can use the dataset freely for research and education. If you do
> so, please refer to the papers. Also refer to the dataset in the
> following way:
>
> Christian Canu Højgaard, Martijn Naaijer, & Stefan Schorch. (2023).
> Text-Fabric Dataset of the Samaritan Pentateuch. Zenodo.
> https://doi.org/10.5281/zenodo.7734632

`LICENSE` is the CC BY-NC 4.0 legal code ("Attribution-NonCommercial 4.0
International"). Every `.tf` header (British spelling of the key):

> @licence=Creative Commons Attribution-NonCommercial 4.0 International License
> @licenceUrl=http://creativecommons.org/licenses/by-nc/4.0/

The Tal–Florentin readings come from M. Florentin & A. Tal, *The
Samaritan Pentateuch: An English Translation with a Parallel Annotated
Hebrew Text* (Open Book Publishers, 2024, doi 10.11647/OBP.0415), which
the README states is "licensed CC BY-NC 4.0". → class `nc`.

## The slices (verse nodes kept)

| slice | verse nodes | why |
|---|---|---|
| Gen 1:1–12 | 399586–399597 | Gen 1:1 reading; the discontinuous clause 520337 / phrase 564649 (1:7); the first T&F reading (word 405625, span 2, 1:12) |
| Gen 2:23 | 399639 | word grammar_note (406550) |
| Gen 6:19–20 | 399742–399743 | clause 520891 crossing the verse boundary; `verse_ft` "6:19, 6:20" |
| Gen 14:20 | 399942 | the one phrase grammar_note (568242) |
| Gen 26:7 | 400285 | a T&F "-" reading (418646: T&F have no words here) |
| Gen 30:36 | 400452 | the grouped 36a–c additions (90 words) |
| Gen 31:47 | 400506 | the two Aramaic words (422873–422874) |
| Deut 32:35–37 | 405370–405372 | the manuscript switch (Dublin → Garizim 1 within 32:36) |
| Deut 34:12 | 405426 | the last verse — the slot space's end (399,393) |

Book nodes kept: 399394 Genesis, 399398 Deuteronomy.

## Trim recipe (scripted; re-run after any re-pin)

1. Kept slots = the sign slots of the verse nodes above.
2. Kept nodes = those slots + those verses + every word whose slots all
   lie in the kept slots + every book/chapter/clause/phrase node whose
   slot ranges touch a kept slot. Atom nodes are dropped (unread).
3. `otype.tf` and `otext.tf` are copied WHOLE. Every other file keeps its
   header byte-verbatim and its data lines for kept nodes only, values
   byte-verbatim; a line whose node does not follow the previous kept
   node gets an explicit `node<TAB>` anchor (core .tf format); empty
   values drop (the family loads them as absent either way). `oslots.tf`
   entries keep their full slot specs (a cross-verse clause still names
   slots outside the slice — the adapter's "partial" flag comes from
   that).
4. Verified: every fixture value equals upstream's at the same node
   (715,677 values incl. the whole otype, 0 mismatches).
