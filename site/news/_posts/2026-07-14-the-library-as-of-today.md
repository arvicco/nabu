---
title: "The library as of today"
date: 2026-07-14 12:00:00 +0000
description: >-
  An inaugural stock-taking: 170,684 documents, 4.27 million passages,
  fifteen gold-lemma languages, and the tool families that read them.
---

This News section opens with a stock-taking. Nabu has been built in
nineteen development phases since 2026-06-20; from here, every release or
phase gate will add a dated entry — new sources, new capabilities, honest
numbers. What follows is the state of the library as of 2026-07-14.

**Holdings.** The catalog holds **170,684 documents / 4,267,213 passages**
from **25 synced sources** — the Perseus Greek and Latin canons, the
documentary papyri (DDbDP/HGV), the Latin inscriptions of EDH, 33 ORACC
cuneiform projects, the Sanskrit shelf, Coptic Scriptorium, the complete
Old English poetic corpus, and the Slavic witnesses from Old Church
Slavonic to early Slovene, among others. Three further sources (IE-CoR,
LIV, de Vaan's Latin etymological dictionary) are registered and await
their first synchronization. The reference shelf carries **450,092
dictionary entries** across twelve dictionaries, including Monier-Williams
and seven reconstruction shelves of proto-language entries; upstream gold
lemmatization contributes **2,852,069 lemma rows in 15 languages**. Every
text keeps its upstream license on record
([sources & licensing]({{ '/sources/' | relative_url }})).

**Reading tools.** Search runs by word, dictionary lemma, morphology
facet, proximity, or — for the damaged documentary corpora — fuzzy
trigram matching that tolerates lacunae. A chronological-geographical
axis dates and places 164,989 documents, so queries compose with
`--from/--to/--century/--place` and, on the epigraphic shelf, with genre,
province, and material facets (256,518 facet rows). Alignment renders one
citation across every witness of a registered work — fifteen for the New
Testament — and collates them into a compact apparatus. On the
comparativist side, `define`, `etym`, and `cognates` walk attested lemma
to reconstruction to cognate set over the reconstruction shelves and
Monier-Williams comparanda, with the three registered adapters queued to
add independent expert-curated witnesses. The corpus also reads itself:
`parallels` finds quotations and echoes (Matthew 4:4 finds Septuagint
Deuteronomy 8:3), `formulas` mines repeated phrases (Homer's ὣς ἔφαθ',
72 occurrences), and `links` reads back the persistent citation graph
these producers build. A [quickstart]({{ '/quickstart/' | relative_url }})
stands up a 693 MB starter shelf; a read-only MCP server exposes ten tools
so AI assistants can search and cite the same library. The full inventory
is on [the Library]({{ '/library/' | relative_url }}) and
[Tools]({{ '/tools/' | relative_url }}) pages.

**Honesty notes.** All figures above are read from the live catalog and
dated 2026-07-14; they will drift as the owner fires pending
synchronizations, and the next entry will carry the new numbers. There is
no packaged release yet — a first tagged release is under consideration —
and command-line flags may still change. The test suite stands at 2,471
tests / 32,142 assertions, green.
