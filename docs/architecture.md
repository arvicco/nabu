# Architecture

Ruby CLI application, modular adapter core, file-based canonical layer, SQLite derived layer. macOS-first (Apple Silicon), self-hosted, no required cloud services.

## 1. Layer model

```
┌─────────────────────────────────────────────────────────────┐
│  CLI (Thor)          nabu sync|adhoc|search|enrich|rebuild │
├─────────────────────────────────────────────────────────────┤
│  Application services                                        │
│   SyncRunner · AdhocPipeline · EnrichmentRunner · Query      │
├──────────────────┬──────────────────────┬───────────────────┤
│  Adapters        │  Normalization core  │  Enrichers        │
│  (per source)    │  (shared, invariant) │  (lemma/embed/    │
│                  │                      │   gloss/HTR)      │
├──────────────────┴──────────────────────┴───────────────────┤
│  Storage                                                     │
│   canonical/  (files, git)   ·   db/  (SQLite: Sequel)      │
└─────────────────────────────────────────────────────────────┘
```

**Invariant:** data flows one way. Adapters/HTR produce canonical files; the loader derives SQLite from canonical files; enrichers write only to derived tables. `nabu rebuild` proves the invariant by regenerating `db/` from `canonical/` byte-for-byte-equivalently (modulo enrichment, which replays from its own journal).

## 2. Directory layout

```
nabu/
├── CLAUDE.md
├── docs/                        # this doc set
├── bin/nabu                   # Thor entrypoint
├── lib/nabu/
│   ├── adapter.rb               # base class + contract
│   ├── adapters/                # one file per source
│   │   ├── perseus.rb
│   │   ├── proiel.rb
│   │   ├── conllu.rb            # parser families are mixins/components,
│   │   ├── epidoc_parser.rb     #   adapters compose them
│   │   └── ...
│   ├── model/                   # Passage, Document, Source, Provenance
│   ├── normalize/               # Unicode, citation, language tagging
│   ├── store/                   # Sequel models, loader, schema migrations
│   ├── enrich/                  # lemmatizer bridge, embedder, glosser
│   ├── adhoc/                   # intake, HTR drivers, review, commit
│   └── query/                   # FTS, vector, concordance
├── config/
│   ├── sources.yml              # registry: adapter class, upstream, license, enabled
│   └── nabu.yml               # paths, models, API settings
├── canonical/                   # git repo (possibly separate) — the asset
│   ├── perseus-greek/           # vendored upstream snapshot or submodule
│   ├── adhoc/<slug>/            #   pages/ (images) + transcription/ + manifest.yml
│   └── ...
├── db/
│   ├── catalog.sqlite3          # sources, documents, passages, provenance, licenses
│   ├── fulltext.sqlite3         # FTS5 (contentless, keyed by passage id)
│   └── vectors.sqlite3          # sqlite-vec embeddings, per model-version table
├── test/
│   ├── fixtures/<source>/       # small real upstream samples, checked in
│   └── ...
└── Rakefile
```

Canonical layer on the big disk, `db/` rebuildable anywhere, both rsync/git-friendly. Keeping three SQLite files separates concerns and keeps the precious catalog small; ATTACH handles cross-db queries.

## 3. The adapter contract

Every adapter is one class implementing four methods. This contract is the extensibility point of the entire system and must stay small.

```ruby
class Nabu::Adapter
  # Bring upstream to local canonical/<source>/ (git pull, rsync,
  # HTTP crawl with cache). Must be resumable and rate-limit polite.
  def fetch(workdir) -> FetchReport

  # Enumerate ingestible documents found in workdir.
  def discover(workdir) -> Enumerator<DocumentRef>

  # Parse one document into the neutral in-memory model.
  def parse(document_ref) -> Document   # Document has_many Passages

  # Static metadata: id, name, license, upstream URL, parser family.
  def self.manifest -> SourceManifest
end
```

Key decisions:

- **Neutral model, not neutral file format.** Adapters emit `Document`/`Passage` Ruby objects; the shared loader handles all persistence. Adapters never touch SQL.
- **Passage = the citable unit.** For CTS sources, the smallest citation level (line, section). For treebanks, the sentence. For ad-hoc, the page or editor-defined chunk. Fields: `urn`, `language` (BCP-47 with ISO-639-3, e.g. `grc`, `chu`, `hit`), `text` (NFC Unicode), `text_normalized` (search form: lowercased, diacritic-folded per-language rules), `annotations` (JSON: lemmas, morphology if source provides), `sequence`, `document_id`.
- **Parser families as components.** `EpidocParser`, `ProielParser`, `ConlluParser`, `AtfParser` are standalone, individually tested classes; adapters are thin compositions (Perseus ≈ EpidocParser + repo layout knowledge + URN extraction). New source in a known family ≈ 100 lines.
- **Idempotency via content hashing.** Loader upserts on `urn`; a passage row stores `content_sha256`. Unchanged content is skipped; changed content bumps `revision` and journals the old hash. Deletions upstream mark rows `withdrawn`, never hard-delete.
- **Fetch is separated from parse** so tests never need network and `nabu sync --parse-only` can re-run after parser fixes without re-downloading.

