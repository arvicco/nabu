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

A source wears every desk it serves — these six answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `oracc` | tablets | open | enabled · manual | 104,722 docs / 1,588,133 passages |
| `tlhdig` | tablets | attribution | enabled · manual | 23,486 docs / 402,195 passages |
| `etcsl` | texts | nc | enabled · frozen | 775 docs / 42,577 passages |
| `cdli` | tablet catalog | attribution | enabled · manual | 353,156 docs / 2,186,961 passages |
| `ebl` | tablets | nc | enabled · manual | 23,288 docs / 325,728 passages |
| `cuc` | tablets | nc | enabled · manual | 279 docs / 7,544 passages |

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

The generic axis surfaces — every desk answers to these:

```
nabu list --axis cuneiform          # the shelf census, this desk only
nabu axis cuneiform                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis cuneiform   # a query scoped to this desk's shelves
nabu sync cuneiform                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu show --random --source oracc     # pull a random tablet from the ORACC shelf
nabu show urn:nabu:oracc:saao-saa01:P224395:o.1-o.3 --parallel  # Akkadian beside its running English translation
nabu search --century -7 --axis cuneiform  # the 7th-century-BCE Assyrian letters, by regnal date
nabu search --fuzzy FRAGMENT --axis cuneiform  # trigram fragment search over the ORACC tablets
nabu search --lemma --lang akk --axis cuneiform WORD  # the gold ORACC Akkadian lemmatization
```


## Terminal setup

- ORACC, CDLI and ETCSL text is stored in **Latin transliteration**
  (subscript indices, `{d}`-style determinatives) — display.md ships no
  cuneiform font and none is required. No RTL or CJK concerns.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
