# de Vaan EDL fixtures (P18-6 — the Leiden-school staged-etymon skeleton)

Real upstream sample from **CIRCSE/EtymologicalDictionaryLatin** — de
Vaan's *Etymological Dictionary of Latin and the other Italic Languages*
(Brill 2008) as a LiLa LOD etymology SKELETON (entries omitted, Brill
copyright). Every kept statement block is **byte-verbatim** upstream data;
only the block SET was trimmed.

- **Upstream:** <https://github.com/CIRCSE/EtymologicalDictionaryLatin>,
  `data/BrillEDL.ttl`.
- **Retrieved:** 2026-07-14, from
  `https://raw.githubusercontent.com/CIRCSE/EtymologicalDictionaryLatin/master/data/BrillEDL.ttl`
  (4,064,145 bytes, sha256
  `0b76d9825e0fa38b17bdd16e244fd2f71e54ae587319f3e77d1f2ddb3d69d622`).
  Full-file census: 2,860 `lemonEty:Etymon` (1,394 `lime:language` "PIE" +
  1,466 "PIt"), 1,453 `ontolex:LexicalEntry` nodes (Brill URIs, ids
  `la####`), 2,653 `lemonEty:EtyLink` edges — source→target shapes
  pie→pit 1,216 · pit→lat 1,410 · pie→lat 27 (direct, no PIt stage);
  every `etyLinkType` is `"inheritance"`.
- **License (repo README, verbatim):** de Vaan's EDL "is copyrighted by
  Brill… The dictionary entries are not represented. The data included
  here only serve to express them according to the selected ontology and
  link them to the Knowledge Base of Latin lemmas of LiLa." + CC BY-NC-SA
  4.0 badge → license_class `nc` (the GRETIL/MW posture). Cite Mambrini &
  Passarotti 2020 (Globalex/LREC).

## What the fixture holds (and the quirks it pins)

Prefix block + one **full Latin → PIt → PIE chain** and two edge shapes:

| block | pins |
|---|---|
| `etymon/pie0787` (`*‑ne`) | the **blank-node** `canonicalForm [ writtenRep … ]` shape; **U+2011 non-breaking hyphen** in labels (kept for display, folded to ASCII "-"); an etymon with no link in the slice (honest empty reflexes) |
| `etymology/718` + `etymon/pie1043` (`*Hreh₃d‑e/o‑`) + `etymon/pit1043` (`*(w)rōde/o‑`) + `etylink/1322` + `etylink/1321` + entry `la1405` (`rōdō`) | the chain rōdō ← \*(w)rōde/o‑ ← \*Hreh₃d‑e/o‑: pie→pit proto-to-proto edge + pit→lat edge; multi-value `writtenRep` inside a blank node; variant reconstructions in `rdfs:comment` (`*Hreh₃d‑e/o‑;*ureh₃d‑e/o‑`); macron folding (rōdō → rodo) |
| `etymon/pie1418` (`*kʷot‑slo‑?`) + `etylink/1033` + entry `la0332` (`cōlum`) | one of the 27 **direct PIE→Latin** edges (no PIt stage); a `?`-marked uncertain reconstruction; `ʷ` modifier-letter folding |

Jena-style serialization (8-space aligned predicates, one subject block
each, `"NaN"^^xsd:double` datatyped literals, `@en` language tag on the
dataset description) — all inside the lila-ttl parser's censused subset.
