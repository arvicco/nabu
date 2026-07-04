# Backlog

Work packets for the dev loop (see `docs/dev-loop.md`). Statuses: `ready` → `in-progress` → `done` | `blocked: <reason>`. The executing session updates its packet's status and appends one line to `docs/worklog.md`.

---

## Phase 0 — Scaffold (branch: phase-0)

## P0-1 · Project skeleton: Gemfile, Rakefile, RuboCop, test harness  [tier: opus] [status: done] [deps: —]
Goal: Ruby 3.3+ project skeleton. Gemfile with the approved dependency budget only
      (thor, sequel, sqlite3, nokogiri, faraday, minitest, webmock, rubocop, rake).
      Rakefile with `test` (default), `lint`, `lint:fix` tasks. `.rubocop.yml`
      standard-ish config. `test/test_helper.rb` requires minitest + WebMock with
      `WebMock.disable_net_connect!` — no allowlist. `lib/nabu.rb` +
      `lib/nabu/version.rb`. `# frozen_string_literal: true` everywhere.
Acceptance: `bundle install` succeeds; `rake test` runs green including one test
      asserting that any HTTP attempt raises; `rake lint` green; Gemfile.lock committed.

## P0-2 · CLI skeleton: bin/nabu, config loading  [tier: opus] [status: done] [deps: P0-1]
Goal: Executable `bin/nabu` (Thor). `Nabu::CLI` with `version` command and stub
      subcommands (`sync`, `status`, `rebuild`, `search`, `show`) that print
      "not implemented" and exit 1. `Nabu::Config` loads `config/nabu.yml`
      (paths for canonical/, db/; sensible defaults when file absent).
      Ship a commented `config/nabu.yml` example.
Acceptance: `bin/nabu version` prints VERSION; `bin/nabu --help` lists commands;
      CLI tests capture output (no shelling out needed); config defaults +
      file-override tested; `rake test`/`rake lint` green.

## P0-3 · CI: GitHub Actions  [tier: opus] [status: done] [deps: P0-1]
Goal: `.github/workflows/ci.yml`: on push + pull_request, macOS-agnostic
      (ubuntu-latest fine), ruby/setup-ruby with `.ruby-version`-independent
      version pin (3.3), bundler cache, run `rake test` then `rake lint`.
Acceptance: workflow YAML is valid; first PR run green (verified at the phase gate).

## P0-4 · Core primitives: errors, Shell, Normalize  [tier: opus] [status: done] [deps: P0-1]
Goal: `Nabu::Error` < StandardError; `Nabu::ParseError`, `Nabu::FetchError`.
      `Nabu::Shell.run(*argv)` — captures stdout/stderr, raises `Nabu::Shell::Error`
      (carrying status + stderr) on nonzero exit; no backticks, use Open3.
      `Nabu::Normalize.nfc(str)` — UTF-8 NFC normalization, raising on invalid bytes.
Acceptance: unit tests for hierarchy and Shell (success, failure, stderr capture,
      argv-not-shell semantics); at least one encoding regression test with real
      offending bytes as inline fixture (e.g. NFD Greek → NFC); green suite + lint.

---

## Phase 1 — Core domain (branch: phase-1; elaborated, starts after Phase 0 PR merges)

## P1-1 · Value objects: Passage, DocumentRef, SourceManifest, Document  [tier: fable] [status: done] [deps: P0-4]
Goal: `Data.define` value objects per architecture §3: `Passage` (urn, language,
      text, text_normalized, annotations, sequence, document_id-less at parse time),
      `DocumentRef`, `SourceManifest` (id, name, license, license_class enum,
      upstream_url, parser_family). `Document` (plain object, has_many passages).
      Keyword construction; validation at construction (URN non-empty, language
      looks BCP-47/ISO-639-3, text is NFC UTF-8).
Acceptance: construction + validation tests; invalid language/URN/non-NFC text
      rejected with meaningful errors; green suite + lint.

## P1-2 · Adapter contract + conformance suite  [tier: fable] [status: done] [deps: P1-1]
Goal: `Nabu::Adapter` base class: `fetch(workdir)`, `discover(workdir)`,
      `parse(document_ref)`, `self.manifest` — abstract methods raise
      `NotImplementedError`. `test/support/adapter_conformance.rb`: manifest
      validity, discover→parse round-trip, URN uniqueness + stability across two
      parses, NFC output, non-empty passages, license class present. Prove the
      suite with a minimal fixture-backed `TestAdapter` in test support.
