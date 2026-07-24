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

A source wears every desk it serves — these nine answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 24 July 2026)</span> |
|---|---|---|---|---|
| `ud` | treebank | nc | enabled · manual | 64 docs / 285,143 passages |
| `oshb` | texts | open | enabled · manual | 39 docs / 23,213 passages |
| `sdbh` | dictionary | attribution | enabled · manual | 7,932 entries |
| `sefaria` | texts | open | enabled · manual | 103 docs / 57,095 passages |
| `bhsa` | texts | nc | enabled · manual | 39 docs / 23,213 passages |
| `bridging` | crosswalk module | attribution | not enabled | nothing held yet |
| `dss` | texts | nc | enabled · manual | 1,001 docs / 52,895 passages |
| `iip` | inscriptions | nc | enabled · manual | 5,499 docs / 17,823 passages |
| `hebrew-lexicon` | dictionary | attribution | enabled · manual | 21,144 entries |

## The desk's instruments

- **The Hebrew-and-Aramaic language desk:** OSHB (the Westminster Leningrad
  Codex), BHSA (ETCBC), the Dead Sea Scrolls consonantal text (`dss`), the
  Sefaria Targums (arc), and IIP's inscriptions of Israel/Palestine.
- **Dictionaries:** `sdbh` (the Semantic Dictionary of Biblical Hebrew) and
  the `hebrew-lexicon` shelf.
- **Alignment works:** `ot` and `psalms` — OSHB, BHSA and the Targum are
  the Masoretic witnesses; `psalms` carries the Masoretic→Greek renumbering.

## Working the hebrew desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis hebrew          # the shelf census, this desk only
nabu axis hebrew                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis hebrew   # a query scoped to this desk's shelves
nabu sync hebrew                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu show urn:nabu:oshb:gen:1.1       # Genesis 1.1 in pointed Masoretic Hebrew
nabu show urn:nabu:oshb:ruth:1.8 --display reading  # qere resolved and cantillation stripped together
nabu align "GEN 1.1"                  # the Masoretic text beside the LXX and the versions
nabu show urn:nabu:oshb:gen:1.1 --display translit  # SBL-style LTR romanization for a bidi-less terminal
nabu define אור --lang hbo            # Brown-Driver-Briggs on the Hebrew lexicon shelf
```


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

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
