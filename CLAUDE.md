# CLAUDE.md — Nabu project

Nabu: personal research infrastructure for ingesting ancient-text corpora into a local SQLite-backed store. Ruby 3.3+, macOS (Apple Silicon), no cloud dependencies required at runtime. Read `docs/architecture.md` before structural changes; read `docs/02-sources.md` before touching any adapter.

## Sister projects — the Nabu family (consult BEFORE proposing any new repo or data home)

Nabu is the hub of a family of small sibling repos, each a `kind: module` source fetched into `canonical/<slug>/` (check `canonical/<slug>` **and** `~/Dev/<slug>`) and read back through a seam. **Before proposing a new repository, or a new home for derived / curated / reference data, check this list first** — the space is almost always already owned by a sister; a genuinely new sister is an owner decision, never an assumption.

| Repo | What it is | Direction | Seam |
|---|---|---|---|
| **nabu-lects** (`arvicco/nabu-lects`) | lect / language-stage registry — anchors, stages, codemap | consumed | `Nabu::Lects` |
| **nabu-places** (`arvicco/nabu-places`) | place-matching decisions registry (the lects pattern for places) | consumed | `Nabu::Places` |
| **nabu-data** (`arvicco/nabu-data`) | derived datasets (CLDF + Frictionless), DOI'd on Zenodo | **two-way** — Nabu produces via `nabu data build` **and** consumes back | `Nabu::FormLemma`, `Nabu::LanguageDossiers`, … |
| **nabu-edubba** (`arvicco/nabu-edubba`) | the sister school's curated didactic overlay (sign pedagogy) | **two-way** — edubba consumes Nabu's exports downstream; its curated data feeds back (its frequency TSVs are NEVER re-imported — circularity guard) | `Nabu::EdubbaOverlay` |

