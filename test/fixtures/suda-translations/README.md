# suda-translations fixtures (Suda On Line, CC BY-NC-SA)

`solEntries.zip` — a TRIMMED-REAL re-pack (2026-11-02) of the Suda On
Line entry export `solEntries.zip` (91,070,805 bytes, sha256
`dbd63ed79f751f80651d32893146fe9ac739c97977e55795b9dac1cbfd2f24aa`,
members dated 2025-07-24) that the SOL's maintainer exported from the
live database and supplied for this library by email, 2026-11-02. Every
member below is byte-verbatim from that export, except the three letter
index pages, which keep their real header and footer lines and only
the `<li>` rows of the entries kept here. Re-pack recipe: copy the
members out of the export, trim the index pages, then
`zip -X -r solEntries.zip sol-entries`.

License: the SOL's own statement (home page and rights page, read
2026-11-02): "All our entries, including translations and annotations,
are covered by a Creative Commons 'Attribution-NonCommerical-ShareAlike
License'" (CC BY-NC-SA 1.0) — redistribution for non-commercial use
with credit to the SOL and the translators, so the sample sits in the
public tree like the other nc fixtures (gretil, dprr).

## Delivery grains (census of the full export, 2026-11-02)

The export is the SOL's search CGI saved once per Adler number:
`sol-entries/<letter>/<n>` is the HTML answer to the query
"<letter>,<n> in Adler number", and `sol-entries/<letter>.html` lists
the letter's entries. 31,371 files:

| grain | count | taken? |
|---|---|---|
| entry page (`<letter>/<n>`, one record found) | 31,341 | YES — one passage each, grouped into one document per Adler letter (27 letters) |
| letter index page (`<letter>.html`) | 27 | no — a link list, skipped by rule (counted) |
| "no matches" page (`<letter>/<n>` answering "the translation database has no matches") | 2 (`epsilon/4079`, `tau/1316`) | no — skipped by rule inside its letter document (named in the document metadata) |
| mis-keyed query page (`omicrioniota/8`, a misspelled letter directory; the CGI answered 27 records and showed `alpha 8`) | 1 | no — the directory is not an Adler letter, skipped by rule (counted) |

The 27 index pages link 31,342 entry files: the 31,341 entries plus
`epsilon/4079`. `tau/1316` and the misspelled directory sit outside
every index. All 31,341 entries carry vetting status "high".

## What is here

- `alpha/1` — two headwords, a gloss-less addendum, Greek inline in the
  notes (`<g>`), an associated web address, eight vetting rows, and the
  Greek Original placeholder `#` (6 entries in the export have it).
- `alpha/2`, `epsilon/1`, `nu/28` — ordinary entries.
- `alpha/106` — the singular "Keyword:" label (1,333 entries use it).
- `nu/27` — Naxos: Greek inline in the translation, notes, a reference,
  ten keywords, six vetting rows.
- `epsilon/4079` — the rejected "no matches" grain.
- `omicrioniota/8` — the rejected mis-keyed query grain.
- `alpha.html`, `epsilon.html`, `nu.html` — the rejected index grain.

## Keying (for the alignment to the Greek)

Entries are keyed by Adler number in SOL's spelling (`nu,27`). The held
First1K Greek Suda (`urn:cts:greekLit:tlg9010.tlg001.1st1K-grc1`) cites
`<book>.<chapter>.<section>` — `3.Ν.27` for the same entry; its chapter
labels mix Latin and Greek capitals (`1.A`, `1.B`, `2.E`, `2.Aι`,
`3.Ο255`) and 10 letters are absent there. The adapter's
`FIRST1K_CHAPTERS` table is the observed mapping; each passage carries
the resulting candidate reference, which the alignment work must still
verify (First1K splits some sections, e.g. `1a`/`1b`).
