# OSTA fixtures

Retrieved 2026-08-13 from github.com/hispanicseminary/OSTA (main branch;
the Zenodo deposit 10.5281/zenodo.18931376 v1.0.0 archives the same
data — the license anchor: CC BY-NC-SA 4.0, per the record and the
№45-1 grant thread).

- `transcriptions/TEXT.RHJ.txt` — COMPLETE real file (1.7 kB, the
  corpus's smallest): Glosa al romance "Rey que no hace justicia"
  (HSMS-0198, Real Biblioteca II/1520 (2), ed. Faulhaber). The HSMS
  curly-brace markup in miniature: `{RMK:}` header block, `[fol.]`,
  `{HD.}`, `{CB2.}`, `¶`, `<n>`-style abbreviation expansions, `σ`.
- `transcriptions/TEXT.DAC.txt` — COMPLETE real file (2.0 kB), second
  witness for header/markup variance.
- `verticalized/TEXT.AC2.vrt.html` — the first 220 lines of the real
  file (1.9 MB upstream) + the file's own closing tags (structural
  trim): `<w data1='normalized•lemma•EAGLES-POS'>diplomatic</w>`
  tokens (`fizo•hacer•VMIS3S0`), `<RMK>` header blocks, `<FOL>`/
  `<CB2>`/`<LN id>` structure, `<ABB>`/`<SUP>` display marks,
  contraction composites (`del•de·el•SPS00·DA0MS0`).

- `tables/tabla-obras.xlsx` + `tables/tabla-codices.xlsx` (P77-r6,
  №R-30) — the real works/codices tables TRIMMED to six sigla
  (RHJ, DAC, AC2, FNG, FJZ, PN2): kept row XML verbatim, sharedStrings
  and all structure byte-identical, non-data sheets cut to their header
  rows, re-zipped with Info-ZIP. FNG carries the castellano/aragonés/
  navarro mixed-language tie, FJZ the leonés minority, PN2 the 17-work
  cancionero; RHJ and AC2 have no codex row upstream — the absent-codex
  witnesses.

Per-text citation identifiers follow the №45-1 ruling: TEXT.xxx.txt.
