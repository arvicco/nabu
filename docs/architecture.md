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

**Invariant:** data flows one way. Adapters/HTR produce canonical files; the loader derives SQLite from canonical files; enrichers write only to derived tables. catalog + fulltext + vectors = f(canonical): `nabu rebuild` proves it by regenerating them from `canonical/` byte-for-byte-equivalently (modulo enrichment, which replays from its own journal). **history.sqlite3 is the exception by design** (P7-1): an append-only operational ledger (run history, per-repo sync pins, license baselines, durable revision events — later the enrichment journal) that is *never* derived, *never* dropped by rebuild, and part of the backup set. It is keyed by durable identity (source slug, repo url, passage/document urn), never by catalog row ids, which every rebuild re-mints.

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
│   ├── query/                   # FTS, vector, concordance
│   └── mcp/                     # MCP read-only surface: protocol core + tool table (P8-1)
├── config/
│   ├── sources.yml              # registry: adapter class, upstream, license, enabled, translations opt-in
│   └── nabu.yml               # paths, models, API settings
├── canonical/                   # git repo (possibly separate) — the asset
│   ├── perseus-greek/           # vendored upstream snapshot or submodule
│   ├── adhoc/<slug>/            #   pages/ (images) + transcription/ + manifest.yml
│   └── ...
├── db/
│   ├── catalog.sqlite3          # DERIVED: sources, documents, passages, provenance, licenses
│   ├── fulltext.sqlite3         # DERIVED: FTS5 + passage_lemmas (both keyed by passage id)
│   ├── vectors.sqlite3          # DERIVED: sqlite-vec embeddings, per model-version table
│   ├── history.sqlite3          # LEDGER (P7-1): runs, pins, revisions — never derived, never dropped
│   ├── migrate/                 # catalog migration track (forward-only)
│   └── ledger_migrate/          # ledger migration track (own schema_info per file)
├── test/
│   ├── fixtures/<source>/       # small real upstream samples, checked in
│   └── ...
└── Rakefile
```

Canonical layer on the big disk; the derived dbs rebuildable anywhere; the history ledger small, precious, and backed up alongside canonical/. One SQLite file per concern; cross-db reads thread separate connections (the established catalog/fulltext pattern — status and health take catalog + ledger handles the same way; ATTACH remains available if a real cross-db join ever appears).

## 3. The adapter contract

Every adapter is one class implementing four methods. This contract is the extensibility point of the entire system and must stay small.

```ruby
class Nabu::Adapter
  # Bring upstream to local canonical/<source>/ (git fetch+merge, rsync,
  # HTTP crawl with cache). Must be resumable, rate-limit polite, and
  # NON-DESTRUCTIVE (see §8: upstream deletions land in the attic; a mass
  # deletion trips the breaker before the tree changes unless force).
  def fetch(workdir, progress: nil, force: false) -> FetchReport

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
- **Passage = the citable unit.** For CTS sources, the smallest citation level (line, section). For treebanks, the sentence. For ad-hoc, the page or editor-defined chunk. Fields: `urn`, `language` (BCP-47 with ISO-639-3, e.g. `grc`, `chu`, `hit`), `text` (NFC Unicode), `text_normalized` (the TRUE search form, minted once at the adapter boundary: `Passage.new` defaults it to `Normalize.search_form` — marks stripped, downcased, plus per-language rules (grc final-sigma ς→σ; lat v→u, j→i; conventions.md §9). The FTS index stores it as-is; queries carry no language, so `Query::Search` matches the union of per-language query folds via `Normalize.query_forms`), `annotations` (JSON: lemmas, morphology if source provides), `sequence`, `document_id`.
- **Parser families as components.** `EpidocParser`, `ProielParser`, `ConlluParser`, `AtfParser` are standalone, individually tested classes; adapters are thin compositions (Perseus ≈ EpidocParser + repo layout knowledge + URN extraction). New source in a known family ≈ 100 lines.
- **Idempotency via content hashing.** Loader upserts on `urn`; a passage row stores `content_sha256`. Unchanged content is skipped; changed content bumps `revision` and journals the old hash. Deletions upstream mark rows `withdrawn`, never hard-delete.
- **Upstream deletions never destroy local data.** Git-based fetch attics the deleted file (§8); the adapter base rediscovers attic documents generically (`Adapter#discover_with_attic` — subclasses implement only `discover`, a urn found both live and in the attic resolves live-wins) and the loader marks them `retired_upstream` — live, searchable, exportable. `withdrawn` keeps meaning "absent from canonical entirely".
- **Fetch is separated from parse** so tests never need network and `nabu sync --parse-only` can re-run after parser fixes without re-downloading.
- **Parallel translations are a per-source opt-in (P7-4).** `translations: true` in `sources.yml` reaches the adapter through `SourceRegistry::Entry#build_adapter` — the one construction seam sync/rebuild/verify share; no-arg `.new` stays every adapter's contract and the default. A translations-on Perseus additionally ingests the highest `perseus-eng<n>` edition per work as an ordinary document (language `eng`, its own edition urn, same license); the shared CTS citation scheme makes passage alignment a pure query (`Query::Parallel`, `nabu show <urn> --parallel [lang]` — suffix-equality pairing, unmatched suffixes shown one-sided). ORACC is the second sibling family (P13-4): a translations-on Oracc crawls the official per-text HTML fragments (project-scoped: `Oracc::TRANSLATION_PROJECTS`, SAA-first staging) and mints `-en` sibling documents whose passage suffixes are the tablet's own line labels; `Query::Parallel`'s work notion covers both shapes (CTS work prefix + edition slug; ORACC tablet urn + `-<variant>`), and the translation prose carries `license_override: "attribution"` (CC BY-SA project content) while the source stays CC0/open.

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

