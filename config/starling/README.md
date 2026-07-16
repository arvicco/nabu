# StarLing → Unicode conversion tables (P22-0 + P23-0)

`unipro.lst` and `chslav.lst` are **verbatim** StarLing-to-Unicode
conversion tables shipped with the StarLing database program, vendored
here because `Nabu::StarlingText` (the `starling-dbf` parser family's
text decoder) is table-driven and must never guess byte meanings —
every mapping the decoder applies is one the StarLing authors
published themselves.

- **Retrieved:** 2026-07-15, from the official Linux package
  <https://starlingdb.org/download/starling_3.9.0-20251128_amd64.deb>
  (StarLing 3.9.0, build 2025-11-28), paths
  `/opt/starling/share/starling/convert/{unipro,chslav}.lst` —
  byte-identical copies, sha256
  `749a8103c3665c97593b1cd62ca8d80287d67ffc7d3139b8b0e507127d39993d`
  (`unipro.lst`) and
  `b92429bb63fc88e7921e20326c42868591d3b4598fbe94e048546f1dbd04e8a8`
  (`chslav.lst`).
- **Why these tables:** the package's own `config.str` wires
  `unipro.lst` as THE Unicode conversion
  (`WINFONT=.../convert/unipro.lst, FreeSerif`); the file's header
  calls it "intended to be fully Unicode compatible". `chslav.lst`
  (P23-0) is the same `config.str`'s `[Chslav font]` conversion
  (`WINFONT=.../convert/chslav.lst, Monomachus` — "Izhitza UniCode"
  per the package's `runconfig.htm`): 90 Unicode-targeted mappings for
  the `\x01`-shifted `\x86/\x87/\x88` doublebyte range the vasmer
  base's Old Cyrillic citations are typed in. That range is absent
  from `unipro.lst` and disjoint from its `\x83/\x85` set-1 keys, so
  merging the tries changes no pokorny/piet decode (measured: chslav
  resolves 19,229 of vasmer's 19,257 otherwise-unmapped pair
  occurrences; the residual 28 are upstream strays, decoded U+FFFD).
  The sibling tables (`standard.lst`, `oldgreek.lst`) target legacy
  private-use fonts, not Unicode.
- **Format** (documented in the package's `help/encoding.htm`): one
  mapping per line, `<StarLing byte sequence> = <target>`; `U+XXXX`
  targets are Unicode code points, non-`U+` targets are aliases spelled
  in StarLing bytes; `*` comments a line out. Multi-line duplicates
  exist for round-tripping — the FIRST line per left side is the
  forward (decoding) mapping. `Nabu::StarlingText` loads the tables in
  the order above; first mapping per byte sequence wins (upstream's own
  forward rule), and the two tables' key spaces are disjoint anyway.
- **Copyright:** the tables are part of the STARLING software
  (S. Starostin, G. Bronnikov, Ph. Krylov), downloadable without charge
  from starlingdb.org. They are redistributed here unmodified, solely so
  the etymological data covered by G. Starostin's 2026-07-15
  any-use-with-acknowledgment grant can actually be decoded; see
  `docs/02-sources.md` (starling row) for the grant and the required
  per-base compiler credits.
