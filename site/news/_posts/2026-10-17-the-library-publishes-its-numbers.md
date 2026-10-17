---
title: "The library publishes its numbers"
date: 2026-10-17 18:00:00 +0200
description: >-
  nabu-data v1.4.0: eight new public datasets — diachronic frequency
  tables for 32 ancient and premodern languages, a million-row
  etymological reflex table joined to the attested corpus, the
  cross-dictionary reference graph, and gold form→lemma tables for
  Old Irish, Biblical Hebrew, Old Norse and Ancient Greek — beside a
  library that crossed 2.38 million documents with the Duke papyri
  re-anchored, two new Buddhist canons, and the St Gall Priscian
  glosses on the Celtic desk.
---

The library has always derived more than it shows: frequency
censuses behind the reading tools, stage assignments behind the
search filters, reference graphs behind the dictionary cards. This
week that derived layer became the story —
[nabu-data](https://github.com/arvicco/nabu-data) v1.4.0 publishes
eight new datasets, the project's largest release.

**Frequency dictionaries for the ancient world.** The headline set,
`mul/lemma-frequencies`, publishes 513,102 rows of gold lemma
frequencies — for each lemma, language, century and corpus, how many
passages and documents attest it, from human-verified annotation
only, across 32 languages (as of 17 October 2026): Sanskrit,
Sumerian, Middle High German, Biblical Hebrew, Egyptian, Akkadian,
Greek, Old East Slavic, Classical Chinese, Old Norse, Coptic and
more. Frequency dictionaries exist for almost none of these
languages; *diachronic* ones existed for none. Beside it,
`mul/language-curve` publishes the attestation census itself —
documents and passages per language per century, the rise-and-fall
table of the whole library.

**Etymology joined to evidence.** `mul/reflex-chains` flattens the
held etymological estate — Wiktionary's reconstruction shelves,
StarLing, IE-CoR, WOLD — into 1,226,690 reconstruction→reflex rows,
and adds a column no etymological database publishes: 36,686
reflexes carry the attestation count of the gold corpus lemma their
folded form matches, so a Proto-Germanic etymon's Old Norse reflex
points at the actual Old Norse evidence. Its sibling,
`mul/dictionary-crossrefs`, publishes the 158,578-edge reference
graph between the held dictionaries, each edge anchored to stable
entry URNs and screened on both endpoints.

**Four form→lemma tables.** The Sanskrit precedent now has company:
Old Irish (`sga/form-lemma`, from *two* independent editions of the
same St Gall Priscian glosses, with an inter-annotator census in
the bargain — 15,480 aligned token pairs, 81% lemma agreement once
folded, every divergence published), Biblical Hebrew
(`hbo/form-lemma`, 111,654 rows from the Open Scriptures Hebrew
Bible with the Masoretic mark order carried byte-verbatim), Old
Norse (`non/form-lemma`, 310,842 rows from the Menota archive at
its three transcription levels), and Ancient Greek
(`grc/form-lemma`, 671,940 rows from GLAUx, labeled silver honestly
— a column keeps the hand-annotated share separable). The Egyptian
hieroglyph frequency list — to our knowledge still the only public
one — deepens to word grain, with damaged attestations counted
separately.

Every dataset carries its derivation recipe, upstream shas and a
published-slice digest; every license screen is censused in-band, so
an excluded corpus can never hide inside a published integer.

**The library under it kept growing.** The Duke Databank of
Documentary Papyri was re-anchored to upstream's own current
numbering — 64,096 documents including the DCLP literary papyri's
first landing — after a document-identity proof across the whole
corpus. Two more Buddhist canons joined CBETA's shelf: the Jiaxing
canon and the 漢譯南傳大藏經, the Yuan Heng Temple translation of the
Pali canon, 1.13 million passages with PTS concordance references
riding every line. The St Gall Priscian glosses (the manuscript of
AD 850–51) joined the Celtic desk as 13,395 glosses with 17,526
gold Old Irish tokens. KorBa 2.0 brought the Middle Korean corpus
to 2,091 documents, the first Old Nubian treebank arrived, and the
kotenseki crawl passed 37,000 of its 97,731 books. The library
stands, as of this writing, at 2.38 million documents and 113.9
million passages across 222 corpus sources on 29 desks.

As always: canonical means canonical — every text verbatim from its
source, every exclusion a written rule, every license the grantor's
own words.