Acceptance: conformance suite passes against TestAdapter; deliberately-broken
      variants fail the right assertions (meta-tested); green suite + lint.

## P1-3 · Store: schema migrations + Sequel models  [tier: fable-design/opus-impl] [status: done] [deps: P1-1]
Goal: Numbered forward-only Sequel migrations in `db/migrate/` creating
      sources, documents, passages, provenance, enrichments, runs
      (architecture §5, including content_sha256, revision, withdrawn,
      license_class). Sequel models in `lib/nabu/store/`. Migration runner
      wired into test helper (fresh `sqlite::memory:` per store test).
Acceptance: migrations apply cleanly on in-memory SQLite; model associations
      and license_class enum constraint tested; green suite + lint.

## P1-4 · Loader: upsert, hashing, revisions, withdrawal  [tier: fable] [status: done] [deps: P1-2, P1-3]
Goal: `Nabu::Store::Loader` takes `Document`s from an adapter and persists:
      upsert on urn; unchanged content (content_sha256 match) skipped; changed
      content bumps revision and journals the old hash to provenance; documents
      absent upstream marked withdrawn (never hard-deleted). Emits `LoadReport`
      (added/updated/withdrawn/errored counts). Parse errors quarantine the
      document, never abort the batch.
Acceptance: idempotency test (load twice → identical counts/revisions);
      revision-bump test; withdrawal test; quarantine test; green suite + lint.

## P1-5 · nabu rebuild  [tier: opus] [status: done] [deps: P1-4]
Goal: `bin/nabu rebuild` — drop db/, re-apply migrations, re-parse + reload
      everything from canonical/ via registered adapters (`--parse-only`
      semantics: no fetch). `--dry-run` prints what would happen. Enrichment
      replay is out of scope (stub the hook).
Acceptance: round-trip test on a fixture canonical dir — build, rebuild, assert
      identical passage rows (modulo ids); green suite + lint.

## P1-6 · Source registry + runs + nabu status  [tier: opus] [status: done] [deps: P1-3]
<!-- ran before P1-5 by design — rebuild consumes the registry -->

Goal: `config/sources.yml` registry (adapter class, upstream, license,
      enabled, sync_policy) with loader + validation; `runs` table written with
      Fetch/LoadReport counts; `bin/nabu status` prints per-source last sync,
      passage counts, and last-run deltas.
Acceptance: registry parsing/validation tests (unknown adapter class → clear
      error); status output test against seeded db; green suite + lint.

---

## Phase 2 — Perseus reference adapter (branch: phase-2)

## P2-1 · Perseus fixtures: plan → approval → fetch  [tier: loop] [status: done] [deps: —]
Goal: Fixture acquisition plan (exact raw URLs from PerseusDL canonical-greekLit
      + canonical-latinLit, sizes, license confirmation) presented to the owner;
      on approval the loop fetches 2–3 small greekLit + 1 latinLit TEI editions
      plus their __cts__.xml metadata, trims each to header + first ~2 citation
      units (structurally intact), writes test/fixtures/perseus/ with a README
      (retrieval date, URLs, license, trim notes).
Acceptance: fixtures on disk, valid XML after trimming, README complete;
      no fetch outside the approved URL list.

## P2-2 · EpidocParser (SAX)  [tier: fable] [status: done] [deps: P2-1]
Goal: `lib/nabu/adapters/epidoc_parser.rb` — standalone parser family
      (architecture §3): Nokogiri SAX/Reader (never DOM — Perseus has >5 MB
      files), consumes a TEI EpiDoc/CapiTainS edition file + its CTS urn,
      emits a Nabu::Document with Passages at the lowest citation level per
      the refsDecl; NFC-normalizes at this boundary; text extraction rules
      (element text sans notes/apparatus) documented in the file header
      comment with the upstream quirks discovered.
Acceptance: parser-family unit tests against the Perseus fixtures (passage
      counts, known snippets, urn scheme, NFC), streaming proven (no DOM
      of the whole document), green suite + lint.

## P2-3 · Perseus adapter  [tier: opus] [status: done] [deps: P2-2]
Goal: `lib/nabu/adapters/perseus.rb` — composes EpidocParser + repo-layout
      knowledge: discover walks data/<tg>/<work>/ for original-language
      editions (grc/lat pattern in filename), resolves titles/urns via
      __cts__.xml; fetch = git clone/pull via Nabu::Shell (unit-tested against
      a local fixture git dir or stubbed Shell — no network in tests);
      manifest (CC BY-SA 4.0, license_class attribution). Register
      perseus-greek (enabled: false) in config/sources.yml.
