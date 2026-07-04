# Nabu

Personal research infrastructure for ingesting the world's digitized ancient
texts — Greek, Latin, Old Church Slavonic, Sanskrit, Gothic, cuneiform, and
beyond — into a single, locally-owned, queryable store. Named for the
Mesopotamian god of scribes, patron of the tablet house.

A pipeline plus a database, operated from the command line: upstream corpora
live as files in a git-tracked **canonical layer**; SQLite (catalog, FTS,
vectors) is entirely **derived** and can be rebuilt from canonical data at any
time. See `docs/01-concept.md` for the full vision,
`docs/architecture.md` for the design, and `docs/conventions.md` for the
field notes (Unicode/NFC, citation systems, editions, licensing) that explain
*why* the code enforces what it enforces — start there if you're new to
ancient-text corpora.

**Status: early development.** The core domain is built (adapter contract,
catalog store, idempotent loader, rebuild) and **six source adapters** exist
across **four parser families** (EpiDoc/CTS, CoNLL-U, PROIEL XML, DDbDP
Leiden): Perseus canonical Greek (**live** — 744 documents / 238k passages
synced), First1KGreek, Universal Dependencies ancient treebanks, PROIEL,
TOROT, and Papyri.info DDbDP (each awaiting its first owner-verified sync).
**The full CLI surface is now real** — sync, status, rebuild, search
(diacritic-insensitive FTS), show, export, verify; no stubs remain.

## Requirements

- Ruby 3.3+ (macOS/Apple Silicon is the development platform)
- `bundle install` pulls the deliberately small dependency set (thor, sequel,
  sqlite3, nokogiri, faraday + test tooling)

## What works today

| Command | Does |
|---|---|
| `bin/nabu version` | Print the version |
| `bin/nabu status` | Per-source overview: enabled/policy, live document & passage counts, last run and its counts. Degrades gracefully with no registered sources or no database. |
| `bin/nabu rebuild` | Drop the derived catalog db and regenerate it from `canonical/` by replaying every registered source through its adapter — parse-only, never touches the network. Prints per-source counts and warnings. |
| `bin/nabu rebuild --dry-run` | Show exactly what a rebuild would do (db file affected, which sources replay vs. skip) without changing anything |
| `bin/nabu sync <slug>` | Fetch a source's upstream snapshot (git, into `canonical/<slug>/`) and load it into the catalog under a recorded run. Explicit-by-slug syncs even disabled sources (with a note). |
| `bin/nabu sync --all` | Sync every *enabled* source with `sync_policy: live` — the unattended path; one source's failure doesn't stop the others |
| `… --parse-only` | Re-parse the existing local snapshot without touching the network (after parser fixes) |
| `… --force` | Override the safety breaker that aborts any sync which would withdraw >20% of a source's documents (upstream restructures look like mass deletions) |
| `bin/nabu search QUERY [--lang X] [--license CLASS] [--limit N]` | Full-text search over the corpus (FTS5, bm25-ranked). Diacritic-insensitive: `μηνιν` finds `μῆνιν`. Prints urn, language, highlighted snippet per hit. |
| `bin/nabu show URN` | Inspect a passage (text, document, license, revision, full provenance trail) or a whole document (ordered passages). Shows withdrawn items, honestly labeled. |
| `bin/nabu export --format plain\|jsonl [--lang X] [--license CLASS]` | Stream the live corpus to stdout — the longevity-hedge exit formats (CoNLL-U arrives with the enrichment phase) |
| `bin/nabu verify` | Re-parse every canonical file and compare content hashes against the catalog — the cronnable bitrot/tamper check. Exit 0 clean, 1 on any mismatch. |

Configuration lives in `config/nabu.yml` (paths; commented example shipped)
and `config/sources.yml` (source registry: adapter class, enabled flag,
sync policy — currently an empty commented example, populated when the first
adapter lands).

## What exists under the hood

- **Domain model** — validating value objects (`Passage`, `DocumentRef`,
  `SourceManifest`, `Document`): construction rejects non-NFC text, malformed
  language tags, unknown license classes. Licensing is data, per passage.
- **Adapter contract** — one small base class (`fetch` / `discover` / `parse` /
  `manifest`); every future adapter must pass a shared conformance suite
  (URN uniqueness across the corpus, URN stability across parses, NFC output).
- **Four parser families, six adapters** — all streaming, all tested against
  real upstream fixtures: EpiDoc/CTS (Perseus **live**, First1KGreek),
  CoNLL-U (Universal Dependencies treebanks: Gothic, Ancient Greek, Vedic
  Sanskrit, Latin — lemmas and morphology preserved in annotations), PROIEL
  XML (PROIEL, TOROT — Old Church Slavonic and Old Russian), and DDbDP
  (Papyri.info documentary papyri, with a print-practice Leiden
  text-extraction policy — see `docs/conventions.md` §5).
- **Catalog store** — SQLite via Sequel: sources, documents, passages,
  provenance, enrichments, runs; forward-only migrations.
- **Loader** — content-hash idempotency: re-loading unchanged data writes
  nothing; changed content bumps a revision and journals the old hash;
  upstream deletions withdraw rows (nothing is ever hard-deleted); parse
  failures quarantine a document without aborting the batch.
- **Rebuild invariant** — the derived db is a pure function of `canonical/`,
  proven by test: two rebuilds produce identical passage rows.

## Development

```
rake test        # full suite (network-blocked by WebMock; fast)
rake lint        # rubocop
bin/nabu --help
```

TDD is the workflow; see `CLAUDE.md` for the ground rules and
`docs/dev-loop.md` for how this project is built (a model-tiered autonomous
dev loop with owner-approved phase gates — this README is updated at every
gate to reflect what actually works).

## License

Code: TBD. Ingested corpora keep their upstream licenses, recorded per
document — see `docs/02-sources.md`.
