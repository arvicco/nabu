# Bosworth-Toller fixtures (P12-3 — dictionary shelf, third occupant)

Real upstream sample from the **official Bosworth-Toller data dump** at
LINDAT/CLARIAH-CZ (CLAUDE.md fixture rules; plan owner-approved 2026-07-10,
docs/backlog.md P12-3). Every kept row is **byte-verbatim** upstream data —
the extraction recipe re-emits parsed rows through the same CSV semantics the
adapter reads with and asserts each emitted row appears verbatim in the raw
bytes; only the record SET was trimmed.

- **Record:** https://lindat.mff.cuni.cz/repository/handle/11234/1-3532
  (hdl 11234/1-3532, "Bosworth-Toller's Anglo-Saxon Dictionary online",
  data dump version 0.1, deposited 2021; maintainer Ondřej Tichý, Charles
  University — the team behind bosworthtoller.com).
- **Retrieved:** 2026-07-10, from the DSpace bitstream content URL
  `https://lindat.mff.cuni.cz/repository/server/api/core/bitstreams/3010b742-b2c4-4152-870a-716ce1652e7c/content`
  (`bosworth_entries_export.csv`, 88,387,561 bytes, MD5
  `7c50c0a47ad2365fa0fddea18a54f11d`, Last-Modified 2021-04-26) — via
  **HTTP Range requests only** (~3.4 MB total: bytes 0–1449999 and
  45600000–46999999 plus small ordering probes), never the full file.
- **License (verbatim, DSpace item metadata):** `dc.rights = "Creative
  Commons - Attribution 4.0 International (CC BY 4.0)"`, `dc.rights.uri =
  http://creativecommons.org/licenses/by/4.0/`, label `PUB`.
- **Attribution:** Bosworth, Joseph. "An Anglo-Saxon Dictionary Online",
  ed. Thomas Northcote Toller, Christ Sean, and Ondřej Tichý. Faculty of
  Arts, Charles University, https://bosworthtoller.com/.

## Upstream format reality (what this fixture preserves)

- Header `"id";"headword";"body"`; every field quoted; `;` separator; quotes
  escaped by doubling (`""`); **record terminator CRLF**, while body-internal
  newlines are bare LF (bodies contain no CR) — a real CSV reader is
  mandatory, line-splitting shreds the multi-line bodies.
- `id` is the stable entry id resolving to `bosworthtoller.com/<id>`
  (spot-checked: id 940 æðele → HTTP 200). Ids have gaps (…3, 4, 6…) — never
  assume contiguity.
- `body` is the entry tagged in the project's own (non-TEI) XML: `<entry>` →
  `<form><orth>/<search>/<sort>`, `<gramGrp><pos>`, `<column name="body">`
  with `<grammar>`, `<def>`, `<equiv lang="eng|lat">`, nested
  `<sense num><snum>`, `<examples><ex><oe>/<trans>/<references>`, milestone
  pairs `<b-s/>…<b-e/>` / `<i-s/>…<i-e/>`, `<rune>`, `<br/>`. Dump v0.1
  caveat (deposit readme, verbatim): "Not all entries have been checked
  and/or tagged" — flat, sense-less bodies are the NORM (249 of the 270 rows
  here have no `<sense>`), so the linearizer treats tagging as optional.
- Double-encoded entities occur in body text: `&amp;#39;` (→ `'`),
  `&amp;mdash;` (→ `—`), `&amp;para;` (→ `¶`), beside legitimate bare
  `&amp;`.
- The upstream `<sort>` field is B-T's own alphabetization key — æðele →
  `aetþele`, þing → `tþing` — i.e. **B-T itself folds æ to "ae" and buckets
  ð/þ identically**, the primary evidence for the conventions §9 `ang` rule.

## This file — 270 entries, 497,144 bytes, ids 1..32052

| Stratum | What | Why |
|---|---|---|
| A-section head | the first 180 records of the file (ids 1..184) | the flagship multi-sense "A" letter entry (runes, ragged nested senses, `&amp;#39;`/`&amp;mdash;` double-encoding), accented á/ā words for the generic mark-strip, prefixed `a-` verbs, the "-a" suffix entry |
| æ-initial (45) | æfnan..ǽfnung, æfter (homograph pair 450/451), æfter-cweðan, ǽg-hwæðer, ǽg-ðer, æcer-, ælf- run, æsc/ÆSP/æspen, the æðel- block (930–947 incl. æðele, æðeling, Æðelbald) | the æ→ae fold, medial ð, capital Æ, proper names |
| þ-initial (44) | the "Þ" letter entry (31437) + its following run (þá, þaca …), þeáh-hwæðere, the þing run (31866–71) | the þ→th fold; Þ is a no-`<def>` entry; þeáh-hwæðere carries medial ð inside the þ section |
| special (~20) | homograph groups: ǽ ×3 (308/309/310), a-bútan ×2, ac ×2, ǽc ×2, ǽcen ×2, þærf ×2, týnan ×2 (31405/31406); the 8 shortest bodies; 5 no-`<sense>` bodies | loader upsert-by-(dictionary, entry_id) with colliding folded headwords; cross-reference stubs; untagged v0.1 tolerance |

NOTE the dump has **no ð-initial headwords** (B-T normalizes headwords to
þ-initial; ð appears medially — æfter-cweðan, ǽg-hwæðer, þeáh-hwæðere), so
the ð→th fold is exercised medially. This is upstream reality, not a trim
choice.

## Extraction recipe (one-shot, run 2026-07-10)

Ruby stdlib CSV over the two contiguous ranged slices:

```ruby
rows = CSV.parse(slice_bytes, col_sep: ";", quote_char: '"')  # align middle
                                    # slices to the first \r\n"<digits>";" and
                                    # drop the trailing partial record
# … select the strata above by id/headword, dedupe, sort by id …
CSV.generate(col_sep: ";", quote_char: '"', force_quotes: true,
             row_sep: "\r\n") { |c| c << %w[id headword body]; rows.each { |r| c << r } }
# then assert: every emitted data row is a byte-verbatim substring of the
# raw upstream slices (raw.include?(line.b))
```