## 5. Storage schema (conceptual)

The DERIVED catalog (catalog.sqlite3 — dropped and regenerated by `nabu rebuild`):

```
sources(id, name, adapter_class, license, license_class, upstream_url,
        enabled, last_sync_at, last_sync_sha)   -- last_sync_* are display mirrors;
                                                -- the authoritative pins are in the ledger
documents(id, source_id, urn, title, language, edition, license_override,
          canonical_path, content_sha256, revision, withdrawn, retired_upstream)
passages(id, document_id, urn, sequence, language, text, text_normalized,
         annotations_json, content_sha256, revision)
provenance(id, passage_id, event, tool, tool_version, model, params_json, at)
enrichments(id, passage_id, kind, model, model_version, payload_json, at)
   -- lemmas, glosses; embeddings live in vectors.sqlite3 keyed by passage id
```

The HISTORY LEDGER (history.sqlite3 — append-only, never derived, never dropped; P7-1):

```
runs(id, source_slug, kind[sync|rebuild], started_at, finished_at,
     added, updated, withdrawn_count, errored, status, notes)
pins(id, source_slug, repo_url, last_sync_sha, license_baseline_sha256)
   -- one row per upstream repo (single- and multi-repo sources alike);
   -- written by sync (sha) and the remote probe (baseline)
revisions(id, urn, event[revised|withdrawn|restored|retired|unretired],
          old_sha, new_sha, at)
   -- the durable revision history: content transitions of existing rows only
```

- Why the split: everything in the ledger is runtime HISTORY, not a function of canonical/ — pre-P7-1 it lived in the catalog and every rebuild amnesia'd health trends, license-drift baselines, and repo pins. Keying is by slug/url/urn because rebuilds re-mint all catalog ids.
- Provenance is deliberately NOT durable (decision, P7-1): it journals per-load noise ("loaded" × 60k docs per rebuild replay, "quarantined", "superseded") that describes the *derivation*, so it honestly resets with the derivation. The compact `revisions` ledger carries the part with lasting value — which passages changed when, old/new shas. The loader writes both: catalog provenance for everything, one ledger row per content transition of an *existing* row (inserts — including every rebuild replay — write nothing durable, so rebuilds leave the ledger byte-identical).
- Runs carry `kind`: rebuild replays are honest history but re-add the whole corpus, so trend queries (health, sync deviation warnings) read `kind=sync` only; `status` shows the latest run of any kind.
- Phase 8 (enrichments — paid API output that must survive rebuilds): the enrichment journal lives in the ledger, urn-keyed like `revisions` (passage urn + kind + model identity), and `nabu enrich --replay` re-applies it into the catalog after a rebuild. The identity scheme above is the contract; the tables land with Phase 8.
- Migration tracks are per-db and forward-only: `db/migrate/` for the catalog, `db/ledger_migrate/` for the ledger — each SQLite file keeps its own `schema_info`, so the counters cannot collide. One-shot lift-and-shift: every write path opens the ledger via `Ledger.open_with_lift!`, which copies a pre-P7-1 catalog's runs/pins/baselines into the ledger (re-keyed by slug/url) and only then migrates the catalog forward (005 drops the moved tables). A fresh machine with no ledger bootstraps clean: read paths treat the absent file as empty history ("no run history", never an error); the first sync creates it.
- FTS5 external-content table over `text_normalized` + trigram tokenizer option for scripts where word segmentation is unreliable.
- `passage_lemmas` (P7-5, alongside the FTS table in fulltext.sqlite3, same drop-and-rebuild lifecycle): the gold-treebank lemma index — one row per (passage, folded lemma) extracted from the catalog's stored `annotations_json` (never by re-parsing canonical), with the distinct surface forms aggregated for display. Lemmas fold per language exactly like `text_normalized` (conventions §9); `search --lemma` matches the query-forms union. The pattern for future annotation-derived indexes (Phase 8 enrichment output).
- `vectors.sqlite3`: one table per `(embedding_model, version)` — model upgrades create a new table, old one dropped only after re-embed completes.
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

