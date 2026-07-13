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

## P13-2 · CCMH adapter — the OCS canon completion  [tier: opus] [status: done] [deps: P13-1]
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

### Phase A findings + FIXTURE PLAN — OWNER-APPROVED 2026-07-11 ("CCMH fixture approved": 4-gospel XML v1; Suprasliensis + Vitae deferred; dup ids → collision-tolerant `:b2` suffixing per the GRETIL precedent)

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

**Gate cleared: OWNER-APPROVED 2026-07-11, scope option 1 (4-gospel XML
v1). Phase B executed — findings below.**

### Findings (P13-2 Phase B, 2026-07-11 — shipped)

SHIPPED AS APPROVED, no scope drift. New small family `ccmh-ces`
(`CcmhCesParser`, the AsprParser one-file-many-documents shape, streaming
Reader only) + `Ccmh` adapter: one document per (manuscript, gospel book),
7 docs from the fixture set, urn `urn:nabu:ccmh:<ms>:<book>` + passage
`:<ch>.<verse>` (zero-padding stripped so the two upstream sub-shapes cite
uniformly). Both sub-shapes handled by ONE accumulation rule — a passage's
text is all character data inside its `<seg>`, collapsed — so `<ver>`-
wrapped (assemanianus/savvina) and direct-seg (marianus/zographensis) never
fork the code path. Duplicate verse ids: `:b2` positional suffix in
document order (GRETIL precedent), pinned by both real dups (assemanianus
b.JOH.21.25, marianus b.JOH.0.14 — distinct texts kept, never merged).
Marianus chapter 0 (heading list) kept — canonical means canonical; the
editors' `%` uncertainty marks stored verbatim.

FETCH DESIGN (the packet's one structural finding): FileFetch keeps ONE
state file per dir and dooms unrecognized siblings, so the four files MUST
NOT share a directory → per-manuscript subdirs (`canonical/ccmh/<ms>/`),
ORACC's two-phase aggregation (prepare all four → one mass-deletion breaker
over the union → complete all), FetchReport.repos = per-file url→sha pins.
Probe: `:http_zip`, 4 targets, `state_subdir: <ms>`, `metadata_url: nil`
(the license lives in the bundle README, no endpoint).

Fixtures: 4 trimmed real slices (13.1/6.3/9.1/1.5 KB) + README (license
chain verbatim, transliteration key, sub-shape map) + manifest.yml (all
`whole: false`, `adapter_test: null` — trimmed counts would false-fail
against full upstream). Registry: `ccmh` enabled:false, sync_policy manual
(upstream frozen since 2021). 02-sources row 19 → READY with alt-edition +
deferral notes. Suite 1394 runs/21263 assertions green, lint clean, 24
adapter tests incl. conformance. Demo: `urn:nabu:ccmh:assemanianus:mat:1.1`
→ `*k$nIg&I !rodstva !!iUxva . !sna !ddva . !sna *avra/am/l@ .` (Mt 1:1).
Deferred honestly: Suprasliensis + the two Vitae (txt-only upstream; a
future `ccmh-txt` family if wanted). Owner next step: real
`bin/nabu sync ccmh`, eyeball, flip enabled.

## P13-3 · ORACC expansion II  [tier: opus] [status: done] [deps: —]
Config-only breadth per the P11-6 pattern: candidate projects saao/saa02…
saa19 (the rest of the State Archives of Assyria), riao, ribo, blms, dcclt
subprojects — Phase A verifies per-project license (CC0 expected but READ
per project — the adapter maps at sync anyway) + zip availability + sizes,
proposes the batch; owner approves the list (sizes matter — this could be
100+ MB of zips); Phase B: PROJECTS list + scope comment + 02-sources.
NEW-NODE-TYPE GUARD stands: if the parse-only smoke on owner-synced data
hits unknown cdl shapes, census + report, do not hack.

### Phase A proposal (2026-07-11) — OWNER-APPROVED 2026-07-11 (all + full-SAA extension)

Scouted via `projects.json` + HEAD on each `json/<slug>.zip` (no zip
downloads). All 25 packet candidates exist (HTTP 200, `application/zip`,
`Last-Modified` present). **License is NOT readable in Phase A**: the
standalone `<project>/metadata.json` serves an empty body over HTTP (200,
0 bytes) for every candidate — the known upstream quirk already recorded in
the ORACC row. License expectation is **CC0** for the whole batch, backed by
(a) the P9-5a family scout (2026-07-08) that sampled every family here —
saao, riao, ribo, blms, dcclt — and found CC0, and (b) the adapter's
per-project license gate that STOPS the sync loudly on any non-`open`
license at ingest (the real guarantee).

| project | slug | zip? | size (MB) | Last-Modified | license evidence |
|---|---|---|---|---|---|
| saao/saa02 | saao-saa02 | 200 | 2.5 | 2024-06-07 | P9-5a saao=CC0; gate at sync |
| saao/saa03 | saao-saa03 | 200 | 4.1 | 2024-06-07 | P9-5a saao=CC0; gate at sync |
| saao/saa04 | saao-saa04 | 200 | 7.8 | 2024-06-07 | P9-5a saao=CC0; gate at sync |
| saao/saa05 | saao-saa05 | 200 | 4.7 | 2024-06-07 | P9-5a saao=CC0; gate at sync |
| saao/saa06 | saao-saa06 | 200 | 6.7 | 2024-06-07 | P9-5a saao=CC0; gate at sync |
| saao/saa07 | saao-saa07 | 200 | 3.6 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa08 | saao-saa08 | 200 | 6.9 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa09 | saao-saa09 | 200 | 0.7 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa10 | saao-saa10 | 200 | 8.3 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa11 | saao-saa11 | 200 | 2.2 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa12 | saao-saa12 | 200 | 3.4 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa13 | saao-saa13 | 200 | 3.7 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa14 | saao-saa14 | 200 | 6.1 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa15 | saao-saa15 | 200 | 5.5 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa16 | saao-saa16 | 200 | 3.9 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa17 | saao-saa17 | 200 | 4.3 | 2023-07-11 | P9-5a saao=CC0; gate at sync |
| saao/saa18 | saao-saa18 | 200 | 4.5 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa19 | saao-saa19 | 200 | 5.2 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| riao | riao | 200 | 17.3 | 2024-06-07 | P9-5a riao=CC0; gate at sync |
| ribo | ribo | 200 | 6.6 | 2023-10-22 | P9-5a ribo=CC0; gate at sync |
| blms | blms | 200 | 10.5 | 2024-06-28 | P9-5a blms=CC0; gate at sync |
| dcclt/ebla | dcclt-ebla | 200 | 1.0 | 2024-08-19 | P9-5a dcclt=CC0; gate at sync |
| dcclt/jena | dcclt-jena | 200 | 0.9 | 2024-08-19 | P9-5a dcclt=CC0; gate at sync |
| dcclt/nineveh | dcclt-nineveh | 200 | 16.9 | 2024-10-16 | P9-5a dcclt=CC0; gate at sync |
| dcclt/signlists | dcclt-signlists | 200 | 11.6 | 2025-01-22 | P9-5a dcclt=CC0; gate at sync |
| saao/saa20 | saao-saa20 | 200 | 4.4 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saa21 | saao-saa21 | 200 | 3.6 | 2024-06-10 | P9-5a saao=CC0; gate at sync |
| saao/saas2 | saao-saas2 | 200 | 1.5 | 2024-06-10 | P9-5a saao=CC0; gate at sync |

**APPROVAL (2026-07-11): all 25 approved — "Approve all 25, full SAA is
the point" — and, full SAA being the point, the batch EXTENDS past the
packet's saa02…saa19 cap** with saao/saa20 and saao/saa21 (HEAD-verified
above: 200, `application/zip`, Last-Modified) and saao/saas2, evaluated
and INCLUDED: its project page shows a lemmatised text corpus in the saao
family (the Assyrian Eponym List / Assyrian King List editions from State
Archives of Assyria Studies 2, Millard 1994, lemmatised by N. Morello
2019) with a normal 1.5 MB zip — the same functional shape as the SAA
volumes, not a different series shape. **Final batch: 28 projects,
158.7 MB of zips** (original 25 = 149.2 MB). ribo subprojects
(babylon2…10/sources/bab7scores) remain out — the packet says "ribo", the
top-level project, which has its own 6.6 MB corpus. Parser unchanged; the
NEW-NODE-TYPE GUARD is the owner-fired sync review gate as in P11-6.

## P13-4 · ATF translations — cuneiform readable  [tier: fable] [status: done] [deps: P13-3]
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

### Findings (P13-4 Phase B, 2026-07-11 — shipped)

Implemented exactly per the approved design (one deviation noted below).
Suite 1415 runs / 21,684 assertions green; lint clean; one commit, not
pushed.

- **`OraccTranslationParser`** (new family member, nokogiri): fragment +
  sibling corpusjson → `-en` Document. All extraction rules are
  MARKUP-based: prose = `span.cell` text (state-notice cells have none →
  skipped by rule); the print marker is its own `span.xtr-label` element
  (excluded by element, no prose regexes); restorations survive verbatim
  ("[tran]sferred"). Prose at a non-line anchor reattaches to the next
  line-start row (never silently dropped; unresolvable → loud ParseError);
  two units on one label JOIN (urn uniqueness). Identity: corpusjson
  project/textid must mint the caller's urn.
- **Oracc adapter**: `translations:` kwarg via the established
  `SourceRegistry::Entry#build_adapter` seam (default provably inert —
  pre-P13-4 behavior byte-for-byte). Crawl runs after the zip phases,
  PROJECT-SCOPED (`TRANSLATION_PROJECTS = saao/*`, stage 1); tr-en lists
  machine-read from metadata formats; fragments land at
  `<workdir>/html-en/<slug>/` OUTSIDE the zip-managed trees (a build swap
  can never attic them); sequential + 0.25 s delay, tmp+rename writes,
  resumable (zip 304 ⇒ missing-only; changed build ⇒ project re-crawl);
  soft-404 ("404\n" bodies) counted missing, never written; per-project
  crawl record in fetch notes ("saao-saa01 html-en: 1 fetched, 0 cached,
  1 missing"). Discover is file-driven (-en ref per fragment with a live
  tablet corpusjson; orphans counted skipped-by-rule).
- **`Query::Parallel`**: second work family — `ORACC_DOCUMENT` pattern
  (tablet urn IS the work; siblings = `<work>-<variant>`), both directions
  resolve. Span-grouping unchanged: SAA's paragraph units render as :block
  over the tablet's own o.1/r.5 lines. CLI `show --parallel` + MCP
  `nabu_show parallel: true` light up with zero renderer changes.
- **License**: `-en` docs carry `license_override: "attribution"`
  (CC BY-SA 3.0 SAAo content statement; evidence quoted in the fixtures
  README) — verified through the Loader into documents.license_override;
  tablets stay NULL (inherit open/CC0).
- **Fixtures** (per approved plan): saao-saa01 P224395 pair (corpusjson
  whole from `saao-saa01.zip` + real 54 KB fragment with the two
  break-anchored notice cells), fragments for the fixtured rimanum tablets
  (P405432 13 KB, P405134 7 KB — primed/seal labels), trimmed saa01
  metadata (tr-en gate: X010028 = the real untranslated text) + catalogue.
  The saa01 slice ships the REAL NESTED zip root (saao-saa01/saa01/…).
  DEVIATION from the Phase A table: fixture corpusjson path is
  `saao-saa01/saa01/corpusjson/…` (nested reality), not the flat path the
  plan sketched; rimanum fragments came in under estimate.
- **Demo (scratch store, fixture-loaded)**: `show
  urn:nabu:oracc:saao-saa01:P224395 --parallel` renders
  `block [:o.1 — covers :o.1..:o.3]` — akk `a-na LUGAL EN-ia` /
  `ARAD-ka {1}10-ha-ti` / `lu DI-mu a-na LUGAL EN-ia` then eng "To the
  king, my lord: Your servant Adda-hati. Good health to the king, my
  lord!" — cuneiform readable like Homer.
- **Owner-fired next**: `bin/nabu sync oracc` after merge = stage-1 crawl
  (saao, ~4.7k texts ≈ 250 MB, ~20 min at the polite delay). Stage 2 =
  extend `TRANSLATION_PROJECTS`. Hungarian (etcsri tr-hun) remains a
  config-shaped follow-up.

### Findings & design (P13-4 Phase A, 2026-07-11 — DESIGN + FIXTURE PLAN — AWAITING OWNER APPROVAL)

**Verdict up front.** There is NO public bulk ATF carrying the translations —
that acquisition path is dead end-to-end (evidence below). The aligned running
English IS bulk-obtainable, from the official per-text rendered-HTML endpoint
(`/<project>/<textid>/html`), machine-aligned to the corpusjson we already hold
via shared node refs. Attachment model: **(a) aligned-translation documents in
the P7-4 sibling shape** — the SAA unit-grain reality is exactly what the
P8-1b span-grouped `--parallel` renderer was built for; `show URN --parallel`
gives the Homer reading experience with near-zero new render machinery.
License: translations are **CC BY-SA 3.0 → `attribution`** (per-document
`license_override`, the P10-4 mechanism), NOT the JSON build's CC0.

#### 1. Acquisition — where the English actually lives (all probed 2026-07-11)

