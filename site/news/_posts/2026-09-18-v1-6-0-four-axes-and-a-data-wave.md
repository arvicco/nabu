---
title: "v1.6.0 — four axes, and a public data wave"
date: 2026-09-18 07:00:00 +0000
description: >-
  The release that completes the library's fourth document axis and
  sends the layers out into the world: classification across two
  million documents, the unified Layers page, a clean health board,
  and the largest nabu-data publication wave since the repository
  opened.
---

Version 1.6.0 closes the classification arc that began with a survey
of twenty-one prior classification schemes and ended, three phases
later, with a working fourth axis. Beside *when*, *where* and *in
what language variety*, every document in the library can now answer
**what kind of text it is** — across
**{{ site.data.census.kind_documents_display }} classified documents**
({{ site.data.census.kind_coverage_pct }}% of the kind-eligible
library, as of {{ site.data.census.as_of }}),
{{ site.data.census.kind_class_count }} class families, every family
attested. The tree is optionally deep — `literary` holds its poetry,
narrative, drama and their siblings; any prefix matches its whole
family — and every fold preserves the upstream label verbatim beside
it. The three older layers now share one
[**Layers**]({{ '/layers/' | relative_url }}) page: one doctrine
(extracted, never guessed; honesty buckets counted, never hidden),
three sections, filters that stack in one query.

The release also ships the machinery a living library needs when an
*upstream* cleans house: when PerseusDL deliberately retired
ninety-six superseded Cicero editions, the library's withdrawal alarm
said so — loudly, correctly, and forever. A reviewed upstream
curation event can now be **accepted**: the alarm quiets to a dated
note and re-arms the moment shedding grows past the accepted level.
The health board is fully green for the first time in a week, with
nothing swept under a rug to get there.

And the derived layers are going public. The
[nabu-data](https://github.com/arvicco/nabu-data) sister repository
is receiving its largest wave since it opened: the complete
**kind-classifications** table (the fourth axis, per-document, with
every upstream label in-band), the **cuneiform sense glosses**
sidecar (Wiktionary's Sumerian, Akkadian and Hittite lanes, under
their own share-alike license beside the CC-BY sign table), and
re-derivations of the standing catalog-wide datasets — lect
assignments, document dates, places — from a catalog two million
documents richer than their last cut. Each dataset carries its full
derivation provenance, as always: the exact producing code version,
the input identities, and a recipe that makes the build repeatable
end to end.