**Publications/mints into any sister ride as prepared PRs I open** (branch → build → push → `gh pr create` on `arvicco/<sister>`, body explaining the USE CASE); the owner reviews + merges, and any release/DOI (e.g. nabu-data's Zenodo mint) stays the owner's identity act. Nabu-side targets depending on a sister node stay queued (a work-queue entry naming the PR) until the mint merges and reaches `canonical/<slug>`. Mechanics: architecture §16 (shelves) / §17 (the nabu-data rail); the lect-mint specifics are the adapter-checklist step below; nabu-data's producer contract is docs/nabu-data.md.

## Ground rules

- **TDD is the workflow, not a suggestion.** Write or update the failing test first, then implement, then refactor. If asked to add behavior, produce the test in the same change. Never mark work done with a red suite.
- **Never touch the permanent folders from application code except through the sanctioned gateways.** `canonical/` (the fetched asset) is written only by `Adapter#fetch` and the ad-hoc pipeline; the owner shelves under `local/shelves/` (P71) only by their one write gateway each (`Nabu::LanguageShelf` for dossiers, `Nabu::LibraryShelf` for the library and `Nabu::SourceShelf` for source dossiers — driven by `nabu ingest` — and `Nabu::NoteShelf` for owner notes, driven by `nabu note`; architecture §16); the instance config under `local/config/` only by its write-through CLIs (lect assign, grants, accept-creep, the batch link CLIs). Loader and enrichers are read-only on all of it.
- **Derived data must stay rebuildable — the derivability law (owner-ruled 2026-08-11).** ONLY derived data lives under `db/`: any feature that writes there must survive `nabu rebuild` (drop db, regenerate from the three permanent folders — `canonical/` the asset, `config/` the project definition, `local/` the instance: owner rulings, shelves, the ledger, acquisitions). Anything non-derivable (paid model output, HTR — anything costing money, network, or human review to regenerate) lands in a local shelf through a sanctioned gateway, never in db/. If a change breaks that invariant, stop and flag it.
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
- Text is always UTF-8 NFC internally — except the named exemption list (`Normalize::NFC_EXEMPT_LANGUAGES`, currently hbo/arc: Masoretic combining-mark order is not NFC-stable and upstream forbids normalizing; owner ruling 2026-07-18, architecture §3). Normalize at the adapter boundary (`Nabu::Normalize.nfc`), never downstream. Any encoding fix gets a regression test with the offending bytes as fixture.
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
5. Register in `config/sources.yml` (`wired: false` until first real sync is verified).
6. `bin/nabu enable <source>` (the box-local profile step — sync refuses un-enabled sources), then run a real `bin/nabu sync <source>` manually; eyeball `nabu status` counts and 5 random passages (`nabu show`); then flip `wired: true`.
7. **Core-layer postures (P59-4/P61-0 — no adapter without them):** run `bin/nabu layer suggest <source>` after the first sync, then record the postures — for lects a rule in `config/lect_facet_rules.yml` or an override row in `config/lect_overrides.yml` (both need an owner ruling), or a `lect:` declaration in `config/postures.yml` (`identity` — the bare code is the claim — is an honest answer; `pending` must name its candidate); dating/places/script declarations likewise (`undatable`/`unplaced`/`implied` are honest answers). The suite fails on a posture-less source.
8. **Sister mints ride as PRs (owner rule 2026-08-13, generalized 2026-08-28) — see the Sister projects section above for the family and the PR discipline.** The lect case, in full: if the source's lect/language claims need registry nodes that don't exist (a new anchor, stage, or codemap row — check `canonical/nabu-lects` AND `~/Dev/nabu-lects`), formulate a small lect package immediately: a branch + PR on `arvicco/nabu-lects` (lects.yml/codemap.yml + CHANGELOG entry, `bin/validate` green) whose body explains the USE CASE — which source, which claim, what the census shows, what stays deliberately coarse. **Concurrent mints aggregate into ONE PR** (owner rule 2026-08-13: every package touches the codemap alias suite and the CHANGELOG head, so parallel PRs conflict on the first merge — batch them). Nabu-side rules/codemap targets stay queued (work-queue entry naming the PR) until the mint merges and reaches `canonical/nabu-lects`; the posture records the blocked state honestly. Precedents: nabu-lects PR #3 (ast/an, OSTA; merged) and PR #4 (sv:old + it:old aggregated after its halves conflicted as separate PRs).
9. Update `docs/02-sources.md` status column.

## Claude Code working agreements

- **Surveys and consideration documents go to gitignored `.docs/` (surveys under `.docs/surveys/`), never `docs/`.** The repo is public; scouting reports, strategy briefs, and any document produced for the owner's consideration are working material, not publications. Publishing into `docs/` is the owner's explicit decision. (2026-07-16: ALL surveys, including formerly public ones, live in `.docs/surveys/` — `docs/*-survey.md` paths in older text are historical.) (Agents in worktrees: gitignored files don't cross merges — deliver consideration material via your final report instead.)

- **Plan before code on anything multi-file.** State the file list and test plan first; wait for nothing — proceed — but the plan goes in the response so drift is visible. **At planning time, consult the Sister projects section**: any new home for derived / curated / reference data almost always belongs to an existing sister (nabu-lects / nabu-places / nabu-data / nabu-edubba), not a new repo — verify against the family before proposing one.
- When a test fails, fix the code or the test's incorrect expectation — never weaken an assertion to green. If upstream fixture reality contradicts the spec, say so explicitly.
- Don't invent upstream formats. If unsure how a source structures its data, inspect the fixture; if there is no fixture, ask for one rather than guessing.
- Long-running/network operations (real syncs, fixture refresh) are human-initiated only. Claude Code runs `rake test` and `rake lint` freely.
- Keep `docs/architecture.md` truthful: if an implementation decision deviates from it, update the doc in the same change.

- **Site freshness rides the phase gate, from one source of truth.** At every gate, *after* the gate's syncs and re-parses land (so the catalog is the state being published), run `bundle exec rake site:refresh` — it regenerates `site/_data/census.yml` (the SSOT: every library-wide headline number — documents, passages, codes, sources, dictionary/gold/silver totals, desk count — stamped today) and the axis pages from the live catalog. The site's prose pages render those figures through Liquid (`{{ site.data.census.* }}`) and MUST NOT hardcode them, so the refresh is the *only* number-entry step. Two suite guards enforce it: `test/site/site_data_test.rb` (SSOT shape) and `test/site/site_prose_ssot_test.rb` (no page hardcodes a headline figure or carries a stale literal). A new headline number a page needs = a new field on `Nabu::Ops::SiteData#census`, never prose. Full routine: `site/MAINTENANCE.md` duty 1.
- **External communications and other private workflow follow the owner's local protocol** (untracked; imported below via `@.docs/private-agreements.md`). **Public-surface hygiene (owner rule 2026-08-30):** PR bodies, commit messages, issues, and every git-tracked file carry ONLY technical content and license-provenance facts (grantor, date, terms); internal workflow state — correspondence status, thread/register/queue identifiers, owner-action lists — never appears on a public surface. The suite's `test/public_hygiene_test.rb` guards the tracked-file half.

@.docs/private-agreements.md
- Commit messages: imperative summary line, body explains *why*, references doc section if implementing planned work. One logical change per commit.

## Things that look like good ideas but aren't

- Parsing giant TEI with DOM: use SAX/Reader for anything over ~5 MB (Perseus has such files).
- "Cleaning up" upstream text (fixing typos, modernizing orthography) during parse — canonical means canonical; corrections are enrichments.
- Cross-adapter shared state or clever registries with autoloading magic — explicit `require` + explicit registry in `sources.yml`.
- Storing embeddings or big JSON in `catalog.sqlite3` — vectors go in `vectors.sqlite3`, bulky derived payloads in `enrichments`.
- Hard-deleting anything from the catalog. Withdraw, revise, journal.
- Destructive fetch — a plain `git pull` in canonical/. A pull deletes working-tree files upstream scrapped, and since `db/` is a pure function of `canonical/`, the next rebuild silently loses those documents. All git fetching goes through `Nabu::GitFetch` (fetch objects → breaker → attic upstream deletions under `canonical/<slug>/.attic/` → ff-merge); see architecture §8.
