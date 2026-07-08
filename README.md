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
catalog store, idempotent loader, rebuild) and **nine source adapters**
exist across **four parser families** (EpiDoc/CTS, CoNLL-U, PROIEL XML,
DDbDP Leiden): **seven sources live** — Perseus Greek and **Perseus Latin** (Iliad, Aeneid,
and Livy included, **with 872 aligned English translations**:
`show <urn> --parallel` — Vergil pairs line-by-line), First1KGreek,
Universal Dependencies ancient treebanks, PROIEL, TOROT, and Papyri.info
DDbDP (61k documents, restart-aware line URNs, cancelled texts kept in ⟦⟧)
— totalling **~2.13 million searchable passages** — plus **GRETIL**
(Sanskrit: Ṛgveda with Vedic accents preserved, CC BY-NC-SA) shipped and
awaiting its first sync, and **ORACC** (cuneiform, CC0, gold-lemmatized)
scouted as the next headline. A Slavic-sources survey
(`docs/slavic-survey.md`) ranks the axis's expansion candidates.
**The collection is protected end to end**: upstream deletions land in a
local attic and stay searchable ("retired upstream"); run history, license
baselines, and revision records live in a ledger no rebuild can wipe; and
`nabu backup` snapshots everything to a mounted external volume — with a
restore drill (`rake ops:drill`) that has actually passed against the full
corpus: backup → fresh-root restore → rebuild → verify → RESTORABLE.
**The research surface is real**: search is diacritic-insensitive with
per-language search forms (Greek final-sigma, Latin v/u–j/i — conventions
§9) and **lemma-aware** — `search --lemma λέγω` finds every inflected
attestation (εἶπον, ῥηθέντος, …) across the 161k gold-annotated treebank
passages; `show` renders passages, documents, **citation ranges**
(`urn:…:1.1-1.10`), and parallel translations (span-grouped: prose blocks
cite exactly which lines they cover); `concord` prints classic KWIC lines
in pristine text. **And the corpus talks**: a read-only MCP server
(`bin/nabu mcp`, hand-rolled stdio; `.mcp.json` ships in-repo) gives any
Claude session four tools — search, show, concord, status — every passage
carrying its license class; see `docs/mcp.md`. Health (local trends +
no-clone upstream probe), fixture drift checks, and launchd ops templates
round out the custodial surface.

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
| `bin/nabu search --lemma FORM [--lang X]` | Dictionary-form search over the gold treebank annotations (~161k passages, 1.6M lemma rows): `--lemma λέγω` finds εἶπον, ῥηθέντος and the rest of the paradigm, showing the matched surface forms per hit. |
| `bin/nabu show URN` | Inspect a passage (text, document, license, revision, full provenance trail), a whole document (passages as `:suffixes`; `--full-urn` for absolutes), or a citation range (`urn:…:1.1-1.10`, inclusive, cross-block). Withdrawn and retired items shown, honestly labeled. |
| `bin/nabu show URN --parallel [LANG]` | Render a passage/document/range aligned with its translation edition of the same work (default eng), paired by citation; unmatched lines shown honestly one-sided. |
| `bin/nabu export --format plain\|jsonl [--lang X] [--license CLASS]` | Stream the live corpus to stdout — the longevity-hedge exit formats (CoNLL-U arrives with the enrichment phase) |
| `bin/nabu verify` | Re-parse every canonical file (attic included) and compare content hashes against the catalog — the cronnable bitrot/tamper check. Exit 0 clean, 1 on any mismatch. |
| `bin/nabu health` | Local anomaly report, no network: per-source run-history trends (quarantine spikes, added-collapse, withdrawal/retirement creep, staleness) plus a replay of the golden queries against the live corpus. Exit 1 on any loud finding. |
| `bin/nabu health --remote` | No-clone upstream probe: `ls-remote` liveness, remote-HEAD-vs-last-sync drift, and best-effort license-file change detection per source. Exit 1 only if an upstream is gone. |
| `rake fixtures:check[source]` | Re-fetch pinned fixture URLs into tmp, byte-diff against the checked-in fixtures, and run the adapter tests against the fresh copies — the upstream-format drift report. Never overwrites; `fixtures:refresh[source]` is the explicit adoption path. |
| `bin/nabu backup [--dry-run] [--skip-derived]` | File-level rsync of everything not re-derivable (canonical + attic, the history ledger, config; derived dbs by default) to the configured external volume. Refuses to run when the volume is not mounted. |
| `bin/nabu concord QUERY\|--lemma FORM [--width N]` | Classic KWIC concordance: keyword column-aligned in pristine text, context trimmed per side, corpus order — for scanning usage, not relevance. |
| `bin/nabu mcp` | The read-only MCP server (stdio): search/show/concord/status as conversational tools for Claude Code/Desktop — registration recipes in `docs/mcp.md`. |
| `rake ops:drill` | The fresh-machine restore drill: backup → restore into a tmp root → rebuild → verify → golden replay → counts cross-check. Exit 0 = RESTORABLE. |

Every query command carries worked examples and syntax notes inline:
`bin/nabu help search` (FTS5 syntax, filters), `help show` (urn shapes
across the corpora, ranges, --parallel), `help export` (formats, jq recipes).

Configuration lives in `config/nabu.yml` (paths; commented example shipped)
and `config/sources.yml` (the source registry: adapter class, enabled
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
- **Five parser families, nine adapters** — all streaming, all tested against
  real upstream fixtures: EpiDoc/CTS (Perseus Greek + Latin, First1KGreek), CoNLL-U
  (Universal Dependencies treebanks: Gothic, Ancient Greek, Vedic Sanskrit,
  Latin — lemmas and morphology preserved in annotations), PROIEL XML
  (PROIEL, TOROT — Old Church Slavonic and Old Russian), GRETIL TEI
  (Sanskrit: three addressability rungs, in-text verse-marker mining), and DDbDP
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
