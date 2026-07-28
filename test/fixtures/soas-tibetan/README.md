# SOAS Classical Tibetan gold POS corpus fixture

Real bytes from the Zenodo deposit "A part-of-speech (POS) tagged corpus of
Classical Tibetan" (Hill, Garrett et al.; SOAS "Tibetan in Digital
Communication", AHRC AH/J00152X/1), record 574878, DOI
10.5281/zenodo.574878, retrieved 2026-07-28. One artifact: `Texts.zip`
(1,780,761 B, Zenodo md5 `1bac00abb7432cc26694449ef47787ef`, sha256
`738262a04d76726391a7debabf828eecb26799a3c6f4b65497c8b87190b0fc55` — the
adapter's `RELEASE_SHA256` pin). The zip unpacks to `Texts/` (plus Apple
`__MACOSX/` sidecar junk the adapter's discover never matches): four
hand-corrected gold-segmentation + gold-POS texts, each in two renderings —
`<stem>-horizontal.txt` (the DISAMBIGUATED gold lane discover ingests) and
`<stem>-horizontal-lex.txt` (every tag the lexicon allows per form, square-
bracketed — undisambiguated furniture, a censused discovery skip).

The four texts (991 gold lines / 318,230 `form|tag` tokens censused
2026-07-28): mdzangsblun (Mdzaṅs blun, 9th c., canonical — 310 lines),
buston (Bu ston chos ḥbyuṅ, 13th c., ecclesiastical history — 309),
mila (Mi la ras paḥi rnam thar, 15th c., biography — 192), marpa
(Mar paḥi rnam thar, 15th c., biography — 180).

## Layout (mirrors the post-fetch tree under `Texts/`)

- `Texts/mdzangsblun-horizontal.txt` — TRIMMED: the REAL first 3 of 310
  lines. Line 1 opens the Mdzaṅs blun ("མཛངས་བླུན་" tagged `n.count`, the
  snippet the adapter test pins) and carries the `~`-joined tag variant
  (`cl.quot~quote.E`).
- `Texts/marpa-horizontal.txt` — TRIMMED: the first 2 of 180 lines
  (the Mar pa rnam thar title line + the `skt` Sanskrit-mantra tag).
- `Texts/mila-horizontal-lex.txt` — TRIMMED: the first 1 line of the
  UNdisambiguated lexicon rendering (`form|[tag][tag]…`) — present so the
  discovery-skip census has real bytes to count; never a DocumentRef.

## The format (censused over all 8 files, 2026-07-28)

Plain UTF-8 text (NFC-stable), LF endings, no interior blank lines. One
line = one editorial chunk of running text; each line is space-separated
`form|tag` pairs — every token has exactly one `|`, tags match
`[a-z0-9.~]+`-ish (`n.count`, `case.gen`, `v.past`, `punc`, `skt`,
`cl.quot~quote.E`; 150 distinct in buston, 95 in mdzangsblun). Forms are
Unicode Tibetan syllables carrying their own tsheg/shad, so the passage
text is the forms joined with NOTHING. Segmentation and POS are
hand-corrected gold (Garrett et al. 2014/2015 tag set); there is NO lemma
column anywhere — the source mints no lemma rows, by honesty.

## License

Zenodo record license: CC BY 4.0 (`cc-by-4.0` on record 574878, verified
2026-07-28) → attribution. Cite the deposit + the SOAS project; see
docs/02-sources.md row 132.