- **The retention contract (the attic).** If upstream scraps a document — deletion, license change, disagreement — local storage marks it and KEEPS it usable. Git-based fetch is non-destructive (`Nabu::GitFetch`): `git fetch` first (objects only, working tree untouched), then each file the `HEAD..FETCH_HEAD` diff deletes is copied to `canonical/<slug>/.attic/<same relative path>` before the ff-only merge. First copy wins — an attic file is never overwritten — and a per-attic `.attic.json` manifest records the upstream sha each file vanished at. The attic lives *inside* canonical/, so `db = f(canonical)` holds unchanged: every rebuild replays attic documents (as `retired_upstream` rows with "retired" provenance carrying that sha). Renames are not scrapping (`--find-renames` is explicit): content surviving at a new path is not atticked. Retired documents stay fully live — indexed, searchable, exportable — and `status`/`show` label them; only intra-document edition changes stay revision-journaled (an upstream typo fix is not scrapping). Out of scope, deliberately: a revised passage's *old text* is journaled by sha only (not stored), and the attic protects against upstream loss, not local disk loss — backups remain the answer there.
- **The HTTP-zip fetch path (`Nabu::ZipFetch`, P10-1) honors the same contract.** ORACC ships per-project zips over plain HTTP (no upstream git repo), so a second fetch implementation exists — with attic parity, deliberately mirrored phase for phase: download + unpack to a private staging dir first (live tree untouched), doomed files = live files absent from the fresh unpack, guard between the phases (raising aborts byte-unchanged), then attic-before-delete with the SAME `.attic.json` manifest format (rel path → the sha256 of the zip build the file vanished at — the FETCH_HEAD analog, and the sha `FetchReport` pins), first copy and first record win, then the staged tree swaps in. Change detection is `Last-Modified`/`If-Modified-Since` (a `.zip-fetch.json` state file per project dir; 304 = tree current, nothing touched). Zip handling shells out to the system `unzip` via `Nabu::Shell` — no zip gem. The remote health probe is strategy-keyed per source (P11-2, `Adapter.remote_probe_strategy`): git sources `ls-remote`, HTTP-zip sources (ORACC) HEAD each project zip for reachability + `Last-Modified` drift vs the stored `.zip-fetch.json` pin and GET each `metadata.json` for license drift, both through ZipFetch's vendored-cert path — so ORACC reads honestly (reachable / never-synced / drift), not gone.
- **The mass-deletion breaker runs BEFORE the merge.** The fetch layer predicts from the deletion diff: the fraction of the source's currently ingestible files (what `discover` yields from the untouched tree) among the doomed paths. Above 20%, `Nabu::SyncAborted` — with the canonical tree byte-unchanged (no merge, no attic writes). `--force` proceeds: files are atticked, documents retired, nothing is lost. A second, load-side guard in SyncRunner (same threshold, urns in the catalog vs `discover_with_attic` ids) still covers `--parse-only` runs and non-git adapters; attic documents count as present there, never as pending withdrawals.
- Every sync (and every rebuild replay, kind-tagged) writes a `FetchReport` + `LoadReport` (counts: added/updated/withdrawn/errored) to the ledger's `runs` table, slug-keyed; `nabu status` and `nabu health` read it — continuously across rebuilds, because the ledger survives them (P7-1). The remote probe's license baselines and per-repo pins live on the ledger's `pins` rows for the same reason: a rebuild must not open a license-drift blindspot.
- Parse errors quarantine the document (recorded, skipped), never abort the batch.
- `nabu verify` re-hashes canonical files (attic included) against the catalog — bitrot/tamper check, cronnable.
- Backups: canonical/ is git (bare mirror on nero/nexo via Tailscale); the derived dbs (catalog/fulltext/vectors) are disposable but nightly-snapshotted anyway (cheap). db/history.sqlite3 is NOT disposable — it is the only copy of run history, pins, baselines, and durable revisions, and belongs in every backup alongside canonical/ (P7-2 makes this operational).

