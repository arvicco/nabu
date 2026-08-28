---
title: "Local — The Librarian"
permalink: /axis/local/
description: >-
  The Librarian's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Librarian — the owner's own shelves: dossiers, library, notes, and the sources' own records.

The canonical-memory shelves (architecture §16): local-language, local-lemmas, local-library, local-notes, local-source.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these five answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 28 August 2026)</span> |
|---|---|---|---|---|
| `local-language` | language dossiers | open | wired · manual | 618 dossiers |
| `local-library` | texts | research_private | wired · manual | 21 docs / 8,731 passages |
| `local-notes` | owner notes | open | wired · manual | nothing held yet |
| `local-lemmas` | silver lemmas | open | wired · manual | not synced yet |
| `local-source` | source records | open | wired · manual | 156 dossiers |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 28 August 2026)</span>: `sga` 5 · `cel` 3 · `chu` 2 · `grc` 2 · `akk` 1 · `ang` 1 · `cor` 1 · `cym` 1 · `got` 1 · `ine` 1 … and 3 more (`nabu axis local` lists all).

## The desk's instruments

- **The Librarian's own shelves** (architecture §16): language dossiers
  (`local-language`, the `nabu language` cards re-derive from Markdown),
  the owner's library of PDFs and scans (`local-library`), owner notes
  (`local-notes`), and curated source dossiers (`local-source`).
- These are the write-gateway shelves, fed by `nabu ingest` and `nabu
  note` — no dictionary, alignment or etymology coverage.

## Working the local desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable local               # first time: put this desk's shelves in this box's profile
nabu sync local                 # fetch/refresh the desk's enabled members
nabu list --axis local          # the shelf census, this desk only
nabu axis local                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis local   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu ingest ~/scans/vaillant-1950-manuel.pdf --collection slavistics  # copy a PDF into the library, derive metadata, mint a urn
nabu ingest --shelf language CODE     # scaffold a language dossier
nabu note URN "a working annotation"  # attach an owner note to any urn; read it back with `nabu note URN`
nabu sync local-language              # re-derive the language cards after editing the dossiers
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“Is this language even covered here, before I conclude a word is unattested?”** → `nabu_status` — Per-source counts and recency, passages by language and license class, and what is excluded by default — the tool a careful model calls before trusting an empty search. Your own shelf notes ride show/define payloads wherever they touch a urn.

## Terminal setup

- Owner-authored Markdown, YAML and PDF — no ancient-script display
  concerns; the terminal default font suffices.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-four research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
