---
title: "The layers learn to join"
date: 2026-08-12 15:00:00 +0000
description: >-
  The Composition Phase: search becomes identity-aware about places,
  gains writing-system and geo-radius cuts, searches by cuneiform sign,
  and grows a deterministic filter-first mode — the held layers finally
  answering one question together.
---

The library has spent months growing layers — place identities with a
crosswalk across four gazetteers, a script axis on every lect id, sign
lists with their reading values, source-asserted find-coordinates. Each
had a desk; almost none had a search consumer. This phase is the join.

**Places are identities now, not spellings.** `search --place cigs:GIR`
matches every document whose provenance claim cites Girsu's identity — in
any of its historical spellings, upstream URL or namespaced mint — and
`--place Girsu` resolves the *name* through the held gazetteers and the
[nabu-places](https://arvicco.github.io/nabu-places) registry's
decisions, one crosswalk hop included, while still matching verbatim
name fields. Every page names the lane that answered:

```
note: place: "Girsu" → cigs:GIR = pleiades:912855 = cdli-provenience:88 = geonames:93976 (identity refs + name match)
```

The 586,765 documents that carry place refs — the place layer's biggest
asset — finally have their search consumer, and the place card renders
the same equivalences as an `=` line.

**Filter-first search is its own mode.** A common word under a selective
filter used to draw a corpus-wide sample and thin it — a different
near-empty page every run, honestly labeled but useless. That is now
recognized as a *different question*: `--scan` walks the term's matches
in corpus order intersected with the filters — deterministic, never
sampled. `search lugal --place Girsu --scan` fills its page identically
every time, in two-thirds of a second, from the ~19,000 Girsu tablets.

**Three more cuts joined the filter set.** `--script TAG` searches by
writing system — the Ogham stones (`--script ogam`), Greek-alphabet
Gaulish (`--script grek`), or artifacts whose original script differs
from their held transliteration. `--sign 𒊬` is the inverse of the sign
desk: one cuneiform sign expands into an OR over its OSL reading values,
each hit bracketing the value it matched. And `--within LAT,LON,KM`
walks the documents found inside a radius — the runestones within 30 km
of Uppsala, off their source-asserted coordinates.

All of it composes: script × place × date × license × lect in one query,
through the one shared join every search mode reads. The [Tools]({{
'/tools/' | relative_url }}) page documents the new modes; the
[Examples]({{ '/examples/' | relative_url }}) page walks them live.
