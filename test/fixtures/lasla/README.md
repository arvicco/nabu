# LASLA fixture

Real bytes from CIRCSE's LASLA release (github.com/CIRCSE/LASLA, branch
`main`, last upstream push 2024-10-15), retrieved 2026-10-21 by raw GET
(`https://raw.githubusercontent.com/CIRCSE/LASLA/main/<path>`). LASLA =
the Latin corpus of the Laboratoire d'Analyse Statistique des Langues
Anciennes (Université de Liège), linked token by token to the LiLa
LemmaBank by the LiLa project (ERC 769994).

## Delivery grains (the whole repo, censused 2026-10-21)

| grain | upstream | adapter |
| --- | --- | --- |
| `conllup/<Author>_<Work>_<code>.conllup` — one per work, or per book of a long work (CaesBG1…7) | 242 files, 95,974 sentences, 1,875,776 token lines (1,839,371 words + 36,405 multiword ranges) | **ACCEPTED** — document = file, passage = sentence |
| `texts/<Author><Work>.ttl.gz` — the per-work Turtle serialization of the same annotation | 131 files (65 MB) — upstream's "~130 texts" | rejected: outside the fetch cone; skipped by rule + counted if present |
| `complete_lasla.ttl.gz` — the whole corpus as one Turtle file | 1 file (102 MB) | rejected: outside the fetch cone |
| `lemma_LiLaRef.tsv.gz` — lemma → LiLa crosswalk table | 1 file (232 KB) | rejected: outside the fetch cone (the LiLa ids already ride every token) |

Reconciliation: 242 conllup files = the 131 works with the long ones
split by book.

## Layout

- `conllup/Cicero_CumQuaestorLilybaeoDecederetFragmenta_CicQuaest.conllup`
  — WHOLE (3,307 B; one sentence). Carries the `# global.columns` header
  opening the first block, `LASLAVariant=2` in MISC, and the per-file
  TokenURI base (`…CicQuaest.BPN_t_0000001` = base + 7-digit LINE).
- `conllup/Catullus_Catullus_Catul.conllup` — TRIMMED: the header line +
  the first 3 sentence blocks (poem 1, Versus 1–10), lines byte-verbatim.
  Verse citations (`Liber_1,Versus_1` → `Versus_2` within one sentence).
- `conllup/Tacitus_TacHistoriae_TacHist4.conllup` — TRIMMED: the header
  line + sentence block TacHist4-Q-05-1672 (upstream lines 856–906: the
  ambiguous LiLa link on `an` — three lemma/URI pairs, 19 columns, the
  CitationHierarchy repeated per candidate; `Tac=est` on `testatum`) +
  blocks 1791, 1792, 1791, 1792 (upstream lines 5913–6031): upstream's one
  REPEATED sent_id run, an interleaved sentence resumed ("sed quia naues
  saeuitia hiemis" / "prohibebantur"), plus a multiword-token range
  (`5-6 magnisque`, 13 columns).
- `conllup/Livius_AbVrbeCondita_TLiv08.conllup` — TRIMMED: the header
  line + the first sentence block (upstream lines 1–27). One of the six
  files upstream never linked to LiLa: every word line is 13 columns, MISC
  carries no CitationHierarchy (only `LASLAVariant`), so the passage cites
  by sent_id alone and no token carries a LiLa id.
- `texts/CiceroCum Quaestor Lilybaeo Decederet Fragmenta.ttl.gz` — WHOLE
  (1,180 B): the REJECTED Turtle grain's specimen (the same work as
  CicQuaest in RDF); discover never yields it, discovery_skips counts it.

## The dialect (censused over all 242 files)

Token lines: 13 columns (128,416) on multiword-token ranges (36,405) and on
every word of the six files upstream never linked to LiLa (92,011 — Livy 8,
Ovid Met. 6 / 7+11+14 / 9+10, Pliny NH 2 / 37, which also carry no
CitationHierarchy), 15 on
ordinary tokens (1,743,705), 17 or 19 when the LiLa linking is ambiguous
(1,506 / 2,149) — the 10 CoNLL-U columns, FLCAT/SENTID/LINE, then one
(lilaLemma, TokenURI) pair per candidate. The header names only 13
columns. HEAD/DEPREL/DEPS are `_` everywhere; no PUNCT tokens; `# text` is
LASLA's normalized surface (u for v, unpunctuated). MISC keys:
CitationHierarchy (every word), LASLAVariant (581,168), Tac (6,846).

## License

Repo README "Copyright", verbatim: "These resources are licensed under a
Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International
License." → `nc`.
