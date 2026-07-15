# StarLing → Unicode conversion table (P22-0)

`unipro.lst` is the **verbatim** StarLing-to-Unicode conversion table
shipped with the StarLing database program, vendored here because
`Nabu::StarlingText` (the `starling-dbf` parser family's text decoder)
is table-driven and must never guess byte meanings — every mapping the
decoder applies is one the StarLing authors published themselves.

- **Retrieved:** 2026-07-15, from the official Linux package
  <https://starlingdb.org/download/starling_3.9.0-20251128_amd64.deb>
  (StarLing 3.9.0, build 2025-11-28), path
  `/opt/starling/share/starling/convert/unipro.lst` — byte-identical
  copy, sha256
  `749a8103c3665c97593b1cd62ca8d80287d67ffc7d3139b8b0e507127d39993d`.
- **Why this table:** the package's own `config.str` wires it as THE
  Unicode conversion (`WINFONT=.../convert/unipro.lst, FreeSerif`); the
  file's header calls it "intended to be fully Unicode compatible". The
  sibling tables (`standard.lst`, `oldgreek.lst`) target legacy
  private-use fonts, not Unicode.
- **Format** (documented in the package's `help/encoding.htm`): one
  mapping per line, `<StarLing byte sequence> = <target>`; `U+XXXX`
  targets are Unicode code points, non-`U+` targets are aliases spelled
  in StarLing bytes; `*` comments a line out. Multi-line duplicates
  exist for round-tripping — the FIRST line per left side is the
  forward (decoding) mapping.
- **Copyright:** the table is part of the STARLING software
  (S. Starostin, G. Bronnikov, Ph. Krylov), downloadable without charge
  from starlingdb.org. It is redistributed here unmodified, solely so
  the etymological data covered by G. Starostin's 2026-07-15
  any-use-with-acknowledgment grant can actually be decoded; see
  `docs/02-sources.md` (starling row) for the grant and the required
  per-base compiler credits.
