---
title: "v1.7.0 — the entity wave, the variant layers, and the replay engine"
date: 2026-10-20 16:00:00 +0000
description: >-
  A month of waves in one release: a cross-tradition person index,
  facets at three grains, the largest dating fill in the library's
  history, early-modern imprint towns on the map, two editorial
  apparatus layers, and a rebuilt replay engine that just carried the
  whole library through a full regeneration.
---

Version 1.7.0 gathers a month of waves — and was cut the day the whole
library finished replaying through its new engine:
**{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources, every number on this
site regenerated from that fresh catalog (as of
{{ site.data.census.as_of }}).

**The library now answers *who*.** A person index joins eight
authority traditions under one roof — the China Biographical Database
beside the Epigraphic Database Heidelberg's Roman names (93,643
persons), the Elephantine papyri's Aramaic archive (7,577), Japan's
Aozora and Kokubunken rosters, and Korea's dynastic records — each
person carrying its authority's own identifier, never a guessed
merge. Beside it, the facet layer grew two new grains: passages and
dictionary entries now carry structured facets exactly as documents
long have, so a Sanskrit verse's meter or a lexicon entry's register
is as queryable as a document's genre.

**The largest dating fill in the library's history.** The Open Korean
Historical Corpus — over a million documents of munjip collected
works — went from 41% to **95% dated** (1,139,409 of 1,198,779
documents, 20 October 2026) by joining each collection to its
author's life years through the Institute for the Translation of
Korean Classics' own bibliographic catalog. Around it, a season of
ruled tables: script-tradition bands date the Old Arabian corpus
(36,651 inscriptions), Vedic text strata date the Digital Corpus of
Sanskrit (15,883), archive and regnal tables drain the Achaemenid
shelf, sixty-seven sourced ruler rows extend the cuneiform regnal
table (each accession year citing its published chronology), CDLI's
"year after" marks are now read as the year-name tables themselves
number them, and a 248-era nengō table converts Japanese era imprints
to calendar years at parse time. Korean historical language stages
(Middle and Early Modern Korean) are live on the lect axis.

**Early-modern Europe is on the map.** The imprint lines of 60,325
EEBO-TCP prints — 1,676 spelling variants of what is overwhelmingly a
few dozen towns — now read to their bare town names, each matched to
GeoNames, Getty TGN and Wikidata identities in the places registry:
**93% of the corpus carries a place reference** (20 October 2026),
with uncertain imprints kept honestly uncertain. The cuneiform world
grew the same way: 272,588 CDLI provenience references through the
registry's new decision rows.

**The variant readings arrived.** Two editorial apparatus layers that
upstream encodes but no reader saw: the documentary papyri's
`<app>/<rdg>` variants (about 48,500 entries across 13,700 documents,
editor-attributed) and the Chinese Buddhist canon's stand-off
witness apparatus — **924,766 entries** resolved onto their exact
passages with zero unresolved anchors and the reading text proven
byte-identical. The Pāli canon joined with a Pali Text Society page
concordance whose keys match the held CBETA translation's own
anchors on 96.5% of pages — two independent encodings of the same
scholarly convention, agreeing in the catalog.

**And the engine underneath was rebuilt.** The loader now writes
multi-row batches (four to ten times faster at library scale), the
link-mining layers stamp their work so a four-hour mining pass is
paid once and carried thereafter, parsing fans out across worker
processes with byte-identical output, and the schema shed several
gigabytes of redundant indexes. A guard pack rides beside it: run
records that cannot claim success before the work is done,
status surfaces tested against freshly born databases, an
encoding belt at the adapter read seam, and commit hooks that keep
conflict markers and workflow residue out of the public tree. This
release's numbers are the engine's first full harvest: the entire
library — every source, every axis, every index — regenerated from
the permanent folders in one pass.

As always: extracted, never guessed; uncertainty is a recorded state,
not a missing value; and every figure above carries its date.