## 9. The MCP read-only surface

`lib/nabu/mcp/` exposes the corpus conversationally — to Claude Code and any
MCP client — and rehearses the eventual `nabu.ac` read-only endpoint
(concept §"eventual read-only query endpoint"). Hand-rolled, no gem (owner
decision: the field moves fast, we keep control; the conformant core is
~150 lines).

- **Protocol** (`mcp/server.rb`): JSON-RPC 2.0 over stdio per MCP spec
  revision **2025-11-25** (pinned as `Server::PROTOCOL_VERSION`; researched
  2026-07 against the spec and the Claude Code 2.1.x client). Framing is
  newline-delimited JSON — one UTF-8 object per line, no Content-Length
  headers, no batching (removed in spec 2025-06-18). Handles `initialize`
  (version negotiation by counter-offer), `notifications/initialized` (all
  notifications swallowed silently), `ping`, `tools/list`, `tools/call`;
  `-32601` for everything else; malformed lines answer `-32700` without
  killing the loop. Unknown tool → `-32602` protocol error; semantically bad
  tool arguments → a tool result with `isError: true` (spec SEP-1303: models
  self-correct from tool errors, not protocol errors). The core is driven by
  injected IO/lines; the real stdin/stdout wiring (and stderr logging) is the
  `bin/nabu mcp` entrypoint's job (P8-2). stdout carries protocol messages
  ONLY.
- **Tools** (`mcp/tools.rb`): `nabu_search` (full-text XOR lemma, lang/
  license/limit), `nabu_show` (passage/document/range urn, `parallel`),
  `nabu_status` (coverage: sources, counts, languages, license classes,
  last-sync recency — what makes "no results" interpretable). Translation
  only: all query logic stays in `lib/nabu/query/`. The tool table is a hash;
  P8-3 adds `nabu_concord` as one entry + handler.
- **The contract**: every returned passage carries urn + language +
  license_class + source; outputs are bounded with honest "N total, showing
  k" notes; no-match searches carry a one-line coverage hint;
  `research_private`/`restricted` classes are excluded from every tool unless
  `include_restricted: true` is passed explicitly (forward-looking: nothing
  synced carries them yet, but the ad-hoc pipeline will — a conversational
  surface must never leak that material casually).
- **Read-only, positively**: connections are opened with
  `Store.connect(..., readonly: true)` (SQLITE_OPEN_READONLY — the engine
  refuses writes, not just our code). Corpus states degrade to normal tool
  responses, never crashes: missing catalog → "no corpus", missing FTS table
  (the mid-reindex window) → "index rebuilding — retry shortly", SQLITE_BUSY
  → brief retry then the same graceful shape. No write tools exist in this
  phase, deliberately.

## 10. The alignment hub — one work across sources (P11-3)

`nabu align "MARK 2.3"` renders the same verse in every witness the corpus
holds — the flagship is the five-way parallel New Testament (PROIEL greek-nt
grc · latin-nt lat · gothic-nt got · armenian-nt xcl · TOROT-family marianus
chu, all under the proiel source). This section records the design decisions
and the upstream reality they answer to.

**The citation reality (verified against the live catalog, 2026-07-09).**
PROIEL passage urns are *sentence ids* (`urn:nabu:proiel:greek-nt:6563`),
not verses — suffix-equality alignment (§3, Query::Parallel) is structurally
impossible across these witnesses. Verse identity lives in the stored
annotations: every token carries `citation_part` ("MARK 2.3"), lifted by
ProielParser into `annotations_json`; the passage-level `citation` field is
only the *first* token's part. Sentence↔verse is honestly many-to-many (846
greek-nt sentences span a verse boundary; a verse is often several
sentences). The five witnesses share one book vocabulary (MATT, MARK, …),
but refs are meaningful only *within* a work — PROIEL's Cicero cites a
bookless "1.1" — and not every ref is numeric (Gothic carries
"MARK Incipit.0"). Coverage is fragmentary per witness (Armenian holds only
sampled chapters; John 1:1 is absent from Gothic and Marianus), so absence
must render honestly, never fuzzed.

