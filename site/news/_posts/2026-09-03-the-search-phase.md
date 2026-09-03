---
title: "The search phase: six dragons, a 51-gigabyte diet, and an attic"
date: 2026-09-03 11:00:00 +0000
description: >-
  One phase, all of it about finding things: exact Han-character
  search over the 23-million-pair CJK index, a full-text engine
  rebuilt to half its size with answers unchanged, a search view for
  everything the library ever withdrew — and the semantic-search
  machinery built end to end, awaiting its first overnight build.
---

The library's newest phase was spent entirely on **search** — four
lanes, each closing a different honest gap.

**Classical Chinese, Japanese and Korean now search exactly.** These
shelves — the Buddhist canons, the Chosŏn state records, the Japanese
library, some eighteen million passages — write without word
boundaries, which quietly degraded them to second-class citizens of a
word-based index. The fix is a dedicated **character-pair index**:
23,372,988 pair rows over fifteen sources, so a Han or kana query
matches exact character sequences with no guessed segmentation
anywhere. The six dragons of the *Yijing*'s first hexagram, asked as
`nabu search 六龍`, answer in two-thirds of a second from the *Book of
Han*'s music treatise and two Buddhist commentaries quoting 乘六龍以御天
— "riding the six dragons to drive across the sky" — three corpora,
one query, mid-rebuild.

**The full-text engine went on a diet.** The index had been storing a
private shadow copy of every passage it indexed — an artifact of the
engine's default design, 39 gigabytes of duplication the catalog
already held. Rebuilt contentless and compacted, the full-text store
fell from **87 GB to 36 GB** with search behavior byte-for-byte
unchanged. Fifty-one gigabytes returned to the shelf, nothing lost but
redundancy.

**The library grew an attic — and it's searchable.** This collection
never hard-deletes: when an upstream source withdraws a document or a
revision prunes a passage, the text is withdrawn, not erased. Now
`search --withdrawn` searches exactly that shadow collection, and
every hit says *why* it left the open shelves — upstream gone, or
revision-pruned — so a vanished reading can be found, cited, and
traced years later.

**And the meaning-search machinery is built.** The phase's largest
single piece is the semantic lane: `nabu embed` distills each passage
of the literary core (4.9 million passages across seventeen Greek,
Latin, biblical and treebank sources) into a numerical fingerprint of
what it says, and `search --similar` — on the command line and
through the MCP server — answers "where else does the library say
this?" with ranked, banded, honestly-labelled neighbors:
cross-edition witnesses, drifting quotations, paraphrases. The whole
pipeline runs on this machine; no text leaves the box. The first
store build is a scheduled overnight run — and the lane will get the
announcement it deserves, with live walk-throughs, once its vectors
actually exist. Nothing on this site is pasted from imagination.

The plain-language write-ups landed with the code:
[embed.md](https://github.com/arvicco/nabu/blob/main/docs/embed.md)
on the semantic lane, and
[lemma-enrichment.md](https://github.com/arvicco/nabu/blob/main/docs/lemma-enrichment.md)
on the silver-lemma campaigns whose tool stack was also folded into
one-command installs this phase. Meanwhile the
[Tools]({{ '/tools/' | relative_url }}) and
[Examples]({{ '/examples/' | relative_url }}) pages have been
reworked around the new capabilities — the Tools page now carries the
MCP server as its own section, and the Examples page gained the
sinologist and the Old English scholar among its walk-throughs.
