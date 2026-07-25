# Hypotactic — fixture

Source: David Chamberlain, **Hypotactic** — metrical scansions of Greek and
Latin verse (hypotactic.com). GREEK lane only for v1.
Mirror repository (fetched): https://github.com/Urdatorn/hypotactic (`tsv/`).

License: **CC BY 4.0** (the mirror repository), WITH Chamberlain's own
statement quoted verbatim in its README: "you can use it as you wish, but if
you make significant or extensive use of it in published work you should
reference me (David Chamberlain) and this site (hypotactic.com)." → house class
`attribution`; the reference expectation is honored on every minted meter edge
(the `detail` field carries "Hypotactic (D. Chamberlain, hypotactic.com)").

Retrieved: 2026-07-24 (github.com/Urdatorn/hypotactic, `tsv/HHAphrodite.tsv`).

## What this is

`tsv/HHAphrodite.tsv` is the **verbatim, whole** per-work TSV for the Homeric
Hymn to Aphrodite (Homeric Hymn 5) — 293 lines, byte-for-byte as the mirror
ships it. Four TAB columns per line, no header:

1. the Greek line text (verbatim)
2. the scansion pattern (`-u u -uu -u u--- uu---`)
3. the meter name (`dactylic hexameter`; a handful of lines read `lyric`)
4. caesura labels, comma-joined (`feminine penthemimeral, hepthemimeral`) —
   **may be empty** (line 9, a `lyric` line, carries no caesura).

There is NO citation column: the file NAME carries the work and line ORDER is
the line number. The producer nonetheless resolves by TEXT, not order (see
`lib/nabu/hypotactic_meter.rb`).

`tsv/iliad1.tsv` (added P45-5, trimmed 2026-07-25 from the same 2026-07-24
mirror clone) is TEN REAL rows of the mirror's Iliad book-1 TSV: upstream
rows 12–16 and 371–375 (= Il. 1.12–16 and 1.371–375). Kept because Homer
repeats whole formulaic lines VERBATIM — rows 372–375 repeat rows 13–16
byte-for-byte (modulo final punctuation) — the real-bytes case for the
producer's one-row-per-passage dedup guard.

## Refresh

A fresh clone of the mirror re-fetches `tsv/HHAphrodite.tsv` whole; drop it in
place. The LATIN lane on hypotactic.com is JavaScript-blocked and is NOT
covered here (Pedecerto, P44-7, covers Latin meter).
