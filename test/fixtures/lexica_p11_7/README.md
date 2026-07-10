# Lexica P11-7 fixture (real trimmed LSJ α slice)

Fixture for P11-7 fix 5, kept in its own tree so the main `test/fixtures/lexica/`
adapter-discover assertions (an exact file set) stay untouched.

Retrieved **2026-07-10** from the on-disk canonical `PerseusDL/lexica`. CC BY-SA
4.0 (credit Perseus).

## File

- `CTS_XML_TEI/perseus/pdllex/grc/lsj/grc.lsj.perseus-eng1.xml` — the α (alpha)
  letter file, TRIMMED to two REAL entries wrapped in the same TEI envelope as
  the committed `eng13` fixture:
  - `n4` (`a(\`) — a normal entry with well-formed dotted CTS citations.
  - `n6454` (`a)na/dikos`) — carries a work-level `<bibl>` whose `@n` is a CTS
    urn with a TRAILING COLON: `urn:cts:greekLit:tlg0027.tlg0088:`. Its empty
    citation suffix used to build an invalid empty-string `DictionaryCitation`
    → `ValidationError` → `ParseError`, quarantining the WHOLE α file (18950
    entries) — and θ/`eng9` (1948) for the same reason.

**Census correction:** the P11-7 brief called `eng1`/`eng9` "alternate
single-file editions to exclude by rule". Disk evidence disproves this — every
`grc.lsj.perseus-eng1..27.xml` maps to a distinct Greek letter (`eng1` = α,
`eng9` = θ). Excluding them would delete ~20900 entries including the entire α
section. The real fix is `cite_parts` minting a work-level citation
(`citation: nil`) for an empty suffix, so both files parse whole.
