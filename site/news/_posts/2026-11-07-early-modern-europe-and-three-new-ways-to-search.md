---
title: "Early-modern Europe, the Latin liturgy, and three new ways to search"
date: 2026-11-07 00:00:00 +0000
description: >-
  Four November days: the early-modern European print wave from the
  Stationers' Register to the mazarinades, six liturgy and chant
  sources with a chant-identity layer, East and Inner Asia breadth
  from the Tangut rhyme dictionary to the Qing Pentaglot — and three
  new search surfaces that open the library's annotation layers,
  scholars' token glosses, and upstream morphology to direct query.
---

Four November days of development bring the library to **2,854,118
documents / 128,499,000 passages across 327 live sources** (census
7 November 2026), with the dictionary layer at 5,281,593 entries
across 956 shelves.

**Early-modern Europe arrives as a wave.** The London book trade's
own ledger — the Stationers' Register, 1557–1640 — enters as 10,453
dated entries, beside the Statutes of the Realm (661 acts of the
English parliament to 1713), the Evans-TCP and ECCO-TCP transcriptions
of early American and eighteenth-century English printing, 3,067
mazarinades (the pamphlet war of the Fronde, 1648–1653), the Socinian
correspondence network (1,869 letters, each queryable from both its
writing and its receiving place), the 16th-century Slovene Protestant
prints of Korpus 16, and Noscemus's neo-Latin scientific corpus
(1,038 works / 555,797 passages). With them lands LEME — the Lexicons
of Early Modern English — as 311 period dictionaries totalling
943,211 entries: the words of the age, defined by the age.

**The Latin liturgy, sung.** Six liturgy and chant sources went live
in one wave: the Cantus Database (449,132 chants, exact on the
database's own advertised total), GregoBase's engraved Gregorian
scores, the Divinum Officium Tridentine office, the Greek Orthodox
liturgical corpus, Church Slavonic service texts from Ponomar, and
the Analecta Hymnica. A new chant-identity layer ties the same chant
across witnesses — 71,032 edges at first build.

**East and Inner Asia, broader.** Seven sources in one window:
Armenian epigraphy, the Jesuit mission press's romanized Japanese
(the Kirishitan prints), the Tangut rhyme dictionary of the Digital
Wenhai, the Qing Pentaglot with its five-script rows, and the
Việt–Tai lexica with their Han-script layers. The runic shelf gained
its catalogue layer too: dating, findspots and inscription sigla
harvested from RuneS-DB's own records, with 370 translation siblings.

**Three new ways to search.** The library's annotation layers —
standardized and regularized spellings, modern readings, margin
notes, editors' and translators' notes — are now a search surface of
their own: 2,336,455 passages across 31 sources answer
`search --annotations` (built 7 November 2026), so a modern-spelling
query reaches the period spelling that carries it, and a margin note
finds its page. Scholars' token glosses became content too:
`search --gloss-lines` queries the glossing line of 320,055 passages
across five annotated corpora — English over the Hebrew Bible and the
Achemenet Akkadian, German over the Egyptian and Hittite corpora —
and returns the original-language passage, so "king" finds מֶלֶךְ and
König finds *nswt*. And upstream morphology tags across five more
tagsets now decode to readable grammatical features at display time,
with a word-grain gloss filter (`--gloss`) joining the lemma search.
The works taxonomy grew five ruled heads — theology with its
treatise, apologetics and polemic subdivisions, oratory, catechesis,
paratext, hagiography — toward a 28-head classification of what each
work *is*.

**The demo keeps earning trust.** The MCP demo server now ships with
a 36-task evaluation pack exercising all 14 tools against the live
image — a machine-checkable answer to "does it actually work" that
runs before every release. Installing it is one click from the
project page: VS Code and Cursor install badges, a Docker one-liner,
and free-tier deploy buttons, with the image version now locked to
the library's own release line.

As always, the numbers above are the generated census of the live
catalog, not hand-kept claims.
