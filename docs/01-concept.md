# Nabu — Concept Document

*A self-hosted, extensible ingestion and research system for ancient texts.*

## What this is

Nabu is a personal research infrastructure that pulls the world's digitized ancient texts — Greek, Latin, Old Church Slavonic, Sanskrit, Gothic, Hittite, cuneiform, and beyond — into a single, locally-owned, queryable store. The name is the Mesopotamian god of scribes and writing, patron of the tablet house and divine custodian of Ashurbanipal's library — a fitting deity for a system whose oldest sources are themselves cuneiform tablets. The domain `nabu.ac` is reserved for the eventual read-only query endpoint. It is not a reader app; the project site documents the system, but the system itself is not a website — it is a pipeline plus a database, operated from the command line (and, over MCP, from an AI assistant), designed to run indefinitely on self-hosted hardware with no cloud dependency beyond optional API calls for enrichment.

Two ingestion modes feed one store:

1. **Adapter ingestion** — automated, repeatable pulls from known digital corpora (Perseus, PROIEL, GRETIL, ORACC, …). Each source has a dedicated adapter that knows its format, structure, and quirks. Runs are idempotent: re-running an adapter syncs changes, never duplicates.
2. **Owner ingestion** — `nabu ingest FILE|URL` files your own PDFs, scans, and articles into the acquired-library shelf (metadata prompts, provenance, a default private license class), and `nabu note` annotates any URN the corpus knows. Both are sanctioned write gateways into the owner's permanent shelves, as provenance-tracked as any adapter.

A third mode is designed but unbuilt: the HTR loop — photo of a manuscript page or 19th-century edition → vision transcription (local model or Claude API) → verification pass → human review → the same normalization gate as adapter content. That is the planned `adhoc` workflow (planned — not yet built); today `nabu ingest` shelves the images and PDFs so nothing waits on it.

## The registry: sources, shelves, modules

Everything ingestible is registered in `config/sources.yml` under one of three kinds. A **source** is a text corpus with document rows (Perseus, ORACC). A **module** is machinery-only reference data — sign lists, gazetteers, the lect registry — zero document rows, all capability. A **shelf** is the owner's own permanent material (the acquired library, language and source dossiers, notes). Three orthogonal switches govern sync (semantics owner-ruled 2026-08-18): **wired** — the fetch channel is tested and declared working, a project-level fact; **enabled** — this box's owner opted in (`nabu enable`, recorded in `local/config/profile.yml`; sync refuses un-enabled sources); **sync_policy** — the cadence: `auto` (swept by `nabu sync --all`), `manual` (re-synced on request), `frozen` (upstream is done moving). A few sources are additionally **grant-gated**: the text is served under a personal permission (TITUS Avestan, under a recorded 2026 grant), and sync demands an explicit per-box acknowledgment of the terms before its first fetch.

## What the user does (workflows)

### Sync a source

```
nabu enable gretil               # opt this box in (the enablement gate)
nabu sync gretil                 # fetch upstream, parse, normalize, load
nabu sync --all                  # the narrow sweep: every enabled auto-cadence source
nabu status                      # per-source: kind, cadence, holdings, last run, drift
```

Fetching is non-destructive by doctrine: a plain `git pull` would silently drop files upstream scrapped, so all git fetching goes through a gateway that attics upstream deletions under `canonical/<slug>/.attic/`, and a circuit breaker refuses any sync that would withdraw more than 20% of a source's documents. The catalog itself never hard-deletes: documents are withdrawn, revised, journaled — never erased.

Long passes narrate: every stage announces itself with an estimate drawn from the ledger's history of past stage timings, so a million-passage load reads as progress, never as a hang.

### Ingest your own material

```
nabu ingest scans/miklosich-1862-lexicon.pdf --collection slavistics
nabu note urn:nabu:sblgnt:john:1.1 "cf. Gen 1.1 LXX ἐν ἀρχῇ"
```

Every ingested item records creator, year, languages, provenance, and license class; every note is an owner-authored annotation riding on a URN. These land in the owner's memory shelves — permanent, backed up, never derivable — each through its one sanctioned write gateway.

### Query

```
nabu search "πλέων"                          # FTS across originals, fold-aware
nabu search --lemma λέγω --lang grc          # dictionary-form search over the treebanks
nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
nabu concord "prisega" --lang sl             # concordance (KWIC) view
nabu export --lang got --format jsonl        # dumps for external tooling
```

