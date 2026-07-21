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

`nabu rebuild --incremental` (P36-1) is an optimization OVER this invariant, never a relaxation of it: the full rebuild remains the reference semantics, and an incremental run must land content-equivalent to a fresh full rebuild of the same canonical tree (test-pinned: counts + content shas). Each replay stamps the source with its derivation fingerprint (`derivation_stamps`, in the catalog — dropped and re-stamped by every full rebuild, correct by construction); `--incremental` keeps the catalog, skips fingerprint-clean sources, and re-derives dirty ones through the same replay seam + per-source index refresh. See §5 (derivation stamps bullet) for the fingerprint inputs and refusal rules.

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
│   ├── fulltext.sqlite3         # DERIVED: FTS5 + passage_lemmas + trigram index (all keyed by passage id)
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
- **The NFC invariant, and its one named exception (P26-3, owner ruling 2026-07-18).** `text` is NFC Unicode, normalized once at the adapter boundary (`Nabu::Normalize.nfc`) and *refused* non-NFC by `Passage` construction — for every language **except Biblical Hebrew and Biblical Aramaic** (`Normalize::NFC_EXEMPT_LANGUAGES = ["hbo", "arc"]`). NFC canonical ordering *reorders* Hebrew combining marks (dagesh/shin-dot ccc 21/24 vs vowel points ccc 10–19), silently rewriting the Masoretic mark order the Westminster Leningrad Codex ships; upstream OSHB warns against NFC outright, and the warning is measured-true (Ruth 1:1 is not NFC-stable — the pinned regression fixture). So `hbo`/`arc` text is stored **byte-verbatim exactly as upstream ships it**: `Passage` validates UTF-8 well-formedness only, and the adapter conformance suite asserts the same seam, keyed on the central exemption list so no adapter can quietly opt another language out. Find-ability is unaffected — `text_normalized` and query folding pass through NFC + mark strip on the search side regardless (an unpointed `בראשית` finds the pointed verse). Content hashing still works: the WLC is internally mark-order-consistent, so one text remains one byte sequence within the shelf. See conventions §1. The exemption extends to the dictionary shelf (P30-1): `DictionaryEntry` headword/gloss/body in an exempt language are validated verbatim-UTF-8, not NFC (measured on the OSHB lexicon: 4,053 LexicalIndex / 3,796 HebrewStrong / 4,720 BDB headwords are not NFC-stable), while `headword_folded` — the minted search form — stays NFC for every language.
- **Parser families as components.** `EpidocParser`, `ProielParser`, `ConlluParser`, `AtfParser` are standalone, individually tested classes; adapters are thin compositions (Perseus ≈ EpidocParser + repo layout knowledge + URN extraction). New source in a known family ≈ 100 lines.
- **Idempotency via content hashing.** Loader upserts on `urn`; a passage row stores `content_sha256`. Unchanged content is skipped; changed content bumps `revision` and journals the old hash. Deletions upstream mark rows `withdrawn`, never hard-delete.
- **Upstream deletions never destroy local data.** Git-based fetch attics the deleted file (§8); the adapter base rediscovers attic documents generically (`Adapter#discover_with_attic` — subclasses implement only `discover`, a urn found both live and in the attic resolves live-wins) and the loader marks them `retired_upstream` — live, searchable, exportable. `withdrawn` keeps meaning "absent from canonical entirely".
- **Fetch is separated from parse** so tests never need network and `nabu sync --parse-only` can re-run after parser fixes without re-downloading.
- **Parallel translations are a per-source opt-in (P7-4).** `translations: true` in `sources.yml` reaches the adapter through `SourceRegistry::Entry#build_adapter` — the one construction seam sync/rebuild/verify share; no-arg `.new` stays every adapter's contract and the default. A translations-on Perseus additionally ingests the highest `perseus-eng<n>` edition per work as an ordinary document (language `eng`, its own edition urn, same license); the shared CTS citation scheme makes passage alignment a pure query (`Query::Parallel`, `nabu show <urn> --parallel [lang]` — suffix-equality pairing, unmatched suffixes shown one-sided). ORACC is the second sibling family (P13-4): a translations-on Oracc crawls the official per-text HTML fragments (project-scoped: `Oracc::TRANSLATION_PROJECTS` — SAA-first staging; stage 2 = the full project list since P14-4, the tr-en metadata gate keeping translation-less projects inert) and mints `-en` sibling documents whose passage suffixes are the tablet's own line labels; `Query::Parallel`'s work notion covers both shapes (CTS work prefix + edition slug; ORACC tablet urn + `-<variant>`), and the translation prose carries `license_override: "attribution"` (CC BY-SA project content) while the source stays CC0/open. **The work notion is a registry declaration, not a code chain (P34-0):** what counts as a sibling is the source row's `siblings:` key — `cts` (the dotted-version form) or a list of `"-"`-leading variant-tail patterns (`["-en"]`, `["-(eng|ita|dipl)"]`, the ORACC `["-[a-z]+"]` open run) — compiled by `Query::SiblingFamilies` into the ONE generic matcher `Query::Parallel` consults. The ten per-source frozen regex constants that used to live in `Parallel` (CTS, ORACC, Freising, Damaskini, SuttaCentral, TLA-HF, AES, RIIG, OpenEtruscan+ItAnt, ETCSL — each new sibling shape an owner repro + a code rider through P29/P30/P32) retired into declarations; a declared tail is a **census claim** (no upstream id ends in it — exactly what each constant's comment used to freeze). I.Sicily is the eleventh family: `["-en", "-it", "-translit"]` — the `-translit` layer sibling (the Latin-script rendering of a Greek-script carving, suffix-equal to the primary, reachable by explicit `--parallel <lang>`, the ItAnt `-dipl` stance) plus the `-en`/`-it` prose translations (whole-text coarse blocks anchored at the primary's first line via a synthesized `corresp`, the ETCSL loose-alignment mechanism). The sibling grammar is a **global installation fact** (`SiblingFamilies.default` reads the installation's own `sources.yml`, not a redirected-catalog config).

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
        enabled, last_sync_at, last_sync_sha)   -- enabled + last_sync_* are display mirrors;
                                                -- sources.yml owns enabled (read surfaces
                                                -- render registry truth, P23-3), the ledger
                                                -- owns the authoritative pins
documents(id, source_id, urn, title, language, edition, license_override,
          canonical_path, content_sha256, revision, withdrawn, retired_upstream)
passages(id, document_id, urn, sequence, language, text, text_normalized,
         annotations_json, content_sha256, revision)
provenance(id, passage_id, event, tool, tool_version, model, params_json, at)
enrichments(id, passage_id, kind, model, model_version, payload_json, at)
   -- lemmas, glosses; embeddings live in vectors.sqlite3 keyed by passage id
language_names(id, dictionary_id, lang_code, name, occurrences)
   -- P18-4: the derived language-name census — what kaikki's descendants
   -- nodes call each lang_code, counted RAW per reflex-bearing dictionary
   -- (written wholesale by DictionaryLoader; the read side filters wrapper/
   -- placeholder names and takes the mode). Feeds `nabu language`.
language_records(id, lang_code, kind, body, source)
   -- P19-1: the derived index of the canonical/local-language dossier shelf
   -- (§16) — one row per (code, kind) lane as the dossier currently states
   -- it (curated name/family/context + front-matter extras + accretion
   -- sections), `source` the per-record provenance ("dossier", "iecor",
   -- "liv"). Replaced per code by LanguageDossierLoader at every
   -- local-language sync/rebuild (and incrementally by the LanguageShelf
   -- accretion path). Feeds `nabu language` ahead of the transitional
   -- ledger notes below.
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
language_notes(id, lang_code, kind[name|family|context|…], body, source,
               created_at)
   -- P18-4, TRANSITIONAL since P19-1: the accumulated per-language layer's
   -- retiring first home. The canonical-memory migration (§16) rehomes
   -- authored language knowledge into canonical/local-language/ dossier
   -- FILES; this table is read only as the per-(code, kind) FALLBACK where
   -- no derived language_record exists (a library whose owner has not yet
   -- fired `nabu language --export-dossiers` serves exactly what it served
   -- before), and is written by NOTHING anymore (the P18-5/6 accretion
   -- writers redirect to dossier sections via Nabu::LanguageShelf; the
   -- config/languages.yml seed and `--seed` are retired). A later packet
   -- drops the table once export parity is verified — the drop cannot ride
   -- P19-1 because every write path auto-migrates the ledger on open, which
   -- would destroy the notes before the owner ever exported.
