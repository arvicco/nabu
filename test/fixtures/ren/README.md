# ReN fixtures (Middle Low German / Low Rhenish, TEI / CorA-token)

Real samples from the **Reference Corpus of Middle Low German / Low Rhenish
(1200–1650)** (*Referenzkorpus Mittelniederdeutsch/Niederrheinisch*, ReN),
version **1.1**, in its **TEI** serialisation (CLAUDE.md fixture rules). Two
small complete texts kept whole, plus three structural trims.

- **Retrieved:** 2026-07-26, from the **fdr.uni-hamburg.de deposit record
  9195** (`https://www.fdr.uni-hamburg.de/record/9195`, DOI
  `10.25592/uhhfdm.9195`, published 2021-01-06).
- **Upstream artifact:** `tei_1.1.zip`,
  `https://www.fdr.uni-hamburg.de/record/9195/files/tei_1.1.zip?download=1`
  (302 → short-lived signed S3 URL), 21,829,154 B, sha256
  `b4cc9664268f760517b822c5d3965050ad15d31d712ba7907742c87808b7841e`. The zip
  holds one top dir `tei_1.1/` with `anno/` (161 annotated texts, 1,485,963
  tokens with pos+msd+lemma) and `trans/` (74 transcribed-only texts, 838,400
  bare tokens). The full zip was fetched to a scratch dir and is **not**
  committed; the record also ships CorA-XML (67.8 MB — per-text headers with
  dating/place/language-area the TEI lacks), relANNIS (391.6 MB), html and
  pdf renderings of the same texts (983.7 MB total).

## Files

| File | Bytes | Text | Kept |
|---|---|---|---|
| `anno/Hamb._Uk._1301-1350.tei` | 18,725 | Hamburg charter, 1329 (ASnA; 202 tokens, 15 lines) | **whole** — smallest annotated text |
| `trans/Dub._Uk._1301-1350.tei` | 18,310 | Duisburg charter, 1345 (transcribed-only; **niederrheinisch**) | **whole** — smallest transcribed text |
| `anno/Brs._Ält._DegB_Altst._I.tei` | 26,845 | Braunschweig Ältestes Degedingebuch Altstadt I | **trim** — the two-column exemplar (`<cb n="a"/"b">` restarts line numbers per column) AND the umlaut-sigle exemplar (Ält → `alt` in the slug). Body cut at the `</s>` before the third editorial note (line 377 of the deposit file), closing tags appended. |
| `anno/Lüb._Uk._1351-1400.tei` | 82,408 | Lübeck charters 1351–1400 (ASnA Ortspunkt-Corpus) | **trim** — the entry-restart exemplar: charters Lub 1352a + Lub 1353a, BOTH restarting at `<pb n="1r"/><lb n="01"/>` with no container element → the house `:b2` disambiguator (the ReM M345 shape). Cut before the third charter's editorial note (line 1093), closing tags appended. |
| `anno/Reval_Schragen_1351-1500.tei` | 33,018 | Reval (Tallinn) guild statutes | **trim** — the apparatus exemplar: `join="both"` multi-part tokens (t2_m1..m4), `<add>`, `<del>` split by a line break, in-token `<note place>` with nested `<gap>`/`<unclear>` (t16), a gap-only token (t294), and a `<pb/><lb/>` pair INSIDE a token (t267 `stuyer…schen`). Cut at the `</s>` before `<pb n="26r"/>` (line 494), closing tags appended. |

All trims keep the file head byte-for-byte and cut the body at an `</s>`
boundary with `</ab></body></text>` appended; every fixture is well-formed
(`xmllint --noout` verified). Because a raw GET of the url returns the 21.8 MB
*zip*, not the member file, the manifest marks all five `whole: false`
(fetched for URL-liveness only, never byte-compared); the `trim:` note records
which members are themselves uncut. Re-extract from the zip after any refresh.

## Structure notes (for the P46-5 parser — the ReN cora-tei dialect)

- **No `teiHeader`**: files open at `<text><body><ab>`. No in-file licence,
  language, or title — the filename is the deposit's text sigle.
- Tokens are `<w xml:id="t1_m1" pos="DPDS&lt;DD" msd="Neut.Nom.Sg"
  lemma="desse,desse,dit">Dit</w>` in `anno/`, bare `<w xml:id>` in `trans/`.
  **No `@norm` anywhere** (ReM's inverse); no `<pc>` — punctuation is a `<w>`
  with pos `$;`; `--` is the null for lemma/pos/msd. `join` right/left/**both**.
- `<s>` sentence containers cross-cut manuscript lines; no `@ed` on
  `pb`/`cb`/`lb` anywhere; `<lb>`/`<pb>` may fall **inside** a token.
- Apparatus inside tokens: `<expan>`, `<del>`, `<add>`, `<unclear>`,
  `<gap reason="illegible"/>`, and `<note place="…">` (always the token's
  whole surface — censused corpus-wide). `<note type="editorial">` between
  entries carries the ASnA charter sigle.
- Text is medieval — combining letters (`ghoͤnen` = o + U+0364, `tuͦ` = u +
  U+0366) with **no long ſ** (censused: zero corpus-wide).

## License (recorded exactly)

**CC BY 4.0** — stated on the deposit record itself ("Creative Commons
Attribution 4.0 International", record 9195, verified 2026-07-25). There is
**no in-file licence** (no teiHeader), so the record + DOI are the license
basis. license_class `attribution`. Cite: *Referenzkorpus
Mittelniederdeutsch/Niederrheinisch (1200–1650)*, Version 1.1, Universität
Hamburg / Westfälische Wilhelms-Universität Münster, DOI 10.25592/uhhfdm.9195.
