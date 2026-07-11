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

## Phase 11 — Philology workbench + Old English axis (branch: phase-11; elaborated 2026-07-09)

Owner shape (2026-07-09): workbench as recommended (alignment hub, dictionary
shelf, biblical trio) PLUS a new axis — "I didn't mention interest in Old
English / Anglo-Saxon previously but it does exist, so it's opportune to add
it to sources search. Also relevant if we move along Philology/Biblic axis."
Riders: HTTP remote-health probe (the ORACC gap), ORACC project expansion
(config-only). Morph facets + vocab profiling: stretch, only if the phase
runs light. Sequential dispatch, live-smoke review between packets, real
syncs owner-fired.

## P11-1 · Old English / Anglo-Saxon sources survey  [tier: opus] [status: done] [deps: —]
Scouting only (docs/slavic-survey.md is the pattern and quality bar): no
code, no bulk fetch — page-level WebSearch/WebFetch + repo metadata only.
Goal: rank the ingestable OE sources; name the blocked ones honestly with
unblock paths. Leads to verify (not exhaustive — find more):
- **ISWOC** (Oslo, Bech/Eide) — PROIEL XML family (we parse it already:
  proiel + torot adapters); contains Ælfric's Catholic Homilies, Apollonius
  of Tyre, Orosius, Anglo-Saxon Chronicle (+ Old French/Spanish/Portuguese
  we'd skip). If format+license check out (expect CC BY-NC-SA like
  PROIEL/TOROT) this is the near-config-only pick. Verify repo, release
  state, exact texts, license.
- **YCOE** (York-Toronto-Helsinki Parsed Corpus of OE Prose) + **YCOEP**
  (poetry) — Penn-Helsinki bracketed format (NEW parser family if taken);
  distribution/license historically via the Oxford Text Archive — verify
  current terms (research-only? redistribution?).
- **Dictionary of Old English Corpus (DOEC)** — the complete surviving OE
  record (~3M words) but University of Toronto LICENSED product — expect
  BLOCKED; document terms + unblock path (institutional/personal license =
  research_private at best).
- **West-Saxon Gospels** (the biblical-axis prize — feeds the P11-3
  alignment hub as the sixth Gospel version): find the best machine-readable
  edition (ISWOC? YCOE? a TEI edition? Bosworth-Toller-adjacent projects?).
- **ASPR / OE poetry** (Beowulf, Exeter Book, Junius): open TEI editions?
  (e.g. "Old English Poetry in Facsimile" project — check data availability
  and license).
- **Bosworth-Toller** OE dictionary (germanet-style shelf candidate for
  P11-4's dictionary pattern; digitized at bosworthtoller.com — check data
  license/API).
- UD: is there an Old English treebank? (None known in UD as of scout
  memory — verify; if one exists it's a config-only UD map add per the
  P10-2 pattern.)
Deliverable: docs/oe-survey.md (ranked picks ≤2 for Phase 11/12 ingestion,
blocked list with unblock paths, biblical-axis note on Gospel versions);
02-sources.md rows for every surveyed source; backlog status → done +
Findings block; worklog line (sha —). No adapter work in this packet.

### Findings (P11-1, 2026-07-09 — survey delivered, docs/oe-survey.md)

