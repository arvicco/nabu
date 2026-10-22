---
title: "Three windows since v1.7.0 — the library learns to answer"
date: 2026-10-22 12:00:00 +0000
description: >-
  The weeks after the release, in three movements: the entity layer
  became readable, eighteen new sources landed in one content wave —
  from the Rigveda's gold morphology to the Anyang oracle bones — and
  a set of reading instruments opened translations, word senses, six
  more morphology tagsets and the printed sign lists to search.
---

The release cut on 20 October was an engine milestone; the weeks
around it have been about what the engine can now say. Three windows,
three movements — and a library standing at
**{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources (as of
{{ site.data.census.as_of }}).

**First, the entity layer became readable.** The person and place
names that parsers had been quietly indexing (318,542 name–passage
pairs) got their own desk: `nabu entity` looks a name up across every
tradition at millisecond speed, `show --entities` reads a passage's
marked names back, and dictionary cards climb their own etymon
chains. Beside it, the dating season continued — a regnal table for
the Pallava and Chola inscriptions added 451 dated documents, each
accession year citing its published chronology — and the Baltic
littoral opened: the earliest Latvian prints (1585–1685), the Old
Latvian sermon corpus, Basque's first books staged by era, and an
86,067-entry Classical Armenian lexicon. South Indian epigraphy
widened by 18,495 documents under a repository-wide grant read
verbatim from the maintainers.

**Then the content wave.** Eighteen new sources and two canon widens
in a single window: the VedaWeb Rigveda with gold morphology on every
word; the Liège LASLA corpus of gold-lemmatized classical Latin
(Plautus to Juvenal); Lotsawa House's Tibetan Buddhist translations
in nine languages; the Anyang oracle-bone corpus — the earliest
Chinese stratum, 10,077 rubbings; the Shuowen Jiezi wired into the
character card; Sefaria's medieval library (the Rishonim, Mishneh
Torah, the Zohar) staged as Medieval Hebrew; ten historical editions
of the Chinese Buddhist canon; seven South-Asian dictionary shelves;
five more Wikisource language cones from Telugu to Breton; and the
Caucasus instruments — Old Georgian and Middle Armenian treebanks on
the registry's new anchors.

**And now the reading instruments.** This week's window opened four
doors into what those waves had already fetched. Translations that
ride inside annotations — the cuneiform corpus's translation lines,
Coptic Scriptorium, the Hittite glossed corpus's German and eleven
more lanes, about 302,000 passages — answer full-text search and
point back at their originals. Six more morphology tagsets decode
through the search façade (the Diorisis Greek analyses, the ETCBC
Hebrew of the Bible and the Scrolls, OpenScriptures Hebrew, two
medieval German corpora, Old Norse manuscripts), with upstream word
glosses joining the search beside them. The Digital Corpus of
Sanskrit's 531,573 sense-tagged tokens became the library's first
word-sense search. And the cuneiform character card now carries the
printed sign-list concordances — Labat, ATU, MZL and kin — 17,090
rows over 2,555 signs, precompiled.

Underneath, the honesty machinery kept pace: fetches of the
scan-indexed Wikisource family are now atomic with their cone
membership persisted (a mass-deletion breaker caught the gap, working
as designed), the Sefaria kind fold reads the deep category path so
commentary classes as commentary, and the test suite — 14,471 tests —
runs in ninety seconds where it took seven minutes.
