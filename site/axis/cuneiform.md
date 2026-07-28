---
title: "Cuneiform — The Assyriologist"
permalink: /axis/cuneiform/
description: >-
  The Assyriologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Assyriologist — Sumerian, Akkadian, Ugaritic, Hittite: the tablet world entire.

The cuneiform-culture shelves: Oracc and CDLI, ETCSL's Sumerian literature, eBL's fragments, the Copenhagen Ugaritic Corpus (alphabetic cuneiform), and TLHdig shared with the Hittitologist.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these seven answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 73 docs / 322,114 passages |
| `oracc` | tablets | open | wired · manual | 118,366 docs / 1,800,130 passages |
| `tlhdig` | tablets | attribution | wired · manual | 23,486 docs / 402,195 passages |
| `etcsl` | texts | nc | wired · frozen | 775 docs / 42,577 passages |
| `cdli` | tablet catalog | attribution | wired · manual | 353,156 docs / 2,186,961 passages |
| `ebl` | tablets | nc | wired · manual | 23,288 docs / 325,728 passages |
| `cuc` | tablets | nc | wired · manual | 279 docs / 7,544 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 28 July 2026)</span>: `sux` 242,884 · `akk` 127,402 · `und` 74,261 · `hit` 35,888 · `eng` 15,798 · `qpc` 8,931 · `xeb` 6,844 · `elx` 2,723 · `uga` 1,387 · `xhu` 729 … and 31 more (`nabu axis cuneiform` lists all).

## The desk's instruments

- **The tablet world:** ORACC (royal inscriptions, lexical lists, gold
  Akkadian/Sumerian lemmatization, aligned English), the CDLI catalog,
  ETCSL's Sumerian literature, eBL's Fragmentarium, the Copenhagen Ugaritic
  Corpus (alphabetic cuneiform), and TLHdig shared with the Hittitologist.
- **The fragment desk:** ORACC is in the `--fuzzy` trigram index, so
  `search --fuzzy … --axis cuneiform` finds broken lines.
- **The deepest timeline:** ORACC's catalogue and regnal dates put 21,558
  documents on the calendar — `--century -7` reaches the Assyrian letters.

## Working the cuneiform desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable cuneiform               # first time: put this desk's shelves in this box's profile
nabu sync cuneiform                 # fetch/refresh the desk's enabled members
nabu list --axis cuneiform          # the shelf census, this desk only
nabu axis cuneiform                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis cuneiform   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu show --random --source oracc     # pull a random tablet from the ORACC shelf
nabu show urn:nabu:oracc:saao-saa01:P224395:o.1-o.3 --parallel  # Akkadian beside its running English translation
nabu search --century -7 --axis cuneiform  # term-less browse — the 7th-century-BCE tablets on the regnal-date timeline, corpus order
nabu search --fuzzy "a-na LUGAL" --axis cuneiform  # trigram fragment search — "to the king", straight off the tablet
nabu search --lemma šarru --lang akk --axis cuneiform  # the gold ORACC Akkadian lemmatization — šarru behind every LUGAL
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Attestations of šarru 'king' — as lemma, not spelling.”** → `nabu_search (lemma: šarru, lang: akk)` — Logographic LUGAL spellings resolved through ORACC's lemmatization — the first hits are the Cyrus Cylinder's opening lines, each with the surface form shown beside the lemma.

## Terminal setup

- ORACC, CDLI and ETCSL text is stored in **Latin transliteration**
  (subscript indices, `{d}`-style determinatives) — display.md ships no
  cuneiform font and none is required. No RTL or CJK concerns.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