Dead ends, each verified:
- **Project json zips carry no prose translations** (re-confirmed on the
  sanctioned sample `saao-saa09.zip`, 755 KB/27 files: corpusjson has 0
  translation nodes, matching P9-5a's saa01 scan). The zip's `index-tra.json`
  is a STEMMED English search index (instances like
  `saao/saa09:P333952_project-en.22.9`) — proof translation documents exist in
  the build, but the index carries word stems, not prose. The 194 KB
  `saao-saa09-portal.json` is project essays (65 chunks, all `index.html`),
  not per-text translations.
- **github.com/oracc/catf** ("Canonical ATF version of Oracc data which is
  permitted to be released under CC0") covers our exact translation-bearing
  scope — saao saa01–saa21 + saas2 + saao, rinap, riao, ribo — but is
  **C-ATF transliteration only: 0 `#tr` lines** (checked saao-saa09.catf
  whole-file: 11 `&P` texts, no translation protocol lines), and stale
  (last pushed 2019-09 vs the 2024-06 JSON builds). No etcsri/rimanum/dcclt.
- **Per-text `.atf`, `.xtf`, `<id>_project-en.json`, and `xml.zip` endpoints
  are all soft-404s** (HTTP 200 with a literal 4-byte `404\n` body, or 0-byte
  JSON) on every mirror probed: upenn, build-oracc, LMU Munich. The
  `oracc/publicdata` repo is empty (2016). P9-5a's ".atf endpoints 404" stands.

The live path:
- **`https://oracc.museum.upenn.edu/<project>/<textid>/html`** — the official
  P4 per-text fragment (served with `access-control-allow-origin: *`, i.e.
  intended for programmatic reads). It interleaves the transliteration rows
  with translation cells: each transliteration `<tr>` carries
  `id="P224395.5"` (**the SAME node ref as the corpusjson `line-start`
  d-node's `ref` field**), and each translation unit anchors at its first row
  via `data-tlat-ref="P224395_project-en.N"`, its prose in a
  `<td class="t1 xtr" data-tlit-id="P224395.5">` cell. Alignment is therefore
  mechanical: HTML ref → corpusjson `line-start` ref → `label` ("o 4") → our
  frozen passage suffix (`o.4`). Verified on saao/saa01 P224395 against the
  synced canonical corpusjson: anchors .2/.5/.12/.34 → `o 1`/`o 4`/`o 11`/
  `r 30`, exact.
- **Which texts to fetch is machine-readable**: each project's `metadata.json`
  (in the zips we already sync) carries `formats["tr-en"]` — the exact list of
  translated text ids. Local evidence: saao-saa01 **264/265**, rimanum
  **378/378**, etcsri **1448/1456** (+1441 Hungarian `tr-hun` — future
  option), rinap-rinap1 **88/96**, dcclt 1229/4980 (lexical lists, expectedly
  partial); saa09 11/11. SAA coverage is effectively total — the famous
  running English is all there.
- Sizes: a typical SAA letter fragment ≈ 55 KB (the giant saa09 prophecy
  compilation P333952: 290 KB). Full 33-project tr-en scope ≈ est. 8–10k
  texts ≈ **400–500 MB, one-time crawl** (~1.5 h at a polite 2 req/s);
  SAA-only ≈ ~4.7k texts ≈ 250 MB. No per-file `Last-Modified` on `/html` →
  freshness gates on the project ZIP's Last-Modified (zip unchanged ⇒ build
  unchanged ⇒ skip project's crawl entirely). Recommend full in-scope crawl;
  SAA-first is the fallback if the owner wants a smaller first sync.

#### 2. License — the honest layered reality

- The **CC0 statements attach to the JSON build files** ("This data is
  released under the CC0 license", in every zip file incl. `index-tra.json`) —
  and the prose translations are deliberately NOT in those files.
- **`oracc/catf`'s README wording** — ATF data "which is *permitted* to be
  released under CC0" — plus the fact that catf strips translations, implies
  the translation layer is exactly what is NOT under the CC0 umbrella.
- The **SAAo project footer** states verbatim: "**Content released under a CC
  BY-SA 3.0 license, 2007-20**" (the site-wide licensing page scopes its CC
  BY-SA to "this online documentation"; the SAAo statement covers project
  content). The translations originate in the printed SAA volumes (Helsinki,
  Parpola et al., 1987–), republished on SAAo.
- → Translation documents are labeled **`attribution` (CC BY-SA 3.0)** via
  `documents.license_override` (P10-4 mechanism, as UD birchbark/rnc/
  ruthenian) while the oracc source stays `open`. Attribution is MCP-safe.
  Attribution string: "CC BY-SA 3.0 (SAAo/ORACC project content; SAA volume
  authors per catalogue)".

#### 3. Format — the #tr.en / unit-grain reality

ORACC ATF has three translation forms (doc/help/editinginatf/translations):
interlinear `#tr.en:` per line, `@translation parallel` (mirrored structure),
and `@translation labeled` (blocks introduced by `@(o 1)` / `@label o 17 -
r 2` label or label-RANGE). **SAAo uses labeled translations** — the rendered
unit structure is the measured reality:
- saao/saa01 P224395 (typical letter): **39 transliteration lines, 6
  translation units** — e.g. unit 1 anchors at `o 1` and covers o 1–o 3 ("To
  the king, my lord: Your servant Adda-hati. Good health to the king, my
  lord!"), unit 2 at `o 4` covers o 4–o 10, etc. **Paragraph-grained, NOT
  1:1.**
- saao/saa09 P333952 (poetry/prophecy): 214 lines, 55 units (~4 lines/unit) —
  finer, still block-grained. Per-line 1:1 is just the degenerate case.
- Two P224395 units anchor at NON-line rows ("(Break)", "(Rest destroyed)" —
  rendered `$`-state notices): prose-free, skipped by rule (counted); a
  prose-bearing unit anchored at a break row (none seen yet) reattaches to
  the next line-start row within the unit.
- Unit prose begins with the print edition's line marker "(1) ", "(4) " —
  alignment metadata now carried by the citation; stripped at parse, noted in
  the parser docs (exact rule TDD'd against real fixtures).

#### 4. Design — the attachment argument and pick

**(a) Aligned-translation documents (P7-4 sibling shape) — CHOSEN.**
One new document per translated text: `urn:nabu:oracc:<slug>:<textid>-en`
(P/Q ids never contain hyphens; no collision with tablet urns or passage
suffixes), language `eng`, `license_override: attribution`, title
"<designation> (English translation)". One passage per translation unit,
suffix = the ANCHOR line's frozen label suffix (`o.1`, `r.30`) — a suffix
that exists in the tablet by construction. Then P8-1b span-grouping does the
rest: the anchor OWNS tablet lines up to the next anchor, a multi-line unit
renders as a :block (tablet lines then the English once, coverage-labeled), a
1:1 unit as a :pair — **the ORACC labeled-translation model and the span-group
ownership rule are the same model**; this is precisely the card-cited-Homer
case the renderer was rebuilt for. Honest caveat (same as Homer cards): a
labeled RANGE ending before the next anchor still owns the gap lines — the
block shows slightly more tablet context than the label claimed, never less.
One code change needed in `Query::Parallel#sibling_edition`: it is
CTS-only today; add the ORACC document pattern
(`\Aurn:nabu:oracc:[^:]+:[PQ][^:.-]+\z` as work; sibling = urn `<work>-…`,
language = LANG) — ~15 lines + tests. The CLI/MCP surfaces then light up
unchanged: `nabu show <tablet-urn> --parallel` and MCP `nabu_show`
`parallel: true, parallel_lang: eng`. Translations are also first-class
documents: English fulltext `search`, `show`, honest per-document license.

**(b) Annotations on original passages — REJECTED.** Unit prose stuffed into
the anchor passage's `annotations_json` has no render surface (`show
--parallel` can't see it; annotations are token/analysis metadata by house
convention), misrepresents a multi-line unit as a property of one line, makes
English unsearchable without new plumbing, and cannot carry its own
(different!) license label. Every honest fix rebuilds model (a) piecemeal.

**(c) Alignment-hub witnesses — REJECTED.** Architecture §10 draws the line
itself: the hub is CROSS-source, N-way, per-WORK with a shared citation
vocabulary; Parallel is "within-source translation pairing". Tablets are
~8–10k independent "works" — a registry entry per tablet is config sprawl the
registry was never meant for, and the hub renders sentence lists, not the
interleaved reading page. This is definitionally Parallel's job.

#### 5. Implementation sketch (Phase B)

1. **Fetch** (same oracc source — no cross-source canonical reads): after the
   zip phase, per project read `metadata.json` `formats["tr-en"]`, crawl
   `/<project>/<id>/html` → `<workdir>/<slug>/html-en/<id>.html` via
   `ZipFetch.default_http` (vendored certs), polite rate limit, resumable
   (skip existing; full re-crawl of a project only when its zip changed);
   attic contract for upstream-dropped ids; counts in fetch notes. WebMock'd
   tests. (~100–120 lines)
2. **Parser** `OraccTranslationParser` (nokogiri, already a dep): input =
   html fragment + sibling corpusjson path (for ref→label); walk xtr cells in
   order → units; skip prose-free non-line anchors (counted); strip print
   markers; NFC; mint `<doc>-en:<label→dots>` passages;
   `license_override: attribution`. (~180 lines + tests incl. conformance)
3. **Discover**: emit an `-en` DocumentRef per `html-en/<id>.html` whose
   sibling corpusjson exists, metadata carrying both paths + title. (~40
   lines)
4. **Parallel**: ORACC sibling pattern as above. (~15 lines + tests)
5. **Docs/registry**: sources.yml oracc `translations: true` note; 02-sources
   ORACC row (translation acquisition + license layering); architecture §3
   note (sibling model gains the ORACC pattern — one paragraph); mcp.md line;
   backlog + worklog.
   Sizing: **≈ half a P10-1** — a solid fable day, no new gems, schema
   untouched (license_override exists).

#### 6. Fixture plan (all real upstream, fetched at Phase B fixture time)

Reuse the five existing corpusjson fixtures; add the html fragments + one SAA
letter pair:

| File (under test/fixtures/oracc/) | Size | whole? | Why |
|---|---|---|---|
| `rimanum/html-en/P405432.html` | ~30 KB est | whole | translation for an ALREADY-fixtured corpusjson (rimanum is 378/378 tr-en); Akkadian admin, P-number |
| `rimanum/html-en/P405134.html` | ~20 KB est | whole | second rimanum pair (short) |
| `saao-saa01/corpusjson/P224395.json` | 25 KB | whole | the fable case: SAA letter, byte-identical to the synced canonical copy (zip URL noted) |
| `saao-saa01/html-en/P224395.html` | 55 KB | whole | 6 paragraph units over 39 lines INCLUDING the two break-anchored prose-free cells (the skip rule's regression case) |
| `saao-saa01/metadata.json` | few KB | trimmed formats | `formats.tr-en` gating test: saa01 has one text with atf but no tr-en (265 vs 264) — keep that id in the trim so the no-translation skip is tested |

HTML fragments are kept WHOLE (trimming rendered HTML risks structural lies);
if P405432's fragment surprises at >100 KB, substitute the smallest
translated rimanum text. README notes: retrieval date, endpoint URLs, the
CC BY-SA 3.0 evidence quotes (SAAo footer verbatim + catf README verbatim),
the "no public bulk ATF with translations" finding, and the soft-404 record.

#### 7. Acceptance (Phase B)

Conformance + idempotency green for `-en` docs; `bin/nabu show
urn:nabu:oracc:saao-saa01:P224395 --parallel` renders o.1–o.3 + "To the king,
my lord…" as a :block (fixture-loaded, demo evidence in the final report);
`search` hits English prose; license_override attribution visible in show
output; suite+lint green; one commit, not pushed.

**DESIGN + FIXTURE PLAN — OWNER-APPROVED 2026-07-11** ("Approved design,
Two-stage SAA-first crawl"): model (a) sibling `-en` documents + per-text
HTML crawl + `attribution` labeling, as proposed. Crawl staging: TWO-STAGE,
SAA-FIRST — stage 1 (owner-fired) crawls the saao projects (~250 MB);
stage 2 (the remaining translated projects: rimanum, etcsri, rinap1, riao,
ribo, blms, dcclt*) is a later owner-fired run. The crawl path is
PROJECT-SCOPED from the start: the fetch serves a translation-project list,
so stage 2 is a list extension (the established `PROJECTS`-scope pattern),
no machinery change between stages.

Decision points as approved:
1. **Model (a)** — sibling translation documents, `--parallel` renders tablets
   like Homer. (b)/(c) rejected with reasons above.
2. **Acquisition = per-text HTML crawl** (the only public machine path;
   official endpoint, CORS-open, ref-aligned), SAA-first two-stage as above.
3. **License: translations labeled `attribution` (CC BY-SA 3.0)** per the
   SAAo content statement — NOT CC0; per-document override, source stays open.
4. Hungarian (etcsri, 1441 texts) supported by the same design later — v1 is
   English only.

## P13-5 · Psalms alignment work  [tier: opus] [status: done] [deps: —]
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

### Findings (P13-5, 2026-07-11 — shipped)

NEW MECHANISM: a per-witness `numbering:` key on the alignment registry
(architecture §10) — a `system:` provenance label plus a `ranges:` list of
`{from, to, shift}` piecewise-linear rules that remap the LEADING citation
segment (the psalm number) of a witness's refs into the work vocabulary. It
lives in `Witness#normalize_ref`, applied AFTER the `books:` alias and, like
`books:`, INDEX-SIDE only (the query already speaks the work vocabulary — the
extractor set stays closed at two, `numbering:` is orthogonal to extraction).
The one new power: an unmapped psalm returns nil → the ref is DROPPED (the
indexer's compact/filter_map skip it), so the join/split psalms never
false-align. Existing works stay byte-stable (numbering defaults nil; the two
`Witness.new` call sites pass it, nothing else moved).

THE MAPPING TABLE (encoded on the WEB witness in config/alignments.yml;
provenance = the standard LXX↔Masoretic psalm concordance — Rahlfs'
Septuaginta front-matter, NETS, and the Douay/Vulgate-vs-Hebrew tables, all
agreeing, cross-checked live against the corpus, e.g. WEB 22 = "My God, my
God, why have you forsaken me" = Greek 21):

    Hebrew 1–8     = Greek 1–8      identity        (shift 0)
    Hebrew 9,10    → Greek 9        LXX JOINS        DROPPED
    Hebrew 11–113  = Greek 10–112   long stretch    (shift −1)
    Hebrew 114,115 → Greek 113      LXX JOINS        DROPPED
    Hebrew 116     → Greek 114,115  LXX SPLITS       DROPPED
    Hebrew 117–146 = Greek 116–145                  (shift −1)
    Hebrew 147     → Greek 146,147  LXX SPLITS       DROPPED
    Hebrew 148–150 = Greek 148–150  identity        (shift 0)

The six unmapped psalms (Hebrew 9, 10, 114, 115, 116, 147) attest per-witness
only: e.g. `align "PSA 113.1"` renders LXX + Vulgate ("In exitu Israel") and
an honest WEB miss, never a fabricated pairing. HONEST RESIDUAL: the remap
fixes the PSALM number only; verse numbering WITHIN a psalm can also differ
(LXX/Vulgate fold a Hebrew superscription into verse 1, the English does not)
— disclosed, uncorrected, never fuzzed. For the acceptance verse the systems
agree verse-for-verse.

DISPLAY: the remapped witness's own (Hebrew) ref is recovered at QUERY time
from the passage urn (never stored in the index) and surfaced — the column
header gains "· Hebrew (Masoretic) numbering" and each sentence a
"[Hebrew (Masoretic): PSA 23.1]" note. So the divergence is VISIBLE, not
silently corrected.

PARIS PSALTER GRAIN VERDICT: DEFERRED with evidence (not registered). ASPR
mints one document per psalm (`urn:nabu:aspr:A5.51` … `A5.150`, psalms 51–150
only — 1–50 are prose, absent from ASPR vol. 5) and numbers passages by the
printed POETIC LINE ordinal, NOT the Latin verse (the adapter's frozen
minting: "Passage urns append the 1-based line ordinal … equals the printed
ASPR line number"). One Latin verse becomes several Old English metrical
lines, so aligning line N onto verse N would fabricate pairings; the psalm
number lives in the document id, not the passage tail, so cts-verse cannot
build "PSA 51.3" from it either. Verse alignment would need a hand-built
line→verse concordance the corpus does not have; a psalm-level registration
would add a column that never co-renders with the verse-grain rows. So it
stays out, documented in a loud registry comment + here + architecture §10,
awaiting a real OE-psalter verse concordance.

ACCEPTANCE RENDER (scratch index over a read-only copy of the live catalog —
the live alignment index picks `psalms` up at the owner's next `nabu sync`/
`nabu rebuild`, a config-only change; 130,543 rows indexed across all works
from the snapshot):

    PSA 22.1 — Psalms (LXX / Vulgate / WEB — the versification divergence)
      3 of 3 witnesses attest this ref
    LXX (Swete, First1K) — Psalmi [grc]   license: attribution
      …:22.1   Κύριος ποιμαίνει με, καὶ οὐδέν με ὑστερήσει.
    vulgate (Clementine) — Psalmi [lat]   license: open
      …vulgate:psa:22.1   Psalmus David. Dominus regit me, et nihil mihi deerit :
    WEB (English) — Psalms [eng]   license: open   · Hebrew (Masoretic) numbering
      …eng-web:psa:23.1  [Hebrew (Masoretic): PSA 23.1]
        Yahweh is my shepherd: I shall lack nothing.

FILES: config/alignments.yml (+psalms work, loud comment), lib/nabu/
alignment_registry.rb (Numbering/NumberingRange + numbering! parser +
normalize_ref split), lib/nabu/query/align.rb (Sentence.native_ref,
Witness.numbering, native_ref helper), lib/nabu/cli.rb (numbering + native
notes, single + range renders), docs/architecture.md §10. TESTS: registry
(remap/drop/validation + shipped psalms pin), indexer (remap + drop), align
(native-ref render + join/split miss), cli (visible label). Suite 1426 runs /
21,735 assertions green; lint clean (190 files). ONE commit, not pushed;
worklog sha —.

## P13-6 · Morph facets  [tier: opus] [status: done] [deps: —]
improvements §1.6: search by morphology over the gold shelves (treebanks +
ORACC pos): `search --lemma X --morph case=dat,number=pl` or a designed
equivalent. Design note first (annotations schema reality check across
conllu/proiel/oracc token shapes; index needed or LIKE-over-annotations
acceptable at current scale? — measure before building), then implement
smallest honest version. MCP: extend nabu_search args. Docs + conventions.

Findings (design note: conventions §6.1):
- **Tagset verdict — unified UD façade, not per-family passthrough.** Query
  vocabulary is UD feature names (case/number/gender/person/tense/mood/voice/
  degree). CoNLL-U `feats` parsed as-is (already UD, zero translation); PROIEL/
  TOROT positional `morphology` DECODED into the same names via a fixed 10×~8
  code map (`Query::MorphFacets::PROIEL_FIELDS`; positions 9–10 undecoded — no
  clean UD facet). ORACC has no inflectional morphology (`pos` is NER-flavoured),
  so inflectional facets never match it — honest absence, tested; a unified
  `pos` facet deliberately deferred (three incompatible pos schemes).
- **Index verdict — NO new index/migration.** Morphology is post-filtered in
  Ruby over the lemma-anchored candidate passages' `annotations_json`. Measured
  on the live 1.94M-row lemma index: `λόγος` dat-pl 37 ms / 46 hits; `sum`
  subjunctive 720 ms / 4129 hits; worst case (article ὁ) 757 ms / 2255 hits.
  A facet index would multiply rows + need a rebuild for no interactive gain.
- **Out of scope (honest):** bare morph search without `--lemma` (would scan
  every annotated passage); ORACC pos-only facets; UD/PROIEL tense-vs-aspect
  divergence follows each treebank's own encoding (documented).
- Scope: `search`/`nabu_search` only (not `concord` — future). `--morph`
  requires `--lemma`; malformed facets → usage/InvalidArguments error. Each hit
  shows the matching surface form(s) + decoded morph evidence, restricted to the
  matching tokens. New `lib/nabu/query/morph_facets.rb`; tests across conllu +
  proiel + oracc-absence (query/morph_facets_test, query/lemma_search_test,
  mcp/tools_test). Suite 1445/21787 green, lint clean.

## P13-7 · Vocab profiling  [tier: opus] [status: dropped-to-register (gate rule: phase ran full, 11 packets) 2026-07-11] [deps: P13-6]
improvements §1.7 (stretch — take only if the phase runs to schedule):
`nabu vocab <urn-or-document>` — lemma frequency profile of a
document/range vs the corpus (distinctive vocabulary, hapax list), gold
shelves only, honest about coverage. CLI + optional MCP. Small.

## P13-8 · Open-source finishers  [tier: opus] [status: done] [deps: —]
CI badge in README (the repo HAS GitHub Actions CI — the P12-4 no-CI claim
was wrong, verify + fix), CONTRIBUTING.md (house rules distilled from
CLAUDE.md/dev-loop for outside contributors + the DCO note from the MIT
decision discussion), and a SECURITY/support one-liner if conventional.
Tiny; no code.

## P13-gate · Phase 13 gate  [tier: orchestrator] [status: done 2026-07-11] [deps: P13-1..8]
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

## P13-9 · Slovenian: goo300k + IMP  [tier: opus] [status: done] [deps: P13-2]
Owner scope ruling (2026-07-11): "there isn't much before Early Modern
Slovenian at all, so it's in-scope." Survey-II picks #3/#4: goo300k
(CLARIN.SI, gold-annotated, verbatim CC BY 4.0, 294k words 1584–1899) and
IMP (CC BY-SA 4.0, 17.7M tokens, historical Slovenian). Two-phase, fixture
gate: Phase A verifies CLARIN.SI download paths + license grants verbatim,
maps formats (TEI? vertical? — survey II has the leads), decides one
adapter family or two, proposes which of the two corpora first (or both)
with sizes; STOP — owner gate. Phase B per approval. Registry
enabled:false; language code sl (historical); 02-sources rows; worklog.

**OWNER-APPROVED 2026-07-11: option B + orig-canonical.** Both corpora via
the one shared imp-tei parser family — goo300k the gold flagship, IMP the
thin silver adapter with the automatic-annotation quality labeled honestly;
gold lemma rows feed passage_lemmas from goo300k ONLY (default upheld: IMP
text searchable without lemma rows, decision documented in the adapter +
registry + 02-sources row 45). Canonical/annotation split confirmed:
historical orig spelling IS the passage text, reg/lemma/msd ride as
annotations.

### Findings (P13-9, 2026-07-11 — shipped)

Phase A verified both CLARIN.SI records page-level: auth-free DSpace zip
bitstreams (goo300k-tei.zip 7.1 MB; IMP-corpus-tei.zip 150.31 MB), licenses
verbatim ("Creative Commons - Attribution 4.0 International (CC BY 4.0)" /
"Creative Commons - Attribution-ShareAlike 4.0 International (CC BY-SA
4.0)"), and the actual TEI of both corpora (samples downloaded, schemas
read). KEY FINDING — the overlap: same documents, complementary layers.
goo300k = SAMPLED pages with GOLD annotation ("fully manualy validated",
README sic; samplingDecl per file); IMP = FULL texts with AUTOMATIC
annotation (deposit verbatim: "a fair amount of errors"); goo300k's gold
labels do NOT exist inside IMP. Same sigil identity both sides
(ZRC_00001-1584 = Dalmatin's Biblia) → alt-editions across sources,
conventions §3, never dedupe.

Shipped: ImpTeiParser (imp-tei family; streaming Reader; block = any
element with direct <s> children; text = the historical orig surface from
<orig>/bare <w>/<pc>/<c> leaves — reg NEVER enters text; :gold mode emits
tokens {form=orig surface, reg, lemma, msd (# stripped), gloss/gloss_bibl},
:none emits nothing; #header peeks sourceDesc bibl for titles). Goo300k
adapter (xi:include page walk in root order, upstream document-global ab.N
citations, urn:nabu:goo300k:<sigil>-<year>; ZipFetch single zip). Imp
adapter (self-contained *-ana.xml, un-id'd <p>/<head> → per-tag counters
p.N/head.N — stable, deposit frozen 2015; TEXT ONLY per the silver
decision). NEW conventions §9 fold: sl ſ→s (Bohorič long s survives the
generic fold — plain downcase is not full case folding — making every
ſ-bearing word unfindable otherwise; digraph modernization deliberately NOT
folded). Gold lemma flow proven end-to-end in tests: fixture → Loader →
Indexer → passage_lemmas rows (joger attested by pristine "Iogre"; svoj by
"ſvoje, ſvojga"). Fixtures: goo300k 2 docs (1584 Biblia 2 pages incl. the
cross-page ab part="F" quirk; 1695 Sacrum promptuarium), imp 2 docs (the
1584 alt-edition trim + WIKI00290-1855 whole). Registry goo300k + imp,
enabled:false, sync_policy manual. Deferred honestly: IMP's reg
(modernized) layer could someday power a modernized-search enrichment —
out of scope here; imp25k lexicon (11356/1032) = normalization data, not
dictionary-shelf.

## P13-10 · Wiktionary-OCS dictionary (kaikki) — and the reconstruction seed  [tier: opus] [status: pending] [deps: P13-2]
## P13-10 · Wiktionary-OCS dictionary (kaikki) — and the reconstruction seed  [tier: opus] [status: done] [deps: P13-2]
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

### FIXTURE PLAN — P13-10 Phase A findings (2026-07-11, network-verified)

**OWNER-APPROVED 2026-07-11** (relayed via orchestrator): fixture plan
approved as written; the "character"-POS single-letter entries are KEPT
("yes, keep").

**Upstream (a), verified live.** kaikki.org Old Church Slavonic extract.
Download URL (per-language subdir, relative href resolved):
`https://kaikki.org/dictionary/Old%20Church%20Slavonic/kaikki.org-dictionary-OldChurchSlavonic.jsonl`
— HTTP 200, **44.0 MB**, one JSON object per LINE. Page reports **4548
distinct words** (~5.7k senses across POS breakdown). Source: enwiktionary
dump 2026-07-06, extracted 2026-07-09 (wiktextract / Ylönen). Ranged GET
(bytes 0–120000 → HTTP 206) pulled 49 clean records for shape analysis.
- **Deprecation caveat (surfaced for the owner):** the file is labelled
  "DEPRECATED, will be removed in the near future" (wiktextract issue
  #1178). It is the *postprocessed per-language* artifact the site itself
  builds on and it **serves today**; Ylönen steers bulk re-processors to
  the 23 GB raw enwiktionary extract instead. Plan: target this live URL
  (FileFetch sha-pin + conditional GET; a future 404 → clean FetchError),
  document the deprecation in the adapter note + 02-sources, and record the
  durable fallback = filter the full enwiktextract by `lang_code == "cu"`.
  enabled:false + sync_policy:manual means the owner-fired first sync
  re-confirms availability, exactly the Bosworth-Toller "frozen deposit"
  posture.

**License — verbatim, located.** On `https://kaikki.org/dictionary/`
("Copyright and license"): *"This data is made available under the same
licenses as Wiktionary - both CC-BY-SA and GFDL."* Plus the wiktextract
academic-citation request. Dual license → `license_class "attribution"`
(the SA arm governs), MCP-surface-safe. Same grant covers the
reconstruction extracts below.

**Record shape (confirmed, not assumed).** One record = one WORD × POS ×
etymology. Top-level keys observed: `word` (Cyrillic headword, e.g. царь,
о, богъ), `pos` (noun/prep/conj/pron/num/adv/particle/**character**),
`lang` ("Old Church Slavonic"), `lang_code` **"cu"**, `senses` (array;
each sense: `glosses` [array of strings], `id`, `links`, optional
`tags`/`examples`/`categories`/`raw_glosses`), `etymology_text` (plain
text — **carries the Proto-Slavic/PIE links to KEEP**, e.g. царь →
"Shortened from Proto-Slavic \*cěsařь … Proto-Germanic \*kaisaraz … Latin
Caesar"; о → "From Proto-Slavic \*o(b), from Proto-Indo-European
\*h₃ebʰi"), `etymology_templates`, `etymology_number` (homograph
disambiguator: 1/2/3), `forms` (canonical + romanization + full paradigm),
`head_templates`, `related`/`derived`/`synonyms`/`descendants`. NO
top-level record id; sense `id` is `en-<word>-cu-<pos>-<hash>`.
- **Mapping to DictionaryEntry:** one record → one entry (senses collapse
  into the body, the LSJ/B-T precedent). `headword` = `word` NFC;
  `headword_folded` = `Normalize.search_form(word, language: "chu")` (the
  EXISTING chu fold = generic downcase+Mn-strip — titlo U+0483 /
  palatalization U+0484 are `\p{Mn}`, so цар҄ь folds toward царь; NO new §9
  rule, matching CCMH/P13-2's chu layer). `gloss` = first sense's first
  gloss, best-effort nil. `body` = `etymology_text` + numbered sense
  glosses (etymology KEPT — the reconstruction seed), NFC. `citations` = []
  (Wiktionary quotes unanchored — B-T precedent).
- **entry_id (unique-per-file, stable):** `word` alone is NOT unique
  (homographs: и ×3, о/а/е ×2 in the 49-record sample, split by
  pos/etymology_number). Plan: `"<word>:<pos>"` + `":<etymology_number>"`
  when present; a residual same-word+pos+no-ety collision (to be measured
  on the full file at fixture build) gets a positional `":<n>"` suffix.
  urn `urn:nabu:dict:wiktionary-cu:<entry_id>`, back-link
  en.wiktionary.org/wiki/<word>#Old_Church_Slavonic.
- **"character" POS caveat:** single-letter alphabet entries (б, з, к…)
  are ~half the *alphabetic-head* sample but a small fraction of the 4548
  overall. They are legitimate glossed Wiktionary entries; plan = **KEEP**
  (canonical; harmless to `define`), fixture stratified so they do not
  dominate. Flag for owner if exclusion preferred.

**Fixture plan (Phase B, ~250–350 records, stratified, trimmed real
JSONL).** Selected deterministically from a full-file download (network
step, README notes retrieval date + URL + selection method):
1. multi-sense (о/prep 7 senses; царь 2) — body sense-linearization;
2. etymology-bearing with Proto-Slavic AND PIE links — the KEEP assertion;
3. Cyrillic edge cases: titlo/palatalization marks (цар҄ь), yus/jer
   letters, romanization forms, a `character` entry or two;
4. homographs (о, и, а, е) — entry_id disambiguation;
5. POS spread (noun/prep/conj/pron/num/adv/particle/character);
6. no-etymology and no-gloss records — best-effort nil paths;
7. **≥1 gospel-frequent lemma for the Phase B `--lang chu` demo** (candidate
   царь "emperor/tsar", or богъ/человѣкъ/слово) — a TOROT/PROIEL/CCMH gold
   `chu` lemma whose folded form must equal the Wiktionary folded headword
   (corpus lemma spelling to be confirmed against the fixture at build).

**Deliverable (b) — reconstruction scout (network-verified, for
improvements.md).** kaikki ships the same-licensed reconstruction extracts:
- **Proto-Slavic** `.../Proto-Slavic/kaikki.org-dictionary-ProtoSlavic.jsonl`
  — 45.4 MB, ~5195 words, `lang_code "sla-pro"`. Record shape ≈ the OCS
  shape PLUS a **`descendants`** tree: `*kara` → {East Slavic: be/ru/uk
  ка́ра; South Slavic: **cu** OCS …} with romanizations. **This is the
  crosswalk edge** — a reconstructed headword linked to attested reflexes
  across the library's languages.
- **Proto-Indo-European**
  `.../Proto-Indo-European/kaikki.org-dictionary-ProtoIndoEuropean.jsonl`
  — 11.5 MB, ~1781 words, `lang_code "ine-pro"`. (Proto-Germanic
  `gem-pro` also exists — the царь chain crosses it.)
- Both same dual CC-BY-SA + GFDL, both same "deprecated" postprocessed
  label. NO adapter this packet; the improvements.md register entry
  describes a future "reconstruction/etymology shelf" joining reconstructed
  headwords to attested lemmas via two signals already in reach: (i) the
  `etymology_text` links we KEEP in every OCS body (forward, text), and
  (ii) the structured `descendants` arrays of the Proto-* extracts
  (reverse, graph) — the comparativist join across chu/orv/ru/got.

### P13-10 findings (Phase B, 2026-07-11)

- **Full-file reality (46,091,411 B, 4,615 lines / 4,548 distinct words,
  sha256 5bd61e74…, all `lang_code "cu"`):** POS census noun 2439 / verb
  1284 / adj 385 / pron 107 / adv 101 / name 63 / **character 60** (kept,
  owner ruling) / num 40 / suffix 39 / prep 36 / prefix 26 / conj 24 /
  particle+intj 8 / contraction+det+punct 3; 2,617 etymology-bearing
  (1,797 Proto-Slavic, 279 PIE); 4 records glossless in every sense; max
  18 senses (слово). **Residual entry-id collisions measured: 10 pairs**
  (each ×2) under `word:pos[:ety]` — блажимъ:verb, блѧдь:noun, боль:noun,
  видимъ:verb:2 (collides WITH an ety number), гобина:noun, гобино:noun,
  начѧтъ:verb, ненавидимъ:verb, привести:verb, ⰿⰾⱑⰽⱁ:noun (Glagolitic) —
  resolved by the positional `:n` suffix in file order (2nd = `:2`).
- **Shipped:** `WiktionaryJsonlParser` (9th parser family; streamed
  line-by-line JSON, entry_id `word:pos[:ety][:n]`, gloss = first gloss
  string of the first glossed sense with trailing colon trimmed, body =
  etymology_text KEPT verbatim first + one line per sense (raw_glosses
  preferred — keeps "(anatomy)"-style labels; nesting path joined " — ";
  numbered only when >1 sense; glossless senses render their upstream
  `tags` so bodies are never empty), NFC; malformed line/record →
  ParseError with line number) + `WiktionaryCu` adapter (`content_kind
  :dictionary`, FileFetch single-file, :http_zip probe with metadata_url
  nil, slug wiktionary-cu, lang chu, `urn:nabu:dict:wiktionary-cu:<id>`)
  + registry enabled:false sync_policy:manual + CLI/MCP define `lang`
  gates widened to chu (Query::Define again needed ZERO changes) +
  architecture §11 fourth-occupant paragraph + 02-sources #46
  SURVEYED→READY + improvements **§1.11** (the reconstruction-shelf
  register entry from the Phase A scout).
- **Fold verdict confirmed in data:** the existing generic chu fold
  suffices — the fixture's ан҃г (titlo U+0483) folds to анг, цар҄ь's
  U+0484 strips, jers/yuses stay; no conventions §9 entry (the P13-1
  survey's open question, settled).
- **Fixture:** 278 stratified byte-verbatim lines (2,252,722 B), all 10
  collision pairs + TOROT-gold demo lemmas + all 4 glossless + 18-sense
  слово + 4-per-POS + 25 PIE + 40 Proto-Slavic + every-32nd sweep + 12
  extra homograph groups; recipe + full-file census in
  test/fixtures/wiktionary-cu/README.md.
- **Demo (scratch catalog built from the fixture; live db untouched):**
  `define богъ --lang chu` → богъ [attribution] gloss "god", body
  "Inherited from Proto-Slavic *bogъ.\ngod" — богъ is a TOROT
  Zographensis gold lemma, the define-glosses join proven in-suite too
  (`Query::Define#glosses` carries "god"/"say, speak" for богъ/глаголати);
  `define о --lang chu` → both homographs (о:character:1 the letter,
  о:prep:2 with 7 numbered senses and the PIE chain *h₃ebʰi verbatim);
  `status` → wiktionary-cu entries=278.
- Remaining owner action (P13-gate): fire `bin/nabu sync wiktionary-cu`
  (~44 MB single GET), eyeball `define` output, flip enabled. NOTE the
  upstream deprecation flag — if the URL is ever pulled, the 02-sources
  fallback (filter the full enwiktextract by lang_code) becomes a small
  follow-up packet.

## Slavic decisions record (owner, 2026-07-11)
Freising (CC BY-ND): GO — superseding ruling later same day: "BY-ND is
in-scope going forward… MCP could serve my local models which arguably have
same tool standing as dumb terminal. If we ever build some form of external
access in future it would be either excluded by design or secure
permission… (tracking permission points for future dev as we include
them)." → P13-11. Miklosich BCDH email: WAIT. Early Modern Slovenian: IN
SCOPE (→ P13-9). Wiktionary OCS: GO (→ P13-10).

## P13-11 · Freising Manuscripts (Brizinski spomeniki)  [tier: opus] [status: done] [deps: P13-9]
Owner ruling 2026-07-11: BY-ND in-scope (zero-distribution library; private
transformations permitted; ND mapped to the research_private posture —
default-excluded from MCP, per-call opt-in; any future external-access
feature adds its exclusion checkpoint). The oldest Slovene — and oldest
Latin-script Slavic — text, ~1000 CE, eZISS TEI P4 critical edition
(diplomatic + critical + phonetic transcriptions, translations, glossary;
license VERBATIM in bs.xml: "Priznanje avtorstva-Brez predelav 2.5
Slovenija" = CC BY-ND 2.5 SI — the English page's BY-SA label is wrong,
survey II verified in-file).
OWNER-APPROVED 2026-07-11 (Phase A gate): design + all-six + sl —
critical transcription = Passage#text; diplomatic/phonetic + all six
translations (slv/eng/ger/ita/lat/pol) as line-aligned sibling documents;
passage = manuscript line, display citation "BS I, fol. 78r, l. 1" in
annotations; language `sl` for transcription layers + slv translation,
per-language codes for the rest.
Two-phase, fixture gate: Phase A verifies the eZISS download path, maps
the P4 TEI (three parallel transcription layers — decide which is the
Passage text and whether the others ride as annotations or sibling docs;
P9-2 P4 experience applies), designs citations (folio/line per the
diplomatic layer?), confirms the license mapping (license string CC BY-ND
2.5 SI, license_class research_private + a permission-point note in
improvements §4.3). STOP — owner gate. Phase B: adapter (small; family
per Phase A verdict), registry enabled:false, conformance, 02-sources row
(SURVEYED-BLOCKED → READY with the ND posture documented), backlog done,
worklog (sha —). One commit, not pushed.
DONE 2026-07-11. Findings:
- **License re-verified in-file**: bs.xml `<availability status="free">`
  verbatim "Avtorske pravice za besedilo te izdaje ureja licenca Creative
  Commons Priznanje avtorstva-Brez predelav 2.5 Slovenija"
  (creativecommons.org/licenses/by-nd/2.5/si/) = CC BY-ND 2.5 SI. Audio
  © ZRC SAZU/RTVS, facsimiles © BSB München — both excluded (fetch takes
  bs-text.zip only, 7.5 MB).
- **Download-path correction over the survey**: the zips live at
  `nl.ijs.si/e-zrc/bs-text.zip` (parent dir), NOT `/e-zrc/bs/bs-text.zip`
  (404). Zip layout: single top dir `bs/`, TEI under `bs/tei/` (41 XML).
- **The structural gift**: all 9 layers share one skeleton
  div[mon]→page[folio]→line[n] with IDENTICAL line keys (228 lines/layer)
  — a perfectly aligned parallel corpus; suffix-equality alignment needs
  no stored links. Master bs.xml composes layers via external entities
  (never resolved — each layer file parses standalone) and carries the
  ZRCola charDesc glyph map (no raw PUA in text, only <g corresp> refs).
- Shipped: FreisingTeiParser (new family freising-tei; corr-over-sic,
  expan-over-abbr, scribal del-dropped/add-kept, glyph resolution, NFC),
  Freising adapter (research_private, ZipFetch), Query::Parallel freising
  work pattern + work-outranks-variants sibling refinement, MCP-exclusion
  evidence tests (real manifest wired through source→indexer→tools),
  improvements §4.3 permission point (first occupant), registry
  enabled:false/manual, 02-sources row 18 → READY, fixtures (trimmed real,
  famous opening included; demo parse bs1:1 "GLAGOLITE PO NAZ REDKA
  ZLOUEZA:" / citation "BS I, fol. 78r, l. 1").
- Deviations: language codes eng/lat per repo precedent instead of the
  Phase-A en/la proposal (users type --parallel eng; lat v/j fold);
  ger/ita/pol per upstream TEI ids. Deferred: witness variants (bsCT-mik,
  bsDT-*, bsPT-grf/rak), glossary bsLX (dictionary-shelf candidate).
- Owner action queued: fire `bin/nabu sync freising`, eyeball, flip
  enabled (CLAUDE.md checklist step 6).

## Phase 14 — The reconstruction shelf + consolidation riders (branch: phase-14; elaborated 2026-07-12)

Owner shape (2026-07-12): "Let's plan B+C+D then we'll review A more
thoroughly" — B = the reconstruction/etymology shelf (improvements §1.11,
the PIE/comparativistics axis); C = the small riders (CCMH hub witnesses,
vocab profiling, stage-2 SAA-English, CCMH txt texts); D = platform
watch-items (incremental-indexing measurement; the real-backup-disk item
remains an owner hardware decision, re-flagged at gate). A ("the corpus
reads itself") gets a dedicated thorough review as the NEXT phase's
planning input — a design-review packet at this phase's END prepares it.
Cut from enable-phase-13-sources so the flips ride. Gate-waits don't
block (dev-loop §4 addendum); worktree isolation for parallel packets.

## P14-1 · The reconstruction shelf  [tier: fable] [status: done] [deps: —]
improvements §1.11 comes due (owner axis: PIE/comparativistics —
"we didn't even start touching yet"). Two-phase, design-heavy:
Phase A (scout + design): the three kaikki reconstruction extracts
(Proto-Slavic 45.4 MB ~5,195 words sla-pro; PIE 11.5 MB ~1,781 ine-pro;
Proto-Germanic gem-pro — verify size/count), same dual CC-BY-SA+GFDL
(re-verify verbatim). Design questions to answer in an architecture
section BEFORE code: (1) are reconstructions DICTIONARY entries (the
shelf precedent: headword *bogъ, body = senses + descendants) or a new
surface? (2) the CROSSWALK: descendants arrays name attested reflexes
(cu богъ, orv богъ, got guþ…) — how do reconstruction entries LINK to
in-catalog lemmas (a derived crosswalk table f(entries, passage_lemmas)?
rebuild-safe? query surface: `define *bogъ` shows attested reflexes with
corpus counts? an `etym <lemma>` command walking attested→reconstruction→
cognate reflexes across languages?); (3) language codes sla-pro/ine-pro/
gem-pro posture (non-ISO — registry + conventions treatment); (4) which
extracts v1 ships (all three? Proto-Slavic first?). Fixture plan. STOP —
owner gate. Phase B per approval.

**OWNER-APPROVED 2026-07-12 (relayed via orchestrator): "P14-1 approved
as-is"** — all five Phase A picks stand: dictionary-shelf reuse +
dictionary_reflexes crosswalk (migration 007); ONE wiktionary-recon source
shipping all three extracts; new `nabu etym` + seventh MCP tool nabu_etym;
Wiktionary codes verbatim (sla-pro/ine-pro/gem-pro); deferred: PIE ASCII
fold (§9 followup), wiktionary-cu descendants backfill.

### P14-1 findings (Phase A 2026-07-12 network-verified; Phase B 2026-07-12)

- **Extracts verified live (extraction 2026-07-09, dump 2026-07-06):**
  Proto-Slavic 47,623,549 B / 5,431 records / 5,195 words (`sla-pro`);
  PIE 12,026,624 B / 1,905 / 1,781 (`ine-pro`); Proto-Germanic
  65,338,100 B / 5,717 / 5,552 (`gem-pro`). License verbatim identical to
  wiktionary-cu ("…both CC-BY-SA and GFDL"), same DEPRECATED label
  (wiktextract #1178), same fallback. Record shape = the OCS shape PLUS
  `original_title` ("Reconstruction:…", 100%) and `descendants` (89/95/88%
  of records) — a recursive tree {lang, lang_code, word?, roman?, tags?,
  descendants?}; branch nodes carry no word; OCS reflexes nest under
  SCRIPT children (Old Cyrillic + Glagolitic, both lang_code cu);
  proto-to-proto reflexes carry a leading asterisk ("*bogъ"); raw lines
  are NOT NFC (bʰeh₂ǵos ships decomposed). ONE malformed lang_code in
  609,691 worded nodes ("ML." — pinned in the fixture).
- **Measured crosswalk (Phase A, 564-record ranged sample vs live gold
  passage_lemmas):** record-level 64.5% sla-pro / 64.2% ine-pro / 54.7%
  gem-pro of proto headwords naming a held language link to ≥1 attested
  folded gold lemma; reflex-level ine-pro→lat 59%, →grc 40%, →san 41%,
  →xcl 40%; sla-pro→orv 46%, →sl 45%, →chu 32% (misses = Glagolitic
  script twins + non-gospel vocab); gem-pro→got 59%, →ang 26%. The
  `roman` field is LOAD-BEARING: word-only matching gives got/san/xcl 0%.
- **Shipped:** `DictionaryReflex` model value + `DictionaryEntry#reflexes`
  (ContentHash appends only-when-non-empty; pre-P14-1 shas pinned by
  test — no revision storm); `WiktionaryJsonlParser reflexes:` option
  (depth-first flatten, LANG_CODE_MAP cu→chu/la→lat/sa→san + identity,
  shape-invalid → nil language, asterisk-stripped §9 folds; cu default
  off); migration 007 `dictionary_reflexes` + Store model + loader
  persistence (citation semantics: content of the sha, replaced on
  revision); `WiktionaryRecon` adapter (ONE source, THREE dictionaries,
  three FileFetch subdirs + shared attic + UD two-phase choreography,
  three :http_zip probe targets, registry enabled:false manual);
  `Query::ReflexViews` (query-time attestation counts, shared);
  `Query::Etym` + CLI `nabu etym` + MCP `nabu_etym` (seventh tool;
  bounded attested-first cognates, one ascent hop, include_restricted
  contract, graceful pre-007 states); `define *bogъ` asterisk convention
  (strip + -pro scope + starred display + reflex views; CLI/MCP lang
  gates widened); docs architecture §12 / conventions §4+§9 /
  02-sources #50 / mcp.md seventh tool / improvements §1.11 SHIPPED.
- **Fixture:** 210 byte-verbatim records (75 sla / 61 ine / 74 gem,
  1.9 MB) — demo chains (bogъ, cěsařь / bʰeh₂g-, ǵʰutós, gʷʰew-,
  bʰeh₂ǵos, swé / gudą, kaisaraz), held-language quotas, homographs,
  no-descendants/no-etymology/glossless/grouping-only edges, Glagolitic
  script children, tagged reflexes, sweeps, + the ML. quirk line;
  deterministic recipe in test/fixtures/wiktionary-recon/README.md.
- **Demo chains proven in-suite:** богъ (chu) → *bogъ → *bʰeh₂g- (with
  grc ἔφᾰγον); guþ (got) → *gudą via the 𐌲𐌿𐌸 roman → *ǵʰutós; live-db
  counts at scout: богъ 725, цѣсарь 244, guþ 914 gold passages.
- Remaining owner action (P14-gate): fire `bin/nabu sync wiktionary-recon`
  (~125 MB, three GETs), eyeball `nabu etym богъ --lang chu` against the
  full shelves, flip enabled. Deferred riders logged: wiktionary-cu
  descendants backfill (re-revises the cu shelf — a deliberate decision),
  ine-pro ASCII fold (conventions §9 note).

## P14-2 · CCMH gospels into the alignment hub  [tier: opus] [status: pending] [deps: —]
## P14-2 · CCMH gospels into the alignment hub  [tier: opus] [status: done] [deps: —]
Registry wiring: the four CCMH manuscripts are verse-cited
(urn:nabu:ccmh:<ms>:<book>:<ch>.<verse>) — add them as nt work witnesses
via the documents: multi-book form (P11-5 precedent). Verify citation
compatibility empirically (chapter-0 headings and :b2 dup suffixes must
not pollute alignment — check how the cts-verse extractor handles them;
exclusions argued not assumed). Acceptance: align MARK 2.3 renders up to
13 witnesses incl. the four OCS manuscripts side by side (manuscript
comparison in one command — Marianus PROIEL edition vs Marianus CCMH
edition is the alt-edition showcase); registry validation green; suite+
lint green; docs; worklog (sha —).

### Findings (P14-2, 2026-07-12 — shipped)

WIRING: the four CCMH gospel manuscripts join the `nt` work in
config/alignments.yml as `documents:` cts-verse witnesses (P11-5 shape, no new
extractor), appended after the WEB witness. Labels `CCMH Assemanianus / CCMH
Marianus / CCMH Savvina / CCMH Zographensis` — the "CCMH" prefix renders them
distinguishably beside the fifth witness PROIEL `marianus`, so `align "MARK
2.3"` puts the two Marianus editions (PROIEL Cyrillic vs CCMH Helsinki
transliteration) side by side (the alt-edition showcase). The work-vocabulary
token (MATT/MARK/LUKE/JOHN) keys the CCMH per-gospel urn (…:mat/mar/luk/joh);
the passage-urn tail IS the verse, so cts-verse reads book-token + tail.

BOOK MAP (verified read-only against the live catalog, 2026-07-12 — all 16
documents non-empty): every one of the four manuscripts holds ALL FOUR gospels,
so all four books map for each. No whole-book lacunae; coverage is fragmentary
at the VERSE level (the two lectionaries are sparse — Savvina Mark 131 verses,
Assemanianus Mark 181, vs Marianus 723 / Zographensis 649), rendered honestly
"not attested" per verse (P11-9). Passage counts: Assemanianus mat 772 / mar
181 / luk 628 / joh 806; Marianus 954 / 723 / 1238 / 854; Savvina 663 / 131 /
422 / 353; Zographensis 715 / 649 / 1178 / 815.

CHAPTER-0 VERDICT — EXCLUDE, argued from the content. Only the continuous-text
codices carry chapter-0 refs (Marianus joh 19 / luk 85 / mar 47; Zographensis
joh 2 / luk 90; never the lectionaries, never Matthew). Inspection of the text
proves they are APPARATUS, not verses: Marianus `mar:0.1` = "*g*l*a!v *e*v*n*&
…" (glavy eun[gelija] — the chapter-title list), `0.2`–`0.N` the numbered
kephalaia ("o besnujuštiim" = "concerning the demoniac"); Zographensis
`joh:0.1`–`0.2` = "evaggeli-/-e ot Joana" (the incipit/title, split across two
segs). These CROSS-ALIGN spuriously — Marianus and Zographensis both number
their Luke kephalaia `0.5`, so left in they would pair chapter-titles as if
verses. So `Store::AlignmentIndexer#cts_verse_refs` now DROPS a leading
chapter-0 segment (`chapter_zero_apparatus?`). General and safe: Bible chapters
are 1-indexed, and NO existing verse-grain witness cites a chapter 0 (verified
— LXX tlg0527 and the Clementine Vulgate carry none); a verse-0 superscription
(`…:3.0`) keeps its non-zero chapter and is untouched. INDEX-side only — the
kephalaia stay canonical, addressable passages via `nabu show`/`search`.
Confirmed on the scratch index: 0 chapter-0 refs indexed for CCMH; Marianus
row counts drop by EXACTLY the chapter-0 census (854−19=835 joh, 1238−85=1153
luk, 723−47=676 mar); `MARK 0.5` looks up 0 rows.

:b2 VERDICT — NO handling needed, self-isolating. The parser's `:b2`/`:b3`
duplicate suffixes (lectionary parallels + repeated headings) occur on both
chapter-0 headings (dropped with their chapter) AND real verses (e.g.
`marianus:luk:13.11:b2`, `assemanianus:joh:21.25:b2`). For a real-verse dup the
generic `:` → `.` fold turns tail "13.11:b2" into a DISTINCT ref "LUKE 13.11.B2"
— it never false-aligns onto the primary "LUKE 13.11" (which renders the first
occurrence alone). Verified: the scratch index carries `LUKE 13.11.B2` etc. as
separate rows, and `align "MARK 2.3"` shows each CCMH witness once.

ACCEPTANCE (scratch alignment index over the READ-ONLY live catalog — no sync,
no db/ mutation; the live index picks the CCMH witnesses up at the owner's next
`nabu sync ccmh`/`rebuild`, config-only): `align "MARK 2.3"` renders all 13
`nt` witnesses, every one `:ok` on the live corpus — greek-nt, latin-nt,
gothic-nt, armenian-nt, marianus (PROIEL, Cyrillic), wscp, sblgnt, vulgate,
WEB, then CCMH Assemanianus/Marianus/Savvina/Zographensis (chu, Helsinki
transliteration). Registry validation green (loads 13 nt witnesses); the
shipped-registry pin test updated openly with the four CCMH labels + the CCMH
Marianus book map.

DEVIATIONS: one — I made the chapter-0 drop GENERAL to the cts-verse extractor
rather than CCMH-gated, because chapter 0 is universally apparatus (not a
verse) for any verse-grain edition and I verified no existing witness relies on
it; a per-witness opt-out is a one-line change if a future witness ever needs
chapter 0.

## P14-3 · Vocab profiling  [tier: opus] [status: pending] [deps: —]
## P14-3 · Vocab profiling  [tier: opus] [status: done] [deps: —]
The dropped P13-7, unchanged scope: `nabu vocab <urn-or-document>` —
lemma frequency profile of a document/range vs the corpus (distinctive
vocabulary by simple ratio, hapax list), gold shelves only, honest about
coverage (documents without gold lemmas say so). CLI + optional MCP
(argue). Small; measure before adding any index (P13-6 precedent).

## P14-4 · Stage-2 SAA-English crawl scope  [tier: opus] [status: done] [deps: —]
Config extension per the P13-4 staging design: TRANSLATION_PROJECTS
grows beyond saao/ to the other translated projects (P13-4 scout data:
rimanum 378/378, etcsri 1448/1456 + Hungarian, rinap1 88/96, dcclt
1229/4980 — verify tr-en counts for the 28 NEW projects via their
metadata at scout). Phase A: propose the stage-2 list with crawl sizes.
STOP — owner gate (sizes again). Phase B: the list + docs. NO parser
changes (new HTML shapes → census + report, the standing guard).

### Findings (P14-4 Phase B, 2026-07-12 — shipped)

OWNER-APPROVED 2026-07-12 ("Full crawl"): the complete stage-2 list as
proposed below — ~214 MB / 3,982 tr-en fragments, all eight translated
projects including dcclt's lexical lists; riao/ribo/dcclt-jena honestly
zero; English only (etcsri's tr-hun stays the flagged follow-up).

Implemented as the promised DATA CHANGE — `TRANSLATION_PROJECTS =
PROJECTS` (one line; the P13-4 crawl/census/report machinery untouched,
no parser changes — the standing new-HTML-shape guard applies at the
owner-fired sync):

- **Pin test** `test_translation_crawl_scope_is_the_full_project_list`
  asserts TRANSLATION_PROJECTS == PROJECTS (the stage-2 scope pin).
- **Fetch tests now exercise a NON-saao crawl** against real payloads:
  the P13-4 rimanum fragment fixtures (P405432/P405134) are served for
  the staged rimanum crawl; crawl-note, resumability (304 ⇒ cached), and
  breaker arithmetic assertions updated (8 ingestible post-crawl docs).
  Test plumbing, same discipline as the formats-less envelopes: the
  STAGED copies of the pristine rimanum/etcsri fixtures get their tr-en
  trimmed (rimanum → its two fragment-fixtured texts, etcsri → none; no
  fixtures invented, checked-in fixtures untouched).
- **Docs**: 02-sources ORACC row (stage-2 scope + per-project counts +
  the zero-English hubs), architecture §parallel-translations staging
  note.
- Suite 1666 runs / 26,889 assertions green; lint clean; one commit in
  the worktree, not pushed. **Owner-fired next**: `bin/nabu sync oracc`
  crawls the ~3,982 stage-2 fragments (≈ 214 MB, ~28 min polite);
  saao fragments already on disk stay cached (resumable by design).

### Phase A — STAGE-2 LIST + CRAWL SIZES (2026-07-12, opus) — OWNER-APPROVED 2026-07-12 ("Full crawl", full list as proposed)

Method: read `formats["tr-en"]` from every non-saao project's
`metadata.json` LOCALLY (all 33 canonical trees are already synced — no
network read was needed). Size = tr-en count × 55 KB (P13-4 calibration:
the typical SAA-letter fragment; see caveat). "Ingested" = tr-en ids
whose live corpusjson is present (discover yields an `-en` ref only for
those); "orphans" = tr-en ids with no live corpusjson (crawled — the
crawl fetches the whole tr-en list — but skipped-by-rule at discover and
counted in the census). The crawl DOWNLOADS the tr-en count; MB below is
therefore bytes fetched, the number the politeness/size budget cares
about.

| project          | tr-en | ingested | orphans | size (55 KB/text) |
|------------------|------:|---------:|--------:|------------------:|
| rimanum          |   378 |      338 |      40 |            20.3 MB |
| etcsri †         |  1448 |     1448 |       0 |            77.8 MB |
| rinap/rinap1     |    88 |       85 |       3 |             4.7 MB |
| dcclt            |  1229 |     1228 |       1 |            66.0 MB |
| blms             |   206 |      190 |      16 |            11.1 MB |
| dcclt/ebla       |   105 |       81 |      24 |             5.6 MB |
| dcclt/nineveh    |   440 |      440 |       0 |            23.6 MB |
| dcclt/signlists ‡|    88 |       88 |       0 |             4.7 MB |
| riao             |     0 |        0 |       0 |               0 MB |
| ribo             |     0 |        0 |       0 |               0 MB |
| dcclt/jena       |     0 |        0 |       0 |               0 MB |
| **STAGE-2 TOTAL**| **3982** | **3898** | **84** |        **~214 MB** |

† **etcsri is trilingual (Sumerian-English-Hungarian).** It carries BOTH
`tr-en` (1448) AND `tr-hun` (1441). Stage 2 crawls ENGLISH ONLY — the
`/html` fragment endpoint the crawler hits serves the English rendering,
and the machinery reads `formats["tr-en"]` exclusively. Hungarian
(`tr-hun`) stays the config-shaped follow-up P13-4 already flagged (a
second crawl target + a `-hun` document kind — out of scope here). So
etcsri is NOT English-dominant, but its English coverage is total and it
belongs in the English stage.

‡ **dcclt/signlists** also carries a single Arabic gloss (`tr-ar=1`);
negligible, English-dominant, ignored (English only, as above).

**Zero-English projects (riao, ribo, dcclt/jena) are catalog HUBS.** They
ship a `catalogue.json` but NO `corpusjson/` locally (their editions live
in out-of-scope subprojects — e.g. `ribo/babylon*`), and their metadata
`formats` block is empty (no `tr-en`). They contribute nothing to crawl
either way; `translated_ids` returns `[]` and the crawl skips them
silently.

**Size caveat.** 55 KB/text is the P13-4 SAA-letter calibration. The
dcclt* projects are lexical lists (often shorter fragments) and rimanum
is admin tablets, so ~214 MB is a conservative (slightly high) estimate
for the non-SAA mix; the outlier direction is the big compilations, not
the norm. Combined with stage 1 (saao ≈ 4.7k texts ≈ 250 MB) the full
translation scope is ≈ 464 MB — squarely inside P13-4 Phase A's 400–500 MB
projection for the whole 33-project run.

**Proposed stage-2 list (the data change, no machinery change):** extend
`TRANSLATION_PROJECTS` to the FULL `PROJECTS` list, i.e.

```ruby
TRANSLATION_PROJECTS = PROJECTS
```

The metadata `tr-en` gate makes this exact: the three zero-English hubs
are provably inert (empty `translated_ids` ⇒ skipped), so "all projects"
and "the eight projects with English" crawl byte-for-byte the same set —
and this is the natural end state (every in-scope project is now
translation-eligible; new tr-en that appears upstream is picked up for
free). One-line data change; the P13-4 crawl/census/report machinery is
untouched. Est. added crawl: **3982 fragments ≈ 214 MB**, one-time,
~28 min at the polite 0.25 s delay; ingests **3898** new `-en` documents,
**84** orphan fragments counted skipped-by-rule.

## P14-5 · CCMH txt texts — Suprasliensis + the Vitae  [tier: opus] [status: pending] [deps: —]
## P14-5 · CCMH txt texts — Suprasliensis + the Vitae  [tier: opus] [status: done] [deps: —]
The deferred half of P13-2: Suprasliensis + Vita Constantini + Vita
Methodii are .txt-only upstream (prose/folio schemes). Phase A: map the
txt structure honestly (folio markers? paragraph numbers? the catalogue's
"not properly checked" caveat applies doubly), design citations, size the
small ccmh-txt family, fixture plan; note the TOROT-Suprasliensis
alt-edition discipline. STOP — owner gate. Phase B per approval.

### Phase A — OWNER-APPROVED 2026-07-12 (fixture plan approved; Suprasliensis grain = LINE; added requirement, owner verbatim: "we need some mechanics to make the line-split words useful for all our tools, not just a dead weight decoration. Find best approach.")

Phase A facts (re-verified 2026-07-12, same Kielipankki www/ tree, same CC
BY 4.0 bundle grant covering the .txt files): every line in all three
files is `<7-digit code> <text>` — zero non-conforming lines; no folio
markers, no XML. The codes are documented by each text's own .html
description page, verbatim: Suprasliensis `part(1) folium(3) side(1:
1=recto 2=verso) line(2)` (Severjanov-edition addressing; 3 parts, folios
1-118/1-16/1-151, ≤31 lines/side); the Vitae `chapter(2)
verse-in-the-edition(3) line-in-this-file-ONLY(1) always-zero(1)` — only
chapter.verse is citable. "Not properly checked" made concrete: Supr
wraps MID-WORD (51% of 17,013 lines end in a hyphen; the Vitae 0%),
duplicate full codes 44/2/1 per file, 4 side-digit-3 slips, occasional
unmarked wraps (`(ot&ved`/`^jO` — undetectable, left alone).
Adapter-shape verdict: EXTEND Ccmh, no sibling source (same corpus,
license, base URL and manual sync policy; parser_family is a descriptive
label, not a dispatch key — goo300k reuses imp-tei, vulgate/eng-web share
usfx; the fetch was already the ORACC two-phase FileFetch aggregation,
4→7 per-text subdirs).

### Findings (Phase B, 2026-07-12 — shipped)

SHIPPED AS APPROVED + the split-word requirement. New family `ccmh-txt`
(`CcmhTxtParser`): folio-line scheme (Suprasliensis, one passage per
physical line, urn `:<part>.<folium>.<side>.<line>`, zero-padding
stripped, side digit RAW — the 3014301 slip carried verbatim) and
chapter-verse scheme (the Vitae, urn `:<ch>.<verse>`, consecutive
same-verse lines aggregated with a space; upstream is CRLF where Supr is
LF, both handled). Duplicate codes: `:b2` in document order; the
verse-grain nuance pinned by all three real cases (VC 0600200 adjacent →
absorbed into one verse; VC 1101010 non-adjacent → `11.10:b2`; VM
1700100 inside one consecutive run → absorbed, no suffix). 3 documents:
urn:nabu:ccmh:suprasliensis / :vita-constantini / :vita-methodii
(upstream stems vita_constantini → hyphenated urn slugs, the UD
slugification precedent; fetch keys/subdirs keep the literal stems).

SPLIT-WORD DESIGN (the owner requirement): **search-form rejoining plus a
`hyphen_join` annotation that two tools genuinely read** — option (a)
with the option-(b) channel earning its keep. Pristine text = the
diplomatic line VERBATIM (hyphen included). text_normalized =
Normalize.search_form over the REJOINED derivation — hyphen line: split
word completed with the next line's first token; continuation line:
orphan leading fragment dropped — recorded per passage as `hyphen_join`
({"tail" => …}/{"orphan" => …}, a line can carry both) so the derivation
is RECOMPUTABLE from the stored row alone (`CcmhTxtParser.search_source`,
a pure function). FTS, --near, snippets and golden queries see whole
words with ZERO query-side machinery — proven end to end: `search
"mOdrovati"` hits supr:1.1.1.3 (`…mOdrova-`/`ti`), the orphan line
1.1.1.4 produces NO junk hit for "ti" while the real pronoun ti
(1.1.1.24) stays findable. KWIC honesty: Concord retries a missed
keyword against the rejoined haystack with every appended-tail character
mapped to the hyphen/EOL display index → the highlight is exactly the
visible `mOdrova-`, never fabricated display text (concord tests pin
keyword, contexts, and the no-tail fallback). The conformance pin was
GENERALIZED, not weakened: new optional `conformance_search_source` hook
(default: pristine text) keeps the guarantee that text_normalized is
always the minted per-language fold of a recomputable source;
passage.rb's contract comment updated to match. Joins cross folio/side/
collision seams (file order = textual flow); a document-final hyphen
line keeps its fragment; an all-orphan line falls back to the raw fold
(text_normalized must not be empty). Documented as a PARSER-SCOPED rule
in conventions §9 (argued: ASPR/Freising/GRETIL lines don't hyphenate,
the gospels' XML doesn't either — corpus layout, not a chu property; the
annotation contract is reusable by a future diplomatic source).

Fixtures: 3 byte-identical line-range trims (supr 72 lines — folio 1
recto+verso head, BOTH 1042114-19 collision runs incl. the hyphen join
straight across that seam, the side-3 slip; VC 41 lines — incipit,
ch1, all three duplicate-code behaviors; VM 17 lines — control), ranges
cut at non-hyphen/verse boundaries so the trims mint no fixture-only
joins. README + manifest extended (schemes verbatim, quirk table,
retrieval 2026-07-12). Alt-edition discipline in 02-sources rows 19+30:
TOROT / CCMH / obdurodon(queued) Suprasliensis = THREE distinct
editions, never dedupe any pair (conventions §3). Registry untouched —
ccmh is already enabled; the owner's next `nabu sync ccmh` fetches the
three txt files and adds 3 docs (~17.5k passages, mostly Supr lines).
Suite 1693 runs / 27,635 assertions green, lint clean; 21 parser + 28
adapter tests incl. conformance over all 10 fixture docs + 3 concord
tests. Demo: urn:nabu:ccmh:suprasliensis:1.1.1.3 = `)i do s&mr)$ti . ne
dobr@ mOdrova-` → normalized `)i do s&mr)$ti . ne dobr@ modrovati`;
concord "mOdrovati" keyword = `mOdrova-`.

## P14-6 · Incremental indexing — measure, then decide  [tier: opus] [status: pending] [deps: —]
improvements §4.2 "when it hurts" checkpoint. Phase A (measurement, no
code): instrument the real cost — time a parse-only sync's index rebuild
at the current ~3.6M passages (per-phase breakdown: FTS insert, lemma
table, alignment refs), project the curve to 5M/10M, and identify the
incremental design IF warranted (per-source reindex? dirty-document
tracking? FTS5 delete+insert granularity?). Report with numbers. STOP —
owner decides implement-now vs re-check-later (the honest answer may be
"doesn't hurt yet"). Phase B only if commissioned.

### Phase A — MEASUREMENT REPORT (2026-07-12, opus)

Method: copied the live catalog.sqlite3 (3.9 GB) to scratch (APFS clone),
ran the PRODUCTION `Store::Indexer` / `AlignmentIndexer` code with per-phase
monotonic timers around each seam (reused `index_row`, `lemma_rows`,
`live_passages`, `AlignmentIndexer.rebuild!` verbatim — only timing added).
Apple Silicon, warm page cache, 2 full runs + a 5-point FTS scaling probe.
The instrumented rebuild reproduced the live index EXACTLY (3,757,019 FTS
rows / 2,513,786 lemma rows / 130,543 alignment refs), confirming the copy
and the timed path are faithful. Live db untouched (read-only throughout).

**Current live corpus (read-only counts):** 3,757,019 live passages · 84,423
live documents · 21 sources · 383,014 passages carry lemma annotations
(10.2%) · 79,890 carry citation_part.

**Current per-sync reindex cost — MEASURED (~70 s wall, +~4 s ruby startup):**

| phase | time | share |
|---|---|---|
| DDL (drop+create FTS/lemma/align tables) | 0.002 s | — |
| catalog stream / iterate (`live_passages`) | 6–10 s | ~11% |
| **FTS5 insert** | **~36–37 s** | **~53%** |
| lemma build (JSON parse + Normalize.fold) | ~11.7 s | ~17% |
| lemma insert | ~11.6 s | ~16% |
| alignment refs (P11-3, whole phase) | ~1.3 s | ~2% |
| **TOTAL** | **~68–71 s** | |

FTS5 insert dominates (~half). Lemma build+insert together ~23 s (~33%).
Alignment is noise (~1.3 s — it walks only registry witnesses, not the
corpus). NOTE: there is NO ANALYZE / FTS5 `optimize` / merge step in the
path — every rebuild produces a fresh, clean (if un-optimized) index. That
matters for the incremental trade-off below.

**Growth curve — EMPIRICAL (FTS build over first N passages by id):**

| N | FTS insert | marginal |
|---|---|---|
| 1.0M | 15.8 s | — |
| 2.0M | 22.9 s | ~7.1 µs/row |
| 3.0M | 31.8 s | ~8.9 µs/row |
| 3.76M | 37.3 s | ~7.2 µs/row |

FTS marginal cost is ~7–9 µs/row and creeps upward with N (the FTS5
segment-merge log factor): **near-linear, mildly super-linear**. Lemma cost
tracks the ANNOTATED-passage count (currently 383k → 2.5M rows), NOT total N.
Alignment tracks registry witnesses, NOT N. So the extrapolation basis,
stated honestly: overall ≈ **linear in total passages, FTS-dominated, with a
gentle super-linear FTS creep**; lemma/alignment are decoupled from N.

**Projection to 5M / 10M passages** (two scenarios, because lemma growth
depends on whether the gold treebanks grow — they are a finite scholarly
resource, so scenario B is the likelier one):

| | 3.76M (now) | 5M | 10M |
|---|---|---|---|
| A · annotated fraction held at 10% | ~70 s | ~90 s (1.5 min) | ~180 s (3 min) |
| B · treebanks bounded (lemma flat ~23 s) | ~70 s | ~84 s (1.4 min) | ~140 s (2.4 min) |

**Where the pain sits.** Two distinct axes:
1. *Absolute time* — ~70 s now is annoying-but-tolerable for an interactive
   operator; it crosses ~2 min around 6–7M passages, ~2.5–3 min at 10M.
2. *Amplification (the real waste)* — the reindex is corpus-wide but is paid
   on EVERY per-source sync. Per-source live passage counts: papyri-ddbdp
   921k (24.5%), gretil 703k, imp 405k … down to ccmh 11k (0.3%), freising
   2,037 (0.05%). A one-source ccmh sync pays the full ~70 s to rebuild
   3.76M rows — a **~340× over-index**. Even syncing the LARGEST source
   re-does 75% of unrelated work.

**Incremental design options (IF commissioned — sketch + risk):**
1. **Per-source reindex** (improvements §4.2's own sketch): delete the
   source's rows (by its document-urn→passage set), reinsert just that
   source. Win: ~4× (papyri worst case) to ~300× (small sources). Coarse,
   correct boundary — a whole source is recomputed, so NO per-document
   dirty-tracking bug surface. Consistency risk: passage_ids are re-minted
   per load, so the delete must key on the source's document urns (the
   FTS/lemma/align tables carry urn UNINDEXED — usable), and it must run
   inside the same reindex step, after the load. Modest.
2. **Dirty-document tracking**: the Loader already knows added/revised/
   withdrawn docs per run — reindex only those. Finest granularity, biggest
   win for a 1-doc fix. Risk: the dirty set must be EXACT; a missed doc = a
   silently stale index (wrong search results, not a crash) — this forfeits
   the rebuild-everything correctness guarantee, and reindex currently sits
   OUTSIDE the RunRecorder transaction on purpose, so coupling the dirty set
   to the catalog write is new plumbing.
3. **FTS5 granular delete+insert** (tombstone deletes on the shadow table):
   accumulates tombstones/segments and REQUIRES a periodic `('optimize')`
   maintenance step the codebase does not currently have. Trades the most
   simplicity (the clean-per-rebuild property) for the least additional gain
   over option 1. Not recommended as a first move.

The current rebuild-everything is PROVABLY correct: index = f(catalog),
recomputed from scratch, drift impossible. Every incremental option adds a
dirty-set obligation whose failure mode is SILENT. Given the corpus is the
permanent asset and search correctness is load-bearing, the bar is high.

**RECOMMENDATION: re-check-at-N, do NOT implement now.** At ~70 s the full
rebuild is annoying-but-tolerable and provably correct; §4.2's own verdict
("do it when the wait annoys, not before") holds and the near-linear curve
gives clear runway. Concrete re-check trigger: when the interactive reindex
crosses **~2 min (≈6–7M passages)**, OR sooner if per-source sync cadence
rises enough that the ~340× amplification becomes the daily annoyance rather
than the absolute time. WHEN commissioned, do **option 1 (per-source
reindex) first** — it captures most of the win, keeps a coarse correctness
boundary, and needs no FTS5 tombstone management; reserve option 2 for later,
skip option 3.

**MEASUREMENT REPORT — OWNER DECISION 2026-07-12: "No urgency with reindexing, mark to-do for later stages" → RE-CHECK-AT-N accepted (revisit at ~2-min reindex / ~6-7M passages; per-source reindex first when commissioned)**

## P14-7 · "Corpus reads itself" design review  [tier: fable] [status: done] [deps: P14-1..6]
The owner wants A reviewed thoroughly before committing. NOT an
implementation packet: a design document (docs/intertext-design.md) for
the Phase 15 decision — intertext engine (§1.1), time/place axes (§1.4),
fragment search (§1.5), links table (§1.8) — each with: precise algorithm
options (n-gram shingling parameters for HIGHLY inflected languages —
lemma-grams vs surface-grams, the cross-language quotation problem
LXX→NT→Fathers), storage/index cost projections AT THIS CORPUS SIZE
(measured, not guessed), staged shipping plan, what the cluster could
later add (embeddings-based paraphrase detection vs the symbolic core).
Ends with a recommendation menu for the owner. Live corpus read-only
experiments allowed (timing probes, n-gram density samples).

Findings: docs/intertext-design.md delivered under the owner-endorsed
2026-07-12 persona frame (interactive-first), all numbers measured live.
The headline finding inverts §1.1's architecture: NO materialized n-gram
table is needed — per-gram FTS phrase probes over the EXISTING index
answer `parallels <urn>` in 1–111 ms at 3.76M passages (Odyssey 1.1 →
Polybius; Matt 4:4 → LXX Deut 8:3 once elision marks are stripped — a
measured U+02BC/U+2019 fold gap; Thucydides 1.9.2 → Dionysius of
Halicarnassus at 57/117 shared grams). Cognate-in-parallel measured: 349
NT verses where got and chu attest reflexes of the same proto-root via
one proto-to-proto hop (31 roots, 1.4 s staged — needs two indexes +
a tiny closure table; contextually matched: salt/соль, malan/млѣти).
Collatable hub surface: grc 7,643 / lat 6,974 / chu 3,764 verses with
≥2 same-language witnesses — but the fold does not bridge Cyrillic vs
Helsinki ASCII, so collation diffs raw tokens within script family only.
Date axis generalizes beyond HGV (63,925/66,261 = 96.5% machine-dated)
to ORACC (96.6% regnal/period), goo300k/IMP (years in urns), TOROT
chronicle annal divs; ≤100k rows, <20 MB. Fuzzy trigram index measured
at 5.8–6.6 B/char → documentary scope 250–270 MB, whole corpus 3.6–4.1 GB
(scope flag vindicated). Formula miner needs zero schema (Homer/ASPR
slices mined in 0.6 s: ὣς ἔφαθ' 72×, "hwaet ic hatte" 16×). Links table
= batch-mode output format only, deferred to the first batch producer.
Menu: P15-1 parallels (headline) → date/place → cognates → collation;
fuzzy can wait; embeddings-tier paraphrase/cross-language allusion waits
for the cluster, gated on golden sets the symbolic packets generate.

## P14-8 · Proximity search  [tier: opus] [status: done] [deps: —]
Owner-promoted 2026-07-12 from the end-user analysis: proximity search is
the TLG-style daily-use feature every persona touches (λόγος within N
words of θεός, lemma-aware) — more basic than the intertext engine and
its building block. Design-first, measure-first (P13-6/P14-3 precedent).
Design questions: CLI shape honoring the compact-CLI preference (e.g.
`search A --near B [--window N]`, composing with the existing --lemma and
--morph flags where honest — a lemma-aware side means expanding lemma →
attested surface forms via passage_lemmas before the FTS NEAR, argue the
mechanics and the window semantics FTS5 NEAR actually gives on folded
search forms); cross-passage adjacency is OUT (passage = the unit, said
honestly); result rendering shows both terms highlighted. Collocation
statistics are NOT this packet (they ride the Phase 15 menu) — but don't
paint them out. MCP: extend nabu_search args. Measured timings on the
live index before any schema addition (expect none needed). Tests incl.
at least two languages + a lemma-expanded case. README command row,
mcp.md, backlog done + findings, worklog (sha —).

Findings:
- **CLI shape:** `search A --near B [--window N]` exactly as sketched —
  `--near` rides the existing `search` command, composing with `--lemma`
  (the lemma becomes the anchor) and `--lang`/`--license`/`--limit`.
  `--window` defaults to 10 (FTS5's own NEAR default), 0 = adjacent. New
  `Query::Proximity` (lib/nabu/query/proximity.rb) shares Search's
  Result/snippet/bm25 machinery and CatalogJoin, so rendering is plain
  search rendering — both terms bracketed because both are NEAR phrases.
- **NEAR semantics (probed on SQLite 3.53, not assumed):** `NEAR(a b, N)`
  matches when ≤ N tokens sit BETWEEN the phrases, order-independent
  (N=0 = adjacent; a gap-k pair needs N≥k). The window counts FOLDED
  tokens (conventions §9): honest per-word for grc/lat/…; documented
  caveat for akk/sux, where sign-joins/determinatives fold to spaces so
  one transliterated word spans several tokens (window reads tighter).
- **Fold-both-sides carried into NEAR:** each side folds to the
  Normalize.query_forms union; the MATCH is the OR of NEAR clauses over
  the cartesian product of the two sides' variants (the P6-4 argument
  applied per side — cannot miss; the generic variant keeps no-rule
  languages findable).
- **Lemma-aware anchor:** `--lemma X --near B` expands X via
  passage_lemmas to its distinct attested surface forms, each folded by
  its passage language, then each is a NEAR phrase. Live expansion counts
  are naturally bounded (folding collapses accent variants: ὁ→25,
  εἰμί→99, λέγω→140 forms); MAX_LEMMA_FORMS=400 guards FTS expression
  limits only. Homograph honesty documented: an attested surface form
  may, in some passage, spell a DIFFERENT lemma's token — surface
  expansion cannot tell (no token offsets in the FTS index).
- **Measured live (3.6M-passage index, read-only, no schema addition —
  as expected):** κύριος NEAR θεός w5 grc → top-20 in 43–113 ms; λόγος
  NEAR θεός w5 → 24–37 ms, surfacing John 1:1 AND the P.Oxy. 8.1151
  amulet quoting it (the intertext promise already visible); --lemma
  λέγω --near κύριος w3 → 280 NEAR clauses, 95–284 ms, surfacing the
  prophetic formula τάδε λέγει κύριος; pathological ὁ NEAR θεός w3 →
  79 ms. Lemma expansion itself ~170 ms for λέγω.
- **Out of scope (said honestly):** cross-passage adjacency (passage =
  the unit; tested); --morph with --near (clear usage error both
  surfaces; clean follow-up); collocation statistics (Phase 15 menu —
  proximity returns the raw hit material such counts would aggregate);
  FTS operators inside proximity terms (each side is phrase-quoted, so
  `*`/AND/OR are literal — operator queries stay with plain search).
- MCP: nabu_search gains `near` + `window` (clamped 0–50, default 10);
  near+morph → InvalidArguments. Tests: query/proximity_test (10: grc +
  lat folds, lemma-expanded suppletive εἶπε, window boundaries, order
  independence, filters, cross-passage honesty), cli_test (5, real UD
  fixture), mcp/tools_test (3). Suite 1598/26,593 green, lint clean.

## P14-gate · Phase 14 gate  [tier: orchestrator] [status: pending] [deps: P14-1..7]
Full-diff, library.md refresh (reconstruction shelf section + the
post-ORACC-sync numbers), README truthfulness, PR, owner queue (syncs:
reconstruction extracts, stage-2 crawl, ccmh re-sync for txt texts; the
ud re-sync for Ruthenian if still pending), flips, RE-FLAG the real
backup disk (D item — owner hardware decision), sticky alarm LAST.

## P14-9 · ORACC sync defects: blms collisions + anchor edge  [tier: opus] [status: done] [deps: —]
Defect packet (orchestrator census of the owner's 2026-07-12 big sync:
+10,899 docs / 30 projects landed, !20): (1) 19 × "duplicate passage urn"
all in blms (bilingual literary) — census the real shape first (parallel
Sumerian/Akkadian versions repeating line labels? column duplication?),
then collision-tolerance per the house precedent (:b2 positional
suffixing, never quarantine, never merge — GRETIL/ccmh pattern) IF the
census supports it; if the duplicates are a different animal, report.
(2) 1 × saao-saa08:P336145-en "prose unit anchored at X resolves to no
line-start row" — inspect the actual HTML + corpusjson pair; fix the
anchor fallback honestly (reattach-forward exists — why did it miss?) or
skip that unit loudly. (3) Verify the 3 projects that yielded no docs
(33 registered, 30 with docs — expect saas2-class catalog-only or empty
corpusjson; confirm via discovery-accounting/canonical inspection and
document; if a project's zip landed but discover found nothing
UNEXPECTEDLY, that's the P11-7 loud-zero class — investigate).
FROZEN-URN GUARD standing: parse-only oracc sync must show all
previously-loaded docs =skipped; quarantines 20 → ~0. Fixtures: trimmed
real slices from canonical/oracc/blms + the saa08 pair (no network).
Suite+lint green; docs (02-sources note); backlog done; worklog (sha —).
One commit, not pushed.

Findings (census FIRST, per item):
- **Census corrected the orchestrator's framing.** The 20 quarantines (event
  `quarantined`, at ≥ 2026-07-12) are 19 "duplicate passage urn" + 1 anchor —
  and the 19 dups are NOT all blms: **7 blms + 12 saao-saa08**. Both dup groups
  are ONE defect class, so one fix covers both.
- **(1) The duplicate shape is the P11-7 sentence-label fallback, not column
  duplication.** blms (bilingual literary) interleaves a Sumerian line (own
  label "o 1'") with its Akkadian interlinear translation, which upstream ships
  as a LABEL-LESS `line-start`; P11-7 falls it back to the enclosing sentence
  label "o 1'" → collision with the Sumerian line. saao-saa08 omens are the same
  animal with a whole-text range sentence ("o 1 - r 6"): several label-less
  line-starts all fall back to it. These are DISTINCT physical lines (different
  words/languages), so the house `:b2`/`:b3` positional suffix in document order
  is exactly right (GRETIL/ccmh P9-4c precedent) — never quarantine, never merge.
  Fix: `OraccJsonParser#disambiguate_suffixes`. Clean tablets keep byte-identical
  urns (only repeated suffixes are touched) → frozen guard holds.
- **(2) saao-saa08:P336145-en: the anchor is a TRAILING unlemmatized line.** The
  final prose unit anchors at row P336145.13 — a `nonl-final` "traces of a name"
  row (print label "(r 3)") the corpusjson never mints (no readable signs; its
  line-starts stop at r 2). Reattach-forward MISSED because it only looks forward
  and this row is the LAST content. Fix: `anchor_label` reattaches BACKWARD to
  the last line-start (r 2) when none follows — prose kept, and the suffix still
  exists in the tablet for `Query::Parallel`. Not "skip loudly" — backward
  reattach is the honest keep.
- **(3) The 3 zero-doc projects (riao, ribo, dcclt-jena) are PROXY corpora, an
  EXPECTED zero — but the accounting was crying wolf.** Each ships `corpus.json`
  `type:corpus` with a `proxies` map (riao 1941, ribo 391) and NO `corpusjson`:
  their texts are proxies hosted in out-of-scope sibling subprojects (the
  PROJECTS note already says riao/ribo are "top level only"). NOT the P11-7
  loud-zero class. But `discovery_skips` was flagging all three as
  "unpack/layout error (unrecognized)". Fix: `proxy_corpus?` recognizes them as a
  benign skipped-by-rule, so `unrecognized` drops 3 → 0.
- **Acceptance (parse-only re-sync, loader-idempotent):**
  `oracc  parse-only  +20 added  ~0 updated  =17775 skipped  -0 withdrawn
  !0 errored  indexed 3757413 passages` · `discovery: 17795 selected ·
  415 skipped-by-rule · 0 unrecognized`. Quarantines 20 → 0; all 17,775
  previously-loaded docs =skipped (frozen guard); 0 unrecognized (was 3).
- Fixtures: trimmed real slices in `test/fixtures/oracc_p14_9/` — blms P345480
  (16 sentence children), saa08 P336559 (36), the P336145 corpusjson (line-start
  skeleton) + html pair, riao proxy corpus.json (3 proxies). TDD: three failing
  tests written first, then the three fixes.

## P14-10 · etym usability: bare proto forms + ASCII typability  [tier: opus] [status: done] [deps: P14-1]
Owner defect report (2026-07-12): (1) `etym bʰewgʰ` fails ("no
reconstruction names…") even though `etym bog` DISPLAYS that very form —
unstarred input must FALL BACK to reconstruction-headword lookup when the
reflex path misses (asterisk optional; trailing-hyphen tolerant — root
entries are stored `bʰewgʰ-`; try the -pro shelves after the attested
path). (2) `etym *bʰewgʰ` dies in zsh globbing before nabu runs — error
messages and docs must show the quoted form (`etym '*form'`), and the
bare-form fallback makes the star mostly unnecessary. (3) Ship the
deferred PIE ASCII fold: modifier letters (ʰ→h, ʷ→w, any others present
in the three extracts — census the actual headword character inventory
first) folded in the -pro shelves' §9 rule so `etym bhewgh` works;
combining marks already strip. Fold change touches only the three
reconstruction dictionaries (synced 2026-07-12) — re-fold via parse-only
sync, frozen elsewhere. Tests: bare-form fallback (hit + updated
miss-message), hyphen tolerance, ASCII lookup for a ʰ/ʷ-bearing root,
define '*' parity. Suite+lint green; docs (README/mcp.md examples use
quoted forms); backlog done; worklog (sha —). One commit, not pushed.

## P14-11 · etym/define --long  [tier: opus] [status: done] [deps: P14-10]
Owner UX (2026-07-12): "I commend the terseness BUT there needs to be
--long form that expands on these '…46 more'." Add `--long` to `etym`
and `define` (compact stays the default per the house compact-CLI rule):
expands every truncated list in the renderers — the "other reflexes
(not attested here)" cap, attested-reflex caps, any "and N more"
elsewhere in these two commands (census the renderers; expand ALL of
them under the one flag, grouped by language where lists are long).
MCP: leave the bounded contract as-is (honest totals already present;
a conversational surface should stay capped) — note that choice in
mcp.md if it names caps. Tests: capped default + expanded --long for
both commands. README rows updated. Suite+lint green; backlog done;
worklog (sha —). One commit, not pushed.

## P14-12 · Upstream drift visible in status  [tier: opus] [status: done] [deps: —]
Owner (2026-07-12): "Right now I have no idea IF the upstream even
changed, for most sources. A reasonable update would be to indicate the
upstream changes in status, so that update remains an informed decision."
Design: health --remote already computes per-source drift (git ls-remote
HEAD vs pin; HTTP Last-Modified vs zip/file pin) but discards it after
rendering. (1) PERSIST the probe verdicts: a per-source probe record in
the history ledger (db/history.sqlite3 — survives rebuilds; new small
table via the ledger migration track: slug, checked_at, drift verdict,
license verdict, detail) written by every health --remote run. (2) STATUS
renders a compact upstream column from the cache per the compact-CLI
rule: nothing extra when current and recently checked is WRONG — the
owner wants signal — so: `up=ok(2d)` / `up=BEHIND(2d)` /
`up=?(never)` / `up=stale(30d)` — pick exact vocabulary honoring
terseness (BEHIND loud, ok quiet, age always shown; argue the shape in
one paragraph and match the existing status row style). frozen-policy
sources render up=frozen (no probe expected). (3) `status --remote` runs
the probe inline first (same code path as health --remote), then renders
— the one-command informed-decision flow. (4) health --remote output
unchanged apart from now also persisting. MCP nabu_status: add the
cached drift fields (it's a status surface; bounded, no live probing
from MCP ever — note that). Tests: probe persistence, cache rendering
incl. never-probed and stale-cache, frozen handling, status --remote
wiring (WebMock/stub probes). Docs: ops.md (the informed-update flow),
README status row. Suite+lint green; backlog done; worklog (sha —).
ONE commit in your worktree, do NOT push.

COLUMN SHAPE (chosen): the up= cell sits immediately after the policy
column, ljust-aligned to a computed width, before the free-form counts
and last_run descriptors. It pairs with policy because both describe the
source's sync disposition — policy is HOW we pull, up= is WHETHER
upstream moved since we last did; read together they answer "should I
sync this now?", which is the informed-decision point. counts/last_run
stay the trailing free-form descriptors they already are. Vocabulary:
drift current+fresh → up=ok(Nd); drift behind → up=BEHIND(Nd) always
(loud; staleness never softens an alarm); drift current but older than
14d → up=stale(Nd) (an "ok" too old to trust — the dangerous
reassuring-but-stale case); drift indeterminate (unknown/never_synced/
multi, incl. a gone/unreachable upstream whose drift can't be computed)
→ up=?(Nd); no cache row → up=?(never); frozen-policy source → up=frozen
(cache ignored). Age is floor-days, always shown. Sample row set:
  perseus     on   live    up=ok(2d)      docs=1320 pass=98211 last 2026-07-10 12:03 ok (+3 ~1 -0 !0)
  ud          on   live    up=BEHIND(2d)  docs=210 pass=44120 last 2026-06-28 09:11 ok (+0 ~0 -0 !0)
  oracc       off  manual  up=stale(31d)  docs=88 pass=9004 last 2026-06-01 07:40 ok (+0 ~0 -0 !0)
  bosworth-t  off  manual  up=frozen      entries=42000 last 2026-05-02 03:00 ok (+0 ~0 -0 !0)
  ccmh        off  manual  up=?(never)    docs=0 pass=0 never synced
Ledger schema (db/ledger_migrate/002_create_source_probes.rb, table
source_probes): id pk; source_slug (unique index); checked_at DateTime;
drift String (current|behind|never_synced|unknown|multi); license String
(baseline_recorded|unchanged|changed|unchecked); detail String nullable.
One row per source (upsert per run) — a cache, not history (runs already
hold history). MCP nabu_status: each source row gains an `upstream`
object {checked_at, drift, license, detail} (or {drift: "never_probed"}
when uncached) plus a note that these are the CACHED verdicts of the
last health --remote / status --remote run — MCP never probes live.

## P14-13 · blms translation anchors  [tier: opus] [status: done] [deps: P14-9]
Defect (orchestrator census of the owner's 2026-07-12 stage-2 crawl:
+3,884 -en docs, !13 — ALL 13 in blms, all "prose unit anchored at X
resolves to no line-start row"). The P14-9 backward-reattach fixed the
trailing-anchor case; blms (bilingual interleaved, the P14-9 collision
oddball) evidently has anchors resolving in NEITHER direction. Census
the 13 actual HTML+corpusjson pairs first (canonical/oracc/blms/) —
what do the anchors point at? (Interlinear structure? refs into the
OTHER language's lines? :b2-suffixed labels the -en anchor map misses
post-P14-9?) Fix per evidence: extend the anchor fallback honestly OR
skip the unit loudly (never quarantine the whole -en doc for one unit
if the rest anchors — argue the grain). FROZEN GUARD: parse-only oracc
sync =all-previous skipped, quarantines 13 → ~0. Fixture: one trimmed
real blms pair. Suite+lint green; backlog done; worklog (sha —). One
commit, not pushed.

## Phase 15 — The corpus reads itself (branch: phase-15; elaborated 2026-07-12)

Owner: "Merged #18, plan Phase 15 with parallels headline" — adopting
docs/intertext-design.md's recommendation menu as commissioned. Every
packet's algorithms, costs, and demo targets are ALREADY DESIGNED with
measured numbers in that document — packets implement, they don't
re-design (deviations from the design doc get argued openly, not
silently). Gate-waits don't block; worktree isolation for parallels...
parallelism as needed; reviews sequential.

## P15-1 · parallels <urn> — the interactive intertext engine  [tier: opus] [status: done] [deps: —]
The headline (design doc §1): passage-anchored quotation/allusion
finding, query-time over the existing FTS index — NO new schema (the
design's measured verdict: per-gram probes 1–111 ms/passage). Surface-
gram engine + rarity scoring + document dedupe + the elision-strip gram
builder (the measured U+02BC-vs-U+2019 fold gap across editions); CLI
`nabu parallels <urn> [--limit]` honoring compact-CLI (per-hit: urn,
shared-gram evidence, score); MCP nabu_parallels (eighth tool, bounded).
Riders per the design: the passage_lemmas(urn) index it identified, and
the rare-lemma co-occurrence second signal; the formula miner rides ONLY
if the packet stays light (else it's P15-5). GOLDEN QUOTATION TESTS
seeded from the design doc's live probes: Odyssey 1.1→Polybius, Matt
4:4→LXX Deut 8:3, John 1:1→the Fathers (+ the P.Oxy amulet). Suite+lint
green; docs (README persona rows gain the command, mcp.md, architecture
§13 short design record pointing at intertext-design.md); backlog done;
worklog (sha —). One commit, not pushed.

Findings:
- **Zero new schema, as the design measured.** `Query::Parallels`
  (lib/nabu/query/parallels.rb) probes the anchor's folded 4-word grams as
  FTS5 phrase MATCHes against the existing `passages_fts`; candidates scored
  by shared-gram count × rarity (1/df, df from each probe's hit count). All
  three live goldens reproduced through the production code: Odyssey 1.1 →
  Polybius 12.27.10 (top, score 1.48, the whole proem as one evidence span);
  John 1:1 → Clement (3 loci), the perseus John edition, other Fathers;
  Matthew 4:4 → Origen, the PROIEL≡UD NT duplicates, corroborating perseus
  Matthew (9 grams), **LXX Deut 8:3 (9 grams), and Philo**.
- **Elision fold is load-bearing (design rider i).** Strip U+02BC (SBLGNT,
  a letter to unicode61) and U+2019/ASCII (First1K/Swete, punctuation) at
  gram-build. Measured: LXX Deut 8:3 shares 3 grams with Matt 4:4 unstripped,
  **9 stripped** — tying canonical Matthew, exactly the design's number. A
  unit test pins that the two encodings' gram tokens are equal after strip.
- **Document dedupe + exclusion argued (rider ii).** One hit per document
  (best passage representative, `loci` counts siblings); only the anchor's
  own document excluded. Translations self-exclude — surface grams are
  language-locked folded tokens, so no cross-language rule is needed; a
  same-language other edition of the anchor's work is a *wanted*
  corroborating hit (the design's Matt probe wants "canonical Matthew" to
  appear). Cross-source identical texts (PROIEL greek-nt ≡ UD greek-proiel)
  stay two hits — we hold no cross-source work identity — stated honestly.
- **Second signal shipped (option c).** `lemma_echoes`: passages sharing ≥2
  of the anchor's RARE lemmas, rarity-weighted — fires only when the anchor
  is gold-lemmatized (else one cheap query, then skip). Measured live 36 ms
  on PROIEL Matt 4:4 (design's 18 ms + the anchor lookup) once the index was
  built; it surfaced στόμα/ἐκπορεύομαι echoes ("proceeds from the mouth").
- **passage_lemmas(urn) index rider landed** in `Store::Indexer`
  (derived-of-derived, rebuilt with the table, NOT a numbered migration —
  migrations own the catalog only). Built on the live db directly (sanctioned
  index build, no reparse): **633 ms, +~44 MB** (design estimated 30–45 MB),
  index name matches a fresh rebuild's. Unblocks P15-3 cognates too.
- **MCP `nabu_parallels`** is the eighth tool: bounded (default 10/max 50),
  license-labeled + source on every hit, `include_restricted` contract,
  graceful "rebuilding" degradation, unknown-urn note.
- **`--long` from birth** (mid-flight owner rule 2026-07-12): compact elides
  evidence spans / shared lemmas with a "… and N more (--long)" tail; `--long`
  expands them untrimmed. Tested both modes.
- **Golden split, argued:** the design's live goldens are a PAIR relation,
  and the trimmed golden fixture corpus holds no quotation pair (proiel =
  Cicero, ud = Greek NT; no same-language duplicate work) — so they live as
  fixture-store unit tests seeded with the REAL probe texts (deterministic,
  offline, a sharper golden than corpus membership), not in
  golden_queries.yml (single-passage membership). Stated in the test header.
- **Formula miner (§5) did NOT ride** — the core + second signal + index +
  MCP + goldens + docs is a full opus packet; the gram builder is shared, so
  it stays the smallest standalone packet, **P15-5**.
- **Timings (live, machine under load):** John 1:1 surface parallels tens of
  ms warm; the elision-strip Matt run ~40 ms; the design's per-gram FTS
  budget (1–111 ms/passage) holds through the production catalog-join path.

## P15-2 · Date/place axis, part 1  [tier: opus impl, fable review of the date model] [status: done] [deps: —]
Design doc §3: document_axes migration (document-level date ranges +
place names; the fable reviewer checks the DATE MODEL specifically —
BCE handling, ranges vs points, uncertainty); extractors for HGV
(63,925/66,261 machine-dated, ddb-hybrid↔urn join verified) +
goo300k/IMP (years in urns); `search --from/--to [--place]`;
`vocab --by-century` as the linguist payoff. Part 2 (ORACC regnal
mapping + chronicle annals) is a named follow-on, NOT this packet.
Two-phase: the migration+model design gets the fable review BEFORE the
extractors land (an internal review, not an owner gate — owner gates
only if the model raises a scope question).

### DATE MODEL DESIGN (pre-implementation, for fable review)

**Measured disk reality (2026-07-12, read-only probes).**
- HGV metadata lives at `canonical/papyri-ddbdp/HGV_meta_EpiDoc/HGV{n}/{m}.xml`
  (66,261 files). Each carries `<idno type="ddb-hybrid">bgu;3;994</idno>` →
  `urn:nabu:ddbdp:bgu:3:994` (semicolons→colons, the SAME transform
  `adapters/papyri.rb` uses to mint the DDbDP urn — the join is exact).
- `origDate` takes two shapes: a POINT `<origDate when="-0113-08-26">26. Aug.
  113 v.Chr.</origDate>` (ISO-ish, ~1/3), or a RANGE `<origDate
  notBefore="0501" notAfter="0700" precision="low">VI - VII</origDate>` (~2/3).
  Years are zero-padded 4 digits; BCE is the MINUS sign.
- **The decisive off-by-one datum:** HGV `when="-0113"` is labelled "113
  v.Chr." = 113 BCE. So HGV negates the BCE year with NO astronomical
  year-0 shift (astronomical numbering would make -0113 mean 114 BCE). HGV
  is proleptic/historical, not ISO-8601-astronomical, in its own labels.
- Place: `<origPlace>Pathyris</origPlace>` + a provenance `<placeName
  type="ancient" ref="https://pleiades.stoa.org/places/786084 https://www.
  trismegistos.org/place/1628">Pathyris</placeName>` (ref present in 200/200
  sampled). goo300k/IMP carry only a YEAR (in the urn `…:sigil-1584` and the
  TEI `<date>1584</date>`); no place.

**Year representation — signed integers, HISTORICAL numbering, NO year 0
(a reasoned deviation from the design doc's loose "astronomical years").**
The stored integer is the plain historical year: negative = BCE, positive =
CE, and there is NO year 0 (1 BCE = -1, 1 CE = +1). HGV `when="-0113"` →
`-113` verbatim (strip zero-pad, keep sign). Rationale, argued openly against
the design doc's word "astronomical":
1. HGV's OWN values are historical (-0113 = 113 BCE, verified). Ingesting
   verbatim keeps ingest = source; an astronomical model would require a +1
   transform on every BCE year, drifting from the source's labels and adding
   an off-by-one surface to get wrong.
2. The CLI must match intuition: `--from -300` = 300 BCE. Under astronomical
   numbering `-300` would mean 301 BCE — a footgun. Historical keeps
   ingest = source = query = display, killing the whole off-by-one class.
3. SQLite integer sort is correct across the boundary regardless
   (`-300 < -30 < 14 < 501`); the absent year 0 is a harmless gap (no
   document occupies it, interval queries don't care). Guard: a literal
   `--from 0`/`--to 0` is degenerate (no year 0) — documented, not special-
   cased in storage.

**Ranges vs points.** Every axis row stores `(not_before, not_after)` as
honest bounds. A POINT (`when`) stores not_before = not_after = the year
(month/day dropped from the integer axis; the full string survives in
`date_raw`). A RANGE stores the two bounds unchanged — "VI–VII, precision
low" → (501, 700, "low"), never a fake midpoint. Interval-overlap is the
filter semantics: a doc [nb, na] matches a query window [from, to] iff
`nb <= to AND na >= from` (each bound optional). Era-boundary reign example
(Augustus 30 BCE–14 CE) stores (-30, 14); `--from -30 --to 14` matches,
`--from -50 --to -40` does not (nb -30 > to -40).

**Uncertainty / precision.** `precision` column = HGV's `precision` attribute
verbatim when present ("low"/"high"/…), else "exact" for `when`-points and
"range" for notBefore/notAfter pairs. Honesty over normalization: uncertain
dates are stored as their full honest interval, never collapsed.

**Place — string, no gazetteer (the §1.4 stance holds).** `place_name` =
`origPlace` text (verbatim); `place_ref` = the provenance placeName `ref`
URL(s) (verbatim string, may be space-joined TM+Pleiades). `--place` filters
`place_name` by case-insensitive LIKE (SQLite default ASCII-case-insensitive;
most papyrus places are Latinised ASCII): a value with `%`/`_` is a LIKE
pattern verbatim, else wrapped `%value%` (substring). `date_raw` keeps the
upstream origDate string (e.g. "26. Aug. 113 v.Chr.").

**Century bucketing math (`vocab --by-century`).** A signed century INDEX is
both the bucket key and the chronological sort key (no year 0, so the index
skips 0 too):
- year ≥ 1 (CE): `idx = (year - 1) / 100 + 1`  (1..100 → 1c CE; 501 → 6c CE)
- year ≤ -1 (BCE): `a = -year; idx = -((a - 1) / 100 + 1)`  (-1..-100 → -1
  = 1c BCE; -113 → -2 = 2c BCE)
Division is always on a positive magnitude (via abs), so no negative-floor
surprise. Ascending idx = chronological order: `-2 < -1 < 1 < 2` = 2c BCE,
1c BCE, 1c CE, 2c CE. Label = `#{ordinal(idx.abs)} c. #{idx<0 ? 'BCE':'CE'}`.
A RANGED document is bucketed by its `not_before` century (earliest attested)
— deterministic, no fake midpoint; the CLI states "bucketed by earliest
century" plainly.

**Schema — catalog-side `document_axes` (migration 008), NOT columns on
documents.** `(id, document_id FK, not_before INT null, not_after INT null,
precision, date_raw, place_name, place_ref, axis_source NOT NULL,
passage_seq_from INT null, passage_seq_to INT null)`. The nullable
`passage_seq_*` pair rides for Part 2's chronicle passage-grain (document-
grain rows leave them NULL); shipping the columns now avoids a second
migration. Indexes: `document_id`, `(not_before, not_after)`, `place_name`.

**Rebuild-safety.** `document_axes` = f(canonical), populated by
`Store::AxisBuilder` (a post-load pass, like the Indexer but writing the
catalog): HGV extractor reads the HGV_meta_EpiDoc XML and joins ddb-hybrid→urn
→ catalog document_id; goo300k/IMP extractors read the year off the urn
suffix of catalog documents (urn = f(canonical)). Wired into `Rebuild#run`
after replay, so `nabu rebuild` regenerates it (invariant holds; the Indexer
never re-parses canonical, unchanged). The live catalog gets a one-time
SANCTIONED build (migration 008 applied + AxisBuilder run — measured,
reported), exactly like P15-1's live index build.

### FABLE REVIEW VERDICT (fable model, 2026-07-12)
**Sound in structure — the core arithmetic survives every boundary case.** The
reviewer verified on disk (not assumed): year 113 BCE → -113 → century idx -2
(2nd c. BCE) ✓; the boundary table 101 BCE/100 BCE/1 BCE/1 CE/100 CE/101 CE all
agree with a historian; the overlap filter `nb<=T ∧ na>=F` is correct where
naive containment `nb>=F ∧ na<=T` FAILS (a "610s" query would lose every
`precision="low"` century-range papyrus); the signed century index is a
collision-free total chronological order; and the historical-vs-astronomical
choice is right (HGV `-0244` is labelled "244 v.Chr." — historical). FIVE
MANDATORY input-modelling fixes were raised and are ALL incorporated:
1. **Reject year 0 at ingest.** Ruby floor-division makes the BCE branch emit a
   phantom idx 0 for year 0 (a=0 → (0-1)/100 = -1 → idx 0), silently. `DateAxis`
   raises on year 0; the extractor treats a 0 year as unparseable (skipped, not
   stored). Also the astronomical-source tripwire. (No year-0 exists in HGV
   today — the guard costs nothing but future-proofs.)
2. **Open-ended intervals.** 335+ single-sided origDates on disk (notBefore-only
   / notAfter-only). Missing not_before = −∞, missing not_after = +∞, stored as
   NULL; the overlap filter is NULL-aware (`(na IS NULL OR na>=F) AND (nb IS
   NULL OR nb<=T)`) so an open-ended row never silently vanishes from a --from
   query. Undated docs (no axis row) are simply absent under a date filter.
3. **Multiple alternative origDates** (`dateAlternativeX/Y`, verified HGV1/997
   with when -0244 AND -0243). Policy: ENVELOPE — min of all lower bounds, max
   of all upper bounds across every date-bearing origDate under origin; composes
   correctly with the overlap filter.
4. **Zero-padded year parse via `.to_i`, never `Integer()`** — `Integer("0700")`
   is OCTAL 448 in Ruby, `Integer("0090")` raises; `.to_i` is base-10. Sign
   handled by regex (`-0113-08-26` split not on a naive `-`).
5. **Label the by-not_before bucketing bias.** Ranged low-precision docs bucket
   in their earliest century only (a systematic earlier-shift for a statistics
   command); `vocab --by-century` prints "bucketed by earliest year; N span
   multiple centuries" so the bias is stated, never hidden.
Recommendations adopted: **`--century N`** convenience flag on `search` (N<0 =
BCE, N>0 = CE) so users never hand-compute BCE century bounds (the reviewer's UX
footgun); an **F>T guard** (clear error, not silent empty). Deferred openly: a
German-label cross-check at ingest (labels are multilingual/fuzzy — "Mitte VII",
"VI - VII" — a robust check risks false warnings; the year-0 guard is the safe
tripwire) and a boundary-aware span helper (no duration math ships this packet;
noted for a future `--by-decade`).

### FINDINGS (implementation)
- **document_axes (migration 008)** landed as designed: `(document_id, not_before,
  not_after, precision, date_raw, place_name, place_ref, axis_source,
  passage_seq_from, passage_seq_to)`. The nullable passage_seq_* ride for Part
  2's chronicle grain (document-grain rows leave them NULL). Indexes on
  document_id, (not_before, not_after), place_name.
- **Nabu::DateAxis** (lib/nabu/date_axis.rb) is the whole date model in one small
  module: `parse_year` (base-10, sign-aware, rejects 0), `century_index`,
  `century_label` (ordinal + BCE/CE), `century_bounds` (for --century). Unit-
  tested across every boundary the reviewer named + the year-0 raise.
- **Store::AxisBuilder** reads canonical, joins by urn, upserts document_axes;
  wired into Rebuild#run after replay (so `nabu rebuild` regenerates it) and run
  once as a sanctioned build on the live catalog (migration 008 applied +
  builder) — measured/reported in the worklog. HGV envelope + open-ended + multi-
  origDate all handled; goo300k/IMP take the CE year off the urn suffix.
- **search --from/--to/--place/--century** compose through CatalogJoin (one
  correlated EXISTS on document_axes, document-grained); **vocab --by-century**
  (Query::Century) buckets the dated corpus, optional text query = "plot this
  word across centuries"; **show** prints the axis line; **nabu_search** gains
  from/to/place/century args (honest, same bounded contract).
- **Live sanctioned build (2026-07-12):** migration 008 applied + AxisBuilder on
  the live catalog: 66,261 HGV files scanned, 0 invalid, **60,923 papyri joined
  (99.2% of the 61,389-doc DDbDP shelf)** + 89 goo300k + 658 IMP = **61,670
  dated/placed documents**, in 46.6 s; document_axes = **10.7 MB** (design
  budgeted < 20 MB). Live demos, sub-300 ms: `search 'στρατηγ*' --from 101 --to
  300 --place oxyrhynch%` → the Oxyrhynchite strategoi (P.Oxy 10.1255, 19.2228);
  `search 'στρατηγ*' --century -3` → the early-Ptolemaic strategoi (P.Oxy
  60.4060); `vocab --by-century` → the corpus peaks 2nd c. CE (16,265 docs),
  4th c. BCE → 20th c. CE (the Slovene tail), 12,215 span multiple centuries;
  `vocab --by-century 'στρατηγ*' --lang grc` → the strategos office peaks 2nd c.
  CE (1,098 docs). Deviation argued openly: the design doc §3's loose
  "astronomical years" → HISTORICAL numbering (no year 0), because HGV's own
  values are historical and the CLI user's `--from -300` means 300 BCE.

## P15-3 · Cognate-in-parallel  [tier: opus impl, fable review of the closure] [status: pending] [deps: —]
## P15-3 · Cognate-in-parallel  [tier: opus impl, fable review of the closure] [status: done] [deps: —]
Design doc §6: `nabu cognates` — alignment hub × reflex crosswalk join
("verses where Gothic and OCS witnesses use reflexes of the same
proto-root"; measured: 349 NT verses / 31 roots / 1.4 s staged). Needs
the two missing indexes + the ~20k-row reflex_roots closure table
(rebuild-safe, derived); got×chu headline demo (salt~соль), grc×got
free rider. MCP exposure argued (probably yes, bounded).

## P15-4 · Collation view  [tier: opus] [status: done] [deps: —]
### DESIGN — reflex_roots closure (for fable review)

**What closes over what.** A derived table
`reflex_roots(language, lemma_folded, root_entry_id)`. Each row asserts:
an attested gold lemma `(language, lemma_folded)` descends — within a
BOUNDED two-level walk — from reconstruction entry `root_entry_id`
(a catalog `dictionary_entries.id`). Build has two edge classes:
- **DIRECT (attested → proto).** Every `dictionary_reflexes` row `r` with
  non-null `language` maps both `(r.language, r.word_folded)` and
  `(r.language, r.roman_folded)` to its OWNING proto entry
  `r.dictionary_entry_id`. The roman fold is the script bridge (§12): got
  `𐍃𐌰𐌻𐍄` reaches via roman `salt`, matching the romanized gold lemma.
- **ASCENT (proto → proto, ONE hop).** For each direct target `P` that is
  itself a `-pro` entry (headword_folded `H`, dict-language `PL`), add
  every entry `Q` whose reflexes name `(PL, H)` — exactly the proto-to-proto
  edge `Etym#ancestors_of` already walks. So got `salt` → {gem-pro *saltą
  (direct), ine-pro *sḗh₂l (ascent)}; chu `соль` → {sla-pro *solь, ine-pro
  *sḗh₂l}. They MEET at the ine-pro id — that shared `root_entry_id` is the
  cognate-in-parallel. Two witnesses are cognate at a verse iff their gold
  lemmas share a `root_entry_id`. (Direct-only meets — the *plęsati case —
  are subsumed: both witnesses land on the SAME entry at depth 1.)

**Cycle handling: safe by construction, no guard.** The walk is exactly two
levels — direct is depth 1, ascent is one non-recursive step; ascent never
re-expands its own output. A proto-to-proto cycle (P names Q, Q names P)
therefore terminates after one hop; a self-naming entry emits a duplicate
row the Set dedups. (Test: a constructed 2-cycle fixture asserts no blow-up
and the expected finite root set.)

**Rebuild story: derived-of-derived, built in the Indexer.** reflex_roots is
a pure function of the CATALOG crosswalk (`dictionary_reflexes` +
`dictionary_entries`), not of passages — but it JOINS `passage_lemmas`, and
cross-file SQLite joins are costly, so it lives in `fulltext.sqlite3` beside
`passage_lemmas`/`alignment_refs` (architecture §5 derived-of-derived),
built by a new `Store::ReflexRootsIndexer` called from
`Store::Indexer.rebuild!` AFTER `passage_lemmas`. Same drop-and-recreate
lifecycle: rebuilt on every `nabu sync` reindex and `nabu rebuild`.
`root_entry_id` is a catalog id re-minted on rebuild, stored cross-db
exactly as `alignment_refs` stores `passage_id` — safe because both are
rebuilt in the SAME pass and the query resolves the id against the current
catalog. A catalog with no reflex shelf → empty table (graceful, like
AlignmentIndexer's nil registry).

**Gold-scoping.** Final rows are scoped to the languages present in
`passage_lemmas` (the attested gold languages). The table exists ONLY to
join attested lemmas, so emitting rows for the ~250k modern-language
descendant keys (en/sco/de…) that can never join is pure waste. Proto
intermediates are still consulted DURING ascent (keys in the in-memory
reflex index, not final rows). Measured gold-scoped: **50,896 rows /
39,872 keys, ~1.4 s build** (design estimated ~10–20k rows — the real
number is ~2.5× higher but still < 5 MB). Trade-off: this couples
reflex_roots to which treebank languages exist; both are f(canonical)
rebuilt together, so determinism holds.

**Homograph / double-counting.** Two hazards: (a) two distinct `-pro`
entries sharing `(language, headword_folded)` — the ascent join matches on
folded STRING, so both attach, over-generating a lemma's root set; (b) two
reflex WORDS folding identically collapse in the in-memory index. Neither
MERGES roots: `root_entry_id` stays a concrete entry id, so a homograph
inflates one lemma's REACH but a false cognate still needs BOTH witnesses to
independently land on the SAME inflated id — a double collision, rare.
The ≥2-distinct-language requirement and the df-suppression (below) filter
the residue; dedup is a Set over the triple; output is sorted before insert
(deterministic). (Test: a homograph fixture asserts distinct ids are KEPT,
not merged.)

**Function-word suppression (df threshold).** Measured noise is both-common
function words (*éti: got `iþ` ~ chu `отъ` df 1316; *nu: 420/692) vs content
roots (salt 13–14, malan/grind 2–4). Default: drop any participating lemma
whose in-language `passage_lemmas` df ≥ `STOPLIST_DF` (200) before grouping;
a root left with <2 languages vanishes. `--all` disables it; output states
"N common-word matches suppressed (--all shows them)". This removes both
whole-hit noise (nu~нъ) and a function word riding a real hit's column
(отъ appearing under *átta beside отьць — measured).

**The two "missing" indexes ALREADY EXIST (deviation).** design §6 says the
packet must land `passage_lemmas(urn)` and `dictionary_reflexes(lang_code,
word_folded)`. Verified read-only on the live db: `passage_lemmas(urn)`
landed with P15-1; `dictionary_reflexes(language, word_folded)` landed with
migration 007 (P14-1) — and `(language, word_folded)` is what the ascent
probe actually uses (etym joins the catalog-side `language`, not
`lang_code`). So NO index is added to an existing table; the only new index
is `reflex_roots(language, lemma_folded)`, created with the table. The
design's >8-min naive figure predates both.

**Surface.** `nabu cognates <work-or-ref> [--langs got,chu] [--all]
[--long]`. Single ref → one verse; a registered work id → batch over its
refs. Group by root; require ≥2 DISTINCT languages reach it (same-language
codices sharing a word are not cross-linguistic cognate signal). Per verse:
root (starred headword + dictionary + license), each language's witness
lemma(s) + surface forms. `--langs` restricts and requires ≥2 of the named
langs. MCP `nabu_cognates`: bounded, license-labeled, argued yes.

### FABLE REVIEW (2026-07-12) — verdict: ship-with-changes

Adversarial review of the design above (cycle handling, closure
correctness, homographs, rebuild determinism, the df threshold). Findings
and their disposition, all incorporated before implementation:

1. **Claim (c) — rebuild safety — was FALSE for the sync path** (required).
   A recon re-sync (DictionaryLoader) revises/withdraws catalog entries
   without dropping the closure; stored row ids would point at withdrawn
   rows SILENTLY. → Fixed: `reflex_roots` stores the entry **URN** (the
   project's cross-parse stability contract), the build filters
   `withdrawn`, and the query re-resolves urns against the live catalog
   with the withdrawn filter — a stale root vanishes honestly. (Also:
   every sync triggers `Indexer.rebuild!` — verified both call sites — so
   the placement in the single choke point covers the drift window.)
2. **Ascent needed the same-language exclusion** (required): the live PIE
   extract holds 6,068 ine-pro→ine-pro reflex rows (derivational
   sub-trees); without Etym#ancestors_of's exclusion every direct PIE
   landing sprouts phantom sibling roots. → Mirrored in the builder;
   pinned by test (intra-shelf edges do not ascend).
3. **df=200 was empirically wrong** (required): fixed absolute df is
   percentile-incoherent across gold corpora spanning 125 (uga) to 113k
   (akk) passages — it would suppress guþ (914), богъ (725), sunus (310),
   the most famous demonstrations. → Per-language relative threshold:
   df ≥ max(50, 10% × language gold passages), calibrated live (function
   words 36–72%: ὁ 72.5, и 55.2, jah 45.2, sa 36.4; wanted cognates
   ≤ 8.4%: guþ 8.4, богъ 4.9, atta 3.7). The floor keeps tiny corpora
   from judging everything common. Honest limit stated everywhere:
   frequency cannot separate богъ (4.9%) from нъ (4.7%) — residual
   common-word survivors are called that, never "function words".
4. **Borrowing contamination** (required, minimum fix): descendant trees
   include unflagged loans (hlaifs ~ хлѣбъ IS a Germanic loan in Slavic;
   лихва, цѣсарь likewise) — a gem-pro meet presented as common descent
   would be wrong. → Every hit displays its meet SHELF (CLI, MCP, help
   text teaches the reading); a `borrowed` flag on dictionary_reflexes
   (parser change + migration) is named future work, improvements-register
   material.
5. **Claim (b) restated** (required): ONE fold collision into a root the
   other language independently reaches suffices for a false pair — not a
   "double collision". 126 folded-headword homograph groups exist among
   1,905 PIE entries (~13%); homographs inflate reach, never merge roots
   (pinned by test: distinct homograph ids are kept apart).
6. **Cycle/depth arithmetic confirmed** (no change): the two-level walk
   terminates trivially (ascent never re-expands); with exactly three
   shelves and every reflex row owned by one of them, one hop provably
   reaches everything an unbounded walk would — a depth-3 chain needs an
   intermediate shelf (ine-bsl-pro: named 1,112× as a reflex language,
   owns no dictionary) that does not exist. Recorded as contingent, not
   structural: revisit the bound if a Balto-Slavic shelf lands (~44% of
   Balto-Slavic-linked PIE entries are today unreachable from the Slavic
   side — a DATA gap, not a walk gap).
7. **Ground-truth fixtures over plumbing metrics** (required): the
   349/31 figure validates nothing about correctness. → Fixture goldens
   from the REAL recon extracts: chu богъ × grc ἔφᾰγον meet at ine-pro
   *bʰeh₂g- (inheritance), chu цѣсар҄ь × ang cāsere meet at gem-pro
   *kaisaraz (loan — the shelf-label test), got guþ via the 𐌲𐌿𐌸 roman
   bridge; plus constructed-row cycle and homograph guards.

### DONE (2026-07-12) — findings

- **The design's two "missing" indexes already existed** (deviation, said
  plainly): `passage_lemmas(urn)` landed with P15-1;
  `dictionary_reflexes(language, word_folded)` has been in migration 007
  since P14-1 — and `language` (not the design's `lang_code`) is what the
  ascent actually joins. Verified read-only on the live db. The packet
  landed NO index on any existing table; the only new index is
  `reflex_roots(language, lemma_folded)`, created with the table. The
  design's ">8 min naive" figure predates both.
- **Shipped:** `Store::ReflexRootsIndexer` (reflex_roots + reflex_root_stats
  in fulltext.sqlite3, drop-and-rebuild from Indexer.rebuild! AFTER
  passage_lemmas — scope and stats snapshot the same pass);
  `Query::Cognates` (work/ref/chapter/book grain, ≥2-distinct-languages
  rule, per-language relative suppression, meet-shelf on every root,
  witness license labels, `exclude_license:` for the MCP restricted
  contract); CLI `nabu cognates` (compact per house rule, `--all`,
  `--long` lifts the 200-hit cap + expands gloss/documents); MCP
  `nabu_cognates` (ninth tool, default 10 / max 50 groups, borrowing
  caveat in every note).
- **Live build (the one sanctioned write):** 50,151 closure rows +
  14 stats rows, **3.72 s, 4.4 MB** — design estimated ~10–20k rows/~1 s;
  the 2.5× rows are the 14-gold-language scope (design counted got+chu
  only), still tiny.
- **Live demo, through the production code:** got×chu whole-NT
  `--all` reproduces the design EXACTLY — **349 verses / 31 roots
  (0.52 s)**; default suppression trims to 299 verses / 30 roots
  (57 common-word hits: *nu, *éti — precisely the design's named noise).
  All six design verses reproduce, now shelf-labeled: LUKE 14.34 *sḗh₂l
  [ine-pro] соль~salt · LUKE 17.35 *melh₂- [ine-pro] млѣти~malan ·
  LUKE 1.24 *mḗh₁n̥s [ine-pro] мѣсѧць~menoþs (inheritance) vs LUKE 18.25
  *ulbanduz [gem-pro] · LUKE 20.10 *wīnagardaz [gem-pro] · JOHN 13.18
  *hlaibaz [gem-pro] (loans, labeled as such). Single verse: 25 ms.
  grc×got rider: 922 hits / 769 verses / 31 roots / 0.95 s with 2,169
  common-word hits suppressed — survivors are real cognates (hairto~καρδία,
  fotus~πούς, filu~πολύς), residual *só/*-we noise stated.
- Tests: store/reflex_roots_indexer_test (16 — fixture chains, cycle,
  homograph, intra-shelf, withdrawn, gold scoping, stats, determinism),
  query/cognates_test (14 — the join, loan shelf, grains, langs,
  suppression + floor, licenses, degradations), cli_test +7, mcp +8;
  tool-count pins bumped 8→9. Suite 1812/28,130 green, lint 230 clean.
  Live db read-only except the sanctioned closure build.

## P15-4 · Collation view  [tier: opus] [status: pending] [deps: —]
Design doc §2: `align REF --collate` — raw-token LCS diff within script
family over the hub's aligned rows (grc 7,643 / lat 6,974 / chu 3,764
multi-witness verses); cross-script witnesses rendered undiffed
honestly (the fold can't bridge Cyrillic↔Helsinki-ASCII — measured).
Compact rendering per house rule; the PROIEL-vs-CCMH Marianus demo.

FINDINGS. Query::Collation (lib/nabu/query/collation.rb) is a pure
RENDERER over Align's aligned rows — it wraps Query::Align, runs it, and
transforms the witnesses; zero schema, and the P11-8 range grammar +
P15-8 --long compose for free. GROUPING VERDICT — the collatable cell is
the PAIR (language, script), argued from the live corpus, NOT script
alone and NOT language alone: language alone lumps the Cyrillic Marianus
with the Helsinki-ASCII CCMH codices (same `chu`, two transcriptions the
fold cannot bridge); script alone lumps got/lat/eng/chu-CCMH (four
languages, one Latin script — measured at MARK 2.3, all present). Script
is detected from the TEXT (majority Unicode script via \p{Greek} etc.),
because the language code does not record which transcription a witness
uses — and this correctly caught that PROIEL "armenian-nt" is romanized
(xcl/Latin, an aside). BASE VERDICT — first witness of a cell in REGISTRY
ORDER (the registry IS the display order), `--base LABEL|urn` overrides;
at MARK 2.3 the chu/Latin base is CCMH Assemanianus (first CCMH), the
other three codices diff against it, Marianus stands aside cross-script.
DIFF — word-level LCS over raw tokens (only punctuation-ONLY tokens
dropped; markers &/$/^/⸂ kept verbatim — stripping them destroys info
exactly as folding does), a run of deletes+inserts coalesces to one :sub
(no transpose op — a word-order variant is honestly del+ins, e.g. the
Vulgate "ad eum ferentes"). APPARATUS marks: `a → b` (sub), `om. a`
(omission), `add. b` (insertion); agreements elided; `--collate --long`
prints each witness's full tokens instead. Cross-script/sole witnesses
render undiffed with the reason stated; no_match/not_synced/withheld
named once. MCP: `nabu_align` gains `collate: true` + `base:` (the
witness diff as `type: "collation"`; license gate withholds excluded
witnesses from the diff bodily). Golden reproduced live at MARK 2.3
(the four CCMH codices collated, придѫ/pridO vs pridoSE and
ослабленъ/nosESte surfacing; Cyrillic Marianus set aside). Tests:
query/collation_test +15 (LCS insert/subst/omit/agreement, (lang,script)
grouping, cross-script vs sole honesty, --base + miss, --long, range,
license withhold), cli_test +6, mcp/tools_test +2. Suite+lint green.

## P15-5 · Formula miner  [tier: opus] [status: done] [deps: P15-1]
Design doc §5: intra-corpus repeated n-gram mining (`nabu formulas
<source-slug|urn-prefix>`); zero schema. SHIPPED as Query::Formulas
(lib/nabu/query/formulas.rb) — the same gram machinery as P15-1's
Parallels pointed INWARD (probe→count). The shared "fold, elision strip,
tokenize, shingle" the design named was EXTRACTED to a mixin
(lib/nabu/query/grams.rb, `include Grams`) so Parallels and Formulas
tokenize/shingle identically — a formula mined here re-probes as a
parallel there; Parallels lost its private ELISION/gram_tokens/shingle to
the module (behaviour byte-identical, its 12 tests green).
FINDINGS. (1) Reads text_normalized STRAIGHT from the catalog — no
fulltext index, no Indexer touch (Formulas takes only `catalog:`); the
slice streams once (`dataset.each`), grams counted in a Hash. (2) SCOPE
resolves as a source slug (exact) else a DOCUMENT-urn byte-range prefix
(urn >= p AND urn < p+maxcp, no LIKE to escape) — a document urn is a
prefix of its passages' urns, so a whole work or the `urn:cts:greekLit:
tlg0012` super-prefix (Iliad+Odyssey) scopes through the join on the
documents.urn unique index; an earlier passages.urn-OR variant defeated
the index (2 s → 0.23 s once dropped). Document-grain by design; a
sub-document prefix is not a v1 slice. (3) LANGUAGE mandatory in practice
(design §5): perseus-greek rides grc + eng on one slug, so `--lang` is
offered and wanted where a source mixes translations (ASPR, single-lang,
needs none); slice AND lang both apply, exactly as Search. (4) STOPWORD
VERDICT — no stoplist, no df filter; rank by count × length and the
ranking is SELF-FILTERING. Measured: under a generous data-derived
stopword definition (token in ≥10% of the slice's passages: δ 22%, καί
18%, δέ 15%) NOT ONE all-stopword 4-gram reaches Homer's top 40 —
function words combine too freely to out-recur a real formula. A
per-language stoplist is a new unbounded per-language artifact (the "no
clever registries" rule) that buys nothing; a token-df filter MISFIRES on
small slices (a formula's own content tokens have elevated df by
construction — it would eat the formulas). `--min-count` is the noise
lever; the eye is the final filter, with almost nothing to reject. (At a
fixed gram size count×length reduces to count — the ×length is the general
form, the discriminator once mixed sizes are mined, the natural v2.) (5)
LOCI: lean pass keeps ≤3 example urns/gram (bounded); `--long` re-walks
the slice a second time for EVERY locus of the few reported grams (pays
its own ~0.2 s; compact prints "e.g. …"). (6) MCP: NOT a v1 tool
(argued in the class doc) — the MCP surface is passage-lookup-flavored;
the miner is batch-flavored (streams a slice, returns a ranked table).
Natural home is the §7 batch/links surface.
LIVE (read-only, through the production CLI): `formulas
urn:cts:greekLit:tlg0012 --lang grc` → 27,903 passages / 199,816 tokens,
2,751 4-grams recur ≥3×, 0.23 s core — ὣς ἔφαθ' οἵ δ' 72×, τὸν δ' αὖτε
προσέειπε 68×, the …ἀπαμειβόμενος προσέφη πολύμητις Ὀδυσσεύς chain 50×
(the design's exact numbers). `formulas aspr` → 30,550 / 175,736, 0.15 s
— ic wæs ond mid 13×, Beowulf maþelode bearn Ecgþeowes 6×; `--gram-size
3`: hwæt ic hatte 16×, awa to feore 20×, to widan feore 19× (all three
design figures). Tests: query/formulas_test.rb +14 (mining/ranking,
min-count, gram-size, no-stoplist, slug/prefix/unknown scope, lang
filter, compact-vs-long loci, locus=passage dedupe, withdrawn, bad
gram-size, slice totals), cli_test +6 (refrain+loci render, --long,
gram-size×min-count, unknown scope, bad gram-size, help). Suite + lint
green. One commit, not pushed.

## P15-6 · search --fuzzy  [tier: opus] [status: parked — owner decision at P15 gate 2026-07-12] [deps: —]
Design doc §4: trigram fragment search, DOCUMENTARY SCOPE (250–270 MB
index vs 3.6-4.1 GB whole-corpus — the measured line); sub-ms substring
queries; damaged-text persona. The menu itself said it loses nothing by
waiting — owner parked it for a later phase (register §1.5 tracks it;
re-propose with the Phase 16 menu alongside links/batch and date part-2).

## P15-gate · Phase 15 gate  [tier: orchestrator] [status: done 2026-07-12] [deps: P15-1..5(+6)]
Full-diff, library/languages/README refresh, improvements register
updates (§1.1/§1.4/§1.5/§1.8 → shipped/partial per reality), PR, owner
queue (no new syncs expected — this phase is all derived capability;
health --remote cache seeding if still unseeded), backup-disk re-flag
(standing), sticky alarm LAST.

## P15-7 · Honest drift labels + pin backfill  [tier: opus] [status: done] [deps: —]
Owner defect (2026-07-12): health --remote reports proiel/torot/
papyri-ddbdp as "never-synced" — "Literally not true." Root cause: the
drift verdict compares upstream vs the LEDGER PIN, and those sources
last fetched before the pins ledger existed (P7); no pin ≠ never
synced. Three fixes: (1) LABEL HONESTY — the no-pin verdict renders as
"unpinned" (with a hint: "synced pre-ledger — next sync records the
pin, or run health --backfill-pins"), never "never-synced" unless the
source truly has no runs in the ledger AND no canonical tree; the
status up= column keeps `?` but its detail follows suit. (2) PIN
BACKFILL — `health --backfill-pins`: for each git-fetched source with a
canonical clone but no pin, record `git -C canonical/<slug> rev-parse
HEAD` as last_sync_sha (through the existing Pin model; timestamp =
now, detail notes backfilled-from-local-clone; NON-git sources with
FileFetch/ZipFetch state files backfill from their sha pins where the
state file exists). Idempotent; read-only on canonical; writes ONLY the
ledger pins. (3) frozen-policy sources: drift verdict "frozen" in
health --remote too (status already does this via up=frozen — P14-12;
make the two surfaces agree). Tests: no-pin labeling, backfill from a
fixture clone + a state-file source, frozen agreement, idempotency.
Docs: ops.md informed-update flow gains the backfill note. Suite+lint
green; backlog done; worklog (sha —). One commit, not pushed.
## P15-8 · --long everywhere (house rule)  [tier: opus] [status: done] [deps: —]
Owner house rule (2026-07-12, after hitting `vocab --long` → ERROR):
"--long form should be available anywhere the outputs are truncated
((+792 more) etc)." CENSUS every CLI command's renderer for elisions —
known: vocab's hapax "(+N more)" cap; check show (document passage
lists?), concord, align (the range 200-ref cap — argue whether --long
raises it, bounded, or the cap stays a guard with a clearer message),
search snippets (no — snippets aren't list elision), anything else.
For every genuine list-elision found: add --long expanding it fully
(compact default byte-identical); for caps that are GUARDS not
elisions (align's 200), argue the verdict openly rather than blindly
expanding. Thor flag consistency: --long declared per-command (etym/
define P14-11 precedent). Tests per command (capped default +
expanded). Update the conventions doc with the house rule (a §
'CLI output: compact by default, --long escapes truncation' — one
paragraph). README rows touched only where a command gains the flag.
backlog done; worklog (sha —). Suite+lint green. One commit, not
pushed. NB: etym/define already have --long (P14-11); parallels ships
with it (P15-1, in flight — do NOT touch its files); your census
covers the REST.

# ── Phase 16 ──────────────────────────────────────────────────────────

## P16-0 · health --remote license-column optics  [tier: orchestrator] [status: done 2026-07-13] [deps: —]
Owner defect (2026-07-13, immediately post-#19): "license: unchecked"
creates wrong optics — reads like a problem when it only means "no
machine-checkable license artifact upstream" (non-github source, or a
github repo without a top-level license file — verified live: proiel/
torot/iswoc/gretil/open-bibles/idp.data all lack one). Owner rule:
"Better not to report anything than report 'unchecked'". Fix is
display-only: the :unchecked verdict still lands in the ledger; the row
renders nothing (rstrip'd — no trailing whitespace), conventions §10
suppress-zero-signal-fields. ok/CHANGED/baseline-recorded unchanged.
Optional follow-up NOT taken (owner may queue later): a per-source
`license_watch:` URL key to make non-github/README-licensed sources
watchable.

## P16-1 · Links substrate + batch parallels  [tier: opus] [status: done] [deps: P15-1, P15-5]
Design doc §7 (the links table as invisible substrate) + §1's batch mode:
the journal lands WITH its first producer, as §1.8 always said it would.
SHIPPED: (1) THE LINKS JOURNAL — db/links.sqlite3, links(from_urn, to_urn,
kind, score, run_id, created_at) + link_runs(producer, scope, params_json,
code_version, created_at); own forward-only migration track
db/links_migrate (the ledger_migrate precedent — per-file schema_info, no
counter collision), urn-keyed both ends. HOST ARGUMENT (from architecture
§5, now recorded as §15): batch links are a function of (canonical, params,
code version) — neither a pure function of canonical (so NOT in the
drop-and-rebuild catalog/fulltext) nor runtime history (a rerun of a scope
legitimately REPLACES its edges; the append-only ledger must never delete,
so NOT a ledger table despite the Phase-8 enrichment journal being the
mechanical precedent). A third file with the ledger's mechanics and its own
lifecycle: rebuild never touches it (tested byte-identical), losing it
costs only a re-mine. (2) PRODUCER #1 — `nabu parallels --batch SCOPE`
(Nabu::BatchParallels): the P15-1 engine looped over every anchor of a
scope (slug or urn prefix — the formulas grammar, EXTRACTED to a shared
Query::Scope mixin so the two surfaces cannot drift), hits persisted as
kind=parallel edges. Engine gains echoes: false (batch sheds the per-anchor
lemma-df probes; lemma echoes are not kind=parallel edges). Pruning NAMED,
never silent: top --per-anchor (5) at --min-score (0.05, ≈ one shared gram
in ≤20 passages) — both in the summary line and in params_json. Dedup: one
edge per unordered pair per kind (unique index), direction = the probe that
found it; within-run seen-set + cross-run refresh-in-place. Rerun of the
same (producer, scope) supersedes atomically (one transaction) —
idempotent, tested. --db writes the journal elsewhere (scratch runs).
(3) READERS — `nabu links <urn>`: both directions grouped by kind,
counterparts re-resolved by urn against the CURRENT catalog
(title/lang/license; "(not in catalog)" honesty for dropped rows),
provenance footer citing the run(s); compact 10/kind, --long lifts (house
rule); --min-score/--per-anchor/--db without --batch are ERRORS naming the
no-persistence stance (design §7's caching-with-staleness trap — no flag
blurs interactive vs batch). `show <urn>` gains "linked: N parallel" ONLY
when edges exist (zero-signal silence). (4) MCP nabu_links, the TENTH
read-only tool (argued: cheap, fits the bounded/license-labeled pattern;
reads persisted edges only, NEVER mines — description says so, and points
empty results at nabu_parallels); tool-count pins bumped 9→10.
LIVE DEMO (read-only: scratch dir with symlinked catalog/fulltext, journal
at a scratch path; live db/ untouched): `parallels --batch
urn:nabu:sblgnt:matt --lang grc` → 1,068 anchors, 5,089 edges, 13.3 s
(12.5 ms/anchor); rerun → 5,089 again, superseded 1 prior run (5,089
edges), 1 run row — idempotent. `links urn:nabu:sblgnt:matt:4.4` reads
back the design's own chain from the journal: Origen's Homiliae in Lucam
1.81, PROIEL/UD NT duplicates 1.54, canonical Matthew 1.24, LXX
DEUTERONOMY 8.3 at 1.22 — and `show` footers "linked: 5 parallel".
Journal: 1.7 MB / 5,089 edges. FULL-CORPUS PROJECTION, honest: the design's
"~1–2 min" figure was the §5 STREAMING extrapolation; the loop-over-anchors
batch (this packet, the design's other named option) measures 12.5 ms/anchor
on short NT verses → grc slice (1.44M anchors) ≈ 5 h lower bound (long
anchors cost up to ~111 ms), full corpus (3.79M) ≈ 13+ h. OWNER-FIRED only;
if whole-corpus mining is wanted at minutes-scale, a streaming-count
producer (P15-5's machinery emitting edges) is the follow-up packet.
Tests: store/links_journal_test 11 (schema, urn keying, pair invariant both
directions, supersede scoping, kind_counts, file lifecycle incl. readonly
refusal), batch_parallels_test 9 (direction, super-scope reverse dedup,
threshold honesty, lang scoping, provenance, rerun idempotency, overlap
refresh, empty scope, progress), query/links_test 6 (both directions +
grouping + resolution, unresolved counterpart, journal-outlives-catalog,
empty-vs-nil, document urn, unknown), rebuild_test +1 (journal
byte-identical across rebuild, edge re-resolves against re-minted ids),
cli_test +10 (batch summary + thresholds, supersede line, --db override,
flags-require-batch, links render both directions + provenance, --long,
unknown urn, no-journal state, help, show footer present/absent),
mcp/tools_test +4 + tool-count pins, config_test +1. Suite + lint green.
One commit, not pushed.

## P16-2 · Batch producers: formulas + cognates  [tier: opus] [status: done 2026-07-13] [deps: P16-1]
Producer #2/#3 riding the P16-1 substrate: `formulas --batch SCOPE` →
kind=formula edges (Nabu::BatchFormulas), `cognates --batch WORK` →
kind=cognate edges (Nabu::BatchCognates). Same journal, same supersede
replay, same `links` reader — no new mechanics beyond one argued column.
FINDINGS: (1) FORMULA EDGE-SHAPE VERDICT — a formula is an N-locus REFRAIN,
not a pair; judged by what `links <urn>` should usefully show a reader at
one locus: all-pairs is O(N²) (the 72-locus ὣς ἔφαθ' οἵ δ' alone = 2,556
edges saying nothing one couldn't), consecutive-loci chains answer "where
else?" with "next door", document-grain loses the loci. VERDICT: a STAR per
formula — hub = its first locus in urn sort order (deterministic,
rebuild-stable), one edge hub → every other locus, score = slice count,
detail = the folded gram. A reader at any locus sees `← hub “gram” ×N`
(which refrain, how strong); `links <hub>` fans out every locus; edges =
loci−1, linear. Live: Widsith's ic wæs ond mid catalog refrain reads back
exactly so (hub :59, 12 spokes, ×13). Pruning named: top --max-formulas by
rank (200) of the recurring grams, gram_size/min_count/lang all in
params_json; overlapping formulas sharing a (hub, locus) pair coalesce
onto the best-ranked gram with the fold COUNTED in the summary. A formula
recurring only within one passage mints no edge. (2) MEET-PROVENANCE
VERDICT — a cognate edge's meaning is WHICH root, on WHICH shelf, at WHICH
verse, and that differs per edge: params_json is run-grain (would lose
per-edge meets) and score is a float, so the schema gained a nullable
`detail` String via the journal's own forward-only track (migration 002,
db/links_migrate): applies IN PLACE on the next write-path open
(LinksJournal.open! migrates), zero data loss (tested against a v1 journal
file with live edges), read-only opens of pre-002 journals read nil.
detail carries display-grade evidence: cognate "MARK 2.1 · *kaisaraz
[gem-pro]" — the shelf on EVERY edge (design §6's borrowing signal);
formula edges reuse it for the gram. Cognate edges: one per unordered
cross-language witness-passage pair (never within a language — the
engine's ≥2-distinct-languages rule; witnesses/verse are few, so pairwise
is bounded), direction normalized lexicographically (the join has no probe
direction), a pair meeting at several roots/refs collapses into one edge
(detail lists all meets, score = distinct roots). Scope = work id;
suppression stays ON (an edge is an assertion), --all lifts and is
recorded; suppressed-group count in the summary. Engine touch: WitnessWord
gains passage_urns (hits pre-filtered to surviving documents, so no
license leak). (3) READERS — `links` renders each kind's evidence natively
(parallel score; formula “gram” ×count — a count rendered as "score 13.00"
would misread; cognate meet with score suppressed, it merely counts the
roots detail lists); array run-params render comma-joined (langs got,chu).
`show` footer was already multi-kind with zero-suppression (kind_counts
returns only present kinds) — verified `linked: 1 formula, 1 parallel` +
single-kind, no reader fix needed beyond the evidence tail. MCP nabu_links
payload gains `detail` (docs/mcp.md updated); tool count unchanged.
Batch-only flags without --batch error exactly like parallels
(--max-formulas/--db; cognates --db), naming the no-persistence stance;
--db override honored (tested: default path untouched).
LIVE DEMO (prod catalog read-only, journal at a scratch --db):
`formulas --batch aspr` → 170 formulas as stars, 395 edges, 70 pairs
coalesced, 0.3 s; rerun → 395 again, superseded 1 prior run (395) —
idempotent. `cognates --batch nt --langs got,chu` → 321 verse-root groups,
360 edges, 57 common-word groups suppressed, 3.4 s. Journal 264 KB / 755
edges; db/links.sqlite3 (matt parallels) untouched. `links` readbacks:
JOHN 6.5 hlaifs ~ хлѣбъ at *hlaibaz [gem-pro] (the design's own loaf), and
the Widsith star above.
Tests +26: batch_formulas_test 9 (star shape + hub determinism,
detail/score, single-locus no-edge, max-formulas cap honesty, coalescing
counted, params_json, rerun supersede, lang scoping, empty scope),
batch_cognates_test 6 (cross-language edges + normalized direction + meet
detail + loan shelf, no same-language edge, langs in params, suppression
default/--all recorded, rerun supersede, work-id-only contract),
links_journal_test +3 (detail write/refresh, nil default, 002 forward
migration on an existing file without data loss), query/links_test +1
(detail through Result), cognates_test +1 (passage_urns), cli_test +9
(batch summaries name knobs, supersede lines, --db overrides,
flags-require-batch both commands, links formula/cognate renders, mixed
kinds + show footer multi-kind/zero-suppression, work-id error, help),
mcp/tools_test +1 (detail payload). Suite + lint green. One commit, not
pushed.

## P16-3 · Date/place axis, part 2 — ORACC catalogue dates + chronicle annals  [tier: opus] [status: done] [deps: P15-2]
Two new AxisBuilder extractors, census-first, feeding the existing
document_axes (migration 008 untouched): ORACC catalogue.json dates
(period table + regnal resolution) and TOROT chronicle anno-mundi
annals (the first passage-grain rows). search --from/--to/--century/
--place and vocab --by-century inherit the coverage.

### FINDINGS (census 2026-07-13, read-only over live canonical + db)
- **ORACC census.** 33 catalogue.json files (html-en has none), 25,502
  members. `period` on 25,330 members (30 distinct values — Neo-Assyrian
  10,248, Old Babylonian 6,259, …, 'Uncertain'/'uncertain'/'Unknown' 106);
  `date_of_origin` on 7,343 (683 distinct): SAA regnal formulas
  `King.000.00.00` (2,814; NO nonzero regnal years anywhere, so reign-range
  grain is the honest maximum) + eponym `King.limu Eponym.mm.dd` variants,
  `00.000.00.00` = unknown (1,506), RIAO/RIBO/RINAP absolute BCE ranges
  (1,899) / years (14) / century phrases (128), 33 stragglers ('?-748',
  'SE 136.06.21', '673, 672' — unparseable, skipped, counted). 12 king
  spellings total, all standard NA kings with textbook reign dates.
- **AxisBuilder::OraccDates.** date_of_origin first (regnal → 12-king reign
  table, eponym-canon chronology after Grayson; absolute values must DESCEND
  = BCE or are unparseable; century phrases via DateAxis.century_bounds),
  else period via a documented ORACC/CDLI → middle-chronology table (after
  CDLI's conventional dates / Brinkman; 'First Millennium' honestly
  -1000..-1; compound "X or Y" envelopes); 'Uncertain' unmapped — skipped +
  counted. provenience (minus unclear/uncertain/unknown) + pleiades_id →
  place_name/place_ref. Translation docs (…-en) carry the tablet's axis row.
  **Coverage (scratch build): 21,558 of 21,692 oracc docs (99.4%) get a row;
  21,517 dated (99.2%), 41 place-only, 172 undated counted, 3 db docs in no
  catalogue (drift: blms P413985, saa03 Q009249, saa08 X000005).** Per
  project: all 30 in-db projects ≥ 97% dated (dcclt 5,797/5,961 lowest).
- **TOROT census: the annal year IS structural.** Chronicle <div> titles
  carry the AM year ('6360: Mikhail …', bare '6361', range '6369–6370',
  '6694 part 1'); exactly 5 of 40 sources are annalistic — lav 89/91 divs,
  pvl-hyp 24/24, kiev-hyp 4/4, nov-sin 163/163, suz-lav 76/76 = 356 AM divs;
  no other source has any (birchbark '43', rusprav '2' etc. all < 4 digits),
  so shape + AM-plausibility gate (5500..7300) needs no allowlist.
- **AxisBuilder::ChronicleAnnals.** Streaming Reader (lav.xml = 12 MB);
  AM → CE via DateAxis.am_to_ce: [Y−5509, Y−5508] (Byzantine epoch 1 Sep
  5509 BCE — the full September-style year; the March/ultra-March mix leaves
  a documented ±1 residue, never a per-annal guess; precision "am"); no-
  year-0 invariant holds across the epoch (AM 5509 → [-1, 1], tested). One
  passage-grain row per annal (passage_seq_from/to = min/max sequence via
  the <doc-urn>:<sentence-id> passage-urn join) + one document-grain
  ENVELOPE row per chronicle. **Coverage: 5 chronicles, 345 annal rows; 11
  nov-sin annal divs (6725-6780 group) are EMPTY upstream — skipped.**
  Envelopes: lav 851–986, pvl-hyp 897–921, kiev-hyp 1131–1135, nov-sin
  1015–1269, suz-lav 1110–1186 CE.
- **Query surface.** vocab --by-century now counts document-grain rows only
  (passage_seq_from IS NULL) — else a 163-annal chronicle tallies 163× in a
  histogram labelled "documents"; search EXISTS unchanged (all rows). Demos
  (scratch catalog + read-only live fulltext): `search LUGAL --lang akk
  --century -7` → SAA 18 101 + Nineveh lexical texts in 22 ms; `vocab
  --by-century LUGAL --lang akk` plots 19c BCE → 4c BCE peaking 8th c.
  (1,212 docs); akk corpus histogram peaks 10th c. BCE (2,210 — the
  by-earliest-year bucketing of the NA period range, stated bias).
- **Grand total after part 2: 83,233 dated/placed documents (was 61,670),
  83,578 axis rows, document_axes 13.9 MB** (< 20 MB budget holds). Scratch
  build 63.1 s on a copy of the live catalog; the LIVE rebuild is owner-
  fired (or next `nabu rebuild`) — untouched here.

## P16-4 · search --fuzzy — documentary trigram index  [tier: opus] [status: done 2026-07-13] [deps: —]
The parked P15-6, re-proposed and approved with the Phase 16 menu: design
doc §4 verbatim (trigram fragment search, DOCUMENTARY SCOPE — the
owner-approved 250–270 MB line vs 3.6–4.1 GB corpus-wide; damaged-text
persona `]μηνιν αει[`; candidates-then-verify; honest failure modes).
FINDINGS: (1) SCOPE FLAG VERDICT — per-source `fuzzy_index: true` in
config/sources.yml (papyri-ddbdp + oracc), parsed/validated by
SourceRegistry::Entry beside enabled/translations: documentary-vs-literary
is INDEX ECONOMICS, an owner posture, not intrinsic adapter metadata (a
manifest field means code edits — the spelunking to avoid; a constant is
the hardcode the design rejected). Registry#fuzzy_slugs threads into
Indexer.rebuild! from both callers (sync reindex + rebuild — the one choke
point, so the invariant holds). (2) INDEX — passages_trigram (FTS5
tokenize='trigram') over text_normalized AS STORED (same fold, only
tokenization differs) + passages_trigram_scope recording the slugs each
build ACTUALLY indexed (the query surface reports real coverage, never
possibly-drifted config); drop-and-rebuild like everything in
fulltext.sqlite3 (the existing indexer is not incremental; neither is
this), empty-not-missing when unscoped. (3) QUERY — Query::Fuzzy, standard
two-phase: implicit-AND MATCH of the fragment's trigrams (co-occurrence ≠
contiguity — "abc xyz bcd" candidates for "abcd") then substring verify
against the stored folded text; query strips editorial [ ] BEFORE the
query_forms fold union (braces kept — {d} is the akk/sux determinative
fold's job; conventions §9 note added); <3 chars post-fold raises
QueryTooShort → CLI names the trigram floor instead of returning nothing.
Composes with --lang/--license/--limit/--from/--to/--century/--place
(CatalogJoin, all free); --long lifts the snippet window (house rule);
--lemma/--near/--morph honestly refused. Every render ends with one scope
line ("fuzzy index covers: oracc, papyri-ddbdp") — the honest answer when
a literary fragment misses. (4) MEASURED (scratch build, live catalog
READONLY, production code path): 1,306,491 documentary passages / 41.9M
chars → 257.1 MB at 6.43 B/char in 8.6 s — INSIDE the design's 250–270 MB
projection (design assumed ~6 B/char on 41.3M chars; delta +0.43 B/char,
+1.5% chars). Queries live: στρατηγ/οφειλ/εν-lil 0.7–6.5 ms; the README
demo is real — `--fuzzy ']ανδρα μοι εν['` → BGU 6.1470, a papyrus writing
exercise breaking off mid-word through the Odyssey's opening (…Μοῦσα
πολύτρο[). (5) The LIVE fulltext.sqlite3 does NOT yet carry the table —
the production build is OWNER-FIRED at the next sync/reindex/rebuild
(+257 MB, +~9 s, both within budget). Tests +33: registry flag parsing +
fuzzy_slugs + non-boolean raise (3), indexer scope gating/empty-not-
missing/infix/withdrawn/idempotent/fresh-db regeneration (6), query
folding (bracketed Greek, determinative-crossing Akkadian, final sigma),
false-candidate-rejected-by-verify, scope reader, floor raises, filters,
snippet-vs-long (14), CLI render/--long/scope hint/literary miss/floor
message/date compose/pre-P16-4 reindex hint/flag conflicts/help (10).
Docs: architecture §5 index bullet + tree line, README papyrologist
persona (live demo pasted) + feature row, conventions §9 bracket-strip
note. Suite 1933/28,563 green (exit 0), lint 245 files clean (exit 0).
One commit, not pushed.

## P16-5 · Riders: wiktionary-cu descendants backfill + license_watch  [tier: opus] [status: done 2026-07-13] [deps: —]
(a) The P14-1 deferred rider: wiktionary-cu entries carry descendants
data never crosswalked into dictionary_reflexes — backfill at the
parser/indexer path (same choke point as wiktionary-recon), so OCS
entries' descendants feed etym/cognates; parse-only resync recovers it,
census the crosswalk gain (rows before/after). (b) license_watch:
optional per-source `license_watch: <url>` key in sources.yml — the
remote probe fetches THAT url (any host, not just github) and
hash-compares against the pin baseline, exactly like the license-file
path; makes README-licensed upstreams (kielipankki README.txt,
clarin.si record pages) watchable. Non-configured sources: behavior
unchanged (silent per P16-0). Tests stub HTTP (WebMock); no live
fetches in suite.

FINDINGS (2026-07-13). (a) CENSUS first, read-only over live
canonical + db: 589 of 4,615 cu entries carry ≥1 worded descendant →
2,210 dictionary_reflexes rows would mint (ALL new — cu owns 0 today;
all 2,210 joinable: language + fold present, 0 display-only). Distinct
(language, fold) keys 3,212 — 1,496 already reachable via recon-minted
edges, 1,716 new. Gold-language keys 243 (189 new); projected
reflex_roots closure gain ~244 rows (orv=171 sl=66 lat=5 chu=2; today
50,151). Top reflex languages sh/ru/bg/uk/mk (modern, non-joining, by
design). Verdict: data real and worth wiring — DONE: WiktionaryCu#parse
now passes `reflexes: true` (one-line flip; parser/DictionaryLoader/
ReflexRootsIndexer already generic). A cu-owned edge is direct-only in
the closure (chu ≠ -pro → no ascent hop; OCS→proto stays Etym's live
ascent); Etym display asterisk now -pro-only (attested OCS entries
enter the walk and must not read as reconstructions — Result#headword
"стопа", not "*стопа"). Reflexes ride the entry content sha → the
OWNER-FIRED `bin/nabu sync wiktionary-cu --parse-only` re-mints the
shelf's 4,615 revisions and lands the 2,210 edges (recovery path; NOT
run here — proven on fixtures: 38 entries / 127 edges in the trimmed
cu fixture, loader idempotent, closure dedup + determinism pinned with
both shelves loaded). (b) license_watch SHIPPED: registry Entry gains
`license_watch` (nil default; ValidationError unless absolute http(s)
url), RemoteProbe#source_license overrides BOTH strategies' license
path when configured — GET via the shared vendored-cert client (no
redirect following), body sha256 through the shared compare_license,
baseline on a ledger pin keyed by the WATCHED url (baseline-only row,
minted on first sight — the one sanctioned exception to "probe never
mints pins"; drift never reads it). First sight :baseline_recorded /
match :unchanged ("license: ok") / mismatch :changed ("license:
CHANGED" + detail naming the url); non-200/transport error → :unchecked
(silent per P16-0), never raises; failed fetch never touches the stored
baseline. Non-configured sources byte-identical. Candidate urls
COMMENTED in sources.yml (owner flips after verifying each serves the
terms directly): ccmh kielipankki README.txt, goo300k/imp clarin.si
records (11356/1025, 11356/1031), bosworth-toller LINDAT record
(11234/1-3532), freising e-ZRC landing page, proiel/torot/iswoc repo
README raws, oracc licensing doc page. Tests: wiktionary_cu +3,
reflex_roots_indexer +2, etym +1, source_registry +3, remote_probe +7.
Docs: architecture §12 addendum, ops.md license_watch paragraph,
02-sources #46 note, improvements §1.11 rider → shipped. Suite
1917/28,540 green (exit 0), lint 254 files clean (exit 0). Live db/
canonical read-only throughout (census only).

## P16-gate · Phase 16 gate  [tier: orchestrator] [status: done 2026-07-13] [deps: P16-1..5]
Full-diff review, library/languages/README refresh (links/fuzzy/axis
coverage numbers from live db), improvements register (§1.4 → shipped,
§1.5 → shipped, §1.8 → shipped), PR, owner queue (parse-only resync
wiktionary-cu; batch runs are owner-fired if long), backup-disk
re-flag (standing), sticky alarm LAST.
# ── Phase 17 ──────────────────────────────────────────────────────────
# Owner directive (2026-07-13): "focus on additional sources this phase:
# 4-7, maximal scope with deep info extraction that synergizes with our
# tools/paradigm. Don't limit yourself to what we ALREADY extract. Think
# about additional meta/info that strengthens our cross-tools and every
# aspect of nabu capabilities." Every packet is TWO-PHASE: scout/design
# (Phase A, docs/<slug>-survey.md, fixture plan) → OWNER GATE → adapter
# (Phase B). Deep-extraction mandate: enumerate EVERY annotation/metadata
# layer upstream carries and map each to a nabu surface — axis, links,
# reflex crosswalk (incl. the P15-3 `borrowed` flag future-work), the
# alignment hub, morph facets, vocab, collation layers, fuzzy, license
# labels, MCP — proposing NEW columns/facets where the data earns them.

## P17-1 · Coptic Scriptorium  [tier: opus, two-phase] [status: scouting] [deps: —]
Register §2.2 (candidate — strong). Gold-lemmatized Coptic (would be
lemma language #15); the Sahidic NT as alignment witness #14. Deep
layers to census: bound-group tokenization vs word grain; gold
lemma/POS/morph; LANGUAGE-OF-ORIGIN tags on tokens (Greek loanwords
marked — a language-contact layer feeding cognates/etym's borrowing
signal); normalized vs diplomatic layers (ccmh-txt collation precedent);
verse citations (hub wiring); English translations (--parallel); MS
metadata — dates (axis), repository/provenance; multi-corpus structure
(NT, Shenoute, Apophthegmata, Besa...). License CC BY (verify per
corpus).

## P17-2 · EDH — Latin inscriptions  [tier: opus, two-phase] [status: scouting] [deps: —]
Register §2.3. Epigraphy as the third documentary shelf — fuzzy_index's
designed second customer (one config line) + the axis's natural feed
(EDH dating not_before/not_after; findspot/province). Deep layers to
census: inscription TYPE (epitaph/dedication/milestone/diploma — a
GENRE facet nabu doesn't have yet; argue schema), material/object type,
personal names (prosopography seed, §3.5), EpiDoc abbreviation
expansions + lacunae (folding/fuzzy nuances), bilinguals (grc/lat),
province geo (strings + province v1; coordinates noted not ingested).
EDH is archived/read-only upstream — census the dump format (Open Data
repo, CC BY-SA) and the frozen sync_policy fit.

## P17-3 · Reconstruction shelf, part 2  [tier: opus, two-phase] [status: done] [deps: —]
DONE 2026-07-13 (Phase B). Survey (docs/recon2-survey.md) verdicts all
shipped. FIXTURES (network-approved): the ~12 byte-verbatim kaikki goldens
into the existing layout — four NEW extracts (ine-bsl-pro *pírštan multi-
hop golden + *wárˀnāˀ ˀ-fold + *duktḗ; gmw-pro *hlaib/*faru; itc-pro *gʷōs
bōs-loan + *kʷis clean; iir-pro *bʰráHtā roman + *kšatrám xcl-loan +
*adᶻdʰáH ˢ/ᶻ-fold) + 5 appends to the existing files (sla *xlěbъ/*pьrstъ,
ine *per-#1/*kʷís, gem *hlaibaz) + 1 cu append (страна Slavonicism); all
re-downloads hash-identical to the P14-1/P13-10 snapshots. MIGRATION 010
(009 reserved): nullable boolean `borrowed` on dictionary_reflexes; parser
mints true/false from raw_tags/tags `/borrow/i` (census: "borrowed"
×92,120, "learned borrowing" ×405, "reshaped by analogy…" correctly NOT
matched), NULL = pre-reparse; rides ContentHash reflex_fields (P16-5
parse-only recovery). FOUR EXTRACTS rows on wiktionary-recon (registry
untouched — same source), PROTO_FOLD += ˢ→s ᶻ→z ˀ→"" under ine + itc/iir
keys (gmw measured clean, no key). MULTI-HOP CLOSURE: ReflexRootsIndexer
rewritten to the shelf-visited worklist walk (each dict-language enterable
once/walk; breadth-first rounds ⇒ deterministic + terminating in
≤shelves−1 rounds; cycle-safe by the visited set; degenerates to the old
one-hop set, pinned); attested shelves ascend like -pro (supersedes P16-5
direct-only); reflex_roots gains OR-aggregated `borrowed` (true>false>NULL).
Etym walks the same bound, renders the chain indented + `←(loan)`; MCP
nabu_etym nests ancestors. Consumers: Cognates WitnessWord.borrowed →
"(loan)", BatchCognates detail "(loan: chu)", MCP payloads carry the
boolean w/ NULL-honesty. JOHN 13.18 acceptance render reproduced on
fixtures: `*hlaibaz [gem-pro] / chu хлѣбъ (loan) / got hlaifs`. Suite +43
tests (2068 runs / 29,172 assertions), lint clean, both exit 0. The real
~60 MB sync + closure rebuild are OWNER-FIRED (not run — worktree never
touched live db; one live-state check DEFERRED-TO-REVIEW per coordinator
db-lock). One commit, not pushed.

Register §1.11 extension; owner PIE/comparativistics axis. Census which
kaikki proto extracts exist beyond our three — Proto-Balto-Slavic,
Proto-Italic, Proto-Hellenic, Proto-Indo-Iranian, Proto-Semitic (the
cuneiform synergy: sem-pro descendants naming akk would crosswalk to
ORACC gold lemmas — verify akk actually appears), others on our axes.
TWO structural upgrades the data forces: (1) the closure indexer's
one-hop ascent bound was argued from "no intermediate shelf exists" —
Proto-Balto-Slavic IS that shelf; design the bounded multi-hop closure
(PIE → PBS → sla-pro → chu → orv chains) the indexer doc said to
revisit. (2) kaikki descendants carry BORROWING flags — land the
P15-3-named `borrowed` column on dictionary_reflexes so cognates/etym
distinguish inheritance from loan PER EDGE, not just by meet-shelf
heuristic. Size/count census per extract; fixture plan.

## P17-4 · Monier-Williams (Cologne CDSL)  [tier: opus, two-phase] [status: scouting] [deps: —]
Register §1.3's named next occupant for Sanskrit. LICENSE SCOUT FIRST
(CDSL terms vary per dictionary — the register's own warning; record
the verdict + posture mapping before any fixture plan). Deep layers:
headwords Devanagari + IAST (folding against GRETIL's san-Latn);
grammatical apparatus; CITATIONS to Sanskrit literature (RV., MBh. —
the §1.3 resolution pattern: parse abbreviations, resolve against the
GRETIL shelf's urns, honest miss-rate reporting); MW's OWN COGNATE
NOTES (entries cite Greek/Latin/Gothic/Slavic comparanda — a
dictionary-native comparativistics layer: census whether these parse
reliably enough to mint crosswalk edges, distinct from kaikki's);
etymology cross-references between entries. Would complete the
per-language desk loop: LSJ:grc :: L&S:lat :: B-T:ang :: MW:san.

## P17-5 · Etruscan axis scout  [tier: opus, two-phase] [status: scouting] [deps: —]
Owner axis voiced 2026-07-13 ("One more axis I'd like to explore while
we're close to Proto-Italic etc - Etruscan"). Phase A survey: what
machine-readable Etruscan exists — inscription corpora (ETP/UMass, CIE
digitizations, Rix ET editio minor derivatives, EDR/Trismegistos
coverage), lexica/glossaries, the kaikki/Wiktionary ett extract
(descendants/contact data — Latin loanwords FROM Etruscan feed the
borrowed-flag layer), anything with dates/findspots (axis + the
P17-2-proposed genre facet fits inscriptions natively). Non-IE: no
proto-shelf ascent, but the language-contact surfaces (Latin↔Etruscan
loans, bilinguals like the Pyrgi tablets) are the synergy to census.
License per source; ranked verdict + fixture plan for the gate.

## P17-gate · Phase 17 gate  [tier: orchestrator] [status: pending] [deps: P17-1..4]
Full-diff, library/languages/README refresh (new languages/shelves/
facets from live db), improvements register (§2.2/§2.3 → shipped,
§1.11 part-2 note, §1.3 MW note), PR, owner queue (real syncs for every
new source are owner-fired; fixture-plan approvals happen mid-phase at
the Phase A gates), backup-disk re-flag (standing), sticky alarm LAST.