RANKED ≤2: **#1 ISWOC Treebank** (Oslo, Bech & Eide) — **PROIEL XML 2.1, the
exact schema proiel/torot already parse** (verified in the raw file:
`schema-version="2.1"`, same `proiel.xsd`); 5 OE texts ≈ 29,406 gold-annotated
tokens: Ælfric's **Lives of Saints** (packet lead said Catholic Homilies —
corrected), Apollonius of Tyre, Anglo-Saxon Chronicles, Orosius, West-Saxon
Gospels; license verbatim (README): "freely available under a Creative Commons
Attribution-NonCommercial-ShareAlike 3.0 License" + per-source `<license>CC
BY-NC-SA 3.0</license>` → `nc`, same class as its PROIEL siblings. Adapter =
TOROT-pattern subclass + `ang` language filter (repo also carries 10 medieval
Romance texts to skip). Repos: `iswoc/iswoc-treebank` (frozen) → successor
`syntacticus/syntacticus-treebank-data` (**must scope to `iswoc/` subdir — its
`proiel/`/`torot/` dirs are the already-synced data**). **BIBLICAL AXIS
ANSWER:** ISWOC `wscp` is **the Gospel of MARK complete (chs 1–16, 671 verse
citations) + fragments of Matt 7/John 1** — NOT four Gospels; native
`citation-part="MARK 1.1"` verse refs are already lifted by ProielParser → OE
Mark is a drop-in sixth P11-3 hub witness with zero citation plumbing. Full
tetraevangelion paths (all costly): YCOE `cowsgosp.o3` conversion (Penn format
+ OTA noncommercial terms) or PD reconstruction from Skeat/Bosworth-Waring
scans; no open TEI OE Gospels edition exists. **#2 ASPR via OTA 3009** — the
complete six-volume Krapp & Dobbie OE poetry corpus (Beowulf, Junius, Vercelli,
Exeter, Paris Psalter, Minor Poems incl. Cædmon's Hymn in Northumbrian AND WS
versions; 374 texts, ~30.5k lines) as ONE 2.2 MB TEI-P5 file, fetched without
auth; license verbatim in the TEI header itself: "Distributed by the University
of Oxford under a Creative Commons Attribution-ShareAlike 3.0 Unported License"
→ `attribution`, the only fully-open structured OE found, MCP-safe. NOT
EpiDoc/CTS, no `l/@n` → new small bespoke TEI family, ordinal line citations.
DICTIONARY SHELF (P11-4): **Bosworth-Toller LINDAT dump** hdl 11234/1-3532,
verbatim "Attribution 4.0 International (CC BY 4.0)", SQL + lemma-keyed CSV
(`id;headword;body`, body XML) — third lexicon candidate. SURVEYED (later):
YCOE/YCOEP (~1.5M words OE prose canon + 71k poetry, Penn bracketed = new
family, OTA "ACA Academic Use" noncommercial with layered copyright, no text
redistribution grant). BLOCKED: DOEC (subscription; verbatim "Recompiling,
copying, publication, or republication … only with specific written permission";
unblock = written permission, or verify the 2000 release on OTA 2488 academic-
use); OE Poetry in Facsimile (web-app, no reuse grant); Electronic Beowulf (©
Kiernan + British Library); Jebson ASC ("all rights reserved", XHTML only);
Digital Ælfric (commercial); CoNE/PASE/LangScape (restricted/metadata). **UD
has NO Old English treebank** (verified — no config-only add exists). MENOTA
confirmed no OE. 02-sources: new rows #34 ISWOC / #35 ASPR / #36 B-T / #37
YCOE+YCOEP (Tier 2), #38 DOEC / #39 OE web-app editions (Tier 3); UD #4 +
Menota #21 notes.

## P11-2 · HTTP remote-health probe  [tier: opus] [status: done] [deps: —]
The P10 known gap: health --remote is git-shaped (ls-remote) and reads the
ORACC HTTP-zip upstream as gone. Teach the remote probe a per-source probe
strategy keyed off the adapter/manifest (git → ls-remote as today; http-zip
→ HEAD request checking 200 + Last-Modified drift vs the stored
.zip-fetch.json pin; license baseline for oracc = per-project metadata.json
license field re-read on probe? NO network-heavy downloads — HEAD only,
plus GET of metadata.json ONLY (small) for license drift). Tests stub HTTP.
02-sources + ops.md updated; probe output shows oracc rows honestly.
Acceptance: nabu health --remote (owner-run, or stubbed test) no longer
reports oracc as gone; suite+lint green; worklog line.

## P11-3 · Cross-source alignment hub  [tier: fable] [status: done] [deps: —]
improvements.md §1.2 comes due. Design + implement the alignment layer:
align the SAME work across sources/languages at citation grain. Flagship:
the parallel New Testament — greek-nt (PROIEL grc) ↔ latin-nt (Vulgate,
PROIEL lat) ↔ gothic-nt (PROIEL got) ↔ armenian-nt (PROIEL xcl) ↔ marianus
(OCS, PROIEL chu) — all five already in the catalog with verse-grained
citations and gold lemmas. Design questions the packet must answer (design
doc section in architecture.md BEFORE code): alignment table schema
(work-level registry + citation-mapping rules vs materialized passage
pairs?); citation normalization across sources (PROIEL sentence ids vs
book.chapter.verse — check what the proiel adapter actually minted);
rebuild-safety (alignment = derived data, must replay from a declarative
registry — enrichment journal or config?); query surface (`show --align`?
extend --parallel? a new `align` subcommand? MCP tool nabu_align?); how
GRETIL commentary layers and future West-Saxon Gospels plug in later.
Scope control: ship the NT five-way as the working proof; the mechanism
must be registry-driven (adding a sixth version = registry entry, not
code). Acceptance: a verse (e.g. John 1:1) renders five-way aligned in one
command with per-version license labels; alignment survives nabu rebuild;
suite+lint green; architecture §10 written; worklog line.

### Findings (P11-3, 2026-07-09 — shipped; architecture §10 is the design record)

CITATION REALITY (verified live): passage urns are SENTENCE ids; verse
identity lives in per-token `citation_part` ("MARK 2.3") in annotations_json
(the passage-level `citation` is only the first token's part); sentence↔verse
is many-to-many (846 greek-nt sentences span verses); all five witnesses share
one book vocabulary but refs are work-scoped (Cicero cites bookless "1.1");
Gothic carries non-numeric refs (MARK Incipit.0). **The packet's example verse
John 1:1 is NOT five-way alignable** (absent from gothic-nt and marianus in
the treebanks) — the shipped demo verse is **MARK 2.3** (present in all five,
and a Mark verse as the OE-Mark rider requires; MARK 1.1 renders 4-of-5,
Armenian honestly "not attested"). Design: registry
(config/alignments.yml, loud-fail loader Nabu::AlignmentRegistry) + derived
`alignment_refs` table in fulltext.sqlite3 (P7-5 passage_lemmas pattern — one
row per work/normalized-ref/passage, built by Indexer.rebuild! from stored
annotations, both call sites) — NOT materialized pairs (O(witnesses²), stale
on the sixth witness); NO catalog migration. Refs fold both sides
(upcase/whitespace/':'→'.'; per-witness books: alias map). Query surface: new
`nabu align REF [--work]` (+ passage-urn pivot) — Parallel stays the separate
CTS-suffix mechanism. MCP: fifth tool nabu_align (license labels on every
sentence row, restricted witnesses withheld bodily). Licenses resolve at query
time (override ∘ source), never stored in the index. OE Mark = uncomment one
prepared registry line (identical proiel-citation extractor); biblical trio =
entries + at most one new named extractor; GRETIL commentary = a new work.
Demo (scratch parse-only store, live db untouched): `nabu align MARK 2.3` →
5/5 witnesses incl. the Armenian sentence honestly labeled "[covers MARK 2.3,
MARK 2.4]"; survived a real `nabu rebuild` of the scratch store byte-identically.

## P11-4 · Dictionary shelf: LSJ + Lewis & Short  [tier: fable] [status: done] [deps: —]
improvements.md §1.3. Ingest the two canonical classical lexica (Perseus
TEI editions, CC BY-SA — verify at fixture time): LSJ (Greek) and Lewis &
Short (Latin). NOT passages — a new dictionaries surface (own table(s)):
entries keyed by folded lemma, senses as structured text. Two capabilities:
(1) `nabu define <lemma> [--lang]` + MCP nabu_define — lemma search
integration (a lemma hit can carry its dictionary gloss); (2) citation
resolution: dictionary entries cite loci (Il. 1.34, Cic. Off. 1.1) — parse
citations into urns where the work exists in-catalog (resolvable→clickable;
unresolvable kept as text). Design note first: dictionary data is derived
from canonical TEI (fetch via git like perseus? verify upstream repo) and
must be rebuild-replayable. Fixture plan (owner approves before network):
2-3 entry slices per lexicon. Acceptance: define works for a Greek and a
Latin lemma end-to-end incl. MCP; ≥1 citation resolves to an in-catalog
urn; suite+lint green; worklog line.

### Fixture plan (P11-4 Phase A, 2026-07-09 — OWNER-APPROVED 2026-07-09, "Approved as-is")

UPSTREAM (verified via gh api + ranged raw reads, no bulk fetch):
**github.com/PerseusDL/lexica**, branch master, HEAD pinned
`b5e707bdda2d6c8e0bb6c29657454996b4fb04d7` (2026-05-05) — one git repo,
~160 MB, still maintained. Layout `CTS_XML_TEI/perseus/pdllex/{grc/lsj,
lat/ls}/`. LSJ = 27 letter-split TEI files (`grc.lsj.perseus-eng1..27.xml`;
eng1=alpha 43 MB carries the book's frontmatter prefaces, eng6=digamma 15 KB
read whole as the structure exemplar, eng12=lambda 6.7 MB, eng13=mu 12.3 MB
— letters verified by `div0/@n`). L&S = `lat.ls.perseus-eng1.xml` (betacode
Greek, per-dir README: "for archival purposes only") and
`lat.ls.perseus-eng2.xml` ("Greek converted to Unicode (use this for
edits)") — eng2 is ours, 77 MB, all letters as `div0` in one file. A third
Latin lexicon dir exists (`lat/viaf2845558`) — out of scope.

LICENSE (verbatim): GitHub license detection: CC-BY-SA-4.0; repo `license.md`
is the full BY-SA 4.0 legalcode; repo README: "Unless otherwise indicated,
all contents of this repository are licensed under a Creative Commons
Attribution-ShareAlike 4.0 International License. You must offer Perseus any
modifications you make." Both per-lexicon READMEs: "This text may be freely
distributed under a CC BY-SA 4.0 license, subject to the following
restrictions: You credit Perseus, as follows, whenever you use the document:
'Text provided under a CC BY-SA license by Perseus Digital Library,
http://www.perseus.tufts.edu, with funding from The National Endowment for
the Humanities. Data accessed from https://github.com/PerseusDL/lexica/
[date of access].'" L&S eng2 additionally carries an in-file
`<availability>`: "Available under a Creative Commons Attribution-ShareAlike
4.0 International License." → license_class `attribution`, same as the
perseus siblings; MCP-safe.

TEI SHAPE (inspected in eng6 whole + eng1/eng12/eng13/ls-eng2 slices): TEI P4
(`<TEI.2>` DOCTYPE + Perseus PersDict DTD — the P9-2 P4 experience applies),
UTF-8. Body = `div0[@type="alphabetic letter"]` → `<entryFree id key type>`;
inside: `orth`, `sense[@n @level]` (nested levels), `tr` glosses, `etym`,
`gramGrp`, `cit`/`quote`, `xr`/`ref`. LSJ Greek (keys, orth, quotes) is
BETACODE (`key="mh=nis"`, long/short marks already stripped from keys
upstream) → the adapter needs a small betacode→Unicode decoder (no gem;
table-driven, tested). L&S keys are plain Latin with homograph digits
(`a2`, `volo1`), orth carries macrons/breves (`ăb`); its Greek is Unicode.
CITATIONS: `<bibl n="urn:cts:greekLit:tlg0012.tlg001.perseus-grc1:1:1">`
with `<author>`/`<biblScope>` children — the 2014 revision "replaced most
abo ids or abbreviations in bibl tags with cts urns". URNs come work-level
(`tlg0291.tlg001:23:6`), edition-level (`phi0474.phi055.perseus-lat1:1:2:4`
— editions that may differ from ours: LSJ cites perseus-grc1, we hold
grc2 → resolve on the WORK prefix, re-anchor to the in-catalog edition),
and bare work (`phi1236.phi001`); many bibls honestly carry NO urn
(inscriptions, AP, fragments) and some inherited urns are contextually
wrong (an "ib."-expansion gave a Corinna quote a Sappho urn) → best-effort
resolution with an honest miss-rate, unresolved stays text. Known miss:
L&S cites Livy as `phi0914.phi001` (unified AUC), Perseus canonical splits
per book (`phi0914.phi0011`) — stays unresolved, documented.

FIXTURE FILES (Phase B: ranged raw-file fetches around the verified byte
offsets + full teiHeaders — a few MB total, NOT the 96 MB of full files;
trimmed locally into structurally intact files, entries byte-identical,
trims documented in the fixture README per house rules; pin sha b5e707b):

1. `test/fixtures/lexica/CTS_XML_TEI/perseus/pdllex/grc/lsj/grc.lsj.perseus-eng13.xml`
   (~35 KB trim of the 12.3 MB mu file): teiHeader whole + `div0 n="*m"` +
   **μῆνις** (`key="mh=nis"`, id n67485 — VERIFIED: cites Il. 1.1 as
   `n="urn:cts:greekLit:tlg0012.tlg001.perseus-grc1:1:1"` → resolves against
   the fixture Iliad tlg0012.tlg001.perseus-grc2:1.1 AND the live catalog;
   plus unresolvable AP/Alcaeus bibls in the same entry) + 1–2 adjacent
   small μην- entries (e.g. `mhni/w`) for shape variety.
2. `.../grc/lsj/grc.lsj.perseus-eng12.xml` (~80–120 KB trim of the 6.7 MB
   lambda file): teiHeader whole + `div0 n="*l"` + **λόγος** (`key="lo/gos"`
   — the flagship polysemous entry, pages long: the MCP-bounds stress case
   and the improvements-§1.3 demo lemma) + one small lambda entry.
3. `.../lat/ls/lat.ls.perseus-eng2.xml` (~60–90 KB trim of the 77 MB file):
   teiHeader whole (incl. the `<availability>` license statement) +
   `div0 n="A"` with **Aaron** (id n3, tiny; cites the Vulgate via a
   greekLit urn — the cross-namespace edge) and **a2** (2-line homograph) +
   `div0 n="O"` with **officium** (id n32391 — VERIFIED: cites Cic. Off. as
   `n="urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4"` and `:1:9:28`;
   De Officiis perseus-lat1 is IN the live catalog, and `officium` is a
   lemma of the PROIEL cic-off fixture → the lemma-search gloss-integration
   test anchor) + `div0 n="V"` with **virtus** (define demo candidate —
   verify citations at carve time; fallback: any V entry citing an
   in-catalog Cicero/Vergil work).
4. `test/fixtures/lexica/README.md` — retrieval date, exact raw URLs, sha
   pin, license quotes above, trim documentation.

Canonical for real syncs = owner-fired `nabu sync lexica` git-clones the
whole repo under `canonical/lexica/` via GitFetch (attic-protected,
sync_policy manual). Fixtures are for the suite only, as ever.

### Findings (P11-4, 2026-07-09 — shipped; architecture §11 is the design record)

Fixtures fetched exactly per the approved plan (ranged reads at pinned
b5e707b, byte-identical entries; one substitution: the mu neighbor entry is
μηνίσκος, the actual file-order successor of μῆνις, standing in for the
plan's "e.g. μηνίω"; the λόγος trim ran 310 KB vs the 80–120 KB estimate —
the entry alone is ~300 KB and was kept whole per plan). DESIGN (defended
in §11): dictionaries ARE registry sources with a declared
`Adapter.content_kind` (:dictionary → Store::DictionaryLoader; SyncRunner +
Rebuild route in exactly two places) — a parallel mechanism would
re-implement retention/breakers/ledger/probes; entries live in
catalog.sqlite3 via migration 006 (Loader-grade idempotency/revision/
withdraw semantics, provenance + durable ledger under
urn:nabu:dict:<slug>:<entry_id> — NOT fulltext.sqlite3, whose tables are
disposable derived-of-derived). Betacode decoded at the boundary
(Nabu::Betacode, no gem); headwords key FOLDED per conventions §9 from the
decoded @key, which is what makes lemma-search gloss integration free
(`search --lemma officium` → "a service", one batched lookup, dictionary
language must match). CITATION REALITY: bibl/@n CTS urns are work-level,
edition-level (frequently an edition we don't hold — LSJ anchors at
perseus-grc1, catalog holds grc2 → resolve on the WORK prefix), bare-work,
non-CTS, or malformed; resolution is query-time (nothing stale stored),
original-language-preferred, and falls back once on 3+-part citations to
(first, last) — the classical chapter/section double citation, discovered
live: Perseus's De Officiis cites book.section (1.4) where L&S cites
"1, 2, 4"; the fallback resolves to the verbatim quoted passage (eyeballed:
"Nulla enim vitae pars … vacare officio potest"). Known honest miss: L&S
cites Livy as unified phi0914.phi001 vs Perseus's per-book split. Demo
(scratch store, live db untouched): define μῆνις → wrath + Il. 1.1 →
…perseus-grc2:1.1; define officium/virtus → Cic. Off. 1,2,4 → :1.4,
1,9,28 → :1.28, 1,15,46 → :1.46; rebuild-safety pinned (entries+citations
byte-identical across two rebuilds). MCP nabu_define = sixth tool (6 KB
body cap, resolved-first citations, restricted shelves withheld). Third
dictionary (Bosworth-Toller, CC BY 4.0 CSV): own adapter, same
language-agnostic tables, slug bosworth-toller/lang ang, citations empty
until an OE crosswalk — §11 note written. `lexica` registered
enabled: false; owner fires the ~160 MB first clone.

## P11-5 · Biblical trio  [tier: opus] [status: done] [deps: P11-3 design]
improvements.md §2.1: Vulgate (full, not just NT — PROIEL latin-nt is NT
only), LXX (Septuagint, Rahlfs where openly licensed — verify; CCAT/other
open editions), SBLGNT (SBL Greek New Testament, free license with
attribution). Scout+fixture-plan FIRST inside the packet (owner approves
fixture plan before network, standing rule); adapters likely reuse existing
parser families (TEI/plain structured). These feed the P11-3 hub as
additional versions (registry entries). Acceptance: three sources READY
(enabled:false, owner-fired syncs), hub registry entries prepared;
suite+lint green; worklog line.

### Fixture plan (P11-5 Phase A, 2026-07-09 — OWNER-APPROVED 2026-07-09, "Approved as is")

SCOUTED (page-level reads + gh metadata only, no bulk fetch). The headline
deviation from the packet framing, stated up front: **the trio is TWO new
sources + one registry-only witness.** The LXX's best open edition is
ALREADY IN THE CATALOG — First1KGreek tlg0527 is Swete's Septuaginta (57
grc book-documents + ~40 perseus-eng translations, synced, verse-grain
CTS passage urns `…tlg0527.tlg001.1st1K-grc1:1.2`; census: 29,170/29,242
passages are chapter.verse, the 72 flat refs are all Epistula Jeremiae's
single-chapter verse numbers). The openly-licensed standalone LXX repo
(nathans/lxx-swete, CC BY-SA 4.0) is itself *derived from* First1KGreek
tlg0527 per its own README — ingesting it would duplicate the same
edition. So: LXX = registry entries + the new extractor, zero fetch,
zero adapter.

RAHLFS IS BLOCKED, honestly: the 1935 text is PD by age, but every
machine-readable Rahlfs derives from the CATSS/CCAT morphological
database, whose user declaration (ccat.sas.upenn.edu …
/lxxmorph/0-user-declaration.txt) requires verbatim "Not to use or make
available these materials for commercial purposes without first obtaining
the written consent of the owners/encoders" and "To control access to
these materials and require any other party to whom the recipient
supplies any portion of this material to observe these conditions" — a
registration-gated no-uncontrolled-redistribution term, below every
acceptable class. eliranwong/LXX-Rahlfs-1935 relabels this CC-BY-NC-SA in
README prose but ships NO license file and itself concedes "readers have
to agree sending CCAT user declaration"; CenterBLC/LXX's MIT covers only
its Text-Fabric conversion (@Editors=CCAT headers). Rahlfs-Hanhart 2006
is (c) Deutsche Bibelgesellschaft. STEPBible (CC BY 4.0) ships no Greek
OT as of HEAD 2026-06-09 (TAGNT + Hebrew TAHOT only; verified in-tree).
Swete 1909 (PD text, CC BY-SA 4.0 digital edition) is the open LXX, and
we hold it.

UPSTREAM 1 — VULGATE (full bible, new source `vulgate`):
**github.com/seven1m/open-bibles**, branch master, HEAD pinned
`8c31c380a9f7af19fbe04e8eaaa6fa74601083d7` (2026-06-05), ~76 MB
collection of PD/libre bibles, one file per translation. Ours:
`lat-clementine.usfx.xml` (4,652,377 B, blob c0e65106…) — the Tweedale
Clementine Vulgate Project text via eBible.org, Sixto-Clementine 1592
(NOT the DBG-copyrighted Stuttgart/Weber-Gryson). FULL bible verified:
book-id sweep runs GEN … MAL, deuterocanon (1MA 2MA …), MAT MRK … REV.
LICENSE (verbatim): repo README translation table row
"| lat-clementine.usfx.xml | Latin | USFX | | Clementine Latin Vulgate |
Public Domain |"; eBible.org details page for this edition: "Public
Domain"; eBible.org copyright page: "No person, company, or organization
may claim any kind of copyright or restriction on this version of the
Bible... even if they make changes." Caveat disclosed: open-bibles has no
repo-wide LICENSE file (per-file assertion in README) — the PD chain is
README row + eBible.org + 1592 text age → license_class `open`.
FORMAT: USFX milestone XML (NOT TEI — new small parser family
`UsfxParser`, streaming Reader): `<book id="MRK"><h>Marcus</h>
<c id="1"/><v id="1"/>Initium Evangelii Jesu Christi, Filii Dei.<ve/>`.
CITATION: OSIS/Paratext 3-letter book codes + numeric c/v milestones →
native book.chapter.verse. Verified verbatim in-file: MRK 1:1 "Initium
Evangelii…", MRK 2:3 "Et venerunt ad eum ferentes paralyticum, qui a
quatuor portabatur.", JHN 1:1 "In principio erat Verbum…". Adapter mints
one document per book (urn:nabu:vulgate:<osis-code-lc>, e.g.
urn:nabu:vulgate:mrk), passages per verse (<doc>:<ch>.<v>), language lat.
First real sync = owner-fired GitFetch clone of open-bibles (~76 MB,
attic-protected; discovery filtered to the one file), sync_policy manual.

UPSTREAM 2 — SBLGNT (new source `sblgnt`):
**github.com/Faithlife/SBLGNT** (LogosBible/SBLGNT redirects here),
branch master, HEAD pinned `c4d241a9c1c479a55b989ba35a4976c1d0b8052c`
(2025-01-19), ~2.3 MB. The historically restrictive SBLGNT EULA is
SUPERSEDED: sblgnt.com/license itself now serves CC BY 4.0.
LICENSE (verbatim): GitHub license detection CC-BY-4.0 (file LICENSE =
full legalcode); README: "The SBLGNT is licensed under a Creative
Commons Attribution 4.0 International License. Copyright 2010 by the
Society of Biblical Literature and Logos Bible Software." Redistribution
of fixture slices is explicit legalcode §2(a)(1): "reproduce and Share
the Licensed Material, in whole or in part" → license_class
`attribution`, MCP-safe. NB the morphgnt/sblgnt sibling's morphology
layer is CC-BY-SA-3.0 copyleft and its README still points at the old
EULA — we take the clean Faithlife plain text, no morphology.
FORMAT: `data/sblgnt/text/*.txt`, 27 book files, verse-per-line TSV
("Mark 1:1<TAB>Ἀρχὴ τοῦ εὐαγγελίου Ἰησοῦ ⸀χριστοῦ." after a book-title
first line; ⸀⸂⸃ apparatus sigla are upstream text and stay — canonical
means canonical). New trivial parser family (verse-per-line TSV; the
word-level custom XML variant and the sblgntapp apparatus are skipped).
CITATION: explicit "Book C:V" per line; book tokens (Matt, Mark, 1Cor,
Phlm…) fold to the PROIEL nt vocabulary (verified against the live
alignment index: MATT MARK … PHILEM REV) — adapter mints one document
per book file (urn:nabu:sblgnt:<stem-lc>, e.g. urn:nabu:sblgnt:mark),
passages per verse (<doc>:<ch>.<v>), language grc. First real sync =
owner-fired GitFetch clone (~2.3 MB), sync_policy manual.

HUB WIRING (architecture §10 pays out as forecast): ONE new named
extractor `cts-verse` — ref = the witness's registry book token + " " +
the passage-urn tail after the document urn (`…tlg001.1st1K-grc1:1.2` →
"GEN 1.2") — serving all three witnesses. It requires one registry
extension: a witness may span MULTIPLE documents via a `documents:`
map (work-vocabulary book token → document urn; the existing single
`document:` form stays for proiel-citation witnesses — nt entries
unchanged). Touches: AlignmentRegistry (schema + validation),
AlignmentIndexer (per-document iteration + the new extractor),
Query::Align (multi-doc witness header: label as title, language/license
from the witness's live docs, not_synced only when none are live).
Registry entries (LIVE, not commented — registering before sync renders
"not synced" honestly, the registry's documented day-one state):
`nt` work gains sblgnt (27-doc map) + vulgate-NT (27-doc map, keys MARK:
urn:nabu:vulgate:mrk …); NEW `ot` work: lxx-swete (57-doc map onto
tlg0527, keys = OSIS-style tokens, double-recension books get distinct
tokens e.g. DAN = Theodotion / DAN-OG = translatio Graeca; exact maps
generated from catalog titles at implementation) + vulgate-OT. LXX↔
Clementine Psalm numbering both follow the Greek tradition — the
versification-swamp caveat (§10) stays scoped out, and the ot registrar
(this packet) owns that claim per the §10 contract.

FIXTURE FILES (Phase B: ranged raw fetches at the pinned shas, trimmed
locally into structurally intact files, entries byte-identical, trims
documented in per-dir READMEs with the license quotes above):

1. `test/fixtures/vulgate/lat-clementine.usfx.xml` (~25–40 KB trim of
   4.65 MB, pin 8c31c38): usfx root + `<book id="GEN">` ch. 1 whole +
   `<book id="MRK">` chs. 1–2 + `<book id="JHN">` ch. 1:1–18 — OT proof,
   the MARK 2.3 flagship anchor, and the John prologue.
   raw.githubusercontent.com/seven1m/open-bibles/8c31c38…/lat-clementine.usfx.xml
2. `test/fixtures/sblgnt/data/sblgnt/text/Mark.txt` (~4 KB trim, pin
   c4d241a: title line + Mark 1:1–2:12), `…/3John.txt` (WHOLE book,
   2,917 B — complete-book round-trip at negligible size), `…/John.txt`
   (~2 KB trim: John 1:1–18).
   raw.githubusercontent.com/Faithlife/SBLGNT/c4d241a…/data/sblgnt/text/<Book>.txt
3. `test/fixtures/first1k/greekLit/data/tlg0527/tlg001/tlg0527.tlg001.1st1K-grc1.xml`
   (~15–30 KB trim: teiHeader whole + Genesis ch. 1) + the two
   `__cts__.xml` metadata stubs — the LXX witness exercised end-to-end
   from a real fixture (epidoc family, existing adapter; first1k tests'
   pinned URN/title lists updated for the added doc). Upstream:
   raw.githubusercontent.com/OpenGreekAndLatin/First1KGreek (HEAD pinned
   at carve time; license already on file: CC BY-SA 4.0, repo license.md).
4. `test/fixtures/{vulgate,sblgnt}/README.md` + first1k README note —
   retrieval dates, exact URLs, sha pins, license quotes, trim docs.

Owner-fired first syncs after merge: `nabu sync vulgate` (~76 MB clone),
`nabu sync sblgnt` (~2.3 MB clone); LXX needs none (already synced —
`nabu rebuild`/next sync reindexes alignment_refs from the new registry).
Demo target from fixtures (scratch store, live db untouched):
`nabu align "MARK 2.3"` renders sblgnt + vulgate + the PROIEL five;
`nabu align "GEN 1.1" --work ot` renders Swete grc ↔ Clementine lat.

### Findings (P11-5, 2026-07-09 — shipped; architecture §10 updated)

Fixtures fetched exactly per the approved plan (ranged reads at the pinned
shas; slices byte-identical; first1k tlg0527 pinned at fresh HEAD 4c9c843
as the plan specified "pinned at carve time"). SHIPPED: two new sources —
`vulgate` (new UsfxParser family: streaming milestone XML, one document
per book from the one whole-bible file, urn:nabu:vulgate:<osis-lc>:<ch>.<v>)
and `sblgnt` (new SblgntParser family: verse-per-line TSV, per-book docs,
Greek first-line titles; apparatus sigla kept verbatim) — both
enabled:false, sync_policy manual, conformance-green, fetch = shared
GitFetch path. HUB: the forecast "one new extractor" landed as `cts-verse`
(registry book token + passage-urn tail) plus the registry extension it
needs — a witness may span per-book documents (`documents:` map;
AlignmentRegistry two witness forms with strict cross-validation,
AlignmentIndexer per-document iteration, Query::Align multi-doc rendering:
hit book heads the column, misses show the label alone, not_synced only
when NO document is live). Registry: nt + sblgnt (27-book map) +
vulgate-NT (27 codes, all scout-verified); NEW ot work = LXX-Swete
(55-book map, catalog-verified urns incl. grc2 slugs for SIR/ISA,
Theodotion-as-plain-token for DAN/SUS/BEL with -OG variants, 2ES = Esdras
B; tlg030 Ecclesiastes has no grc upstream — honest gap) + vulgate-OT
(ONLY the 9 scout-verified codes; rest config-only after first sync).
DEMO (fixture scratch store, live db untouched): MARK 2.3/MARK 1.1/JOHN
1.1 render sblgnt grc ↔ vulgate lat with the PROIEL five honestly "not
synced"; GEN 1.1 renders Swete ↔ Clementine 2-of-2. LIVE-witness demo
(live catalog opened READ-ONLY, index built into scratch memory — no live
file touched): 68,896 refs; MARK 2.3 = 5-of-7 (trio pending owner syncs);
GEN 1.1, PSA 22.1 (Κύριος ποιμαίνει με — the Greek-numbering claim
proven), JON 2.1 attest from the live LXX. Deviations, all argued in the
plan: trio = 2 sources + registry-only LXX (Rahlfs BLOCKED on the CATSS
declaration — 02-sources #44 records the verbatim terms; Swete already
in-catalog, and nathans/lxx-swete derives FROM tlg0527); vulgate-OT
registry deliberately partial (guessed codes would dangle silently).
REVIEW FIX (same commit): the second work made every bare `align REF`
error "pick one with --work" — work resolution now auto-resolves a bare
ref through the index (unique attesting work → picked, for citations AND
passage-urn pivots; several → ambiguity naming ONLY the attesters; none
→ honest not-found with the --work hint; explicit --work keeps
precedence; MCP inherits via Query::Align). Cosmetic: a not-synced
multi-book witness cites the ref's OWN book urn ("JOHN 1.1" → …:john),
and when the map lacks the ref's book entirely it cites nothing — the
CLI phrases the miss neutrally. Verified bare on live data (read-only):
`align MARK 2.3` → nt 5-of-7, `align GEN 1.1` → ot with Swete attesting.
Suite 1206/15,303 green, lint clean.

## P11-6 · ORACC project expansion  [tier: opus] [status: done] [deps: —]
Config-only rider: extend Oracc::PROJECTS with saao-saa01 (Sargon II
letters), rinap-rinap1 (Tiglath-pileser III), dcclt (lexical lists) — all
CC0-verified in P9-5a scouting; adapter reads license per-project anyway.
Fixture: NONE needed if the parser family covers them (it should — verify
by parsing a few texts from the owner-fired sync at review; if any new cdl
node type appears, STOP and report for a follow-up packet instead of
hacking). Registry scope comment updated. Owner-fired: bin/nabu sync oracc
after merge pulls the new projects. Acceptance: suite+lint green (no new
fixtures = no new tests beyond PROJECTS list pin); 02-sources scope updated;
worklog line.

## P11-gate · Phase 11 gate  [tier: orchestrator] [status: done 2026-07-10] [deps: P11-1..6]
Gate decision: stretch riders (morph facets §1.6, vocab profiling §1.7) NOT
taken — the phase ran full (6 packets + 2 review fixes); they stay in the
improvements register for a later phase.
Full-diff review, library.md refresh (per §9: new capabilities sections for
alignment + dictionaries; OE survey linked), README truthfulness, PR,
sticky alarm LAST. Stretch riders (morph facets §1.6, vocab profiling §1.7)
only if the phase ran light — decide at gate, don't cram.

## P11-7 · Silent-ingestion defects + skip visibility  [tier: opus] [status: done] [deps: P11-4, P11-6]
Defect packet (census-first: orchestrator's 2026-07-10 disk-vs-catalog audit
across ALL 12 sources after the owner-fired oracc/lexica/vulgate/sblgnt
syncs; papyri/perseus×2/first1k/proiel/torot/ud/vulgate/sblgnt verified
clean to the file). Six fixes:

1. **ORACC nested-root (the headline)** — subproject zips unpack with a
   nested root: canonical/oracc/saao-saa01/saa01/corpusjson/, but discover
   looks only at <project-dir>/corpusjson → saao-saa01 and rinap-rinap1
   silently ingested 0 of their 361 texts while the sync reported
   "succeeded (+4675)". Fix discover to find corpusjson at either depth
   (or normalize at unpack); AND make it loud: a registered project whose
   tree exists but yields zero refs is an error-grade sync note, never
   silence. After the fix the owner re-fires sync oracc.
2. **Verify broken on dictionary sources** — Verify#reparse calls
   document.urn on Nabu::DictionaryDocument (no such method): P11-4 routed
   sync+rebuild via Adapter.content_kind but missed Verify, and the crash
   at lexica aborts the ENTIRE verify run (sources after it unverified).
   Teach Verify content_kind :dictionary (reparse dictionary entries by
   their own identity/hash semantics per DictionaryLoader) — or, minimum
   acceptable, cleanly skip dictionary sources with an honest per-source
   "skipped (dictionary)" line; prefer real verification. Regression test:
   verify over a store containing BOTH kinds completes and reports both.
3. **dcclt no-content shape (112 files)** — object/surface skeleton with
   only nonx d-nodes, zero transcribed lines: these are catalog-only
   cousins of the 0-byte case P10-1 skips honestly. Treat identically:
   skip at discover, count in the sync note, never quarantine.
4. **dcclt label-less line-start (58 files)** — e.g. P010104: ~300 labeled
   lines and ONE line-start with no label/n (upstream data gap; its parent
   sentence c-node carries the label, "r xi' 10'" in the sample). Fix: fall
   back to the enclosing sentence's label; if that too is absent, skip THAT
   LINE honestly (annotation note) — never quarantine the document. Two
   fixture slices from canonical/oracc/dcclt (real, trimmed; no network).
5. **LSJ stray editions (2 quarantines)** — grc.lsj.perseus-eng1.xml and
   eng9 are alternate single-file editions the lexica discover sweeps in
   alongside the 27 letter-split files; exclude them from discovery by
   rule (not by name-list if a pattern exists — inspect the repo layout in
   canonical/lexica), with a test.
6. **GRETIL silent strays (2 files)** — sa_vijJAnezvara-mitAkSarA (1.8 MB,
   the Mitākṣarā!) and sa_haribhadrasUri-zAstravArttAsamuccaya: peek_header
   → nil (no <text xml:lang> in the expected shape) and discovery drops
   them INVISIBLY. Inspect both files; if ingestible with a small header
   fallback (e.g. lang from teiHeader or filename sa_ prefix), recover
   them (fixture slice, frozen-urn census over gretil per the standing
   guarantee); if genuinely not editions, classify them loudly.
7. **Skip visibility (the systemic fix)** — sync output + run notes gain
   per-source discovery accounting: files matching the content pattern
   that yield no ref are counted and classed (selected / skipped-by-rule /
   unrecognized), with unrecognized ≥1 rendered prominently. Keep it cheap
   (discover already walks the tree); wire through FetchReport/run notes;
   status/health untouched. Design the counting at the Adapter seam so all
   families inherit it.

FROZEN-URN GUARD: fixes touch discovery/skip paths only; all currently
loaded docs re-parse byte-identical (targeted two-parse censuses for oracc
+ gretil; =N skipped on parse-only syncs as the loader-level proof).
Acceptance: suite+lint green; parse-only oracc sync quarantines 170 → ~0
with honest catalog-only counts (real saao/rinap ingestion is owner-fired
post-merge); verify completes over the full live catalog (read-only run);
gretil strays resolved (recovered or loudly classified); worklog line;
02-sources notes updated.

RESOLUTION (2026-07-10): all seven fixes shipped in one commit; suite+lint
green (+12 tests). Per-fix: (1) ORACC nested-root — `project_dir` resolves
`corpusjson/` at either depth; saao/saa01 + rinap/rinap1 (361 texts) now
ingest; a tree-present-but-no-corpusjson project is a LOUD `unrecognized`
note. (2) Verify — routes `content_kind :dictionary` to entry-level hash
reconciliation; a store with both kinds verifies (the `document.urn`-on-
DictionaryDocument crash that aborted the whole run is gone). (3) dcclt
no-content — new `Nabu::DocumentSkipped` signal; loader counts it
`skipped_by_rule`, never quarantines. (4) dcclt label-less line — falls back
to the enclosing sentence c-node's label, else skips just that line. (5) LSJ
"strays" — **the census was WRONG: eng1/eng9 are the α (largest, ~18950
entries) and θ (~1948) letter files, not alternate editions.** They
quarantined on an empty-citation-suffix bug (`urn:cts:…tlg0088:` → ""
DictionaryCitation). Excluding them would have DELETED α+θ (~20900 entries);
the real fix is `cite_parts` minting `citation: nil` for an empty suffix.
Classified loudly here rather than forcing the packet's exclusion rule. (6)
GRETIL strays — genuine Sanskrit editions (Mitākṣarā 4788 passages,
Śāstravārttā 701) whose `<text>` lacks `@xml:lang`; RECOVERED via
`<body>/@xml:lang` (san-Latn) then filename `sa_` fallback. (7) Skip
visibility — `Adapter#discovery_skips` (DiscoverySkips: selected /
skipped-by-rule / unrecognized) at the seam, wired through the Outcome and a
`discovery:` CLI line, loud notes persisted to `runs.notes`. FROZEN-URN
proof (parse-only, live db): oracc `+407 added ~0 updated =6469 skipped !0
errored` (170 → 0 quarantines), gretil recovers the two strays with ~0
updated. Verify runs clean read-only over the full live catalog.

## P11-8 · Readable aligned scripture: align ranges + English witness  [tier: opus] [status: done] [deps: P11-5, P11-7]
Owner-requested (2026-07-10, after eyeballing `show urn:nabu:vulgate:jon
--parallel` and hitting the CTS-sibling wall). Two halves:

1. **Range/chapter support for `align`** — `align "JON 1.1-1.16"` (verse
   range, same-book) and `align "JON 1"` (whole chapter) render every ref
   in document order, each with its witnesses grouped per the existing
   single-ref layout (compact: ref header + witness lines; suppress
   repeated witness titles). Honest handling of refs where witnesses
   differ in attestation (per-ref counts, the existing not-attested
   rendering). Same grammar in MCP nabu_align (range/chapter args or ref
   string — follow the CLI). Guard: cap rendered refs (e.g. 200) with an
   honest truncation note, mirroring nabu_define's cap style. This also
   pays out for the future OE Mark witness.
2. **English witness (World English Bible or sibling PD English)** — the
   open-bibles repo already vendored for vulgate carries PD English
   bibles; scout IN-REPO (canonical checkout / pinned sha — page-level
   raw reads only if the local clone lacks it), verify the license row
   verbatim (expect Public Domain like lat-clementine), confirm USFX
   format (UsfxParser reuse — zero new parser), pick the edition (WEB
   preferred: modern PD, complete OT+NT+deuterocanon coverage vs KJV
   licensing quirks in the UK — argue briefly). New source `eng-web`
   (or matching slug), enabled:false, owner-fired sync; registry entries:
   nt + ot works gain the eng witness (documents: map per P11-5 pattern).
   FIXTURE GATE: this repo's fixture plan was already owner-approved for
   vulgate (P11-5, same repo, same pinned sha, same PD assertion
   mechanism); trimming 2-3 book slices of the chosen English edition
   from the SAME repo under the SAME approval is in-scope — note it in
   the fixture README; do NOT fetch anything outside the pinned repo.
   Cosmetic rider: the `--parallel` error hint ("is translations: true
   set…") is misleading for non-CTS sources — mention `align` when the
   work has hub registry entries.
Acceptance: `align "JON 1"` renders LXX ↔ Vulgate chapter-wise from
fixtures (and live read-only demo); eng witness READY awaiting owner
sync; suite+lint green; docs (mcp.md nabu_align args, backlog done,
worklog sha —); one commit, not pushed.

## P11-9 · show --random + OT registry completion  [tier: opus] [status: done] [deps: P11-8]
Owner-requested (2026-07-10): `bin/nabu show --random [--source SLUG]
[--count N]` — render N (default 1, cap 20) random passages, optionally
scoped to one source; the standard show layout per hit. Purpose: the
eyeball ritual at every source flip. Honest randomness over PASSAGES
(ORDER BY RANDOM() on the passage set after the usual visibility/license
joins — reuse CatalogJoin; no new query surface). Excluded: withdrawn
(standard rule). MCP: NOT exposed (a conversational surface has no
eyeball ritual; keep the tool list tight). Tests: scoping, count cap,
determinism-free assertions (shape not content), unknown slug error.
Small: CLI + Query touch only.
RIDER (config, now unblocked): complete the alignment registry's
vulgate-OT `documents:` map — P11-5 shipped it deliberately partial
("guessed codes would dangle silently"); the vulgate is now SYNCED, so
every one of its 46 OT book documents is verifiable read-only against
the live catalog (e.g. urn:nabu:vulgate:jon exists but JON is unmapped —
`align "JON 1"` renders vulgate "not attested" wrongly). Add ONLY
catalog-verified codes; keep WEB's OT map conservative (versification
divergence — do NOT expand it beyond what P11-8 shipped). Registry
loader validation must stay green; live read-only demo: `align "JON 2.1"`
renders LXX ↔ Vulgate.
Suite+lint green; docs (README command table row); backlog done;
worklog line (sha —); one commit, not pushed.
OWNER FEEDBACK 2026-07-10 (folded into this packet): `align "JON 1"` live
was unreadable — 16 refs each repeating "vulgate — not attested" and
"WEB — not synced". Fix (range/chapter path only; single-ref byte-unchanged):
a witness with ZERO attestation across the whole rendered range is summarized
ONCE in the header ("not attested in this range: …; not synced: …") and
OMITTED from every per-ref block; partially-attesting witnesses keep the
per-ref honest "— not attested" lines. Mirrored in MCP nabu_align range
results (range-level `absent_witnesses:[{label,reason}]`; per-ref witness
arrays drop the all-absent witnesses); documented in docs/mcp.md.

## P11-10 · status learns dictionary sources + USFX non-verse books  [tier: opus] [status: done] [deps: P11-9]
Defect packet (owner report 2026-07-10: "lexica status weirdly zero docs").
1. **StatusReport content_kind awareness** — lexica renders
   `docs=0 passages=0` because its content is 168,133 dictionary_entries;
   the status renderer never learned `content_kind :dictionary` (same
   missed-surface class as the P11-7 verify fix). Render dictionary
   sources with their true counts (e.g. `entries=168133` in place of the
   docs/passages pair; keep the rest of the row shape — enabled/policy/
   retired/last-run). Check the OTHER status-adjacent surfaces for the
   same gap while there: MCP nabu_status (does it already carry
   dictionary counts? P11-4 said status shows "what is excluded by
   default" — verify), health trends (runs table is fine — kind-agnostic
   counts — but confirm no misleading zero renders), README table row if
   it describes status output.
2. **USFX non-verse books skip rule** — eng-web quarantines FRT (front
   matter) + GLO (glossary): structural non-scripture books with zero
   verses. Quarantine implies damage; these are upstream norms → skip by
   rule (the P11-7 DocumentSkipped signal), counted in the discovery/
   skip accounting. Test with a trimmed FRT-bearing fixture slice (the
   vendored repo is on disk; no network). Vulgate unaffected (its file
   has no FRT/GLO — verify, don't assume).
Acceptance: live read-only render of status shows lexica entries count
(the status command only READS); parse-only eng-web sync shows FRT/GLO
as skipped-by-rule, quarantines 2 → 0, previously-loaded 84 docs
=skipped (frozen); suite+lint green; backlog done; worklog (sha —); one
commit, not pushed.

## Phase 12 — The Old English axis + the public face (branch: phase-12; elaborated 2026-07-10)

Owner shape: "Let's get on the OE axis planning next" + "updating/improving
user-facing docs and making README better structured and presentable. It's a
Github face of an open source project… attract followers, explain the use
cases." Headliners from docs/oe-survey.md (all pre-scouted with verbatim
license quotes); the presentation packet runs LAST so it reflects the phase's
own additions. Branch cut from enable-reference-shelf (PR #13) so the flips
ride along. Sequential dispatch, live-smoke review between packets, real
syncs owner-fired, fixture plans owner-approved before network (standing).

## P12-1 · ISWOC adapter — Old English treebank  [tier: opus] [status: done] [deps: —]
The survey's pick #1: five OE texts (~29,406 gold tokens) in PROIEL XML 2.1
— the exact schema ProielParser already parses. Ælfric's Lives of Saints,
Apollonius of Tyre, Anglo-Saxon Chronicles, Orosius, West-Saxon Gospel of
Mark (verse-cited MARK 1.1 style — the hub's witness #8). License CC
BY-NC-SA 3.0 (verified in README + per-source headers) → nc.
Phase A (scout + fixture plan, page-level reads only): confirm the current
canonical repo (survey: successor syntacticus/syntacticus-treebank-data
carries iswoc/ + proiel/ + torot/ — MUST scope to iswoc/; also verify
whether the original iswoc repo is the better pin), the five files, the ang
language code, the Romance texts to filter out; write the fixture plan
(2 trimmed real slices: one prose text + the wscp Mark for the citation
path) into this packet block. STOP — owner approval gate.
Phase B (post-approval): TOROT-pattern adapter subclass (ang filter,
iswoc/ scoping), registry entry enabled:false, conformance + two-parse,
uncomment the prepared OE Mark line in config/alignments.yml (it renders
"not synced" honestly until the owner syncs — P11-9 header-summary
handles it), 02-sources row → READY, worklog (sha —). Suite+lint green.
One commit, not pushed.

### FIXTURE PLAN — Phase A findings (scouted 2026-07-10, page-level only)
### OWNER-APPROVED 2026-07-10 — "Approved as is, including the third fixture"

**Repo verdict: pin the ORIGINAL `iswoc/iswoc-treebank` (the project's own
repo), NOT the syntacticus successor.** Evidence:
- Original `iswoc/iswoc-treebank`: default branch `master`, **HEAD sha
  `574c81cd9dbf8124290e869bc65078c303a36911`** (2023-05-02T11:55:56Z),
  **`archived: true`** (GitHub read-only → genuinely frozen). Flat repo
  root: one `<text>.xml` + `<text>.conll` per work.
- Successor `syntacticus/syntacticus-treebank-data`: default branch `main`,
  HEAD `525cee4fb40590d7d514376c11acaed1bdd91c15`, last commit
  **2023-04-26** — i.e. it PREDATES the original's final commit. Not
  archived, but carries no newer ISWOC data: the `iswoc/` subtree files are
  byte-*similar* (±a few hundred bytes of export-time/whitespace drift), not
  newer content. It also bundles `proiel/`, `torot/`, `menotec/` subtrees —
  the SAME data the Proiel + Torot adapters already sync from their own
  repos (double-load / urn-collision hazard).
- Decision rationale: this exactly mirrors the established nabu Proiel
  precedent (adapters/proiel.rb header): point `upstream_url` at the frozen
  own-project repo, `sync_policy: frozen`, and note the syntacticus successor
  for a future migration. Pinning the original means the inherited flat-root
  `Proiel#discover` works verbatim — **NO `iswoc/`-subdir scoping code
  needed** (that scoping is only required IF the successor is ever adopted;
  documented in the adapter header as the future-migration note). The `ang`
  language filter alone excludes the Romance texts.

**File enumeration (original repo @ pinned sha, verified via `gh api` tree
+ raw `<source>` header peeks):** 15 texts total, 5 OE + 10 Romance.
- KEEP (5 OE, all `<source language="ang">`): `wscp.xml` (2,735,960 B,
  West-Saxon Gospels) · `æls.xml` (646,405 B, Ælfric's Lives of Saints;
  **non-ASCII id `æls`**) · `apt.xml` (1,138,070 B, Apollonius of Tyre) ·
  `chrona.xml` (1,070,236 B, Anglo-Saxon Chronicles) · `or.xml` (336,862 B,
  Orosius; **two-letter id `or`**).
- EXCLUDE (10 Romance, non-`ang`): `eustace` (fro, Old French) · `cge1`,
  `cge2`, `coutdec-v-8` (por, Portuguese) · `alfonso-xi`, `ce`, `cdeluc`,
  `ee1`, `ge4`, `varones` (spa, Spanish). All carry the same CC BY-NC-SA
  header; excluded purely by the `ang` filter, never by name.

**License (re-verified verbatim):**
- README (github.com/iswoc/iswoc-treebank @ pinned sha): "…is freely
  available under a [Creative Commons Attribution-NonCommercial-ShareAlike
  3.0 License](http://creativecommons.org/licenses/by-nc-sa/3.0/us/)." Cite
  as: "Bech, Kristin and Kristine Eide. 2014. The ISWOC corpus. Department of
  Literature, Area Studies and European Languages, University of Oslo."
- Per-source header (`wscp.xml <source>`): `<license>CC BY-NC-SA 3.0</license>`
  + `<license-url>http://creativecommons.org/licenses/by-nc-sa/3.0/us/</license-url>`
  (æls/or/apt/chrona headers agree). → `license_class: nc` (proiel/torot
  sibling). No LICENSE file in the repo.

**OE Mark citation evidence (`wscp.xml`, verified from raw header peek):**
`<source id="wscp" language="ang"><title>West-Saxon Gospels</title>`; first
`<div><title>Matthew 7</title>` (boundary fragment, tokens `citation-part="MATT 7.27"`),
second `<div><title>Mark 1</title>` with tokens `citation-part="MARK 1.1"` —
the space-separated `BOOK C.V` shape the P11-3 hub's `cts-verse` extractor
already folds (MK→MARK), lifted by ProielParser into `passage.citation` with
zero new plumbing. Confirms the prepared `urn:nabu:proiel:wscp` alignments
line (hub witness #8).

**Fixtures to fetch (STOP — awaiting owner approval; base
`https://raw.githubusercontent.com/iswoc/iswoc-treebank/574c81cd9dbf8124290e869bc65078c303a36911/`):**

| Fixture file | Upstream (full B) | Trim scope | Est. trimmed B |
|---|---|---|---|
| `wscp-mark.xml` | `wscp.xml` (2,735,960) | PROIEL surgery: XML decl + `<proiel>` root + whole `<annotation>` + `<source>` metadata, then leading whole `<div>`s — the `Matthew 7` fragment div + `Mark 1` + `Mark 2` divs kept intact (no div/sentence split) | ~90–130 KB |
| `æls-headN.xml` | `æls.xml` (646,405) | same PROIEL surgery: header + `<annotation>` + `<source>` + leading whole `<div>`s to ≥ ~15 sentences | ~35–55 KB |
| `eustace-head.xml` | `eustace.xml` (469,127) | **exclusion probe** (see note): header + `<annotation>` + `<source language="fro">` + 1 leading whole `<div>` | ~10–15 KB |

Exact trimmed byte counts recorded at fetch time (torot-manifest precedent).

**Deviation flagged for approval — 3 fixtures, not the packet's 2.** The
packet named "2 slices (one prose + wscp Mark)". I recommend adding a THIRD
minimal slice — a trimmed Romance file (`eustace`, `fro`) — because the ONE
thing this adapter adds over the TOROT pattern is the `ang` language filter,
and honestly testing that filter's *exclusion* branch requires a non-`ang`
file physically present in the fixture dir (discover must drop it). Without
it the exclusion path is untested. It stays out of the conformance count
(discover filters it before parse). If the owner prefers to hold to 2
fixtures, the filter's exclusion branch can instead be unit-tested against a
stubbed peek, but a real Romance header is the CLAUDE.md-preferred evidence.

**Phase B design notes (what differs from TOROT):**
- Manifest override only, PLUS a private `document_refs` override:
  `super.select { |ref| ref.metadata["language"] == "ang" }` (few lines;
  survey's "ang filter"). Everything else — peek_source, parse, git fetch —
  inherited from Proiel wholesale (TOROT pattern).
- URN namespace: inherit `urn:nabu:proiel:<source-id>` (TOROT precedent; the
  ids wscp/æls/apt/chrona/or are disjoint from proiel/torot by upstream
  convention). This is REQUIRED — the prepared alignments line hard-codes
  `urn:nabu:proiel:wscp`. Manifest `id: "iswoc"` (source_id on refs), but urn
  stays literal `proiel`, exactly as Torot does.
- Non-ASCII-id check: `æls` mints `urn:nabu:proiel:æls` (æ preserved, NFC) —
  add an explicit URN-mint test.
- `sync_policy: frozen`, `enabled: false` in config/sources.yml.

### Findings (Phase B, shipped 2026-07-10)
- Built exactly per the approved plan: `Iswoc < Proiel`
  (lib/nabu/adapters/iswoc.rb) — manifest override + one private
  `document_refs` override (`ang` select on peeked header metadata). No
  subdir scoping needed (original repo pinned). 19-test battery
  (test/adapters/iswoc_test.rb): full conformance (incl. two-parse URN
  stability), ang-filter exclusion tested against the real `fro` probe
  (guarded non-vacuous: the probe file's presence + header are asserted),
  non-ASCII `urn:nabu:proiel:æls` NFC mint, MARK 1.1 / MATT 7.27
  citation-part lifting, real OE snippets, repo_url identity, registry
  round-trip (frozen + disabled).
- Fixtures in test/fixtures/iswoc/ (upstream sha256s in its README):
  wscp-mark.xml 305,320 B (3 whole divs: Matthew 7 + Mark 1–2, 150
  sentences), æls-head20.xml 86,069 B (20 sentences), eustace-head.xml
  20,899 B (fro exclusion probe, 3 sentences).
- Honest deviations from the plan text: (1) æls/eustace TRUNCATE their
  single kept div after N whole sentences — upstream reality (æls div 1 =
  197/198 sentences ≈ 630 KB; eustace div 1 ≈ 95 KB) made "whole divs" and
  the approved size envelopes mutually impossible; sentences never split,
  strict-parse verified, recorded in the fixture README. (2) wscp actual
  305 KB vs the ~90–130 KB estimate — content scope exactly as approved
  (the named 3 divs); the Phase A byte estimate was simply low.
- Hub witness #8 live: urn:nabu:proiel:wscp uncommented in
  config/alignments.yml; `bin/nabu align "MARK 1.1"` (read-only) renders
  "wscp — not synced (urn:nabu:proiel:wscp is registered but not in the
  catalog)" with the P11-9 header honestly counting "7 of 9 witnesses".
  The shipped-registry pin in test/alignment_registry_test.rb was updated
  to the new 9-witness truth (wscp at index 5) — a planned expectation
  change, not a weakening.
- Registered iswoc `enabled: false` / `sync_policy: frozen`; 02-sources
  row 34 → READY. First real sync remains owner-fired.

## P12-2 · ASPR adapter — the OE poetry corpus  [tier: opus] [status: done] [deps: P12-1]
The survey's pick #2 and the only fully-open OE: the complete six-volume
Krapp & Dobbie Anglo-Saxon Poetic Records as ONE 2.2 MB TEI-P5 file on the
Oxford Text Archive (OTA 3009) — Beowulf, Junius, Vercelli, Exeter Book,
Paris Psalter, Minor Poems; 374 texts / ~30.5k lines. License quoted from
the TEI header itself: CC BY-SA 3.0 → attribution (MCP-shareable).
Phase A: verify the OTA download URL + the in-file license quote still
stand (survey inspected it 2026-07-09; one small fetch to scratch was the
survey's sanctioned sample — re-verify page-level), map the internal
structure (NOT EpiDoc; no l/@n → ordinal line citations per the survey),
decide the fetch path (single HTTP file — extend ZipFetch's plumbing or a
sibling FileFetch with the same Last-Modified + attic contract; argue it),
write the fixture plan (2-3 poem slices incl. a Beowulf passage). STOP —
owner approval gate.
Phase B: small new TEI family (own class + tests first), one document per
poem, urn:nabu:aspr:<poem-slug>:<line-ordinal>, registry enabled:false,
02-sources row, worklog. Suite+lint green. One commit, not pushed.

### Phase A findings (2026-07-10) — fixture plan OWNER-APPROVED 2026-07-10 ("Fine as-is, proceed")

**URL + auth + license re-verified (page-level, no re-download beyond the
survey's one sanctioned sample, which is still in scratch):**
- Download URL (DSpace bitstream, no handle-page scrape needed):
  `https://ota.bodleian.ox.ac.uk/repository/xmlui/bitstream/handle/20.500.12024/3009/3009.xml`
- HEAD → `HTTP/1.1 200 OK`, **no auth** (a JSESSIONID cookie is set but access
  is granted anonymously), `Content-Type: text/xml;charset=utf-8`,
  `Content-Length: 2214065` (matches survey exactly), `Last-Modified: Fri,
  19 Jul 2019 12:07:26 GMT`, `Accept`-less server (Range NOT honoured — the
  server returns the full body, so the "small ranged read" degraded to the
  survey's one full-file sample; retained read-only in scratch, sha256
  `4cf370226d9329e846eceb78fdaa987735113a02ef998980d6070664775ceed5`).
- License, read verbatim from the in-file teiHeader `<availability
  status="free">`: `<licence target="http://creativecommons.org/licenses/by-sa/3.0/">
  Distributed by the University of Oxford under a Creative Commons
  Attribution-ShareAlike 3.0 Unported License</licence>` → **`license_class:
  attribution`** (MCP-surface-safe). Still stands.

**Structure map (precise, from the full file):**
- `<TEI>/<teiHeader>` (3,999 bytes, compact) then `<text><body>` holding
  **349 flat `<div rend="linenumber" xml:id="…">`, NO nesting** (349 `</div>`,
  0 nested). Each div = one poem: `<head>` (title) + optional `<bibl>` (Krapp/
  Dobbie ASPR ref) + a flat run of `<l>` verse lines. 30,550 `<l>` total;
  **0 `<l>` outside a div**.
- Line markup: `<caesura/>` mid-line (30,299), `<unclear>` spans (2,613),
  `<foreign xml:lang="rune">` runic glosses (124), `<gap/>` lacunae (38),
  `<g>` glyphs (73). **No `<l>/@n` anywhere** (survey confirmed) — but the div
  carries `rend="linenumber"` and the per-div `<l>` ordinal **equals the
  canonical printed ASPR line number**: verified Beowulf div = 3,182 `<l>`
  (ASPR Beowulf is 3182 ll.) and Judith = 349 `<l>` (ASPR Judith is 349 ll.).
  So the ordinal citation here is *canonical*, not honest-but-noncanonical the
  way GRETIL prose ordinals are.
- The survey's "374 texts" = `<head>` count; the extra 25 over 349 divs are
  **duplicate `<head>` elements** in single poems (Meters of Boethius A6.10–31,
  Psalm fragments A24.x each repeat their title twice) — NOT multiple poems per
  div. **div == poem, cleanly.** Parser takes the *first* `<head>` as title.

**Citation design — `<poem-slug>` = the div `xml:id` (Cameron number), verbatim:**
- The `xml:id` values are the canonical **Cameron/DOE-Corpus record numbers**
  (A = poetry section): A1 Junius, A2 Vercelli, A3 Exeter, A4 Beowulf+Judith,
  A5/A6 Paris Psalter + Meters, A12 Rune Poem, A32 Cædmon's Hymn, A33 Bede's
  Death Song, A43 Metrical Charms, … up to A-values in the 40s. **All 349 are
  unique** (verified) → urn uniqueness for free.
- **Title-slugs would collide and are rejected:** A43.5 and A43.10 are *both*
  `<head>For Loss of Cattle`; Cædmon's Hymn ships as A32.1 (Northumbrian) +
  A32.2 (West-Saxon) and Bede's Death Song as A33.1/.2/.3 (three dialect
  witnesses) — the survey's "separate texts" point. The stable, collision-free,
  scholar-cited id is the Cameron number, so the frozen mint is
  `urn:nabu:aspr:<xml:id>` (kept verbatim incl. case + dots, the GRETIL
  "literal upstream slug, no re-slugification" rule), title carried in
  metadata. Passage urn = `<doc-urn>:<line-ordinal>` (1-based `<l>` count),
  e.g. **`urn:nabu:aspr:A4.1:1`** = Beowulf line 1 "Hwæt! We Gardena…".

**Fetch path — DECISION: a sibling `Nabu::FileFetch`, NOT extending ZipFetch.**
- Shared contract to honour either way: conditional GET (`If-Modified-Since`
  replayed from a `.file-fetch.json` state file storing Last-Modified + sha256
  + url), sha256 body pin, attic retention with a GitFetch-format manifest, and
  the `doomed_paths` guard hook — so the adapter base's attic rediscovery and
  the mass-deletion breaker work unchanged.
- Why a sibling, not a branch in ZipFetch: ZipFetch is irreducibly zip-shaped —
  `unpack!` shells to `unzip`, `tree_root` picks the single top dir, the staged
  tree is a *directory of many files*, and `doomed = live_relpaths -
  staged_relpaths` is a multi-file set-difference. A single 2.2 MB XML file has
  none of that: the "tree" is one file, the doomed set is essentially always
  empty (a single-file source's only "deletion" is the whole file 404-ing,
  which aborts the fetch — a revised file is an *update*, not an attic-worthy
  deletion, exactly as git adapters don't attic every changed file). Threading
  an `is_zip?` mode through unpack!/tree_root/copy_tree would muddy a clean,
  heavily-documented class and violate "one thing per class / no clever
  dual-purpose code." FileFetch is smaller and single-purpose: GET → sha →
  write file → write state; attic path present for contract symmetry but inert
  in the single-file case. It **reuses `ZipFetch.default_http`** (the
  vendored-cert Faraday) as-is — the cert-hardened connection is genuine shared
  infra, one method reference, not dual-mode logic. (OTA's nginx served fine on
  system certs; reusing the hardened store is belt-and-braces.)
- Health probe: OTA has no git repo and no per-project metadata.json, so
  neither `:git` nor `:http_zip` fits. Phase B adds a minimal HEAD-only
  `remote_probe_strategy` (or reuses the `:http_zip` HEAD target minus the
  metadata GET) pointed at the bitstream URL for Last-Modified drift; license
  drift is a re-fetch concern (license lives in-file). Small, flagged.
- `sync_policy: manual`, `enabled: false` (per packet). Effectively frozen
  upstream (Last-Modified 2019, header normalised 2010) — manual is honest.

**Parser family shape (the Vulgate single-file-many-docs precedent):**
- New `Nabu::Adapters::AsprParser` (own class + tests first). Mirrors
  UsfxParser: `#texts(path)` streams once → inventory `[{id: xml:id, title:
  first <head>}]` for `discover`; `#parse(path, div_id:, urn:, language:
  "ang", title:)` re-streams and extracts the one matching div. Sole Nokogiri
  entry point = `XML::Reader` (house streaming rule; 2.2 MB). One passage per
  `<l>`, ordinal 1-based, `<caesura/>` kept as a space boundary, `<unclear>`/
  `<foreign>` text kept inline (canonical), `<gap/>` → nothing, `<g>` glyph
  kept; NFC at the boundary. Adapter mints `urn:nabu:aspr:<xml:id>`, discover
  re-reads the one file (Vulgate pattern), 349 documents.

**FIXTURE PLAN — `test/fixtures/aspr/3009.xml` (one trimmed valid TEI file,
≈13–14 KB, extracted from the scratch sample; owner may trim the tail):**
- **Extraction method (NOT raw byte ranges — those would split multibyte
  æ/ð/þ and tag boundaries → invalid XML):** a Phase-B selection script reads
  the retained scratch `3009.xml`, emits the teiHeader verbatim + `<text>\n
  <body>`, then for each selected `xml:id` writes the div verbatim (complete
  divs) or head+bibl+first-N-`<l>`+`</div>` (the Beowulf trim), then
  `</body></text></TEI>`. Deterministic; `fixtures/aspr/README.md` records
  retrieval date, URL, source sha256, and the exact div-id + trim list. No new
  network fetch needed — the scratch sample is the real upstream bytes.
- **Core slices (the packet's "2–3 poem slices incl. Beowulf"):**
  1. **A4.1 Beowulf** — head + bibl + `<l>` lines **1–24 contiguous** (ordinals
     genuine), then `</div>`. Demo line `urn:nabu:aspr:A4.1:1` = "Hwæt! We
     Gardena // in geardagum,". Covers `<caesura>` (every line) + `<unclear>`
     (lines 4,6,15,20,21). ≈2 KB.
  2. **A32.1 + A32.2 Cædmon's Hymn** (Northumbrian + West-Saxon, 9 `<l>` each,
     complete) — the dialect-witness-as-separate-document design; distinct
     Cameron ids, near-identical text. ≈1.5 KB.
  3. **A43.5 + A43.10 "For Loss of Cattle"** (16 + 13 `<l>`, complete) — the
     **collision proof**: identical `<head>` text, distinct xml:id → asserts
     `urn:nabu:aspr:A43.5:1` ≠ `urn:nabu:aspr:A43.10:1` where a title-slug
     would clash. ≈2.8 KB.
- **Feature-coverage micro-divs (real complete divs, element regression tests;
  each <1 KB — owner may drop if "2–3 docs" is strict):**
  4. **A3.34.15** (Exeter Riddle, 2 `<l>`) — `<foreign xml:lang="rune">`.
  5. **A3.34.22** (Exeter Riddle, 5 `<l>`) — `<gap/>` lacuna.
  6. **A16** (2 `<l>`) — `<g>` glyph.
- Total ≈11 documents / ≈90 lines / ≈13–14 KB, structurally intact, covering
  every element the parser must handle (`head bibl l caesura unclear foreign
  gap g`), plus the Beowulf demo line and the two collision families.

**STOP — owner approval gate. No fixture written; no Phase B code.**

### Phase B findings (2026-07-10, shipped — one commit, not pushed)

Executed exactly per the approved plan; deviations listed last.

- **Fixture** `test/fixtures/aspr/3009.xml` (12,015 B, well-formed, NFC):
  teiHeader verbatim + 8 of 349 divs in upstream file order — A3.34.15
  (Riddles 75, runes), A3.34.22 (Riddles 82, `<gap/>`), **A4.1 Beowulf
  head+bibl+lines 1–24**, A16 (`<g>` glyphs), A32.1/A32.2 (Cædmon's Hymn
  dialect pair), A43.5/A43.10 (the "For Loss of Cattle" title-collision
  pair) — extracted mechanically by div-id from the retained Phase A scratch
  sample (sha256 recorded in the fixture README + manifest.yml). Fixture
  archaeology finds: A3.34.22 carries a **div-level `<gap/>` BETWEEN
  lines** (must not shift ordinals — regression-tested), and Nokogiri's
  Reader reports whitespace-only text nodes as TYPE_SIGNIFICANT_WHITESPACE
  (dropping them fused sibling runes: "DNLH." — captured now, so
  "D N L H."; the collapse keeps `dom<g>ę</g>…` joins tight).
- **AsprParser** (7th family, the smallest; UsfxParser shape): `#texts`
  inventory / `#parse(path, div_id:, …)` one-poem extraction, sole entry
  point XML::Reader, one passage per `<l>` cited by 1-based ordinal (==
  printed ASPR line number), `<unclear>`/`<foreign>`/`<g>` text kept inline,
  head/bibl never leak, ParseError on absent div / no lines / malformed XML.
- **Nabu::FileFetch** (the argued ZipFetch sibling): conditional GET
  replaying the stored Last-Modified (304 → untouched; wiped tree →
  unconditional), sha256 body pin in `.file-fetch.json`, guard-before-
  mutation, attic with GitFetch-format manifest — the one genuine doomed
  case (a stale differently-named previous download) tested; a changed body
  is an update, never atticked. Reuses `ZipFetch.default_http` by reference.
- **Aspr adapter**: one document per poem div, `urn:nabu:aspr:<Cameron>`
  frozen; fetch via FileFetch wrapped in FetchReport/FetchError; probe rides
  `:http_zip` with `HttpProbeTarget` gaining an optional `state_file`
  member (default `.zip-fetch.json` — ORACC unchanged) and a nil
  `metadata_url` now short-circuiting the license row to honest `unchecked`
  with NO GET issued (the license lives in-file). Registry `aspr`
  `enabled: false`, `sync_policy: manual`.
- **Tests**: 13 parser + 12 FileFetch + 18 adapter (incl. the shared
  conformance suite: two-parse urn stability, NFC, uniqueness) + 2 probe.
  Suite 1338 runs / 18,106 assertions green; rubocop 181 files clean.
- **Deviations from the approved plan, openly:** (1) fixture is ~12.0 KB vs
  the estimated 13–14 KB (estimate was high; content scope exactly as
  approved). (2) FileFetch's attic is NOT inert-for-symmetry as the Phase A
  text sketched — it covers the real FILENAME-migration case (doomed =
  live files other than the target/state/attic), which is stronger and
  contract-true. (3) The probe reuses `:http_zip` (per the plan's "or"
  branch) rather than adding a new strategy symbol — two surgical changes
  in remote_probe.rb, both tested.

## P12-3 · Bosworth-Toller onto the reference shelf  [tier: opus] [status: done] [deps: P12-2]
The OE dictionary (survey: official LINDAT dump, hdl 11234/1-3532,
CC BY 4.0 verbatim, SQL + lemma-keyed CSV id;headword;body). Third
occupant of the P11-4 shelf — architecture §11 already sketches the
plug-in: own CSV adapter, content_kind :dictionary, slug bosworth-toller,
lang ang, betacode off, citations table starts empty (no OE crosswalk
yet — resolution layer needs nothing new).
Phase A: verify the LINDAT record + license + dump format (page-level),
write the fixture plan (a few hundred entry rows trimmed). STOP — owner
approval gate.
Phase B: CSV dictionary adapter (new small family — first non-TEI
dictionary; keep the DictionaryLoader contract), define --lang ang path,
folded-headword keying for OE (ash/thorn/eth folding rule — conventions
§9 addition, argued not assumed), registry enabled:false, 02-sources,
worklog. Suite+lint green. One commit, not pushed.

### Phase A findings (verified 2026-07-10, page-level reads only)

**Record.** LINDAT/CLARIAH-CZ handle `11234/1-3532`, title (dc.title,
verbatim) "Bosworth-Toller's Anglo-Saxon Dictionary online", handle URI
`http://hdl.handle.net/11234/1-3532`, source `https://bosworthtoller.com/`.
The repo migrated to CLARIN-DSpace 7.6.5; the old xmlui handle/bitstream
URLs now 302-redirect to the Angular UI (an HTML shell), so the survey's
`.../xmlui/handle/...` link resolves but no longer serves files directly.
Item uuid `da2f3c19-f5a9-48d2-bb8f-eb84a415f954`.

**License (verbatim, from DSpace REST item metadata).** `dc.rights =
"Creative Commons - Attribution 4.0 International (CC BY 4.0)"`;
`dc.rights.uri = http://creativecommons.org/licenses/by/4.0/`;
`dc.rights.label = PUB`. → `license_class "attribution"`, MCP-surface-safe.
Confirms the survey; the deposit by the site's own maintainer is the
authoritative grant (bosworthtoller.com itself carries no readable license).

**Dump contents/format (verbatim from the deposit's own readme.txt, 769 B).**
Three files in the ORIGINAL bundle:
- `bosworth_entries_export.csv` — 88,387,561 B (~84 MB), MD5
  `7c50c0a47ad2365fa0fddea18a54f11d`. THE lemma-keyed CSV. readme: "Encoding:
  UTF-8 / Data separator: ; / Data enclosed by: \"\" / Contains three
  columns: \"id\";\"headword\";\"body\" … id = the entry id that can be used
  to refer to the entry online via http://bosworthtoller.com/id … body = body
  of the entry tagged in xml".
- `bosworth_backup_sql.sql` — 634,251,167 B (~605 MB) full DB backup. Out of
  scope (the CSV carries the id/headword/body we need).
- `readme.txt` — 769 B, the format spec above.
readme caveat (verbatim): "Data dump version 0.1. The data is still being
processed for accuracy and manually tagged with XML structural tags. … Not
all entries have been checked and/or tagged." → the parser must tolerate
untagged/degenerate bodies.

**CSV reality (verified on the first 8 KB via HTTP Range — page-level, NOT a
bulk fetch).** Header row `"id";"headword";"body"`. RFC-style CSV: every
field quoted (incl. the numeric id and headword), embedded `"` escaped by
DOUBLING (`""000001""`), and the `body` field is **multi-line XML with
literal embedded newlines** — so a real CSV reader is mandatory (Ruby stdlib
`CSV`, `col_sep: ";"`, `quote_char: '"'` handles doubling + multiline
fields; line-splitting would shred entries). Bodies use a **project-specific
(non-TEI) schema**: `<entry id=… vid=… …>`, `<form><orth>/<search>/<sort>`,
`<gramGrp/>`, `<column name="body">`, `<grammar>`, `<page header=… num=…/>`,
milestone empty-element pairs `<b-s/>…<b-e/>` (bold) and `<i-s/>…<i-e/>`
(italic), `<def>`, nested `<sense num="N"><snum>N.</snum>…`, `<references>`,
`<examples><ex><oe>…</oe><trans>…</trans><references>…</references></ex>`,
`<rune>ᚪ</rune>`, `<br/>`. Entity double-encoding is present
(`&amp;#39;`→`'`, `&amp;mdash;`); senses nest raggedly and repeat @num — v0.1
reality the linearizer must tolerate, not assume well-formedness of.
Note: the CSV `id` column ("1" for headword "A") is the readme's stated
back-link id; the XML also carries an internal `id="000001"`/`vid=` — Phase B
spot-checks one CSV id against the live `bosworthtoller.com/<id>` and keys the
URN on the CSV id (`urn:nabu:dict:bosworth-toller:<csv id>`).

**Fetch-path verdict: FileFetch-ready via the DSpace REST content URL.** The
stable, auth-free download is the bitstream `/content` endpoint:
`https://lindat.mff.cuni.cz/repository/server/api/core/bitstreams/3010b742-b2c4-4152-870a-716ce1652e7c/content`
(uuid is per-deposit-stable). HEAD confirms `200`,
`Content-Type: application/octet-stream;charset=UTF-8`,
`Content-Length: 88387561`, **`Last-Modified: Mon, 26 Apr 2021 14:04:23 GMT`**,
`ETag: "7c50c0a47ad2365fa0fddea18a54f11d"`, `Accept-Ranges: bytes` — i.e. the
conditional-GET + sha-pin contract `Nabu::FileFetch` (P12-2) needs, exactly
the ASPR wiring: `remote_probe_strategy :http_zip`, one `HttpProbeTarget`
(zip_url = the content URL, metadata_url nil — license lives in the deposit,
not an endpoint, so the license row reads unchecked), `state_file
FileFetch::STATE_FILE`. Dump is frozen (Last-Modified 2021-04-26, v0.1) →
`sync_policy: manual`. The handle-based xmlui bitstream URL is NOT usable
(serves the Angular shell); the REST `/content` uuid URL is the one to pin.

**OE headword folding rule (argued — conventions §9 addition
`LANGUAGE_FOLDS["ang"]`).** On top of the generic fold (downcase → strip
`\p{Mn}`), apply: **æ→"ae", þ→"th", ð→"th"** (and Æ/Þ/Ð reach these via the
downcase step that runs first). Argument:
1. *Vowel-length marks need no rule.* B-T alphabetizes á/é/í/ó/ú/ý and
   macroned ǣ/ō as their base vowels (length is editorial, not lexical); the
   generic fold already delivers this — precomposed á → NFD → strip U+0301 →
   a; ǣ (U+01E3) → NFD → æ + U+0304 → strip → æ, then the ang rule folds the
   surviving æ. So accents compose correctly with no ang-specific handling.
2. *æ→"ae".* æ is a real OE letter (its own B-T section after A) but not
   ASCII-typeable; "ae" is its standard scholarly transliteration and the
   digraph it historically writes. A user types `nabu define caeg`/`waeter`
   and must reach cæg/wæter.
3. *þ→"th", ð→"th".* B-T interfiles þ and ð as ONE letter (after T), and OE
   scribes used them interchangeably for the same dental fricative; both map
   to the ASCII "th" a user types. Folding both to "th" mirrors B-T's own
   interfiling (one search bucket) — ð→"d" was considered and rejected because
   it would SPLIT the pair B-T unifies. (Wynn ƿ is effectively never in the
   edited headwords/text — editions already print "w" — so no rule; noted so
   the absence is deliberate.)
Both-sides contract: the SAME `LANGUAGE_FOLDS["ang"]` folds ISWOC/ASPR ang
lemmas, so `search --lemma wæter` (or the ASCII `waeter`) carries the B-T
gloss — the LSJ/L&S lemma-gloss bridge, verbatim, for OE. Query-union
pollution (a non-OE query's ang variant, e.g. "þing"→"thing") is the same
bounded tradeoff §9 already accepts for lat v→u and the cuneiform fold, and
is harmless here because æ/þ/ð essentially never occur in the other corpora's
text. No rebuild storm: the rule is added BEFORE any ang corpus is synced
(aspr + iswoc are both `enabled:false`, zero ang rows in the catalog), so the
§9 "changing a rule ⇒ plan a rebuild" caveat is satisfied vacuously. Implement
as a `gsub` lambda (not `tr` — æ→"ae"/þ→"th" are 1→2 expansions;
`Normalize.fold_with_map` already tolerates non-length-preserving folds).

### FIXTURE PLAN

- **Target:** `test/fixtures/bosworth-toller/bosworth_entries_export.csv`
  (mirrors the upstream filename so the adapter's `Dir.glob` finds it the same
  way ASPR finds `3009.xml`) + `test/fixtures/bosworth-toller/README.md`
  (retrieval date, the CC BY 4.0 verbatim quote above, the content-URL + MD5 +
  Last-Modified pin, and the selection table below).
- **Source (Phase B, owner-fired):** the CSV `/content` URL above; verify MD5
  `7c50c0a47ad2365fa0fddea18a54f11d` on the full download before slicing.
- **Selection — a stratified ~300-entry sample (values byte-verbatim; only the
  record SET is trimmed), guaranteeing every folding + parser case:**
  1. The header row + the first ~180 contiguous records (the "A"/"a-" section):
     the flagship multi-sense "A" entry (runes, ragged nested `<sense>`,
     `<examples>`/`<oe>`/`<trans>`, entity double-encoding), accented headwords
     (ác, á-, etc.) exercising length-mark folding, and prefixed a- verbs.
  2. ~40 records whose headword begins **æ/Æ** (æ, æcer, æsc, æfter, ælf,
     æðele — the last also carries ð) — the æ→"ae" fold.
  3. ~40 records whose headword begins **þ/Þ or ð/Ð** (þ, þæt, þing, þeod, ðes,
     ðegn) — the þ/ð→"th" fold and the þ/ð interfiling.
  4. ~20 records covering: any homograph groups seen in the pass (same headword,
     multiple ids — the DictionaryLoader upsert-by-(dict,entry_id) case), the
     shortest/most-degenerate bodies found (v0.1 untagged tolerance), and a
     body with a bare `<references>`/cross-ref stub (nil-gloss honesty).
- **Extraction method (deterministic, exact):** a Ruby stdlib-`CSV` streaming
  script — `CSV.foreach(src, col_sep: ";", quote_char: '"', headers: true)`,
  collect the four strata above (dedupe by id, cap ~300, cap any single body at
  a sane trim only if it blows the size budget — prefer keeping the "A" entry
  whole as the stress case), then re-emit with
  `CSV.generate(col_sep: ";", force_quotes: true)` + the header. Round-tripping
  through the same CSV semantics the adapter uses keeps every field value
  identical while trimming only the record selection; `force_quotes` reproduces
  upstream's quote-all shape. Script lives under the fixture README as the
  documented recipe (not committed as code — one-shot, like the lexica trims).
- **Size budget:** aim < ~600 KB (calibrated to the lexica fixtures' ~380 KB;
  the "A" entry is the one large keep). If over, drop the largest non-essential
  bodies from stratum 1, never the folding-case headwords.

**FIXTURE PLAN — OWNER-APPROVED 2026-07-10** ("Bosworth-Toller fixture
plan approved as is", incl. the ang folding rule æ→ae, þ→th, ð→th).

### Phase B findings (2026-07-10, done)

- **Fixture acquired via Range reads only** (~3.4 MB of the 84 MB CSV:
  bytes 0–1449999, 45600000–46999999, plus small ordering probes — never the
  full file): 270 stratified entries, 497,144 B, every emitted row asserted
  **byte-verbatim** against the raw upstream slices. Two plan adjustments,
  both upstream reality not trim choices: (1) the dump has **no ð-initial
  headwords** (B-T normalizes headwords to þ-; ð appears medially —
  ǽg-hwæðer, þeáh-hwæðere — which is where the ð→th fold is exercised);
  (2) 249/270 bodies have no `<sense>` tag — flat untagged bodies are the
  NORM, so the linearizer treats tagging as optional. Bonus corroboration
  found in the data: the dump's own `<sort>` field folds æðele→`aetþele`,
  þing→`tþing` — B-T itself folds æ→ae and buckets ð/þ identically, the
  strongest possible evidence for the approved rule.
- **Shipped:** `BosworthCsvParser` (8th parser family; stdlib CSV streaming,
  gloss = first `<equiv lang="eng">` else first `<def>` else nil, body
  linearizer skips `<search>/<sort>/<checked>`, breaks lines on
  `<sense>`/`<br>`, second-pass decode of the dump's double-encoded entities,
  NFC; row errors → ParseError) + `BosworthToller` adapter (`content_kind
  :dictionary`, FileFetch fetch of the DSpace `/content` URL, ASPR-style
  :http_zip probe with metadata_url nil, `urn:nabu:dict:bosworth-toller:<csv
  id>` ↔ bosworthtoller.com/<id>) + registry `bosworth-toller`
  enabled:false sync_policy:manual + conventions §9 `ang` fold + CLI/MCP
  `lang` gates widened to ang (Query::Define needed zero changes — it was
  genuinely language-agnostic; the loader/status/verify/rebuild routing
  inherited purely via content_kind, each pinned by a test against the REAL
  adapter class).
- **Gem note:** `csv` added to the Gemfile — the stdlib extraction
  (ruby-core, zero transitive deps) stopped being a default gem in Ruby 3.4
  and this box runs 4.0; the approved plan's "stdlib CSV" is exactly this
  gem.
- **Demo (scratch catalog built from the fixture; live db untouched):**
  `define aethele --lang ang` → æðele [attribution] gloss "noble", sense
  breaks intact; `define thing` → þing "a thing"; `define ae` → the three
  ǽ homographs (life / river / alas!); `status` → entries=270.
- Suite 1370 runs / 19,907 assertions green; rubocop 185 files clean.
  Remaining owner action (P12-gate): fire `bin/nabu sync bosworth-toller`
  (~84 MB single GET), eyeball `define` output, flip enabled.

## P12-4 · The public face: README + user-facing docs  [tier: fable] [status: done] [deps: P12-1..3]
Owner: the README is the GitHub face of an open source project — it needs
to attract followers and explain use cases, not just report status. Runs
LAST so it reflects the OE additions. Scope:
- README restructure: a short hero section (what nabu is, in three
  sentences a stranger understands); a "show me" block early (real
  commands with real output: trilingual align, define, lemma search,
  random tablet); use cases by persona (classicist, indologist,
  assyriologist, digital humanist, AI-tooling builder — MCP angle);
  clear install/quickstart; corpus table (the library.md summary table,
  linked); feature tour; protection story (attic/ledger/backup — the
  "your collection cannot rot" pitch); docs index with one-line
  descriptions; contributing/status/license sections. Badges only if
  honest (CI). NO fabricated numbers — pull live counts at write time
  and date them.
- docs/quickstart.md: zero-to-first-search walkthrough (install, sync a
  small source e.g. sblgnt, search/show/align/define), copy-pasteable.
- Consistency pass over user-facing docs (01-concept, mcp.md intro,
  library.md → linked coherently from README; no stale claims — verify
  numbers against the live catalog read-only).
- The dev-loop/backlog/worklog stay internal (link once under
  "how this is built", nothing more).
Acceptance: README renders well on GitHub (check raw markdown structure,
heading hierarchy, table widths); quickstart executes truthfully on this
box (each command actually run); suite+lint untouched-green; worklog
(sha —). One commit, not pushed.

## P12-gate · Phase 12 gate  [tier: orchestrator] [status: pending] [deps: P12-1..4]
Full-diff review, library.md refresh (OE sections when synced; §10 duty),
PR, owner-fired syncs queue (iswoc, aspr, bosworth-toller), flips on
owner word, sticky alarm LAST.

## Phase 13 — Slavic deepening + cuneiform readability + workbench riders (branch: phase-13; elaborated 2026-07-11)

Owner shape (2026-07-11): "go with B+C but I'm not happy with OCS/Slavic
coverage — can we do more? are there dictionary sources? Is there something
for South Slavic/Slovenian?" So: a second, deeper Slavic survey FIRST (its
findings may append adapter packets to this very phase), then CCMH (survey-I
pick #2), ORACC breadth + ATF translations, and the workbench riders never
taken. Sequential dispatch, fixture gates standing, real syncs owner-fired.

## P13-1 · Slavic survey II: dictionaries + South Slavic/Slovenian  [tier: opus] [status: done] [deps: —]
Scouting only, docs/slavic-survey.md quality bar (that doc covered treebanks
and OCS canon; this one covers what it didn't). Three axes:
(a) SLAVIC DICTIONARY SOURCES for the P11-4 reference shelf: the GORAZD
    project / Old Church Slavonic Digital Hub (gorazd.org, Czech Academy —
    digitized SJS Slovník jazyka staroslověnského, Cejtlin, Miklosich?
    formats, APIs, LICENSE verbatim); Sreznevsky (survey I said scans-only —
    re-verify, any new machine-readable edition?); anything else genuinely
    machine-readable (derksen etymological? out of copyright dictionaries
    with digital editions?). For each: format, license VERBATIM, entry
    count, DictionaryLoader fit (the shelf now has TEI + CSV precedents).
(b) SOUTH SLAVIC / SLOVENIAN: Freising Manuscripts (Brižinski spomeniki,
    ~1000 CE, oldest Slovene/Slavic-Latin-script text — eZISS/NUK TEI
    critical edition, license?); eZISS generally (Slovenian electronic
    critical editions — what's in scope, what license); IMP historical
    Slovenian corpus (license? period coverage); Croatian Church Slavonic
    (Hrvatski crkvenoslavenski corpus, Staroslavenski institut — anything
    downloadable?); Serbian/Bulgarian/Macedonian Church Slavonic digital
    editions beyond the already-surveyed Suprasliensis/CCMH. UD treebanks
    for OLD South Slavic variants (modern hr/sl/sr/bg/mk are OUT of scope —
    ancient-texts library).
(c) REVISIT survey-I blocked items ONLY if their status plausibly changed
    (obdurodon bulk availability; Manuscript.ru grant path — do NOT write
    emails, just verify current state).
Deliverable: docs/slavic-survey-2.md (ranked ingestable picks with effort
sizing, blocked list with unblock paths, explicit "what this adds that
torot/proiel/ccmh don't already hold" dedup column); 02-sources rows;
recommendation whether findings warrant packets IN THIS PHASE (orchestrator
+ owner decide at review); backlog done + findings; worklog (sha —).
Page-level reads + gh metadata only, no bulk fetches, no emails.

### Findings (P13-1, 2026-07-11 — survey delivered, docs/slavic-survey-2.md)

OWNER'S THREE QUESTIONS ANSWERED. (1) More OCS/Slavic: modestly — CCMH
(P13-2) closes the canon; ONE new clean win found: **UD_Old_East_Slavic-
Ruthenian** ("prosta mova" 1380–1650, Polotsk letters/Lithuanian Metrica/
Lokhvitsa book; README metadata verbatim `License: CC BY-SA 4.0`; zero
overlap — third East Slavic branch) → config-only `TREEBANKS` add, the P10-2
recipe, **recommended THIS PHASE** as pick #1. No other open machine-readable
ChSl edition exists in ANY South Slavic recension (Zagreb RCJHR = PDF scans,
no license; SANU Serbian corpus = internal, no release; Sofia histdict =
web-UI + bare ©; DIACU JSON = no LICENSE + mostly re-packaged TOROT).
(2) Dictionaries: **the scholarly OCS lexica are not openly available today.**
GORAZD hub (Prague SJS ~33k entries + Cejtlin + Greek-OCS index; NB Miklosich/
Sreznevsky NOT in it — packet lead corrected) is query-only with NO content
license (the GPL covers its software, not data); **Miklosich BCDH/ELEXIS TEI
(41,338 entries) exists but CLARIN.si 11356/1666 is metadata-only, 0 files**
— the nearest prize, one email to BCDH unblocks a drop-in for the existing
TEI dictionary family; Sreznevsky re-verified unchanged (oldrusdict.ru
query-only); Derksen Brill-blocked. Only clean ingest today: **Wiktionary OCS
via kaikki.org** (verbatim "made available under the same licenses as
Wiktionary - both CC-BY-SA and GFDL", ~4,548 senses, JSONL → small new
dictionary family) — modest, LATER, best bundled with Miklosich if unblocked.
(3) South Slavic/Slovenian: YES — **Freising Manuscripts (eZISS) fully
downloadable TEI P4** (diplomatic+critical+phonetic + 6 translations +
glossary) but the survey's key catch: the TEI source's `<availability>` says
verbatim "Priznanje avtorstva-Brez predelav 2.5 Slovenija" = **CC BY-ND**
(the English HTML page mislabels it BY-SA; verified directly in bs.xml) →
LATER, gated on owner posture decision (permission email to Ogrin/Erjavec vs
restricted local ingest); CLARIN.SI holds **goo300k** (gold, 294k words
1584–1899, verbatim "CC BY 4.0") + **IMP** (17.7M tokens 1584–1919, CC BY-SA
4.0) → LATER, owner scope call (Early Modern vs ancient charter); no Old
Slovene/South Slavic UD treebank exists. (c) Blocked re-checks: obdurodon,
Manuscript.ru (now cert/DNS-degraded), TITUS — all **UNCHANGED**.
PHASE-13 SHAPE: only UD Ruthenian warrants an in-phase packet (config-only
rider beside CCMH); everything else is owner-decision-gated (Freising ND
posture, Miklosich email, Slovene scope), not engineering-gated. Register
rows: #18 updated (Freising), #45–49 added, #4/#13/#30/#32/#33 annotated.

## P13-2 · CCMH adapter — the OCS canon completion  [tier: opus] [status: pending] [deps: P13-1]
Survey-I pick #2: Corpus Cyrillo-Methodianum Helsingiense (Kielipankki) — 7
canonical OCS texts as transliteration + simple structured XML; real gain =
Codex Assemanianus + Savvina kniga (absent from all current holdings) +
alt-editions of Marianus/Zographensis/Suprasliensis (NEVER dedupe — distinct
editions per the standing alt-edition rule). Two-phase with fixture gate:
Phase A verifies the Kielipankki download path + exact license ("Open" in
the catalogue — get the verbatim grant), maps the "very simple, not all
texts properly checked" XML honestly, designs citations (text·chapter·verse
where the transliteration carries them?), sizes the new small family. STOP
— owner gate. Phase B: adapter, registry enabled:false, conformance, docs.

### Phase A findings + FIXTURE PLAN — AWAITING OWNER APPROVAL (2026-07-11)

**LICENSE (verbatim).** The PUB `-src` bundle carries its own grant. From
`https://www.kielipankki.fi/download/ccmh-src/README.txt` verbatim:
> Corpus Cyrillo-Methodianum Helsingiense: Corpus of Old Church Slavonic
> texts, source
> Metadata: http://urn.fi/urn:nbn:fi:lb-20140730106
> Licence: CC-BY (https://creativecommons.org/licenses/by/4.0)
> Resource shortname: ccmh-src

The download index (`/download/ccmh-src/`) labels `ccmh-src.zip` (2.1M) **"CC
BY"**; the Helsinki data catalogue record (`342b3dd2-…`) shows the access
label **"Open"**. So the catalogue's bare "Open" resolves to **CC BY 4.0**.
→ `license_class: attribution` (byte-for-byte the sblgnt precedent: "CC BY
4.0" → `attribution`). The manifest will still read the string from the
bundle at ingestion, not hardcode a class beyond this verified mapping.
Attribution required: cite CCMH + `urn:nbn:fi:lb-20140730106`.

**DOWNLOAD-PATH VERDICT — CLEAR (no auth).** PUB, publicly browsable, no
login. Two equivalent surfaces, both verified reachable:
- bundle zip: `https://www.kielipankki.fi/download/ccmh-src/ccmh-src.zip` (2.1M)
- per-file www tree: `https://www.kielipankki.fi/download/ccmh-src/www/<text>.{html,txt,xml}`
Not a git repo → `fetch_path` is HTTP file/zip (ASPR-`FileFetch` / ORACC-
`ZipFetch` family), `sync_policy: manual`, `enabled: false`. **Recommend
per-file FileFetch of the 4 gospel `.xml` files** (stable URLs, no unzip step)
over the zip. No email/signup anywhere on the path — nothing BLOCKED.

**STRUCTURE MAP (honest).** Each `<text>.html` is a LibreOffice-exported
*description* page (3–22 KB) that links a `.txt` (7-bit-ASCII data) and, for
the gospels only, a `.xml`. XML availability is the decisive fact:

| text | .txt | .xml | genre / ref scheme |
|---|---|---|---|
| Codex Assemanianus | 317 KB | **563 KB** | gospel lectionary — XML re-sorted to canonical MAT→JOH order |
| Codex Marianus | 413 KB | **618 KB** | tetraevangelium |
| Codex Zographensis | 389 KB | **560 KB** | tetraevangelium |
| Savvina kniga | 198 KB | **359 KB** | gospel lectionary |
| Codex Suprasliensis | 861 KB | *(none)* | menaion/homilies — prose, folio scheme |
| Vita Constantini | 71 KB | *(none)* | prose (later copy) |
| Vita Methodii | 25 KB | *(none)* | prose (later copy) |

The `.xml` is **CES `cesDoc` version 4** — genuinely structured:
`<div type="book" id="b.MAT">` → `<div type="chapter" id="b.MAT.01">` →
`<seg type="verse" id="b.MAT.01.01">`. Books are the four gospels, upstream
codes **MAT / MAR / LUK / JOH** (note MAR not MRK, JOH not JHN — kept verbatim,
not "corrected"). Two sub-shapes under one schema, both handled by a single
streaming pass (accumulate all text between `<seg>`…`</seg>`):
- **Assemanianus, Savvina:** verse text wrapped in `<ver id="1.01.01.0.0">`
  children (id = the 7-digit gospel·ch·verse·line·parallel code); a seg may
  hold several `<ver>` (line splits / lectionary parallels) → concatenated.
- **Marianus, Zographensis:** verse text sits directly in `<seg>` mixed
  content, no `<ver>`; chapter/seg ids NOT zero-padded (`b.MAT.5.23`).

Quirks confirmed against the real files (to be pinned by fixtures): a
non-canonical chapter `0` exists (`b.JOH.0.14` — colophon material); duplicate
`(book,chapter,verse)` seg ids occur and carry **distinct** text (marianus 8,
assemanianus 1, zographensis 3, savvina 0) → must disambiguate, never merge.
Text is the corpus's **7-bit ASCII transliteration** (case-significant:
`&`=big jer, `$`=small jer, `@`=jat, `O`=big jus, `E`=small jus, `w`=omega,
`x`=xer, `T`=fita, plus editorial marks `*`=capital, `!`=titlo, `'`=poerok,
`[…]`=interpolation, `%`=editor-flagged uncertainty). Stored **verbatim** (no
Cyrillic back-transliteration — that is an enrichment, not canonical). ASCII ⇒
NFC is trivially satisfied; `chu` gets the generic search fold. The catalogue's
"not properly checked" warning is materially the `%` marks and the dup segs;
both are handled, not cleaned.

**CITATION / URN DESIGN.** One XML file = one manuscript = up to 4 gospel
books; mirror the ASPR one-file-many-divs pattern — `discover` yields one
`DocumentRef` per (manuscript, gospel-book), `parse` extracts that book div.
- Document URN: `urn:nabu:ccmh:<manuscript>:<book>` e.g.
  `urn:nabu:ccmh:assemanianus:mat` (book lowercased, sblgnt-style).
- Passage URN: `…:<chapter>.<verse>` e.g. `urn:nabu:ccmh:assemanianus:mat:1.1`
  (leading zeros stripped → integers, so shape-A `01` and shape-B `5` unify).
- Passage grain = verse (`<seg type="verse">`); text = its concatenated
  `<ver>`/mixed content, NFC.
- **Uniqueness rule** (conformance): where a `(book,ch,verse)` repeats within a
  document, append an occurrence suffix (`…:21.25` then `…:21.25#2`) so
  passage URNs stay unique and stable across two parses. Exact suffix form
  pinned in Phase B against the fixture dup.
- `parser_family: ccmh-ces`; language `chu` for all.

**DEDUPE DISCIPLINE (standing rule §3 — NEVER dedupe).** Confirmed against
holdings: PROIEL already carries `urn:nabu:proiel:marianus`; TOROT carries a
Zographensis and a Suprasliensis. CCMH's Marianus/Zographensis/Suprasliensis
are **distinct editions** (Vajs–Kurc / Helsinki transliteration vs the
treebank editions) → ingested as separate versions, no cross-source dedup.
The genuine gaps CCMH closes — **Codex Assemanianus + Savvina kniga** — are
absent from every current holding and both live in the XML core below.

**SCOPE RECOMMENDATION (owner call).** Recommend **v1 = the 4 gospel
manuscripts via the CES-XML parser** (Assemanianus, Marianus, Zographensis,
Savvina). This delivers BOTH new prizes (Assemanianus, Savvina) AND 2 clean
alt-editions (Marianus, Zographensis) with uniform book·ch·verse citations,
low fixture risk, one small parser family, one small diff. **Defer** the 3
TXT-only texts (Suprasliensis + the two Vitae): no XML, prose/folio 7-digit
schemes whose semantics differ per text (fixture archaeology), and the
Suprasliensis alt-edition value is already queued far richer in the obdurodon
packet (#30) while TOROT holds one. They can be a later `ccmh-txt` extension
if wanted. **If the owner prefers full-canon coverage now**, say so at the
gate and I will add the `.txt` line parser + Suprasliensis/vitae fixtures in
Phase B (larger diff, more quirk-pinning).

**FIXTURE PLAN** (Phase B; the ONLY network step — trimmed real slices,
retrieved 2026-07-11, from `…/download/ccmh-src/www/<t>.xml`, byte-identical
heads/tails, structurally intact). Under `test/fixtures/ccmh/`:
- `assemanianus.xml` — **shape A + lectionary prize + the dup-seg quirk.**
  Trim to MAT 1 (genealogy, the `<ver>`-wrapped opening already sampled) +
  the JOH 21 tail that carries the one duplicate `b.JOH.21.25` seg → exercises
  `<ver>` concatenation, multi-`<ver>` segs, and the uniqueness-suffix path.
- `savvina.xml` — **shape A + second prize.** Trim to MAT 1 + one LUK
  pericope; confirms lectionary-with-`<ver>`, zero dups (control).
- `marianus.xml` — **shape B + alt-edition + dup-seg + chapter-0.** Trim to
  MAT 5 (Sermon slice, direct mixed content, no `<ver>`) + the `b.JOH.0.14`
  colophon dup → exercises shape-B path, non-padded ids, chapter `0`, dup.
- `zographensis.xml` — **shape B alt-edition control.** One short MAT chapter.
- `README.md` — retrieval date/URL, license chain verbatim (CC BY 4.0 →
  `attribution`, README.txt + zip label + catalogue "Open"), per-file table,
  the transliteration/edito­rial-mark key, and the two sub-shape notes.
Demo-parse evidence to report at Phase-B close: an Assemanianus verse, e.g.
`urn:nabu:ccmh:assemanianus:mat:1.1` → `*k$nIg&I !rodstva !!iUxva . !sna
!ddva . !sna *avra/am/l@ .` (Matthew 1:1, "The book of the generation of
Jesus Christ, the son of David, the son of Abraham").

Files touched Phase B (planned): `lib/nabu/adapters/ccmh.rb` +
`lib/nabu/adapters/ccmh_ces_parser.rb`, `test/adapters/ccmh_test.rb`,
`test/fixtures/ccmh/…`, `config/sources.yml` (ccmh: enabled:false,
sync_policy:manual), `docs/02-sources.md` (row 19 → READY + alt-edition
notes), worklog (sha —). One commit, not pushed.

**STOP — FIXTURE PLAN — AWAITING OWNER APPROVAL. No fixtures fetched.**

## P13-3 · ORACC expansion II  [tier: opus] [status: pending] [deps: —]
Config-only breadth per the P11-6 pattern: candidate projects saao/saa02…
saa19 (the rest of the State Archives of Assyria), riao, ribo, blms, dcclt
subprojects — Phase A verifies per-project license (CC0 expected but READ
per project — the adapter maps at sync anyway) + zip availability + sizes,
proposes the batch; owner approves the list (sizes matter — this could be
100+ MB of zips); Phase B: PROJECTS list + scope comment + 02-sources.
NEW-NODE-TYPE GUARD stands: if the parse-only smoke on owner-synced data
hits unknown cdl shapes, census + report, do not hack.

## P13-4 · ATF translations — cuneiform readable  [tier: fable] [status: pending] [deps: P13-3]
The SAA letters famously have running English; the JSON carries none of it
(P9-5a: 0 translation nodes; English lives in the ATF #tr.en lines / HTML).
Phase A (design-heavy scout): find the bulk ATF acquisition path (oracc
zips with ATF? per-project ATF exports? the oracc github ATF repos?);
verify license (same CC0 project umbrella?); design how #tr.en lines
attach: aligned-translation documents in the P7-4 shape (eng docs whose
citations mirror the tablet lines → --parallel works) vs annotations vs
hub witnesses — argue, pick, size. STOP — owner gate (this is the
"cuneiform readable like Homer" payoff and the phase's fable packet).
Phase B: implement per approved design.

## P13-5 · Psalms alignment work  [tier: opus] [status: pending] [deps: —]
Cross-shelf gem: new `psalms` work in config/alignments.yml — LXX-Swete
(tlg0527 Psalmi, Greek numbering) ↔ Vulgate (Gallican, same Greek-tradition
numbering — verified compatible in P11-5) ↔ WEB (HEBREW numbering — the
versification divergence P11-8 dodged; this packet FACES it: a per-witness
offset map or verse-map extractor extension, designed not hacked; if the
honest answer is "Psalms need a mapping layer the registry lacks", report
the design and stop for review) ↔ ASPR Paris Psalter (OE metrical psalms,
psalm-numbered divs A5.x — verify their citation grain supports verse
alignment; they may be psalm-level only → document honestly what grain the
OE witness supports). Acceptance: `align "PSA 22.1" --work psalms` (or the
designed equivalent) renders ≥3 witnesses correctly INCLUDING the numbering
divergence handled visibly; registry loader validation green; docs.

## P13-6 · Morph facets  [tier: opus] [status: pending] [deps: —]
improvements §1.6: search by morphology over the gold shelves (treebanks +
ORACC pos): `search --lemma X --morph case=dat,number=pl` or a designed
equivalent. Design note first (annotations schema reality check across
conllu/proiel/oracc token shapes; index needed or LIKE-over-annotations
acceptable at current scale? — measure before building), then implement
smallest honest version. MCP: extend nabu_search args. Docs + conventions.

## P13-7 · Vocab profiling  [tier: opus] [status: pending] [deps: P13-6]
improvements §1.7 (stretch — take only if the phase runs to schedule):
`nabu vocab <urn-or-document>` — lemma frequency profile of a
document/range vs the corpus (distinctive vocabulary, hapax list), gold
shelves only, honest about coverage. CLI + optional MCP. Small.

## P13-8 · Open-source finishers  [tier: opus] [status: pending] [deps: —]
CI badge in README (the repo HAS GitHub Actions CI — the P12-4 no-CI claim
was wrong, verify + fix), CONTRIBUTING.md (house rules distilled from
CLAUDE.md/dev-loop for outside contributors + the DCO note from the MIT
decision discussion), and a SECURITY/support one-liner if conventional.
Tiny; no code.

## P13-gate · Phase 13 gate  [tier: orchestrator] [status: pending] [deps: P13-1..8]
Full-diff review, library.md refresh (new shelves/sections as synced),
README truthfulness (numbers), PR, owner sync queue + flips, sticky alarm
LAST. P13-7 dropped without ceremony if the phase runs long.

## P13-1b · UD Ruthenian treebank  [tier: opus] [status: done] [deps: P13-1]
Survey-II pick #1, promoted in-phase (config-only, the P10-2 recipe
exactly): add UD_Old_East_Slavic-Ruthenian to the ud adapter's TREEBANKS
map — "prosta mova" chancery/legal texts 1380–1650, the third East Slavic
branch (zero overlap with birchbark/RNC/TOROT). License gate: verify
CC BY-SA 4.0 in the repo README/LICENSE verbatim at fixture time (survey
verified; re-verify) → attribution via the P10-4 per-treebank override
(follow the birchbark/rnc entries). Fixture: one trimmed ~50-sentence
.conllu slice (the ONLY network). Language code: verify what the treebank
declares (orv? separate code?) and follow upstream. Conformance +
idempotency + lemma-row evidence + dedup-guard test untouched. 02-sources
UD row → 7 treebanks; backlog done; worklog (sha —). One commit, not
pushed.

### Findings (P13-1b, 2026-07-11 — shipped)

LICENSE GATE PASSED. `UD_Old_East_Slavic-Ruthenian/master/LICENSE.txt` verbatim:
"The treebank is licensed under the Creative Commons License Attribution-ShareAlike
4.0 International." + "The complete license text is available at:
http://creativecommons.org/licenses/by-sa/4.0/legalcode" — byte-identical to
Birchbark/RNC. `README.md` machine-readable metadata block: `License: CC BY-SA
4.0`. (GitHub repo license field reads `NOASSERTION`, as the survey flagged; the
in-repo grant is authoritative.) The stop-if-different condition never fired.

LANGUAGE CODE: **`orv`** (following upstream: the UD file stem is `orv_ruthenian`,
the shared East-Slavic code Birchbark/RNC also use). The per-newdoc comment
`# lang = orv-be` (all 33 newdocs in the test split) is a finer BCP-47 regional
subtag (Old East Slavic, Belarus), NOT the UD treebank language — the adapter
tags the document `orv` from the `TREEBANKS` map, exactly as birchbark/rnc.

FIXTURE: `test/fixtures/ud/old-east-slavic-ruthenian/orv_ruthenian-ud-test-head50.conllu`
— the first 50 complete sentence blocks of `orv_ruthenian-ud-test.conllu` (390
blocks, 940,453 → 309,311 B). The whole test split has NO multiword-token range
line (`n-m`) and NO empty node (`n.m`) — checked file-wide — so head-50 is
representative with nothing extra to append (as Birchbark/RNC). Opens with the
Second Lithuanian Statute (1566). All token lines validated at 10 tab-columns,
file ends with a blank line, only complete blocks.

ADAPTER: one `TREEBANKS` entry (`old-east-slavic-ruthenian`, repo, language `orv`,
license "CC BY-SA 4.0", license_class `attribution`) — the P10-2 + P10-4 recipe
verbatim, no new parser family, no fetch/discover changes. Dedup guard untouched
(Ruthenian is neither a chu-PROIEL nor an orv-TOROT conversion). URN example:
`urn:nabu:ud:old-east-slavic-ruthenian:orv_ruthenian-ud-test-head50:StatutVKL1566-1`.

LEMMA-ROW EVIDENCE: fixture load → `passage_lemmas` orv rows via the UNCHANGED
Indexer plumbing; the opening NOUN lemma `артыкулъ` "article" at
`…:StatutVKL1566-1` is attested by the pristine uppercase surface form `АРТЫКУЛЪ`.

## P13-9 · Slovenian: goo300k + IMP  [tier: opus] [status: pending] [deps: P13-2]
Owner scope ruling (2026-07-11): "there isn't much before Early Modern
Slovenian at all, so it's in-scope." Survey-II picks #3/#4: goo300k
(CLARIN.SI, gold-annotated, verbatim CC BY 4.0, 294k words 1584–1899) and
IMP (CC BY-SA 4.0, 17.7M tokens, historical Slovenian). Two-phase, fixture
gate: Phase A verifies CLARIN.SI download paths + license grants verbatim,
maps formats (TEI? vertical? — survey II has the leads), decides one
adapter family or two, proposes which of the two corpora first (or both)
with sizes; STOP — owner gate. Phase B per approval. Registry
enabled:false; language code sl (historical); 02-sources rows; worklog.

## P13-10 · Wiktionary-OCS dictionary (kaikki) — and the reconstruction seed  [tier: opus] [status: pending] [deps: P13-2]
Owner (2026-07-11): "Wiktionary is a good start, could be used for other
things as a basis. Such as PIE/comparativistics/reconstructions that we
didn't even start touching yet." Two deliverables:
(a) kaikki.org Wiktionary-OCS extract (~4,548 senses, "made available
    under the same licenses as Wiktionary - both CC-BY-SA and GFDL" —
    dual-license → attribution) onto the reference shelf: JSONL dictionary
    family (third format after TEI + CSV), slug wiktionary-cu, lang chu,
    folded-headword keying (Cyrillic OCS — existing chu fold), etymology
    fields KEPT in the body (they carry the Proto-Slavic links).
(b) SCOUT NOTE (no implementation): what kaikki offers for the
    reconstruction axis — Proto-Slavic/Proto-Germanic/PIE reconstruction
    entries exist in Wiktionary's extracts; survey scope, sizes, licensing
    (same dual), and how a future "etymology/reconstruction shelf" might
    join dictionaries (entries whose headwords are *reconstructed forms
    linked to attested lemmas across the library's languages — the
    comparativist's dream). Write findings into improvements.md as a new
    register entry; NO adapter for it in this packet.
Two-phase, fixture gate on (a). Registry enabled:false; 02-sources;
worklog.

## Slavic decisions record (owner, 2026-07-11)
Freising (CC BY-ND): WAIT. Miklosich BCDH email: WAIT. Early Modern
Slovenian: IN SCOPE (→ P13-9). Wiktionary OCS: GO (→ P13-10, with the
reconstruction-axis scout note).
