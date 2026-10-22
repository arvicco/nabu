# memis fixture

Trimmed REAL excerpt of MEMIS 1.0 — Epigrafski korpus srednjeveških in
zgodnje novoveških napisov na Slovenskem / Epigraphic corpus of Medieval
and Early Modern inscriptions in Slovenia (Gregor Pobežin, ZRC SAZU;
TEI by Tomaž Erjavec). Retrieved 2026-10-22 from the CLARIN.SI deposit
http://hdl.handle.net/11356/1376 (issued 2020-12-06), its one bitstream:

https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1376/MEMIS.xml?sequence=3&isAllowed=y

(160,164 bytes, 3,490 lines, sha256
74f523312b016e4cbab8f3bbb19a7609e18e89f4c63c70617a4834bd68552861,
Last-Modified Mon, 27 Mar 2023 17:01:19 GMT; served with a
`text/xml;charset=ISO-8859-1` header although the bytes are UTF-8, as
the XML declaration says.)

## License (verified 2026-10-22)

The deposit page's DC.rights: "Creative Commons - Attribution-ShareAlike
4.0 International (CC BY-SA 4.0)"; the file's own `<availability>`:
"This work is licenced under the Attribution-ShareAlike 4.0
International (CC BY-SA 4.0)" → `attribution`.

## Delivery grains

The deposit serves ONE bitstream, MEMIS.xml (the landing page is
metadata, not data). Inside it:

- `<teiHeader>` — the edition's header (not a grain);
- `<front>` — the corpus introduction, Slovene prose: **rejected**,
  counted skipped-by-rule; kept whole in the fixture as its specimen;
- `<body>` — 51 `<div type="inscription" n="1…51">`: **the accepted
  grain**, one document each. Each holds a description div (msDesc),
  a transcription div (`transcr`, `trans` on no. 1) and a Slovene
  translation div. The document key is `@n`; the msIdentifier idno is
  NOT unique upstream (I-1-002 is worn by nos. 2, 21 and 26).

Census of the full file: 49 inscriptions from Koper, 2 from Piran; 476
numbered transcription lines (473 with text: one is the Greek
placeholder "..." of no. 32, two are empty — no. 30's line 12 and no.
40's doubled `<lb n="2"/>`); origDate on 50 (one "?"), so 49 dated, 1 CE – 1740.

## Cut

The teiHeader, `<front>` and the closing tags whole; of the body, the
14 inscription divs n = 1, 2, 4, 6, 8, 12, 16, 21, 32, 38, 40, 46, 50,
51, byte-verbatim in upstream order (the other 37 divs removed whole). They
cover: the pseudo-inscription (1, undated, `trans`), expansions,
unclear, damage/supplied, gap and corr (2), two transcribed sides with
titles (4, 38), the date shapes "2. pol. 15. stol." (6), "29. 8. 1578"
(8), "1581/2" (12), "ok. 1670" (16), "1. stol. po Kr." (21, also a
duplicate idno and an in-text date 1222), "1591?" (38) and "?" (46),
the Greek placeholder transcription "..." (32), the doubled empty
`<lb n="2"/>` (40), and Piran (50, whose
text says MCCCXXX against origDate 1430; 51, the painted elogium with
caesurae).

## Refresh

Re-fetch the bitstream URL above and re-cut the same `n` values (the
recipe keeps each div's lines from its opening tag to the line before
the next inscription div).
