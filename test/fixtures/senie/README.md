# SENIE fixtures

Source: The Corpus of Early Written Latvian (2025) — "Senie: latviešu
valodas seno tekstu korpuss", AiLab IMCS UL with the Latvian Language
Institute, University of Latvia. CLARIN-LV repository item
<https://hdl.handle.net/20.500.12574/141> (issued 2025-11-27), bitstream
<https://repository.clarin.lv/repository/xmlui/bitstream/handle/20.500.12574/141/SENIE_Unicode.tei.xml.zip?sequence=2&isAllowed=y>
(8.81 MB, MD5 1e06063000b041fcd25a1c49ff14fff7). Retrieved 2026-10-21.

License: CC BY-SA 4.0 — the item page, verbatim: "This item is Publicly
Available and licensed under: Creative Commons - Attribution-ShareAlike 4.0
International (CC BY-SA 4.0)".

## Upstream grains

| Grain | Where | Taken? |
|---|---|---|
| `SENIE_Unicode.tei.xml` — one 61 MB `<teiCorpus>` of 186 `<TEI>` elements | bitstream 2 (zip) | **yes: the asset** |
| leaf `<TEI>` with a `<text>` (99 top-level + 84 container children = 183) | inside the asset | **yes: the document** |
| container `<TEI>` holding child TEIs (Apokr1689, JT1685, VD1689_94 — no text of its own) | inside the asset | rejected: skipped by rule, counted in `discovery_skips`; its title rides on its children as `collection_title` |
| `SENIE_Unicode_unhyphened.tei.xml.zip` — the same corpus, line-break hyphens contracted by machine | bitstream 3 | not fetched: the contraction rewrites `<sic>` spans across the break (AP1622: `<sic>ayz ledz</sic>` became `<sic>ayzayz ledz</sic>`); the search form rejoins hyphenated lines from the faithful file instead |
| `Senie-DSL-plaintext.zip` — the legacy @-coded plaintext (102 `*_Unicode.txt`) | bitstream 1 | not fetched: the pre-TEI encoding the TEI supersedes |
| `docs.zip` — `metadata.ods` (186-row catalog: source, name, author, order, year, genre, subgenre, manuscript) + `codes-explained.ods` (the @-code legend) | bitstream 4 | not fetched: every catalog field but the in-collection order is in the TEI headers; the legend documents the DSL encoding |

Upstream's count: the item description says "This version contains 102
sources" — the 99 top-level leaves + the 3 containers. `metadata.ods` lists
186 rows (the 102 + the 84 container children). Accepted 183 + skipped 3 =
186; residue 0.

Inside a document the adapter's passage grain is one of three, never mixed in
one TEI (censused on the full file): the page (`<pb n>`, 99 TEIs), the verse
(`<div type="Verse" id="…_ch:v.">`, the 84 Bible books) or the section
(`<div type="Section" n>`, four law/oath prints).

## The file

`SENIE_Unicode.tei.xml` here is the real release file cut on 2026-10-21 at
line granularity (every cut falls between body-level children, so the XML
stays well-formed): the real `<teiCorpus>` header, then

- `AP1622` (Agenda Parva, Braunsberg 1622 — Latin rite, Latvian, German,
  Estonian, and Polish lines tagged Latvian upstream): body cut before the
  4th `<pb>` (pages 1, 6, 7). Pins mixed-language lines, Remark runs, one
  `<corr>/<sic>` pair, the unknown author "nezināms".
- `Depk1681_90_ms` (Depkin's manuscript sermon, "1681_90"): body cut before
  the 16th `<pb>` (pages 1–15). Pins `<chanel>manuscript</chanel>`, the date
  span, and the printed-page `<sic>` after `<pb n="13"/>`.
- `Ench1586` (the 1586 Enchiridion): a body WINDOW — the 33rd through the
  41st `<pb>` (EB … FA, EB). Pins upstream's duplicated page label EB.
- the `JT1685` container (its own header) with two of its 30 children,
  whole: `JT1685::2J` (2 John, 14 verses — the Verse grain, the Comment
  headings, Parallel cross-references) and `JT1685::Prolog_Tit` (the New
  Testament title page, one `<pb n="0">`).
- `SKL1696_KB` (the war-court articles, Riga 1696): body cut before the 6th
  `<div type="Section">` (sections 0., 1., 2., 3., 5.6.).

61 MB → 86 KB.
