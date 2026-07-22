# Universal Dependencies fixtures (CoNLL-U)

Real upstream samples from Universal Dependencies ancient-language treebanks
(CLAUDE.md fixture rules), one directory per treebank.

- **Retrieved:** 2026-07-03 for the first four treebanks; **2026-07-09** for the
  first two Old East Slavic treebanks (`old-east-slavic-birchbark`,
  `old-east-slavic-rnc`, packet P10-2); **2026-07-11** for the third,
  `old-east-slavic-ruthenian` (packet P13-1b); **2026-07-17** for the two Old
  Irish glosses treebanks (`old-irish-dipsgg`, `old-irish-dipwbg`, packet
  P25-2); **2026-07-19** for the Hittite treebank (`hittite-hittb`, packet
  P31-0), for the two Perseus treebanks (`ancient-greek-perseus`,
  `latin-perseus`, packet P31-6) and for the two Classical Chinese treebanks
  (`classical-chinese-kyoto`, `classical-chinese-tuecl`, packet P32-0) — all
  from `master` of each treebank's UD repo via `raw.githubusercontent.com`.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1);
  the first two OES treebanks added under packet P10-2 (survey pick #1,
  `.docs/surveys/slavic-survey.md` §1); the Ruthenian treebank under packet P13-1b
  (survey-II pick #1, `.docs/surveys/slavic-survey-2.md` §1).
- **Trim procedure:** each source `*-ud-test.conllu` was trimmed to its **first 50
  complete sentence blocks**. A block = comment lines + token lines up to and
  including the terminating blank line. Files end with a blank line and contain
  only complete blocks (validated: 10 tab-columns per token line, no dangling
  partial block). See the Latin-ITTB note for its extra MWT rule.

## Files

| Dir / file | Source URL | Src bytes | Trimmed bytes | Blocks |
|---|---|---|---|---|
| `gothic-proiel/got_proiel-ud-test-head50.conllu` | `UD_Gothic-PROIEL/master/got_proiel-ud-test.conllu` | 970,958 | 48,093 | 50 |
| `greek-proiel/grc_proiel-ud-test-head50.conllu` | `UD_Ancient_Greek-PROIEL/master/grc_proiel-ud-test.conllu` | 1,465,264 | 91,320 | 50 |
| `sanskrit-vedic/sa_vedic-ud-test-head50.conllu` | `UD_Sanskrit-Vedic/master/sa_vedic-ud-test.conllu` | 3,035,277 | 72,407 | 50 |
| `latin-ittb/la_ittb-ud-test-head50+mwt.conllu` | `UD_Latin-ITTB/master/la_ittb-ud-test.conllu` | 3,184,535 | 61,008 | 50 |
| `old-east-slavic-birchbark/orv_birchbark-ud-test-head50.conllu` | `UD_Old_East_Slavic-Birchbark/master/orv_birchbark-ud-test.conllu` | 1,446,600 | 63,865 | 50 |
| `old-east-slavic-rnc/orv_rnc-ud-test-head50.conllu` | `UD_Old_East_Slavic-RNC/master/orv_rnc-ud-test.conllu` | 2,483,580 | 365,977 | 50 |
| `old-east-slavic-ruthenian/orv_ruthenian-ud-test-head50.conllu` | `UD_Old_East_Slavic-Ruthenian/master/orv_ruthenian-ud-test.conllu` | 940,453 | 309,311 | 50 |
| `old-irish-dipsgg/sga_dipsgg-ud-test-head50.conllu` | `UD_Old_Irish-DipSGG/master/sga_dipsgg-ud-test.conllu` | 37,231 | 24,075 | 50 |
| `old-irish-dipwbg/sga_dipwbg-ud-test.conllu` | `UD_Old_Irish-DipWBG/master/sga_dipwbg-ud-test.conllu` | 32,767 | 32,767 (whole) | 34 |
| `hittite-hittb/hit_hittb-ud-test-head50.conllu` | `UD_Hittite-HitTB/master/hit_hittb-ud-test.conllu` | 118,705 | 46,175 | 50 |
| `ancient-greek-perseus/grc_perseus-ud-test-head50.conllu` | `UD_Ancient_Greek-Perseus/master/grc_perseus-ud-test.conllu` | 1,979,022 | 85,337 | 50 |
| `latin-perseus/la_perseus-ud-test-head50.conllu` | `UD_Latin-Perseus/master/la_perseus-ud-test.conllu` | 1,153,778 | 61,276 | 50 |
| `classical-chinese-kyoto/lzh_kyoto-ud-test-head50.conllu` | `UD_Classical_Chinese-Kyoto/master/lzh_kyoto-ud-test.conllu` | 2,698,869 | 22,472 | 50 |
| `classical-chinese-kyoto/lzh_kyoto-ud-dev-slices.conllu` | `UD_Classical_Chinese-Kyoto/master/lzh_kyoto-ud-dev.conllu` | 3,032,014 | 9,831 | 18 |
| `classical-chinese-tuecl/lzh_tuecl-ud-test-head50.conllu` | `UD_Classical_Chinese-TueCL/master/lzh_tuecl-ud-test.conllu` | 59,420 | 29,817 | 50 |
| `icelandic-icepahc/is_icepahc-ud-dev-head50.conllu` | `UD_Icelandic-IcePaHC/master/is_icepahc-ud-dev.conllu` | 11,860,801 | 49,397 | 50 |

(All URLs prefixed `https://raw.githubusercontent.com/UniversalDependencies/`.)

### Old East Slavic (Birchbark + RNC) trim note (P10-2)

Both OES fixtures are the plain **first 50 complete sentence blocks** of their
`orv_*-ud-test.conllu`. Neither file contains any multiword-token range line
(`n-m`) or empty node (`n.m`) — checked across the whole test split, not just the
head — so, unlike Latin-ITTB, there was nothing extra to preserve; the head-50
slice is representative as-is. The RNC slice is comparatively large (365,977 B)
because Middle-Russian chancery sentences are long (this head-50 runs 2–396
tokens per sentence, mean ~86) and each token line carries a rich RNC-derived
MISC column — the bytes are honest real data, not padding; the count stays at 50
sentences for parity with the other treebanks. Both files carry the CoNLL-U
`# newdoc id`, `# transl_ru`/`# transl_en_*`, `# text` and per-sentence
`# sent_id` comments; the LEMMA (col 3) column is populated (the `orv` lemma-row
acceptance in `universal_dependencies_test.rb`).

### Old East Slavic Ruthenian trim note (P13-1b)

`old-east-slavic-ruthenian/orv_ruthenian-ud-test-head50.conllu` is likewise the
plain **first 50 complete sentence blocks** of `orv_ruthenian-ud-test.conllu`
(390 blocks total). The whole test split contains **no** multiword-token range
line (`n-m`) and **no** empty node (`n.m`) — checked file-wide — so, as with
Birchbark/RNC, the head-50 slice is representative with nothing extra to append.
The slice is 309,311 B because these are long legal/chancery sentences: the head
opens with the Second Lithuanian Statute (1566) and one sentence
(`StatutVKL1566-10`) runs 73 tokens. Comment lines are `# newdoc = …`,
`# lang = orv-be` (a finer BCP-47 regional subtag — Old East Slavic, Belarus —
NOT the UD treebank language, which is `orv`, the file-stem prefix shared with
Birchbark/RNC), `# title`, `# note`, `# newpar`, and per-sentence `# sent_id` /
`# text`. The LEMMA (col 3) column is manually annotated and populated (the
`orv` lemma-row acceptance asserts the opening NOUN lemma `артыкулъ` "article"
at `…:StatutVKL1566-1`, surface form `АРТЫКУЛЪ`).

### Old Irish glosses trim note (P25-2)

`old-irish-dipsgg/sga_dipsgg-ud-test-head50.conllu` is the plain **first 50
complete sentence blocks** of `sga_dipsgg-ud-test.conllu` (64 blocks upstream —
the dependency-annotated subset of the collection's 3,471 St Gall Priscian
glosses; the treebank is test-set only). `old-irish-dipwbg/sga_dipwbg-ud-test.conllu`
is the **whole upstream file** (34 blocks < 50 — the 42-gloss Würzburg treebank
is tiny and growing; byte-identical to upstream at retrieval,
sha256 `f04fd8e44c60be16b68f8ced77cbcd34a304f5986671c48f10e92ad6b9ac161a`).
Neither test split contains any multiword-token range line (`n-m`) or empty
node (`n.m`) — checked file-wide. Comment lines are per-sentence `# sent_id`
(plain integers), `# reference` (manuscript locus, e.g. `1a1`/`16d8`),
`# scribe` (DipSGG), `# text`, `# translation` (DipSGG). The LEMMA column is
populated on most tokens (upstream file-wide: DipSGG 392/418, DipWBG 428/438;
this DipSGG head-50 trim: 246/269 — the rest are `_`, honest upstream gaps). The glosses code-mix Latin inside Irish (both READMEs:
"only those glosses which contain some Irish text are collected here");
the treebank language tag is `sga`, the same one-tag-per-treebank practice
as RNC's Middle Russian under `orv`. Note the SAME St Gall glosses arrive
at a different grain via CorPH (sibling packet P25-0, morphology) — two
honest witnesses, NO dedup (the MW-beside-kaikki precedent).

### Hittite HitTB trim note (P31-0)

`hittite-hittb/hit_hittb-ud-test-head50.conllu` is the plain **first 50
complete sentence blocks** of `hit_hittb-ud-test.conllu` (136 blocks upstream —
the whole treebank: 136 sentences / 1,309 words of Hoffner & Melchert tutorial
examples, test-set only, the DipWBG shape; upstream file sha256
`a55968a8a694503431cfceebf06fad3d2de6a509cc32f92f53710b58fa5fd019` at
retrieval). The treebank is RICH in **multiword-token range lines** — clitic
chains (`ta=an`, `nu=za`, `n=an=ši`…) are split into syntactic words under an
MWT range, 255 range lines file-wide, **98 inside this head-50** — so the
Latin-ITTB MWT machinery is exercised massively; no empty nodes file-wide.
Comment lines are per-sentence `# sent_id` (Hoffner & Melchert section
numbers, e.g. `5.7`), `# text` (bound transliteration), `# translation`, and
`# source` — the REAL manuscript/edition locus (`KBo 6.2 i 16-17 (OH/OS) =
Laws §10`), spanning Old/Middle/New Hittite. The LEMMA column is fully
populated (1,309/1,309 file-wide; Sumerograms lemmatized to their Hittite
readings where known, e.g. `LÚ.U19.LU-an` → `antuhša-`). Language `hit`.

### Perseus pair trim note (P31-6)

Both fixtures are the plain **first 50 complete sentence blocks** of their
upstream test split, retrieved 2026-07-19 from `master`; upstream file sha256
at retrieval:

- `grc_perseus-ud-test.conllu`
  `e18d47c395c0ec8da678fb5e315ce6d90133e88c25ed2a55bc72a2a66e6254d5`
  (1,306 blocks upstream; **no** multiword-token range line and **no** empty
  node file-wide, checked across the whole split — nothing extra to preserve).
  The head-50 is a single `# newdoc id = tlg0008.tlg001.perseus-grc1.12.tb.xml`
  run — Athenaeus, *Deipnosophists* book 12 (the whole test split is Athenaeus
  books 12–13; the treebank's Homer/Hesiod/tragedy bulk sits in the other
  splits, honest note).
- `la_perseus-ud-test.conllu`
  `e0e53fdcc8040a2a6d3b6e7b5dfa69fa35d355ce11cae0682b61e6848745d386`
  (939 blocks upstream, 189 MWT range lines file-wide, no empty nodes;
  **exactly 1 MWT range falls inside the head-50** — block 16, sent
  `phi0690.phi003.perseus-lat1.tb.xml@66`, the enclitic `5-6 mecum` →
  `me` + `cum` — so the ITTB MWT machinery is exercised without any append).
  The head-50 is Vergil, *Aeneid* (`phi0690.phi003`); the split's other
  newdocs (Ovid, Petronius, Phaedrus) fall past the head.

Comment lines in both: `# newdoc id`, per-sentence `# sent_id`
(`<perseus-file>@<n>`, globally unique) and `# text`. The LEMMA (col 3) column
is fully populated file-wide (grc 20,959/20,959 word lines, lat
10,964/10,964); Latin MISC carries `LId=` lemma-sense indices (e.g. `LId=tu1`),
kept verbatim.

### Classical Chinese pair trim note (P32-0)

Both fixtures are the plain **first 50 complete sentence blocks** of their
upstream test split, retrieved 2026-07-19 from `master`; upstream file sha256
at retrieval:

- `lzh_kyoto-ud-test.conllu`
  `e492ba5f5054ee560c33197e1681a5c18c3f21adff7dca82be3ed4af09cbf1e5`
  (5,528 blocks upstream; **no** multiword-token range line and **no** empty
  node file-wide — checked across ALL THREE Kyoto splits, not just test:
  Classical Chinese is written character-per-word, no clitic fusion — nothing
  extra to preserve). The head-50 is a single
  `# newdoc id = KR1h0004_001` run — 論語 學而篇第一 (Analects book 1,
  Kanripo id KR1h0004), title sentence + paragraphs 1–9, 233 word lines.
  SCALE NOTE (the honest census, 2026-07-19): the WHOLE Kyoto treebank is
  86,239 sentences / 433,169 word lines / 9,641 distinct lemmas across
  train (74,609 sents / 36,466,278 B) + dev (6,102 / 3,032,014 B) + test
  (5,528 / 2,698,869 B) ≈ 42.2 MB of conllu — 論語, 孟子, 禮記, 十八史略,
  楚辭, 戰國策, 唐詩三百首 and three sutras (README census; v2.18-era
  master). This one treebank dwarfs the rest of the `ud` source combined.
  LEMMA fully populated file-wide (433,169/433,169); XPOS carries the
  Kyoto four-field kanbun tags (`v,動詞,行為,動作`), MISC carries `Gloss=`
  English glosses — all ride the token annotations verbatim.
- `lzh_tuecl-ud-test.conllu`
  `596d6b22837e0e5bc72471dc6d10d80029da276c4e3298d89bfd4a1c1727fa2a`
  (100 blocks upstream — the whole treebank is 100 sentences / 648 word
  lines of Zhuangzi's 逍遥游 "Enjoyment in Untroubled Ease", test-set only,
  the DipWBG shape; no MWT/empty nodes file-wide; head-50 = sentences 1–50).
  QUIRK, deliberately inside the trim: TueCL carries **free-form comment
  lines with no `= `** — bare Chinese working notes (`# 北方的海里有一条大鱼`),
  annotator questions (`# ???宿是名词`), and `# gloss = …` English lines —
  which the parser must (and does) ignore, interpreting only
  sent_id/text/source. LEMMA populated on 646/648 word lines (2 honest `_`
  gaps upstream); XPOS is `_` throughout; some MISC carry `Translit=`
  variant-character notes (`通“溟”`), kept verbatim.

Comment lines: Kyoto has `# newdoc id`, `# newpar text`, per-sentence
`# sent_id` (`KR1h0004_001_par1_3-7` — Kanripo doc + paragraph + character
span) and `# text`; TueCL has per-sentence `# sent_id` (plain integers 1–100),
`# text`, most blocks `# gloss`, plus the free-form notes above.

### Kyoto dev-slices trim note (P33-3, the Kanripo crosswalk)

`classical-chinese-kyoto/lzh_kyoto-ud-dev-slices.conllu` — retrieved
2026-07-20 from `master` (`lzh_kyoto-ud-dev.conllu`, sha256
`b67614202e30006f9cada1abccbd8f04371f50bd9821791db4c3932a3fd6b3a7`,
3,032,014 B, 6,102 blocks, 26 newdocs). NOT a head-50: the crosswalk
producer needs several Kanripo texts in one file, and the dev head is all
論語 — so the trim is the **first 3 complete sentence blocks of each of six
real `# newdoc id` runs**, verbatim in file order within each run, blocks
intact: `KR1h0004_012` + `KR1h0004_013` (論語 books 12–13 — a two-juan span
for the detail line), `KR1h0001_011` (孟子), `KR4a0001_005` (楚辭 遠遊 —
wave-1 KR4), `KR6f0082_001` (佛說阿彌陀經 — the KR6 sutra the README
mis-lists under train; the data is authoritative) and `KR2e0003_029`
(戰國策 西周 — out-of-wave KR2, the dangling-edge case). 18 blocks, 9,831 B.
The full-split id census (all three splits, 2026-07-20) lives in
`Nabu::KyotoKanripoCrosswalk`'s class note.

### Icelandic IcePaHC trim note (P40-g, the Germanic phase)

`icelandic-icepahc/is_icepahc-ud-dev-head50.conllu` is the plain **first 50
complete sentence blocks** of `is_icepahc-ud-dev.conllu` (retrieved 2026-07-22
from `master`; upstream file sha256 at retrieval
`1ea62344c94791c91f974bc243fab0b08a2c20febafa0b2a5146c9ad342ef68d`). The **dev**
split was chosen over test only because both are ~11.9 MB and dev sorts first;
the treebank is a rule-based UD conversion of the Icelandic Parsed Historical
Corpus (IcePaHC), spanning Old Norse (12th c.) to Modern Icelandic. Upstream
dev has 4,866 blocks; **221 multiword-token range lines file-wide, exactly 1
inside the head-50** (block 30, `1-2 láttu` — an enclitic `lát`+`þú`), and **no
empty nodes** — so the Latin-ITTB MWT machinery is exercised without any append.
Comment lines are per-sentence `# sent_id` (`<year>.<TEXT>.<GENRE>,<n>.<n>`,
e.g. `1250.THETUBROT.NAR-SAG,1.1`), `# X_ID`, and `# text`. The LEMMA (col 3)
column is fully populated; XPOS carries the IcePaHC/Penn constituency tags
(`ADV`, `PRO-N`, `VBDI`), MISC an `IFD_tag=` field (the Icelandic Frequency
Dictionary tag). Language tag `is`.

### Latin-ITTB multiword-token (MWT) rule

The plan called for the first 50 blocks **plus** every sentence block anywhere in
the file containing a multiword-token range line (ID like `20-21`), appended after
and deduped against the head. The full `la_ittb-ud-test.conllu` (2101 blocks)
contains exactly **2 MWT sentences** (blocks 0 and 15 — the enclitic `essetque` →
`14-15`), and **both fall within the head 50**. So **0 MWT sentences were
appended** and the file is the plain first-50 head. It is still named
`…-head50+mwt.conllu` per the plan; the `+mwt` variant is preserved for the
adapter test even though no extra append was needed.

## Licenses (recorded exactly, inconsistencies verbatim)

- **UD_Gothic-PROIEL** and **UD_Ancient_Greek-PROIEL** — `LICENSE.txt` in each
  repo has an internal inconsistency, quoted verbatim:
  > This work is licensed under the Creative Commons Attribution-NonCommercial-
  > ShareAlike **3.0 Generic** License. To view a copy of this license, visit
  > http://creativecommons.org/licenses/by-nc-sa/**4.0**/
  i.e. the prose says **CC BY-NC-SA 3.0 Generic** but the link points to the
  **4.0** deed. Treat as a NonCommercial-ShareAlike license (license_class `nc`).
- **UD_Sanskrit-Vedic** — CC BY-SA 4.0
  (`LICENSE.txt`: "Attribution-ShareAlike 4.0 International",
  http://creativecommons.org/licenses/by-sa/4.0/legalcode).
- **UD_Latin-ITTB** — CC BY-NC-SA 3.0 (`LICENSE.txt`: "distributed under the same
  license as the original ITTB, which is CreativeCommons BY-NC-SA 3.0",
  http://creativecommons.org/licenses/by-nc-sa/3.0/). license_class `nc`.
- **UD_Old_East_Slavic-Birchbark** — **CC BY-SA 4.0** (verified 2026-07-09, the
  P10-2 license gate). `LICENSE.txt`, quoted verbatim:
  > The treebank is licensed under the Creative Commons License
  > Attribution-ShareAlike 4.0 International.
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  and `README.md` machine-readable metadata: `License: CC BY-SA 4.0`. → license
  class `attribution` (MCP-surface-safe). Consistent, no 3.0-vs-4.0 discrepancy.
- **UD_Old_East_Slavic-RNC** — **CC BY-SA 4.0** (verified 2026-07-09). Its
  `LICENSE.txt` is byte-identical to Birchbark's (same verbatim
  "Attribution-ShareAlike 4.0 International" / by-sa/4.0 link) and `README.md`
  metadata likewise records `License: CC BY-SA 4.0`. → license class
  `attribution`.
- **UD_Old_East_Slavic-Ruthenian** — **CC BY-SA 4.0** (verified 2026-07-11, the
  P13-1b license gate). `LICENSE.txt`, quoted verbatim:
  > The treebank is licensed under the Creative Commons License Attribution-ShareAlike 4.0 International.
  >
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  and `README.md` machine-readable metadata: `License: CC BY-SA 4.0`. → license
  class `attribution` (MCP-surface-safe). Consistent, no 3.0-vs-4.0 discrepancy.
  (Note: the GitHub repo license field reads `NOASSERTION`; the authoritative
  grant is the in-repo LICENSE.txt + README metadata, exactly as at P10-2 for
  Birchbark/RNC.)

- **UD_Old_Irish-DipSGG** — **CC BY-NC-SA 4.0** (verified 2026-07-17, the P25-2
  license gate). Its `LICENSE.txt` is, verbatim and in its entirety:
  > CC BY-NC-SA 4.0

  and `README.md` machine-readable metadata agrees: `License: CC BY-NC-SA 4.0`.
  → NonCommercial-ShareAlike: **no override** — the treebank rides the `ud`
  source's `nc` class unchanged (the PROIEL/ITTB class).
- **UD_Hittite-HitTB** — **CC BY-SA 4.0** (verified 2026-07-19, the P31-0
  license gate). `LICENSE.txt`, quoted verbatim and in its entirety:
  > The treebank is licensed under the Creative Commons License Attribution-ShareAlike 4.0 International.
  >
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  and `README.md` machine-readable metadata: `License: CC BY-SA 4.0`. → license
  class `attribution` via the P10-4 per-document `license_override` (the
  birchbark/RNC/DipWBG mechanics exactly); the `ud` source class stays `nc`.
- **UD_Ancient_Greek-Perseus** and **UD_Latin-Perseus** — **CC BY-NC-SA 2.5
  Generic** (verified 2026-07-19, the P31-6 license gate). Each repo's
  `LICENSE.txt` opens, quoted verbatim (identical in both):
  > This work is licensed under the Creative Commons Attribution-NonCommercial-
  > ShareAlike 2.5 Generic License. To view a copy of this license, visit
  >
  > http://creativecommons.org/licenses/by-nc-sa/2.5/

  and each `README.md` machine-readable metadata block agrees:
  `License: CC BY-NC-SA 2.5`. Consistent (unlike the PROIEL 3.0-vs-4.0
  discrepancy), just an old license version. → NonCommercial-ShareAlike:
  **no override** — both treebanks ride the `ud` source's `nc` class
  unchanged (the PROIEL/ITTB/DipSGG posture, NOT the P10-4 mechanics).
- **UD_Old_Irish-DipWBG** — **CC BY-SA 4.0** (verified 2026-07-17, the P25-2
  license gate). `LICENSE.txt`, quoted verbatim:
  > The treebank is licensed under the Creative Commons License Attribution-ShareAlike 4.0 International.
  >
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  and `README.md` machine-readable metadata: `License: CC BY-SA 4.0`. → license
  class `attribution` via the P10-4 per-document `license_override` (the
  birchbark/RNC mechanics exactly).
- **UD_Classical_Chinese-Kyoto** — **CC BY-SA 4.0 by LICENSE.txt, with a
  RECORDED UPSTREAM DISCREPANCY** (verified 2026-07-19, the P32-0 license
  gate). `LICENSE.txt`, quoted verbatim and in its entirety:
  > The treebank is licensed under the Creative Commons License Attribution-ShareAlike 4.0 International.
  >
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  **but** the `README.md` machine-readable metadata says `License: PD` — the
  two grants CONTRADICT each other (unlike every other treebank here except
  the PROIEL 3.0-vs-4.0 version slip, this is a substantive PD-vs-BY-SA
  fork). Ruling: **LICENSE.txt is authoritative** — the Ruthenian precedent
  (the in-repo license file governs over secondary metadata; GitHub's
  license field there read `NOASSERTION` and we followed LICENSE.txt), and
  BY-SA is also the conservative reading (treating PD-claimed data as BY-SA
  can never over-share; the reverse could). → license class `attribution`
  via the P10-4 per-document `license_override`; the `ud` source class
  stays `nc`. If upstream ever reconciles the two, re-read at that fixture
  refresh — never from memory.
- **UD_Classical_Chinese-TueCL** — **CC BY-SA 4.0** (verified 2026-07-19, the
  P32-0 license gate). `LICENSE.txt` is byte-identical to Kyoto's (same
  verbatim "Attribution-ShareAlike 4.0 International" / by-sa/4.0 link) and
  `README.md` machine-readable metadata AGREES: `License: CC BY-SA 4.0` —
  consistent, no discrepancy. → license class `attribution` via the same
  P10-4 per-document `license_override`.
- **UD_Icelandic-IcePaHC** — **CC BY-SA 4.0** (verified 2026-07-22, the P40-g
  license gate). `LICENSE.txt`, quoted verbatim and in its entirety:
  > The treebank is licensed under the Creative Commons License Attribution-ShareAlike 4.0 International.
  >
  > The complete license text is available at:
  > http://creativecommons.org/licenses/by-sa/4.0/legalcode

  and `README.md` machine-readable metadata: `License: CC BY-SA 4.0`. Consistent.
  → license class `attribution` via the P10-4 per-document `license_override`
  (the birchbark/RNC/DipWBG/Hittite mechanics exactly); the `ud` source class
  stays `nc`.

All three OES licenses were confirmed BEFORE the fixtures were committed (packet
gate: had any said anything other than CC BY-SA 4.0 the treebank would have been
dropped); likewise both Old Irish licenses at P25-2, both Perseus licenses
at P31-6 and both Classical Chinese licenses at P32-0 (the Kyoto PD-vs-BY-SA
discrepancy recorded above, LICENSE.txt ruling). The `ud` manifest still
declares the most-restrictive class present — `nc` (PROIEL/ITTB/DipSGG/Perseus)
— so the BY-SA-only treebanks are never over-shared.

## Structure notes (for the CoNLL-U parser + UD adapter, P3-3)

- Line-based TSV, 10 columns: `ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL DEPS MISC`.
- One **sentence = one passage**; blocks separated by a single blank line.
- Comment lines begin `#`; `# sent_id = …` gives the stable id used to mint
  `urn:nabu:ud:<treebank>:<sent_id>`, `# text = …` gives the surface text.
- **Multiword-token range lines** (`ID` like `14-15`) precede the individual
  member tokens (`14`, `15`) and carry no annotations — the parser must handle
  them per P3-3 (the Latin-ITTB fixture exercises this; `essetque` is the case).
- Empty-node ids (`n.1`) may appear in some treebanks; none are relied on here.
- `lemma`/`upos`/`feats` → passage annotations (JSON) per P3-3.
