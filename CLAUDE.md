# CLAUDE.md — Nabu project

Nabu: personal research infrastructure for ingesting ancient-text corpora into a local SQLite-backed store. Ruby 3.3+, macOS (Apple Silicon), no cloud dependencies required at runtime. Read `docs/architecture.md` before structural changes; read `docs/02-sources.md` before touching any adapter.

## Ground rules

- **TDD is the workflow, not a suggestion.** Write or update the failing test first, then implement, then refactor. If asked to add behavior, produce the test in the same change. Never mark work done with a red suite.
- **Never touch `canonical/` from application code except through `Adapter#fetch`, the ad-hoc pipeline, and a local shelf's one sanctioned write gateway (`Nabu::LanguageShelf` for dossiers, `Nabu::LibraryShelf` for the library and `Nabu::SourceShelf` for source dossiers — driven by `nabu ingest` — and `Nabu::NoteShelf` for owner notes, driven by `nabu note`; the fetch analogues for authored/acquired-not-downloaded data, architecture §16).** Canonical data is the permanent asset. Loader and enrichers are read-only on it.
- **Derived data must stay rebuildable.** Any feature that writes to `db/` must survive `nabu rebuild` (drop db, regenerate from canonical + enrichment journal). If a change breaks that invariant, stop and flag it.
- **No network in tests. Ever.** WebMock blocks all HTTP in the suite; adapter tests run against fixtures in `test/fixtures/<source>/`.
- **Small diffs.** One adapter, one parser family, or one CLI command per PR-sized change. Don't refactor opportunistically across the codebase while implementing a feature.
- **Ask before adding a gem.** The dependency budget is deliberately small (thor, sequel, sqlite3, nokogiri, faraday, rubocop, minitest, webmock). Justify anything new in the commit message.

## Commands

```
rake test                 # full suite (must pass before any commit)
rake test TEST=test/adapters/perseus_test.rb
rake lint                 # rubocop
rake lint:fix             # rubocop -a (safe corrections only)
bin/nabu --help
bin/nabu sync <source> --parse-only   # re-parse without network
bin/nabu rebuild --dry-run
rake fixtures:refresh[source]           # re-snapshot upstream sample (network, manual only)
```

## Ruby conventions

- Ruby 3.3, `# frozen_string_literal: true` everywhere, pattern matching encouraged in parser code (`case node in ...`).
- Plain Ruby objects; no Rails, no ActiveSupport. `Data.define` for value objects (`Passage`, `DocumentRef`, `SourceManifest`).
- Keyword arguments for anything with more than two params. No boolean positional args.
- Errors: subclass `Nabu::Error`; adapters raise `Nabu::ParseError` (quarantines document) vs `Nabu::FetchError` (aborts sync). Never rescue `StandardError` bare.
- Text is always UTF-8 NFC internally. Normalize at the adapter boundary (`Nabu::Normalize.nfc`), never downstream. Any encoding fix gets a regression test with the offending bytes as fixture.
- SQL only through Sequel datasets/models in `lib/nabu/store/`. No SQL strings elsewhere. Schema changes only via numbered migrations in `db/migrate/`; never edit an applied migration.
- Shelling out (mutool, git): through `Nabu::Shell.run` (captures stdout/stderr, raises on nonzero) — never backticks scattered in code.

## Testing conventions (Minitest)

- Test files mirror lib: `lib/nabu/adapters/perseus.rb` → `test/adapters/perseus_test.rb`.
- **Fixtures are small, real upstream samples** (2–3 documents per source, trimmed but structurally intact), checked into git. Never hand-write fake TEI/CoNLL-U — trimmed real files only, so fixtures document actual upstream quirks.
- Every adapter must pass the **shared conformance suite** (`test/support/adapter_conformance.rb`): manifest validity, discover→parse round-trip, URN uniqueness and stability across two parses, NFC output, non-empty passages, license class present. New adapter = include conformance suite + source-specific tests.
- Store tests run against in-memory SQLite (`sqlite::memory:`) with migrations applied fresh.
- Idempotency is always tested: load fixture twice, assert row counts and revisions unchanged.
- Enricher tests stub model calls (WebMock); one recorded-shape fixture per API so response parsing is tested against reality.

## How to add a new adapter (checklist)

1. Read the source's entry in `docs/02-sources.md`; confirm license and note `license_class`.
2. `rake fixtures:refresh[<source>]` won't exist yet — manually snapshot 2–3 small real documents into `test/fixtures/<source>/`, with a `README.md` noting retrieval date and URL.
3. Write `test/adapters/<source>_test.rb`: include conformance suite, add source-specific assertions (expected URNs, passage counts, a known text snippet).
4. Implement `lib/nabu/adapters/<source>.rb`, composing an existing parser family if one fits. If a new parser family is needed, it gets its own class + tests first.
5. Register in `config/sources.yml` (`enabled: false` until first real sync is verified).
6. Run a real `bin/nabu sync <source>` manually; eyeball `nabu status` counts and 5 random passages (`nabu show`); then flip `enabled: true`.
7. Update `docs/02-sources.md` status column.

## Claude Code working agreements

- **Surveys and consideration documents go to gitignored `.docs/` (surveys under `.docs/surveys/`), never `docs/`.** The repo is public; scouting reports, strategy briefs, and any document produced for the owner's consideration are working material, not publications. Publishing into `docs/` is the owner's explicit decision. (2026-07-16: ALL surveys, including formerly public ones, live in `.docs/surveys/` — `docs/*-survey.md` paths in older text are historical.) (Agents in worktrees: gitignored files don't cross merges — deliver consideration material via your final report instead.)

- **Plan before code on anything multi-file.** State the file list and test plan first; wait for nothing — proceed — but the plan goes in the response so drift is visible.
- When a test fails, fix the code or the test's incorrect expectation — never weaken an assertion to green. If upstream fixture reality contradicts the spec, say so explicitly.
- Don't invent upstream formats. If unsure how a source structures its data, inspect the fixture; if there is no fixture, ask for one rather than guessing.
- Long-running/network operations (real syncs, fixture refresh) are human-initiated only. Claude Code runs `rake test` and `rake lint` freely.
- Keep `docs/architecture.md` truthful: if an implementation decision deviates from it, update the doc in the same change.
- Commit messages: imperative summary line, body explains *why*, references doc section if implementing planned work. One logical change per commit.

## Things that look like good ideas but aren't

- Parsing giant TEI with DOM: use SAX/Reader for anything over ~5 MB (Perseus has such files).
- "Cleaning up" upstream text (fixing typos, modernizing orthography) during parse — canonical means canonical; corrections are enrichments.
- Cross-adapter shared state or clever registries with autoloading magic — explicit `require` + explicit registry in `sources.yml`.
- Storing embeddings or big JSON in `catalog.sqlite3` — vectors go in `vectors.sqlite3`, bulky derived payloads in `enrichments`.
- Hard-deleting anything from the catalog. Withdraw, revise, journal.
- Destructive fetch — a plain `git pull` in canonical/. A pull deletes working-tree files upstream scrapped, and since `db/` is a pure function of `canonical/`, the next rebuild silently loses those documents. All git fetching goes through `Nabu::GitFetch` (fetch objects → breaker → attic upstream deletions under `canonical/<slug>/.attic/` → ff-merge); see architecture §8.
