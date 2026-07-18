# DSS fixture — Dead Sea Scrolls (Abegg/ETCBC, P30-5)

Byte-verbatim trimmed slices of the frozen `tf/2.0` Text-Fabric dataset of
[github.com/ETCBC/dss](https://github.com/ETCBC/dss).

- **Retrieved:** 2026-07-18, from commit
  `2403d16654984fc5567a5bd263086d9ad2a7a1dd` (master), via raw GETs of
  `https://raw.githubusercontent.com/ETCBC/dss/master/tf/2.0/<name>.tf`.
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches
  (`tf/2.0/*.tf`); the license-bearing `docs/about.md` (also in the sparse
  cone) is quoted below rather than checked in — the adapter never parses it.

## Upstream census (at the pinned commit, from otype.tf — checked in WHOLE)

`tf/2.0` = 79 files, 138,951,983 bytes (≈ 139 MB of the 206 MB repo).
otype.tf declares: **1,430,241 signs / 500,995 words / 52,895 lines /
11,182 fragments / 1,001 scroll nodes / 10,450 lexemes** — every P30-5
briefed number exact — plus 101,099 clusters and the v2.0 ML extras'
125 clauses / 315 phrases (ALL of them inside 1Qisaa; silver, not
ingested). Corpus-wide facts the fixture scrolls were chosen to attest:
only 997 DISTINCT scroll names (4Q88, 4Q483, 11Q5, 11Q6 each label two
scroll nodes — the biblical/non-biblical source-file split the conversion
did not reunite; downcasing collides no OTHER pair, censused), per-word
`lang` values only absent/`a`/`g` (Hebrew/Aramaic/Greek — all 7 Greek
words live in 3Q15), line labels all-integer, fragment labels never
containing "." and (scroll, fragment, line) globally unique, words never
crossing line boundaries and never discontinuous, line node order equal
to slot order, ZERO lines whose text-orig-full render is empty, and
exactly 6 clusters corpus-wide crossing a line boundary. NO period/dating
feature exists in tf/2.0 (the P30-5 date-axis census verdict; `script` is
paleohebrew/greekcapital — a script fact, not a date).

## License (both verbatim, retrieved 2026-07-18)

Every `.tf` header carries the machine-readable pair:

> @license=Creative Commons Attribution-NonCommercial 4.0 International License
> @licenseUrl=http://creativecommons.org/licenses/by-nc/4.0/

and `docs/about.md` carries the human grant:

> Upon learning of the current project, Martin Abegg graciously gave
> permission to Jarod Jacobs to use his data and to distribute the results
> under a CC-BY-NC license.

> The data in this repo, notably the contents of its `.tf` subdirectory,
> is available under a CC-BY-NC license

> The program code in this repo is freely available under the MIT license.

MIT covers code only; the data grant is CC BY-NC → source class `nc`.

## The six slices (5 scrolls, 6 scroll nodes)

| slice | slots | lines | why |
|---|---|---|---|
| 3Q15 (Copper Scroll, whole: 12 columns, 181 lines, 1,180 words) | 140842–144186 | 181 | the flag-rich Hebrew non-biblical lane: cor/cor3/rec/rem/vac clusters, all 7 Greek words (`lang=g`, greekcapital — line 1.4's ΚΕΝ), 35 paleo-Hebrew numerals (`type=numr`, e.g. א֜ק֜ at word 1655485, line 1.6), 68 sof-pasuq punct words, vac cluster 1436791 (empty sign, no word) in line 1.15 |
| 4Q156 (Targum of Leviticus, whole: 2 fragments, 14 lines, 166 words) | 146170–146597 | 14 | the Aramaic lane (154 `a` vs 12 punct-word Hebrew votes); rec clusters 1437217–19 in f1:2 with the flagged `full` bytes "ח##פנו?׳ה##[ י ]"; empty-transcription word 1657373 (glyph absent, `full`="ε", `lex`=" # ") |
| 4Q483 node **1606388** (papGen?, 2 fragments, 5 lines) | 539876–540101 | 5 | first of the DUPLICATE-NAME pair → plain urn `dss:4q483`; biblical lane: Gen 1:27–28 word refs with `biblical=2` (three of the corpus's 14 both-files lines); ╱ end-of-line tokens |
| 4Q567 (Aramaic, 1 fragment, 3 lines) | 663625–663666 | 3 | the fixture's only `alt` (alternative-reading) cluster 1491352 (f1:2) beside rec + vac; second Aramaic witness |
| 4Q143 (Deut 10:22–11:11, 2 fragments, 15 lines) | 1314784–1315365 | 15 | cluster 1525404 (`rem2`, slots 1314784–1314916) — one of the 6 corpus-wide LINE-CROSSING clusters, spanning f1R:1–3 → the clipped-`ranges` + `partial: true` witness; `cor2` cluster; mixed-case fragment label `f1R` (urns keep label case verbatim); biblical=1 Deut refs |
| 4Q483 node **1606812** (2 lines) | 1320075–1320133 | 2 | second node of the duplicate name → urn `dss:4q483-2`; carries f1:4–5 (Gen 1:29), proving the two nodes are one physical scroll split by source file |

Scroll nodes kept in scroll.tf: 1605955 (3Q15), 1605960 (4Q156),
1606388 + 1606812 (4Q483), 1606476 (4Q567), 1606801 (4Q143).

Not attested in the slices (real upstream, documented here so their
absence is honest): `unc2` clusters (906 corpus-wide), `halfverse`
(932 words), `intl` (interlinear, 1,632 nodes), and `merr` (Abegg-tag
parse errors — exactly ONE word corpus-wide, node 1747115, value
"vnPfpa"); their trimmed feature files carry headers with zero in-slice
data rows and the adapter reads them as absent.

## OSHB lexeme join (measured 2026-07-18, fixture level — nothing wired)

Folding the slices' 399 distinct word-grain `lex` values consonantally
(Normalize.search_form for hbo + keep only א–ת; "_N" homograph suffixes
stripped) leaves 372 foldable lexemes (27 are placeholders like " # ");
**301/372 = 80.9%** match an augmented-Strong headword of the FULL
openscriptures HebrewStrong.xml the same fold. Against the trimmed
`test/fixtures/hebrew-lexicon` slice the number is 19/372 (that fixture
is itself a trim). Measured and journaled (02-sources row 88) — the join
is NOT built.

## Trim recipe (scripted; re-run per this table after any refresh)

Every data line kept is byte-verbatim upstream; the ONLY synthesized
bytes are explicit `<node><TAB>` anchors at trim-gap starts and range
specs clipped to the keep set (anchors and ranges are core .tf format).
The keep set = the six slices' sign slots + every cluster/fragment/line/
scroll/word node whose slots fall inside them. The lex-NODE block
(1542523–1552972) and the clause/phrase nodes are dropped everywhere —
the adapter reads lex word-grain and never touches the silver nodes.

| file | upstream B → fixture B | grain kept |
|---|---|---|
| `otype.tf`, `otext.tf` | 750 / 1,139 → same | WHOLE, byte-identical (otype is the census-of-record; otext documents `@fmt:text-orig-full={glyph}{punc}{after}` and `@sectionTypes=scroll,fragment,line` = the identity + rendering contract) |
| `oslots.tf` | 14,394,455 → 26,748 | slice cluster/fragment/line/scroll/word nodes (2,106 rows) |
| `scroll.tf`, `fragment.tf`, `line.tf` | 378,532 / 268,441 / 119,086 → 1,949 / 1,225 / 1,106 | slice scroll+fragment+line labels |
| `glyph.tf`, `after.tf`, `punc.tf`, `full.tf`, `type.tf` | 0.3–10.8 MB → 1.6–35 KB | slice sign + word (+ cluster, for `type`) grains — the text surface and word/cluster types |
| `lang.tf`, `script.tf` | 418,353 / 61,876 → 2,156 / 3,850 | slice sign+word grains |
| `lex.tf`, `sp.tf`, `cl.tf`, `ps.tf`, `gn.tf`, `nu.tf`, `st.tf`, `vs.tf`, `vt.tf`, `md.tf`, `morpho.tf` | 26 KB–4.5 MB → 0.6–17 KB | slice word grain (lex-node block dropped) |
| `cor.tf`, `rec.tf`, `rem.tf`, `alt.tf`, `unc.tf`, `vac.tf` | 4 KB–1.9 MB → 0.5–3.4 KB | slice sign grain (the per-sign flag projections of the clusters) |
| `biblical.tf`, `book.tf`, `chapter.tf`, `verse.tf` | 0.5–0.9 MB → 1.0–1.9 KB | slice grains (biblical also covers clusters/fragments/lines/scrolls) |
| `merr.tf`, `intl.tf`, `halfverse.tf` | 555 / 4,993 / 2,552 → 540 / 589 / 552 | header-only trims (zero in-slice rows — see above) |

Features deliberately NOT fixtured (and not read by the adapter): the
ML-derived `*_etcbc` lane + `morph_etcbc`/`note_etcbc` (silver — the
goo300k/imp discipline), the transliteration/source variants (`*e`/`*o`,
`g_cons`, `glyphe/glypho`, `fulle/fullo`, `punce/punco`, `lexe/lexo`,
`glex*`), the second/third-morpheme features (`gn2/gn3`, `nu2/nu3`,
`ps2/ps3`, `cl2` — the original tag rides tokens whole as `morpho`),
`srcLn`/`nr`/`sim`/`occ` (source-file provenance, similarity and the
lex-node occurrence edges), and `book_etcbc`/`lang_etcbc`/`uvf_etcbc`.
