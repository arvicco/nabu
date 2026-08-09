---
title: "Iranian — The Iranologist"
permalink: /axis/iranian/
description: >-
  The Iranologist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Iranologist — the Avesta to the Achaemenid inscriptions, Old Iranian liturgy toward Middle Persian.

The Iranian-language lane, Zoroastrian canon at its heart: the TITUS Avesta (Old Iranian liturgy — grant-gated private research, not a public holding) and the Old Persian of the Achaemenid royal inscriptions, which ride the ORACC and CDLI cuneiform shelves whole — their trilinguals' Old Persian column the desk's shared lane with the tablet world.

The desk's heart, the **Avesta** (TITUS, `titus-avestan`), is grant-gated
PRIVATE research material — served locally under the owner's personal grant
№41-3 and credited on every serving surface (the grant's own condition), but
NOT a public library holding, so it is absent from the shelves table above and
the footnote there says so. What the desk publicly holds is the **Old Persian**
of the Achaemenid royal inscriptions, riding the shared cuneiform corpora
(ORACC's `ario`, the CDLI catalog) whole — only their Old Persian column is
Iranian.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these two answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 8 August 2026)</span> |
|---|---|---|---|---|
| `oracc` | tablets | open | wired · manual | 118,367 docs / 1,800,218 passages |
| `cdli` | tablet catalog | attribution | wired · manual | 353,156 docs / 2,186,961 passages |

Private research materials under personal grants are not listed.

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 8 August 2026)</span>: `sux` 238,796 · `akk` 106,793 · `und` 74,258 · `eng` 15,417 · `hit` 14,678 · `qpc` 8,931 · `xeb` 6,844 · `elx` 2,723 · `uga` 1,108 · `xur` 703 … and 15 more (`nabu axis iranian` lists all).

## The desk's instruments

- **The Avestan text lane (ave):** the TITUS Avesta — full-text `search --lang
  ave` and citation `show` across the Yasna, Yašts and the rest. It is a text
  edition, not a treebank, so there is **no gold-lemma or morphology layer** —
  `--lemma`, `vocab` and `formulas` do not apply to this desk. Every serving
  surface carries the verbatim TITUS credit line (the №41-3 grant's condition).
- **The Old Persian Achaemenid lane (peo):** the royal trilinguals — ORACC's
  `ario` (Achaemenid Royal Inscriptions online) and the CDLI catalog carry the
  Old Persian column of the Bīsotūn / Naqš-e Rostam inscriptions. Reach them
  with a peo-scoped `search` or through the cuneiform desk (both are
  whole-source members — only their Old Persian lane is Iranian).
- **Iranian comparanda through `etym`:** StarLing's PIE base carries Avestan
  (`ae`) and Other-Iranian reflex columns, reachable with `nabu etym` and the
  cognate lists — dual-tagging, so StarLing rides `etym` and its Iranian
  reflexes surface through the crosswalk rather than as a separate shelf here.

## Working the iranian desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable iranian               # first time: put this desk's shelves in this box's profile
nabu sync iranian                 # fetch/refresh the desk's enabled members
nabu list --axis iranian          # the shelf census, this desk only
nabu axis iranian                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis iranian   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu show urn:nabu:titus-avestan:avest001:Y.0.1.a  # the frauuarāne creed (Y 0.1 a), the Avesta rendered with its verbatim TITUS credit line
nabu search mazda --lang ave          # Ahura Mazda across the Avestan lane (mazdaiiasnō, mazdā̊)
nabu show urn:nabu:titus-avestan:avest020:Y.19.1  # a citation prefix opens into every passage below it (Y.19.1.a, .b …) — the P44 show
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Where does the Avesta invoke Ahura Mazdā?”** → `nabu_search "ahura mazda" (lang: ave)` — Yasna and Yašt passages (Y.19.1, Y.58.8, Yt.3.2 …) served under their nc class with the TITUS/editors credit line riding every card — a personal research grant, honored in the payload.

## Terminal setup

- **Avestan (ave):** the TITUS Avesta is a scholarly Latin transliteration with
  combining diacritics (ā̊, ϑ, ṣ̌, t̰, ə) — no dedicated font is needed; any
  Unicode font with extended-Latin coverage renders them, and **Noto Sans
  Mono** in the terminal's non-ASCII slot gives uniform metrics. No RTL or CJK
  concerns.
- **Old Persian (peo):** the Achaemenid inscriptions ride ORACC and CDLI stored
  in Latin transliteration (the cuneiform desk's convention), so no cuneiform
  font is needed.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-three research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
