---
title: "Hebrew — The Hebraist"
permalink: /axis/hebrew/
description: >-
  The Hebraist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Hebraist — Masoretic vowels, Qumran consonants, the Aramaic of the Targums.

The Hebrew-and-Aramaic language desk beside the cross-language biblical hat: OSHB, BHSA, DSS, SDBH and the lexicon shelf, the Sefaria Targums, the bridging crosswalk, and IIP's inscriptions of Israel/Palestine.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these ten answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 31 August 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | wired · manual | 76 docs / 325,533 passages |
| `oshb` | texts | open | wired · manual | 39 docs / 23,213 passages |
| `sdbh` | dictionary | attribution | wired · manual | 7,932 entries |
| `sefaria` | texts | open | wired · manual | 921 docs / 474,643 passages |
| `bhsa` | texts | nc | wired · manual | 39 docs / 23,213 passages |
| `bridging` | crosswalk module | attribution | wired · manual | nothing held yet |
| `dss` | texts | nc | wired · manual | 1,001 docs / 52,895 passages |
| `iip` | inscriptions | nc | wired · manual | 5,499 docs / 17,823 passages |
| `hebrew-lexicon` | dictionary | attribution | wired · manual | 21,144 entries |
| `elephantine` | papyri & ostraca | attribution | wired · manual | 15,539 docs / 69,350 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 31 August 2026)</span>: `hbo` 30,259 · `grc` 6,297 · `eng` 5,320 · `arc` 3,331 · `egy` 3,050 · `egy-Egyd` 1,424 · `ara` 962 · `cop` 456 · `heb` 408 · `lat` 317 … and 21 more (`nabu axis hebrew` lists all).

## The desk's instruments

- **The Hebrew-and-Aramaic language desk:** OSHB (the Westminster Leningrad
  Codex), BHSA (ETCBC), the Dead Sea Scrolls consonantal text (`dss`), the
  Sefaria Targums (arc), and IIP's inscriptions of Israel/Palestine.
- **Dictionaries:** `sdbh` (the Semantic Dictionary of Biblical Hebrew) and
  the `hebrew-lexicon` shelf.
- **Alignment works:** `ot` and `psalms` — OSHB, BHSA and the Targum are
  the Masoretic witnesses; `psalms` carries the Masoretic→Greek renumbering.

## Working the hebrew desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable hebrew               # first time: put this desk's shelves in this box's profile
nabu sync hebrew                 # fetch/refresh the desk's enabled members
nabu list --axis hebrew          # the shelf census, this desk only
nabu axis hebrew                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis hebrew   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu show urn:nabu:oshb:gen:1.1       # Genesis 1.1 in pointed Masoretic Hebrew
nabu show urn:nabu:oshb:ruth:1.8 --display reading  # qere resolved and cantillation stripped together
nabu align "GEN 1.1"                  # the Masoretic text beside the LXX and the versions
nabu show urn:nabu:oshb:gen:1.1 --display translit  # SBL-style LTR romanization for a bidi-less terminal
nabu define אור --lang hbo            # Brown-Driver-Briggs on the Hebrew lexicon shelf
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Compare the two Masoretic editions of a verse.”** → `nabu_align "GEN 1.1" (work: ot)` — OSHB (WLC) and BHSA (ETCBC) side by side with the Targum and Peshitta columns — two independent Masoretic witnesses at deliberately different annotation grains, never merged.

## Terminal setup

- **Hebrew and Aramaic (hbo/arc):** cantillation stripped, points and maqaf
  kept, runs wrapped in RTL isolates. The terminal owns the bidi: the
  **iTerm2 RTL toggle** (Terminal.app has none); **Ezra SIL** or **SBL
  Hebrew** in a dedicated profile (+4pt), or **Noto Sans Mono** in the
  non-ASCII slot. `--display translit` (via `Nabu::Hebr`) is the legible
  fallback where bidi is unavailable.
- Note: hbo/arc are NFC-exempt, so `--display full` is byte-identical to the
  Masoretic source (mark order preserved).

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
