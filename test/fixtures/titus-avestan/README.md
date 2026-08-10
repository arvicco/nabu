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
the full editorial header (the credit block), Book **Y** (Yasna), Chapter 0,
Paragraphs 1–3 AND Paragraph 13 (spliced in real document order, 2026-07-24 —
P43-i2: paragraph 13 carries the repeated-recitation anchors Q1c/Q1d twice
each, the liturgical-repetition genus that 48 of the 248 live pages show and
the original 1–3 trim had cut away), then the original "Next part" footer. `avest002.htm` keeps its
(header-less) continuation start — Chapter 1, Paragraph 1, verses a–k — then its
footer. Bytes are otherwise untouched, so the fixtures document the real 1990s
markup quirks the parser must survive: broken `</sPAN>` nesting, `<span id=x12>`
superscript Geldner line-numbers interspersed mid-verse, `<SUP>` in-word
combining marks (`mazdā̊`, `xᵛarənah-`), `<span id=iipzc…>` parenthetical Pahlavi
ritual rubrics, and — on page 2 — the fact that a continuation page carries **no**
`Book:` header, so book context is recoverable only from the
`<A NAME="Avest._Y_1_1_a">` anchors.

## avest029.htm (P66-1)

The WHOLE live Yasna 28 page (the first Gatha), copied 2026-08-10 from
the owner's held canonical/titus-avestan tree (same grant) — the
old-avestan exemplar for the avestan-stage facet (Gathic chapters
Y 28–41, 43–51, 53; every other page/book is Young Avestan).

## Provenance / grant

This corpus is served under the owner's **personal grant №41-3** (Prof. Jost
Gippert, TITUS, 2026-07-23): non-commercial use, with "TITUS and the editors
clearly indicated wherever displayed." The fetch right is personal to this
project's author and is NOT conveyed by a public clone — hence
`grant_required: true` on the `config/sources.yml` row. These trimmed fixtures
are retained here purely to exercise the parser offline (no network in tests).
