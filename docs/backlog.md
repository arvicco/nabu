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

## P5-3 · Upstream probe: nabu health --remote  [tier: opus] [status: done] [deps: —]
Goal: `bin/nabu health --remote` — per registered source (enabled or not):
      `git ls-remote` liveness (alive / moved / gone / auth-trouble), remote
      HEAD vs last_sync_sha (current / behind), and a no-clone license-drift
      check (fetch the upstream license file raw where the host allows;
      tolerate absence gracefully). Table output; exit 1 if any upstream is
      gone. No cloning, no fetching corpora. Tests mock Shell/HTTP (WebMock).
Acceptance: probe tests for alive/moved/gone/behind/license-changed paths
      against mocked responses; exit codes tested; suite + lint green.

## P5-4 · Fixture sentinel  [tier: opus] [status: done] [deps: —]
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

## P5-5 · Post-sync anomaly detection: nabu health  [tier: opus] [status: done] [deps: P5-3]
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

## P5-6 · Ops wiring  [tier: opus] [status: done] [deps: P5-3, P5-5]
Goal: `docs/ops.md` — the operating manual for the maintenance §1 cadence
      (nightly `nabu verify`, weekly `sync --all` + `health` + `health
      --remote`), with launchd plist templates under `ops/launchd/` the owner
      can install (paths parameterized, install steps documented, nothing
      auto-installed). Optional ntfy notification hook documented as
      owner-configured. No code changes beyond what the templates invoke.
Acceptance: plists are valid (plutil -lint in tests via tmp copies), commands
      they reference exist; docs/ops.md complete enough that a newcomer could
      wire the cadence; suite + lint green.


---

## Phase 6 — Corpus completeness & fidelity (branch: phase-6; elaborated 2026-07-04)

*All packets work the LOCAL snapshot (parse-only resyncs, no bulk fetches);
fixtures are trimmed from local canonical, as in Phase 5. Enrichment (API
keys, sidecars, human review) is deliberately NOT this phase — it is planned
at this phase's gate with the owner as originally intended.*