```

- Why the split: everything in the ledger is runtime HISTORY, not a function of canonical/ — pre-P7-1 it lived in the catalog and every rebuild amnesia'd health trends, license-drift baselines, and repo pins. Keying is by slug/url/urn because rebuilds re-mint all catalog ids.
- Provenance is deliberately NOT durable (decision, P7-1): it journals per-load noise ("loaded" × 60k docs per rebuild replay, "quarantined", "superseded") that describes the *derivation*, so it honestly resets with the derivation. The compact `revisions` ledger carries the part with lasting value — which passages changed when, old/new shas. The loader writes both: catalog provenance for everything, one ledger row per content transition of an *existing* row (inserts — including every rebuild replay — write nothing durable, so rebuilds leave the ledger byte-identical).
- Runs carry `kind`: rebuild replays are honest history but re-add the whole corpus, so trend queries (health, sync deviation warnings) read `kind=sync` only; `status` shows the latest run of any kind.
- Phase 8 (enrichments — paid API output that must survive rebuilds): the enrichment journal lives in the ledger, urn-keyed like `revisions` (passage urn + kind + model identity), and `nabu enrich --replay` re-applies it into the catalog after a rebuild. The identity scheme above is the contract; the tables land with Phase 8.
- Migration tracks are per-db and forward-only: `db/migrate/` for the catalog, `db/ledger_migrate/` for the ledger — each SQLite file keeps its own `schema_info`, so the counters cannot collide. One-shot lift-and-shift: every write path opens the ledger via `Ledger.open_with_lift!`, which copies a pre-P7-1 catalog's runs/pins/baselines into the ledger (re-keyed by slug/url) and only then migrates the catalog forward (005 drops the moved tables). A fresh machine with no ledger bootstraps clean: read paths treat the absent file as empty history ("no run history", never an error); the first sync creates it.
- FTS5 external-content table over `text_normalized` + trigram tokenizer option for scripts where word segmentation is unreliable.
- `passage_lemmas` (P7-5, alongside the FTS table in fulltext.sqlite3, same drop-and-rebuild lifecycle): the lemma index — one row per (passage, folded lemma) extracted from the catalog's stored `annotations_json` (never by re-parsing canonical), with the distinct surface forms aggregated for display. Lemmas fold per language exactly like `text_normalized` (conventions §9); `search --lemma` matches the query-forms union. The pattern for future annotation-derived indexes (Phase 8 enrichment output). Each row carries a `tier` (P26-0; declared per source via `lemma_tier:` in sources.yml, validated against `SourceRegistry::LEMMA_TIERS`): **gold** — verified annotation, the default, the only tier that ever counts as attestation (`attested_count` everywhere means gold); **silver** — upstream-automatic lemmatization (Diorisis/TLHdig/CDLI/eBL), labeled at every render, `--gold-only` excludes; **equivalence** (P34-3, owner-decided as DISTINCT from silver) — scholar-curated cross-language equivalence: CEIPoM's `Classical_Latin_equivalent` values mint LATIN keys (folded and labeled `lat`, read from the `latin_equivalent` token key, never from `lemma`) on the non-Latin passages, so `search --lemma precor` reaches the Iguvine Tables' `pesnimu`. Curated but never attestation in the key's language and never automatic — a different honesty, so its own label at every tier-rendering surface: per-hit `[equivalence]` tags + footer totals in `search --lemma`/`concord` (CLI and MCP), an `equivalence_count` beside — never inside — `attested_count` in ReflexViews/define/etym, and the gold-scoped consumers (cognate closure, language cards, vocab reference corpus) exclude it via their existing gold filters. All tier rows re-derive from stored annotations at every rebuild/refresh.
- The loans facet (P34-2, honoring P17-1's "a future `--loans` facet reads them without reparse"): `search --loans CODE` / `list SOURCE --loans [CODE]` read the per-passage loan-token counts a language-contact source stores in its OWN `annotations_json` (`"loans": {code => token count}`, tallied from per-token `lang` — Coptic Scriptorium today). Deliberately NOT an index or a projection table: a correlated `json_each` EXISTS in the shared catalog join (`CatalogJoin#loans_exists`), passage-grained, code matched case-insensitively as a bound value. Because it is one more `visible_passages` conjunct it composes with every search path (text, `--fuzzy`, `--lemma`/`--morph`, `--near`, and all catalog filters), and because the loader's `annotations_json` IS the facet store, `nabu rebuild` has nothing extra to maintain — the complement of the `passage_lemmas` pattern: extract-into-an-index when the query needs its own access path, read-in-place when one JSON probe per candidate row suffices.
- The `spans` annotations contract (P30-4, beside the P7-5 `tokens` contract): a syntax-bearing source stores constituent extents in the SAME per-passage `annotations_json` that carries its tokens — an ordered `"spans"` array beside `"tokens"`, one hash per constituent intersecting the passage: `{"type": "clause"|"phrase"|…, "node": <upstream stable id>, "ranges": [[from, to], …]}` where ranges are 0-based inclusive INDEX PAIRS INTO THAT PASSAGE'S OWN tokens array (passage-relative — no global token table needed to consume them; a discontinuous constituent is a list of ranges, never flattened), plus `"partial": true` on every passage-clipped piece of a constituent that crosses passage boundaries (the shared upstream `node` id joins the pieces), plus the constituent's own features verbatim (BHSA: clause `kind`, phrase `function`). No new table: spans survive storage, rebuild, display and MCP exactly as tokens do, and any future span-derived index follows the passage_lemmas pattern (extracted from stored annotations, never by re-parsing canonical). First registrant bhsa. dss (P30-5) reuses the shape under the key `"clusters"` for upstream's text-critical cluster nodes (cor/cor2/cor3, rem/rem2, rec, alt, unc2, vac — degrees verbatim; a vacat covers no token and rides with empty `ranges` as a positioned gap), and deliberately does NOT emit its ML-derived clause/phrase boundaries (silver — 125/315 nodes, all in 1Qisaa; the goo300k/imp discipline, journaled in 02-sources row 88).
- The feature-MODULE lane (P34-1): a Text-Fabric sibling repo that ships extra node features over a registrant's frozen slot space (ETCBC/bridging over BHSA tf/2021) gets its own registry row for the sanctioned GitFetch path into `canonical/<module>` — but mints NO documents (discover empty by design, `enabled: false` permanently, conformance suite inapplicable) and surfaces exclusively as extra token keys on the core adapter's passages: the bhsa Corpus reads `canonical/bridging/tf/2021` when present and rides `"osm"`/`"osm_sf"` (OSHB's OSM morph tag of each word's first/second aligned morpheme, verbatim incl. upstream's `*` problem marker) beside lex/gloss/qere; absent module = lane off, byte-identical output. A module whose nodes exceed the core dataset's slot space is a ParseError (version misalignment — module data off its own slot numbering is noise). NOT a links-journal producer: word slots have no urns, and verse-grain OSHB↔BHSA edges would only duplicate the ot alignment hub (§10) — the hub joins the verses, the lane joins the words.
- **Research axes (P35-0, D35 rulings 2026-07-20)**: the grown source list grouped by the owner's research desks — 18 owner-ratified axes, each an explicit definition in `config/axes.yml` (`Nabu::AxisRegistry`: name, persona one-liner, desc; file order = render order; the persona is FIRST-CLASS RENDER DATA — the hat in the house voice, printed verbatim by the axis surfaces) plus a REQUIRED list-valued `axes:` key on every source row in sources.yml. Axes are TAGS, not a partition — multi-membership deliberate (tlhdig = cuneiform+hittite by ruling D35-d; the hebrew/syriac language desks coexist with the cross-language biblical hat by design) and membership is whole-source (no per-document axes in v1 — where only part of a shelf fits, the honest note rides the axis desc, never a fake partition). Three load-time invariants in `SourceRegistry`: every source declares ≥ 1 axis once definitions exist; every declared axis is defined; an axis name never equals a source slug — the RESOLUTION GUARANTEE that lets the future `nabu sync <axis>` / `list --axis` surfaces (P35-1/2) resolve one bare token unambiguously. Placement decision: definitions live BESIDE, not inside, sources.yml — the sources file keeps its pure slug ⇒ entry mapping contract (a reserved top-level block would need a magic-key carve-out in the loader and would make a source slug named "axes" silently impossible instead of loudly colliding), while membership stays on the source row like `enabled`/`translations`/`siblings` (the P34-0 owner-posture precedent; a missing axes.yml is bootstrap/test mode — no axes required, a redirected registry brings its own axes file or none). Consumption seam: `SourceRegistry#axes` (the definitions) + `#axis_members(name)` (slugs in registration order). NB "axis" unqualified always means research axis; the §14 date/place mechanism renames to "timeline" (P35-4).
- `passages_trigram` + `passages_trigram_scope` (P16-4, intertext design §4, same file and lifecycle): the fragment-search index behind `search --fuzzy` — a second FTS5 table over the SAME folded `text_normalized`, tokenized into character trigrams for infix/mid-word matching (`]μηνιν αει[` on a damaged papyrus). DOCUMENTARY SCOPE ONLY: sources flagged `fuzzy_index: true` in config/sources.yml (papyri-ddbdp + oracc; an owner posture like `enabled`/`translations` — the whole corpus would cost 3.6–4.1 GB, the documentary shelves 257 MB measured at 6.43 B/char, 8.6 s build). The scope table records the slugs each build actually indexed, so the query surface reports real coverage instead of trusting config. Query semantics are two-phase: trigram candidates (implicit-AND MATCH of the fragment's trigrams — co-occurrence, not contiguity), then substring verification against the stored folded text (Query::Fuzzy). Sub-ms to ~10 ms measured live.
- Index lifecycle (P26-5): `nabu rebuild` keeps the pure-function guarantee — `Indexer.rebuild!` drops every fulltext-side table and regenerates the lot from the catalog, and it is the ONLY full-reindex surface (owner decision: no separate `nabu index` command). Syncs now maintain the index INCREMENTALLY: `Indexer.refresh_source!` deletes the synced source's rows from the FTS/lemma/trigram tables (the FTS tables are regular contentful FTS5, so per-row DELETE is real deletion; one streaming rowid scan stands in for the missing passage_id index) and re-inserts them from the current catalog, rebuilds `alignment_refs` only when the source holds a registry witness document, and rebuilds the reflex closure only when the source's lemma rows or reflex edges changed. The contract is ROW IDENTITY — after a refresh, the fulltext state equals what a from-scratch `rebuild!` would produce (test-pinned) — and the sync line's "indexed N passages (slug)" is the SOURCE's count, never the corpus total. Index-inert grains (`:notes`, `:language`, `:source` — no passages, no dictionary entries) skip index work entirely. A fulltext file that is missing tables (first sync) or predates the tier column falls back to the full rebuild.
- Derivation stamps + `rebuild --incremental` (P36-1): `derivation_stamps` (catalog, migration 017) records, per replayed source, the fingerprint its derivation satisfied — `Nabu::DerivationFingerprint`'s four-input rule plus registry posture: (1) canonical bytes (git-backed trees: HEAD sha per embedded repo + the git-excluded `.attic/` content hashed explicitly; everything else: sha256 over every file's bytes; a git tree with non-attic local modifications — e.g. LFS-materialized clones — has a WEAK identity: no stamp, never skipped); (2) parser/pipeline code (a constant-reference closure of the adapter's files within `lib/nabu/adapters/` — per-family granularity, catching bare composition like Perseus→EpidocParser that the require graph misses — plus a shared derivation-core digest of loaders/indexers/models/script helpers, exclusion-listed so a mistake over-rebuilds, never under); (3) fold rules (a digest of `normalize.rb` — a fold edit honestly dirties everything); (4) the migration level; (5) the entry's derivation-shaping flags (`translations`/`classes`/`lemma_tier`/`fuzzy_index`, stored as plain JSON). Full rebuild stamps as it replays; `--incremental` skips clean sources (row-identity untouched), re-derives dirty ones via the shared replay seam (loader upsert/withdraw, the `sync --parse-only` machinery) + `Indexer.refresh_source!`, and re-runs the corpus-wide timeline/facet builders only when something was dirty. An absent stamp = dirty. REFUSALS are loud (full rebuild required): no catalog, catalog schema level ≠ code's, or catalog rows/stamps for a source with no replayable canonical tree. Honest divergences from a fresh full rebuild, by design: row ids, revision counters (incremental REVISES and journals changes — more history, not less), `sources.last_sync_*` mirrors on clean sources, and withdrawn tombstones where full rebuild has no row (never-hard-delete). Syncs do not stamp: a synced source's stale stamp reads dirty and re-derives once (over-rebuild-safe). Not fingerprinted (documented limit): gem/Ruby toolchain upgrades — full rebuild after those.
- `vectors.sqlite3`: one table per `(embedding_model, version)` — model upgrades create a new table, old one dropped only after re-embed completes.
- `license_class` enum (`open`, `attribution`, `nc`, `research_private`, `restricted`) drives query/export filters.
- The honesty invariants of the query/render surfaces (P35-6, dev-loop §6b): every literal in query/render/fetch code is a census claim about the corpus at authoring time, so (a) **era-bound literals carry their justification in place** — a `# census: <number>, <YYYY-MM-DD>[, basis]` comment recording what was measured against the live corpus and when, or `# const: <reason>` for values no corpus growth can falsify; `rake census:check` (also enforced inside the suite) fails on any unstamped literal in `lib/nabu/{query,mcp}/` + `*_fetch.rb`, and each phase gate re-diffs the recorded numbers against the live catalog. (b) **Every truncating surface announces what it hid and every empty result under active filters explains itself** — the shared exhausted-inner-window hint (`CatalogJoin::INCOMPLETE_PAGE_HINT`: a full `limit × INNER_LIMIT_FACTOR` index window + active catalog-side filters + a short page means matches may exist beyond the window, said at all four search surfaces, CLI and MCP), proximity's announced lemma-expansion clip, the render-cap tails (define/list/links/etym), and the fuzzy scope line — all pinned data-driven in `test/render_conformance_test.rb`, where a new surface joins by adding a row. (c) **A corrupt annotation lane never poses as an unannotated passage**: `Query::Show#parse_annotations` marks unparseable `annotations_json` (`ANNOTATIONS_UNREADABLE`) and show/`--tokens`/export announce the skip (export JSONL carries `annotations_error` on the affected line); concord's hyphen-tail lookup alone stays a silent nil (adjudicated: a highlight-span micro-feature whose no-highlight fallback is itself the documented degrade).
- Lock tolerance (P17-7): every SQLite file runs `journal_mode=WAL`, set idempotently on each read-write connect (the pragma persists in the file, so existing dbs self-heal on first open — no migration; readonly connects inherit what the file says). WAL is the fit for the real usage pattern — N readers (MCP, agents, CLI) + 1 writer (sync/rebuild/batch producers) without mutual blocking; pre-WAL, a reader's shared lock crashed a running rebuild's commit (`SQLite3::BusyException`, owner defect 2026-07-13). Every connect, readonly included, also carries `busy_timeout` = 10 s (`Store::BUSY_TIMEOUT_MS`: longest legitimate lock holder is seconds-scale — batch links readbacks, loader/indexer commits — plus margin), which covers writer-vs-writer overlap and not-yet-flipped rollback-mode files. Cost: `-wal`/`-shm` sidecars sit next to each db while connections are open — `nabu backup` copies live sidecars with each db and prunes stale ones at the target (ops §9/§10).

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
- **The MediaWiki fetch path (`Nabu::WikiFetch`, P29-3) honors the same contract.** The Vienna wiki pair (lexlep/tir) is a living Semantic-MediaWiki site with no dump endpoint, so a fourth fetch arm exists, phase-mirrored: stage 1 fetches every configured category's member map via `generator=categorymembers&prop=info` (500 per request, pagination) — doomed = local page files upstream no longer lists, computed with the live tree untouched; guard between the phases; then attic-before-delete (same manifest format, sha = the member-map pin) and a page crawl in the API's own 50-title `prop=revisions` batches, split into per-page envelope files `pages/<Category>/<percent-encoded title>.json` (wikitext byte-verbatim inside). Change detection is REVID-driven (api.php serves no useful `Last-Modified`): a page refetches iff its stored revid differs from upstream's lastrevid — resumable at the page grain. Requests are throttled and carry a nabu-identifying User-Agent; the remote probe HEADs api.php via the `:http_zip` strategy against the `.wiki-fetch.json` state pin.
- **The Git-LFS materialization arm (`Nabu::LfsFetch`, P31-2) rides the git path, not beside it.** The cdli data repo stores its two payloads (155 MB csv + 87 MB atf) as Git LFS objects, and a plain GitFetch clone on a machine without the `git lfs` extension leaves 134-byte pointer stubs. Rather than depend on an uninstalled binary, LfsFetch speaks the standard LFS Batch API directly (`<repo>.git/info/lfs/objects/batch` — anonymous on GitHub, verified live): POST each pointer's oid+size, GET the returned href, **sha256-verify against the pointer's own oid**, rename into place. The pull cycle preserves GitFetch's ff-merge contract: a materialized payload dirties the tree in git's eyes, so before a pull each recorded payload steps aside into an oid-keyed cache (`.lfs-cache/<oid>`, in `.git/info/exclude` like the attic) and its pointer is restored via `git checkout --`; after the merge, re-materialization is a cache rename on an oid hit — an unchanged upstream never re-downloads. A machine WITH git-lfs smudges at clone time; materialization then finds no pointers and reports the files present — both worlds behave identically downstream. Discovery treats an unmaterialized pointer as an absent-but-loud state (`discovery_skips` unrecognized note), never as an empty corpus.
- **The many-repo git fetch arm (`Nabu::KanripoFetch`, P33-0) composes GitFetch across an org of repos.** Kanripo is one GitHub repo per text (9,355 repos censused 2026-07-20) — neither clonable wholesale nor scoped by any single repo's layout. The wave: (1) the KR-Catalog repo (org-mode catalogs, 3.4 MB) is synced through ordinary GitFetch as the *discovery index*, and the scope is the `:KR_ID:` entries of the catalog files for the registry's `classes:` list (a class with no catalog file is a loud error, never a silent empty wave); (2) each in-scope text is its own shallow GitFetch of master only (editions live as git *branches*; master carries the BASEEDITION text), processed **sequentially to completion** — prepare → per-text guard → merge → ledger pin — deliberately NOT the UD all-prepare-then-merge choreography: at ~3,000 repos, holding every repo hostage to the last would mean an interrupted wave pins nothing, so the guard protects at text grain (each repo's doomed paths against its own files — stricter than a source-wide fraction) and interruption loses at most the text in flight; (3) every network operation is followed by a configurable delay (`KanripoFetch::DEFAULT_DELAY`, 2 s — conservative, owner-adjustable through the adapter's `fetch_delay` seam); (4) the **fetch ledger** (`<workdir>/.kanripo-fetch.json`, the Sefaria index-pin discipline git-flavored) records per text the fetched HEAD sha and the *catalog* sha it was fetched under, rewritten after every text — a text pinned under the current catalog sha is skipped without touching the network, so an interrupted wave resumes refetching nothing, and a catalog advance (catalog commit = wave identity) re-pulls each text exactly once. Catalog ids with no repo are real (61 of 2,989 wave-1 ids): a clone failing with git's not-found signature is recorded `absent` in the ledger — censused, reported, retried once per catalog advance — while any other failure aborts the wave loudly. The attic contract holds per repo (`<workdir>/.attic/<KR-id>/…`, plus the catalog's own attic); the FetchReport pin is the catalog sha, per-text pins stay in the ledger file, and the remote probe targets the catalog repo (the org URL is not ls-remote-able).
- **The mass-deletion breaker runs BEFORE the merge.** The fetch layer predicts from the deletion diff: the fraction of the source's currently ingestible files (what `discover` yields from the untouched tree) among the doomed paths. Above 20%, `Nabu::SyncAborted` — with the canonical tree byte-unchanged (no merge, no attic writes). `--force` proceeds: files are atticked, documents retired, nothing is lost. A second, load-side guard in SyncRunner (same threshold, urns in the catalog vs `discover_with_attic` ids) still covers `--parse-only` runs and non-git adapters; attic documents count as present there, never as pending withdrawals.
- Every sync (and every rebuild replay, kind-tagged) writes a `FetchReport` + `LoadReport` (counts: added/updated/withdrawn/errored) to the ledger's `runs` table, slug-keyed; `nabu status` and `nabu health` read it — continuously across rebuilds, because the ledger survives them (P7-1). The remote probe's license baselines and per-repo pins live on the ledger's `pins` rows for the same reason: a rebuild must not open a license-drift blindspot.
- Parse errors quarantine the document (recorded, skipped), never abort the batch — and never withdraw (P37-r2): a quarantined ref's document is still present in canonical, so its urn shields the held row (prior revision, still served) from the full-load withdrawal sweep. Recognition getting stricter can therefore never unserve held content; the row revives via the normal restore/revise path when the parse succeeds again.
- **Postcondition invariants (P18-7).** Beside the trend rules, `nabu health` holds STATE against PROMISES (`Health::Invariants`, findings-only — a green library prints nothing new): a source whose most recent ledger run FAILED is loud with the error detail (and, when provenance shows rows written during that run, a named "partial load"); a source whose latest run succeeded yet which holds zero rows in its grain (docs/entries/language records) is the half-loaded-catalog / synced-to-nothing signature — `enabled` deliberately not consulted (P23-3); flag-vs-artifact pairs (`fuzzy_index` vs the trigram index + scope table, timeline extractor families vs `document_axes` rows, `Adapter.reflex_bearing?` vs `dictionary_reflexes` rows, reflexes vs the `language_names` census); pending catalog/ledger migrations (soft). The sync/rebuild quarantine WARNING is DELTA-aware against the ledger's `quarantine_baselines` (ledger migration 005): `baseline` auto-advances at every ok run, so each change announces exactly once and a standing audited count is silent; `anchor` is the low-water mark (advances downward only), so health's creep check catches the slow bleed the advancing baseline absorbs — the withdrawal-creep precedent. The optional `sync SLUG --review CMD` hook pipes a JSON brief to a subprocess and reports its exit honestly without ever failing the sync (ops.md §11) — no cloud dependency enters the core.
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
(catalog, registry) and is rebuilt whole inside `Indexer.rebuild!` (`nabu
rebuild`) — so a rebuild regenerates alignment for free, id re-minting and
all (the index carries re-minted passage_ids precisely because it is
dropped and rebuilt with them). Since P26-5, a sync regenerates it only
when the synced source actually holds a registry witness document
(`Indexer.refresh_source!`'s relevance gate — the index is registry-scoped,
157k rows live, so the full regeneration is cheap when it fires and skipped
entirely when it cannot matter). No hand-curated rows exist anywhere in
db/.

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
never fuzzed. A `cts_work` may also be an in-catalog DOCUMENT urn
(`urn:nabu:…` — P17-4, MW→GRETIL: Mn./Pāṇ. cite at document grain by
design), where the held document is itself the resolution when the
citation is nil — and, since P34-4, also when a passage-grain probe
MISSES on a held document: TLS attestations cite Kanripo texts by
`<juan>:<page>` (the mandoku passage key), and the held edition's
pagination only sometimes agrees with TLS's, so the page probe hits where
it honestly can and falls back to the text — never to nothing — while
unheld texts keep nil. The TLS attestation crosswalk (P34-4) is the
volume case of this machinery: one `dictionary_citations` row per
distinct (sense uuid, seg id) pair in tls-data's notes/doc + notes/swl
(~190K attestations; sense uuids join the tls-words bodies, KR-shaped
text ids claim `urn:nabu:kanripo:<KR-id>`, TLS-side/Taishō ids mint
display-only rows), re-derived at every parse from canonical — resolution
coverage grows as kanripo sync waves land, with zero stored state. The
CLI caps the resolved-citation print (first 12, `--long` expands); MCP
was already capped.

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
Bosworth-Toller (Old English; .docs/surveys/oe-survey.md — gitignored
planning material: official CC BY 4.0 LINDAT
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

## 12. The reconstruction shelf — the comparativist's crosswalk (P14-1)

`nabu etym богъ --lang chu` walks from an attested lemma to its
reconstructed ancestors and out to the cognates: богъ (725 gold passages)
→ Proto-Slavic \*bogъ (gloss, senses, the Iranian-loan discussion) → PIE
\*bʰeh₂g- with ITS reflexes (grc ἔφᾰγον…), each cognate carrying the
count of gold-lemma passages attesting it in THIS catalog. The data is
English Wiktionary's reconstruction pseudo-languages via kaikki.org's
wiktextract extracts (same dual "CC-BY-SA and GFDL" grant as
wiktionary-cu → attribution): Proto-Slavic (`sla-pro`, ~5,195 words),
Proto-Indo-European (`ine-pro`, ~1,781), Proto-Germanic (`gem-pro`,
~5,552). This section records the design decisions.

**Reconstructions ARE dictionary entries — one source, three
dictionaries.** The records are byte-for-byte the OCS record shape (the
`wiktionary-jsonl` family parses them unchanged), so the shelf reuses
everything §11 built: `WiktionaryRecon` is ONE registry source
(`wiktionary-recon`, `content_kind :dictionary`) shipping three
dictionaries (`wiktionary-sla-pro` / `wiktionary-ine-pro` /
`wiktionary-gem-pro`), urns `urn:nabu:dict:wiktionary-sla-pro:<entry_id>`,
same entry-id recipe, same revision/withdraw semantics. Fetch is three
FileFetch single-file syncs — each extract in ITS OWN subdir (FileFetch is
one-file-per-dir by design), attics under the shared top-level
`<workdir>/.attic/<subdir>/`, the UD two-phase choreography (all prepare,
the breaker sees the whole set, all complete), three probe targets. The
upstream `word` field carries NO asterisk; display puts it back (a
headword whose dictionary language ends `-pro` prints starred), and
`define *bogъ` strips a leading asterisk and scopes to the reconstruction
shelves — the comparativist's notation IS the query convention.

**Language codes: Wiktionary's, verbatim.** `sla-pro`/`ine-pro`/`gem-pro`
are not ISO 639-3 — they are Wiktionary's etymology-language codes, and
the registry adopts them unchanged because the whole crosswalk speaks
them (inventing our own would break the join with every descendants
node). They pass the existing shape-only tag validation (conventions §4)
with zero code changes; folding is the generic rule (ě/ř lose their
hačeks under the Mn strip, jers stay — `*cěsařь` folds `cesarь`; the PIE
laryngeal subscripts survive, an accepted typability gap since `etym`
enters from an attested, typeable lemma).

**The crosswalk: `dictionary_reflexes` (migration 007), stored edges,
query-time resolution.** ~89% of reconstruction records carry a
`descendants` tree; its WORDED nodes flatten depth-first into
`DictionaryReflex` values (the citation pattern exactly: parser mints,
loader persists, revision replaces wholesale, reflexes are part of the
content sha). Each row keeps the upstream `lang_code` VERBATIM plus a
catalog-side `language` (the parser's map where codes differ — cu→chu,
la→lat, sa→san — identity for shape-valid codes, NULL for the lone
malformed "ML." in the wild: display-only, never a join candidate), the
reflex `word` and its `roman`, and their conventions-§9 folds (leading
asterisk stripped — proto-to-proto edges arrive as "*bogъ"). Resolution
happens at QUERY time only, against whatever `passage_lemmas` currently
holds — the §10/§11 no-stale-links stance; a rebuild or reindex changes
nothing here. The `roman` fold is load-bearing: the catalog's got/san/xcl
gold lemmas are romanized, so Gothic 𐌲𐌿𐌸 counts via "guþ" (measured in
the P14-1 scout: roman rescues got from 0% to 59% reflex-level).
ContentHash appends reflexes ONLY when non-empty, so every reflex-less
entry on every pre-P14-1 shelf keeps its stored sha (pinned by test) —
no revision storm. The wiktionary-cu records also carry descendants;
their backfill is a deliberately deferred decision (improvements
register), so the parser's `reflexes:` option defaults off.

**Query surface: two directions of one table.** `define *bogъ` (and
`--lang sla-pro|ine-pro|gem-pro`) reads the shelf as entries — body plus
the reflex list, attested-in-catalog cognates first with counts.
`Query::Etym` (`nabu etym`, MCP `nabu_etym`) walks the reverse edge:
folded query → reflex match → proto entries (each with MatchedVia, the
reflex that let it in), then ONE proto-to-proto hop up (reflex rows of
OTHER `-pro` dictionaries naming this entry's language + folded headword)
with the ancestors' own cognates — bounded by design, a report not a
graph crawl. Counts come from `passage_lemmas` grouped per language
(ReflexViews, shared by both surfaces); nil is an honest absence, never a
zero claim. The MCP tool is the seventh, same contract as the rest:
license fields on every entry, cognate lists bounded attested-first with
honest totals, research_private/restricted withheld unless
`include_restricted`, graceful pre-007 degradation ("run nabu sync
wiktionary-recon").

**Addendum (P15-3): cognates-in-parallel — the crosswalk × the hub.**
`nabu cognates <work-or-ref> [--langs got,chu]` (MCP `nabu_cognates`, the
ninth tool) answers the question the crosswalk and the alignment hub (§10)
can only answer together: verses where witnesses in ≥2 languages use
reflexes of the SAME reconstruction root — got salt ~ chu соль under PIE
*sḗh₂l at LUKE 14.34, found blind; the Gothic × OCS NT yields ~300 verses /
30 roots in under a second (design doc `intertext-design.md` §6). The join
is staged through `reflex_roots(language, lemma_folded, root_urn)` — a
derived closure table built by `Store::ReflexRootsIndexer` from
`Indexer.rebuild!` (and, since P26-5, from a sync's incremental
`refresh_source!` whenever the synced source's lemma rows or reflex edges
changed — a lemma-less source's sync skips it),
living in fulltext.sqlite3 beside `passage_lemmas` (~50k rows / ~4 MB /
~4 s live). The closure is the etym walk, precomputed and bounded the same
way: direct reflex edges (word AND roman folds — the script bridge) plus
ONE proto-to-proto ascent hop with the same-language exclusion (intra-PIE
derivational edges are sub-tree structure, not ancestry); rows are scoped
to gold languages, since only they can ever join `passage_lemmas`. Design
decisions from the fable closure review (2026-07-12, backlog P15-3): roots
are stored as URNs, never row ids (ids re-mint on shelf reload; the query
resolves urns against the live catalog with the withdrawn filter, so stale
roots vanish rather than serve); the meet SHELF is displayed on every hit
(descendant trees include unflagged borrowings — hlaifs ~ хлѣбъ meets at
gem-pro, and saying "gem-pro" is the minimum honesty until a `borrowed`
flag lands on the crosswalk); common-word suppression is per-language
relative (df ≥ max(50, 10% of the language's gold passages) — an absolute
threshold is percentile-incoherent across gold corpora spanning 125 to
113k passages, and frequency cannot separate богъ from нъ at all, said
plainly in the help). Recall is bounded by Wiktionary coverage (~34% got /
~21% chu gold lemma types reach any proto entry): absence of a hit is
absence of evidence.

**Addendum (P16-5): the attested-OCS descendants feed the crosswalk too.**
The wiktionary-cu records carry the same `descendants` trees the recon
extracts do; the P14-1 deferral is closed — the cu adapter now parses them
(`reflexes: true`), so attested-OCS entries mint `dictionary_reflexes`
edges through the identical parser → DictionaryLoader → ReflexRootsIndexer
choke points (census over the live extract, 2026-07-13: 589 of 4,615
entries carry worded descendants → 2,210 edges, ~244 of them gold-joinable,
mostly orv and sl). The walk semantics stay bounded: a cu-owned edge is
direct-only (chu is not `-pro`, so the closure takes no ascent hop from
it — the OCS → Proto-Slavic step remains Etym's live one-hop ascent), and
etym renders attested entries WITHOUT the reconstruction asterisk, which
only the `-pro` shelves earn. Reflexes ride the entry content sha, so the
backfill lands in the live db at the next owner-fired
`bin/nabu sync wiktionary-cu --parse-only` (re-mints the shelf's
revisions — expected, journaled).

**Addendum (P17-3): four more shelves, the multi-hop closure, and the
`borrowed` flag.** The survey (`.docs/surveys/recon2-survey.md`) landed all four
served on-axis kaikki extracts as EXTRACTS rows on the SAME
`wiktionary-recon` source (registry untouched): Proto-Balto-Slavic
(`ine-bsl-pro`, 491 records — near-zero direct gold value, stated
plainly; it earns its place as the STRUCTURAL chain link, 88.4% of its
sla-pro descendant nodes fold-join the sla-pro shelf), Proto-West
Germanic (`gmw-pro`, 5,551 — the OE axis's proto desk and the second
intermediate shelf), Proto-Italic (`itc-pro`, 745 — best record-level
join, 76.9%), Proto-Indo-Iranian (`iir-pro`, 799 — largest new-key
contributor, san via roman). ~60 MB across the four owner-fired GETs,
+7,586 entries (13,053 → 20,639). Folding gains ˢ→s, ᶻ→z, ˀ→(dropped)
on the shared proto rule, keys `itc`/`iir` added (`gmw` measured clean —
no key; conventions §9). Two structural consequences:

- **The closure's one-hop bound died with PBS** — it was argued from "no
  intermediate shelf exists", and `ine-bsl-pro`/`gmw-pro` ARE that shelf.
  `Store::ReflexRootsIndexer` now runs a shelf-visited worklist walk:
  from each direct target, breadth-first rounds over "entries of an
  UNVISITED shelf whose reflexes name (shelf, headword_folded)", each
  dictionary language enterable once per walk (the same-language
  exclusion generalized). Termination is structural (every non-final
  round visits a new shelf ⇒ ≤ shelves−1 rounds; a malformed
  proto-to-proto cycle's return edge re-enters a visited shelf and dies),
  determinism is round-grain (shelves are marked visited per round, so
  membership never depends on iteration order), and with no intermediate
  shelf the walk degenerates to EXACTLY the old one-hop set (pinned by
  test). Attested reflex-owning shelves (wiktionary-cu) now ascend like
  the -pro shelves — descent through an attested intermediary is the same
  descent relation (supersedes P16-5's direct-only closure stance;
  display asterisks stay -pro-only). The verified live chain: PIE *per- →
  ine-bsl-pro *pírštan → sla-pro *pь̃rstъ → chu прьстъ / orv пьрстъ.
  `Query::Etym` walks the same bound and renders the chain indented, one
  step per hop; MCP `nabu_etym` nests `ancestors` recursively.
- **The `borrowed` flag (P15-3 review finding 4)**: migration 010 adds a
  NULLABLE boolean to `dictionary_reflexes`; the parser mints true/false
  from the upstream loan markers in `raw_tags`/`tags` (`/borrow/i`:
  "borrowed" ×92,120 across the eight extracts, "learned borrowing"
  ×405, a hedged free-text tail; "reshaped by analogy…" never matches),
  and NULL remains the honest "row predates the reparse" — the flag rides
  ContentHash's reflex fields, so the next owner-fired
  `sync <shelf> --parse-only` re-mints reflex-carrying revisions and
  backfills (the P16-5 recovery pattern). The flag **ORs along the
  closure path** (the *hlaibaz golden: the marker sits on the gem→sla-pro
  proto edge, not the chu leaf — a direct-only flag would never fire for
  hlaifs ~ хлѣбъ), three-valued (true > false > NULL) across duplicate
  edges and paths, and lands in `reflex_roots.borrowed`. Consumers state
  the loan PER EDGE: cognates witness words read "(loan)"
  (`chu хлѣбъ (loan) ~ got hlaifs` at JOHN 13.18 — previously the reader
  had to apply the meet-shelf heuristic, which stays the caption for
  unflagged/NULL edges), etym ancestor arrows read "←(loan)", batch
  cognate details append "(loan: chu)", MCP payloads carry the boolean
  with the NULL-honesty note. Projected closure growth ~50,395 → 56–60k
  rows (survey §2), realized at the owner-fired sync + reindex.

## 13. Passage-anchored intertext — the corpus reads itself (P15-1)

`parallels <urn>` answers the classicist's "who quotes THIS line? where
does it echo?" — reception discovery, the inverse of the alignment hub
(§10, which renders one verse across its *registered* translation
witnesses; this DISCOVERS quotation across the whole corpus from surface
text alone). The full design, priced against measured live probes (per-gram
FTS 1–111 ms/passage; the elision-strip finding; rarity scoring; document
dedupe), is `docs/intertext-design.md` §1 — this is the short standing
record of what shipped.

**Zero new schema — a query surface, not an index.** The design's measured
verdict: the materialized corpus-wide n-gram table the register imagined is
not needed. `Query::Parallels` folds the anchor to its stored search form
(`text_normalized`, already minted at the adapter boundary), cuts it into
overlapping 4-word grams, and probes each as a quoted FTS5 phrase MATCH
against the SAME `passages_fts` index Search and Proximity use. Candidates
are scored by shared-gram count **weighted by rarity** (1/document-frequency,
the df free from each probe's own hit count), so a rare shared phrase — a
real quotation — outweighs a pile of common function-word grams. Grams in
≥ `COMMON_GRAM_DF` passages are dropped (no evidence, and a cost bound).

**Two measured correctness riders (design §1).** (i) *Elision fold at
gram-build.* The elision apostrophe splits editions — SBLGNT writes it
U+02BC (a LETTER to unicode61: `ἐπʼ` is one token) while First1K/Swete
writes U+2019 (punctuation: bare `ἐπ`) — so a surface gram misses its twin
until the apostrophe is stripped. `Parallels` strips every elision
apostrophe in its gram builder (the cheapest fix, local to the query;
folding U+02BC in `text_normalized` is the deeper fix but re-mints shas, a
fable decision). Measured payoff: Matthew 4:4 finds LXX Deuteronomy 8:3.
(ii) *Duplicate witnesses.* The corpus deliberately holds texts more than
once, so candidates group to **document grain** — one hit per document, its
best passage the representative, sibling loci counted; cross-source
identical texts stay two hits (two documents; no cross-source work
identity). The only explicit exclusion is the anchor's own document —
translations self-exclude (no shared folded tokens across languages), and a
same-language other edition of the anchor's work is a wanted corroborating
hit, not excluded.

**Second signal — rare-lemma co-occurrence (design §1 option c).** For the
gold-lemmatized slice, `lemma_echoes` lists passages sharing ≥2 of the
anchor's RARE lemmas (global df ≤ `RARE_LEMMA_DF`), rarity-weighted — the
re-inflected/reordered allusion verbatim grams miss. It fires only when the
anchor carries gold lemmas (else one cheap query returns empty and it
skips), and depends on the **`passage_lemmas(urn)` index** this packet adds
to `Store::Indexer#create_lemma_table` (the anchor-lemma lookup by urn; also
needed by cognate-in-parallel, design §6). Like the rest of the fulltext db
the index is derived-of-derived — created imperatively in the Indexer,
rebuilt with the table, never a numbered migration (§5; migrations own the
catalog only).

**Surfaces.** CLI `nabu parallels <urn> [--lang/--license/--limit]
[--long]` (compact by default; `--long` expands any truncated evidence-span
or shared-lemma list, per the owner rule that `--long` be available wherever
output is elided). MCP `nabu_parallels` is the eighth tool, same contract as
the rest: license fields + source on every hit, bounded with an honest note,
research_private/restricted withheld unless `include_restricted`, graceful
degradation when the index is rebuilding.

**What it is not.** Cross-language allusion without alignment (a Father
paraphrasing LXX in another language, an OCS homily echoing a Greek
original) shares no surface or lemma vocabulary to shingle — that is the
embeddings/cluster line (design §"what waits"), gated on the golden set the
symbolic packets like this one produce as a side effect. Batch/corpus-wide
mining and its persisted `links` edges (design §7) are a later rider on this
same gram machinery, not this packet.

## 14. The timeline — when and where a document is from (P15-2)

The historical linguist and documentary historian ask "only 2nd-century
texts", "only Oxyrhynchus", "plot this word across centuries". The full
design — five dating sources measured, the schema priced (≤ ~100k rows,
< 20 MB) — is `docs/intertext-design.md` §3; this is the standing record of
Part 1 (HGV papyri + Slovene goo300k/IMP, P15-2) and Part 2 (ORACC catalogue
dates + TOROT chronicle annals, P16-3).

**A catalog-side `document_axes` table (migration 008), NOT columns on
documents.** A document may carry zero, one, or (Part 2's chronicle annals)
several timeline rows, and most of the corpus is *undated* — an absence, never a
row. Columns: `(document_id, not_before, not_after, precision, date_raw,
place_name, place_ref, axis_source, passage_seq_from, passage_seq_to)`. The
date model is signed historical years with no year 0 (conventions §11); the
nullable `passage_seq_*` pair rides for Part 2's passage-grain, document-grain
rows leaving them NULL.

**timelines = f(canonical), regenerated on rebuild.** `Store::TimelineBuilder` is a
post-load pass — like the Indexer, but writing the CATALOG rather than the
fulltext index — wired into `Rebuild#run` after every source is replayed. The
HGV extractor reads the `HGV_meta_EpiDoc` XML and joins its `ddb-hybrid` idno
to the DDbDP urn (`bgu;3;994` → `urn:nabu:ddbdp:bgu:3:994`, the same transform
the papyri adapter mints with — verified); goo300k/IMP take the CE year off
the urn suffix (`…:sigil-1584`, urn = f(canonical)). The Indexer is unchanged
and never re-parses canonical. Live coverage (2026-07-12 sanctioned build):
66,261 HGV files → 60,923 papyri joined (99.2% of the DDbDP shelf) + 89
goo300k + 658 IMP = 61,670 dated/placed documents in 46.6 s; `document_axes`
is 10.7 MB.

**Part 2a — ORACC catalogue dates (`TimelineBuilder::OraccDates`, P16-3).** Every
ORACC project ships a `catalogue.json`; the 2026-07-13 census (33 catalogues,
25,502 members) found `period` on 25,330 members and `date_of_origin` on
7,343 (SAA regnal formulas `Sargon2.000.00.00` / eponym `Esarhaddon.limu
Dananu.07.21`; RIAO/RIBO/RINAP absolute BCE ranges `704-681`, `ca. 1233-1197`;
century phrases `9th-8th century`). Extraction is census-backed, never
guessed: `date_of_origin` first — a regnal formula resolves through a
12-king Neo-Assyrian reign table (standard eponym-canon chronology, absolute
via the 763 BCE Bur-Saggilê eclipse; regnal dates after Grayson — the census
found NO nonzero regnal years, so reign-range grain is the honest maximum);
an absolute value must DESCEND (BCE) or it is unparseable. Unresolved values
fall back to `period` through a documented period table (ORACC/CDLI period
names → middle-chronology year ranges after CDLI's conventional dates,
Brinkman's chronology; Neo-Assyrian → −911..−612, Old Babylonian →
−1900..−1600, "First Millennium" honestly −1000..−1). "Uncertain"/"Unknown"
are deliberately unmapped: skipped and counted (`oracc_undated`). Place =
`provenience` verbatim (minus unclear/uncertain/unknown) + a Pleiades URL
from `pleiades_id`. A translation document (`…-en`, P13-4) carries its
tablet's timeline row — the artifact's date, so the English witness inherits the
time filter. Scratch-measured coverage: 21,558 of 21,692 oracc documents
(99.4%) carry a row — 21,517 dated (99.2%), 41 place-only, 172 undated
members counted, 3 documents absent from any catalogue (upstream drift).

**Part 2b — TOROT chronicle annals (`TimelineBuilder::ChronicleAnnals`, P16-3):
the first PASSAGE-GRAIN rows**, using migration 008's `passage_seq_*` columns
as designed. Census: the annal year is structural — chronicle `<div>` titles
carry the anno-mundi year (`6360: Mikhail …`, bare `6361`, ranges
`6369–6370`); exactly five TOROT sources are annalistic (lav 89 AM divs of
91, pvl-hyp 24/24, kiev-hyp 4/4, nov-sin 163/163, suz-lav 76/76 — 356 divs;
no other source has one, so a shape + AM-plausibility gate (5500..7300)
replaces any allowlist). AM → CE via `Timeline.am_to_ce`: the Byzantine
epoch is 1 Sep 5509 BCE, so AM Y is stored as the honest span
[Y−5509, Y−5508] — the full September-style year; the Rus chronicles' mixed
March/ultra-March styles make a ±1 residue (Jan–Feb of a March-style year)
that is documented, not guessed per annal; precision "am" marks every row.
The conversion crosses the era boundary without a year 0 (AM 5509 → [-1, 1]).
Each annal div becomes one row anchored by `passage_seq_from/to` (min/max
catalog sequence of its sentences, joined by the ProielParser's
`<doc-urn>:<sentence-id>` passage urns); one document-grain ENVELOPE row
(min..max, passage_seq NULL) is inserted first so document-grain consumers
see the chronicle once. Scratch-measured: 5 chronicles, 345 annal rows —
11 nov-sin annal divs are EMPTY upstream (year heading, no text) and anchor
nothing. Grand total after Part 2: 83,233 dated/placed documents, 83,578
timeline rows, `document_axes` = 13.9 MB (design budget < 20 MB holds).
`vocab --by-century` counts document-grain rows only (`passage_seq_from IS
NULL`) — a histogram labelled "documents" must not tally a 163-annal
chronicle 163 times; `search --from/--to/--century/--place` EXISTS over all
rows, so annal grain sharpens nothing there yet (the envelope spans it) but
stands ready for passage-grain queries.

**Query surface.** `search --from/--to/--century/--place` compose through the
shared `CatalogJoin` as one correlated NULL-aware EXISTS on `document_axes`
(document-grained, so a multi-row document never multiplies passages). `show`
prints the timeline line ("date: 292 CE · Oxyrhynchos") when present. `vocab
--by-century` (`Query::Century`) is the diachronic payoff: the dated corpus
bucketed by century, or — with a text query — a word plotted across the
centuries. `nabu_search` gains the same `from`/`to`/`century`/`place` args
(honestly scoped to text search — the dated corpus is not lemmatized).

## 15. The links journal — batch-mined edges that outlive rebuilds (P16-1)

`db/links.sqlite3` holds the corpus's mined cross-reference graph:
`links(from_urn, to_urn, kind, score, detail, run_id, created_at)` with
`kind` ∈ {parallel, formula, cognate, reference, etymology, …} and `detail`
the per-edge evidence
(nil for parallels; the gram for formulas, the meet for cognates — added by
journal migration 002; the headword ← ancestor line for etymology, P28-3),
plus a `link_runs` companion
`(producer, scope, params_json, code_version, created_at)` so every edge is
honest about the run that minted it. The `links` reader resolves
counterparts at passage grain first, document grain second, and — P28-3 —
dictionary-entry grain third (an ingested shelf's `urn:nabu:dict:` urns
read "headword — dictionary title"; a not-ingested shelf's forward edges
still render "(not in catalog)", honestly). The full design is
`docs/intertext-design.md` §7; this is the standing record of what shipped
and where it lives.

**The host argument (the §5 pattern, applied).** The corpus now has three
data temperatures. The catalog/fulltext are pure functions of `canonical/` —
dropped and regenerated by `nabu rebuild`. The history ledger (§5, P7-1) is
runtime HISTORY — append-only, never regenerable, never pruned. Batch links
are NEITHER: they are a function of *(canonical, params, code version)* —
minutes to recompute, so they must survive a rebuild journal-style (the
Phase-8 enrichment stance: derived-but-expensive output lives outside the
drop-and-rebuild dbs, keyed by urn because rebuilds re-mint every catalog
id) — but a rerun of the same scope legitimately REPLACES its edges, which
an append-only ledger must never do. So the journal is a third SQLite file
with the ledger's *mechanics* (its own forward-only migration track in
`db/links_migrate/`, its own `schema_info`, absent-file = empty state,
urn keying) and its own lifecycle: `nabu rebuild` never touches it, and
losing it costs only a re-mine, so backups may include it but need not.

**Write discipline.** Edges are minted ONLY by batch producers. Producer #1
is `nabu parallels --batch SCOPE` (`Nabu::BatchParallels`): the interactive
intertext engine (§13) looped over every anchor passage of a scope (source
slug or urn prefix — the formulas scope grammar, now shared via
`Query::Scope`), persisting hits as kind=parallel edges. Pruning is named,
never silent: top `--per-anchor` (5) hits clearing `--min-score` (0.05)
persist, and the summary line states both. One edge per unordered pair per
kind (unique-indexed; the direction is the direction the probe found);
a rerun of the same (producer, scope) supersedes the prior run atomically —
edges and run row replaced in one transaction, so reruns are idempotent.
Interactive output is NEVER persisted (design §7: recomputing
costs milliseconds; a stored copy is caching with staleness obligations),
and no flag blurs that line. The same discipline holds for every producer.

**Producers #2/#3 (P16-2).** `nabu formulas --batch SCOPE`
(`Nabu::BatchFormulas`): the whole-tradition formula sweep (§13's miner, one
full-loci pass) persisting kind=formula edges. A formula is a REFRAIN across
N loci, not a pair, so it maps onto the pair-shaped table as a STAR: hub =
the formula's first locus in urn order (deterministic, rebuild-stable),
one edge hub → every other locus, score = the slice count, `detail` = the
folded gram — a reader at any locus sees which refrain ties the line to the
tradition, and `links <hub>` fans out every locus (all-pairs would be O(N²):
2,556 edges for the 72-locus ὣς ἔφαθ' οἵ δ' alone; chains would only show
neighbors). Top `--max-formulas` by rank persist (200); overlapping formulas
sharing a pair coalesce onto the best-ranked gram, counted in the summary.
`nabu cognates --batch WORK` (`Nabu::BatchCognates`): the whole-work cognate
map (§12's join) persisting kind=cognate edges between cross-language witness
passages meeting at a reconstruction root — never within one language;
direction normalized (smaller urn first — the join has no probe direction).
The meet is per-edge meaning, so it rides `detail` (migration 002, the
journal's own forward-only track: nullable, in-place, zero data loss):
"MARK 2.1 · *kaisaraz [gem-pro]" — ref, root, and SHELF, because a gem-pro
meet under a Slavic witness reads as a borrowing (§12). Scope = the work id;
common-word suppression stays on (`--all` lifts it, recorded in params_json).

**Reference producers (#4–#8).** The sync-driven kind=`reference` lane
(each documented in its class comment): #4 `LibraryReferences` (P19-4, the
manifests' `related:` urns — also instantiated under a source's own
producer name for the concordance adapters, P25-1), #5
`CorphDilReferences` (P25-0, token DIL ids), #6 `CclEtymologies` (P28-3,
kind=etymology), #7 `SuttacentralParallels` (P32-6, the sc-data
parallels graph — 195,287 document-grain edges expanded per upstream's own
loader semantics), and #8 `KyotoKanripoCrosswalk` (P33-3, the UD Kyoto
treebank's own `# newdoc id` Kanripo ids — document-grain edges treebank
split-file ↔ `urn:nabu:kanripo:<KR-id>`, minted dangling-but-stable until
each Kanripo wave syncs). SyncRunner re-runs the adapter's declared producer
(`Adapter.reference_producer`) after every load of a `reference_edges?`
source, passing the source's canonical workdir — the seam for the
producers whose input is a canonical FILE (read-only, like the loader)
rather than catalog rows; #7 without its fetched graph file (and #8
without the kyoto treebank on disk) is a no-op that supersedes nothing,
so standing edges survive parse-only syncs.

**Read surface.** `nabu links <urn>` — edges BOTH directions grouped by
kind, each counterpart re-resolved against the *current* catalog by urn
(title/language/license; a counterpart a rebuild dropped reads "(not in
catalog)", honestly), with the producer run(s) cited in the footer and each
kind's evidence rendered natively (a parallel's score, a formula's
“gram” ×count, a cognate's meet). `show <urn>` gains a one-line
`linked: N formula, M parallel` footer counting each kind present, ONLY when
edges exist (zero-signal silence, absent kinds suppressed). MCP adds
`nabu_links`, the tenth read-only tool — same bounded/license-labeled
contract as the rest; it reads persisted edges only (the `detail` field rides
the payload) and never mines (batch runs are owner-fired).

## 16. Canonical memory — local shelves (P19-1)

**The principle.** canonical/ holds the permanent asset; db/ is a derived
index, rebuildable from scratch. P18-4's language notes broke that rule by
making the ledger the home of authored knowledge; the canonical-memory
design (owner-approved 2026-07-14) generalizes the rule instead of patching
the case: **everything nabu KNOWS — fetched corpora, owner-authored
dossiers, locally acquired documents — lives as files under canonical/, in
a `local-<kind>/` shelf when we author or acquire it ourselves. The db only
ever indexes it. The ledger records what HAPPENED (runs, pins, probes),
never what is KNOWN.**

**Local shelves are ordinary sources.** Registry entry, adapter, discovery
accounting, quarantines, rebuild — the whole pipeline applies unchanged,
under the fourth `sync_policy` vocabulary word, **`local`**: no upstream, no
network, ever. Sync = re-scan the tree (`Nabu::LocalFetch`): validates it
exists, sha256-pins every file into the ledger via the existing pin
machinery (one `pins` row per file, keyed `local:<relative path>`), and
reports disappearances. The remote probe short-circuits to the frozen-style
`local` verdict (liveness = the tree itself; license from the shelf's own
manifest/data, never a fetched file); `status` shows `up=local`. Per-file
INTEGRITY is bare `nabu health`'s job: a pinned file that is neither live
nor atticked is a LOUD "vanished" finding (restore from backup, or retire
deliberately); a live file whose bytes changed since the last scan is a
soft "stale derivation" nudge toward the re-scan — owner edits are the
shelf's whole point, not corruption.

**The attic, within honest limits.** LocalFetch runs AFTER any deletion, so
it cannot copy bytes that are already gone: the sanctioned retire flow is
MOVING a file into `canonical/<slug>/.attic/<same relative path>` —
`discover_with_attic` then rediscovers it retained and its derived rows
never vanish. An un-atticked disappearance keeps its last-known sha pinned
(so health stays loud) and, above the house 20% threshold, trips the
mass-deletion breaker before the scan state advances (`--force` overrides).

**The write doctrine.** Application code never writes canonical/ except
through `Adapter#fetch` and the ad-hoc pipeline — and, for local shelves,
through the shelf's ONE sanctioned write gateway, the `Adapter#fetch`
analogue for data that is authored rather than downloaded. For the
local-language shelf that gateway is `Nabu::LanguageShelf`; for the
local-library shelf it is `Nabu::LibraryShelf` (P19-5: copy-in — never
move — plus the mechanical, append-only manifest append) and for the
local-source shelf `Nabu::SourceShelf` (P24-0) — all driven by `nabu
ingest`; for the local-notes shelf it is `Nabu::NoteShelf` (P24-1),
driven by `nabu note`. Everything else stays read-only on the shelves.

**Shelf one: `canonical/local-language/`** — one Markdown + YAML
front-matter dossier per language code (`Nabu::LanguageDossier`): curated
`code/name/family` front matter (any other scalar key — `period`,
`scripts` — is an extra card lane), free prose as the curated context, and
one provenance-headed accretion SECTION per kind
(`## witness:liv (liv, 2026-07-14)`). The P18-4 append-only
latest-per-(code, kind) contract maps verbatim onto files: the section body
IS the latest, supersession = a writer replacing its OWN section (kinds are
writer-owned), never someone else's lane, and idempotency = write only when
the body differs, so re-syncs and rebuild replays are byte-level no-ops.
The `local-language` adapter (`content_kind :language`, the third loader
routing) parses dossiers into the catalog's `language_records` (§5) —
temperature 1, the cleanest one; `nabu verify` re-parses the dossiers and
diffs the derived rows; the P18-7 invariants extend with the
dossier-files-vs-records pair and the pin-integrity check. `nabu language`
reads the merged view unchanged.

**The migration** is owner-fired and ordered so both states are honest at
every step: (1) this code ships with reads falling back to the ledger's
`language_notes` per (code, kind); (2) `nabu language --export-dossiers`
(idempotent, absence-filling, `--dry-run` previews) writes the ledger notes
— seed curation and accretions alike, provenance preserved as section
headers — out as the initial dossier files, then `bin/nabu sync
local-language` derives the records; (3) a LATER packet drops the ledger
table after parity is eyeballed (it cannot ride this one: write paths
auto-migrate the ledger on open, which would drop the notes before the
export ever ran). `config/languages.yml` is retired immediately — the
ledger already accumulated everything it seeded, and one home beats three.

**Shelf two: `canonical/local-library/` (P19-4)** — PDFs, scans and
scholarly articles the owner acquires: one `<collection>/` dir per drop,
each with a `manifest.yml` that is the SOURCE OF RECORD — a YAML list of
entries (`file`, `title`, `creator`, `year`, `languages`, `provenance`,
`license_class`, `tags`, `related`) shaped so `nabu ingest` can append one
mechanically. A file present but
unmanifested is UNRECOGNIZED in the discovery census (awaiting ingest);
manifested but missing is the vanished/attic story above. Unlike the
dossier shelf this one mints DOCUMENTS + PASSAGES (the full conformance
suite applies): `content_kind` stays `:passages` — "article" is document
metadata (`kind: article`, plus creator/year/tags/related, the EDH-persons
pattern), not a fourth loader routing. A PDF with a text layer extracts
via mutool (`Nabu::PdfText`, through `Nabu::Shell`) into PAGE-GRAIN
passages (`…:p12` — the page is the only citation unit a PDF keeps stable,
and the one scholarship cites); a scan that reads clean but blank is a
metadata-only document marked `text_layer: none` (queued for the HTR era,
never quarantined for being a scan); images likewise; a genuinely
unreadable file quarantines. Licensing is the shelf's point: class
`research_private` (MCP default-excluded, never redistributed), applied as
the manifest DEFAULT in one place (`Nabu::LibraryManifest`); an entry's
explicit more-open class is honored as a per-document `license_override`.
The shelf's write path is `nabu ingest FILE... [--collection NAME]`
(P19-5), through the `Nabu::LibraryShelf` gateway — ATOMIC and two-phase
since P20-1 (the GitFetch/ZipFetch prepare/complete mirror): a batch
lands whole or leaves canonical/ byte-identical. PREPARE does everything
fallible against staging only — download urls / existence-check locals
and refuse executables (mode `+x`; shelf material never runs),
sha-account (bytes already MANIFESTED anywhere in the shelf = honest
no-op; same name with new bytes = the loader's ordinary revision),
derive candidates mechanically (PDF Info metadata + a first-page sample
via the `PdfText` seam where mutool exists, filename heuristics and the
sha always), categorize — interactive field-by-field prompts with the
candidates prefilled, an invalid answer re-prompted with a one-line
reason; `--assist CMD` piping a `nabu.ingest-assist/1` JSON brief to a
suggester subprocess (the P18-7 hook pattern; bundled
`script/ingest-assist-claude`) whose answer PREFILLS the same prompts
(never lands unreviewed without `--yes`); or `--yes` + flags for
scripted drops (an invalid value fails the batch) — then REHEARSE the
collection's future manifest through the real `LibraryManifest` parser
(language tags validated with the model's own rule), so an entry the
loader would reject cannot exist. Only a fully validated batch COMMITS:
per file, copy in (never move) + append one manifest entry (a freak
append failure rolls that file's copy back); then the shelf's ordinary
sync runs and the minted urns print. Any prepare defect aborts the whole
batch — one named FAILED line per defect, the rest `aborted`, canonical
untouched, exit 1. The default collection is `inbox`, argued over a
date-based name: the collection is a FROZEN urn segment, and one visible
triage collection with one accumulating review-surface manifest beats a
manifest-per-day scatter that bakes an acquisition accident into
identity. `--shelf language CODE` is the same front door for the dossier
shelf: a THIN scaffold (front matter + context, same three modes) through
`Nabu::LanguageShelf`, then the dossier sync. Owner hand-placement plus a
manual sync stays legitimate — the census flags whatever ingest has not
catalogued.

**Shelf three: `canonical/local-source/` (P24-0)** — the canonical-memory
doctrine extended to the SOURCE grain: one Markdown + YAML front-matter
dossier per REGISTERED SOURCE (`Nabu::SourceDossier`,
`canonical/local-source/<slug>.md`) — what each shelf holds, in the
owner's words. Curated lanes: `description` (THE load-bearing field, a 1–3
sentence content description served on `nabu list` cards, the `--long`
census, and the MCP status payload by default — the owner's own library
metadata is useful context), `themes` (list), `key_works` (urn list), any
other scalar as an extra lane, free prose as the curated NOTE lane, and
provenance-headed accretion sections under the language shelf's
append-only latest-per-(slug, kind) contract verbatim. The `local-source`
adapter (`content_kind :source`, the fourth loader routing) parses
dossiers into the derived `source_records` (migration 015 —
slug/kind/body/provenance, temperature 1, replaced per slug); `nabu
verify` re-parses and diffs; the P18-7 invariants' populated/files-vs-
records checks cover both dossier grains. Populated by the owner-fired
one-shot `nabu list --export-source-dossiers` (idempotent, existing
dossiers untouched): descriptions seed from the best EXISTING prose —
docs/library.md per-shelf sections and bullets, then sources.yml
standalone shelf comments — and where none exists the dossier is an
HONEST STUB that says so, never invented content. Per-source scaffolds go
through `nabu ingest --shelf source SLUG` (the language scaffold's thin
three-mode pattern, description prefilled from the registered source's
name). The dossiers are gate-checked, never generated: `rake site:check`
(the P24-0 gate rider) flags PRESENCE/MENTION drift — a registered source
without a dossier, a docs/library.md-mentioned shelf whose dossier lacks
a description, an enabled described shelf the library review never
mentions — never verbatim equality (the two registers legitimately
diverge in wording; site/library.md is covered transitively as the
printed map of docs/library.md). Exit 1 on drift, findings listed.

**The `related:` edges.** Manifest `related:` URNs become kind=`reference`
edges in the links journal (producer `library`, scope = the source slug),
refreshed by every local-library sync AFTER the load (SyncRunner →
`Nabu::LibraryReferences`, superseding the prior run — the journal always
holds the current manifests' assertions; a lost journal costs one
no-network re-sync). Edges carry no score (a manifest assertion is owner
curation, not a mined similarity); `detail` names the asserting manifest.
`Query::Links` resolves counterparts at passage grain first, then DOCUMENT
grain, so `nabu links <urn>` shows an article beside the passages it
discusses from either end. Language codes in `related:` stay document
metadata only: P19-1 minted no dossier urns, and an edge to an invented
urn would sit permanently unresolved — codes upgrade to edges if dossier
documents ever exist.

**Shelf three: `canonical/local-notes/` (P24-1)** — the owner's annotation
lane, scholia of one's own: curatorial notes keyed by ANY urn the corpus
knows — a document, a passage, a range, a dictionary entry (P22-2's minted
urns included). One YAML file per TOPIC (`<topic>.yml`, default `notes` —
grouping is the owner's whim), each a YAML LIST of records
(`urn`/`note`/`added`/optional `tags`) so the gateway appends one
mechanically without rewriting the owner's bytes; hand-edits are welcome
(the file is the record) and parse validates every record, naming defects
file+entry (`Nabu::NoteFile`). The gateway (`Nabu::NoteShelf`, driven by
`nabu note URN [TEXT]` — scripted with TEXT, interactive on a TTY, an
honest refusal piped; `nabu note URN` alone reads back) resolves the urn
against the catalog BEFORE any write (Query::Show's resolution, dictionary
urns included): a typo'd urn is an error naming the miss, while `--force`
records a note on a not-yet-held urn deliberately (planned material) and
such notes read "(dangling)" at render until the urn arrives. The append is
atomic with the LibraryShelf discipline: reparse-validate through the real
parser, rollback to the prior bytes on rejection. The `local-notes` adapter
(`content_kind :notes`, the fourth loader routing → `Store::NoteLoader`)
indexes topics into the derived `urn_notes` (migration 015) — temperature
1, replaced per topic wholesale, swept on full loads, rebuilt by `nabu
rebuild`; `nabu verify` re-parses the topic files and diffs the derived
rows (the dossier pattern). Render is the point: `show` prints an "owner
note (topic, date): …" footer (a document also counts its passage-note
children), `define` prints entry notes after the body, `links` shows an
owner-notes lane, `nabu note --list` enumerates (bounded, dangling urns
flagged) — and the MCP surface serves notes BY DEFAULT on
nabu_show/nabu_define (owner ruling: your own library metadata is useful
context), attached strictly AFTER the withhold gate so a note on a
research_private/restricted document is withheld with its target: a note
must never leak a withheld text's content frame. The shelf itself is class
`open` (owner-authored, the local-language argument).

**What this does not change.** The ledger keeps runs/pins/probes/revisions;
the links journal keeps batch edges; `nabu language`'s command surface is
unchanged. Future local shelves follow the same pattern: files + manifest +
adapter + one sanctioned write gateway, with `nabu ingest` as the shared
intake front door.
