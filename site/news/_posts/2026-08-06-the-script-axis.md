---
title: "The script axis — what script is this text actually in?"
date: 2026-08-06 17:30:00 +0000
description: >-
  The lect identifier gains a fifth axis: ~script claims the writing
  system of the text as held, machine-checkable against the bytes —
  and a measurement of the catalog's own script-suffixed codes is what
  overturned the registry's earlier doctrine. Plus: four Sefaria
  documents recovered from quarantine by teaching the parser nested
  schema nodes, and language dossiers gain their stage ladders.
---

The [nabu-lects](https://arvicco.github.io/nabu-lects) registry
shipped with a deliberate omission and a documented argument for it:
script stays out of the lect id, because BCP 47 already gives it a
home (`sr-Cyrl`, `san-Latn`). One fact, one home.

Measurement overturned the doctrine. This library holds ~3,450
documents whose language codes carry script suffixes, and a byte-check
of every one of them found the suffix convention making **two
different claims with no way to say which**: `san-Latn` on a GRETIL
text means the held edition is romanized — a fact about the bytes —
while `egy-Egyd` on an Elephantine papyrus means the *artifact* was
written in Demotic, riding text that is itself 100% Latin
transliteration. Same syntax, opposite directions. A nomenclature that
wants to pin down *which lect, presented how* has to say this
precisely.

So the identifier grammar grew a fifth axis:

```
lect-id = anchor [ ":" stage ] [ "/" variety ] [ "~" script ] [ "@" ortho ]
```

`~script` claims exactly one thing: **the writing system of the text
as held** — the surface a reader meets, checkable against the bytes.
`san~latn` is a romanized Sanskrit edition; `sga~ogam` is Old Irish as
the ogham stone renders it. Where the artifact's original script
differs from the held presentation — the transliterated cuneiform
tablet, the Demotic papyrus — that fact is real and kept, but as a
separate field, never folded into the lect id. (The sigil is `~`
rather than the more literary `&` for a thoroughly practical reason:
`&` backgrounds unquoted shell commands and separates URL query
strings; `~` passes everywhere bare.)

The registry side ships a global `scripts:` table — twenty ISO 15924
rows seeded from this library's measured need — and the two existing
orthography tags traded their prose script notes for machine `script:`
scopes. The retired argument stays in the registry's README, replaced
honestly by the measurement that beat it.

Two smaller things landed alongside. The Sefaria parser learned
**nested schema nodes** — a text section that is itself a dict of
named subsections — which recovered four documents that had sat in
quarantine since their waves: both Tanna DeBei Eliyahu Zuta versions
and both English Sifras (2,741 passages in the Silverstein alone,
including upstream's variant "Chapter 2*", which now cites as
`chapter-2-2` instead of colliding). And the language dossiers gained
structured **stage ladders** accreted from the registry — twenty-five
languages now carry their historical stages, bands and registers in
their permanent files, with the live card still computing holdings
fresh.
