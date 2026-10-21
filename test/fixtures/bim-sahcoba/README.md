# BIM/SAHCOBA fixtures

Source: BIM/SAHCOBA corpus: Syntactically Annotated Historical Corpus in
Basque — HiTZ, University of the Basque Country (Ainara Estarrona, Izaskun
Etxeberria, Ricardo Etxepare, Ander Soraluze, Manuel Padilla-Moyano).
CLARIAH-EUS repository item <https://hdl.handle.net/20.500.14614/43>
(doi:10.71845/hitz-32, issued 2026-06-17), bitstream
<https://clariah.hitz.eus/server/api/core/bitstreams/ca44acee-b541-458b-a917-fbf5eeb3f71d/content>
(`BZENTROA-BIM.zip`, 2,926,904 bytes). Retrieved 2026-10-21.

License: CC BY 4.0 — the item record's dc.rights, verbatim: "Creative
Commons - Attribution 4.0 International (CC BY 4.0)" (rights URI
creativecommons.org/licenses/by/4.0/, rights label PUB).

## Upstream grains

| Grain | Where | Taken? |
|---|---|---|
| `BZENTROA-BIM/<Author>_automatikoa.tsv` — one token stream per work (15) | the item's one ORIGINAL bitstream (zip) | **yes: the document** |
| a token line: form · standardized form · lemma · Basque POS · UPOS | inside each TSV | the token annotation; the passage is DERIVED (no sentence or page structure exists — see below) |
| `license.txt` — the repository's deposit agreement | the item's LICENSE bundle | not fetched: an agreement, not text |
| item 20.500.14614/21 (doi:10.71845/hitz-17) — the search-interface record | a sibling item, type toolService | not fetched: it carries no files |
| bim.ixa.eus — the search application with per-work metadata (period, dialect, author) | web | not an acquisition route (a browser challenge answers) |

Upstream's count: the zip holds 15 files / 669,109 token lines (the record
says "around one million words" for the BIM range and local.size.info
600,000 tokens). Accepted 15 of 15; nothing skipped.

The passage rule (BimTsvParser): the source page where the stream carries
single-bracket page markers (`< 3 >`, `< I 17 >`, `< 126v >` — 11 works),
else the sentence (Chourio, Etxepare, Larramendi, Leizarraga, Maister,
Pouvreau). Tag runs `< lat > … < / lat >`, `< gap > … < / gap >` and
`< / text >` are markup, never text; `< <` / `> >` are the corpus's
quotation marks.

## Files

Line windows cut 2026-10-21 from the 15 files (a TSV has no structure to
break — every window starts and ends on whole token lines):

- `Materra_automatikoa.tsv` — lines 1–213 of 21,944: the title page
  ("Bordelen, Jacques Millanges … 1623"), pages i–iii, the `< / text >` /
  `< gap >` French dedication to Claude de Rueil.
- `Beriain_automatikoa.tsv` — lines 12,203–12,489 of 18,170: folios 90v and
  91r, with a `< lat > " pater noster " < / lat >` span and `&quot;`
  escapes.
- `Axular_automatikoa.tsv` — lines 108,371–108,970 of 116,746: pages 584,
  585 and upstream's second 585.
- `Etxepare_automatikoa.tsv` — lines 1–1,442 of 4,700 (ending on a sentence
  period): no page markers — the sentence grain — and the `< <` quotation
  marks of the verse dialogues.
