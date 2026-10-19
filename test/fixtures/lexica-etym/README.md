# Lexica `<etym>` fixtures

Real upstream entries from **PerseusDL/lexica** (the same repository and
license as `test/fixtures/lexica/` — CC BY-SA 4.0, credit Perseus Digital
Library; see that README for the verbatim grant), chosen to pin the
`<etym>` mining shapes of `Nabu::Adapters::LexiconTeiParser`. Used by
`test/adapters/lexicon_tei_parser_test.rb` only (the lexica adapter's own
tests keep the `lexica` fixture set and its counts).

- **Retrieved:** 2026-10-19, re-cut from the box's `canonical/lexica/`
  clone of PerseusDL/lexica (the upstream files at the same paths).
- **Recipe:** the `teiHeader` and document frame are the existing
  `test/fixtures/lexica/` files' (themselves byte-identical upstream
  slices); each kept `<entryFree>…</entryFree>` is a byte-identical slice
  of the canonical file, wrapped in its real `div0` letter frame. All other
  entries removed.

| File | Kept entries | Why |
|---|---|---|
| `grc/lsj/grc.lsj.perseus-eng13.xml` | μεταπνοή (`metapnoh/`, n66879), μετάψυξις (`meta/yucis`, n67061) | μετάψυξις's `(<etym lang="greek">metapnoh/</etym>)` names a headword held in the same file — the exact-headword resolution pin (μεταπνοή also carries a `gloss on` `<xr>` back) |
| `lat/ls/lat.ls.perseus-eng2.xml` | ambactus (A), bimeter (B), do2 (D), hydrius (H), metrum (M), vespa (V) | bimeter `bis-metrum` = the hyphen-compound base shape (metrum held, bis not); do2 and vespa = cognate chains (Sanscr./Gr./Ger./Eng.; Gr./O. H. Germ./Engl.); ambactus = an unmapped label (`Celt.`) beside a mapped one (`Goth.`); hydrius = a Greek-only `<foreign>` etym (the derivation source) |