**Registry + derived ref index, not materialized pairs.** The declarative
side is `config/alignments.yml` (Nabu::AlignmentRegistry, validated loudly
on load like sources.yml): works keyed by id (`nt`, `ot`), each listing its
witnesses — one document urn (`document:`) or, since P11-5, a per-book
document map (`documents:`, work-vocabulary book token → urn: the shape of
an edition minted one-document-per-book), plus citation `extractor`,
optional `books:` alias map and display `label`. Adding a witness is a
registry entry, never code. The
materialized side is ONE derived table, `alignment_refs` in
fulltext.sqlite3: one row per (work, normalized ref, passage) — (work, ref,
document_urn, passage_id, passage_urn, seq) — built by the Indexer from the
catalog's stored `annotations_json` (never by re-parsing canonical), exactly
the P7-5 passage_lemmas pattern: same drop-and-rebuild lifecycle, same
"not a migration" stance, same file. Materialized passage *pairs* were
rejected: pairs are O(witnesses²) rows that go stale the day a sixth
witness lands, while ref rows are O(passages) and the N-way pairing is a
query-time GROUP BY ref. The catalog schema is untouched.

**Citation normalization.** A ref is an opaque string scoped to its work,
folded identically on both sides (the §9/P6-4 contract again):
whitespace-collapsed, uppercased, `:` → `.` — so a query spelled
"Mark 2:3" finds rows indexed "MARK 2.3". A witness whose book tokens
differ maps them in its registry `books:` alias table at index time;
non-verse refs (Incipit.0) fold and index like any other and stay
addressable. Extractors are a CLOSED, registry-validated set of two:
`proiel-citation` (P11-3: the distinct per-token citation_part values of a
sentence; multi-verse sentences index one row per verse covered) and
`cts-verse` (P11-5: the witness's registry book token + the passage urn's
citation tail — `…tlg0527.tlg001.1st1K-grc1:1.2` under `GEN:` indexes
"GEN 1.2" — for verse-grain editions whose verse identity IS the passage
urn; no annotations read). cts-verse requires the `documents:` witness form
(the book token comes from the registry, since a per-book document's urn
tails are bookless); a single-chapter book's flat tail folds to "LJE 5" and
stays addressable, the Incipit stance again.