Search is diacritic- and case-insensitive on both sides and carries some thirty-five composable filters — language, license, source, research axis, date window, findspot, script, meter, morphology, loan origin, cuneiform sign, Han-character structure, and more. Semantic search across languages ("oath-swearing rituals" in Greek, Hittite, and Sanskrit at once) is designed but (planned — not yet built), as is the vectors store it would run on (planned); today's cross-linguistic reach comes from lemma search, aligned witnesses, and the reference desks.

Beyond search, the **reference desks** answer scholarly questions directly: `align` renders one citation across every held witness; `define` looks a lemma up in the held dictionaries; `etym` walks a lemma to its reconstructed ancestors; `char` and `signs` are the Han-character and cuneiform-sign desk cards; `place` resolves findspots against the gazetteers; `cognates` and `parallels` surface aligned-witness cognates and textual echoes; `links` walks mined cross-reference edges. Each desk degrades honestly, section by section — an unsynced shelf is an absent section, never an error.

The library is organized into **research desks** (axes): 24 as of 2026-08-19 — classical, slavic, cuneiform, indic, sinitic, iranian, and on. Each axis names the sources serving one research programme and is drivable as a unit: `nabu enable slavic && nabu sync slavic`, `nabu search --axis epigraphy`, `nabu status --axis`.

### Enrich

The model-driven enrichment family — lemmatization bridges (CLTK/Stanza), embeddings, machine glosses — is designed but (planned — not yet built). Today's lemma layer comes from the gold treebanks (PROIEL, UD, TOROT) and upstream silver annotations, and the shipped enrichment lane is sync-driven producers — the meter scansions, where pedecerto and hypotactic scan the Latin verse corpus at load. The design contract already holds for everything shipped: enrichment is layered and non-destructive — derived data never overwrites canonical text and always carries provenance (tool, version, date) — and anything costing money, network, or human review to regenerate lands in a permanent shelf, never in the rebuildable database.

### Talk to your library

`nabu mcp` serves the corpus read-only over MCP. The repo ships `.mcp.json`, so opening the directory in Claude Code registers the server automatically; an AI assistant can then search, read, align, and define against everything synced, with a license label on every passage ([mcp.md](mcp.md)).

## Core principles

- **Three permanent folders; everything else is derived.** `canonical/` holds the fetched assets (gitignored — each source inside it is its own clone or snapshot, attic included); `config/` is the git-shared project definition (registries, rules, postures, alignments); `local/` is the instance — owner shelves, rulings, grants, the operational ledger (`local/history.sqlite3`). Everything under `db/` is a pure function of those three, regenerated by `nabu rebuild` at any time. That is the derivability law: anything non-derivable must live in a permanent folder, never in `db/`.
- **Citations are identifiers.** Every passage keys on a stable ID — CTS URN where upstream provides one, a generated URN in the same style where it doesn't. IDs never change once minted.
- **Provenance everywhere.** Every passage knows its source, upstream edition, license, retrieval date, and every transformation applied to it.
- **Licensing is data.** Each source's license is recorded per-document; queries and exports can filter on it (`--license open`), keeping legally-restricted material segregated from anything shareable. Grant-gated sources additionally record who granted what, when, on which terms.
- **Local-first.** Everything runs on owned hardware over Tailscale. External APIs (Anthropic, HTR services) are optional accelerators, never load-bearing.
- **Boring storage.** One SQLite file per concern (catalog, fulltext, lects, links — plus the non-derived ledger at `local/history.sqlite3`), plain files for canonical data, git for history. Restorable from an rsync backup with zero services.

## What success looks like

- On a fresh machine, `nabu quickstart` lights the starter shelf in minutes; the full library (87 GB canonical / 125 GB derived as of 2026-08-19) restores from an rsync backup + `nabu rebuild`, or re-syncs shelf by shelf.
- Adding a new digital source is a bounded, documented task (one adapter class + fixtures + registry entry), not a research project.
- A scholar's question — where does this word attest, what does this sign read, which witnesses carry this verse — is one desk command against local files.
- Ten years from now, the SQLite layer can be thrown away and rebuilt; the three permanent folders remain the asset.

## Explicit non-goals

- No web UI — though "talk to your library" has shipped as the read-only MCP server, and the project site documents the system; the working surface stays CLI + files.
- No collaborative editing, no publishing platform.
- No attempt to model scholarly critical apparatus relationally — apparatus is preserved in canonical files and honored by display modes, not turned into structure.
- No OCR-everything ambition: owner ingestion is demand-driven, triggered by actual research needs.
