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
Leiden): **all six sources live** — Perseus, First1KGreek, Universal
Dependencies ancient treebanks, PROIEL, TOROT, and Papyri.info DDbDP
(61k documents, restart-aware line URNs) — totalling **~1.55 million
searchable passages**.
**The collection is protected**: upstream deletions land in a local attic
and those documents stay searchable, labeled "retired upstream" — nothing
the corpus once held can be destroyed by upstream removals, license
reversals, or a rebuild. **The full CLI surface is real** — sync, status,
rebuild, search (diacritic-insensitive FTS), show, export, verify, and
health (local anomaly trends plus a no-clone upstream probe); fixture drift
is checked by `rake fixtures:check`, and `docs/ops.md` ships launchd
templates for the nightly/weekly maintenance cadence.

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
| `bin/nabu show URN` | Inspect a passage (text, document, license, revision, full provenance trail) or a whole document (passages listed as `:suffixes` relative to the document urn; `--full-urn` for absolutes). Withdrawn and retired items shown, honestly labeled. |
| `bin/nabu export --format plain\|jsonl [--lang X] [--license CLASS]` | Stream the live corpus to stdout — the longevity-hedge exit formats (CoNLL-U arrives with the enrichment phase) |
| `bin/nabu verify` | Re-parse every canonical file (attic included) and compare content hashes against the catalog — the cronnable bitrot/tamper check. Exit 0 clean, 1 on any mismatch. |
| `bin/nabu health` | Local anomaly report, no network: per-source run-history trends (quarantine spikes, added-collapse, withdrawal/retirement creep, staleness) plus a replay of the golden queries against the live corpus. Exit 1 on any loud finding. |
| `bin/nabu health --remote` | No-clone upstream probe: `ls-remote` liveness, remote-HEAD-vs-last-sync drift, and best-effort license-file change detection per source. Exit 1 only if an upstream is gone. |
| `rake fixtures:check[source]` | Re-fetch pinned fixture URLs into tmp, byte-diff against the checked-in fixtures, and run the adapter tests against the fresh copies — the upstream-format drift report. Never overwrites; `fixtures:refresh[source]` is the explicit adoption path. |

Every query command carries worked examples and syntax notes inline:
`bin/nabu help search` (FTS5 syntax, filters), `help show` (urn shapes
across all six corpora), `help export` (formats, jq recipes).

Configuration lives in `config/nabu.yml` (paths; commented example shipped)
and `config/sources.yml` (the six-source registry: adapter class, enabled
flag, sync policy — with per-source sign-off notes). `docs/ops.md` documents
the maintenance cadence (nightly verify, weekly sync + health) with
ready-to-install launchd templates under `ops/launchd/` — nothing runs
unless you install it.

## What exists under the hood

- **Domain model** — validating value objects (`Passage`, `DocumentRef`,
  `SourceManifest`, `Document`): construction rejects non-NFC text, malformed
  language tags, unknown license classes. Licensing is data, per passage.
- **Adapter contract** — one small base class (`fetch` / `discover` / `parse` /
  `manifest`); every future adapter must pass a shared conformance suite
  (URN uniqueness across the corpus, URN stability across parses, NFC output).
- **Four parser families, six adapters** — all streaming, all tested against
  real upstream fixtures: EpiDoc/CTS (Perseus, First1KGreek), CoNLL-U
  (Universal Dependencies treebanks: Gothic, Ancient Greek, Vedic Sanskrit,
  Latin — lemmas and morphology preserved in annotations), PROIEL XML
  (PROIEL, TOROT — Old Church Slavonic and Old Russian), and DDbDP
  (Papyri.info documentary papyri: print-practice Leiden text extraction —
  see `docs/conventions.md` §5 — and restart-aware line-URN minting).
- **Catalog store** — SQLite via Sequel: sources, documents, passages,
  provenance, enrichments, runs; forward-only migrations.
- **Loader** — content-hash idempotency: re-loading unchanged data writes
  nothing; changed content bumps a revision and journals the old hash;
  upstream deletions withdraw rows (nothing is ever hard-deleted); parse
  failures quarantine a document without aborting the batch.
- **The retention contract** — fetch is non-destructive (`Nabu::GitFetch`):
  files upstream deletes are copied to `canonical/<slug>/.attic/` *before*
  the merge, and the documents load as `retired_upstream` — still live,
  searchable, and exportable, keeping the license they were fetched under.
  The mass-deletion breaker runs before any tree mutation, so an aborted
  sync leaves canonical byte-unchanged. See `docs/architecture.md` §8.
- **Rebuild invariant** — the derived db is a pure function of `canonical/`
  (the attic included, so retired documents survive every rebuild),
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