## P6-1 · The Iliad: EpidocParser citation-depth quarantine class  [tier: fable] [status: done] [deps: —]
Goal: tlg0012.tlg001.perseus-grc2 (THE Iliad) quarantines with "citation
      depth mismatch: refsDecl declares 2 component(s), found 1 ([\"1\"])" —
      found 2026-07-04 while verifying help examples. Diagnose ALL current
      EpiDoc quarantines first (perseus !25, first1k !37 — query the
      provenance journal, classify by error shape), then fix the dominant
      class(es) in EpidocParser. Likely shape: files whose refsDecl declares
      book.line but whose text nests divs differently (or numbers lines via
      milestones) — inspect the actual Iliad XML before deciding; do not
      guess upstream formats. HARD CONSTRAINT (frozen-urn, as P5-1):
      documents that parsed cleanly before must mint byte-identical URNs and
      text (re-parse as "skipped"); quarantined docs are unconstrained.
      Classes that are genuinely malformed upstream stay quarantined —
      honesty over count. Fixture: trim the Iliad exemplar (+1 more of the
      dominant class if it differs) from local canonical into
      test/fixtures/perseus/ (README + manifest updated; whole:false trim).
Acceptance: quarantine census reported (error shape → count → fixed or
      why-not); Iliad fixture parses with book.line URNs stable across two
      parses; existing perseus/first1k fixture URN lists byte-identical
      (golden regression); conformance + suite + lint green; worklog notes
      recovered-doc counts after the orchestrator's --parse-only resync.

## P6-2 · Cancelled-but-legible papyri: Leiden <del> policy amendment  [tier: fable] [status: done] [deps: —]
Goal: ~40 DDbDP docs whose ENTIRE edition sits inside <del
      rend="cross-strokes"|"slashes"> (+ a few whole-doc erasures) quarantine
      as "no citable lines" — the blanket drop-<del> policy erases documents
      that print practice reads in ⟦⟧ (ancient cancellation, fully legible:
      P5-1 audit; exemplars cpr.6.3, bgu.1.179, apf.59.139, o.claud.3.457).
      Amend the DdbdpParser Leiden policy (fable decision — it is a
      text-fidelity contract): keep <del> content wrapped in ⟦…⟧ — decide
      the exact scope deliberately. HARD CONSTRAINT: passages of
      already-loaded documents must be byte-identical after the change —
      if the honest policy is "always render <del> in ⟦⟧", that changes
      loaded passages containing partial dels and is NOT acceptable in this
      packet; scope to the whole-document class (or an equally safe rule)
      and record the general-policy question for the conventions doc.
      Fixture: trim one exemplar from local canonical. conventions.md §5
      updated in the same change.
Acceptance: exemplar fixture parses with ⟦⟧-wrapped text, urns stable;
      existing papyri fixture URN lists AND text byte-identical (golden);
      genuinely empty stubs (chrest.wilck.101) still quarantine; docs
      updated; suite + lint green.

## P6-3 · Per-repo drift & license for multi-repo sources  [tier: opus] [status: done] [deps: —]
Goal: UD probes each treebank repo for liveness but drift reads :multi and
      license :unchecked (P5-3 deferral) because sources carry ONE
      last_sync_sha + ONE license baseline. Add per-repo pinning: a
      source_repos table (forward-only migration: source_id, repo_url,
      last_sync_sha, license_baseline_sha256) written by the UD fetch path
      (extend the FetchReport/GitFetch result plumbing minimally) and read
      by RemoteProbe — per-repo drift (:current/:behind) and license
      baselines, offenders named per repo. Single-repo sources keep the
      existing columns (no migration of behavior); rebuild-purity: the
      table is runtime state like last_sync_*, dropped and re-pinned by the
      next sync.
Acceptance: migration + model tests; UD sync records per-repo shas (fixture
      git repos); probe reports per-repo drift/license for UD and unchanged
      behavior for single-repo sources; suite + lint green.

## P6-4 · Per-language folding at the adapter boundary  [tier: fable-design/opus-impl] [status: done] [deps: P6-1, P6-2]
Goal: text_normalized currently carries only downcasing; diacritic folding
      happens at index time and query time (P4-1 stopgap, architecture §3
      note). Move folding to the adapter boundary with per-language rules
      (fable designs the rule table: Greek fold marks + final-sigma
      normalization; Latin v→u/j→i decision; Cyrillic/OCS titlo and
      yer questions — research what the field does, document in
      conventions.md; when in doubt per language, fold conservatively =
      current behavior). Passage.text_normalized becomes the true search
      form; Indexer/Search drop their fold calls (query folds by the SAME
      per-language… decide: query folding without a lang hint applies the
      union/conservative fold — document). Then the orchestrator runs
      `nabu rebuild` to re-derive the corpus (LOCAL, no network) and replays
      golden queries. Deps on P6-1/P6-2 so the reload happens once, after
      recovered docs land.
Acceptance: rule-table unit tests per language incl. final-sigma and the
      documented Latin/Slavic decisions; fold-both-sides contract tests
      still green; golden queries green against a fixture corpus built the
      new way; architecture §3 updated (stopgap note removed); suite +
      lint green; worklog notes the rebuild + golden replay results.


---

## Phase 7 — Collection durability & the readable corpus (branch: phase-7; elaborated 2026-07-07)

*Owner direction (2026-07-07): integrate better research capabilities,
archiving/protection, and an MCP server as the next phases. Mapping: Phase 7
delivers protection (the concept's own backup promise, still unmet) plus the
research foundations that need NO new keys/APIs (corpus expansion, lemma
search, ranges, parallel translations — all local or already-cloned data);
Phase 8 delivers the research surface (MCP first) with the API/hardware
decisions gated to the owner at the Phase 7 gate. The only bulk fetch in
Phase 7 is the first latinLit sync (owner-initiated at the gate); P7-4's
English editions are already on disk in the cloned Perseus repos.*

## P7-1 · Durable history: split what rebuild must never destroy  [tier: fable] [status: done] [deps: —]
Goal: runtime history currently dies with the derived catalog — watched live
      at the P6-4 reload: runs (health trends), license baselines, per-repo
      pins, and the provenance journal all reset, because they live in the
      db that rebuild drops. Design the storage split (fable decision):
      catalog.sqlite3 stays a pure derivation of canonical/; precious
      history moves to a non-derived ledger db (e.g. db/history.sqlite3)
      that rebuild NEVER touches. Fixed constraints: runs, license
      baselines, and source_repos pins MUST survive rebuild; a fresh
      machine with no ledger bootstraps cleanly (empty ledger, everything
      works); migrations forward-only per db. The open design question
      (decide deliberately, document): revision provenance — its rows key
      on passage/document ids that a rebuild re-mints, so either (a) an
      urn-keyed append-only revisions ledger survives rebuilds, or (b)
      provenance stays derived and resets, documented honestly. Weigh
      P8's enrichments (expensive API output — their journal MUST be
      durable; design the ledger so enrichment replay can live there).
Acceptance: seed runs/baselines/pins → rebuild → still present (test);
      health trends read the ledger; status unaffected; fresh-bootstrap
      test; architecture §1/§2/§5/§8 updated truthfully (the invariant
      statement gains the ledger clause); suite + lint green.

## P7-2 · Backup & the restore drill  [tier: opus] [status: done] [deps: P7-1]
Goal: the concept promises "restorable from an rsync backup with zero
      services" — make it true. `bin/nabu backup` — file-level snapshot
      (rsync -a --delete via Nabu::Shell) of canonical/ (the attic rides
      along — NOTE: per-slug git mirrors would MISS .attic/, which is
      exactly the data that exists nowhere else; file-level or nothing),
      db/history ledger, config/, and (default-on, flag-off) the derived
      dbs, to a config-driven target (config/nabu.yml `backup: target:` —
      the OWNER wires the real destination). OWNER DECISION 2026-07-07:
      target is a locally mounted external volume; a virtual volume
      (hdiutil sparsebundle mounted under /Volumes) simulates it until
      real hardware is wired. Because the target is a mount point, the
      backup MUST refuse to run when the volume is not actually mounted
      (verify the path is a real mount point, not an empty directory on
      the boot disk — the classic rsync-into-the-mountpoint footgun that
      silently "backs up" to the wrong disk and later shadows the real
      volume). `--dry-run` prints the rsync plan.
      docs/ops.md gains the backup section + an optional launchd template;
      restore procedure documented step-by-step. `rake ops:drill` — the
      fresh-machine drill, LOCAL: back up to a tmp target, "restore" into
      a tmp root, rebuild from restored canonical, run verify + the golden
      replay, report — proving the concept's fresh-machine criterion
      without touching the live setup. Orchestrator runs the drill at
      acceptance.
Acceptance: backup to a tmp target in tests (attic + ledger + config
      present, exclusions honored); dry-run changes nothing; drill task
      green end-to-end locally; ops.md complete; suite + lint green.

## P7-3 · Perseus Latin  [tier: opus] [status: done] [deps: —]
Goal: the designed one-line sibling — `PerseusLatin < Perseus` with
      NAMESPACE latinLit (manifest perseus-latin already defined in
      MANIFESTS), registry entry `enabled: false`, conformance + adapter
      tests against the existing latinLit fixture (stoa0045, fetched at
      P2-1). Extend the fixture set from the already-cloned repo only if
      a test genuinely needs it (no network).
      The first real sync (multi-GB clone) is OWNER-INITIATED at the gate
      per CLAUDE.md; the packet ships everything up to that.
Acceptance: conformance green for the new adapter; registry + docs
      (02-sources status row: READY, awaiting first sync); manifest
      updated; suite + lint green.

## P7-4 · Parallel translations: the readable corpus  [tier: fable] [status: done] [deps: —]
Goal: Perseus ships English editions IN THE REPOS WE ALREADY CLONED —
      the language gate drops them (`perseus-eng*`). Ingest them as
      aligned parallel documents: same work, own edition urn, language
      "eng" — CTS citation makes passage-level alignment free
      (…perseus-grc2:1.1 ↔ …perseus-eng4:1.1). Fable decisions: opt-in
      mechanism (per-source registry flag, e.g. `translations: true`, so
      corpora stay original-only by default); edition selection (highest
      eng version, mirroring the grc rule); alignment surface —
      `nabu show <urn> --parallel [lang]` renders original and
      translation line-by-line by citation suffix across editions of the
      same work (unmatched suffixes shown honestly one-sided); search
      includes eng passages (lang filter separates; per-language folding:
      generic). License unchanged (CC BY-SA). FROZEN-URN: new documents
      only — existing docs byte-identical (verify read-only, the
      standing standard). Recovery is a parse-only resync (files on
      disk, zero network) run by the orchestrator.
Acceptance: eng editions discovered/parsed only when the flag is on;
      alignment fixture (trim an eng sibling of an existing grc fixture
      from local canonical — e.g. the Odyssey's) renders side-by-side in
      show --parallel; one golden parallel query; conformance green;
      help show/search updated; suite + lint green.

## P7-5 · Lemma search: exploit the gold treebanks  [tier: fable] [status: done] [deps: —]
Goal: ~161k passages (UD, PROIEL, TOROT) carry gold lemmas + morphology
      in annotations_json — dead weight to search today. Design the lemma
      index (fable — first index of its kind): lemma→passage table in
      fulltext.sqlite3 (derived-of-derived, rebuilt by the Indexer from
      annotations), lemma matching folded consistently with the
      per-language rules (a lemma is a dictionary form; query folds the
      same way). `bin/nabu search --lemma <form> [--lang]` — every
      inflected attestation, hits annotated with the surface form that
      matched. `help search` teaches it with real examples (e.g. --lemma
      λέγω across PROIEL). Non-treebank passages simply have no lemma
      rows (honest absence); the future P8 MCP tool reuses this path.
Acceptance: index builds from the fixture corpus; --lemma finds
      inflected forms across all three treebank families' fixtures;
      folding consistency tested (accented/unaccented lemma queries);
      plain search unaffected; help + goldens extended; suite+lint green.

## P7-6 · show ranges  [tier: opus] [status: done] [deps: P7-4]
Goal: the concept's own syntax — `nabu show urn:…:1.1-1.10`. A range is
      an inclusive, sequence-ordered slice of one document between two
      resolved citation suffixes (endpoints must both exist; clear error
      otherwise). Composes with --parallel (dep P7-4) and --full-urn.
      Keep semantics simple and documented: the slice is by stored
      sequence between the endpoints, whatever citation shapes lie
      between (papyri blocks included).
Acceptance: ranges over CTS (1.1-1.10) and papyri (:1-:b2:2) fixtures;
      endpoint errors; parallel+range composition; help show updated;
      suite + lint green.

---

## Phase 8 — Research surface (branch: phase-8; elaborated 2026-07-07)

*The corpus becomes a tool. MCP first (hand-rolled stdio, owner decision
2026-07-07), then concordance; the two packets needing owner input
(embedding model/hardware, glossing API key) carry their decision menus
below and are dispatched only after the owner picks. Everything else is
local and read-only against the corpus.*

## P8-1 · MCP tool contract + protocol core  [tier: fable] [status: done] [deps: —]
Goal: the read-only conversational surface, hand-rolled (no gem — owner
      decision: the field moves fast, we keep control; the core is small).
      Two layers, one packet, because the contract shapes both:
      (a) Protocol: JSON-RPC 2.0 over stdio (Content-Length framing or
          newline-delimited — check what current MCP spec + Claude Code
          actually speak, research allowed; support initialize /
          notifications/initialized / tools/list / tools/call; clean
          errors for unknown methods; exit on stdin EOF). Version pinned,
          documented, ours.
      (b) The tools (the contract IS the product — descriptions teach the
          model): nabu_search (query XOR lemma, lang, license, limit),
          nabu_show (urn — passage/document/range; parallel flag;
          bounded: max N passages per call with an honest truncation
          note), nabu_status (corpus coverage: sources, doc/passage
          counts, languages, license classes — the tool that makes
          negative results honest). Fixed contract points: bounded
          outputs, snippet-first with "N matches, showing k";
          license_class + upstream attribution + urn on EVERY passage
          returned; license classes research_private/restricted
          DEFAULT-EXCLUDED (forward-looking — the classes exist; a
          conversational surface must never leak future ad-hoc material
          casually); no-match responses carry a coverage hint; a
          mid-reindex missing FTS table degrades to "index rebuilding —
          retry shortly", never a crash; read-only db connections,
          SQLITE_BUSY tolerated with brief retry.
      All query logic stays in the existing Query classes — the server is
      translation only. No write tools in this phase, stated in the docs.
Acceptance: protocol unit tests (in-process IO-pair harness: initialize
      round-trip, tools/list shape, tools/call success + tool-error +
      unknown-method + malformed-json paths); tool-contract tests
      (bounds, license fields present, default exclusion, no-match
      coverage hint, reindex grace); tool descriptions reviewed as prose
      (they are UI); suite + lint green; architecture gains the MCP
      section (read-only surface, nabu.ac rehearsal).

## P8-2 · MCP server: bin/nabu mcp + registration  [tier: opus] [status: done] [deps: P8-1]
Goal: `bin/nabu mcp` — the stdio entrypoint wiring P8-1's server to real
      stdin/stdout (logging to stderr/file, NEVER stdout — stdout is the
      protocol channel); .mcp.json shipped in-repo (project-scope
      registration for Claude Code sessions in this repo) + docs/mcp.md:
      registering in Claude Code (project + user scope), Claude Desktop,
      what each tool does, example conversation transcripts, the
      read-only/license stance, and the nabu.ac-rehearsal note.
Acceptance: process-level smoke test (spawn bin/nabu mcp, speak the
      protocol over pipes, one real tools/call against a fixture corpus,
      clean EOF shutdown); .mcp.json valid; docs complete; suite + lint
      green.

## P8-3 · Concordance: nabu concord  [tier: opus] [status: done] [deps: P8-1]
Goal: `bin/nabu concord QUERY|--lemma FORM [--lang/--license/--limit/
      --width N]` — KWIC lines: one row per hit, keyword column aligned,
      left/right context trimmed to --width chars (default sensible),
      urn tag per row; corpus order; reuses Search/LemmaSearch entirely
      (a formatter, not a new query path). Exposed as MCP tool
      nabu_concord (extend P8-1's tool table — same bounded/license
      contract).
Acceptance: concord over fixture corpus (plain + lemma modes, width,
      alignment stable for varying-length matches incl. Greek combining
      chars — width counts on the folded/display string, decide and
      document); CLI + MCP tool tests; help; suite + lint green.

## P8-4 · Semantic search  [tier: fable-design/opus-impl] [status: blocked: owner decisions] [deps: P8-1]
OWNER DECISION MENU (pick to unblock; packet elaborated fully on pick):
      (a) Embedder: LOCAL on the DGX Sparks via an OpenAI-compatible
          endpoint over Tailscale (concept's local-first; needs a served
          multilingual embedding model — e.g. bge-m3 class — and the
          Sparks reachable), or (b) LOCAL on this Mac (ollama/mlx-served
          small multilingual model; slower, zero infra), or (c) API
          (managed embeddings; recurring cost, corpus text leaves the
          box in bulk — license-fine but philosophy-relevant).
      Scope decision: literary corpora first (~800k passages incl. eng
      translations) vs all 1.7M (papyri long tail doubles cost/time).
      Storage: vectors.sqlite3 via sqlite-vec (NEW GEM + native
      extension — ask-first rule applies) vs brute-force float blobs
      (no gem, fine at <1M vectors with batched dot products — honest
      option at our scale).
      Fixed regardless: embeddings journal in the P7-1 ledger (never
      wiped by rebuild), embed --changed incrementality, `search
      --semantic "oath-swearing rituals" --langs grc,chu` per concept.

## P8-5 · Lazy glossing  [tier: fable-design/opus-impl] [status: blocked: owner decisions] [deps: P8-1]
OWNER DECISION MENU (pick to unblock):
      API key (ANTHROPIC_API_KEY via env — owner provides; the loop
      never touches keys), model (default claude-haiku for cost? owner
      picks), and where glossing may trigger (CLI `show --gloss` only,
      or also as an MCP tool the model can call mid-conversation —
      spend-per-conversation implications).
      Fixed regardless: gloss at the point of reading, NEVER batch;
      cached in enrichments keyed by (urn, model identity) journaled in
      the P7-1 ledger (replayed after rebuild, one API call per passage
      EVER per model); output flagged machine-generated everywhere it
      renders; passages with human parallel translations (P7-4) render
      those first, glossing is the fallback.

## P8-1b · Owner feedback: span-grouped parallel display  [tier: opus] [status: done] [deps: —]
Goal: card-cited prose translations (both English Homers — no line-cited
      alternative exists upstream) render as a wall of text paired at the
      block's first line, with every following original line dashed "—"
      (owner: "frankly, not that parallel"). Replace pair-only rendering
      with SPAN-GROUPED display. Semantics (designed at orchestrator
      review, 2026-07-07):
      - A translation anchor OWNS original passages from its own suffix
        up to (not including) the next translation anchor, computed over
        the FULL sibling documents' suffix orders — not just the queried
        slice (a range 1.5-1.10 is covered by the card anchored at 1.1
        even though 1.1 is outside the slice; today that renders all-"—").
      - Output groups: original lines first, then the owning translation
        block ONCE, labeled with its full coverage in the original's
        numbering and an explicit clip note when the queried range shows
        only part: `eng [:1.1 — covers :1.1–:1.31; range shows :1.5–:1.10]`.
      - Verse-cited translations (1:1 groups: single original line whose
        suffix equals the anchor) keep the current compact paired form —
        the Hymns fixture must render byte-identically to today.
      - Translation-only suffixes (original lacks the line) stay honest
        one-sided rows. Blocks whose coverage doesn't intersect the
        queried slice don't render.
      - MCP nabu_show inherits via the shared Query::Parallel — its
        parallel payload gains the coverage fields (bounded as before).
Acceptance: Odyssey-shaped fixture (card-cited eng + line-cited grc):
      full-document, mid-card range (block labeled + clip note), and
      range-starting-inside-a-card cases; Hymns fixture byte-identical
      regression pin; eng-only suffix case; MCP show parallel payload
      carries coverage; CLI + query tests, help show example updated;
      suite + lint green.

---

## Phase 9 — Corpus breadth (branch: phase-9; elaborated 2026-07-08)

*Owner direction: items 1–6 of the post-P8 plate as one phase. Three local
packets, two new-corpus tracks (each: scout → owner-approved fixture plan →
adapter, per dev-loop §8), one scouting survey. Network: scout packets may
research (WebSearch/WebFetch) but fetch NOTHING bulk; fixture fetches happen
only after the owner approves each plan; first real syncs owner-fired.*

## P9-1 · First1K English translations  [tier: opus] [status: done] [deps: —]
Goal: First1kGreek's repo carries ~45 English editions under the 1st1K-eng<n>
      slug family; the P7-4 translation classifier keys on the perseus slug
      shape, so `translations: true` would find nothing. Extend the subclass
      (mirror how it already overrides edition_slug_pattern for its originals
      — inspect first; the translation rule should be the same one-method
      override shape), flip the registry flag, fixture from local canonical
      (an eng sibling of an existing first1k fixture work if one exists on
      disk — check; else the smallest real eng file + its grc sibling).
      Frozen-urn: new docs only, flag-off byte-identical (standing standard).
      Orchestrator runs the parse-only recovery at acceptance.
Acceptance: eng editions discovered only with the flag; conformance green;
      existing fixture URN lists unchanged; parallel render test over the new
      fixture pair; suite + lint green.

## P9-2 · Legacy P4-TEI parser support  [tier: fable] [status: done] [deps: —]
Goal: 101 perseus-latin English editions (and census whatever else across
      all sources shares the shape) quarantine as pre-P5 TEI: numbered
      <div1/div2 type="poem|book|chapter"> containers instead of
      div[@type="edition"|"translation"], typically no refsDecl-driven
      citation. CENSUS FIRST (provenance journal, all sources, error-shape
      classification — the P6-1 standard), then design the P4 acceptance
      path in EpidocParser (or a sibling strategy it delegates to): citation
      minting from the numbered-div hierarchy (div1/div2/... @n or @type
      labels — inspect real files, never guess; milestones/cards may appear
      inside), same NFC/folding discipline, same frozen-urn constraint
      (clean-parsing docs byte-identical — provably unreached code for
      them). Genuinely malformed files stay quarantined per class, reported.
      Fixture: trim 1–2 exemplars from local canonical. Orchestrator runs
      recovery resyncs at acceptance.
Acceptance: census table; exemplar parses with stable urns two-parse; all
      existing fixture urn+text goldens byte-identical; conformance green;
      suite + lint green; expected recovery counts reported.

## P9-3 · Live-resolvable lemma golden  [tier: opus] [status: done] [deps: —]
Goal: the P7-5 lemma golden pins a fixture-only urn (trimmed doc id), so
      live health never exercises the lemma path. Add one golden whose
      expected urn exists in BOTH the fixture corpus and the live corpus
      (a PROIEL-proper sentence urn — fixture doc ids match live ones there;
      verify read-only), keeping the fixture-only one for suite coverage.
Acceptance: golden suite green; live `nabu health` (orchestrator runs it)
      shows the new golden found, not skipped; suite + lint green.

## P9-4a · GRETIL scout + fixture plan  [tier: opus] [status: done] [deps: —]
Goal: research GRETIL (Göttingen Register of Electronic Texts in Indian
      Languages) for adapter feasibility: current corpus format (TEI P5
      e-library? plain text legacy?), download mechanics (bulk? per-text?),
      LICENSE (per-text? blanket? — record honestly; nc/research classes
      exist for a reason), citation structure (what would passages key on —
      GRETIL texts rarely carry CTS; a minted urn scheme sketch), overlap
      with the UD Vedic treebank, corpus scale. Produce: docs/02-sources.md
      row updated + a FIXTURE ACQUISITION PLAN (exact URLs, 2–3 small real
      texts, trim intent, licenses) appended to this packet in the backlog
      for OWNER APPROVAL. No bulk fetching; page-level WebFetch research is
      fine.
Acceptance: the plan is concrete enough to execute on approval; findings
      honest about blockers (license or format may kill it — that is a
      valid outcome).

## Findings & fixture acquisition plan (P9-4a, 2026-07-08 — AWAITING OWNER APPROVAL)

### Verdict

**Viable, but as a new bespoke parser family, and as `nc` (not `open`).** GRETIL's
current corpus is mass-converted **TEI P5 — but NOT EpiDoc/CapiTainS**: no
`refsDecl`, no `cRefPattern`, no CTS URNs, so `EpidocParser` cannot be reused; a
new small-but-real parser family is required (**opus**, per the acceptance note's
"stretch toward a family" test). The license is the *good* surprise: every
mass-converted TEI header carries a uniform **CC BY-NC-SA 4.0** notice, which maps
cleanly to our existing `nc` class (the same class PROIEL/UD already live under) —
**not** the feared `research_private`. The real cost is **addressability
heterogeneity**, not licensing.

### Evidence (cited)

- **Format reality.** TEI P5, `xmlns=tei`, `<TEI>/<teiHeader>/<text><body>`, one
  file per work. Sample headers/bodies inspected verbatim from the GitHub TEI
  mirror `mmehner/gretil-corpus-tei@master` (= the same files served at
  `gretil.sub.uni-goettingen.de/gretil/corpustei/`). Three addressability classes
  found:
  1. **Hand-crafted, fully addressable (minority).**
     `sa_Rgveda-edAufrecht.xml`: `<div type="maṇḍala" n="1"><div type="sūkta"
     n="001"><lg xml:id="RV_1.001.01"><l n="1.001.01a">…`. Vedic accents encoded
     via `<orig>̱</orig>` inside `choice` (per the header's normalization decl).
  2. **Mass-converted verse (the bulk).** `sa_brahmabindUpaniSad.xml`: flat
     `<body>` of `<lg><l>…</l></lg>` with the verse number **inside the text** as
     a marker `// BrbUp_1 //` — **no `@n`, no `@xml:id`, no div hierarchy**.
     Addressable only by parsing the per-text `// Abbr_N //` marker (abbreviation
     and depth vary per text; some are hierarchical like `RV_1,1.1`).
  3. **Prose, non-addressable.** `sa_prajJApAramitAhRdayasUtra.xml`: flat sequence
     of `<p>` with **no numbering of any kind**. Some texts even carry their
     "REFERENCE SYSTEM" as a prose `<p>` (`sa_sAmavedasaMhitA.xml`).
  Encoding: **IAST** romanization throughout (`<text xml:lang="sa-Latn">`), Unicode
  NFC-friendly; the header documents an IAST normalization table. No Devanāgarī, no
  legacy HK/CSX in the TEI layer (those were the pre-2016 legacy formats).
- **Download mechanics.** Per-text files (`.xml` TEI + `.html` + `.txt`
  transforms); site cumulative **`.zip` bundles per language**; **git bulk** via
  the GitHub mirrors (`mmehner/gretil-corpus-tei` = TEI-only, ~784 XML / ~240 MB;
  `INDOLOGY/GRETIL-mirror` = full site incl. legacy); **Zenodo DOI snapshots** for
  citation/archival. Stable direct-file URLs on the site; the directory index
  itself 403s to bots (individual files fetch fine). An adapter would clone the
  TEI mirror — exactly the Perseus/UD git pattern.
- **License, judged honestly.** Uniform in every TEI header:
  `<licence target="…/by-nc-sa/4.0/">Distributed under a Creative Commons
  Attribution-NonCommercial-ShareAlike 4.0 International License.</licence>`,
  preceded by `<availability><p>This e-text was provided to GRETIL in good faith
  that no copyright rights have been infringed. If anyone wishes to assert
  copyright over this file, please contact the GRETIL management … The file will be
  immediately removed pending resolution of the claim.</p>`. GRETIL is an
  **aggregator, not the rights-holder** (data-entry credited "n.n."), so the CC
  grant is GRETIL's, under a takedown disclaimer. → **`license_class: nc`.**
  Practically: ingestable for the owner's local research, indexed/searchable,
  **default-excluded from the MCP surface** (P8-1 excludes `research_private`/
  `restricted`; `nc` is shareable-with-attribution-non-commercially but we still
  never redistribute the corpus). The legacy pre-TEI holdings historically carried
  restrictive per-contributor notices ("private study only"); those are **out of
  scope** — we ingest the TEI corpus only, whose license is clean and uniform.
- **Citation / URN sketch (no CTS upstream, so we mint).**
  `urn:nabu:gretil:<text-slug>:<division-path>` where `<text-slug>` = the filename
  stem sans `sa_` (e.g. `brahmabindUpaniSad`, `Rgveda-edAufrecht`). Division path
  per class: (1) `div @n` join + `lg/@xml:id` or `l/@n` for the addressable
  minority (`…:Rgveda-edAufrecht:1.001.01`); (2) the parsed `// Abbr_N //` marker
  for mass-converted verse (`…:brahmabindUpaniSad:1`); (3) a synthetic sequence
  index `p1, p2…` for non-addressable prose, **flagged in an annotation as
  non-canonical addressing** so a future re-chunk is honest. Minting frozen once
  used (standing rule).
- **Overlap with UD Sanskrit-Vedic.** Complementary, not duplicative. UD Vedic =
  **4,000 sentences / 27k words** *sampled* from RV, Atharvaveda(Śaunaka),
  Maitrāyaṇīsaṃhitā, Aitareya- & Śatapatha-Brāhmaṇa, with gold lemma+morphology
  (its README). GRETIL = the **full running texts** of those works (and hundreds
  more), **no annotation**. Different layers, different granularity, disjoint URN
  namespaces (`urn:nabu:ud:sanskrit-vedic:*` vs `urn:nabu:gretil:*`) — no dedup
  needed; they enrich each other (readable full text ↔ annotated sample).
- **Scale + effort.** TEI corpus ≈ **784 texts / ~240 MB** (Sanskrit-dominant;
  Pali/Prakrit/Tibetan largely still legacy, not yet TEI). Adapter effort:
  **new parser family, opus** — the marker-mining (per-text `// Abbr_N //`
  extraction) plus three-shape addressability plus the `choice/orig/reg` accent
  policy are genuinely new work, not an EpidocParser tweak. Sizing is closer to
  DdbdpParser than to a First1K one-liner.

### FIXTURE ACQUISITION PLAN (owner: approve / amend)

Fetch **3 small real TEI texts** spanning the full addressability spectrum so the
new parser family is tested against every shape it must survive. Primary source =
the GRETIL site; the GitHub TEI mirror serves byte-identical copies and is the
reproducible fetch used for verification.

| # | Text | Site URL (primary) | Mirror URL (raw) | Size | Class | Trim intent |
|---|------|--------------------|------------------|------|-------|-------------|
| 1 | Brahmabindu Upaniṣad | `https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_brahmabindUpaniSad.xml` | `https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_brahmabindUpaniSad.xml` | 12,878 B | mass-converted **verse**, `// BrbUp_N //` markers | **whole** (complete short text, structurally intact) |
| 2 | Prajñāpāramitā-hṛdaya-sūtra (Heart Sūtra) | `https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_prajJApAramitAhRdayasUtra.xml` | `https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_prajJApAramitAhRdayasUtra.xml` | 11,002 B | **prose**, flat `<p>`, **no addressing** | **whole** (complete short text) |
| 3 | Ṛgveda-Saṁhitā (ed. Aufrecht) | `https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_Rgveda-edAufrecht.xml` | `https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_Rgveda-edAufrecht.xml` | ~9 MB | hand-crafted **fully addressable** `div/lg[@xml:id]/l[@n]` + `orig` accents | **trim** to `teiHeader` + Maṇḍala 1, Sūktas 1–3 (`whole: false`; the adapter test asserts trimmed counts, à la UD) |

License notice (identical, quoted once — applies to all three, verbatim from each
`<availability>`):

> This e-text was provided to GRETIL in good faith that no copyright rights have
> been infringed. If anyone wishes to assert copyright over this file, please
> contact the GRETIL management at gretil(at)sub(dot)uni-goettingen(dot)de. The
> file will be immediately removed pending resolution of the claim.
> Distributed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0
> International License.

→ recorded `license_class: nc` for the source; fixtures carry the same.

**Target layout** (`test/fixtures/gretil/`):

```
test/fixtures/gretil/
  README.md                 # retrieval date, URLs, CC BY-NC-SA 4.0 notice, trim procedure
  manifest.yml              # P5-4 schema: per-file url, whole:, trim note; adapter_test asserts trimmed counts
  sa_brahmabindUpaniSad.xml            # whole
  sa_prajJApAramitAhRdayasUtra.xml     # whole
  sa_Rgveda-edAufrecht-m1s1-3.xml      # trimmed: header + maṇḍala 1 sūkta 1–3
```

**README template note:** retrieval date; primary GRETIL URLs + mirror raw URLs;
the verbatim CC BY-NC-SA 4.0 + good-faith/takedown notice above; per-file trim
procedure (files 1–2 `whole: true`; file 3 trimmed to header + M1.S1–3, XML kept
well-formed — close the truncated `div type="maṇḍala"`); a line stating GRETIL is
an aggregator and the legacy non-TEI holdings are **out of scope**.

**If the owner prefers not to ingest `nc` Sanskrit at all**, P9-4b can be dropped
without loss to the classical/Slavic axes — GRETIL is breadth, not a blocker. But
the scout's judgment is that it is worth it: clean uniform license, huge readable
Sanskrit corpus, complements the existing UD/DCS annotation layers.

## P9-4b · GRETIL adapter + parser family  [tier: opus] [status: done] [deps: P9-4a]
FIXTURE PLAN OWNER-APPROVED 2026-07-08 ("proceed with 1-3"). Execute the
P9-4a plan exactly (3 texts, site or byte-identical mirror URLs, nothing
outside the list), then build: GretilParser (new family) handling the three
addressability shapes — attribute-cited div/lg/l, in-text `// Abbr_N //`
verse markers (mined per text), unaddressed prose (paragraph ordinals) —
IAST text, NFC at the boundary, generic fold (san rules per conventions §9);
Gretil adapter: per-text HTTP fetch of registered texts? NO — scope
decision: canonical/gretil/ is populated by fetching the TEI corpus mirror
via git (mmehner/gretil-corpus-tei — byte-identical, GitFetch-compatible,
attic and all) — verify the mirror covers the corpus; if it does, fetch
stays on the shared git path. Registry entry enabled:false, license nc,
translations n/a. urn:nabu:gretil:<text-slug>:<division-or-marker path>.
Conformance + fixtures per the approved plan; first real sync owner-fired.
Acceptance: conformance green; three shapes parse with stable two-parse
urns; README/manifest per plan; 02-sources GRETIL row → READY; suite+lint
green.

## P9-4c · GRETIL quarantine recovery  [tier: opus] [status: done] [deps: P9-4b]
Defect packet (census-first: orchestrator census 2026-07-08 of the 118 files
quarantined by the first real gretil sync — 663 loaded / 118 quarantined of
781). Two classes, three fixes:

1. **xml:id rung (~60 files)** — files like sa_RgvidhAna carry the citation
   only in `xml:id`: `<lg xml:id="RgV_1.1.1">` (often `<l xml:id="RgV_1.1.1a">`
   children); no `n=` attributes, no `//` markers, sometimes no divs at all.
   Add a fourth addressability rung: derive citation from the lg-level (or
   p-level) xml:id by stripping the leading `<Abbr>_` prefix, keeping the
   dotted path (`RgV_1.1.1` → `1.1.1`). Line-level ids (`…1.1.1a`) are NOT
   separate passages — the lg is the passage, same as the marker rung.
   Casualties recovered include Rāmāyaṇa, Buddhacarita, Gītagovinda,
   Kirātārjunīya, Paippalāda Saṃhitā.

2. **Pipe-marker variant (~13 files)** — sa_bAdarAyaNa-brahmasUtra etc. use
   `| BBs_1,1.1 |` (single-pipe delimiters, comma level separators) instead
   of `// Abbr_N //`. Extend the in-text marker recognizer to accept the
   single-pipe form; commas in the citation normalize to the same separator
   the `//` rung already emits (keep whatever P9-4b chose — two-parse
   stability is the contract, cross-file cosmetics are not).

3. **Collision tolerance (45 files)** — parser currently hard-fails the
   document on the first duplicate citation. Census: ~39 single-prefix
   collisions = upstream numbering typos (sa_AnandabhaTTa-vallAlacarita runs
   1.76→1.70→1.78; sa_bhAgavatapurANa has a decade of verses inside chapter
   3.31 mislabeled 03.32.0xx) or legitimate repeats (sa_harSadeva-nAgAnanda:
   Prakrit verse + Sanskrit chāyā both numbered Nā_1.19). Fix per ddbdp
   precedent: on collision, disambiguate deterministically (second occurrence
   gets a `:b2` suffix, third `:b3`, document order) — never quarantine, never
   merge. 6 multi-prefix files (sa_Anandavardhana-dhvanyAloka DhvK_/DhvA_,
   sa_IzvarakRSNa-sAMkhyakArikA-comm ISk_/SkMv_, sa_kuntaka-vakroktijIvita-comm,
   sa_mAdhava-jaiminIyanyAyamAlAvistara, sa_nAgArjuna-pratItyasamutpAdahRdayavyAkhyAna,
   plus dhvanyAloka-comm): when a file's markers carry ≥2 distinct prefixes,
   the prefix joins the citation (`:DhvK.1.1` vs `:DhvA.1.1`) so kārikā and
   commentary don't collide. Prefixes may contain non-ASCII (KūrmP_, Nā_).

Fixtures: trimmed REAL slices from canonical/gretil/ (already on disk, no
network): sa_RgvidhAna (xml:id rung), sa_bAdarAyaNa-brahmasUtra (pipe
markers), sa_AnandabhaTTa-vallAlacarita (single-prefix collision),
sa_Anandavardhana-dhvanyAloka-comm (multi-prefix). Note in fixture README
these are cut from the local canonical clone (mmehner/gretil-corpus-tei),
retrieval date 2026-07-08, license CC BY-NC-SA (nc) — same as P9-4b fixtures.

FROZEN-URN GUARD (standing acceptance): the 663 clean docs must re-parse
byte-identical — verify with a read-only two-parse census against the live
catalog before/after (orchestrator will re-verify at review). Fixes 1–2 only
touch previously-quarantined shapes; fix 3's multi-prefix rule fires only on
files with ≥2 prefixes (all currently quarantined) — assert that in a test.
Single-prefix collision suffixing must not alter non-colliding citations.

Acceptance: conformance green for new fixtures; suite+lint green;
`bin/nabu sync gretil --parse-only` quarantine count 118 → ~0 (orchestrator
runs the live smoke); frozen-URN census clean; docs/02-sources.md GRETIL row
notes the recovered classes.

## P9-5a · ORACC scout + fixture plan  [tier: opus] [status: done] [deps: —]
Goal: research ORACC (Open Richly Annotated Cuneiform Corpus) for adapter
      feasibility: JSON API vs ATF, project structure (oracc.museum.upenn
      .edu projects — SAAo, RINAP, etc.), license (CC BY-SA 3.0 blanket?
      verify per project), what a passage is (line? sentence? the
      transliteration vs normalization vs translation layers — which do we
      ingest as text; lemmatization is often PRESENT in ORACC JSON — note
      the annotations opportunity), urn minting sketch (P-numbers/Q-numbers
      are stable museum ids), corpus scale per project, which 1–2 projects
      to start with. Produce: 02-sources row + FIXTURE ACQUISITION PLAN for
      OWNER APPROVAL, as 4a.
Acceptance: as 4a. This is the founding dream (Nabu's own tablets) — the
      scout should also honestly size the parser-family effort (ATF/JSON =
      new family, fable).

## Findings & fixture acquisition plan (P9-5a, 2026-07-08 — AWAITING OWNER APPROVAL)

### Verdict

**Viable, and the cleanest new source since Perseus — a new bespoke parser family
(fable, ~DdbdpParser-tier), license `open` (CC0, better than the CC BY-SA our table
recorded).** ORACC's open data is **ORACC JSON**: each `corpusjson/<id>.json` is a
nested `cdl` tree from which a transliteration line reconstructs mechanically, and
**every word carries gold lemmatization** (`norm`/`cf`/`gw`/`sense`/`pos`) — the
`annotations_json` lemma-search goldmine the packet hoped for. Two honest
corrections to the optimistic brief: (1) **prose translations are NOT in the JSON**
(they live only in the ATF `#tr.en:` source layer — aligned English is a future
parallel-doc job, not v1); (2) delivery is a **per-project zip over HTTP, not git**,
so ORACC is the **first adapter that can't reuse the git-clone `fetch`** — it needs
a small new HTTP-zip fetch path. That second point, plus the non-IE language family
and the founding-dream weight, is why I recommend P9-5b be **Phase 10's headline,
not a tail packet in an already-rich Phase 9** (see "Phase shape" below).

### Evidence (cited; all fetched 2026-07-08)

- **Format reality — the cdl tree.** `https://oracc.museum.upenn.edu/json/rimanum.zip`
  (2.9 MB) → `rimanum/corpusjson/P405432.json` inspected verbatim. Top keys:
  `type` (`cdl`), `project`, `textid`, `license`, `license-url`, `cdl`. The `cdl`
  value is a tree of three node kinds: **`c`** (chunk: `text` > `discourse`/`body` >
  `sentence`, the sentence carrying a human `label` like `"o 1 - r 5"`), **`d`**
  (discontinuity: `type:"object"` tablet, `type:"surface"` obverse/reverse with
  `subtype`+`label`, `type:"line-start"` with `n` line-number + `label` like `"o 1"`),
  **`l`** (lemma: one word). A transliteration line reconstructs by walking the tree
  and concatenating each `l`-node's `f.form` between `line-start` d-nodes, tracking
  the current `surface` — verified, e.g. obverse line 1 = `2(BARIG) ZI₃ US₂ a-na GEŠBUN`,
  determinatives (`du-un-nu-um{ki}`, `{d}EN.ZU-še-mi`, `{iti}KIN.{d}INANNA`) and
  subscript numerals (`ZI₃`, `E₂`, `U₄`) intact, NFC-clean.
- **Lemmatization layer (the opportunity).** Every content `l`-node's `f` object
  carries: `form` (transliteration), `norm` (normalization, e.g. `qēmu`, `Dunnum`),
  `cf` (citation form / dictionary lemma, e.g. `awīlu`, `bītu`), `gw` + `sense`
  (English guide word, e.g. `flour`, `man`, `house`), `pos`/`epos` (part of speech),
  and a `gdl` grapheme-description array (sign readings, determinative/logogram roles,
  per-grapheme `logolang`). This maps directly onto `Passage#annotations` and the
  P7-5 lemma index — Akkadian/Sumerian lemma search for free.
- **What a passage is.** The natural unit is the **line** (the `line-start` d-node,
  with `label`/`n`) — clean, stable, matches how Assyriologists cite ("obv. 5"). The
  `sentence` `c`-node is an alternative but its labels span ranges (`"o 1 - r 5"`) and
  many are `implicit:"yes"`; **line is the right Passage grain**, sentence/clause
  membership recorded in annotations if wanted. `Passage#text` = the **transliteration**
  (the scholarly text, per conventions.md §4) reconstructed from `l.form` fragments;
  `norm`/`cf`/`gw`/`pos` ride in `annotations`. Folding (flag for the adapter packet,
  don't decide here): the generic fold strips IAST-style diacritics, which for Akkadian
  norm would conflate ā/a, š→s, ṣ→s, ṭ→t (accepted, same tradeoff as Greek/Sanskrit);
  but the **transliteration** carries structural punctuation (`{det}`, subscript
  digits, `.`/`-` sign joins) that a search form should probably strip to bare sign
  readings — a real new per-language rule (`akk`/`sux`), sketched here, decided in 5b.
- **Translations — honest finding.** Scanned all **265 `saao/saa01` texts**
  (`https://oracc.museum.upenn.edu/json/saao-saa01.zip`, 5.0 MB): node types
  `{c, d, l}` only, **0 prose-translation nodes**. Running English exists in ORACC
  (SAA is famous for it) but lives in the **ATF source** (`#tr.en:` lines) and the
  rendered HTML, not the open-data JSON. So: word-glosses (`gw`) yes, aligned
  sentence translations no — those are a future ATF-parse / parallel-document
  enhancement (P7-4 shape), explicitly out of the v1 JSON adapter.
- **URN sketch.** Ids are stable CDLI/ORACC museum numbers of two kinds, both seen:
  **P-numbers** (physical artifacts — `rimanum`, `saao`) and **Q-numbers** (composite/
  reconstructed texts — `rinap/rinap1` = 96 Q-texts, `etcsri` = 1456 Q-texts). Sketch:
  `urn:nabu:oracc:<project>:<P/Q-number>:<line-label>` where `<project>` keeps the
  subproject slash-path flattened (`saao-saa01`), and `<line-label>` = the `line-start`
  `label` (`o.1`, `r.5`) — stable, human-legible, matches citation practice. Minting
  frozen once used (standing rule).
- **License — machine-readable, and a correction.** Both `metadata.json` AND every
  `corpusjson/*.json` carry `"license"` + `"license-url"`. All **8 projects sampled**
  (saao, rinap, etcsri, riao, dcclt, blms, ribo, rimanum) report verbatim
  `"This data is released under the CC0 license"` +
  `https://creativecommons.org/publicdomain/zero/1.0/` → **`license_class: open`**
  (public domain). The ORACC website/docs footer still shows the 2014 blanket
  *"Creative Commons Attribution Share-Alike license 3.0"* (which our 02-sources row
  recorded, and a 2018 third-party mirror cited) — the current JSON build supersedes
  it per-project with CC0. **The adapter reads the per-project `license` field and
  maps it (CC0→open, CC BY-SA→attribution); it never hardcodes** — future projects may
  differ.
- **Network mechanics.** Per-project **zip over HTTP**:
  `https://oracc.museum.upenn.edu/json/<project>.zip` (subprojects hyphenated,
  e.g. `saao-saa01.zip`), served `application/zip` with `Last-Modified` (change
  detection without full re-download). **No git repo** holds the data
  (`oracc/publicdata` empty/2016, `oracc/json` 404). So `fetch` is a **new
  HTTP-download-and-unzip path**, not `Nabu::GitFetch` — the one genuinely new
  plumbing piece (the attic/retention contract still applies to the unpacked files).
  Sub-project discovery via `https://oracc.museum.upenn.edu/projects.json` (144 public
  entries). `.atf` per-text endpoints 404 individually; ATF (translations) would be a
  separate source acquisition — deferred.
- **Effort sizing.** **New parser family, fable** (the packet's tag stands). The cdl
  tree walk is *simpler* than DDbDP's Leiden XML mixed-content, but the decision
  density is comparable: translit line reconstruction + surface/line tracking,
  P-vs-Q urn policy, the `akk-x-oldbab`/`sux` language question (Sumerian logograms
  appear *inside* Akkadian words via `gdl.logolang` — per-word lang in annotations,
  per-text primary lang for `Passage#language`; note `akk-x-oldbab` is valid BCP-47
  private-use, maps to base `akk`), the annotations schema, and the new translit
  folding rule. Plus the **new HTTP-zip fetcher** (small, but net-new). Sizing ≈
  DdbdpParser, not a First1K one-liner.

### FIXTURE ACQUISITION PLAN (owner: approve / amend)

Fetch **two mini-slices from two projects** so the new family is tested against both
id-schemes (P/Q), both languages (Akkadian/Sumerian), and the full node vocabulary.
The fetch unit is the whole project zip (small); each fixture is an **extract** from
it — corpusjson text files kept **whole** (a cdl tree is atomic; trimming breaks the
JSON and the sentence/lemma structure), `metadata.json` kept **whole** (the adapter
reads its license + config), `catalogue.json` **trimmed** to the fixtured ids only
(it lists every project text; keep just the entries the adapter needs for titles).

**Slice A — `rimanum` (Akkadian, P-numbers, CC0)** — zip:
`https://oracc.museum.upenn.edu/json/rimanum.zip` (2.9 MB):

| Extract | Size | whole? | Note |
|---|---|---|---|
| `rimanum/metadata.json` | ~27 KB | whole | license (`CC0`) + project name/config; adapter reads license here |
| `rimanum/catalogue.json` | 376 KB → few KB | trimmed | keep only the 3 fixtured P-numbers' catalog entries (designation/period/provenience → doc titles) |
| `rimanum/corpusjson/P405432.json` | 59 KB | whole | the rich exemplar: obverse+reverse surfaces, 25 lemmas, determinatives, subscripts, full `norm`/`cf`/`gw` |
| `rimanum/corpusjson/P405134.json` | 25 KB | whole | a shorter second Akkadian text |
| `rimanum/corpusjson/P405254.json` | 0 B | whole | **empty** (catalog-only, no transliteration) — the no-content case the parser must skip/quarantine honestly |

**Slice B — `etcsri` (Sumerian, Q-numbers, CC0)** — zip:
`https://oracc.museum.upenn.edu/json/etcsri.zip` (12.9 MB):

| Extract | Size | whole? | Note |
|---|---|---|---|
| `etcsri/metadata.json` | ~30 KB | whole | license (`CC0`) + config |
| `etcsri/catalogue.json` | large → few KB | trimmed | keep only the 2 fixtured Q-numbers' entries |
| `etcsri/corpusjson/Q004151.json` | ~15 KB | whole | Sumerian royal inscription (Amar-Suen), `lang:"sux"`, lemmatized (`cf`/`gw`) — the Q-number + Sumerian case |
| `etcsri/corpusjson/<one more small Q>.json` | ≤30 KB | whole | second Sumerian text (pick the next smallest non-empty Q at fetch time) |

Total fixture footprint well under **500 KB**. License notice (identical, machine-read,
quoted once — applies to every file, verbatim from each `metadata.json`/corpusjson):

> This data is released under the CC0 license
> (https://creativecommons.org/publicdomain/zero/1.0/)

→ recorded `license_class: open` for the source; the adapter reads it per-project.

**Target layout** (`test/fixtures/oracc/`):

```
test/fixtures/oracc/
  README.md                 # retrieval date, project-zip URLs, CC0 notice, per-file extract/trim procedure, "translations live in ATF not JSON" note
  manifest.yml              # P5-4 schema: per-file url (the project zip), whole:, trim note; adapter_test asserts reconstructed line/lemma counts
  rimanum/
    metadata.json                     # whole
    catalogue.json                    # trimmed to the 3 fixtured P-numbers
    corpusjson/P405432.json           # whole (rich Akkadian)
    corpusjson/P405134.json           # whole (short Akkadian)
    corpusjson/P405254.json           # whole (empty / no-content case)
  etcsri/
    metadata.json                     # whole
    catalogue.json                    # trimmed to the 2 fixtured Q-numbers
    corpusjson/Q004151.json           # whole (Sumerian, Q-number)
    corpusjson/<Q…>.json              # whole (second Sumerian)
```

**README template note:** retrieval date; the two project-zip URLs; the verbatim CC0
notice above; per-file extract procedure (corpusjson + metadata whole, catalogue
trimmed to fixtured ids only, JSON kept well-formed); the explicit honest notes that
(a) **prose translations are not in the JSON** (ATF-only, deferred) and (b) the fetch
is an **HTTP zip**, not a git clone.

**Phase shape (my recommendation).** Keep this scout (P9-5a) in Phase 9; make **P9-5b
the Phase 10 headline, not a Phase 9 tail packet.** Rationale: 5b carries *two*
net-new mechanics at once — the bespoke JSON `cdl` parser family **and** the first
non-git (HTTP-zip) `fetch` path — over a non-IE language family, and it is the
founding dream (the system is named for Nabu). Phase 9 is already rich (P9-1/2/3
done, GRETIL adapter P9-4b, Slavic survey P9-6); cramming the largest remaining
packet into its tail underserves it. Phase 10 headline = ORACC adapter (P9-5b) +
the top pick(s) from the P9-6 Slavic survey. **If instead the owner wants ORACC in
Phase 9**, it is fully unblockable on fixture approval — the format is clean and the
plan above is execution-ready.

## P9-5b · ORACC adapter + parser family  [tier: fable] [status: deferred: Phase 10 headline (owner 2026-07-08)] [deps: P9-5a]
FIXTURE PLAN OWNER-APPROVED 2026-07-08 (no re-ask needed in Phase 10).
Carries two net-new mechanics: the JSON cdl parser family and the first
non-git HTTP-zip fetch path (+ translit folding rules for akk/sux).
Elaborated fully at the Phase 9 gate as Phase 10's headline.

## P9-6 · Slavic sources survey  [tier: opus] [status: done] [deps: —]
Goal: scouting survey for the owner's Slavic research axis beyond
      TOROT/PROIEL: what OCS / Old East Slavic / Church Slavonic corpora
      are digitized, licensed, and machine-readable (candidates to assess:
      Codex Suprasliensis digital editions, the Ruthenian/RNC historical
      corpora access model, Obdurodon/Slavonic projects, manuscript
      libraries with transcriptions, SEENET/eSlavistik e-editions —
      research broadly, judge licensing honestly incl. "viewable but not
      redistributable" traps). Produce docs/slavic-survey.md: per-candidate
      format/license/scale/citation-scheme/effort estimate + a ranked
      recommendation of at most two for Phase 10. No fetching beyond
      research pages.
Acceptance: survey doc complete and honest; 02-sources.md gains candidate
      rows marked SURVEYED.

### Findings (P9-6, 2026-07-08 — survey delivered, docs/slavic-survey.md)

RANKED ≤2 FOR PHASE 10: **#1 UD Slavic treebank expansion** (add
`old-east-slavic-birchbark` + `old-east-slavic-rnc` to the `ud` adapter's
`TREEBANKS` map — both `CC BY-SA 4.0` CoNLL-U, genuinely-new vernacular OES
birchbark letters 1025–1500 + Middle Russian 1300–1700, absent from TOROT/PROIEL;
**zero new parser family**, reuses ConlluParser + UD plumbing; `attribution` =
MCP-safe; deliberately EXCLUDE the chu-PROIEL/orv-TOROT UD conversions that would
double-load the native sync). **#2 CCMH** (7 canonical OCS texts, transliteration
+ simple XML, openly downloadable from Kielipankki/CLARIN `Open`; real gain =
Codex Assemanianus + Savvina kniga, absent from current holdings; needs a small
new bespoke family; adapter reads the exact CC at ingestion). Honorable mention:
**obdurodon Codex Suprasliensis** critical edition (richest single OCS ms +
parallel Greek, but `CC BY-NC-SA 3.0` = `nc`/MCP-excluded, and per-text website
crawl, and overlaps TOROT's Suprasliensis as a fuller alt-edition).
NOT-INGESTABLE (SURVEYED-BLOCKED, unblock paths in the survey): TITUS (custom
scholarly-only/non-commercial terms, no redistribution, legacy encodings →
`research_private`); RNC full historical corpora (query-only, "cannot be
distributed" — its `CC BY-SA 4.0` UD releases ARE pick #1); "Манускриптъ"
manuscripts.ru (retrieval system, no export — write for a grant); Sreznevsky
Materialy (page scans only, no machine-readable TEI); SEENET/eSlavistik (no
distinct open corpus located). Phase-10 shape: ORACC stays headline (P9-5b),
pick #1 rides alongside as the smallest-possible companion packet, pick #2 as the
follow-on scout→plan→adapter track.

## Phase 10 — Cuneiform + Slavic breadth (branch: phase-10; elaborated 2026-07-09)

Owner go: "Merged, let's proceed" (2026-07-09) after PR #10. Headline = ORACC
(the P9-5b deferral comes due; fixture plan owner-approved 2026-07-08 in P9-5a);
companion = UD Slavic expansion (P9-6 pick #1); rider = GRETIL residue
micro-packet (P9-4c census follow-up). Sequential dispatch, orchestrator
live-smoke review between packets, real network syncs owner-fired (EXCEPT the
two pre-approved fixture zips in P10-1 and the two UD fixture fetches in P10-2,
which are part of the approved fixture plans).

## P10-1 · ORACC adapter + parser family  [tier: fable] [status: done] [deps: —]
Execute the P9-5a plan exactly (see "Findings & fixture acquisition plan
(P9-5a)" above — it is the spec; this packet adds only sequencing notes):

- FIXTURES FIRST (network, pre-approved): download the two project zips
  (rimanum 2.9 MB, etcsri 12.9 MB) to scratch, extract EXACTLY the slices in
  the P9-5a table (corpusjson texts WHOLE incl. the empty P405254.json,
  metadata.json WHOLE, catalogue.json TRIMMED to fixtured ids), into
  test/fixtures/oracc/. README with retrieval date + URLs + CC0 note.
  Nothing else fetched; zips deleted from scratch after extraction.
- OraccJsonParser (new family): walk the cdl tree (c/d/l nodes); passage =
  line (d-node line-start, label as citation); Passage#text = transliteration
  reconstructed from l.form fragments; norm/cf/gw/sense/pos/gdl ride in
  annotations. Empty corpusjson (P405254) skips honestly (not quarantine —
  catalog-only artifacts are an upstream norm, not damage; count them in the
  sync note).
- Lemmas: cf (citation form) → passage_lemmas rows (language akk/sux), gw as
  gloss annotation — Akkadian/Sumerian lemma search lands with the adapter.
- Language: per-text primary lang for Passage#language (akk-x-oldbab → akk
  base mapping, sux); per-word logolang in annotations only.
- URNs: urn:nabu:oracc:<project>:<P/Q-number>:<line-label> (o.1, r.5);
  subproject paths flattened with hyphens (saao-saa01). Frozen once minted.
- License: READ per-project from metadata.json license field, map
  CC0→open, CC BY-SA→attribution; never hardcode.
- Fetch: new HTTP-zip path (NOT GitFetch): download <project>.zip with
  Last-Modified change detection, unpack to canonical/oracc/<project>/;
  retention contract holds — files present locally but absent from a fresh
  zip go to .attic with manifest, never deleted. Zip handling via
  Nabu::Shell.run unzip (no new gem without asking).
- Registry: oracc source, enabled: false, sync_policy: manual,
  translations: false (JSON has no prose translations — P9-5a finding; ATF
  #tr.en is a future separate acquisition).
- Folding: new akk/sux search-form rule — strip structural punctuation from
  transliteration ({det} determinative braces, sign-join ./-, subscript
  digits normalized) so `search` hits bare sign readings; norm diacritics
  fold under the generic rule (ā→a, š→s — accepted conflation, same
  tradeoff as grc/san). Rule documented in conventions.md §9.
- Acceptance: conformance green (both fixtures parse, two-parse URN
  stability, NFC, license class present); lemma rows for cf forms present
  after fixture load; suite+lint green; docs/02-sources.md ORACC row →
  READY (enabled:false awaiting owner sync); architecture §8 note for the
  HTTP-zip fetch path; worklog line (sha —).

## P10-2 · UD Slavic treebank expansion  [tier: opus] [status: done] [deps: P10-1]
P9-6 pick #1 (owner-approved via phase go). Add to the ud adapter's TREEBANKS
map: old-east-slavic-birchbark (UD_Old_East_Slavic-Birchbark) and
old-east-slavic-rnc (UD_Old_East_Slavic-RNC, Middle Russian 1300–1700). Both
CC BY-SA 4.0 (attribution — verify in each repo's README at fixture time and
record in the fixture README; if either differs, STOP and report). Fixture:
one trimmed real .conllu slice per treebank (~50 sentences, structurally
intact multiword/empty-node cases if present) fetched from the UD GitHub
repos — the ONLY network in this packet. urn:nabu:ud:<treebank>:<sent_id>.
DEDUP GUARD (the survey's hazard): do NOT add the UD chu-PROIEL or orv-TOROT
conversions — assert in a test that TREEBANKS excludes them (they double-load
the native proiel/torot syncs). Conformance + idempotency; language codes orv
(both treebanks; RNC is Middle Russian under orv in UD). Registry unchanged
(ud source exists; enabled stays as-is). Acceptance: conformance green;
fixture load produces lemma rows (orv) via existing plumbing; suite+lint
green; 02-sources UD row lists 6 treebanks; worklog line.

## P10-3 · GRETIL residue micro-packet  [tier: opus] [status: done] [deps: P10-1, P10-2 merged order irrelevant — touches only gretil_parser]
P9-4c census follow-up: recover the 4 recoverable residue files (target
quarantines 8 → 4, the remaining 4 being genuinely unaddressable flat lists):
(a) sa_vimalamitra-abhidharmadIpa — hyphenated marker prefix `// Abhidh-d_N //`
(the prefix charset currently rejects `-`); (b) sa_sAtvatatantra,
sa_somAnanda-zAktavijJAna, sa_puruSottamadeva-ekAkSarakoza — leading-`//`-only
markers `// Abbr_N</l>` (no closing delimiter; the `</l>` boundary
terminates). Extend the marker recognizer for both shapes AS FALLBACK-SAFE
variants (same discipline as P9-4c: primary MARKER regex stays byte-identical;
new shapes only rescue docs the existing rungs leave empty, proven by the
frozen-URN census). Fixtures: trimmed real slices of abhidharmadIpa + one
leading-// file from canonical/gretil/ (no network). Acceptance: two-parse
stability; read-only frozen census over canonical/gretil/ shows 773 loaded
docs byte-identical; parse-only sync quarantine 8 → 4; suite+lint green;
worklog line.

## P10-gate · Phase 10 gate  [tier: orchestrator] [status: pending] [deps: P10-1..3]
Full-diff review, live smokes already done per-packet, README + library.md
truthfulness pass (new ORACC section + treebank row update + header totals),
02-sources statuses, worklog shas, PR, sticky alarm LAST. Owner-fired after
merge: bin/nabu sync oracc <projects TBD — owner picks starter set> and
bin/nabu sync ud; then enabled flips with sign-off comments.

## P10-4 · Per-treebank license override plumbing  [tier: opus] [status: done] [deps: P10-2]
Defect (orchestrator live smoke after the owner-fired `sync ud`, 2026-07-09):
the two new Slavic treebanks are CC BY-SA 4.0 (verified in-repo, P10-2) but
`show` reports them `license: nc` — they inherit the ud SOURCE class
(`nc`, correct for the PROIEL-derived treebanks) because
`documents.license_override` (the P1-3 column, honored by the entire query
layer: catalog_join, show, export, MCP) has NO WRITE PATH — no adapter has
ever set it. Mislabel is in the restrictive direction (no leak), but it
sells the shareable shelf short: birchbark/RNC are attribution-class and
should be MCP-labeled as such.

Fix: thread a per-document license override from adapter → loader →
documents.license_override.
- TREEBANKS map gains optional license/license_class per treebank; the two
  Slavic entries set license_class attribution (license "CC BY-SA 4.0").
- The adapter surfaces it on the parsed document (extend the value object /
  DocumentRef with an optional license_override field, nil default — decide
  the cleanest seam after reading adapter.rb + loader).
- Loader persists it on create AND on re-load (metadata update, like title:
  NO revision bump, content_sha256 untouched — license relabeling must not
  fake a content change; pin that in a test).
- Constraint: value must be a valid class (db CHECK exists) — loader/adapter
  validates against the enum.
- Tests: fixture load shows the two Slavic treebanks attribution + the four
  legacy treebanks still nc (source class, override NULL); idempotency (two
  loads, no revision drift); a doc whose override is REMOVED from the map
  reverts to NULL on next load.
- After the code lands the orchestrator re-runs `sync ud --parse-only`
  equivalent (owner db) to relabel the six live docs and verifies via show +
  MCP that license_class reads attribution.
Acceptance: suite+lint green; live relabel verified; 02-sources UD row
notes the split licensing; worklog line (sha —).
