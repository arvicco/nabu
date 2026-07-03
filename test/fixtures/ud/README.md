# Universal Dependencies fixtures (CoNLL-U)

Real upstream samples from Universal Dependencies ancient-language treebanks
(CLAUDE.md fixture rules), one directory per treebank.

- **Retrieved:** 2026-07-03, from `master` of each treebank's UD repo via
  `raw.githubusercontent.com`.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1).
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

(All URLs prefixed `https://raw.githubusercontent.com/UniversalDependencies/`.)

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
