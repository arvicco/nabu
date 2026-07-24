# titus-avestan fixtures

Trimmed but structurally-intact real pages from the TITUS Avestan Corpus
(frame-based HTML edition), for the P43-2 adapter.

- Source: TITUS — Thesaurus Indogermanischer Text- und Sprachmaterialien,
  J. W. Goethe-Universität Frankfurt (Prof. Jost Gippert).
- URLs (retrieved 2026-07-24, polite 2s pauses):
  - `avest.htm`    — https://titus.uni-frankfurt.de/texte/etcs/iran/airan/avesta/avest.htm (frameset entry, verbatim)
  - `avest001.htm` — https://titus.uni-frankfurt.de/texte/etcs/iran/airan/avesta/avest001.htm
  - `avest002.htm` — https://titus.uni-frankfurt.de/texte/etcs/iran/airan/avesta/avest002.htm

## Trimming

`avest.htm` is the 1.2 KB frameset entry, kept verbatim. `avest001.htm` keeps
the full editorial header (the credit block), Book **Y** (Yasna), Chapter 0 and
Paragraphs 1–3, then the original "Next part" footer. `avest002.htm` keeps its
(header-less) continuation start — Chapter 1, Paragraph 1, verses a–k — then its
footer. Bytes are otherwise untouched, so the fixtures document the real 1990s
markup quirks the parser must survive: broken `</sPAN>` nesting, `<span id=x12>`
superscript Geldner line-numbers interspersed mid-verse, `<SUP>` in-word
combining marks (`mazdā̊`, `xᵛarənah-`), `<span id=iipzc…>` parenthetical Pahlavi
ritual rubrics, and — on page 2 — the fact that a continuation page carries **no**
`Book:` header, so book context is recoverable only from the
`<A NAME="Avest._Y_1_1_a">` anchors.

## Provenance / grant

This corpus is served under the owner's **personal grant №41-3** (Prof. Jost
Gippert, TITUS, 2026-07-23): non-commercial use, with "TITUS and the editors
clearly indicated wherever displayed." The fetch right is personal to this
project's author and is NOT conveyed by a public clone — hence
`grant_required: true` on the `config/sources.yml` row. These trimmed fixtures
are retained here purely to exercise the parser offline (no network in tests).