Acceptance: passes AdapterConformance against test/fixtures/perseus/ +
      source-specific tests (expected urns, counts, snippet); green + lint.

## P2-4 · SyncRunner + circuit breaker  [tier: opus, fable-review] [status: done] [deps: P2-3]
Goal: `lib/nabu/sync_runner.rb`: fetch (respecting sync_policy: frozen/manual
      excluded from --all; fetch skipped with --parse-only) → load_from via
      Loader + RunRecorder → update sources.last_sync_at/last_sync_sha.
      FetchReport value (architecture §3). Circuit breaker (architecture §8):
      abort before the withdrawal sweep if it would withdraw >20% of a
      source's documents, unless --force. CLI: `nabu sync <slug>|--all
      [--parse-only] [--force]`.
Acceptance: runner tests with TestAdapter (+ fetch-counting subclass);
      breaker triggers at threshold, --force overrides, run row records
      aborted; --parse-only never calls fetch; green + lint.

## P2-5 · First real sync  [tier: human] [status: done] [deps: P2-4]
Goal: Owner (or loop with owner watching) runs `bin/nabu sync perseus-greek`
      for real: clone upstream, load, eyeball `nabu status` + a few random
      passages, then flip enabled: true.
Acceptance: owner sign-off; sources.yml updated; docs/02-sources.md status
      column updated for Perseus.

---

## Phase 3+ — outline only (elaborated at the Phase 2 gate)

Phase 3 (family expansion): First1KGreek, ConlluParser + UD, ProielParser +
PROIEL/TOROT, Papyri.info [all opus].
Phase 4 (query surface): FTS5 + search/show/export, golden queries, verify [opus].

## P2-6 · Sync/rebuild progress reporting  [tier: opus] [status: done] [deps: P2-4]
Goal: Long operations show live progress (owner feedback from first real sync:
      several minutes of silence). (a) Nabu::Shell.stream(*argv, &on_line) —
      popen3 variant forwarding merged output lines live to a block, same
      Shell::Error semantics; run() unchanged. (b) Perseus#fetch passes
      --progress to git and streams via an optional progress: callback kwarg
      (base contract gains fetch(workdir, progress: nil) — nil-safe, ignored
      by adapters that don't support it). (c) Loader#load_from gains
      on_document: callback (called with running doc count + errored count
      after each document). (d) CLI sync/rebuild: when $stderr is a tty,
      \r-updating counter lines ("fetching… <git line>" / "loading… N docs,
      E quarantined"); final counts line unchanged. Non-tty: one line per 100
      docs. No progress output in tests (not a tty; callbacks tested directly).
Acceptance: unit tests for Shell.stream (lines forwarded, error carries
      stderr), Loader callback counts, CLI progress gated on tty (stub
      $stderr.tty?); existing output assertions unchanged; green + lint.

---

## Phase 3 — Family expansion (branch: phase-3)

## P3-0 · Conformance: ref.id ↔ document.urn identity  [tier: opus] [status: done] [deps: —]
Goal: The sync circuit breaker predicts withdrawals via discover() ref ids
      standing in for document urns (P2-4 gate note). Promote that identity
      into test/support/adapter_conformance.rb: assert parse(ref).urn ==
      ref.id for every discovered ref; meta-test a violating adapter fails
      it. Align TestAdapter/fixture rigs if needed.
Acceptance: new conformance assertion + meta-test; all existing adapters
      still pass; green + lint.

## P3-1 · Phase 3 fixtures: plan → approval → fetch  [tier: loop] [status: done] [deps: —]
Goal: One consolidated acquisition plan (dev-loop §8) covering: First1KGreek
      (OpenGreekAndLatin), UD ancient treebanks (2–3 languages, CoNLL-U),
      PROIEL treebank, TOROT, Papyri.info (idp.data) — exact raw URLs, small
      real samples, licenses verified. Owner approves once; loop fetches,
      writes test/fixtures/<source>/ trees + READMEs.
Acceptance: fixtures on disk + READMEs; no fetch outside the approved list.

## P3-2 · First1KGreek adapter  [tier: opus] [status: done] [deps: P3-0, P3-1]
Goal: OpenGreekAndLatin First1KGreek — same CapiTainS/EpiDoc conventions as
      Perseus ("nearly free"): adapter reusing EpidocParser + Perseus layout
      knowledge (subclass or shared module — implementer's call, justify).
      Register first1k-greek (enabled: false, live).
Acceptance: AdapterConformance + source-specific tests on real fixtures;
      green + lint.

## P3-3 · ConlluParser + UD adapter  [tier: opus, fable-review] [status: done] [deps: P3-0, P3-1]
Goal: CoNLL-U parser family (line-based TSV: 10 columns, sentence = passage,
      lemma/upos/feats → annotations; follows the EpidocParser family
      template) + Universal Dependencies adapter over per-treebank git repos
      (start: 2–3 ancient-language treebanks from fixtures). URN minting:
      urn:nabu:ud:<treebank>:<sent_id> (frozen once used). Register
      ud (enabled: false, manual).
Acceptance: parser unit tests (columns, multiword tokens skipped/handled,
      comments, annotations JSON) + AdapterConformance; green + lint.

## P3-4 · ProielParser + PROIEL adapter  [tier: opus, fable-review] [status: done] [deps: P3-0, P3-1]
Goal: PROIEL XML parser family (sentence = passage; token lemma/morphology →
      annotations; citation ids from source metadata) + PROIEL treebank
      adapter (proiel-treebank repo). Register proiel (enabled: false,
      manual). NC license class recorded (nc).
Acceptance: parser unit tests + AdapterConformance on real fixtures;
      green + lint.

## P3-5 · TOROT adapter  [tier: opus] [status: done] [deps: P3-4]
Goal: TOROT (Tromsø OCS + Old Russian) — PROIEL XML reuse; adapter is thin
      composition. Register torot (enabled: false, manual).
Acceptance: AdapterConformance + OCS-specific assertions (chu language tag,
      known Marianus snippet); green + lint.

## P3-6 · DdbdpParser + Papyri.info adapter  [tier: fable] [status: done] [deps: P3-1]
Goal: RETIERED opus→fable after research: DDbDP is NOT CapiTainS (no
      __cts__.xml, no refsDecl, no CTS urns) — a new parser family, not
      EpidocParser reuse. Identity via <idno> (filename/ddb-hybrid/HGV/TM);
      citation via <lb n> lines inside <ab>; heavy documentary markup
      (app/lem/rdg, choice/reg/orig, subst/add/del, gap+quantity, supplied,
      unclear, expan/ex, handShift). Parser implements the deferred Leiden
      text-extraction policy (keep lem+reg+supplied, drop rdg/orig/del,
      mark gaps) and documents it; adapter walks collection/volume dirs,
      urn:nabu:ddbdp:<ddb-hybrid> minting (frozen once used). Register
      papyri-ddbdp (enabled: false, manual).
Acceptance: AdapterConformance + Leiden-markup extraction tests on real
      fixtures; green + lint.

---

## Phase 4 — Query surface (branch: phase-4)

## P4-1 · FTS5 index + Indexer  [tier: opus, fable-spec] [status: done] [deps: —]
Goal: db/fulltext.sqlite3 (architecture §2/§5): contentless FTS5 table keyed
      by passage id over text_normalized (+ urn column unindexed), tokenizer
      unicode61 remove_diacritics 2 (folds Greek/Latin diacritics at query
      time; trigram deferred until CJK). Nabu::Store::Indexer.rebuild!(catalog:,
      fulltext:) — full reindex of non-withdrawn passages (bulk, transactional,
      drop+recreate); wired automatically into the tail of sync and rebuild
      (a fresh index is part of "loaded"). Store.connect_fulltext helper.
Acceptance: indexer unit tests (index count == live passages; withdrawn
      excluded; reindex idempotent); sync/rebuild integration test proves
      auto-index; green + lint.

## P4-2 · nabu search  [tier: opus] [status: done] [deps: P4-1]
Goal: `nabu search QUERY [--lang X] [--license open|attribution|nc|…]
      [--limit N]` — FTS5 MATCH over text_normalized (query lowercased+NFC),
      joined to catalog for urn/language/license filtering (ATTACH or
      two-step id join — implementer's call, no SQL strings outside Sequel).
      Output: urn, language, snippet() highlight per hit; count line. No
      hits → message + exit 0. Missing index → hint to run sync/rebuild.
Acceptance: CLI tests against seeded fixture corpus (Greek hit via
      diacritic-insensitive query proves remove_diacritics; lang + license
      filters; limit); green + lint.

## P4-3 · nabu show + export  [tier: opus] [status: done] [deps: —]
Goal: `nabu show URN` — passage (text, document title, language, revision,
      provenance events) or whole document (ordered passages) when the urn
      is a document's. `nabu export [--lang X] [--license Y] --format
      plain|jsonl` — streams non-withdrawn passages (plain: text lines;
      jsonl: urn/language/text/text_normalized/annotations). CoNLL-U export
      deferred to enrichment phase (needs token model) — note in backlog.
Acceptance: CLI tests on seeded corpus (passage show, document show,
      unknown urn exit 1; export filters + valid JSONL); green + lint.

## P4-4 · Golden queries + nabu verify  [tier: opus] [status: done] [deps: P4-1, P4-2]
Goal: test/golden/golden_queries.yml — known query → expected-urn-in-results
      pairs run against the full fixture corpus (all six adapters loaded into
      one store) as a smoke suite (test/golden_test.rb); catches
      loader/normalizer/indexer regressions unit tests miss. `nabu verify` —
      re-hash canonical files against catalog content_sha256 per architecture
      §8 (bitrot/tamper check, cronnable): OK/exit 0, mismatches listed/exit 1.
Acceptance: golden suite green with ≥6 queries spanning grc/lat/got/chu/orv
      (incl. one diacritic-folded and one Leiden-gap-adjacent); verify tests
      (clean, corrupted-file, missing-file); green + lint.

---

## Phase 5 — Collection protection & source health (branch: phase-5; elaborated 2026-07-04)

*Fixture note: this phase fetches NOTHING. The only new fixtures are trimmed
from the already-synced local `canonical/papyri-ddbdp` snapshot (license
recorded at the Phase 3 approval); fixture READMEs note trim provenance and
the original fetch date.*

## P5-1 · DdbdpParser: restart-aware URN minting  [tier: fable] [status: done] [deps: —]
Goal: Fix the duplicate-urn quarantine class from the 2026-07-04 first sync
      (12,288 of 21,641 quarantines): DDbDP files where line numbering restarts
      mid-document (multiple `<lb n="1"/>`) with NO textpart divs to
      disambiguate — exemplar: `aegyptus/aegyptus.89/aegyptus.89.240.xml`
      (two `<lb n="1"`, one `<ab>`, zero textparts). Design the minting policy
      (fable decision): passage URNs within such documents must be unique and
      stable across parses (e.g. an implicit block index per restart) —
      documents WITH textparts keep their current minting untouched.
      HARD CONSTRAINT — frozen-urn safety: documents that parsed cleanly
      before the fix must mint byte-identical URNs after it (the 49,060 loaded
      docs re-parse as "skipped", never "revised"); restart docs never entered
      the catalog, so their URNs are unconstrained.
      Also: sample the OTHER quarantine class ("no citable lines", 9,351 docs)
      — inspect ≥10 canonical files drawn from the quarantine journal
      (provenance events) and confirm they are genuinely text-less stubs;
      if a recoverable subclass emerges, REPORT it (own packet later), don't
      scope-creep this fix.
      Fixtures: trim the restart exemplar + one text-less stub from local
      canonical into `test/fixtures/papyri-ddbdp/`.
Acceptance: restart fixture parses (no quarantine) with unique URNs, stable
      across two parses; pre-fix URN lists of all existing papyri fixtures
      asserted unchanged (golden regression); stub fixture still quarantines
      with a clear message; conformance + full suite + lint green; stub-sample
      findings reported in the worklog line.

## P5-2 · Retention contract: the canonical attic  [tier: fable] [status: done] [deps: —]
Goal: Owner requirement (2026-07-04): if a document/source is scrapped
      upstream (deletion, license change, disagreement), local storage marks
      it but KEEPS it usable. Today this holds only in the catalog — `fetch`
      (git pull) deletes canonical FILES, and rebuild = pure function of
      canonical/, so any rebuild after an upstream deletion silently loses the
      withdrawn documents (canonical/ is gitignored, clones are --depth 1: no
      net). Fetch also mutates canonical BEFORE the breaker runs.
      Design (the attic):
      (a) Non-destructive fetch — `git fetch` first (objects only), diff
          HEAD..FETCH_HEAD --diff-filter=D, copy doomed files to
          `canonical/<slug>/.attic/<relpath>` (first copy wins, journaled),
          THEN ff-merge. Attic lives inside canonical/, so the rebuild
          invariant (db = f(canonical)) survives unchanged and attic docs
          replay through every rebuild.
      (b) Attic discovery in the Adapter base so all six adapters inherit it:
          attic refs flagged retained; a URN discovered both live and in the
          attic → live wins, attic copy superseded + journaled (restructures/
          renames self-heal instead of duplicating).
      (c) Schema (forward-only migration): `documents.retired_upstream`,
          distinct from `withdrawn`. Retired docs stay LIVE — searchable,
          exportable, indexed (the point of keeping them) — labeled in
          status/show; provenance "retired" records the upstream sha where
          they vanished. `withdrawn` keeps meaning "absent from canonical
          entirely"; intra-document edition changes stay revision-journaled,
          not atticked (upstream typo fixes are not scrapping).
      (d) Breaker prediction moves before the merge — an aborted sync leaves
          the canonical working tree truly unchanged.
      Docs in the same change: architecture §3/§8 retention contract;
      conventions.md licensing note (retained docs keep the license they were
      fetched under); CLAUDE.md anti-patterns. Out of scope (state in docs):
      passage-level old text on revision is journaled by sha only; attic
      protects against upstream loss, not local disk loss (backups remain the
      answer).
Acceptance: fixture-git-repo test — upstream deletes a file → post-sync the
      file exists under .attic, its document loads live with
      retired_upstream=true + "retired" provenance; rebuild replays the attic
      (doc survives, still flagged); live-beats-attic dedup test; breaker-abort
      test asserts canonical tree byte-unchanged; search/export include and
      status/show label retired docs; migration + models tested; docs updated;
      full suite + lint green.

## P5-3 · Upstream probe: nabu health --remote  [tier: opus] [status: ready] [deps: —]
Goal: `bin/nabu health --remote` — per registered source (enabled or not):
      `git ls-remote` liveness (alive / moved / gone / auth-trouble), remote
      HEAD vs last_sync_sha (current / behind), and a no-clone license-drift
      check (fetch the upstream license file raw where the host allows;
      tolerate absence gracefully). Table output; exit 1 if any upstream is
      gone. No cloning, no fetching corpora. Tests mock Shell/HTTP (WebMock).
Acceptance: probe tests for alive/moved/gone/behind/license-changed paths
      against mocked responses; exit codes tested; suite + lint green.

## P5-4 · Fixture sentinel  [tier: opus] [status: ready] [deps: —]
Goal: Formalize the approved fixture-acquisition URLs as per-source fixture
      manifests (`test/fixtures/<source>/manifest.yml`: URLs, retrieval date,
      trim notes). `rake fixtures:check[source]` — fetch to tmp, diff against
      checked-in fixtures, run the source's adapter tests against the fresh
      copies, report; NEVER overwrites (the failing tests ARE the drift
      report, maintenance §6). `rake fixtures:refresh[source]` — explicit
      adoption. Rake tasks are manual/network; the test suite itself stays
      network-free (task logic tested with mocked fetches + tmp dirs).
Acceptance: manifests for all six sources (papyri entries note the local-trim
      provenance); check/refresh behavior tested with WebMock + tmp fixtures;
      check exits nonzero on drift, refresh only on explicit invocation;
      suite + lint green.

## P5-5 · Post-sync anomaly detection: nabu health  [tier: opus] [status: ready] [deps: P5-3]
Goal: `bin/nabu health` (local, no network) — per-source run-history trends
      from the runs table: quarantine spikes vs prior runs, added-count
      collapse, withdrawal/retirement creep, stale sources (last_sync_at older
      than the source's cadence expectation); plus replay of
      test/golden/golden_queries.yml against the LIVE corpus (catalog +
      fulltext on disk) reporting any query that lost its expected URN.
      SyncRunner gains inline deviation warnings on the same signals at sync
      time. Exit 1 on any red finding.
Acceptance: trend detection tested against seeded runs histories (spike,
      collapse, creep, stale, healthy); live golden replay tested against a
      fixture-built corpus; SyncRunner warning test; suite + lint green.

## P5-6 · Ops wiring  [tier: opus] [status: ready] [deps: P5-3, P5-5]
Goal: `docs/ops.md` — the operating manual for the maintenance §1 cadence
      (nightly `nabu verify`, weekly `sync --all` + `health` + `health
      --remote`), with launchd plist templates under `ops/launchd/` the owner
      can install (paths parameterized, install steps documented, nothing
      auto-installed). Optional ntfy notification hook documented as
      owner-configured. No code changes beyond what the templates invoke.
Acceptance: plists are valid (plutil -lint in tests via tmp copies), commands
      they reference exist; docs/ops.md complete enough that a newcomer could
      wire the cadence; suite + lint green.

