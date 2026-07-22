---
title: "Local — The Librarian"
permalink: /axis/local/
description: >-
  The Librarian's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Librarian — the owner's own shelves: dossiers, library, notes, and the sources' own records.

The canonical-memory shelves (architecture §16): local-language, local-library, local-notes, local-source.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these four answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 22 July 2026)</span> |
|---|---|---|---|---|
| `local-language` | language dossiers | open | enabled · manual | 214 dossiers |
| `local-library` | texts | research_private | enabled · manual | 20 docs / 8,725 passages |
| `local-notes` | owner notes | open | enabled · manual | nothing held yet |
| `local-source` | source records | open | enabled · manual | 88 dossiers |

## The desk's instruments

- **The Librarian's own shelves** (architecture §16): language dossiers
  (`local-language`, the `nabu language` cards re-derive from Markdown),
  the owner's library of PDFs and scans (`local-library`), owner notes
  (`local-notes`), and curated source dossiers (`local-source`).
- These are the write-gateway shelves, fed by `nabu ingest` and `nabu
  note` — no dictionary, alignment or etymology coverage.

## Working the local desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis local          # the shelf census, this desk only
nabu axis local                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis local   # a query scoped to this desk's shelves
nabu sync local                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu ingest ~/scans/vaillant-1950-manuel.pdf --collection slavistics  # copy a PDF into the library, derive metadata, mint a urn
nabu ingest --shelf language CODE     # scaffold a language dossier
nabu note URN "a working annotation"  # attach an owner note to any urn; read it back with `nabu note URN`
nabu sync local-language              # re-derive the language cards after editing the dossiers
```


## Terminal setup

- Owner-authored Markdown, YAML and PDF — no ancient-script display
  concerns; the terminal default font suffices.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
