---
title: "v1.9.0 — the settled name, a rebuilt library, and two weeks of shelves"
date: 2026-11-24 00:00:00 +0000
description: >-
  Two weeks of development in one release: the public server takes its
  settled name, nabu-ancient-corpora; the Greek canon, the Hebrew wave,
  the New Testament's witnesses and apparatus, Syriac, Estonian and a
  Pacific shelf arrive; and the whole library is rebuilt from its
  sources onto a leaner store, with a verification pass that proves it.
---

Version 1.9.0 gathers the two weeks since v1.8.0 — the library now
stands at **{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources, every number on this
site regenerated from the live catalog (as of
{{ site.data.census.as_of }}).

**The settled public name.** The public MCP server and its demo image
are now **nabu-ancient-corpora** everywhere: the registry entry, the
container image, the install commands and the deploy buttons. Existing
installs keep working; new ones should use the new image name, and
directories that read the official registry pick the change up from
this release.

**What arrived on the shelves.** Ancient Greek roughly quadrupled with
the freed TLG canon, and philosophy became a first-class category.
Four languages arrived from their first printed books — Old Prussian,
Old Lithuanian, Old Albanian and Old Frisian. The Hebrew shelves grew
by the Cairo Geniza's documentary transcriptions, a rabbinic library
with the first responsa shelf, the Samaritan Pentateuch, and the
pre-modern layer of Project Ben-Yehuda: six thousand works of piyyut
and Andalusian poetry. Around the Greek New Testament the library
already read, three word-level editions now supply the critical
apparatus, and 189 manuscript transcriptions — from the second-century
papyri to the great uncials — supply the witnesses, all aligned verse
by verse. Syriac gained a lexical database, a New Testament and
handwriting ground truths; Estonian gained a corpus of early
twentieth-century books; the Pacific shelf opened with the
Māori-language newspapers of 1842–1932 and the rongorongo corpus of
Easter Island, the first undeciphered script in the catalog. Josephus
arrived in his medieval Latin dress, with the Roman Republic's
prosopography beside him.

**A library rebuilt, and proven.** For this release the whole library
was regenerated from its fetched sources — the standing guarantee
that everything searchable is derivable — onto a leaner store. Search
text that merely repeats the passage is no longer stored twice, the
catalog uses a larger page, and content hashes are kept in binary;
together the database files shrank by about a fifth while the library
grew. The rebuild now announces a priced plan before it touches
anything, records the time of every stage, and is followed by a
ten-check verification — counts against a census taken beforehand,
search membership, storage classes, file integrity — so that "the
rebuild worked" is a measured statement.

**Incremental means what it says.** A document that stops parsing
after an upstream change is now withdrawn on an ordinary sync exactly
as a full rebuild would withdraw it, so the quick path and the full
path can no longer drift apart. A parser regression that would take
many documents down at once trips a loud breaker instead, and waits
for the operator.

**Search and reuse.** Search stays fast as the library grows: index
updates are priced from measured runs and refuse, with numbers, work
that would silently burn hours. Text-reuse discovery gained a batch
engine — the tool that finds a school exercise quoting the Odyssey can
now mine a whole corpus. Over MCP, verse alignment summarizes absent
witnesses instead of listing them one by one.

**The crawl rail.** Long-horizon sources — national-library
digitizations served a few requests at a time — now run as paced
crawls with resumable ledgers, and a trickle runner that harvests
politely for weeks without holding anything else up.

**Under the hood.** The codebase was restructured in one sitting —
modules moved to their own homes, the source registry split into one
small file per source — with proofs that every public surface
survived unchanged, and a one-command gate runs the whole check
sequence.

Install or update the demo:

```
docker run -i --rm ghcr.io/arvicco/nabu-ancient-corpora:1.9.0
```

Full release notes are on the
[GitHub release page](https://github.com/arvicco/nabu/releases/tag/v1.9.0).
