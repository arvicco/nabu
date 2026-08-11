---
title: "The library proves it can die — then publishes its layers"
date: 2026-08-11 21:00:00 +0000
description: >-
  Three phases in one arc: the derivability law makes everything
  permanent live in three plain-file folders and proves it by an
  actual restore drill; the character desks grow a graded-reading lane
  and a didactic overlay from the scribal school next door; and
  nabu-data ships eight new datasets — the library's stage, dating,
  place, and sign layers, published whole, with 95,054 cuneiform
  tablets upgraded to single-year dating on the way out.
---

The last few days rebuilt the library's foundations, then published
what stands on them. Three phases, one arc.

## Everything permanent fits in three folders — proven, not assumed

The **derivability law** is now an enforced architectural invariant,
not a habit: everything permanent lives in three plain-file folders —
`canonical/` (the texts, the universal asset), `config/` (the project's
definition), and `local/` (this instance: the owner's rulings, shelves,
notes, and the operational ledger, newly elevated to a first-class
folder) — and **every database is derived from them**. Guard tests now
classify every table in every database by that law, census every code
path that writes a permanent file, and refuse new ones that arrive
undeclared. The stronger claim has its own drill: restore ONLY the
three folders to a bare directory, re-derive everything, and compare
counts against the live library. Backups stopped being a hope.

## The character desks learn to teach

A capability survey from [Edubba](https://arvicco.github.io/nabu-edubba)
— the scribal-school sibling — came back as a shipped feature wave the
same day. The Han character card grew a **graded-reading lane**: give
it the characters a student knows, and it finds real corpus passages
readable with at most N unfamiliar characters, cleanest first, naming
each passage's strangers — backed by a 16-million-row rarest-character
index, so the answer is instant at any charset size. Cards gained
per-document **vocabulary profiles** with coverage percentages, JSON
output for machine consumers, and a **didactic panel**: where Edubba's
course material covers a sign, the library's card now says so, chapter
and keyword, with uncertain etymologies flagged *in front of* the
gloss. The school teaches the scripts; the library carries the texts;
the seam between them is now data.

## The layers go public — eight new datasets

[nabu-data](https://github.com/arvicco/nabu-data) grew from thirteen
datasets to **twenty-one**, and the new eight are a different kind of
thing: not single-language tables but the library's own **compiled
layers across the whole catalog**, published under the new `mul/`
(multiple-languages) namespace:

- **`mul/lect-assignments`** — 482,287 per-document historical-stage
  assignments (Old vs Neo-Babylonian, Vedic vs Classical Sanskrit…),
  each with its basis in-band. No other project publishes stage
  stratification at corpus scale.
- **`mul/place-refs`** — 969,929 document→place claims over 7,309
  places, every historical ref spelling folded to clean gazetteer
  identifiers, shipped as four shards.
- **`mul/places-lpf`** — the same places as a **Linked Places Format**
  FeatureCollection plus the LP-TSV upload table the World Historical
  Gazetteer accepts: attested spellings cited to their corpora,
  coordinates, aggregated date spans, cross-gazetteer links.
- **`mul/document-dates`** — 703,372 normalized year spans with the
  verbatim upstream dating string riding every row.
- **`mul/char-postings`** — the Han character × corpus doc-frequency
  census behind the graded-reading lane, 38,397 rows.
- **`sux/sign-table`** — compiled cuneiform sign cards: OSL identity,
  print-list concordances, CDLI readings, and *real attestation
  counts* — how many held documents actually use each sign.
- **`egy/unikemet-signs`** — the Egyptian hieroglyph spine: 5,067
  codepoints with Gardiner-style codes and the JSesh/Hieroglyphica/
  IFAO concordances every Egyptological tool joins on.

Every dataset slices by license class row-by-row (non-commercial and
ODbL inputs excluded and censused, never silently dropped), and
share-alike datasets now carry their own LICENSE file in-directory.

And one upgrade shipped on the way out: cuneiform tablets dated by
regnal year ("Šulgi year 44") now resolve through a ruled king table —
middle chronology, stated in-band — so **95,054 CDLI documents moved
from ±100–300-year period bands to single-year dating**, 82,133 of
them to an exact conventional year. Rulers whose absolute chronology
is genuinely uncertain stay period-banded on purpose: the table's
header names them, and false precision is refused.

The v1.1.0 release of nabu-data — the first carrying the cantigas —
cuts alongside this wave.
