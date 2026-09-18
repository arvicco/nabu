---
title: "The classification axis: what kind of document is this?"
date: 2026-09-14 06:00:00 +0000
description: >-
  The library gains its fourth axis. Beside when, where, and in what
  language variety, every document can now answer what KIND of text it
  is — funerary, administrative, letter, divination, historiography —
  one ruled vocabulary folded over every upstream jargon, with the
  original label preserved verbatim beside the fold.
---

A gravestone inscription is *sepulcralis* in one collection, *epitaph*
in another, *funerary* in a third, *Inscription funéraire* in a
fourth, and a *Leichenpredigt* — a printed funeral sermon — in a
fifth. Until this week, "show me all funerary texts across the
library" required knowing every collection's private jargon. Now it is
one query:

    nabu search "dis manibus" --kind funerary --lang la

The library's fourth document axis — **kind**, beside dates, places,
and lects — folds each source's own genre vocabulary onto a ruled
cross-corpus class list: {{ site.data.census.kind_class_count }}
plain families (funerary, dedicatory, administrative, legal, letter,
lexical, scripture, divination, poetry, historiography, …), each
carrying pointers to the international vocabularies that recognize it
(the EAGLE epigraphic types, Library of Congress genre/form terms,
Getty AAT). No external standard spans cuneiform tablets, papyri,
stone, scripture, and novels at once — the survey behind this axis
verified that — so the list is the library's own, and every upstream
label is preserved verbatim beside the fold.

**Classification is multi-label.** An ode to a ruler is *poetry* AND
*royal*; a cuneiform "Administrative Letter" is both of its words; a
verse epitaph carries *funerary/epitaph* and *poetry* together. And
it is two-grain: `--kind divination` finds the whole family,
`--kind divination/extispicy` narrows to the liver omens.

The numbers, from the live census
({{ site.data.census.as_of }}): **{{
site.data.census.kind_documents_display }} documents classified —
{{ site.data.census.kind_coverage_pct }}% of the library** — drawn
from upstream catalogue genres (cuneiform's CDLI and Oracc, the
Heidelberg and Rome epigraphic databases), the papyri's HGV text
types (*Quittung*, *Vertrag*, *Mumienetikett*), the sibu 四部
classes of the Chinese canon, Japan's NDC decimal codes, Sefaria's
category tree, and whole-collection declarations where a source IS
one thing — the Korean dynastic records, the Buddhist and biblical
canons. What no rule covers yet sits in an honest, counted
*unmapped* bucket; sources carrying nothing genre-shaped say so
through their postures. The full board lives on the new
[Kinds page]({{ '/kinds/' | relative_url }}), and `nabu kind census`
prints it in under a second.
