# calfa-lexicon fixtures

Trimmed real samples of **calfa-co/lexical-databases** — the source files of
the Calfa Classical Armenian dictionary (dictionary.calfa.fr), retrieved
2026-10-21 at upstream commit `71109ce90a8c3bbbb17b772f2b8287f84e540ee6`
(2026-09-29) from
`https://raw.githubusercontent.com/calfa-co/lexical-databases/<commit>/<path>`.

License: the upstream README, verbatim — "These data can be freely used under
a [CC BY-NC 4.0 license](https://creativecommons.org/licenses/by-nc/4.0/)."
(no LICENSE file; the GitHub license field is empty) → class `nc`.

Every file is a LINE TRIM, byte-verbatim (CRLF line ends kept in the TSVs,
LF in the XML): whole upstream lines picked by number, in upstream order,
header line first. Line numbers below are upstream's 1-based line numbers.

## Delivery grains (census 2026-10-21)

Upstream serves ONE git repo; its data grain is the FILE (six data files),
each file a table of ROW = one dictionary entry (the XML: one `<entry>`).
There is no per-record id upstream and no per-row attribution to the
constituent printed dictionaries — the split is by function and language:

| file | rows | taken as |
|---|---|---|
| `definitions/en-definitions01.tsv` | 41,317 | dictionary `calfa-en` (Armenian–English) |
| `definitions_proper/en-definitions01.tsv` | 918 | `calfa-en`, proper-name lane (`np:` ids) |
| `definitions/fr-definitions01.tsv` | 31,586 | dictionary `calfa-fr` (Armenian–French) |
| `definitions_proper/fr-definitions01.tsv` | 920 | `calfa-fr`, proper-name lane (`np:` ids) |
| `etymology/etymology01.xml` | 11,326 `<entry>` | dictionary `calfa-acharian` (Ačaṙean 1926) |
| `synonyms/synonyms01.tsv` | 31,449 | **REJECTED by rule** (see below) |

Accepted: 86,067 entries. Rejected: 31,449 synonym rows (one file).
`README.md` and `.gitignore` are repo documentation, not data.

The README's headline "65,430 entries" does not reconcile to any file sum or
headword union (the union of every headword across all six files, markup and
`*`/`+` marks stripped, case-folded, Ačaṙean's `կամ` variants split, is
60,058; across the four definitions files alone 44,615): it counts the web
dictionary's compiled entries, not the repo's rows.

**Rejected grain — `synonyms/`** (pinned: `synonyms/synonyms01.tsv`, header +
upstream lines 2–4). Łazarean's *Dictionary of Classical Armenian Synonyms*
(Antelias, 2006) is in-copyright material carried under Calfa's grant; the
shelf holds it back until that is ruled on, and discovery counts the file as
skipped-by-rule with its note — never a silent drop.

## Files

- `definitions/en-definitions01.tsv` — lines 1 (header), 2 (the
  `<letter>Ա</letter> (aïp)` letter row), 3–5, 25 (`*Աբեղուկ`, the
  asterisk mark), 26 (two senses, POS adj./np.), 394–396 (the homograph
  `Ակն` ×3), 451 (`Ահաբեկ`, the target of…) 452 (`Ահաբեկեմ`, a quoted
  field carrying a `<a href="./?s=Ահաբեկ">` cross-reference), 3112
  (`<ab>pl.</ab>`), 6179 (`<br />` sense breaks), 38142 (`Տրամագիծ`, an
  empty POS cell).
- `definitions/fr-definitions01.tsv` — lines 1, 2, 3 (`<br />`), 54
  (multi-clause sense), 386–387 (`Ակն` ×2), 393 (`Ակնածեմ`, a
  cross-reference to the AMBIGUOUS `Ակն`), 437 (`*Ակռայ`), 741 (an empty
  POS_2 cell, `<ab>adv.</ab>`), 1158 (`<fr>` spans), 3096 (`*Ապրիմ մեռնիմ`, a
  multi-word headword), 21730 (`<i>`), 27943
  (`Վերստեայ` — a TAB inside a quoted field, upstream's CSV quoting), 29226
  (`Տրամագիծ` — the file's one non-NFC row: `e` + U+0301 in "édit").
- `definitions_proper/en-definitions01.tsv` — lines 1–4, 566–567 (the
  homograph `Յակոբ` ×2: the patriarch / the apostle).
- `definitions_proper/fr-definitions01.tsv` — lines 1–4 (line 2 `Աբաս`
  carries an NBHL-style Armenian prose note with `<br />`), 567–568 (`Յակոբ`
  ×2).
- `etymology/etymology01.xml` — lines 1–2 (declaration + `<dictionary>`),
  the entries `ԱԲ` (8–13), `*ԱԲԲԱ կամ ԱԲԲԱՅ` (14–19, a `կամ` variant
  headword), `ԱԳՈՒՌ` (155–160, a `<ԳՒՌ>` dialect section), `ԱԿՈՒԹ`
  (907–912, `<ԳՒՌ>` + `<ՓՈԽ>`), `ԱՃԱՌ` ×2 (1403–1414, a duplicate
  headword), `+ԱՅՐ` (1910–1914, the `+` mark), `+ԱՐՈՒ` (5190–5195, no
  `<content>`), `*ԳԱՒԱՌ` (9210–9218, the file's one `<other_pox/>`),
  `ԵՂԱՆԱԿ` (13385–13387, headword only), `*ԹԱՐԽԱՆԱՅ` (16650–16656, the
  file's one `<indent/>`), and the closing line 61255. U+0304 combining
  macrons (non-NFC, composed at the boundary) and the AI-processing
  placeholders `[arabic word]` / `[hebrew word]` are upstream's, verbatim.
- `synonyms/synonyms01.tsv` — the rejected-grain specimen (above).
