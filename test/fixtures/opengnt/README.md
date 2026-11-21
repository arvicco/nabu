# OpenGNT fixtures

Real upstream samples from eliranwong/OpenGNT — the Open Greek New
Testament base text, OGNT version 3 (file `OpenGNT_version3_3.csv`).

- **Retrieved:** 2026-11-18, `OpenGNT_BASE_TEXT.zip` from
  `https://raw.githubusercontent.com/eliranwong/OpenGNT/0029589cccd50bd48b1941aa041a956de6c29ac4/OpenGNT_BASE_TEXT.zip`
  (repo HEAD pinned `0029589cccd50bd48b1941aa041a956de6c29ac4`,
  2022-04-21; no releases or tags upstream). Zip: 8,351,123 B, sha256
  `7d8377bad8d8c836272ca67a646024a303e524434345c61ee288b82d13f8e712`;
  members `OpenGNT_version3_3.csv` (46,440,555 B, dated 2018-10-07) and
  `__MACOSX/._OpenGNT_version3_3.csv` (319 B).
- **Census of the full CSV:** 138,014 lines = 1 header + 138,013 word
  rows; 27 books (numbers 40–66); 7,941 distinct verses; UTF-8, no BOM,
  LF line ends, 13 TAB-separated columns on every row.
- **License** (README "License:", verbatim): "The main text of Open Greek
  New Testament Project, OGNT in short, is released under the following
  license: … Open Greek New Testament Project by Eliran Wong is licensed
  under a Creative Commons Attribution-ShareAlike 4.0 International
  License." → `license_class: attribution`, share-alike. Fixture
  redistribution under the same CC BY-SA 4.0 terms, credit Eliran Wong.
  The CSV's gloss/translation column and Levinsohn columns carry other
  terms (Berean: "Copyright ©2016, 2018 by Bible Hub … All Rights
  Reserved Worldwide"; TBESG titled CC BY-NC-ND; Levinsohn GNTDF ©2016
  SIL International under SIL's end-user licence). They are present in
  these fixture rows only because the rows are byte-verbatim; the adapter
  never emits them (pinned by the adapter test).

## Files

| Path | Contents |
|---|---|
| `OpenGNT_version3_3.csv` | **Trimmed**: the real header row + every word row (byte-identical, upstream order) of Matthew 1:1, 1:2, 1:23 (¬ layout marks, an OT quotation), 2:16 (a ＝ orthographic-variant note), 4:16 (a ＊ NA28-differs note), 8:8 (a ＋BYZ added word); Mark 1:1–3, 6:33 (the decomposed lexeme bytes U+1FC6 U+0345 in πεζῇ — the NFC regression), 16:20 (the `[[ ]]` shorter ending inside the verse); 3 John WHOLE (15 verses, 218 words). 456 word rows. |
| `__MACOSX/._OpenGNT_version3_3.csv` | **Whole**: the zip's macOS AppleDouble resource-fork member, byte-identical — the rejected grain, pinned real so `discovery_skips` is tested against it. (A dotfile: the fixture-manifest orphan check globs without dotfiles, so it is recorded here rather than in `manifest.yml`.) |

Re-cut recipe: download the pinned zip, unzip, keep line 1 plus every
row whose column 7 (`〔Book｜Chapter｜Verse〕`) is one of the verses
above, in file order; copy the AppleDouble member as is.

## Delivery grains (enumerated at fixture time)

The repo serves many grains; the adapter takes ONE:

- **Accepted** — `OpenGNT_BASE_TEXT.zip` → the base-text CSV. Document =
  one NT book (the CSV's book number), passage = one verse.
- **Rejected inside the fetched zip** — `__MACOSX/._OpenGNT_version3_3.csv`
  (AppleDouble, not text): skipped by rule, pinned above.
- **Never fetched (out of scope by rule)** — `OpenGNT_keyedFeatures.csv.zip`
  (Levinsohn/OpenText mapping features), the interlinear translation zips
  (Berean, NET2, CUVtc, Spanish), `clause-translation/`, the per-language
  morphology and RMAC dictionaries, `Lexicons/`, `Glossary/`,
  `Modules_for_Bible_Applications/`, `OpenGNT-concordance/`, the
  `mapping_*` trees, `OldVersions/`, `onlineReader/`, `Script/`,
  `Screenshot/`, the heading cross-reference TSVs. None lands in
  `canonical/opengnt/`.

## Column map (the header row, as shipped)

`fileDescription.md` documents an older column order; the shipped header
is authoritative (it adds `OTquotation` as column 5 and orders `rmac`
before `sn`):

| # | Header | Adapter |
|---|---|---|
| 1 | `OGNTsort` | token `id` |
| 2 | `TANTTsort` | not carried (sort key into TANTT) |
| 3 | `FEATURESsort1` | not carried (sort key into keyedFeatures) |
| 4 | `LevinsohnClauseID` | **EXCLUDED** (SIL Levinsohn layer) |
| 5 | `OTquotation` (`+`/`-`) | **EXCLUDED** (SIL Levinsohn layer) |
| 6 | `〔BGBsortI｜LTsortI｜STsortI〕` | not carried (sort keys) |
| 7 | `〔Book｜Chapter｜Verse〕` | document + passage urn |
| 8 | `〔OGNTk｜OGNTu｜OGNTa｜lexeme｜rmac｜sn〕` | OGNTa → text + `form`; `lemma`, `rmac`, `strong`; OGNTk/OGNTu not carried |
| 9 | `〔BDAGentry｜EDNTentry｜MounceEntry｜GoodrickKohlenbergerNumbers｜LN-LouwNidaNumbers〕` | `ln`; the rest not carried |
| 10 | `〔transSBLcap｜transSBL｜modernGreek｜Fonética_Transliteración〕` | not carried (transliterations) |
| 11 | `〔TBESG｜IT｜LT｜ST｜Español〕` | **EXCLUDED** (glosses / translations) |
| 12 | `〔PMpWord｜PMfWord〕` | `pmp`/`pmf` verbatim; non-layout marks attach in the text (¶ ¬ are layout) |
| 13 | `〔Note｜Mvar｜Mlexeme｜Mrmac｜Msn｜MTBESG〕` | `note`, `mvar`, `mlexeme`, `mrmac`, `msn`; MTBESG **EXCLUDED** (gloss) |
