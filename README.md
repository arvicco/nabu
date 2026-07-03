# Nabu

Personal research infrastructure for ingesting the world's digitized ancient
texts — Greek, Latin, Old Church Slavonic, Sanskrit, Gothic, cuneiform, and
beyond — into a single, locally-owned, queryable store. Named for the
Mesopotamian god of scribes, patron of the tablet house.

A pipeline plus a database, operated from the command line: upstream corpora
live as files in a git-tracked **canonical layer**; SQLite (catalog, FTS,
vectors) is entirely **derived** and can be rebuilt from canonical data at any
time. See `docs/01-concept.md` for the full vision and
`docs/architecture.md` for the design.

**Status: early development.** The core domain is built (adapter contract,
catalog store, idempotent loader, rebuild); no source adapters exist yet, so
Nabu cannot ingest real corpora at this point. The first adapter (Perseus
canonical Greek/Latin) is next.

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
| `bin/nabu sync` / `search` / `show` | **Not implemented yet** — stubs that say so and exit 1 (sync arrives with the first adapter in Phase 2; search in Phase 4) |

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