**Rebuild-safety.** The registry is config — canonical-adjacent, in git, in
the backup set, untouched by rebuild. The index is a pure function of
(catalog, registry) and is rebuilt inside every `Indexer.rebuild!` (both
call sites: SyncRunner#reindex!, Rebuild) — so `nabu rebuild` regenerates
alignment for free, id re-minting and all (the index carries re-minted
passage_ids precisely because it is dropped and rebuilt with them). No
hand-curated rows exist anywhere in db/.

**Query surface: a new `align` subcommand.** `nabu align REF [--work ID]`
(REF may also be a passage urn, pivoting from a show/search hit into its
verse). A new subcommand rather than `show --align` or an extension of
`--parallel`, deliberately: show/--parallel take a *urn* and resolve
CTS-sibling editions by suffix equality — a different mechanism with
document-lookup semantics — while align takes a *citation* and resolves the
registry; forcing one onto the other would conflate the two lookup models.
Query::Parallel stays what it is (within-source translation pairing);
Query::Align is its cross-source sibling. Output: the witnesses in registry
order, each with title, language, EFFECTIVE license class (override ∘
source class, resolved at query time — never stored in the index), and its
sentences in sequence order, labeled with the full ref span when a sentence
covers more verses than the one asked for. A registered witness absent from
the catalog renders as "not synced" (the day-one state of the OE Mark
entry); a synced witness lacking the verse renders "not attested".

**MCP surface: `nabu_align`.** One more entry in the §9 tool table, same
contract: every sentence row carries urn + language + license_class +
source (the five NT witnesses are all `nc` — the labels are the point),
bounded output, research_private/restricted witnesses withheld unless
`include_restricted`, corpus states degrade gracefully (missing
alignment_refs table → "alignment index not built — run nabu sync or nabu
rebuild").

**How later witnesses plug in.** ISWOC's OE Gospel of Mark (P11-1: PROIEL
XML 2.1, native `citation-part="MARK 1.1"`) is one registry entry under
`nt` with the same `proiel-citation` extractor — zero code, and the hub
renders for Mark the day the adapter syncs. The P11-5 biblical trio landed
exactly as forecast — entries plus the one `cts-verse` extractor: `nt`
gained SBLGNT (CC BY, 27 per-book documents) and the Clementine Vulgate's
NT books (public domain), and a new `ot` work pairs the LXX (Swete —
ALREADY in the catalog as First1KGreek tlg0527, verse-grain CTS urns; the
registry-only witness) with the Vulgate's OT books. A multi-document
witness renders as ONE column: the hit book's document heads it
(title/urn), a miss shows the label alone (no arbitrary book title), and
"not synced" appears only when none of its documents are live. GRETIL
commentary layers are a *new work* with its own ref scheme (works are
independent namespaces; nothing NT-shaped is hardcoded). Versification
swamps (LXX-vs-Masoretic) stayed out of scope through P11-8 by the same
scoping: a work's witnesses must share a citation scheme, and whoever
registers a witness owns that claim — the `ot` registrar's claim rests on
both witnesses following the Greek tradition (Vulgate Psalms are numbered
after the LXX, so "PSA 22.1" is the shepherd psalm in both).

**Facing versification: the `numbering:` remap (P13-5).** The `psalms` work
finally faces the divergence the `ot` work sidestepped by omitting the WEB
psalter. Its vocabulary is the Greek/LXX numbering the Septuagint and
Vulgate share (so "PSA 22.1" is the shepherd psalm); the World English Bible
is Hebrew/Masoretic-numbered (its "23.1" is that same verse). A new
OPTIONAL per-witness key, `numbering:`, carries a `system:` provenance label
plus a `ranges:` list of piecewise-linear rules — each `{from, to, shift}`
maps a span of the witness's leading citation segment (the psalm number)
into the work vocabulary. It is a second witness-local transform in
`Witness#normalize_ref`, applied AFTER the `books:` alias, and — like
`books:` — INDEX-SIDE only (the query already speaks the work vocabulary).
The one genuinely new power: a psalm NO rule covers returns nil, which
DROPS the ref (the indexer's compact/filter_map skip it). This is the
honesty the divergence demands — the psalms the LXX joins or splits (Hebrew
9, 10, 114, 115, 116, 147) map onto no single Greek number, so rather than
false-align onto a Greek psalm they do not equal, the witness simply renders
"not attested" there (verified: querying Greek 113, the Hebrew 114+115 join,
shows the two Greek-tradition witnesses and an honest WEB miss). The
extractor set stays closed at two — `numbering:` is orthogonal to how a ref
is EXTRACTED. The remapped witness's OWN ref is recovered at query time from
the passage urn (never stored) and surfaced on the aligned row ("WEB … ·
Hebrew (Masoretic) numbering" / "[Hebrew (Masoretic): PSA 23.1]"), so the
divergence is visible, not silently corrected. The mapping table's
provenance is the standard LXX↔Masoretic psalm concordance (Rahlfs'
Septuaginta front-matter, NETS, the Douay/Vulgate-vs-Hebrew tables — all in
agreement, cross-checked live against the corpus). SCOPE HONESTY: the remap
corrects the PSALM number only; verse numbering WITHIN a psalm can also
differ (LXX/Vulgate fold a Hebrew superscription into verse 1, the English
does not), a disclosed residual left uncorrected rather than fabricated
away. The OE Paris Psalter (ASPR A5.51–A5.150) was a candidate fourth
witness but is DEFERRED with evidence: the ASPR adapter numbers passages by
the printed POETIC LINE (the psalm number lives in the per-psalm document
id, not the passage tail), and one Latin verse becomes several Old English
metrical lines, so its citations do not support verse alignment without a
hand-built line→verse concordance the corpus does not have — registering it
would either fabricate pairings or add a column that never co-renders. The
shipped-registry pin test (`test/alignment_registry_test.rb`) grew a `psalms`
case openly as the schema gained `numbering:`.

**The CCMH gospels — the Old Church Slavonic manuscript comparison (P14-2).**
The `nt` work grows from nine witnesses to thirteen: the four CCMH gospel
manuscripts (Corpus Cyrillo-Methodianum Helsingiense — Codex Assemanianus,
Codex Marianus, Savvina kniga, Codex Zographensis) join as `documents:`
cts-verse witnesses, one document per gospel, the work-vocabulary book token
(MATT/MARK/LUKE/JOHN) keying the CCMH per-book urn
(`urn:nabu:ccmh:marianus:mar`), their verse identity the passage-urn tail —
pure registry entries, no new extractor, the P11-5 shape exactly. All four
manuscripts hold all four gospels (verified read-only against the live
catalog), so `align "MARK 2.3"` renders up to thirteen witnesses and the
flagship five-way parallel becomes a thirteen-way one; verse coverage stays
honestly fragmentary per witness (the lectionaries Assemanianus and Savvina are
sparse — "not attested" per the P11-9 machinery). Two of the four are
ALTERNATIVE EDITIONS of witnesses the corpus already holds — CCMH Marianus
beside PROIEL `marianus` (the fifth witness), CCMH Zographensis beside TOROT's
— so each CCMH label carries the "CCMH" prefix to render distinguishably: one
`align` command puts the two Marianus editions (the PROIEL treebank's Cyrillic
beside CCMH's Helsinki transliteration) side by side, the alt-edition showcase
(two editions are two versions, never a dedupe, conventions §3). One empirical
wrinkle drove the ONE code change to the otherwise-closed cts-verse extractor:
the continuous-text codices (Marianus, Zographensis) mint CHAPTER-0 refs
(`…:0.N`) for the kephalaia — the chapter-title lists and gospel incipits —
which are manuscript APPARATUS, not running gospel text, and which cross-align
spuriously between manuscripts (Marianus and Zographensis both number their
Luke kephalaia `0.N`). So `cts_verse_refs` now DROPS a leading chapter-0
segment: Bible chapters are 1-indexed, no verse-grain witness legitimately
cites a chapter 0 (verified — LXX/Vulgate carry none), and a verse-0
superscription (`…:3.0`) keeps its non-zero chapter and stays. The drop is
INDEX-side only — the kephalaia remain canonical, addressable passages via
`nabu show`/`search`; only the verse-alignment index excludes them. The
`:b2`/`:b3` duplicate-verse suffixes CCMH mints for lectionary parallels need
NO handling: the generic `:` → `.` fold turns `13.11:b2` into a distinct
`13.11.B2` ref, so a duplicate never false-aligns onto the primary verse (it
renders only under its own explicit ref). The pin test grew the four CCMH cases
openly.

## 11. The dictionary shelf — lexica as data (P11-4)

`nabu define μῆνις` prints the LSJ entry — gloss, sense tree as structured
plain text, and every citation the entry makes, resolved to in-catalog
passage urns where the cited work is here (`Il. 1.1 →
urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1` — one `nabu show` away).
Two dictionaries ship: LSJ (grc) and Lewis & Short (lat), both from
PerseusDL/lexica (CC BY-SA 4.0 → attribution class). This section records
the design decisions.

**Dictionaries ARE sources — with a declared content kind.** The lexica are
a registry source like any other (`lexica` in sources.yml): canonical data
under `canonical/lexica/`, fetched by GitFetch with the attic and the
mass-deletion breaker, reconciled/pinned/journaled through the same ledger
machinery, probed by health like every git source. What differs is only the
load shape, declared once on the adapter — `Adapter.content_kind`, default
`:passages`, overridden to `:dictionary` — and routed on in exactly two
places (SyncRunner#load, Rebuild#replay): dictionary sources load through
`Store::DictionaryLoader` instead of the passage Loader. A parallel
fetch/sync mechanism was rejected: it would duplicate retention, breakers,
run recording, pins and probes to avoid one routing conditional. The
adapter's parse returns `Nabu::DictionaryDocument` (one FILE's entries —
LSJ ships 27 letter-split files) — never passages, so dictionary entries
can never flood full-text search. The passage-shaped conformance suite
cannot apply; the lexica adapter test mirrors its checks for the dictionary
shape (manifest, round-trip, id uniqueness/stability, NFC).

**Storage: catalog tables, by migration.** Entries are first-class
derived-from-canonical data with the same idempotency/revision/withdrawal
semantics as documents — upsert on (dictionary, entry_id), skip on equal
content sha, revise+bump on change, withdraw on full-load absence, journal
to provenance (new nullable `dictionary_entry_id`) and to the durable
ledger under urn `urn:nabu:dict:<slug>:<entry_id>`. That is
catalog-shaped, so migration 006 puts `dictionaries`, `dictionary_entries`
and `dictionary_citations` in catalog.sqlite3. NOT fulltext.sqlite3: that
file holds disposable derived-of-derived indexes (drop-and-rebuild, no
revision history); parking the primary copy of entry bodies there would
invert the layering. NOT a new db file: "one file per concern" cuts at
real concerns, and entries are the same concern as documents — a fourth
file would add connection plumbing through every CLI/MCP entry point for
no boundary. Rebuild-safety is free: `nabu rebuild` drops the catalog and
replays `canonical/lexica/` through the same loader (pinned by test:
byte-identical entries and citations across two rebuilds).

**Betacode at the boundary.** LSJ's Greek — keys, orths, quotes — is TLG
betacode ("mh=nis"); Lewis & Short's Unicode variant (eng2) is ingested and
its betacode twin (eng1) skipped. `Nabu::Betacode` (table-driven, no gem)
decodes at the adapter boundary like every other text normalization:
canonical mark ordering, NFC output, positional sigma. Headwords key the
shelf FOLDED — `headword_folded = Normalize.search_form(decoded key,
dictionary language)`, hyphens and homograph digits stripped — the same
both-sides contract as lemma search (conventions §9), which is exactly what
lets a treebank lemma hit carry its dictionary gloss (`search --lemma
officium` shows "a service" — Query::Define#glosses, one batched lookup,
dictionary language must match the lemma's).

**Citation resolution — query time, best effort, honest misses.** The 2014
upstream revision put CTS urns in `bibl/@n`; the parser keeps each verbatim
(`urn_raw`) and derives the resolution keys: a work-level prefix
(`urn:cts:greekLit:tlg0012.tlg001` — upstream EDITION tokens are dropped,
because LSJ cites perseus-grc1 while the catalog holds grc2) and a
dot-joined citation ("1.1"). Resolution happens at QUERY time, never at
load: works sync after dictionaries and vice versa, rebuilds re-mint ids,
and nothing stale may be stored (the §10 stance again). A citation resolves
iff an in-catalog edition of the work has that passage urn — original
language preferred over translations, then urn order for determinism; a
3+-part citation that matches nothing retries once as (first, last), the
classical chapter/section double citation ("Cic. Off. 1, 2, 4" is book 1,
chapter 2, CONTINUOUS section 4, while Perseus editions cite book.section —
the fallback lands on the exact quoted passage, verified against the real
text; a genuinely 3-level edition always wins with the exact form first).
Everything else — URN-less bibls (inscriptions, AP), non-CTS values
("Dig. 33.6.9"), malformed upstream urns (`…:Orat::2:27:120`), works not
ingested — stays as display text with a nil resolution: a lexicon's
citations are best-effort by upstream reality, and the miss-rate is honest,
never fuzzed.

**Query surface: `nabu define` + MCP `nabu_define`.** The CLI prints
entries whole (the λόγος entry is ~300 KB of text — the CLI is the
unbounded surface) with the license label on every entry header and
resolved citations listed for the `nabu show` handoff. `nabu_define` is the
sixth MCP tool, same contract as the rest: license fields on every entry,
bounded body (6 000 chars, honest truncation note pointing at the CLI),
bounded citations (resolved first), research_private/restricted shelves
withheld unless `include_restricted`, and graceful states (no catalog / no
shelf yet → "run nabu sync lexica").

**How a third dictionary plugs in — done (P12-3, Bosworth-Toller).** The
schema is deliberately language-agnostic (dictionaries.language is a
column, entries fold by it), and the plug-in went exactly as designed:
Bosworth-Toller (Old English; docs/oe-survey.md: official CC BY 4.0 LINDAT
dump, CSV `id;headword;body` with project-XML bodies) is its own registry
source with a small CSV adapter (`BosworthToller` + the `bosworth-csv`
parser family — the first non-TEI dictionary) — same `content_kind
:dictionary`, same DictionaryDocument/Entry model, dictionary slug
`bosworth-toller`, language `ang`, betacode off — and `define`/glosses
worked unchanged (the only edits outside the adapter were widening the
CLI/MCP `lang` gates to `ang` and the conventions §9 ang fold: æ→ae,
þ/ð→th, so `define aethele` reaches æðele from an ASCII keyboard). Entry
ids are the dump's CSV ids (`urn:nabu:dict:bosworth-toller:940` ↔
`bosworthtoller.com/940`). Its bodies cite OE works by short title without
urns, so its `dictionary_citations` start empty until a crosswalk to
ISWOC/ASPR urns exists; the resolution layer needed nothing new. Fetch is
the ASPR FileFetch path (one ~84 MB CSV, DSpace bitstream `/content` URL).
A second dictionary from the SAME repo (Middle Liddell lives beside LSJ
upstream) is one entry in the lexica adapter's DICTIONARIES map.

**The fourth occupant brought the third format (P13-10, Wiktionary-OCS).**
kaikki.org's wiktextract JSONL (one JSON object per line, one record per
word × POS × etymology; dual "CC-BY-SA and GFDL" → attribution) plugs in
as `WiktionaryCu` + the `wiktionary-jsonl` parser family: slug
`wiktionary-cu`, language `chu`, FileFetch single-file path (~44 MB), same
Entry model, `define`/glosses again unchanged (only the CLI/MCP `lang`
gates widened to `chu`; the fold is the generic rule — no §9 entry needed,
Cyrillic combining marks are `\p{Mn}`). Two format-specific decisions:
kaikki records carry NO stable upstream id, so entry ids are minted
`<word>:<pos>[:<etymology_number>]` with a positional `:n` suffix for the
handful of residual collisions (stable while upstream file order is; a
reorder is an ordinary revision); and `etymology_text` is deliberately
KEPT at the head of every entry body — those Proto-Slavic/PIE chains are
the seed data for a future reconstruction/etymology shelf (see the
improvements register). Citations start empty (Wiktionary quotations are
unanchored — the B-T precedent).
