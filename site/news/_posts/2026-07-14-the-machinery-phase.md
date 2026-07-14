---
title: "The machinery phase: quickstart, language cards, invariants"
date: 2026-07-14 09:00:00 +0000
description: >-
  Phase 18 (PR #22): nabu quickstart, language cards for an 803-code
  universe, three comparativist adapters, and a postcondition checker.
---

Phase 18 merged on 2026-07-14 (PR
[#22](https://github.com/arvicco/nabu/pull/22)) — the phase that turned
operating friction into machinery, written up retrospectively as this
News section opens.

**`nabu quickstart`** now stands up a starter library — a measured 693 MB
shelf spanning Greek epic, the Latin canon, papyri, and the parallel New
Testament — in one command ([quickstart]({{ '/quickstart/' |
relative_url }})). **`nabu language CODE`** answers "what is `gkm`?" for
the 803 language codes the etymology tools surface, each card drawing on
a derived names census, curated context, and live holdings, in about
0.2 seconds. **Three comparativist adapters** were registered awaiting
first sync: the IE-CoR cognacy matrix (4,981 cognate sets, loan
flagging), the LIV verbal roots, and de Vaan's Latin etymological
dictionary — expert-curated witnesses to set beside the
Wiktionary-derived chains. **A postcondition checker** made the sync
pipeline self-auditing: failed or partial loads are now loud, flags are
checked against their artifacts, and quarantine counts are watched
against a baseline. Coptic passage coverage also rose from 188 to 482 of
483 documents, and a dictionary dedupe audit closed with a single defect
found and fixed. The suite stands at 2,471 tests / 32,142 assertions.
