# Nabu documentation

The map of this folder. Every file keeps its path (many are linked from
the project site and from dated news posts), so this index groups them
logically rather than moving them. The project overview and the full
command tour live in the repository [README](../README.md); the public
site, [arvicco.github.io/nabu](https://arvicco.github.io/nabu/), renders
summaries of several pages below.

## Suggested reading order for newcomers

1. [01-concept.md](01-concept.md) — what Nabu is and the principles it keeps.
2. [quickstart.md](quickstart.md) — from a fresh checkout to the first search, alignment, and dictionary lookup.
3. [library.md](library.md) — what every shelf holds and what it is good for.
4. [axes.md](axes.md) and [languages.md](languages.md) — the research desks and the language codes.
5. [architecture.md](architecture.md) — when you want to change the code.
6. [operating-library.md](operating-library.md) — when you run your own instance.

## Getting started

| Document | What it covers |
|---|---|
| [quickstart.md](quickstart.md) | Zero to first search: install, the starter shelf, search, show, define, align, the MCP server. |
| [restore.md](restore.md) | Restoring an instance on a fresh machine — the three permanent folders and the two restore paths. |

## The library

| Document | What it covers |
|---|---|
| [01-concept.md](01-concept.md) | The concept document: ingestion modes, the registry, workflows, core principles, non-goals. |
| [library.md](library.md) | The shelf-by-shelf guide to the holdings, with research uses and the gate-time review duty. |
| [operating-library.md](operating-library.md) | The administrator's process map: every recurring operating routine with its commands and detail links. |
| [axes.md](axes.md) | The research desks (axes): personas, membership, how to drive a desk as a unit. Registry-checked by the suite. |
| [languages.md](languages.md) | The language-code system, the lect layer, and every significant code in the corpus and on the reference shelves. |
| [places.md](places.md) | The place layer: held gazetteers, the matching registry, coverage, and the place-mining loop. |
| [display.md](display.md) | Displaying ancient text in a terminal: what the display layer does, the edition-level transforms, fonts and terminal setup per script. |

## Sources

| Document | What it covers |
|---|---|
| [02-sources.md](02-sources.md) | The source survey and status table: one row per source with access path, license, and lifecycle status. |
| [03-unlockable-sources.md](03-unlockable-sources.md) | Sources behind permissions, subscriptions, or images, with the unlock paths tried and the ones still open. |
| [manual/](manual/README.md) | Replayable instructions for every source or tool a machine cannot fetch unattended. |

## Architecture and internals

| Document | What it covers |
|---|---|
| [architecture.md](architecture.md) | The system design: adapters, the catalog schema, normalization, loading, sync, rebuild, the stores, shelves, and the nabu-data rail. |
| [conventions.md](conventions.md) | Field notes and data conventions: Unicode/NFC, citations, editions and witnesses, language codes, epigraphic brackets, licensing, search folding, CLI output, dates, uncertainty. |
| [ops.md](ops.md) | The operations runbook: the scheduled cadence (launchd), health and red-job triage, backup and the restore drill, the release rail, ingest, notes, source dossiers, display modes. |
| [mcp.md](mcp.md) | The read-only MCP server: registration per client, the fourteen tools, the restricted-source stance. |
| [embed.md](embed.md) | Semantic search (`nabu embed`, `search --similar`): what it builds, what it costs, its measured limits. |
| [lemma-enrichment.md](lemma-enrichment.md) | The silver-lemma lane (`nabu lemma-enrich`): gold vs silver, the campaign, its measured accuracy. |
| [nabu-data.md](nabu-data.md) | The producer contract for the derived-dataset sister repository (CLDF + Frictionless, DOI'd releases). |
| [intertext-design.md](intertext-design.md) | The design record for the intertext layer — parallels, collation, the timeline, fuzzy search, formulas, cognates, the links table — with a status note on what shipped. |

## Process

| Document | What it covers |
|---|---|
| [dev-loop.md](dev-loop.md) | How Nabu is built: phases, packets, gates, model tiering, releases. |
| [maintenance-and-extension.md](maintenance-and-extension.md) | Where truth lives for every aspect of the project, the maintenance cadence, and the source-adoption decision procedure. |
| [improvements.md](improvements.md) | The improvement catalogue: known gaps and candidate directions. |

## History

| Document | What it covers |
|---|---|
| [history/](history/README.md) | The frozen early record — the original packet backlog (Phase 0–P43) and the completion worklog (to the P55 gate). Not current; kept verbatim. |