## 4. Ad-hoc pipeline

State machine per intake item, manifest-driven (`manifest.yml` tracks state, provenance, model versions):

```
new → pages_added → transcribed → reviewed → committed
                       ↑    ↓ (re-run with different model/params)
                       └────┘
```

- **Intake:** `nabu adhoc new` creates `canonical/adhoc/<slug>/` with `pages/`, `transcription/`, `manifest.yml`. PDFs are exploded to page images (mutool/pdftoppm via shelling out — both fine on macOS).
- **HTR drivers** behind one interface: `ClaudeVision` (API, page image → text, with a second *verification* call that diffs transcription against image and flags low-confidence spans), `KrakenDriver` (local, for trained models e.g. polytonic Greek), `LocalVLM` (OpenAI-compatible endpoint → the DGX Sparks over Tailscale). Driver choice per-item in the manifest. Every transcription file records driver, model id, prompt version.
- **Review:** `nabu adhoc review` generates a static HTML page (image left, editable text right) served from a local port; saved edits write back to `transcription/`. Human sign-off flips state to `reviewed`.
- **Commit:** transcription becomes a canonical document (minted URN `urn:nabu:adhoc:<slug>:<page>`), enters the store through the standard loader. Source images stay forever — they are the actual primary source.

## 5. Storage schema (catalog.sqlite3, conceptual)

```
sources(id, name, adapter_class, license, license_class, upstream_url,
        enabled, last_sync_at, last_sync_sha)
documents(id, source_id, urn, title, language, edition, license_override,
          canonical_path, content_sha256, revision, withdrawn)
passages(id, document_id, urn, sequence, language, text, text_normalized,
         annotations_json, content_sha256, revision)
provenance(id, passage_id, event, tool, tool_version, model, params_json, at)
enrichments(id, passage_id, kind, model, model_version, payload_json, at)
   -- lemmas, glosses; embeddings live in vectors.sqlite3 keyed by passage id
```

- FTS5 external-content table over `text_normalized` + trigram tokenizer option for scripts where word segmentation is unreliable.
- `vectors.sqlite3`: one table per `(embedding_model, version)` — model upgrades create a new table, old one dropped only after re-embed completes.
- Migrations via Sequel's migration framework, numbered, forward-only.
- `license_class` enum (`open`, `attribution`, `nc`, `research_private`, `restricted`) drives query/export filters.

## 6. Enrichment

- **Lemmatization:** CLTK/Stanza are Python; bridge via a small persistent Python sidecar exposing HTTP on localhost (started by `nabu enrich`), not per-call subprocess spawning. Ruby stays the orchestrator.
- **Embeddings:** pluggable `Embedder` interface — Anthropic-adjacent APIs, or local model on the Sparks. Embed `text` and, when available, the English gloss; store both vectors.
- **Glossing:** Claude API, batched, always stored as `enrichments(kind: 'machine_gloss')`, never presented as translation without the flag.
- All enrichment is journaled (provenance rows) and replayable: `nabu rebuild` restores derived text tables, then `nabu enrich --replay` re-applies from journal or re-computes.

## 7. Technology choices

| Concern | Choice | Rationale |
|---|---|---|
| Ruby | 3.3+ (rbenv) | New project — no reason to inherit 2.5; modern YJIT, pattern matching for parser code. |
| CLI | Thor | Subcommand ergonomics, ubiquitous. |
| DB | Sequel + sqlite3 | Existing house expertise; Sequel's dataset model fits reporting queries. |
| XML | Nokogiri (SAX for big TEI files) | Perseus files can be large; stream, don't DOM, in hot paths. |
| HTTP | Faraday + faraday-retry, disk cache middleware | Uniform caching/politeness across scraping adapters. |
| Vectors | sqlite-vec extension | Single-file, no service. |
| Tests | Minitest + WebMock/VCR | See CLAUDE.md. |
| Lint | RuboCop (standard-ish config) | CC needs an objective style oracle. |

## 8. Failure & integrity

- Every sync writes a `FetchReport` + `LoadReport` (counts: added/updated/withdrawn/errored) to a `runs` table; `nabu status` reads it. A sync that would withdraw >20% of a source's passages aborts and demands `--force` (upstream restructures happen; don't silently gut the corpus).
- Parse errors quarantine the document (recorded, skipped), never abort the batch.
- `nabu verify` re-hashes canonical files against the catalog — bitrot/tamper check, cronnable.
- Backups: canonical/ is git (bare mirror on nero/nexo via Tailscale); db/ is disposable but nightly-snapshotted anyway (cheap).
