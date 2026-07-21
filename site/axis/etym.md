---
title: "Etym — The Comparative Indo-Europeanist"
permalink: /axis/etym/
description: >-
  The Comparative Indo-Europeanist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Comparative Indo-Europeanist — laryngeals, reflex chains, the long descent of words.

The reconstruction shelves: the kaikki proto-extracts, IE-CoR cognacy, LIV, the Leiden Latin dictionary, StarLing's bases, and the curated loan edges. Non-IE lanes of the same shelves ride their own axes too — dual-tagging, never folding.

## The shelves

A source wears every desk it serves — these six answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 21 July 2026)</span> |
|---|---|---|---|---|
| `wiktionary-recon` | dictionary | attribution | enabled · manual | 30,261 entries |
| `iecor` | cognacy dataset | attribution | enabled · manual | 4,981 entries |
| `liv` | dictionary | attribution | enabled · manual | 305 entries |
| `edl` | dictionary | nc | enabled · manual | 2,860 entries |
| `starling` | etymological bases | attribution | enabled · manual | 27,397 entries |
| `sabellic-loans` | dictionary | attribution | enabled · local | 85 entries |

## The desk's instruments

- **The reconstruction shelves:** the kaikki proto-extracts
  (`wiktionary-recon`), IE-CoR cognacy (`iecor`), LIV's PIE verbal etymons
  (`liv`), de Vaan's Latin (`edl`), the five StarLing bases including
  Vasmer's Russian (`starling`), and the curated loan edges (`sabellic-loans`).
- **The walk:** `nabu etym` closes the reflex graph hop by hop, flagging
  `(loan)` edges along the way; `nabu define *headword` scopes to the
  reconstruction shelves; `nabu cognates` crosses the crosswalk with the
  alignment hub.
- Non-IE lanes of the same shelves ride their own axes too — dual-tagging,
  never folding.

## Working the etym desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis etym          # the shelf census, this desk only
nabu axis etym                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis etym   # a query scoped to this desk's shelves
nabu sync etym                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu etym богъ --lang chu             # a multi-hop proto-to-proto walk with per-edge loan flags
nabu define *bʰer-                    # a leading * scopes to the reconstruction shelves; --long expands
nabu etym rufus                       # the Sabellic-to-Latin loan etymon
nabu cognates nt --langs got,chu      # same-root verses across the aligned witnesses
nabu language zle-ort                 # decode an etymology cognate-list language code
```


## Terminal setup

- Mostly Latin and IPA reconstruction text. Cyrillic reflexes render under
  **Noto Sans Mono**; Old Italic reflex headwords (sabellic-loans) need
  `font-noto-sans-old-italic`. No RTL or CJK concerns.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
