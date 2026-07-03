# Nabu — Concept Document

*A self-hosted, extensible ingestion and research system for ancient texts.*

## What this is

Nabu is a personal research infrastructure that pulls the world's digitized ancient texts — Greek, Latin, Old Church Slavonic, Sanskrit, Gothic, Hittite, cuneiform, and beyond — into a single, locally-owned, queryable store. The name is the Mesopotamian god of scribes and writing, patron of the tablet house and divine custodian of Ashurbanipal's library — a fitting deity for a system whose oldest sources are themselves cuneiform tablets. The domain `nabu.ac` is reserved for the eventual read-only query endpoint. It is not a reader app and not a website. It is a pipeline plus a database, operated from the command line, designed to run indefinitely on self-hosted hardware with no cloud dependency beyond optional API calls for enrichment.

Two ingestion modes feed one store:

1. **Adapter ingestion** — automated, repeatable pulls from known digital corpora (Perseus, PROIEL, GRETIL, ORACC, …). Each source has a dedicated adapter that knows its format, structure, and quirks. Runs are idempotent: re-running an adapter syncs changes, never duplicates.
2. **Ad-hoc ingestion** — a drop-folder workflow for anything else: photos of manuscript facsimiles, scans of 19th-century critical editions, PDFs from Internet Archive. Images pass through an HTR/vision-transcription pipeline (local model or Claude API), a verification pass, and human review before entering the store through the same normalization gate as adapter content.

## What the user does (workflows)

### Sync a source

```
nabu sync perseus-greek          # clone/pull upstream, parse, normalize, load
nabu sync --all                  # sync every enabled adapter
nabu status                      # per-source: last sync, passage counts, drift
```

### Ingest a scan

```
nabu adhoc new "Miklosich 1862 Lexicon"     # creates an intake folder + manifest
# drop page images / PDF into the folder
nabu adhoc transcribe miklosich-1862        # HTR pass → draft transcription per page
nabu adhoc review miklosich-1862            # opens side-by-side review (image vs text)
nabu adhoc commit miklosich-1862            # normalize + load into store with provenance
```

Every ad-hoc item records: source images (kept forever), transcription model + version, confidence flags, and reviewer sign-off. Nothing enters the searchable store unreviewed unless explicitly flagged `--draft`.

### Query

```
nabu search "πλέων"                          # FTS across originals
nabu search --semantic "oath-swearing rituals" --langs grc,hit,san
nabu show urn:cts:greekLit:tlg0012.tlg001:1.1-1.10
nabu concord "prisega" --corpus ocs          # concordance view
nabu export --lang got --format conllu       # dumps for external tooling
```

Semantic search runs over embeddings of the original text and (where generated) English glosses, enabling cross-linguistic concept queries that no traditional corpus tool supports.

### Enrich

```
nabu enrich lemmatize --lang lat             # CLTK/Stanza bridge
nabu enrich embed --changed                  # embed new/modified passages only
nabu enrich gloss --lang chu --model claude  # rough aligned translations, flagged as machine-generated
```

Enrichment is layered and non-destructive: derived data never overwrites canonical text and always carries provenance (tool, model, version, date).

## Core principles

- **Canonical vs derived.** Upstream text lives as files (TEI XML, plaintext, ATF, CoNLL-U) in a git-tracked canonical layer. SQLite (FTS5 + vectors + metadata) is entirely derived and can be rebuilt from the canonical layer at any time with `nabu rebuild`.
- **Citations are identifiers.** Every passage keys on a stable ID — CTS URN where upstream provides one, a generated URN in the same style where it doesn't. IDs never change once minted.
- **Provenance everywhere.** Every passage knows its source, upstream edition, license, retrieval date, and every transformation applied to it.
- **Licensing is data.** Each source's license is recorded per-document; queries and exports can filter on it (`--license open`), keeping legally-restricted material segregated from anything shareable.
- **Local-first.** Everything runs on owned hardware over Tailscale. External APIs (Anthropic, embedding services) are optional accelerators with local fallbacks (Kraken/eScriptorium for HTR, local embedding models on the DGX Sparks).
- **Boring storage.** One SQLite file per concern (catalog, fulltext, vectors), plain files for canonical data, git for history. Restorable from a rsync backup with zero services.

## What success looks like

- `nabu sync --all` on a fresh machine reproduces the entire searchable corpus from upstream + the canonical git repo in under an hour of compute.
- Adding a new digital source is a bounded, documented task (one adapter class + fixtures + registry entry), not a research project.
- A photographed manuscript page goes from camera to searchable, provenance-tracked passage in one sitting.
- Ten years from now, the SQLite layer can be thrown away and rebuilt; the canonical layer and ad-hoc source images remain the permanent asset.

## Explicit non-goals

- No web UI in v1 (CLI + optional read-only JSON endpoint over Tailscale later).
- No collaborative editing, no publishing platform.
- No attempt to replicate scholarly critical apparatus handling in v1 — apparatus is preserved as-is in canonical files but not modeled relationally.
- No OCR-everything ambition: ad-hoc ingestion is demand-driven, triggered by actual research needs.
