---
title: Kinds
permalink: /kinds/
description: >-
  The kind axis of the Nabu library: what kind of document is this —
  cross-corpus classification over ruled classes, the honesty buckets,
  and the live class census.
---

As of **{{ site.data.kinds.as_of }}** — a live census:
**{{ site.data.census.kind_documents_display }} documents carry a kind
classification** ({{ site.data.census.kind_coverage_pct }}% of the
kind-eligible library), across
{{ site.data.census.kind_class_count }} class families. Kind is the
library's fourth dimension, after language, time and place: what kind
of document is this — an epitaph, a receipt, a hymn, a school
exercise? Each source ships its own genre vocabulary (EpiDoc
inscription types, cuneiform catalogue genres, manuscript headings);
those upstream labels **fold onto one ruled cross-corpus class list**
(`config/kind_classes.yml`, with crosswalks to EAGLE, LCGFT and Getty
AAT where those vocabularies recognize the class). Classification is
**multi-label** — a funerary poem is both — and the upstream claim is
preserved verbatim beside the fold, so the ruled class never erases
what the source actually said.

## The classes

| Class | Documents | Sources |
|---|---:|---:|
{% for class in site.data.kinds.classes -%}
| {{ class.head }} | {{ class.documents_display }} | {{ class.sources }} |
{% endfor %}

Heads match their whole family in queries (`funerary` includes
`funerary/epitaph`); the sub-grain vocabulary under each head is
extensible without re-ruling the class list.

## What stays honest

Two buckets are counted beside — never inside — the classes:
**unknown** ({{ site.data.kinds.unknown_documents_display }} documents)
is upstream's own "cannot determine", a claim the library preserves
rather than overwrites; **unmapped**
({{ site.data.kinds.unmapped_documents_display }} documents) holds
values still awaiting a fold rule — a visible curation worklist, not a
silent discard. Sources carrying nothing genre-shaped at all
({{ site.data.kinds.unclassified_sources }} sources,
{{ site.data.kinds.unclassified_documents_display }} documents) speak
through their recorded postures, not through silence.

## Try it

```
nabu kind census                  # the class board above, live
nabu kind census --unmapped       # raw values awaiting a fold rule
nabu search --kind funerary       # a head matches its whole family
nabu search --kind letter/private # head/sub narrows the grain
nabu search lugal --kind administrative --scan   # composes with every filter
```

The kind line also appears on every document card (`nabu show`), with
the upstream label quoted verbatim beside the ruled class.
