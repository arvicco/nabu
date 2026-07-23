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

## P17-1 · Coptic Scriptorium  [tier: opus, two-phase] [status: done 2026-07-13] [deps: —]
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

FINDINGS (Phase B, 2026-07-13 — survey docs/coptic-survey.md is the spec
of record; owner approved the fixture plan as suggested, incl. the
optional 4th documentary sample). Shipped: fixture set (Besa TT+CoNLL-U
whole, AP.004.poemen.65 whole, cpr.2.237 whole, rebuilt sahidica.nt zip
with Mark_01 trimmed to verses 1–12 + Philemon whole; README+manifest,
all at tag v6.2.0 commit 6c2acf0); parser family `CopticTtParser`
(span-EVENT stack, never a tree — cpr's `</figDesc>`-before-`</figure>`
proves it); adapter `CopticScriptorium` (chapter→book merge incl. the
single-chapter edge, in-repo-zip discover via `unzip` through Shell —
canonical never written outside fetch, treebank-dir + license-less skip
rules with discovery accounting, P10-4 attribution overrides read from
each header, most-restrictive-wins across a book's chapters); GitFetch
grew `ref:` (fetch pinned to the release TAG, owner re-pins by bumping
RELEASE_TAG); conventions §9 `cop` fold (⳿ U+2CFF deletes; census: every
stroke/overline is Mn, already generic-stripped); text = diplomatic
orig_group sequence, text_normalized = norm-layer WORD sequence through
the one folding boundary (conformance search-source hook pins the
derivation); tokens/entities/identities/loans/topology annotations
(loans = per-passage code counts {grc/hbo/arc/lat/egy}, the future
--loans facet reads them without reparse); gold-lemma gate `lemmas:
:gold` default (automatic docs mint lemma_auto — nothing lost, index
unpolluted; :all = the owner flip); `CopticScriptoriumDates` axis
extractor (dates+places, unknown-class places skipped, urn mint pinned
against the adapter by test); hub witnesses #14 sahidica NT (nc) + #15
bohairic NT (attribution), 27 books each, urns verified in the tagged
meta.json. DEVIATIONS from the survey, all fixture-forced: (1) a THIRD
structural TT dialect the survey's 8 samples missed — Philemon's
COLLAPSED shape (orig_group/orig/lang as ATTRIBUTES on norm_group/norm,
translation as verse_n attribute) — parser handles all three, fixture
preserves it; (2) upstream's "Arabic only in ANNIS" is false for AP:
AP.004 carries embedded per-verse `<arabic>` spans — ingested as
translation_ar where present; (3) survey's `sync_policy: versioned` is
not a registry enum — implemented as `manual` + tag-pinned fetch (same
substance); (4) -en translation sibling documents NOT minted v1 (the
per-verse English rides in annotations["translation"]; the ORACC-shape
sibling minting is a named follow-up — deliberate scope hold, the
packet's deliverable list governed). V2 backlog (survey §10): --loans
facet + Coptic→Greek borrowing crosswalk (converges with P17-3
`borrowed`), witness/identity links-journal producers, CoNLL-U FEATS
join, ANNIS Arabic for the other 72 docs, CDO lexicon, sbl_greek
collation, -en siblings, AND the OT witnesses (sahidic.ot 911 +
bohairic.ot 507 docs) — NOT wired v1: upstream's own "versification may
not always align with traditional Septuagint versification" caveat
demands a Psalms/Jeremiah spot-check against the LXX witness after
first sync (the P11-5 clean-books-first precedent). Projected first
sync: ~2.8 GB clone; ~75–80k passages / ~2.4M token records (~300–400
MB annotations JSON in the catalog, survey estimate stands — fixture
parse yields ~46 tokens/passage on literary, ~31 words/verse on NT).
Registry `enabled: false`; owner fires the first sync (checklist §6).
Note for review: the §9 cop fold refolds the ~28k live papyri-ddbdp cop
passages at next rebuild — expected a no-op (documentary text carries
no U+2CFF) but unverified against live canonical (db untouched this
packet, per mid-task coordinator directive). [VERIFIED at review,
post-rebuild: 8 live cop passages DO carry U+2CFF — not a no-op; they
refold correctly at next rebuild, intended and small.]

## P17-2 · EDH — Latin inscriptions  [tier: opus, two-phase] [status: done 2026-07-13] [deps: —]
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
PHASE A (2026-07-13): docs/edh-survey.md — 82,450 inscriptions censused
from 12,747 records read + both corpus-wide CSVs; all verdicts inside
(langUsage-lies trap, del→⟦…⟧, line grain, facet schema, frozen policy,
persons-as-annotations v1). Fixture plan owner-approved same day.
PHASE B FINDINGS (2026-07-13): (1) ONE SURVEY DEVIATION, argued — the
survey's "persons ride in the document's annotations, zero schema"
presumed a document-annotations surface that DID NOT EXIST (documents had
no metadata/annotations column; the loader dropped Document#metadata on
the floor). Migration 009 therefore carries a rider beside
document_facets: documents.metadata_json (NOT NULL default "{}"),
persisted by the loader as pure METADATA — deliberately outside
ContentHash (the license_override precedent), reconciled on the
same-content path with no revision bump, so every stored sha is
byte-stable and imp/goo300k/freising's already-emitted metadata persists
for free. (2) document_facets landed as surveyed: skinny
(document_id, facet, value, raw), facet ∈ genre/province/material/
object_type for EDH, value = the record's own EAGLE/XML term, raw = the
CSV code verbatim with `?`-certainty surviving; Store::FacetBuilder
projects it from metadata_json at rebuild (after AxisBuilder), so NO
code-side vocabulary tables exist — the titadnun unknown resolved itself
(each record carries its own term; live-checked HD014570 = "adnuntiatio").
(3) search --type/--province/--material as correlated EXISTS in
CatalogJoin (value OR raw, ilike), composing with --from/--to/--century/
--place AND --fuzzy; compact renders: search footer names active facet
filters, show prints one facets: line (raw in parens when divergent),
rebuild prints the facets summary. MCP nabu_search facet args deferred
(not in the packet deliverable list; config-shaped follow-up).
(4) EdhEpidocParser: DdbdpParser-adjacent streaming family; del ALWAYS
⟦…⟧ (per-source adoption of conventions §5's future-work direction —
recorded there; no frozen urns exist so no revision storm); gap-only
lines (lb n="0") not citable; per-passage grc by script (GL bilinguals);
textpart-relative line restarts in urns. (5) Adapter: 9 flat zips
(ZipFetch, all URLs HEAD-re-verified 2026-07-13) + 2 CSVs (FileFetch,
each in its OWN subdir — FileFetch is single-file-per-dir, siblings read
as deletions); language STRICTLY from CSV nl_text (L→lat, G→grc,
exotic 5-record residue → und); ~475 text-less stubs skip-by-rule with
discovery accounting (XML-without-CSV-row = loud unrecognized).
(6) AxisBuilder::EdhDates: CSV signed years verbatim (no year 0 —
tripwire counted), open-ended honest, place = fo_antik→fo_modern with
Pleiades-then-GeoNames refs; Summary grew edh/edh_undated/edh_invalid
with defaults. (7) Registry: enabled: false, sync_policy: frozen,
fuzzy_index: true — the one-config-line promise kept. Fixtures per the
approved plan (HD000001/HD000082/HD080825 byte-identical + both CSVs
trimmed, manifest + README). Tests +83 (suite 2130/29,466, lint clean,
both exit 0). Owner queue: one frozen ~220 MB `bin/nabu sync edh`, then
rebuild (facet+axis rows + trigram +~70 MB materialize), eyeball, flip
enabled. Live-db demo SKIPPED (owner rebuild was running — deferred to
review). v2 recorded in the survey: persons table + attestation query,
geo layer, btext, PIR/TM links edges, GODOT.

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

## P17-4 · Monier-Williams (Cologne CDSL)  [tier: opus, two-phase] [status: done 2026-07-13] [deps: —]
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
PHASE A (2026-07-13): docs/mw-survey.md — CC BY-NC-SA 3.0 → `nc`
(mwheader.xml is the grant, per-dictionary; upstream NOT frozen,
Last-Modified 2026-07); whole-corpus census 286,525 records / 193,890
grouped entries; headwords SLP1 not Devanagari (backlog lead corrected);
328,060 <ls> citations, RV resolution verified end-to-end; cognate layer
973 records / 2,537 tags / 98.9% parseable. Fixture plan owner-approved.
PHASE B FINDINGS (2026-07-13): (1) `Mw` adapter + `mw-xml` family
shipped — FileFetch of mwxml.zip (sha pin), parse streams the xml/mw.xml
member via `unzip -p` (canonical stays the 11 MB zip); ONE ref id
`mw:mw.xml` for both plain-file (fixtures) and zip shapes. H1–H4 mains
group their A/B/C/E continuations by file adjacency; entry_id = Cologne
<L>, urn:nabu:dict:mw:<L>. (2) `Nabu::Slp1` transcoder, deterministic
BOTH directions (x→ḷ vs L→ḻ keeps the reverse map unambiguous; accents
a/MSa→áṃśa round-trip; digraphs longest-match-first) — the betacode
precedent, NO conventions-§9 change; fold("aṃśa")=fold(GRETIL IAST)=
"amsa" verified in tests. (3) Citations: curated MwSigla map — 24
GRETIL-held works (filenames verified against the mmehner mirror
listing) + 11 authority labels; roman→arabic + per-work sprintf pad
templates ("RV. v, 86, 5" → 5.086.05); Define grew document-urn work
resolution + bounded pada-suffix probing (a–d; exact verse wins) and
document-grain citations now resolve to the DOCUMENT urn (nabu-urn
works only — CTS bare-work refs keep nil). Per-siglum coverage via
`Mw.citation_coverage` printed at every sync through a generic CLI
respond_to? hook — tier totals + live-resolution fractions, "document
not in catalog" never faked. (4) Cognate notes → dictionary_reflexes
with ZERO schema change (survey §4 state machine: coordination "Goth.
and Germ. un" shared, register markers ep./Ved. filtered; Gk./Lat./
Goth./Lith./Angl.Sax./Zd.→ae/Eng./Germ./Russ./Armen. mapped, Slav./Hib.
display-only) — etym walks a Greek lemma (ὦμος) to the MW aṃsa entry as
a SECOND witness beside kaikki, tested; P17-3's borrowed column will
read NULL on these rows honestly (migration 010 untouched). (5) Grammar
apparatus → a `grammar:` body line (lex genders incl. f#-stems
transcoded, verb class-pada, Westergaard/Whitney refs); See-refs ride
the body via the transcode. Fixtures test/fixtures/mw/ (26 record lines
= 11 entries: aṃśa L10-27.1 with the verified RV citation, aṃs/aṃsa
L44-92.1 cognate cluster, akūpāra L313 <ls n=> restoration, √bhāṣ
L150479 verb apparatus, bhāṣaṇa) + verbatim mw.dtd + mwheader.xml (the
license travels in-fixture) + README/manifest. Registry `enabled:
false`, sync_policy manual — first real sync OWNER-FIRED (11 MB GET →
~100–130 MB catalog; eyeball coverage output + define aṃśa/bhāṣ).
DEFERRED-TO-REVIEW: non-RV passage-grain templates (BhP/R/Ragh/Yājñ/
Kum/Sāh/MārkP/VP/Daś) encode the survey's census shapes but were not
re-verified against the live catalog (db access embargoed mid-packet —
coordinator, owner rebuild in flight); wrong templates yield honest
query-time misses, never fake links. v2 (surveyed, priced): ibid
propagation (+10.4k), Devanagari display forms, See-ref/phwparent →
links graph, root families, full 871-sigla key, Mn./Pāṇ. re-grain.
Suite 2097 runs / 29,355 assertions green, lint clean, exit 0/0.

## P17-5 · Etruscan axis scout  [tier: opus, two-phase] [status: Phase A done 2026-07-13 — owner gate PASSED: fixture plan approved, OpenEtruscan ingests under `attribution` (Larth-provenance caveat journaled + license_watch on the Zenodo record); Phase B adapter → P18 queue] [deps: —]
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

## P17-6 · CLARIN.SI repository survey  [tier: opus, scout] [status: done 2026-07-13 — owner verdict: ALL findings → P18 queue (Damaskini, Slovenian dictionary shelf, PriLit rider); ELEXIS repo-help email = owner reminder, ride the Miklosich send] [deps: —]
Owner request (2026-07-13): "check what else is available on clarin.si
in addition to goo300k/imp/freising". Survey the whole repository
against our axes (Slavic deepening — OCS/Old East Slavic/South Slavic/
Slovenian, historical corpora, dictionaries, treebanks; secondary: any
cross-axis surprises worth naming). Known context: goo300k/imp/freising
already held; Miklosich known-blocked on BCDH (do not re-scout it,
reference the standing thread). Per-item license verdicts (clarin.si
items carry explicit CC labels; BY-ND is IN-SCOPE per the standing
ruling → research_private), machine-readability, size, ranked verdict +
fixture-plan sketches for the top picks.

## P17-7 · Lock-tolerant SQLite: busy_timeout + WAL verdict  [tier: opus] [status: done 2026-07-13] [deps: —]
Owner defect (2026-07-13): `nabu rebuild` crashed mid-papyri with
SQLite3::BusyException "database is locked" — a concurrent READER
(agent demos/verification, even `sqlite3 -readonly`) held a shared lock
during the loader's journal commit. Root cause: journal_mode=delete
(rollback) + NO busy_timeout anywhere in Store.connect — any
reader/writer overlap is a hard crash instead of a wait. Two fixes to
argue and land: (1) busy_timeout (Sequel/sqlite3 timeout) on EVERY
connect path (catalog, fulltext, ledger, links journal) — a writer
waits out a transient reader instead of dying; pick the value from the
longest legitimate reader (MCP tools, links readback) + margin.
(2) THE WAL VERDICT — journal_mode=WAL lets readers and one writer
coexist (the actual architecture here: MCP/agents read while
syncs/rebuilds write). Argue costs honestly: -wal/-shm sidecar files
(rsync backup + restore-drill parity — ops.md update), sqlite3
-readonly semantics on WAL, checkpointing on close. If WAL wins, flip
at connect + migrate existing files (PRAGMA journal_mode=WAL is
persistent) with a rebuild-safe path; if not, document why busy_timeout
alone suffices. Tests: concurrent reader-during-write no longer raises
(thread-based, in-memory-excluded — file-backed tmp db), timeout
present on every connect, backup drill still green.

FINDINGS (done 2026-07-13): VERDICT = WAL + explicit busy_timeout —
timeout-only loses because no timeout survives an unbounded reader
(rollback COMMIT needs EXCLUSIVE vs the reader's SHARED; the crash's
`sqlite3 -readonly` session could sit for minutes). Correction to the
crash analysis: there WAS a busy wait — Sequel's sqlite adapter
defaults :timeout to 5000 ms — the reader simply outlived it, which is
the proof implicit-and-shorter-than-the-longest-reader is not a policy.
Landed: Store.connect + connect_fulltext (ledger + links delegate)
carry timeout: BUSY_TIMEOUT_MS = 10_000 (longest legitimate holder is
seconds-scale — batch links readbacks, loader/indexer commits — ×
margin), readonly included; journal_mode=WAL set on every RW connect
(persists in the file → existing dbs self-heal on first open, no
migration; readonly connects never set it — the pragma writes). WAL
costs handled: `nabu backup` db sections copy live -wal/-shm sidecars
and PRUNE stale ones at the target (a restored stale -wal replays old
frames over a newer main file); drill unchanged and green. Caveat
pinned in the class doc: sqlite3's C-level busy handler blocks the GVL,
so writer-writer waits only work CROSS-PROCESS (nabu's actual writers);
tested via subprocess holder — 0.3 s held lock waited out, not raised.
Tests +8 (reader-snapshot-during-commit regression, subprocess busy
wait, busy_timeout + journal_mode pinned on all 7 connect paths,
rollback→WAL self-heal; backup sidecar ride-along/prune/dry-run).
Suite 2055/29,104 exit 0, lint 263 files exit 0.

## P17-8 · PIE/comparativistics sources survey  [tier: opus, scout] [status: done 2026-07-13 — v1 picks IE-CoR (CC BY, 2,261 held-pair edges, loans layer) + LIV-LOD (CC BY-SA); reflexes-rows surface verdict; dev → P18 pending owner gate at P17-gate] [deps: —]
Owner (2026-07-13): "Dispatch a scout on other PIE sources, I feel we're
thin on comparativistics." Beyond kaikki (held: 3 proto shelves + 4 more
landing in P17-3): survey the machine-readable comparativistics field —
Pokorny IEW digitizations (UT-Austin LRC, dnghu, Starling), LIV/NIL
digital state, IE-CoR / IELex / CoBL cognacy databases (Jena/MPI-EVA —
CLDF, licenses), the Lexibank/CLDF ecosystem generally (cognate-coded
wordlists, CC-labeled), Tower of Babel/Starling (license reality),
PIE Lexicon (Pyysalo, Helsinki), UT LRC etyma lists, anything serving
laryngeal-notated reconstructions with DESCENDANTS/cognate-set structure
that joins our gold shelves. Per-item: format, entry/cognate-set counts,
license verdict (paywalled Brill dictionaries = blocked, named), and the
measured-or-projected join story against dictionary_reflexes/etym (the
kaikki-shelf precedent: record-level rates). Ranked verdict + fixture
sketches for the gate; honest "print-only, no unblock" list.

# ── Phase 18 queue (owner-approved 2026-07-13, dispatch next phase) ──
# 1. Etruscan adapter (P17-5 Phase B): OpenEtruscan CSV (new flat-CSV
#    parser family, skip ocr_failed, fuzzy_index, BCE sign-flip pin) +
#    kaikki ett EXTRACTS row + the Latin-loans curated-edge rider;
#    posture: attribution — the Larth provenance caveat DISSOLVED
#    2026-07-14 (upstream added LICENSE CC-BY 4.0 on owner request);
#    carry instead the author's own data-quality caveat ("many
#    inscriptions are really noisy and not really reliable") in
#    02-sources. Fixture plan APPROVED (etruscan-survey.md §fixtures).
# 2. Damaskini (clarin-si-survey pick #1, CC BY-SA): Balkan Slavic
#    gold corpus, aligned English, St. Petka multi-witness collation.
# 3. Slovenian historical dictionary shelf (pick #2, CC BY): Pleteršnik
#    + Svetokriški (loanword etymologies → borrowed synergy) + besedje16
#    (Dalmatin sigla crosswalk); one dictionary parser family.
# 4. PriLit rider (pick #3, CC BY): 1643–1866 TEI, 7-edition collation.
# 5b. Postcondition checker + optional AI review (owner, 2026-07-13):
#    MECHANICAL layer first — health/verify gains consistency invariants:
#    per-source last-run status surfaced LOUDLY (failed run + partial
#    docs = today's Coptic case), flag-vs-artifact pairs (fuzzy_index vs
#    trigram table, axis extractors vs row counts, reflex code vs
#    crosswalk rows), enabled-vs-populated, pending migrations,
#    quarantine DELTA vs baseline (not the standing count), projection
#    diffs vs survey-stated expectations. AI layer as OPTIONAL rider:
#    post-sync hook (config key / --review), off by default, tool-
#    agnostic (structured brief on stdin; bundled example wires claude -p
#    + the nabu MCP server; local models have equal standing per the MCP
#    ruling) — judgment calls only: sample-passage reading, quarantine-
#    reason triage. No cloud dependency enters the core.
# 5a. Coptic sync robustness (defect, found 2026-07-13) — SHIPPED in
#    P17-10 (2026-07-13). The "transient race" hypothesis was WRONG: the
#    census proved the crash deterministic — the dual-origin work urn
#    ot.hab.bohairic_ed (standalone bohairic-habakkuk corpus AND
#    bohairic.ot_TT.zip members share one CTS urn) merged into one
#    document group whose ref path was the loose .tt, so chunk_content
#    ran `unzip -p` against a non-zip → exit 9 on EVERY sync, at ref
#    #280 of 465. Shipped: per-chunk origin reads (structural fix),
#    standalone-over-zip precedence (shadowed members skipped by rule),
#    unreadable zip MEMBER at parse → ParseError (quarantine), unreadable
#    zip at discover → FetchError. Census + verdict: see ## P17-10.
# 5. PIE deepening (P17-8 picks, fixture sketches in pie-survey.md §7):
#    IE-CoR cognacy matrix (CC BY — 273 sets/2,261 held-form pair edges,
#    1,596 laryngeal PIE roots as kaikki cross-check, 1,036 curated loan
#    events) + LIV-LOD Latin slice (CC BY-SA, 305 verbal etymons);
#    v2: de Vaan EDL skeleton (nc). Unblock emails on file: Starostin
#    (Starling pokorny.dbf), UT LRC.
# 5. Carried candidates: scholia + dictionary-citation links producers,
#    edition-vs-edition collate, streaming batch parallels producer.
# OWNER REMINDER (raise at P17-gate + P18 planning): ELEXIS bitstream
# question — one email to repo-help@clarin.si settles 141 dictionary
# records incl. Miklosich; CC on the pending Miklosich draft send.

## P17-9 · Static site — the project's academic face  [tier: opus] [status: done 2026-07-13] [deps: —]
Owner (2026-07-13): "a separate static site for Nabu (github project
page). Humanists are allergic to github READMEs it seems. The site needs
to restate README, sources and supporting materials in a more academic
style and org-look (tabs/pages etc). It needs to be further maintained
and synced with README and current project state at any future gate."
Jekyll site under site/ (NOT docs/ — the loop docs stay un-rendered),
deployed by a GitHub Actions Pages workflow; pages: Home, The Library
(collections from library.md), Tools, Examples (personas), Languages,
Licensing & Access, About. Academic register: restrained serif design,
no marketing voice, cite-the-numbers style, every claim traceable to the
repo docs. STANDING GATE DUTY added to the §10 cadence: the site is
refreshed alongside library.md/README at every future gate. Site serves
PROJECT DOCS ONLY — no corpus content (the external-access licensing
rulings are not triggered). Enabling Pages in repo Settings = owner
action, queued.
FINDINGS (2026-07-13): shipped as a hand-rolled Jekyll site (no theme,
own layout + CSS: serif stack Charter/Iowan/Georgia, muted oxblood
accent, 𒀭𒀝 masthead glyph with font-stack fallback) — 7 tab pages
(Home, The Library, Tools, Examples, Languages, Sources & Licensing,
About) + site/MAINTENANCE.md (the gate-duty contract) + site/Gemfile
(self-contained, app Gemfile untouched). Deploy:
.github/workflows/pages.yml — jekyll-build-pages from site/ +
deploy-pages, push-to-main paths [site/**] + dispatch, pages:write +
id-token:write. All numbers restated from library.md/README with as-of
dates, never re-derived; snippets are README's own live-run outputs; the
three enabled:false sources (coptic-scriptorium, mw, edh) listed
honestly as "awaiting first synchronization". Verified: jekyll build
exit 0 (jekyll 4.4.1 vendored under site/vendor, gitignored), href
sweep — every internal link resolves to a built page; rake test exit 0
(2256 runs / 30,434 assertions). DEFERRED TO ORCHESTRATOR: (1) the §10
review-cadence line in docs/library.md naming the site (another agent
held library.md during this packet); (2) a README link to the site;
(3) owner action to go live: Settings → Pages → Source: GitHub Actions.

## P17-10 · Coptic sync crash: dual-source works  [tier: fable] [status: done 2026-07-13] [deps: P17-1]
Owner-hit defect, twice: both `bin/nabu sync coptic-scriptorium` attempts
died `command failed (exit 9): unzip` after "279 docs / 127 quarantined".
CENSUS (read-only over canonical @ v6.2.0, 465 refs total): exactly ONE
work urn collects chunks from two origins — `ot.hab.bohairic_ed`, minted
by BOTH the standalone `bohairic-habakkuk` corpus (3 loose chapter .tt)
AND `bohairic.ot/bohairic.ot_TT.zip` (members 35_Habacuc_01..03.tt).
Everywhere else upstream keeps the origins apart with distinct `_ed` CTS
urns (nt.mark.sahidica_ed loose vs nt.mark.sahidica zip; ot.jonah/ruth
.coptot_ed vs .coptot) — Habakkuk is an upstream collision, unique in the
release. The merged group's ref path was the first (loose) chapter file,
so `chunk_content` ran `unzip -p` against a .tt → exit 9, deterministic,
at ref #280/465 in urn order: 152 loaded + 127 quarantined + crash =
exactly the owner's numbers (re-derived ref-by-ref; the live catalog's
152 urns all re-mint identically — frozen-URN guarantee holds, and
ot.hab.bohairic_ed itself never loaded). The 127 quarantines are a
SEPARATE finding, NOT this defect: CopticTtParser's fixture-verified span
inventory rejects unknown TT span types loudly, and the full corpus
carries 32 span types the 5-doc fixture census never saw (ed_page_n 58×,
supplied_reason 42×, entity_identity 30×, abbr 21×, petermann/marcion_
chapter_n 28×, gap* 28×, …) plus 9 structural rejects (unsegmented
stretches in 8 NT zip books + 1 magical papyrus, whose copticMag urn the
CTS_NAMESPACE regex also doesn't strip) — corpus-wide 188 of 465 parse
clean post-fix (277 quarantine); widening the inventory is P18 material,
quarantine is exactly the designed behavior. BYTE-IDENTITY: the two Habakkuk origins DIFFER — the
loose corpus is the v6.2.0 re-release (2025-11-25; segmentation/tagging/
parsing/entities/identities all GOLD, people/places rosters, lb_n
manuscript topology, revised lemmas + re-tokenization, public domain +
CC-BY 4.0) vs the zip's frozen v6.0.0 automatic snapshot (2024-10-31,
minimal header, CC-BY-SA). PRECEDENCE VERDICT: same edition urn at two
releases → ONE document, the STANDALONE corpus wins (newer + gold + richer
+ clearer license); the shadowed zip members are skipped_by_rule ("zip
member shadowed by the standalone edition"), never doubled chapters —
post-fix live census: 465 refs, 0 mixed groups, skipped_by_rule 111→114,
ot.hab.bohairic_ed = 56 passages gold v6.2.0. Distinct-urns alternative
REJECTED: upstream says same work, and the frozen-URN check showed no
loaded urn moves either way. MECHANICAL FIX regardless of verdict:
chunk_content now derives the zip path from the CHUNK's own `zip` key
(expand_path'd), never document_ref.path — a mixed group is structurally
incapable of the crash even if precedence regresses (pinned by a
hand-built mixed-group test; ref_path/chunk_label audited, group-order
safe). Robustness rider (5a, landed here): unreadable zip MEMBER at
parse → ParseError quarantine; unreadable zip at discover → FetchError
(that IS a fetch problem). Fixtures: dual-origin pair trimmed from the
local canonical tree (loose Habakkuk_01 vv1-2 + rebuilt bohairic.ot zip
with the trimmed real 35_Habacuc_01 member, provenance in README +
manifest); 6 new tests (precedence at discover, gold edition surfaced at
parse, mixed-group no-crash, corrupt-member quarantine, corrupt-archive
FetchError, skip accounting) — suite 2261 runs exit 0, lint exit 0.
Owner re-run: `bin/nabu sync coptic-scriptorium` (expect 188 docs
loaded, 277 quarantined — the span-inventory finding, honest and loud).

## P17-gate · Phase 17 gate  [tier: orchestrator] [status: done 2026-07-13] [deps: P17-1..4]
Full-diff, library/languages/README refresh (new languages/shelves/
facets from live db), improvements register (§2.2/§2.3 → shipped,
§1.11 part-2 note, §1.3 MW note), PR, owner queue (real syncs for every
new source are owner-fired; fixture-plan approvals happen mid-phase at
the Phase A gates), backup-disk re-flag (standing), sticky alarm LAST.

## P18-1 · Coptic coverage: span inventory + headerless files  [tier: fable] [status: done 2026-07-13] [deps: P17-1, P17-10]
The owner's third sync completed (run 112): 188 of 465 docs loaded, 277
quarantined, 18 files "no usable TT meta header" (the reported "295
unrecognized" = 277 + 18 conflated; run 112's notes list exactly 18).
Census-first widening of the P17-1 inventory — the strict-inventory
tripwire stays: an unknown span type still quarantines.

CENSUS 1 (spans; full sweep of all 2,497 non-excluded TT chunks @ v6.2.0
— the P17-10 first-error census undercounted at 32): **66 unknown span
types**, EACH given a verdict, occurrence×file counts pinned in the
parser constants. (a) INGEST-AS-ANNOTATION, 49 tags: edition topology
ed_page_n/ed_pg_n/ed_page (869×/80f + 274×/14f + 14×/2f → "ed_page"),
ed_line_n/ed_lb_n (38,285×/113f → per-token "ed_line"), ed_chapter_n;
editorial transcription marks → "editorial" records {mark, verbatim
sub-attrs incl. upstream typos gap_exent/gap_reasaon/gap_reasonn}: gap*
(1,154×/165f + reason/unit/extent/quantity), supplied* (1,865×/138f +
reason/evidence/source/unit/quantity), surplus*, unclear*, abbr
type=nomSac (1,620×/337f — the sahidic-OT nomina-sacra layer), sic,
del_rend, add_place; entity_identity (686×/62f — v6.0 attribute-form
Wikification wrapping the TOKEN → token-anchored entities records);
PATHS entity markup (persName/placeName/roleName/date/org/rs _type +
placeName_ref gazetteer ids merging into their enclosing entities;
standalone quote_ref/quote_type biblical-quotation records); Pistis
Sophia alternate versification marcion_*/petermann_* (10,117×+2,320×/28f
→ "cit_marcion"/"cit_petermann" lists) + trans_horner (→
"translation_horner") + pb_coptic_id (→ "page_coptic"); german (→
"translation_de", Besa on_vigilance), arabic_translation, section_title;
verse_n_vname (→ "verse_name"); note/note_note upgraded from ignore to
"notes" (only annotation change touching already-loaded docs — revision
bumps at resync, urns frozen). (b) FOLD-INTO-EXISTING, 8 tags:
verse_n_vid_n/v_id/vid__n → vid; verse → the unit opener (verse-as-unit
files: 1Cor/shenoute-house carry NO verse_n; fused labels "1 Corinthians
14:1" normalize to citation 14.1, verbatim label kept in annotations);
pb_n/pb_id → page; ch_n → chapter; pb_coptic_xml → page_coptic. (c)
IGNORE-COUNTED, 9 tags, named in IGNORED_TAGS with reasons: hi, sup,
sub, cb, ignore_note (upstream's own name says ignore), p_source
(constant PATHS credit), chapter/chapter_name/chapter_2 (duplicate
chapter naming; citation comes from meta). STRUCTURAL verdicts: (1) the
"unsegmented stretches" are the OMITTED-VERSE lacuna shape — Mark 7:16,
John 5:4, Acts 8:37, Matt 12:47, Rom 16:24, Rev 1:1-2, bohairic Acts
24:7, OCrum's final Amen carry `[..]`/`[--]`/`[...]` placeholder groups
that open BEFORE the verse_n nested inside them → stray groups/tokens
attach FORWARD to the unit that opens inside them; a stray that CLOSES
with no unit is still the loud error (tripwire pinned by 3 synthetic
guard tests). Acts 24:7's group crosses into v8 → attaches whole to the
verse it opened into, token-level attribution stays exact. (2) A token
still open at unit close belongs to the unit it OPENED in (span-stack
semantics — Luke 13:20|21 splits mid-word ⲟⲩ|ⲉⲥ, helias splits at
chapter boundaries; freed helias ×4 + nt.luke.sahidica). (3) copticMag
urn regex deliberately NOT widened: the live catalog froze urn:nabu:
coptic-scriptorium:urn:cts:copticMag:kyprianos.tm99995.kyp_t_53 at the
first sync; the corpus keeps the full CTS urn as its tail (pinned by
test; Würzburg Kyprianos cross-refs ride in metadata `source`).

CENSUS 2 (headers): ALL 18 unrecognized files share ONE lexical variant
— `msItem_title ="…"`, a space before the equals (helias 5, theodosius
9, acts-pilate 2, lament-mary 2; v6.0.0 OCR-era headers). NOT a 4th
structural dialect, NOT meta-on-part1-only: every part carries its own
full meta with a range-suffixed cts urn (helias.martyrdom.sobhy_ed:0-15)
→ regex widened to \s*=\s*, one document per part (the shenoute range
precedent, no group merge). theodosius/acts-pilate/lament-mary parts are
verse-less → the existing translation-ordinal mode.

POST-FIX COVERAGE (re-derived read-only over the live tree): **482 of
483 discovered docs parse clean** (465+18 refs; was 188/465), 74,169
passages projected (was 29,946), 0 unrecognized, skipped_by_rule 114
unchanged. Remaining quarantine, itemized: 1 — lives.longinus_lucius.
paths_ed:10-16 (life.longinus.lucius.02.tt carries a verse-less bare
<translation> stretch inside a verse-mode file, upstream mixed
segmentation; honest named quarantine, not worth a heuristic). FROZEN
URNS verified: all 188 live doc urns re-mint with identical passage
counts; passage-urn lists spot-checked identical on 7 live docs incl.
the copticMag one and dual-origin Habakkuk. Fixtures: 12 offender items
(10 trimmed loose files, Mark_07 added to the sahidica.nt zip, NEW
bohairic.nt + sahidic.ot one-member zips; provenance in README +
manifest.yml); fixture discover now mints 18 docs. Suite 2,283 runs /
31,217 assertions exit 0, lint exit 0. Owner re-run:
`bin/nabu sync coptic-scriptorium --parse-only` (expect 482 loaded /
1 quarantined / 0 unrecognized).

## P18-2 · Starter pack + site Quickstart  [tier: opus] [status: done 2026-07-13] [deps: —]
Owner (2026-07-13): queue the starter pack; "the site needs some kind of
'Quickstart' section - right now it lacks even clearly visible link to
the repo, as well as steps needed to initialize your own Nabu Library."
Adoption bottleneck: time-to-first-marvel is currently clone + Ruby +
multi-GB syncs. (a) STARTER PACK: a curated small-shelf set reaching a
real marvel in minutes — candidates sblgnt + vulgate + eng-web + proiel
+ lexica (align MARK multi-witness, lemma search, define λόγος) —
MEASURE real canonical sizes (live tree read-only) and pick under a
~300 MB / <10 min budget; mechanism argued: a `nabu quickstart` command
(sync the starter list, then print the three demo commands) vs a
documented sync line — bias to the command, it's the humanist's path.
(b) SITE: a Quickstart page (prereqs, clone, bundle install, starter
sync, first search + align + define, MCP registration pointer, "grow
the library" next step) + a VISIBLE repo link in the site header/nav
(currently buried in About). README quickstart section aligned with the
site page (single source of truth stated). Tests for the command
(fixture-backed, no network in suite); site builds exit 0.
FINDINGS (done 2026-07-13): MEASURED canonical sizes (du -sh, live
tree, git history included): sblgnt 11 MB · proiel 173 MB · iswoc 30 MB
· lexica 479 MB · vulgate 357 MB · eng-web 357 MB · torot 270 MB. The
~300 MB budget is NOT attainable with the define marvel: lexica alone
is 479 MB on disk (the registry's "~160 MB" note is stale). CHOSEN SET
(693 MB): sblgnt + proiel + iswoc + lexica — align "MARK 2.3" renders
SEVEN witnesses (grc ×2, lat, got, xcl, chu, ang — iswoc's 30 MB buys
the OE witness), search --lemma rides the PROIEL gold rows, define
λόγος/virtus has LSJ + L&S. vulgate/eng-web EXCLUDED: each is a full
open-bibles clone measuring 357 MB (stale "~76 MB" note) for one USFX
file — they are the first "grow the library" step instead. TIME: ledger
first-sync wall clocks sblgnt 3 s / proiel 14 s / iswoc 4 s / lexica
133 s ≈ 3 min fetch+load, projected well under the 10 min line with
per-source reindexes. SHIPPED: `nabu quickstart` (normal per-source
sync path in starter order, one failure never stops the rest + end
report + exit 1, idempotent re-sync, --list previews; epilogue = the
three marvels + grow pointer), site/quickstart.md + nav entry +
GitHub ↗ repo link in the nav bar of EVERY page (layout-level, accent-
styled), README Quickstart short form moved near the top pointing at
the site page, docs/quickstart.md §2 re-anchored on the command,
MAINTENANCE.md gate duty covers the measured sizes. Lint rider:
site/vendor + site/_site excluded in .rubocop.yml (vendored gems ship
.rubocop.yml requiring rubocop-minitest — the CI vendor trap, found at
the first local site build). Tests +7 (starter wiring vs the shipped
registry, --list touches nothing, order + epilogue, idempotent re-run,
partial failure aggregation + exit 1, help teaches the shelf, command
listed). Suite 2,267 runs exit 0, lint 287 files exit 0, jekyll build
exit 0.

## P18-3 · Reflex dedupe audit — every grouping surface  [tier: opus] [status: done 2026-07-13 — every surface tested-or-proven, findings table below; 8 forcing tests added, zero code defects found beyond the already-fixed choke point] [deps: —]
Owner (2026-07-13, after the prīmus ×3 fix): "Make sure to dedup not
just specific command but more generally any path where such grouping
COULD create dup entries." The orchestrator fixed the display choke
point (ReflexViews.for_entry — serves etym/define/MCP); this packet
AUDITS every other surface that groups crosswalk/closure/alignment data
and proves-or-fixes each: Query::Cognates interactive join (same
(language, word) via word-fold AND roman-fold double-match?; multiple
reflex rows per root), BatchCognates edges, Query::Etym ancestors_of
(claims merge — verify by test), the reflex_roots closure build
(claims sorted/deduped — verify multi-shelf + multi-subtree), MW
comparanda rows landing beside kaikki rows for the same (entry, word),
nabu_etym/nabu_cognates/nabu_define MCP payloads, links journal
readers (kind-grouped edge lists), parallels loci grouping, formulas
star edges, vocab hapax lists, collation cells. For each: a test that
FORCES the duplicate condition and pins the grouped render, or a short
proof in the class doc why duplication is structurally impossible
there. Deliverable includes a one-table findings summary (surface /
dup-possible? / fixed-or-proven).

FINDINGS (2026-07-13). Verdict: the display choke point the
orchestrator fixed (ReflexViews#for_entry) was the only defect; every
other surface either already collapses duplicates structurally
(hash-keyed grouping / Sets / unique index) or rides the fixed view.
Where a duplicate condition is reachable in the DATA it was forced by
test; where unreachable, the impossibility is argued in the class doc.

| surface | dup possible? | fixed-or-proven | where |
|---|---|---|---|
| ReflexViews#for_entry (etym/define display) | YES — multi-subtree crosswalk rows (prīmus ×3) | FIXED (orchestrator): dedupe by (language, word, roman), flags merge true>false>nil | lib/nabu/query/reflex_views.rb; etym_test test_duplicate_reflex_rows_render_one_view_with_merged_loan_flag |
| Query::Cognates join | no — accumulator hash-keyed (ref,root)→language→lemma, surfaces/docs/passages are Sets; word/roman folds are distinct closure keys and a gold lemma has one folded form | proof in class doc + forced-dup test (raw duplicate closure rows) | cognates.rb doc; cognates_test test_duplicate_closure_rows_render_one_group_with_one_witness_word_each |
| BatchCognates edges | no — refs/meets are Sets, one edge per unordered pair; multi-SUBTREE same-root dups collapse like P16-2's multi-root | test: forced dup closure row → same edge count, meet listed once, score unchanged | batch_cognates_test test_duplicate_closure_rows_collapse_to_one_edge_with_one_meet |
| Query::Etym#ancestors_of | YES — one ancestor naming the same child via several subtree edges | VERIFIED by test: one ancestor Result, edge_borrowed merges true>false>nil (the class-doc claim now pinned) | etym_test test_duplicate_ancestor_naming_edges_collapse_with_merged_edge_borrowed |
| Etym entry-level match (word+roman double-join) | reachable rows, collapsed by uniq(entry_row_id) | pinned via the MW doubled-comparandum test (one entry) | etym_test test_duplicated_mw_comparanda_render_one_entry_with_one_cognate_view |
| ReflexRootsIndexer closure | YES in input (multi-subtree edges) | verified: one (language, lemma_folded, root) row; OR-aggregated borrowed = max_flag, identical to the display merge rule | reflex_roots_indexer_test test_multi_subtree_duplicate_edges_emit_one_row_with_the_display_merge_flag |
| MW comparanda (P17-4) | under ONE entry: yes (senses repeat a comparandum) — covered by the display dedupe; MW vs kaikki naming the same (language, word) under DIFFERENT entries stays two honest witnesses, never merged | test forces the in-entry dup | etym_test (as above); define surface: define_test test_duplicate_reflex_rows_render_one_view_on_the_define_surface |
| MCP nabu_etym / nabu_define | ride Query::Etym/Define → the deduped ReflexViews, never raw rows | pinned by payload test | mcp/tools_test test_etym_and_define_payloads_ride_the_deduped_reflex_views |
| MCP nabu_cognates | rides Query::Cognates | pinned by payload test | mcp/tools_test test_cognates_payload_rides_the_deduped_join |
| links reader (kind groups) | no — unique (from_urn,to_urn,kind) index + write_edge! reverse-direction refresh ⇒ ≤1 row per unordered pair; out/in double-listing needs a self-edge no producer mints | proof in class doc | lib/nabu/query/links.rb |
| parallels loci grouping | no — candidates hash-grouped by document id, one Hit per document; loci = sibling row count | already argued (rider ii, class doc) | lib/nabu/query/parallels.rb |
| formulas star spokes | no — gram counts hash-keyed (one Formula per gram); full loci distinct-passage via per-passage seen-Set; spokes deduped by (hub,locus).minmax seen-set, overlaps counted as coalesced, never silent | already argued (class docs) | lib/nabu/query/formulas.rb; lib/nabu/batch_formulas.rb |
| vocab hapax list | no — tally hash-keyed by folded lemma: a repeated spelling MERGES (un-hapaxes), never doubles; a repeated display string needs one spelling folding two ways in one scope (mixed-language document — no adapter mints one) | proof in class doc | lib/nabu/query/vocab.rb |
| collation cells | no — cells hash-grouped by (language, script); Align yields each registered witness at most once per ref, so each reading lands in one cell once | proof in class doc | lib/nabu/query/collation.rb |

## P18-4 · nabu language CODE — the code desk reference  [tier: opus] [status: done 2026-07-14 — three-layer persistence per the mid-packet owner redirect; findings below] [deps: —]
Owner (2026-07-14, reading etym reflexes): "half of these language codes
means nothing even to (non-specialist) humanists. There needs to be a
nabu language [code] that not only gives language name but also
(possibly historical) context and the language relevance to
corpus/library." Census first: the code universe actually OCCURRING in
the db (documents.language + passage_lemmas.language + reflex
lang_codes — the kaikki etymology codes like zle-ort/gkm/zlw-opl are
the long tail). NAMES: the kaikki descendants data carries the language
NAME per node — check whether the parser sees it and can store/derive
it (zero-curation name source beats a hand-table); fall back to a
generated code→name table from wiktextract's published language data.
CONTEXT: curated one-to-three-line entries for (a) every held corpus/
gold/dictionary language (from languages.md — period, family, what the
library holds), (b) code FAMILIES for the etymology tail (zle-* = East
Slavic historical stages, zlw-* = West Slavic, gkm = Medieval Greek…)
— family-level context is honest and tractable where per-code curation
isn't. RELEVANCE computed live: docs/passages/gold-lemma counts,
dictionary shelves, reflex-edge counts ("appears in N etymology
edges"). Command: `nabu language CODE` (compact card; --long lists
where it appears), unknown code → honest miss + nearest-family hint.
Consider (argue, don't assume): a one-line name hint in etym's grouped
reflex lists where the terminal is wide enough vs keeping the render
compact and pointing at the command. languages.md gains a pointer;
MCP tool deferred unless trivially clean. OWNER DESIGN CHANGE mid-packet
(2026-07-14): "we probably need a per-language info persistence layer
with accumulatable data, not just hardcoded stubs/hit counts" — languages
become a persisted entity: DERIVED layer (names/counts, rebuildable,
catalog) + ACCUMULATED layer (curated context/notes/references,
survives rebuild — journal-style per the links precedent, provenance
per record) + an idempotent git-reviewable seed loader; the command
reads the merged view. Agent re-briefed in flight.
MCP tool deferred unless trivially clean.
MID-PACKET OWNER REDIRECT (2026-07-14): "we probably need a per-language
info persistence layer with accumulatable data, not just hardcoded
stubs/hit counts" — languages became a first-class persisted entity,
designed against the three-temperatures doctrine (§5/§15).
FINDINGS (2026-07-14):
- CENSUS (live db, read-only): documents.language 30 distinct / 170,684
  docs (lat 82,424 · grc 61,080 · eng 9,870 · akk 6,261 · sux 5,905 ·
  cop 2,529 · san-Latn 776 · sl 759 · qpc 601 · ang 354 · + 20 more incl.
  und ×5); passage_lemmas.language 15 distinct / 2.85M rows (lat 583k ·
  orv 455k · grc 379k · akk 361k · cop 233k · sl 214k · san 190k ·
  sux 171k · chu 123k · got 99k · ang 25k · xcl 18k · xhu/uga/hit tiny);
  dictionary_reflexes 803 distinct lang_codes / 1,006,872 rows (sco 144k ·
  en 87k · enm 65k · yol 33k · de 32k · gmw-msc 29k …; tail: 549 codes
  ≤100 rows, 317 codes ≤10). kaikki descendant nodes DO carry a human
  `lang` name — the parser dropped it until now. Mode-of-names per code
  over the 8 held extracts names 787/803 (98%); the 16 unnamed are 12
  malformed abbreviation codes ("Angl.Sax.", "Lat."… — the ML. precedent),
  unk, kdr, xlu-Latn, xmn (script-wrapper-only names). Mode needs a
  plausibility filter: drop "unknown", /script$/ wrappers ("Old Cyrillic
  script" outnumbers "Old Church Slavonic" 1532:919 under cu), and
  non-capital free-text fragments.
- STORAGE VERDICT (three temperatures): DERIVED = language_names census
  in the catalog (migration 011: dictionary_id, lang_code, name,
  occurrences — RAW, filter at read so rule changes need no reparse),
  written wholesale per reflex-bearing dictionary by DictionaryLoader —
  pure function of canonical, regenerated by rebuild; the LIVE db shows
  census names after the next owner-fired rebuild or parse-only shelf
  resync (until then curated names cover the pain codes). lang_name rides
  the DictionaryReflex VALUE only — deliberately NOT stored per row (a
  787-name function duplicated across 1M rows) and NOT in ContentHash
  (pinned: no revision storm). ACCUMULATED = language_notes in the
  LEDGER (ledger migration 004: lang_code, kind[name|family|context|…],
  body, source, created_at) — ledger over own-journal-file because
  authored curation is the most precious temperature (never-dropped,
  always-backed-up file), the Phase-8 enrichment stance already assigns
  authored accretions there, source_probes proves the ledger hosts
  non-run-history state, and append-only FITS (supersession = append +
  read-latest per (code,kind) — provenance history free; links needed its
  own file precisely because reruns must physically replace). SEED =
  config/languages.yml (curation reviewable in git; 183 notes: 33 held
  languages incl. all 7 -pro shelves, 8 pain-tail codes incl. zle-ort/
  ono/mru, zlw-opl/mpl, gkm, rue, cu; 24 family-prefix entries zle/zlw/
  zls/sla/gem/gmw/gmq/ine/iir/inc/pra/ira/xme/xsc/itc/grk/bat/cel/roa/
  sem/urj/cau/crp/frr) loaded by `nabu language --seed`, idempotent
  (append only when latest body differs; duplicate code across sections
  refused loudly — grc nearly ping-ponged). Update path: seed-file
  reload is the shipped path; `--note` write command + agent survey-time
  accretions = future work.
- MERGED READ: Nabu::Languages (catalog+ledger handles, both optional,
  both tables guarded — pre-011 catalog / pre-004 ledger read as no
  data): name = note > filtered census mode > nil; context/family =
  latest note; hyphenated codes fall back to family-prefix notes.
  Query::LanguageInfo computes live relevance (docs/passages excl.
  withdrawn, lemma rows, shelves + entry counts, reflex edges as
  lang_code OR mapped language — one count, --long splits per upstream
  code: chu's edges arrive as cu).
- RENDER VERDICT: inline names in the GROUPED --long reflex render
  ("[gkm · Medieval Greek]" — one name per line, exactly where the
  owner's pain was; benefits define --long too) + one footer line on
  etym ("codes: nabu language CODE — …"); the capped compact list stays
  code-only (ten inline names would blow the line — the compact rule).
  --list ships scoped to HELD languages only (a full 803-code dump is
  unusable; the tail is the card's job — stated in the list footer).
  MCP tool deferred (not trivially clean: needs ledger handle plumbing
  in the MCP server).
- Tests: suite 2,328 runs / 31,500 assertions exit 0, lint exit 0 (30 new
  tests: parser lang_name, ContentHash exclusion pin, loader census raw +
  idempotent + lexica-silent, Languages mode/filter/precedence/fallback/
  degradation/seed-idempotency/duplicate-refusal/shipped-seed-anchors,
  LanguageInfo counts incl. withdrawn exclusion + held scope, CLI
  cards/miss/list/seed/footer/help + 2 updated grouped-render assertions).
  Owner: run `nabu language --seed` once, and the census names land at
  the next rebuild/resync.

## P18-5 · IE-CoR — the cognacy matrix  [tier: opus] [status: done 2026-07-14 — adapter + cldf-csv family + loan flag + language-notes rider shipped, enabled:false awaiting owner sync; findings below] [deps: —]
Owner (2026-07-14): "plan all major unblocked sources from PIE survey…
This batch," with the language-info rider: "extract not only corpus but
also nabu-language info where relevant." docs/pie-survey.md is the spec
(v1-1; fixture sketch §7 approved by the batch directive). IE-CoR
(lexibank/iecor, CC BY 4.0, Zenodo): 160 varieties / 170 concepts /
25,731 lexemes / 4,981 cognate sets. SURFACE (survey verdict): reflexes
ROWS — each cognate set = a dictionary entry (headword = Root_Form,
1,596 laryngeal-notated PIE roots; collective `ine` tag proposal for
mixed-root sets per §1), members = DictionaryReflex rows → 2,261
measured held-pair edges light up etym/cognates/closure/MCP with zero
new query code; 1,036 curated loan events feed the `borrowed` flag.
LANGUAGE-INFO RIDER: IE-CoR's languages table carries per-variety
metadata (names, clades, historical status) — accrete into the P18-4
language layer (language_notes, provenance "iecor"; the named
future-work write path becomes real here: agent/loader accretion with
per-record provenance, seed-file untouched). Honest gaps from the
survey handled as stated (san stem lemmas, hit hyphenated stems, orv
dialect). Migration number IF needed: 014 (P18-6 has 015).

FINDINGS (2026-07-14):
- FETCH VERDICT: the Zenodo VERSIONED record (10.5281/zenodo.13304537 =
  v1.2, one immutable 6.4 MB zip, published md5 matched) via ZipFetch
  with a HARD sha256 pin (RELEASE_SHA256; mismatch aborts before any
  tree mutation) — over GitFetch-of-repo (drags git history for a
  dataset that only moves by minting a new DOI) and GitHub zipballs
  (generated on the fly, NOT byte-stable). New release = new DOI =
  owner re-pins URL+sha (the Coptic RELEASE_TAG pattern). NO migration
  needed — 014 stays free (reflexes/borrowed/language_notes all exist).
- INE DECISION: dictionary language = ISO 639-2 collective `ine`, per
  the survey proposal, decided against per-clade shelves on the frozen-
  URN clincher: Root_Language is a CURATABLE field (v1.2 roots span
  PIE 1,596 / Latin 123 / Sanskrit 102 / … / 639 blank) — keying entry
  identity to it would move entries between dictionaries on upstream
  revision. Costs stated: `ine` is not -pro, so no renderer asterisk
  (upstream Root_Form carries its own, kept VERBATIM incl. ?-doubt) and
  `etym *root`/`define *root` direct-asterisk lookups skip iecor —
  covered from the attested side (etym срьдьцє) and bare define
  (define kerd-), where the cognacy value lives.
- SHAPE: one entry per member-bearing set (4,981; the 58 judgment-less
  rows skip by rule; singletons INCLUDED — a curated root + concept is
  a define surface and can only surface when queried by its own forms).
  Multiform split policy pinned: comma + SPACED slash split, native/
  roman paired by index (mismatch → one unsplit verbatim row). Folds:
  root keeps trailing hyphen (kaikki convention — *k̑erd- ≡ *ḱerd- →
  "kerd-", verified cross-witness), members strip parens + trailing
  hyphen (gold lemmas carry neither). Doubt flags dropped (no home in
  the entry model) — named, not fudged. loans.csv ORs borrowed=true
  into every member edge of an event set (path-grain, the survey's
  explicit hlaibaz rule); non-event members parse false.
- 12-variety map keyed by upstream variety ID (not ISO): the two real
  remaps are Slovene EM slv→sl and grc ×2 collapsing; gmy rides
  honestly off-gold. lang_code = upstream ISO else Glottocode verbatim.
- RIDER: languages.csv → ledger language_notes, kind/provenance
  "iecor" (never name/family/context — programmatic accretion can
  never supersede curation), ONE note per catalog-facing code with
  co-coded varieties grouped (grc, and 14 more multi-variety codes
  measured) so append-only idempotency can't ping-pong. Writer =
  DictionaryLoader#accrete_language_notes (the P18-4 named future
  write path, now real: DictionaryDocument#add_language_note →
  append-only latest-per-(code,kind), guarded pre-004/no-ledger).
  Languages#extra_notes + card render ("iecor: IE-CoR variety: …");
  card miss-guard extended so an extras-only code still gets a card.
- FIXTURES: byte-verbatim trimmed 6-CSV set (13 varieties / 5 sets /
  17 forms+judgments / 1 loan event; csv round-trip verified byte-
  identical before trimming) — heart 6458, loan 1171, calc-only 1846,
  singleton 2280, comma-multiform 1105 (?*pel(h₁)- paren-laryngeal
  fold pin). Fixture render: etym срьдьцє → *k̑erd- [ine] with the 11
  witnesses (got 𐌷𐌰𐌹𐍂𐍄𐍉 (hairto), sl ſerzè); etym кожа → "(loan)";
  language chu → iecor note + census-named card; language lit → card
  from iecor census+note alone.
- PROJECTED LIVE (measured from the full v1.2 tables under the shipped
  policy): 4,981 entries / 26,328 reflex rows (2,308 loan-flagged) /
  1,800 held-language member edges (grc 334 · chu 179 · sl 179 · san
  173 · lat 172 · xcl 170 · ang 170 · hit 148 · got 123 · orv 105 ·
  gmy 47) / 144 language notes. Owner: bin/nabu sync iecor, eyeball
  etym срьдьцє + language chu, flip enabled, rebuild reindex picks the
  closure up.

## P18-6 · LIV-LOD + de Vaan EDL skeleton  [tier: opus] [status: done 2026-07-14 — both CIRCSE shelves READY (enabled: false), findings below] [deps: —]
pie-survey v1-2 + its named v2 sibling, one packet (both CIRCSE, both
Latin/Italic): LIV as Linked Open Data (CC BY-SA w/ publisher
permission, 657 KB Turtle) — 305 laryngeal PIE verbal etymons → 385
Latin entries, joins lat gold through the u/v fold; NEW LAYER: the
verbal-stem-type annotations (survey: a layer nabu has no surface for —
design the minimal honest home, likely entry payload + etym display).
de Vaan EDL skeleton (CC BY-NC-SA → nc): 1,429 Latin headwords staged
through 1,466 Proto-Italic + 1,394 PIE etymons — the Leiden-school
cross-witness beside kaikki's itc-pro (provenance-distinct entries, the
MW precedent). LANGUAGE-INFO RIDER as P18-5. Migration IF needed: 015.

## P18-7 · Postcondition checker + AI-review hook  [tier: opus] [status: done] [deps: —]
FINDINGS (2026-07-14):
- **Turtle verdict: in-house censused-subset reader, no gem.** New parser
  family `lila-ttl` (~200 lines with docs): both files censused
  first-hand — no triple-quoted/multiline literals, no collections, no
  bare numerics, blank nodes only as `[…]` objects (BrillEDL
  canonicalForm, incl. multi-valued writtenRep), one `@en` tag, `^^`
  only on quoted literals, repeated subjects (LIV's Lexicon accretes
  lime:entry), `a`, `;`/`,` lists. Anything outside the census fails
  LOUDLY (ParseError + line). rdf-turtle would drag the rdf gem family
  through the CLAUDE.md bar for two small regular files — declined.
- **Adapter count: TWO adapters, one family.** Forced by the license
  split (BY-SA `attribution` vs BY-NC-SA `nc` — license_class is
  per-source) and by graph shape (LIV: stem-typed themes + prinparlat
  links; EDL: staged etymon→etymon). Both single-file FileFetch of the
  raw URLs (git clone drags history for one data file; raw host serves
  no Last-Modified → manual re-syncs refetch unconditionally, 0.7/3.9 MB).
- **Stem-type surface verdict: entry BODY, nothing else.** One line per
  theme, "present stem *dʰu̯éh₂-/dʰuh₂- → pres suffio" (link-label tails
  carry the Latin PERFECT forms — peperci, lusi — that no writtenRep
  holds); define renders body already, zero schema/query change. Not
  gloss (formations ≠ meanings; the LOD ships no meanings — nil gloss
  honest); no new table for a one-source 426-row layer. The shared
  placeholder theme (label "–") is scoped per-etymon so it never leaks
  other verbs' continuations. **Migration 015 NOT needed** — number
  still free.
- **Shelf layout:** liv = ONE dictionary (ine-pro; 305 etymons, lat
  reflexes, u/v pin uireo↔vireo fixture-tested; ~40-digit upstream
  etymon ids verbatim as entry ids). edl = TWO dictionaries from one
  file (edl-ine-pro 1,394 + edl-itc-pro 1,466; reflexes pie→pit 1,216
  proto-to-proto + pie→lat 27 direct + pit→lat 1,410) — the existing
  shelf-visited etym walk runs rōdō ← *(w)rōde/o‑ ← *Hreh₃d‑e/o‑ with
  zero query change, and two itc-pro witnesses list side by side
  (pinned). U+2011 kept in display, opened to "-" in folds. All 2,653
  links "inheritance" (censused); /borrow/i guard for future loan links.
- **Rider:** language_notes kinds `witness:liv`/`witness:edl`
  (source-laned — never supersede each other or the seed's context
  under latest-per-(code,kind)), provenance column "liv"/"edl";
  accreted idempotently by DictionaryLoader#load_from via new
  Languages.accrete! (the P18-4 "future write path" made real — same
  latest-body rule as seed!); `nabu language CODE` renders witness
  lines. Notes: ine-pro (liv), itc-pro + lat (edl).
- **Projected live counts:** liv 305 entries / 385 lat reflex edges;
  edl 2,860 entries / 2,653 edges across two shelves. Acceptance
  rendered on a scratch root: define *dʰu̯eh₂- (stem line + reflex),
  etym vireo (u/v → LIV), etym rodo (full Leiden chain), language
  itc-pro (EDL witness note + EDL shelf beside kaikki's).
- Suite 2,374 runs / 31,714 assertions exit 0 · lint 303 files exit 0.
  Tests +46 (parser 11, liv 16, edl 16, languages 3). Fixtures:
  test/fixtures/liv (170 lines) + test/fixtures/edl (106 lines),
  byte-verbatim blocks + READMEs + manifests.

## P18-7 · Postcondition checker + AI-review hook  [tier: opus] [status: dispatched] [deps: —]
The owner-designed P18-queue item 5b, now taken (owner 2026-07-14).
MECHANICAL layer (always on, in health/verify): per-source last-run
status surfaced LOUDLY (failed run + partial docs = the Coptic case),
flag-vs-artifact invariants (fuzzy_index vs trigram table, axis
extractors vs row presence, reflex parse code vs crosswalk rows,
language_names table vs filled), enabled-vs-populated, pending
migrations (schema_info vs migration dir), quarantine DELTA vs a
recorded baseline (the standing 9,312 stops shouting; a CHANGE shouts),
projection diffs where the registry/docs state expected counts. AI
layer: OPTIONAL post-sync hook, off by default, tool-agnostic
(structured brief on stdout/stdin; bundled example script wires
`claude -p` + the nabu MCP server) — judgment only. Ledger migration
IF needed: 005 (quarantine baseline lives in the ledger — it must
survive rebuilds).
FINDINGS (2026-07-14):
- INVARIANTS SHIPPED (Health::Invariants, folded into bare `nabu
  health`'s per-source findings + a global slot; findings-only, so a
  green library prints exactly what it printed before): (1) last-run
  honesty — most recent ledger run `failed` → LOUD with the recorded
  error + "re-run"; (2) partial load — the failed run journaled
  provenance rows (the 152-doc Coptic case; provenance is the witness,
  doc- and dictionary-grained) → LOUD, named; (3) enabled-vs-populated
  — enabled + a succeeded run on record + zero docs AND entries (the
  crashed-rebuild signature for never-reached sources) → LOUD; (4)
  fuzzy_index vs trigram index/scope (absent | source outside the
  built passages_trigram_scope | empty) → LOUD; (5) axis extractor
  families (slug→axis_source map off AxisBuilder) vs document_axes
  rows → LOUD, "run rebuild"; (6) Adapter.reflex_bearing? (new
  declaration, true on the two wiktionary adapters) vs
  dictionary_reflexes rows → LOUD, "--parse-only resync"; (7) reflex
  rows vs language_names census → LOUD; (8) quarantine creep (below)
  soft/loud; (9) pending catalog/ledger migrations (schema_info vs
  dir) → SOFT, global. All raw-dataset reads (Verify precedent), every
  missing table degrades silent (pending-migrations says why).
  never_synced note now yields to invariant findings (a failed FIRST
  sync reads "last run FAILED", not "never synced").
- PROJECTION DIFFS: skipped, argued — no machine-readable expectation
  exists (sources.yml counts live in sign-off comments, rot by
  design); an expected_docs: key would stale at every ordinary sync;
  zero-rows + delta rules cover the class.
- ADVANCE-RULE VERDICT (ledger migration 005, quarantine_baselines):
  TWO columns. `baseline` = errored of the last ok sync/rebuild run,
  auto-advances at EVERY ok run → the delta warning (TrendRules
  .quarantine_delta, replaces the absolute rebuild WARNING and the
  sync-time spike check) speaks exactly once per change, silent at
  steady state, drops loud too (upstream churn is signal). `anchor` =
  low-water mark, advances DOWNWARD only → health's creep check
  (TrendRules.quarantine_creep: floor 10, then the shared 5%/15%
  fractions of the anchor; any over-floor drift from a zero anchor is
  loud) keeps the cumulative bleed visible that pure auto-advance
  would absorb step by step — the trend_rules withdrawal-creep
  precedent applied verbatim. Improvement pulls both down (auto
  re-anchor); acceptance of a higher standing level needs no command
  (each step already announced once; the creep line IS the standing
  reminder until triaged).
- HOOK MECHANISM VERDICT: `nabu sync SLUG --review CMD` (flag, not a
  post_sync_review: config key) — syncs here are owner-fired, the
  visible flag keeps the subprocess boundary explicit per invocation,
  and no standing config can rot or surprise an unattended --all.
  ReviewHook emits schema nabu.sync-review/1 (source, sha, counts,
  quarantine vs baseline/anchor, discovery accounting, warning
  messages, ≤5 fresh urns via provenance) to CMD's stdin; output
  relayed as review| lines, exit status reported, NEVER fails the sync
  (spawn failure included). script/review-sync-claude = the bundled
  `claude -p` + nabu MCP example (read-only tools, ≤6-line verdict).
- Healthy-library check: bare `nabu health` output is UNCHANGED on
  green (asserted end-to-end in cli_test).
- Tests: suite 2,388 runs / 31,714 assertions exit 0, lint exit 0
  (60 new: delta/creep rules, baseline record/advance/degrade, each
  invariant red+green, ledger 005 forward-only on a live-shaped
  ledger without loss, sync delta silent-on-baseline/loud-on-change/
  records, rebuild first-records + silent-then-loud-then-silent,
  hook brief shape + stdin pipe + non-fatality incl. unstartable
  command, CLI --review relay + off-by-default + failed-run health).

## P18-gate · Phase 18 gate  [tier: orchestrator] [status: done 2026-07-14] [deps: P18-1..7]
Full-diff, library/languages/README/site refresh (per §10 + the site
duty), improvements register updates, EDH 27-quarantine triage folded
in if not done sooner, PR, owner queue (IE-CoR/LIV syncs owner-fired;
Starostin email in .docs awaiting owner send), backup-disk re-flag
(standing), sticky alarm LAST.

# ── Phase 19 queue (owner-approved in principle, 2026-07-14) ──────────
# Canonical memory (design: .docs/canonical-memory.md — file-first local
# knowledge; owner: "local dev approved for P19 headliner in principle"):
# 1. P19-1 headline: LocalFetch + sync_policy: local + the
#    canonical/local-language/ dossier shelf + P18-4 layer migration
#    (ledger notes + config seed → dossiers; db becomes derived).
# 2. P19-2: canonical/local-library/ (PDFs/scans/articles; manifest,
#    mutool text layer, research_private DEFAULT, links reference edges).
# 3. P19-3: `nabu ingest` — the intake front door (owner: "separate
#    ingest command… possibly interactive/AI-assisted categorization"):
#    copy → derive metadata → categorize (interactive TTY / --assist via
#    the P18-7 hook pattern, AI suggests + owner confirms / scripted
#    --yes) → manifest append → local sync. Deps: P19-2.
# Carried: P18-7 invariant refinement — enabled-vs-populated misses a
#   DISABLED source synced-anyway to zero rows (the liv case: succeeded
#   run + empty shelf, silent because enabled:false; check any source
#   with a succeeded run + zero rows instead),
# Carried: EDH lb-less fallback (P18-gate triage verdict: 26 of the 27
#   quarantines are real inscriptions with NO <lb> markup — fall back to
#   whole-inscription passage grain; 1 is malformed upstream XML
#   (hd059778), honest permanent quarantine; baseline keeps all quiet),
# Damaskini, Slovenian dictionary shelf, OpenEtruscan, Coptic -en
# siblings, scholia/dict-citation links producers, streaming batch
# parallels, tr-hun. Waiting: Starostin reply (starling packet on YES),
# Miklosich/ELEXIS reply, cluster-gated §3.

# ── Phase 19 ──────────────────────────────────────────────────────────

## P19-0 · Site: Contributing + request funnels + maintainer contact  [tier: opus] [status: done] [deps: —]
Owner (2026-07-14, post-#22): "next site revision should include
(probably in About tab) Contributing (worth a separate md document in
docs as well) and Feature/Source requests with the links that lead
directly to opening GH Issue (issues/new), as well as maintainer
contact e-mail Ar Vicco (arvicco@nabu.ac)." Deliverables: (a) GitHub
issue templates (.github/ISSUE_TEMPLATE/: request-a-source,
feature-request, wrong-reading/defect — the pre-wave 0.4 design,
finally built) so the direct links land on useful forms; (b)
CONTRIBUTING.md refreshed (root, 95 lines exist — verify truthfulness
post-P18 and extend: how to request sources/features, the dev-loop
reality, fixture rules for adapter PRs); (c) site About tab: a
Contributing section + "Request a corpus" / "Request a feature" /
"Report a wrong reading" links straight to issues/new?template=…, +
maintainer line "Ar Vicco <arvicco@nabu.ac>"; (d) README contributing
pointer verified consistent.
DONE (2026-07-14): three .md templates + config.yml shipped
(request-a-source / feature-request / wrong-reading; blank issues stay
enabled, contact_links → site home + About — GitHub contact_links
require http(s), so the mailto lives on the About page itself).
CONTRIBUTING truth pass: suite figure added (2,471 tests / 32,142
assertions, dated), dependency list corrected (csv was missing; dev
gems separated), survey list extended (+pie-survey), "Proposing a new
source" grew into "Requesting corpora and features" with the three
direct template links + issues/new/choose, source count 25+3 dated,
maintainer line appended to Security & support. About tab: new
Contributing section (what's welcome + the three direct links +
new/choose) before a slimmed Contact carrying the mailto; "two dozen
sources" → "more than two dozen". README pointer extended by one
clause (templates live in CONTRIBUTING.md), no duplication. Jekyll
build exit 0 (links verified in rendered HTML); suite/lint exit 0.

## P19-1 · Canonical memory: framework + local-language shelf  [tier: opus] [status: done 2026-07-14 — shipped; the REAL export + first sync are OWNER-FIRED, findings below] [deps: —]
The approved headliner (design: /Users/vb/Dev/nabu/.docs/
canonical-memory.md §§0-1,3-4 — read it; owner approved in principle
2026-07-14). LocalFetch + sync_policy: local + canonical/local-language/
dossiers (Markdown, YAML front-matter, provenance-headed accretion
sections) + the P18-4 layer MIGRATION (ledger language_notes +
config/languages.yml seed → dossier files via one-shot exporter; db
records become derived; the ledger table and seed file retire; the
P18-5/6 accretion writers redirect to dossier sections). nabu language
reads the merged view unchanged. Integrity via ledger pins; attic on
deletion; P18-7 invariants extend (dossier files vs language records).

## P19-2 · Site FAQ  [tier: opus] [status: done] [deps: P19-0]
Owner (2026-07-14): "FAQ site section (Q&A Bank from licensing-emails +
think of most common questions - answers should be clear and contain
links to site tabs or md docs with context)." A new site tab: the
licensing Q&A bank generalized (commercial? AI involvement? what is
stored? redistribution?) + the predictable newcomer questions (what is
this / who for; install & first marvel → Quickstart; why no TLG/Brill;
license classes explained; offline/privacy; MCP & AI assistants; how to
request a source / report a wrong reading → the P19-0 funnels; disk
size; platforms; vs Perseus/Scaife; how to cite). Every answer links to
the tab or md doc holding the full context. Academic register, honest
answers (incl. the AI-assisted development one, verbatim from the
framework bank).

## P19-3 · Site News + the release rail  [tier: opus] [status: done] [deps: P19-0]
Owner (2026-07-14): "Site news page (media plan suggestion) - releases
with info about new sources/capabilities. Need to think of the best
gate point to cut the first 'official' release." Deliverables: (a)
site/news — dated entries per release/phase (new sources, new
capabilities, honest numbers), newest first, plus an ATOM/RSS feed
(the media plan's DHNow syndication rail needs a feed to submit); an
inaugural entry summarizing the library as of today, back-referencing
the phase history compactly. (b) The release rail: CITATION.cff
(pre-wave 0.2), a documented release flow (tag → GitHub release notes
distilled from the gate worklog line → news entry → Zenodo DOI mints
on release once the owner links the repo, one-time). (c) Gate duty
extended: every future gate adds a news entry (site/MAINTENANCE.md +
library §10). First-release gate point = OWNER DECISION, orchestrator
recommendation prepared separately (P19 gate, v1.0.0).
DONE (2026-07-14): site/faq.md shipped — 17 questions in 5 clusters
(Getting started: what/who-for, try-in-minutes → Quickstart, needs
(Ruby 3.3/git, 690 MB starter / 16+7 GB full, dated 2026-07-13),
platforms (macOS honest), offline, vs Perseus/Scaife; The library:
what's included (dated counts), why-no-TLG/Brill (license-honest, →
02-sources blocked entries + request-a-source funnel), own PDFs
(local-shelf in active development stated honestly, no backlog leak),
source currency (live/manual/frozen postures + health probes);
Licenses and use: the four classes plain-language, redistribution
per-class, not-commercial (MIT tool, data licenses upstream's), what's
stored (files+SQLite local, nothing leaves); AI: MCP read-only w/
license labels → docs/mcp.md, research_private/restricted default
exclusion (Freising named), AI-assisted development honest answer
(agent loop, Claude models, code open for inspection → dev-loop);
Contributing and contact: the three P19-0 template links + new/choose,
how-to-cite (honest: site+repo+access date, DOI planned), maintainer).
Nav entry FAQ before About (_config.yml); MAINTENANCE gate-duty list
extended with faq.md dated-figure re-check. Every answer 2–5 sentences
with ≥1 contextual link (relative_url internal, absolute GitHub for
repo docs). Gates: jekyll build exit 0; href sweep over built
/faq/index.html — 24 hrefs, all 10 internal resolve in _site, all
linked repo docs/templates exist on disk; suite 2,471/32,142 exit 0;
lint 314 files exit 0. Finding: docs/mcp.md §restricted-exclusion
still says "nothing synced today carries those classes" — stale since
Freising went live as research_private; FAQ follows the newer
sources.md truth, the mcp.md sentence is a one-line gate-duty fix.
DONE (2026-07-14): native Jekyll posts, not a collection —
site/news/_posts/ gives filename dates, newest-first ordering, and
zero-config jekyll-feed coverage; a collection buys nothing here.
Inaugural entry "The library as of today" (2026-07-14) + THREE
retrospectives kept (PR #20 fuzzy+links and #21 sources 2026-07-13,
#22 machinery 2026-07-14, distilled from gates 16–18; verdict: a
one-entry News section gives aggregators nothing to judge cadence by —
three compact entries establish format and history without clutter;
same-day ordering pinned by front-matter times). Feed: jekyll-feed
~> 0.17 (site/Gemfile only, github-pages-whitelisted so
jekyll-build-pages carries it in production) → /feed.xml,
xmllint-valid, 4 entries, absolute URLs correct under baseurl;
feed_meta in the layout head. Nav tail pinned: Sources & Licensing,
[FAQ slot], News, About — FAQ (P19-2) slots directly before News,
About stays last (noted in _config.yml for the merge). CITATION.cff
shipped (cff 1.2.0, structurally validated; version 0.0.0-unreleased +
date-released placeholders, bumped per tag). Release rail = ops.md §12
(chosen over CONTRIBUTING — release-cutting is operator duty;
CONTRIBUTING got a 6-line "Releases & citation" pointer): one-time
Zenodo link, then per-tag checklist (green gate → CITATION bump → tag
→ gh release from the worklog gate line → news post → DOI badge first
time). Gate duty wired: MAINTENANCE.md duty 5 + library §10 duty 1.
News pages link-swept (15 internal links OK), jekyll build exit 0,
suite + lint exit 0.
FINDINGS (2026-07-14): shipped as designed; the doctrine decisions —
(a) canonical-write path: ONE sanctioned gateway per local shelf
(Nabu::LanguageShelf, the Adapter#fetch analogue for authored data;
CLAUDE.md ground rule amended, architecture §16 states it); accretion
refreshes the derived rows incrementally so cards see it without a
re-scan; rebuild replays MAY touch the shelf but only as byte-level
no-ops (idempotent own-section supersession). (b) Migration ordering:
code first (reads fall back to ledger notes per (code, kind)), export
owner-fired (`nabu language --export-dossiers`, idempotent,
absence-filling, --dry-run), ledger-table DROP deferred to a later
packet — it cannot ride this one because write paths auto-migrate the
ledger on open, which would destroy the notes before the export ran.
config/languages.yml deleted NOW (the live ledger holds all 183 seed
notes; exporter still reads a seed yml if a checkout has one).
(c) Conformance subset argued (LexicaTest precedent): manifest/license/
discover-parse/id-identity/uniqueness/stability/NFC mirrored for the
dossier shape; passage-only checks (urns, search form) have no analogue.
(d) LocalFetch attic honesty: it runs AFTER deletion so it cannot attic
vanished bytes — sanctioned retire = move into .attic/ (rediscovers
retained); un-atticked disappearance keeps its pin (health LOUD:
dossiers_vanished) and >20% trips the breaker. Owner-edited dossiers
read as a SOFT stale-derivation nudge, not corruption. (e) Probe cache
needed ledger migration 006 (widen drift CHECK for "local").
OWNER RUNBOOK: nabu language --export-dossiers --dry-run → without
--dry-run → bin/nabu sync local-language → eyeball `nabu language chu`
/ `zle-ort` / `--list`. LATER PACKET: drop ledger_migrate language_notes
after parity (supersession history lives only there until then).

## P19-4 · The local-library shelf  [tier: opus] [status: done 2026-07-14 — shipped; population is owner-by-hand until ingest] [deps: P19-1]
Shelf two of the canonical-memory design (.docs/canonical-memory.md §2;
the queue's "P19-2: local-library" renumbered — site FAQ/News took the
P19-2/3 slots): canonical/local-library/<collection>/ with one
manifest.yml per collection as the SOURCE OF RECORD (file/title/creator/
year/languages/provenance/license_class/tags/related; a YAML list so
`nabu ingest` — the NEXT packet — appends mechanically). Adapter
sync_policy: local on the P19-1 framework (LocalFetch pins, vanished/
attic honesty, §16 write doctrine), documents + passages (FULL
conformance, unlike the dossier shelf): PDF text layer → page-grain
passages via mutool (Nabu::Shell), scans/images → metadata-only
(text_layer: none, HTR-era queue, never quarantined), corrupt files →
quarantine; research_private DEFAULT enforced at the manifest parser
with per-entry upgrades as license_override; manifest related: urns →
kind=reference links-journal edges refreshed at every sync.
DONE (2026-07-14): shipped as specced. VERDICTS — (a) content_kind
stays :passages: the enum routes LOADERS (closed set, "new kind = new
loader"); articles parse to Document+Passage, exactly Store::Loader's
shape, so :article would be a routing word without a loader (and would
skip the document-grain withdrawal trend rule); article-ness =
Document#metadata "kind"=>"article". (b) Page grain argued: the page is
the only citation unit a PDF keeps stable across extractions and the
one scholarship cites — urns …:p<N>, sequence = physical page, blank
pages skipped but numbering preserved; born-digital txt/md get
paragraph ordinals (…:<n> — blank-line paragraphs are authorial there).
(c) related: language codes stay metadata, NOT edges — P19-1 minted no
dossier urns, and an edge to an invented urn would sit permanently
"(not in catalog)"; codes upgrade if dossier documents ever exist.
Counted honestly (Result#skipped_codes). (d) Query::Links counterparts
now resolve passage-grain first then DOCUMENT-grain, so the article
shows beside the passages it discusses from either end. (e) New Adapter
capability flag reference_edges? (beside reflex_bearing?); SyncRunner
refreshes Nabu::LibraryReferences (producer "library", scope=slug,
superseding, score nil, detail=the asserting manifest) after load,
outside the run row (the reindex stance); rebuild never touches the
journal — a lost journal costs one no-network re-sync. (f) Conformance
extended with a marker-driven hook (conformance_metadata_only?, default
false; meta-test pins that an UNDECLARED empty document still fails).
(g) minitest 6 ships no mock/stub → PdfText got an explicit runner:
seam; the adapter takes pdf_text: injection. (h) LocalFetch missing-tree
hint made a pass-through (each shelf names its own front door).
FIXTURES: constructed (cupsfilter, noted in README/manifest) — a REAL
2-page text-layer PDF carrying PD Leskien 1871 text (text layer
verified via PDFKit at construction; mutool NOT installed on this box,
so adapter tests inject the extractor and a guarded live test pins real
mutool substrings when present), a textless scan PDF, an OCS-Cyrillic
.txt (explicit open entry), a PNG plate, a manifested-but-MISSING
entry, an UNMANIFESTED stray. MCP end-to-end pin: shelf hidden by
default, explicit open entry served, include_restricted labels both.
Registered enabled: true (the P19-1 argument verbatim). Docs: arch §16
extension, 02-sources row 55, README one-liner (modest — the story
lands with ingest). Suite 2,568/32,662 exit 0 (1 skip = guarded mutool
live test) · lint 337 files exit 0.

## P19-5 · `nabu ingest` — the intake front door  [tier: opus] [status: done 2026-07-14] [deps: P19-1, P19-4]
The design's §4b (canonical-memory, owner addition 2026-07-14): the
sanctioned intake for local acquisitions. `nabu ingest FILE...
[--collection NAME]` — sha-account (identical MANIFESTED bytes = honest
no-op), COPY (never move) into canonical/local-library/<collection>/,
derive candidates mechanically (PDF Info metadata + first-page sample
via the PdfText seam where mutool exists, filename heuristics + sha256
always), categorize in one of THREE modes (interactive TTY prompts with
candidates prefilled and the research_private default STATED at the
prompt; --assist CMD piping a JSON brief to a subprocess whose suggested
entry PREFILLS the same prompts — the P18-7 hook pattern, bundled
`claude -p` example; --yes + field flags for scripted drops), append the
manifest entry mechanically, then the shelf's ordinary sync + minted
urns + a compact try: epilogue. Same front door for the dossier shelf:
--shelf language CODE scaffolds a skeleton through LanguageShelf.
DONE (2026-07-14): shipped as specced. VERDICTS — (a) default collection
"inbox" over date-based, argued: the collection is a FROZEN urn segment,
so a date default bakes an acquisition accident into identity AND
scatters review across a manifest-per-day; one visible triage collection
with one accumulating manifest keeps the census honest ("prefer
--collection <topic>" stated in help/ops). (b) Second sanctioned write
gateway: Nabu::LibraryShelf (LanguageShelf's sibling — copy_in! never
moves, sha_index for dup detection, append_entry! is APPEND-ONLY: owner
comments/entries never rewritten, result re-validated through
LibraryManifest so a bad append cannot land; refuses manifest.yml/
dotfile names, path-shaped collections, malformed manifests). CLAUDE.md
ground rule + arch §16 updated. (c) Assist brief nabu.ingest-assist/1
(schema-tagged like the ReviewHook): derived candidates + ≤2000-char
sample + field/license vocabulary; capture3 not 2e (a chatty tool must
not corrupt its own JSON); lenient parse (whole stdout, else outermost
{...}); nonzero exit/garbage = advisory note, mechanical candidates
stand; suggestion only ever PREFILLS — flags beat assist beats derived;
script/ingest-assist-claude wires claude -p + nabu MCP (search/show —
related: urns looked up, not invented). (d) Resolver seam: the three
modes are ONE injectable interface (PromptResolver with a plain ask
callable — CLI wires Thor ask; AcceptResolver for --yes); non-TTY
without --yes refuses honestly BEFORE any copy. (e) Idempotency ladder:
manifested dup sha = no-op naming the existing home; UNMANIFESTED
identical copy (aborted earlier ingest) does NOT block — the re-run
finishes the cataloguing; same name + new bytes = copy replaced, entry
kept, the loader's revision story at sync; bad file named, rest proceed,
exit 1 at end. (f) Manifest writes OMIT license_class at the
research_private default (fixture-file doctrine: silence means the
conservative class; an explicit class marks an owner override) and OMIT
empty lanes; keys in manifest order. (g) Year precedence fixed by live
transcript: PDF Title/Author beat filename guesses, but CreationDate
year only fills ABSENCE (a scan's CreationDate is the scan date; the
author-year-title filename year is the publication year). (h) --shelf
language kept THIN: name/family/context prompts (family prefilled from
the code's hyphen prefix), LanguageDossier skeleton via LanguageShelf,
dossier sync, `try: nabu language CODE`; existing dossier = no-op
pointing at the file. (i) DRIVE-BY FIX exposed by this box's newly
installed mutool 1.26: PdfText.pages kept the trailing "\f\n" fragment
as a phantom third page — whitespace-only tail after the final \f now
drops (regression test; the P19-4 guarded live test runs green, 0 skips
now). Epilogue: show always; search hint only when text was extracted
(word from the sample, --license = the entry's effective class);
links hint when related urns were given. Docs: README paragraph (the
"add your own material" story) + example, site/tools.md Stewardship
(argued over quickstart: ingest is command surface, not the
zero-to-first-marvel path — one place only), ops.md §13, CONTRIBUTING
pointer ("your own PDFs need no adapter"), arch §16 truth pass,
sources.yml comment. Tests +45 (engine 24 incl. real-subprocess Assist,
gateway 11, PdfText.info 3 + phantom-page regression, CLI 8 e2e on
scratch roots incl. --shelf language). Interactive flow verified live
via PTY on a scratch root (real mutool derivation end to end). Suite
2,616/32,881 exit 0 (0 skips) · lint 341 files exit 0.

## P19-gate · Phase 19 gate — the v1.0.0 release gate  [tier: orchestrator] [status: done 2026-07-14] [deps: P19-0..5]
Full-diff, docs+site truthed (16 dictionaries / 458,238 entries /
170,711 docs / 4.27M passages verified live), news post = the release
announcement, FAQ #9 → YES, register §3.4 intake-half + §4.3/§4.6
updated. PR #23; on owner merge: ops §12 release checklist cuts
v1.0.0 (owner-blessed version pending final word), DOI mints if the
Zenodo toggle is on. Owner queue: first real `nabu ingest`; the
licensing send queue (GORAZD next); backup disk (standing).

# ── Phase 20 ──────────────────────────────────────────────────────────

## P20-0 · ingest URL intake  [tier: opus] [status: done 2026-07-14] [deps: —]
Owner incident (2026-07-14): `bin/nabu ingest https://archive.org/
download/handbuchderaltbu00lesk/….pdf` printed the categorize header,
THEN failed with ENOENT on the url. Verdict: "I see no reason why it
shouldn't ingest both local and url pdfs."
DONE (2026-07-14): http(s) arguments are DOWNLOADED first into a
Dir.mktmpdir staging pass, then flow through the unchanged intake
(copy → derive → categorize in all three modes → append → shelf sync);
the staging dir dissolves after the batch — the shelf copy is the
record, and for a url the staging copy IS the original (ingest still
never moves anything). VERDICTS — (a) New Nabu::UrlDownload (ZipFetch/
FileFetch's one-shot sibling; NOT a sync path — no retention contract,
no state file): bounded manual redirect loop over 301/302/303/307/308,
max 5 hops then an honest error, relative Location via URI.join
(archive.org's mirror 302 is the motivating case), body binwritten,
shared cert-hardened ZipFetch.default_http, http:-injectable — no new
gem, no middleware. (b) Filename: Content-Disposition filename=
(quotes stripped, path components dropped) beats the percent-decoded
FINAL-url basename; an extension-less final basename (mirror handler
garbage à la /fetch?id=) falls back to the ORIGINAL url's; numbered
suffix on staging collisions. (c) Provenance (deep-extraction): the
manifest entry records the ORIGINAL url in a new source_url: lane
(LibraryManifest schema + validation, omit-when-empty, after
provenance in manifest key order; mirror-final urls rotate — the
owner's url is the stable identity); recorded mechanically, NEVER
prompted; the provenance candidate names the url (not the ephemeral
staging path) so the categorize display surfaces it; local ingests get
no lane; the adapter rides it into document metadata beside
provenance. (d) BOTH incident UX defects fixed: the engine's staging
pass settles EVERY argument (downloads complete, local existence
checked) before any categorization, and the CLI's categorize header
now prints at the FIRST prompt, not at resolver construction — a
failed batch shows one honest FAILED line per defect (HTTP status /
transport message for urls, ENOENT for files), others proceed, exit 1
at the end (the existing ladder, ordered correctly). Tests +26
(UrlDownload 13 incl. loop cap/relative Location/CD filename/
transport; engine url intake 7 incl. staging-before-prompt ordering +
staging-dir cleanup + 404-means-untouched-shelf; manifest lane 2;
adapter pass-through 1; CLI 3 e2e incl. the header-order regression
under a tty-claiming stdin double) — WebMock throughout, no network.
Docs: cli desc/long_desc + url example, ops.md §13, README paragraph;
site/tools.md untouched (its wording stays true — additive
capability). Suite 2,642/32,974 exit 0 (0 skips) · lint 343 files
exit 0.

## P20-1 · ingest validates before append  [tier: opus] [status: done 2026-07-14] [deps: P20-0]
Owner incident (2026-07-14, live library): the categorize languages
prompt accepted `chu (body ger)` (pasted from a scout doc), the entry
appended, and only the SHELF SYNC exploded (model validation.rb:44) —
the manifest stayed poisoned, every later local-library sync failed
until hand-repair; a second live find catalogued the EXECUTABLE
bin/nabu itself. Mid-packet owner doctrine upgrade: "the changes
should be atomic as well — either everything succeeds or fails, and
if it fails it doesn't pollute canonical."
DONE (2026-07-14): `nabu ingest` is ATOMIC TWO-PHASE (the GitFetch/
ZipFetch prepare/complete mirror) — a batch lands WHOLE or leaves
canonical/ byte-identical. PREPARE (all fallible work, staging only,
zero canonical writes): downloads + existence checks (P20-0's staging
pass) + NEW executables-refused guardrail (mode +x, one honest line —
no shelf material runs), sha-account, derive, categorize, entry
construction, then a REHEARSAL: the collection's future manifest
(existing bytes + every new entry, rendered by the same render_entry
the append uses) round-trips through the REAL LibraryManifest parser
against a staging file — an entry the loader would reject cannot
exist, whatever rules the loader grows; intra-batch duplicate names
surface here too. COMMIT (only after the whole batch validated): per
file copy_in! + append_entry!, a freak append failure compensating-
deletes that file's copy (new LibraryShelf#remove_copy!, refuses
manifested files); append_entry! itself also now ROLLS BACK a
rejected append (truncate/delete) as the last-gate belt. VERDICT
CHANGE, owner-ordered: any prepare defect aborts the WHOLE batch —
one named FAILED line per defect, other files print `aborted`
(new Outcome status, yellow), canonical untouched, exit 1; replaces
P19-5's bad-file-named-rest-proceed ladder (it let a typo'd batch
half-land; the owner lived the cleanup) — and a doomed batch asks NO
categorize questions (defects known at staging skip prompts).
VALIDATION per mode, one shared rule (Ingest.field_error: languages
via the model's LANGUAGE_SHAPE — reused, never a second regex;
license_class vocab): interactive RE-PROMPTS with a one-line reason
(`! "chu (body ger)" is not a language tag — give comma-separated
codes like: chu, deu`; PromptResolver warn: lane, CLI says it yellow)
until valid or '-'-cleared — an assist suggestion only ever prefills
this guarded prompt; --yes/scripted raise the same message from
build_entry, failing the batch in prepare. FOUNDATION: LibraryManifest
now validates language tags at PARSE (Model::Validation.language!
reused, FormatError naming file + entry index like every per-entry
defect) — a hand-edited bad manifest fails at load, early and named,
never deep in the loader scan. Residual crash window stated honestly:
kill -9 between copy and append leaves one unmanifested file; the
next sync's discovery census names it LOUDLY (unrecognized ≥ 1 path).
RIDER: the try: epilogue's search hint picks the first ALPHABETIC
word ≥ 4 (Unicode letters — Greek/Cyrillic count; edge punctuation
stripped, digit/symbol-riddled tokens skipped): the live Leskien
smoke's `search 01assJ£` junk is gone, an all-garbage sample omits
the hint. Tests +20 (manifest parse 2; gateway rollback 2; engine 13
net incl. re-prompt bad-then-good, '-' escape, yes-mode pre-append
refusal, incident regression across all modes, atomic aborts for
ENOENT/404-in-mixed-batch/executable, freak-append rollback,
intra-batch dup at rehearsal, staging-defect-asks-nothing, rider 3;
CLI e2e 3 incl. whole-batch abort + executable refusal) — WebMock,
no network. Docs: cli long_desc atomicity paragraph, ops §13 rewritten
(atomic + executables + crash window), arch §16 truth pass. Suite
2,662/33,056 exit 0 (0 skips) · lint 343 files exit 0.

# ── Phase 21 ──────────────────────────────────────────────────────────

## P21-0 · UrlDownload names cross the boundary UTF-8 NFC  [tier: orchestrator, hotfix] [status: done 2026-07-14] [deps: —]
Live crash, owner's seventh url ingest (Linguistica Brunensia, OJS):
Content-Disposition filenames arrive as raw UTF-8 bytes in a
BINARY-encoded header value ("37850-Text článku-….pdf"); the derived
name reached the engine ASCII-8BIT, the success message's UTF-8
interpolation raised Encoding::CompatibilityError AFTER copy+append had
landed (canonical stayed CONSISTENT — the atomic contract held — but
the manifest serialized the file lane as a YAML !binary blob and the
run died before the shelf sync). FIX at the one choke point every
derived name crosses (UrlDownload#sanitize, the adapter boundary, the
house text rule): force UTF-8, scrub undecodable bytes to U+FFFD,
Normalize.nfc — Content-Disposition and percent-decoded url basenames
alike (NFD e+combining-acute composes). Tests +3 with the offending
bytes as fixture (BINARY CD header w/ UTF-8 bytes → UTF-8 NFC name;
NFD percent-encoding → composed; invalid byte → honest U+FFFD).
LIVE REPAIRS (owner tree, disclosed): articles manifest !binary lane →
plain string; shelf resync (9 local-library docs live). Live smoke: the
exact crashing url end to end on a scratch root, exit 0, plain-string
manifest lane. Suite 2,665 exit 0 · lint 343 exit 0.

# ── Phase 21 queue (licensing replies landed 2026-07-15) ──────────────
# 1. STARLING PACKET UNBLOCKED: G. Starostin granted any-use-with-
#    attribution (per-base compiler credit REQUIRED — roster at
#    starlingdb.org/descrip.php; his non-consensus caveat rides verbatim,
#    the Larth-caveat treatment). Owner pre-approved "starling packet on
#    YES" (2026-07-13) — scope: StarLing-format parser + Pokorny IE base
#    adapter, class attribution, grant email as license basis
#    (pie-survey §3.1 census stands). Dispatch at owner's word.
# 2. ETP CLOSED (Wallace: database no longer exists) — Etruscan axis
#    rests on OpenEtruscan alone; its adapter packet already queued.
# 3. CATSS DECLINED (Tov: commercial, Accordance) — LXX position
#    unchanged (Swete held); CCAT-declaration route now doubtful,
#    02-sources row 44 updated.
# Send queue rest: GORAZD (#2) still first among unsent.

# ── Phase 22 ──────────────────────────────────────────────────────────

## P22-0 · starling adapter (StarLing parser + Pokorny/PIET)  [tier: fable] [status: done 2026-07-15 — parser family + adapter shipped, enabled:false awaiting owner sync+flip; verdicts below] [deps: —]
The unlock: G. Starostin's e-mail grant 2026-07-15 ("all etymological
data are free for anybody to use for any purposes as long as the source
is properly acknowledged") with the EXPRESS per-base compiler-credit
condition (roster: starlingdb.org/descrip.php?lan=en#bases) and the
non-consensus caveat carried verbatim (the Larth treatment). Owner
pre-approved ("go ahead with starling packet", 2026-07-15). Scope: ONE
parser family (starling-dbf) + ONE adapter (slug starling), pokorny +
piet only; germet/baltet/vasmer are follow-up configuration.

FINDINGS (2026-07-15):
- ENCODING VERDICT (the packet's hard part): the survey's /startrac/
  source tree 404s live; the authority used instead is the OFFICIAL
  current package — starling_3.9.0-20251128_amd64.deb, whose own
  config.str wires convert/unipro.lst ("fully Unicode compatible",
  1,134 forward mappings + 17 alias rows) as THE Unicode conversion.
  unipro.lst is vendored VERBATIM (config/starling/, sha256 + provenance
  README) and drives a longest-match trie decoder (Nabu::StarlingText)
  — no byte meaning guessed, alias rows resolved through the table
  itself. Structure from the package's help/encoding.htm: \x01–\x07
  open doublebyte sets (IE bases use set 1 only — \x01\x83/\x01\x85
  Greek + combining), any byte <0x80 terminates, \x7F invisible
  breaker, \B\I\C\U\L\H markup stripped; \x15 = paragraph mark (live
  site renders <P>) → "\n". Table sequences deliberately span mode
  transitions (α+\x7F+macron = one ᾱ entry) — the trie walks with the
  shift byte virtually prefixed. VERIFIED against the live starlingdb
  CGI rendering of the same records (2026-07-15): pokorny #1 (\xB0→ā;
  \x01\x83\xC2\x83\xC0→ἆ — the survey's byte run, its ellipsis resolved:
  ἆ is the FOUR-byte run, \x01\x83\xC2 alone is bare α), #34 (αἰγίλωψ
  across continuing pairs), #284 (\x1Da→æ), #1089 (kʷel-1; cīrṇá),
  piet #1/#562/#1501 (утро, ayarə, kaṇṭhá-, collus). FULL-CORPUS decode
  census: 41,329 non-empty cells over 5,513 records decode with ONE
  unmapped pair — \x80\xA8 after τέλλω in pokorny #1089 (upstream
  stray; the official converter silently drops it) → honest U+FFFD,
  fixture-pinned. dBase III layer: length-6 C cells with descriptor
  byte 12 = "V" are var-pointers (uint32 offset + uint16 length into
  .var); pokorny carries a trailing 0x1A EOF, piet does not (both real,
  both handled); zero deleted records in either base.
- REFLEX VERDICT (deep-extraction mandate, censused on the full base
  before promising): piet branch columns are scholarly PROSE (variants,
  grammar tags, glosses, dialect prefixes), not word lists — whole-cell
  reflex rows would poison the crosswalk. The honest slice: the six
  SINGLE-LANGUAGE attested columns (HITT→hit, IND→san, AVEST→ae,
  ARM→xcl, LAT→lat, ALB→sq) mint ONE row per cell — the LEADING
  citation form only, gated by a clean-token shape (dialect-prefixed
  "Khow. yor" and ?-doubt cells mint nothing; the gate self-filters the
  census's dirty classes). lang_code = upstream column name verbatim,
  lang_name = the .inf field alias (feeds the language_names census →
  reflex_bearing health invariants hold). Projected ~4.4k rows (LAT
  1,386 · IND 1,335 · AVEST 652 · ARM 486 · HITT 323 · ALB 230 of
  clean-first-token cells). NO rows from: GREEK (Starostin Latin
  transcription — script-mismatched against grc gold; 80% clean would
  still join nothing), SLAV/BALT/GERM (Nikolayev-notation branch
  PROTOFORMS, morpheme-segmented (*xáls-a-), a rival notation whose
  honest lane is the body + the SLAVNUM/BALTNUM/GERMNUM links into the
  subordinate bases — live joins when germet/baltet/vasmer land as
  config), IRAN/ITAL/CELT/TOKH (multi-language cells — rows would
  invent language codes). Every column rides the entry BODY verbatim
  regardless (labeled with the upstream .inf aliases).
- CROSSLINK SEMANTICS (read from the in-package .inf files, which
  correct the survey's guess): pokorny.PIET → piet NUMBER; piet's
  REFERNUM = "Pokorny" (NOT a references table), PRNUM = "Nostratic
  etymology" (nostret, out of package), SLAVNUM = "Vasmer", BALTNUM/
  GERMNUM = the Baltic/Germanic subordinate bases. Both directions
  preserved as body lines ("PIE database: #562" / "Pokorny: #1089" —
  the numbers ARE the shelves' entry ids); fixture pair pokorny #1089 ⇄
  piet #562 pins it both ways.
- LEMMATIZATION: both shelves ine-pro (piet is laryngeal-free
  traditional notation — a second ine-pro witness, provenance-distinct
  from kaikki/LIV; the define-unification lane is the §9 ine PROTO
  fold). headword verbatim (homonym digits kept in display: bher-1),
  key_raw keeps the asterisk; headword_folded = FIRST comma-variant,
  ?/* prefix + parens off, IEW homonym digit off, trailing hyphen KEPT
  (the iecor/kaikki root-fold convention): "kʷel-1, kʷelə-" → "kwel-".
  Starostin palatal apostrophes (*k'īgh-) fold as-typed — cross-
  notation unification with kaikki ḱ is NOT forced (journal: honest
  non-join; the closure sees this shelf through its reflex rows).
- ATTRIBUTION LANE: the grant + BOTH per-base credits travel in
  MANIFEST.license → sources.license → every define/etym/cognates/MCP
  result row (fixture-tested on a define render); sources.yml row +
  02-sources row 56 carry the caveat verbatim.
- FIXTURES: real-byte rebuilds (header/descriptors/record bytes + var
  payloads verbatim; only nrec + the 6-byte pointers rewritten to a
  compacted .var) — pokorny #1/#721/#1089, piet #1/#562/#1501, each
  decode web-verified; manifest.yml + README with grant, sha256s,
  selection rationale. Conformance: dictionary-shaped, so the passage
  suite is MIRRORED (the LivTest/MwTest house form) — manifest/round-
  trip/uniqueness/stability/NFC + loader idempotency + rider + renders.
- docs/library.md NOT extended with the shelf (truthfulness: its
  numbers read from the live catalog; starling is not in it yet) —
  only the registry sentence updated to 31 sources / 30 enabled.
- Owner queue: bin/nabu sync starling (6.2 MB; projected 2,222 + 3,291
  entries, ~4.4k reflex rows, 1 ine-pro note), eyeball define '*bher-'
  (credit line) + etym collum-class walks + the ONE U+FFFD in pokorny
  #1089, then flip enabled + rebuild for the closure reindex.

## P22-2 · show resolves dictionary-entry urns  [tier: orchestrator, in-PR] [status: done 2026-07-15] [deps: —]
Owner repro (first starling browse): `define '*kreu-'` prints
`urn:nabu:dict:starling-pokorny:1040` on the headline; `show <that urn>`
→ "urn not found". Corpus-wide gap since the dict shelf existed (lsj
urns missed identically) — define INVITES the show. FIX: Define#by_urn
(one entry by minted urn, entry_columns extracted for reuse; withdrawn
entries resolve FLAGGED — show's hides-nothing contract, not define's
live-shelf lookup; Result gains withdrawn, default false),
Query::Show#run routes the urn:nabu:dict: prefix there
(table_exists-guarded), CLI print_show dispatches to the extracted
print_define_entry (one renderer, no divergence; "(withdrawn)" tag),
MCP nabu_show → define_payload with the SAME license-withholding rule
(research_private entries withheld as ever). Reflex attested-counts
read nil under show (no fulltext dependency added — honest absence).
Tests +5 (by_urn ×3 incl. withdrawn, Show routing, MCP payload) + CLI
e2e of the exact owner repro. Suite exit 0 · lint exit 0.

## P22-1 · `nabu list SOURCE` + `--source` filter on search/export  [tier: agent] [status: done 2026-07-15] [deps: —]

Owner-approved semantics (2026-07-15): "nabu list source semantics
(general shelf info/stats by default, --documents --entries
--collections --limit - other useful filters you can think of? Sure,
plus a --source filter on search/export". Gap: no CLI way to enumerate
a shelf's contents — the owner had to be handed a sqlite3 one-liner.

SHIPPED — `nabu list [SOURCE]`, the WHAT-IS-HELD view (status = the
sync-state view; each command's help names the other, the
discoverability pair):

- Bare census: one line per catalog source — docs=/pass= (live,
  StatusReport counting semantics), entries= (dictionary shelves),
  langs= (codes when ≤3, count when more; passage ∪ dictionary
  languages), license= (distinct EFFECTIVE classes — document overrides
  included; declared class when empty), withdrawn=/retired= only when
  nonzero (conventions §10, zero-suppression). Footer totals.
- `list SOURCE` card: slug — name, adapter + registry sync policy +
  enabled (NOT IN REGISTRY reads loudly when a catalog source lost its
  registry row), license class(es) + the source's free-text
  license/credit line when it carries one (truncated to one line),
  counts, per-language passage breakdown, per-dictionary entries,
  date-axis coverage (dated docs + min..max signed years, `open` for a
  NULL bound), facet summary (facet=N values/M docs), collections
  (inline ≤8, else a count pointing at --collections). Bounded — a
  card, not a dump.
- `--documents`: urn — title [lang] license, urn order, withdrawn/
  retired flagged inline; filters --lang/--license/--withdrawn (ONLY
  withdrawn/retired — the stewardship lens)/--from/--to/--century
  (reuses CatalogJoin#axis_exists — the date join was already
  document-grain-correlated, so reuse was cheap; require_axis! guard
  as in search). Default --limit 50, 0 = all, honest "… N more —
  raise --limit (0 = all)" tail (Page carries the true total).
- `--entries`: headword [dict] — gloss (one line, collapsed), live
  entries, (dictionary, entry_id) order; --lang = dictionary language;
  --prefix STR = FOLDED headword prefix via the full
  Normalize.query_forms variant union ORed as byte-range prefixes
  (rides the headword_folded index, nothing to escape — the
  Scope#prefix_match precedent; ASCII bh finds *bʰer-, leading *
  stripped). Non-dictionary source: one honest line, exit 0.
- `--collections`: collection → doc count, censused MECHANICALLY from
  the urn shape urn:nabu:<slug>:<collection>:<rest> (≥2 segments after
  the source prefix) — local-library reads exactly as filed, any
  nested nabu-urn source (ddbdp series) censuses honestly, CTS shelves
  miss honestly (exit 0). VERDICT: no adapter/registry flag needed;
  the urn IS the manifest structure.
- Flag grammar validated up front: one enumeration mode per invocation;
  SOURCE required for modes; --prefix entries-only; --license/
  --withdrawn/date filters documents-only; --lang documents/entries.
  Every misuse is a NAMED error, never a silently ignored flag.
- `--source SLUG` on search AND export: threaded as `source:` through
  CatalogJoin#visible_passages/#catalog_rows (one place, the
  visibility-rule module) so it composes with EVERY search path —
  plain FTS, --lemma (+--morph), --near, --fuzzy — and all
  lang/license/date/place/facet filters; Export gets the same clause
  in its own dataset builder. Validated CLI-side against the catalog
  with the define-miss pattern (unknown slug → the valid slugs, exit 1)
  so an unknown source is never a silent empty result.

DESIGN VERDICTS (journaled):
- --prefix stays ENTRIES-ONLY: a urn-prefix filter on --documents does
  NOT fall out of the folding helpers (urns are never folded; prefix
  semantics would differ per shelf) — out, said in help via omission.
- INDEX verdict: NO migration. The --source filter lands on the
  already-joined sources row (documents.source_id indexed since 001,
  sources.slug unique); FTS hit resolution stays an id-list join
  bounded by INNER_LIMIT_FACTOR — nothing quadratic to index away
  (012/013 addressed per-passage language lookups; there is no
  per-passage source column and none is needed). Known tradeoff
  (same as --lang/--license): a rare --source may under-fill a page
  since filtering is catalog-side after the inner FTS limit.
- --source deliberately NOT added to concord/parallels/etc. — the
  owner named search + export; the CatalogJoin threading makes the
  future addition one kwarg each.
- census/card read the CATALOG (held content); registry supplies only
  the card's policy/enabled line — an unsynced registered source is
  status's story, not list's.

Tests +40 (query/list_test 22 on sqlite::memory: with migrations;
search/export query tests +2 source-filter; CLI e2e +16: census, card,
dictionary card, unknown-source miss, documents flags+tail+filters
(--lang/--license/--withdrawn/--century), entries+--prefix folding,
passage-shelf entries miss exit 0, collections census + honest miss,
flag guards, search/export --source + unknown miss, help anchors both
directions of the status/list pair). Docs: cli help (list long_desc,
status long_desc naming list, search/export --source), README feature
tour (+list row, --source in search/export rows); docs/ops.md and
site/tools.md untouched (no enumerated command list goes false).
Suite 2,704 runs / 33,259 assertions exit 0 · lint 345 files exit 0.
LIVE-GAP FIX (owner report, 2026-07-15, in-PR): the dossier shelf
(language grain, no documents) rendered as `empty` — census/card now
count dossiers (198) + records-by-kind, `--documents` enumerates
`code — Name [family]` with --prefix/--limit (other document filters
= named inapplicability), document-grain --prefix also a NAMED error
(was a silent no-match). Grain detected from adapter_class in the
catalog, never the registry; guarded on table_exists (read surfaces
never migrate). Tests +7.


# ── Phase 23 ──────────────────────────────────────────────────────────

## P23-3 · loop-health trio  [tier: agent] [status: done 2026-07-16] [deps: —]
Three small owner-approved fixes, each bitten live (packet spec verbatim
from the P19-queue carried items + the 2026-07-14 status defects).

(a) INVARIANT REFINEMENT — synced-vs-populated. The liv case
(2026-07-14): a DISABLED source synced anyway to zero entries —
succeeded run, empty shelf, silent because enabled-vs-populated watched
enabled sources only. Health::Invariants#synced_unpopulated now gates on
the LATEST run having succeeded (a failed latest run stays
last-run-honesty's single loud line) and NEVER on `enabled`; the
populated test keeps its per-grain routing (live documents / dictionary
entries / language_records — the P22-1 grain knowledge). VERDICT: no
exemption mechanism ships — reality checked first (2026-07-15 census of
the live catalog): every one of the 31 sources is populated in its own
grain (local-language holds 330 language_records), so an
honestly-empty-by-design source does not exist to exempt; the mechanism
gets built if one ever does.

(b) STATUS FLIP-RECONCILE — registry is AUTHORITATIVE for enablement.
Registry `enabled:` flips reached db sources.enabled only at that
source's next sync (2026-07-14: mw/iecor/liv/edl read off in status
after the owner flipped them on; orchestrator hand-reconciled).
VERDICT: option (1), READ-side registry truth — no write path (`nabu
status` opens the catalog read-only-ish; a write-back at status time
was rejected as a read surface mutating state). StatusReport renders
entry.enabled directly (every status line IS a registry entry — no
orphan fallback needed there); the list card already rendered registry
truth via registry_fragment (pinned with a regression test) and the
P22-1 NOT IN REGISTRY loud-orphan case is pinned too; MCP nabu_status
gets the same rule (Tools takes registry:, wired like alignments) —
registry value for registered slugs, db value kept for unregistered
catalog orphans, the one surface that enumerates them. Regression
tests: flip in registry with no sync → status/list/MCP show registry
truth, both directions.

(c) EDH LB-LESS FALLBACK — landed, with the triage's mechanism claim
CORRECTED BY THE BYTES. The P18-gate verdict said the 26 real
quarantines have "no <lb> line markup"; canonical inspection of all 26
shows every one HAS <lb> milestones (mostly n="0") — each line extracts
gap markers only, i.e. the WHOLE edition is lost lines (CSV atext
'[------]'/'[---]'/'//', zero readable text anywhere). VERDICT: the
owner-approved remedy stands and generalizes — when line grain mints
ZERO passages, EdhEpidocParser falls back to ONE whole-inscription
passage carrying the edition's full extraction (its own lacuna
notation, '[…] […]') under the stable flat suffix :text
(collision-free by construction — minted only when no line suffix
exists; no textpart path: whole-inscription grain); edition <head>
joins the dropped elements. hd059778 (malformed upstream XML) raises
before extraction — the honest permanent quarantine. Per-source policy
(the del-⟦…⟧ precedent): DDbDP's empty-<ab/> stubs keep quarantining.
BASELINE VERDICT: the P18-7 machinery handles the 26 leaving BY DESIGN
— delta announces the -26 exactly once at the landing run, record!
advances baseline AND anchor down to 1 (an improvement resets the
low-water mark), creep never trips; regression-pinned, no migration/
surgery. Fixtures: HD029093 + HD081183 byte-identical from
canonical/edh + their text-CSV rows (whole physical lines; no pers
rows); rebuild e2e replays 5 records (19 facet rows, 5 axis rows).

Tests +13 net (invariants 4 reshaped, baseline story 1, status flip 1,
MCP registry 1, list-card 2, parser fallback 6, adapter/rebuild
expectations updated to 5 fixture records). Docs: ops.md §anomalies +
§11 table, architecture sources-mirror note + invariants wording,
README/library.md invariant name, source_registry authority comment,
edh-survey status block, 02-sources row 94 (EDH, ex-51; status LIVE + fixture
list). Owner queue: `bin/nabu sync edh --parse-only` lands the 26
(+26 docs, errored 27→1, one loud -26 delta line, then quiet).

## P23-2 · Slovenian dictionary shelf (Pleteršnik / JSV / besedje16)  [tier: fable] [status: done 2026-07-15 — zrc-xml family + sl-lexica adapter shipped, enabled:false awaiting owner sync+flip; verdicts below] [deps: —]

Owner-approved 2026-07-15 (queued since the P17-6 CLARIN.SI survey,
docs/clarin-si-survey.md §2): the three ZRC SAZU dictionary deposits
that give the sl axis what LSJ/L&S/B-T gave grc/lat/ang, keyed to the
goo300k/IMP corpora already held. SHIPPED: parser family `zrc-xml`
(flat ZRC SAZU dictionary XML, NOT TEI — streamed via XML::Reader, the
>5 MB rule) + `SlLexica` adapter (`sl-lexica` source, three
dictionaries pletersnik/jsv/besedje16), three-zip ZipFetch (per-dict
subdir + state + attic, the ORACC recipe on goo300k's CLARIN.SI URL
pattern), registry row `enabled: false` / `sync_policy: manual`,
conformance-mirror tests + idempotent double-load + define renders.

CENSUS VERDICTS (fetched to scratch 2026-07-15, one GET per artifact):
- **One source, not three.** All three records carry the IDENTICAL
  verbatim grant — dc.rights "Creative Commons - Attribution 4.0
  International (CC BY 4.0)", label PUB → `attribution` — same
  publisher conventions (`geslo-id` entry-per-line XML + XSD), same
  fetch shape; no license/posture split demands per-artifact sources
  (the lexica LSJ/L&S precedent).
- **Counts:** pletersnik 103,185 (= description), jsv 8,461 counted vs
  8,540 described (upstream delta, reported honestly in fixtures README
  + 02-sources), besedje16 27,759. All geslo-ids unique per file.
- **Language = `sl` for all three** (besedje16 included): headwords are
  MODERNIZED orthography by editorial design — exactly what goo300k's
  gold lemmas speak — so a period subtag/marker would fracture the
  define/gloss joins for no gain. The period lives in dictionary
  titles + the `witness:sl-lexica` language note.
- **Pleteršnik headword split:** display headword = accented `<oi>`
  (tonemes: abecę̑da), `headword_folded` from unaccented `<ge>` — the
  generic §9 mark strip folds tonemes, but `<oi>` spellings carry ə/ł
  (ábəł) that no modern query types; ge "abel" is the real key. No new
  conventions §9 rule needed (sl ſ→s + generic strip suffice — the
  survey's toneme-folding question, settled at fixture time).
- **JSV citations minted UNRESOLVED:** every `<ct>` → DictionaryCitation
  with urn_raw/label verbatim ("(I/1, 207)"), cts_work nil (nothing
  invented), citation = parsed "I/1.207" vol/page pair ("s." suffix
  tolerated; upstream typos like "I1, 112" parse to nil honestly).
- **besedje16 CRLF** line endings (the other two are LF) — preserved
  byte-exact in fixtures.

DEEP-EXTRACTION LEDGER — wired: German/modern-sl/razl glosses, toneme
display forms, folded lookup (define abeceda ≡ define abecę̑da; one
"a" lookup unifies all three dictionaries), JSV vol/page citation rows,
loanword etymologies + attestation quotes verbatim in bodies (Bohorič ſ
kept — canonical means canonical), besedje16 attestation sigla verbatim
in bodies, sl witness language note (dictionary_loader rider).
JOURNALED, not wired (each needs its own owner-scoped packet):
- Pleteršnik `<gn>`/`<ko>` dialect/place tags as a geo facet (26,692
  gn occurrences) and `<ov>` source-authority sigla (215,568) as an
  attestation apparatus; `dodatek` (663) + besedje16 `zvezdica` (192) /
  `hom` attributes as entry metadata.
- JSV citation RESOLUTION against IMP (needs the Sacrum promptuarium
  holding check the survey left open).
- besedje16 sigla→document crosswalk (DB 1584 = zrc_00001-1584) —
  mechanical once a sigla registry exists; earliest-attestation axis.
- Franček crosswalk deposit (11356/1472): NOT fetched — outside this
  packet's three-artifact scope; remains the survey's rider.

Fixtures: test/fixtures/sl-lexica/ — 7+5+6 byte-verbatim entries + the
three XSDs whole (documented deviation from the plan's "2–3 each":
homograph sets and per-element variants cannot be pinned with fewer).
Tests +23 (suite 2,787 / 33,663 · lint 354 files, both exit 0).
Checklist §6 for the owner: bin/nabu sync sl-lexica (three GETs, ~7 MB
→ 139,405 entries), eyeball `nabu define abeceda` (toneme headword,
German gloss) + `nabu define --lang sl a` (three-dictionary
unification) + `nabu language sl` (witness note), then flip enabled.

## P23-1 · damaskini corpus adapter  [tier: fable] [status: done 2026-07-15 — adapter + registry shipped, enabled:false awaiting owner sync+flip; census below] [deps: —]

The clarin-si-survey (P17-6) pick #1, owner-approved 2026-07-15: the
Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1
(CLARIN.SI hdl 11356/1441, CC BY-SA 4.0 verbatim → attribution). Shipped:
`Nabu::Adapters::Damaskini` on the `conllu` family (one document per
`# newdoc id` of the ONE corpus-wide CoNLL-U file; new optional
`citation:` + `metadata:` hooks on ConlluParser, UD callers unchanged);
urn `urn:nabu:damaskini:<newdoc-id downcased>`, citation = the numeric
tail of upstream's corpus-continuous sent_id; two-zip ZipFetch
(CoNLL-U + TSV bitstreams); TSV headers → doc metadata (source name,
place with honest "?", date, scribe, title, locus notes) +
`AxisBuilder::DamaskiniDates` (all 23 headers date-parseable: point
years, decades, "1650-1670s", "17th"/"XV c.", "19th (post 1817)",
xrulev's year in an edition line); language chu×3/bul×20 from the
philological PDF's own Norm classification (deposit tags `bul, mkd`
collectively, no per-doc tag; fn.7 quoted in the adapter); Norm+Origin
→ document_facets; gold lemmas → passage_lemmas; `translations: true`
mints -en siblings (100% text_en, censused) with the DAMASKINI_DOCUMENT
work pattern in Query::Parallel (hyphen-rich doc ids: the -en tail is
the only variant, anchored literally).

### Metadata-layer census — wired vs journaled (deep-extraction mandate)

WIRED: gold lemma (→ lemma index) · msd-bg-dam XPOS + UD head/deprel
(annotations tokens) · text_en (-en siblings, --parallel) · dating +
place (axis rows) · scribe/title/locus (doc metadata) · Norm + Origin
dialect classification (facets) · per-doc language (chu/bul).

JOURNALED — phase 2 of this source (build only on owner say-so):

1. TSV TOKEN layers: accented | Cyrillic | diplomatic orthography
   (3-layer collation, the ccmh-txt precedent), per-token folio anchors,
   `eol` line breaks. Census: per-file column layouts vary 15–20 cols,
   the per-file header row is authoritative; 3 files (nbkm1064,
   raikovski, nbkm1423 — the last Latin-script original) have NO
   cyrillic column; TSV sentence numbering restarts per file and 5 files
   disagree with the CoNLL-U by 1–3 sentences (jankul 293/296, kievski
   579/580, krcovski 316/317, raikovski 315/316, veles 182/183) — a real
   alignment job, needs a small bespoke TSV family.
2. `chunk` column: narrative-division labels ("1. staroe Žitie" — 628
   marks in kievski) — a structural layer nabu could render as div
   context; `ref` column: dictionary/Biblical/cross-text references —
   the machine seed for the St.-Petka collation hub (~10 independent
   witnesses of one vita across four centuries, the alignment layer's
   best Slavic case since ccmh; needs work-registration design).
3. Scribe as a queryable person facet (16 named scribes incl. Josif
   Bradati and Sofronii Vračanski) — nabu has no prosopography model;
   currently doc metadata only.
4. Balkan-sprachbund msd-bg-dam features (definiteness marking, case
   loss, future tense) as morph facets — the corpus's own philological
   PDF quantifies them per source; would need a morph-facet subsystem.

Suite 2,806 runs / 34,112 assertions exit 0 · lint 355 files exit 0.
Owner gate (checklist §6): `bin/nabu sync damaskini` (~1.7 MB, two
zips) → eyeball `nabu show urn:nabu:damaskini:berlinski--slovo-petki:1
--parallel`, a veles Cyrillic passage, 5 random passages → flip
`enabled: true`.

## P23-0 · starling follow-up bases: vasmer + germet + baltet  [tier: fable] [status: done 2026-07-16 — three config rows + fixtures shipped; enabled stays false, owner re-sync queued; verdicts below] [deps: P22-0]
The P22-0 promise cashed: the IE.exe package's remaining three bases as
BASES configuration rows — starling-vasmer (rus, 18,239 entries: M.
Vasmer's Russian etymological dictionary, Trubachev edition),
starling-germet (gem-pro, 1,994: Nikolayev's Common Germanic database),
starling-baltet (bat-pro, 1,651: Nikolayev's Baltic database). Owner-
authorized fixture pass only: one IE.exe fetch to scratch (sha256
byte-identical to the P22-0 snapshot), .inf DBINFO + descrip.php roster
snapshots, live-CGI char-level verification of every fixture record.

FINDINGS (2026-07-16):
- CONFIG-ONLY VERDICT: held, with FOUR measured exceptions, each the
  minimum code (journaled in the adapter class comment): (1) chslav.lst
  — vasmer's OCS citations ride the \x01\x86–\x88 doublebyte range,
  absent from unipro.lst; the official 3.9.0 package wires a SECOND
  Unicode table for it (config.str [Chslav font] → convert/chslav.lst,
  90 mappings), vendored verbatim beside unipro.lst (sha in
  config/starling/README.md) and merged into the StarlingText trie
  (key spaces disjoint — zero pokorny/piet drift, measured). Census:
  19,229 of vasmer's 19,257 otherwise-unmapped pair occurrences
  resolve (азъ, багрѣница, сѧгати — live-verified); the residual 28
  are stray high bytes inside per-character shift runs (the official
  web converter garbles them too) → honest U+FFFD, unit-pinned with
  verbatim corpus bytes. (2) duplicate-NUMBER entry ids, (3) "#NUMBER"
  placeholder headwords, (4) the STOP_TOKENS reflex gate — all below.
- UPSTREAM DATA-DEFECT CENSUS (whole package, both defect classes
  found the hard way — the owner's 2026-07-16 live sync quarantined
  piet.dbf whole on "duplicate entry id 574"):
  · NUMBER collisions: piet ×1 — record #573 (*kōim- 'village') and
    record #1573 (*kneuk- 'to shout') BOTH stamped 574, the latter
    sitting exactly where the vacant 1574 belongs in an otherwise
    consecutive run (a dropped leading "1"); the live CGI itself
    serves "Total of 2 records" for 574. baltet ×6 (76/95/248/689/
    1049/1394) — exactly the six piet BALTNUM links that dangle
    (piet #76 'flea' → BALTNUM 37 dangles while baltet's flea record
    wrongly wears 76 = its own PRNUM; in baltet the INTERLOPER comes
    first in file order, so the plain id lands on the typo'd record —
    upstream's defect, journaled, not repaired). pokorny/vasmer/
    germet ×0. VERDICT: first occurrence in file order keeps the plain
    NUMBER as entry id (upstream "#N" crosslinks resolve to it), each
    repeat mints a stable file-order suffix (-b, -c…) + one honest
    body note; NEVER renumbered (canonical means canonical). urns
    frozen — the 2005 package is frozen. Fixture-pinned: BOTH piet
    574s, BOTH baltet 76s.
  · Headword-less records (the SECOND whole-file quarantine class,
    censused before it bit): piet 6 — content-bearing Iranian stubs
    at the file tail (Sogd./Yag. material) the live CGI cannot even
    serve ("Total of 0 records") — germet 6 / baltet 7 fully-empty
    numbered slots; pokorny/vasmer 0. VERDICT: kept under the
    mechanical "#NUMBER" placeholder headword (the crosslink
    notation) — nothing hidden, links at those numbers resolve.
    Fixture-pinned: piet #3278, germet #401.
- VASMER: language rus (the headwords are Russian dictionary words,
  accented, verbatim incl. the inflection-follows comma the live site
  renders — "сига́ть,"; fold takes the first comma-variant). vasmer.inf
  is BLANK → field labels from the live CGI (Word / Near etymology /
  Further etymology / Trubachev's comments / Editorial comments /
  Pages; web-verified on #20) and the ATTRIBUTION from the roster's
  actual words ("scanned, OCR'd, and database-converted versions of
  M. Vasmer's etymological dictionary of Russian…") — vasmer's credit
  differs from pokorny's, carried verbatim per the grant. Field
  density: GENERAL 18,085 / ORIGIN 3,097 / TRUBACHEV 1,478 /
  EDITORIAL 191 / PAGES 18,239. REFLEX VERDICT: mints NOTHING —
  every field is scholarly prose; body-only. No gloss lane (config
  gloss: nil — the one-line build_entry accommodation).
- GERMET: gem-pro (unifies with wiktionary-recon's Proto-Germanic
  shelf code). REFLEX VERDICT: 19 of 21 single-language columns mint
  leading-citation-form rows — 14,627 rows censused with the real
  gate. GOT→got and OENGL→ang JOIN THE GOLD (attested counts resolve
  via ReflexViews at query time — test-pinned against a seeded lemma
  index); the rest speak the Wiktionary codes the kaikki crosswalk
  speaks (non/no/gmq-osw/sv/gmq-oda/da/enm/en/ofs/osx/dum/nl/gml/nds/
  goh/gmh/de). NEW GATE, censused: bare dialect/variety LABELS lead
  ~75 cells without the period that self-filtered piet's "Khow."
  (CrimGot ×7, NIsl ×20, OGutn ×13, OWFris ×15, Langob, dial…) —
  STOP_TOKENS (27 censused tokens, zero collisions with legitimate
  citation forms anywhere in the package, zero piet/pokorny drift,
  both measured). EASTFRIS + OLFRANK stay BODY-ONLY: variety-
  ambiguous columns (EASTFRIS ~47% label-led "Fris./WFris."; OLFRANK
  mixes ONFrank/OFrank/SalFrank/EFrank) — a language code would be
  invented, the P22-0 IRAN/ITAL/CELT/TOKH discipline.
- BALTET: bat-pro — minted by the family-code+-pro convention;
  Wiktionary reconstructs Balto-Slavic (ine-bsl-pro), not Proto-
  Baltic, so there is no upstream shelf to unify with (journaled in
  the language note). Headwords carry no Lm modifier letters
  (censused) — the generic §9 fold suffices, no Normalize change.
  REFLEX VERDICT: all four columns mint (OLITH→olt, LITH→lt, LETT→lv,
  OPRUS→prg; 96%+ clean) — 3,091 rows.
- CROSSLINKS NOW LIVE: piet's SLAVNUM/BALTNUM/GERMNUM body lines name
  entry ids that exist (censused: GERMNUM 1,965/1,965 resolve, SLAVNUM
  1,233/1,233, BALTNUM 1,626/1,632 — the six misses ARE the six baltet
  duplicates); germet/baltet PRNUM → piet (1,955/1,955 and 1,642/
  1,643). Fixture set closes every crosslink loop on itself: piet #1 ⇄
  germet #1, piet #562 ⇄ germet #390 + baltet #1634, piet #1501 →
  vasmer #12561. BODY-LINE → LIVE-LINK RESOLUTION: no cheap wire
  exists inside the current rendering — the only resolution lane
  define renders is DictionaryCitation (cts-work-shaped, resolved at
  query time); a "Vasmer: #12561" line would need a dictionary-
  crosslink rows lane (the citations pattern: parser mints, loader
  persists, query resolves) — JOURNALED AS FOLLOW-UP, not built (the
  packet's explicit boundary). Interim: `show urn:nabu:dict:
  starling-vasmer:12561` works today (P22-2).
- ATTRIBUTION: all five credits verbatim in MANIFEST.license →
  sources.license → every define/etym/MCP surface (render-tested on a
  vasmer define). 02-sources row 56 extended; the non-consensus caveat
  rides as before.
- FIXTURES: 19 real records across five bases (piet regained its
  P22-0 three + the two 574s + #3278; every record live-CGI verified
  char-level; one known divergence journaled — the legacy web
  converter renders \xF0 as ɵ where the official unipro.lst maps
  U+03D1 ϑ, germet #513; the table is the authority). manifest.yml +
  README updated with selection rationale.
- Owner queue: `bin/nabu sync starling --parse-only` (re-parse of the
  already-fetched package lands piet's 3,291 + the three new shelves;
  a fresh fetch also fine), eyeball `define 'сигать'` (vasmer credit
  line), `define '*kakla-'`, `etym hals` (germet got/ang gold joins),
  the piet 574-b note body, then flip enabled + rebuild.

# ── Phase 24 ──────────────────────────────────────────────────────────

## P24-2 · define/etym coordination — etym must not miss what define finds  [tier: fable] [status: done 2026-07-16] [deps: —]

Owner incident (2026-07-16, verbatim: "disagreement between define and
etym. should be more coordination between command execution paths with
similar function"): `define сигать` finds the Vasmer article
(urn:nabu:dict:starling-vasmer:12561 — prose fields, no reflex rows)
while `etym сигать` returned a flat miss whose message enumerated a
HARDCODED, pre-starling/LIV/EDL shelf roll call.

FALLBACK-DESIGN VERDICT (judged as specced): fallback fires ONLY on a
crosswalk miss — etym's primary contract stays the walk, hits never mix
with dictionary entries. On a miss the CLI runs the SAME Query::Define
lookup the define command runs (one execution path — coordination, not
duplication) and renders any entries via the P22-2-extracted
print_define_entry (zero renderer divergence) under the honest header
"no reconstruction path in the crosswalk for X — the dictionary shelf
holds:". MCP nabu_etym mirrors it exactly: `dictionary_entries`
(define_payload shape, license-withholding applied) + an explanatory
note; entries stays honestly [].

ENUMERATION now DB-DERIVED (the P11 DEFINE_LANGS / P18 lesson —
hardcoded shelf lists rot): new public Query::Etym#crosswalk_shelves =
distinct dictionary languages holding reflex rows (withdrawn entries
excluded, sorted; [] pre-migration-007). The genuine-total-miss message
(CLI + MCP) lists exactly those codes ("the crosswalk covers bat-pro,
gem-pro, ine-pro" on the starling fixture — vasmer's rus honestly
absent, zero reflex rows) with the `nabu language CODE` pointer and the
'*form' quoting hint kept; a fixture shelf added to the catalog appears
in the message with zero code change (test-pinned). When the fallback
fired, the full miss text is suppressed (coordinated message).

Boundaries held: crosswalk semantics, reflex minting, and define
behavior untouched; cli.rb diff localized to the etym command +
etym renderer region (print_etym_results lost its dead miss branch —
misses route through print_etym_fallback).

Tests +8 (query 2: db-derived census + new-shelf-no-code-change pin,
pre-007 grace; CLI 3: the verbatim incident on the starling fixtures
incl. the сига́ть, trailing-comma fold pin, hit-never-mixes, db-driven
miss; MCP 3: fallback payload+note, db-driven miss note, restricted
withholding through the fallback; +1 help-pin assertion). Docs: cli
etym long_desc (shelf wording de-hardcoded + fallback paragraph),
ETYM_DESCRIPTION, docs/mcp.md nabu_etym paragraph.

# ── Phase 25 queue: the Celtic axis (owner-approved as-is, 2026-07-16) ─
# Survey: .docs/celtic-survey.md (scout 2026-07-15/16; licenses verbatim,
# contacts verified). Five packets + rider, ranked value×readiness:
# 1. riig — 428 Gaulish EpiDoc inscriptions (CC BY 4.0 IN-FILE, header
#    governs), ~6 MB polite crawl, EDH-style date/place extraction,
#    Gaulish xtg incl. Gallo-Greek script.
# 2. kaikki sga/mga/wlm — three EXTRACTS config rows on the live
#    wiktionary-jsonl adapter (the ett precedent, zero new code; the
#    Old Irish extract is 19.8 MB — DIL-derived depth).
# 3. corph — Maynooth ChronHib, 78 annotated Old Irish texts, MIT
#    LICENSE (dump in chronhib-MU/Chronhib-Website repo, 39 MB);
#    FIRST CELTIC GOLD LEMMAS → unmutes piet CELT column, Pokorny
#    MATERIAL, IE-CoR sga, cel-pro ReflexViews; DIL_Headword ids →
#    links-journal edges into eDIL's stable id space.
# 4. UD Old Irish ×2 — DipSGG (3,471 St Gall glosses, BY-NC-SA → nc)
#    + DipWBG (42 Würzburg glosses, BY-SA → attribution override).
#    Config-only.
# 5. ogham — 508 EpiDoc records (git clone; in-file CC BY 4.0 vs site
#    BY-NC-SA → class nc PENDING the clarification email #14,
#    relabel-on-reply); Primitive Irish pgl, real Ogham codepoints.
# Rider: 11 verified PD-scan ingest one-liners (survey §PD; Thurneysen
#    1909 GERMAN original — the 1946 English translation is IN
#    COPYRIGHT, trap avoided).
# Negative (verified): no licensed machine-readable Celtic Gospel
#    exists — alignment hub gains no Celtic witness this phase.
# Unlock emails DRAFTED (registry rows 11-16): eDIL, GPC, CELT,
#    OG(H)AM clarification, Cardiff Welsh Prose (address needs owner
#    eyeball), Hesperia. v2 on replies: LexLep, Rhyddiaith 13eg,
#    CELT subset, Celtiberian.

## P25-1 · Celtic epigraphy pair: RIIG (Gaulish) + OG(H)AM (Primitive Irish)  [tier: fable] [status: done 2026-07-17 — both adapters + families shipped, enabled:false awaiting owner syncs; verdicts below] [deps: —]

Two EpiDoc corpora, one shared parser investment (queue picks #1 + #5).

SHIPPED:
- `CelticLeiden` — the shared Leiden reading-text policy module (the "one
  shared investment" verdict: gap `[…]` / del `⟦⟧` / surplus `{}` markers,
  corr>reg>lem>expan choice-branch rule, supplied/unclear grapheme counts,
  language mapping, line folding). The two parsers stay SIBLING families
  (the EDH/DDbDP siblings-not-a-hierarchy doctrine), each owning its walk;
  both are DOM-based (428 + 504 files ≤70 KB — the freising small-TEI
  precedent, not the >5 MB Reader rule; and choice-branch selection needs
  name-based lookahead a one-pass stream can't do).
- `riig` (adapter `Riig`, family `riig-epidoc`, `attribution`): passage =
  line WITHIN an editorial reading (`<urn>:<seg-id>:<lb n>` — RIIG marks
  no preferred reading, so EVERY seg mints; AHP-01-01's καρε[…]μ vs
  καρβ[…]μ both live). choice→reg; word-internal pretty-print whitespace
  stripped (no xml:space upstream; `<space/>` = real division —
  "nanton{t}icnos", "votum solvit libens merito"); msd/pos/type →
  per-line `words`; seg resp/cert → `reading` annotation. Fetch =
  FileFetch corpus map (corpus.html's embedded placesgeo GeoJSON, the
  crawl seed + probe target) + polite resumable per-record crawl (ORACC
  html-en shape, CRAWL_DELAY 0.25). `AxisBuilder::RiigDates` (envelope
  reuse, BCE-signed; findspot-over-settlement, Trismegistos refs; WGS84
  verbatim in metadata — the EDH no-coordinate-columns decision). RIG
  concordance → `related` `rig:G593` (hyphen variants deduped) →
  reference edges. French translation divs → `-fr` siblings, cited by
  reading id (registry `translations: true`; per-file peek since coverage
  is partial — the AHP empty-div case). LICENSE both layers verbatim in
  MANIFEST + 02-sources: in-file CC BY 4.0 governs (Freising ruling);
  page-level BY-NC-ND covers site documentation only.
- `ogham` (adapter `Ogham`, family `ogham-epidoc`, `nc` PENDING registry
  #14 — relabel-on-reply): Document = (stone × layer), the Freising
  sibling design — ogham layer bare urn, transliteration/roman/runic/
  english as -translit/-roman/… siblings with IDENTICAL line suffixes
  (suffix-equality --parallel alignment). SCRIPT-HONESTY verdicts: Ogham
  codepoints verbatim NFC as the PRIMARY surface (byte-pinned ᚇᚑᚈᚐᚌᚅᚔ);
  the transliteration is its own parallel document, never a replacement;
  a false `-Ogam` subtag on a Latin-script layer is SHED, `-Latn` never
  invented (upstream doesn't claim it). charDecl glyph table resolves
  `<g>` refs per layer (ogham vs diplomatic mapping, `@type` override;
  unknown ref = ParseError, the freising rule). choice→corr either order;
  no-lb layers → the `:text` whole-layer fallback (EDH P23-3c); empty
  edition divs skip-by-rule (discovery census); `<ab type="list">`
  summary dropped. dil.ie word links → `related`
  (`https://dil.ie/<id>`) → reference edges, producer `ogham` — corph
  coordinates via producer, no code coupling. GitFetch; sync_policy
  MANUAL verdict (not frozen: v2.0 2025, commits into 2026).
- Reference-edge generalization (the packet's links promise):
  `Adapter.reference_producer` (default "library") +
  `LibraryReferences#run(slug, producer:)` + the edge-worthiness rule
  generalized from urn:-only to scheme-bearing targets (":"-less strings
  stay codes/metadata) — SyncRunner passes the producer; supersession
  stays (producer, scope)-scoped so independent producers over the same
  id space never clobber.
- AxisBuilder Summary + rebuild + CLI axes line gain riig (+undated/
  +invalid residues); config rows riig (translations: true) + ogham,
  both enabled: false; fixtures = 4 real RIIG records + trimmed corpus
  map, 6 real ogham records + charDecl (manifests + READMEs with both
  license layers verbatim).

KNOWN HONEST RESIDUES (first-sync triage): ~5 RIIG "Indéterminé" records
may quarantine (empty editions — the EDH 27-quarantine precedent); ogham
W-PEM-006/W-PEM-012 transliteration layers quarantine on lb-without-@n
(upstream defect, named in the fixture README). FOLLOW-UP (proposed, not
promised): an ogham place/date axis feed (geo 484/504, origDate attrs
104/504 censused) once the owner wants Insular findspots on the axis.

## P24-1 · `nabu note` — owner annotations on any urn  [tier: fable] [status: done 2026-07-16 — shelf + gateway + adapter + renders shipped; design verdicts below] [deps: —]
The curatorial note lane (owner-approved 2026-07-16, metadata-framework
phase 2): notes keyed by ANY urn the corpus knows — document, passage,
range, dictionary entry — nabu's scholia-of-one's-own. Canonical-memory
doctrine (architecture §16): notes live as FILES under
canonical/local-notes/<topic>.yml (a YAML LIST of urn/note/added/tags
records, append-only through the gateway, hand-edits validated with
file+entry defect naming — Nabu::NoteFile); the db only indexes
(urn_notes, migration 015, temperature 1, replaced per topic wholesale by
Store::NoteLoader — content_kind :notes, the fourth loader routing).

SHIPPED:
- Nabu::NoteShelf — the FOURTH sanctioned local-shelf write gateway
  (CLAUDE.md rule + architecture §16 updated in the same change): atomic
  append + reparse-validate + rollback (the LibraryShelf P20-1 pattern),
  urn resolution against the catalog BEFORE any write (Query::Show incl.
  P22-2 dictionary-entry urns; a range with a bad endpoint is a miss,
  never a crash); --force records a note on a not-yet-held urn (planned
  material), flagged (dangling) at render.
- `nabu note URN [TEXT]`: scripted append / interactive prompt (TTY; the
  ingest furniture) / bare-urn read-back of existing notes; non-TTY
  without TEXT refuses honestly BEFORE any write; `--topic` (default
  notes; "manifest" reserved shelf furniture), `--tags`, `--force`,
  `nabu note --list [--topic] [--limit]` (bounded, dangling flagged).
  Append runs the shelf's ordinary sync (the ingest pattern) so the note
  indexes + sha-pins immediately.
- Adapter local-notes (sync_policy local, enabled true — the P19-1
  argument): LocalFetch per-file pins/vanished/attic verbatim; quarantine
  per topic file; discovery census counts non-topic yml by rule.
  Registered in config/sources.yml + 02-sources row 61. Verify diffs
  derived rows per topic (the dossier pattern); status shows notes=N
  (the P11-10 misleading-zero rule); health populated? gains the :notes
  grain.
- Renders: show footer "owner note (topic, date): …" + document
  passage-note child count; define entry notes after the body (and on
  show of a minted dict urn); links owner-notes lane; MCP nabu_show/
  nabu_define serve notes BY DEFAULT (owner: "your own library metadata
  is useful context"), attached strictly AFTER the withhold gate — a note
  on a research_private/restricted document is withheld with its target.

DESIGN VERDICTS (2026-07-16):
- FILE GROUPING: topic files (default "notes"), not per-urn files — one
  honest review surface per theme, mechanical appends, the manifest
  precedent; topic names are lowercase file stems, "manifest" reserved
  (fixture/shelf furniture collision, gateway and discovery agree).
- DANGLING-URN STORY: resolution is a GATEWAY check, not a parse rule —
  NoteFile accepts any urn:-shaped key so hand-edits and --force survive
  rebuilds; renders flag (dangling) by re-resolving at read time, so the
  note self-heals the day the urn arrives. The reparse-validate backstop
  keeps even a --force append from landing a non-urn key (rollback,
  byte-identical prior file).
- WITHHOLDING RULE: notes attach to their TARGET's payload only, after
  the withhold gate — the withheld response carries no notes field at
  all, so the frame cannot leak; include_restricted serves note beside
  target, deliberately.
- IDEMPOTENCY GRAIN: notes have no per-record key, so the loader replaces
  per TOPIC wholesale — byte-identical topics skip whole (double-load
  test pins rows AND ids unchanged), edits re-add whole, absent topics
  sweep on full loads only.

Owner queue: `bin/nabu sync local-notes` errors until the first note
exists (LocalFetch's missing-tree honesty — the hint names `nabu note`);
try `bin/nabu note <urn> "…"` on a held urn, then `show <urn>`,
`note --list`, and an MCP nabu_show to see the served lane.

## P24-0 · Shelf dossiers — canonical/local-source/  [tier: fable] [status: done 2026-07-16 — full stack shipped; owner queue: seed export + first sync + eyeball] [deps: P19-1]
The canonical-memory doctrine (architecture §16) extended to the SOURCE
grain — the language-dossier stack's twin, owner-approved 2026-07-16.
- SHIPPED: Nabu::SourceDossier (canonical/local-source/<slug>.md — YAML
  front matter slug/description/themes/key_works + scalar extras, owner
  prose = the curated `note` lane, provenance-headed accretion sections
  under the append-only latest-per-(slug, kind) contract verbatim;
  parse/render round-trips, NFC at the boundary); Nabu::SourceShelf —
  the THIRD sanctioned canonical-write gateway (CLAUDE.md ground rule +
  architecture §16 amended in the same change); Adapters::LocalSource
  (`content_kind :source`, the FOURTH loader routing in
  SyncRunner/Rebuild/Verify; sync_policy local, enabled true by default
  — the P19-1 argument verbatim in sources.yml) →
  Store::SourceDossierLoader → derived `source_records` (migration 015:
  slug/kind/body/provenance; replace-per-slug, record-grained counts,
  absent-slug sweep, attic retention); status reads records=N;
  invariants' populated + files-vs-records checks generalized to both
  dossier grains (DOSSIER_TABLES).
- SCAFFOLD: `nabu ingest --shelf source SLUG` — the thin three-mode
  language-scaffold pattern; description prompt prefilled from the
  registered source's manifest name; key_works validated as urns via the
  shared field_error seam (prompt re-asks; --yes fails pre-write).
- SEED (owner-fired one-shot): `nabu list --export-source-dossiers
  [--dry-run]` scaffolds a dossier for EVERY registered source,
  description seeded from the best EXISTING prose — docs/library.md
  per-shelf `| **Source** |` sections + slug bullets (slug-specific
  bullets win), then sources.yml standalone shelf comments (inline flag
  comments and license_watch lines excluded); sentences capped at 3; NO
  prose = an HONEST STUB named in the report, never invented content;
  idempotent at the file grain (existing dossier = untouched no-op).
- CONSUMERS: `nabu list SLUG` card renders the description wrapped under
  the header (house measure, whole words); `nabu list --long` census
  adds one description line per described source (zero fields
  suppressed); MCP nabu_status serves `description` per source by
  default (absent dossier = absent key, never a null).
- GATE-CHECK RIDER (owner: gate-checked only, never generated): `rake
  site:check` → Nabu::Ops::DossierDrift. PRESENCE/MENTION rule,
  journaled in the class: drift = registered source with no dossier /
  docs/library.md-mentioned slug whose dossier lacks a description / an
  ENABLED described shelf the library review never mentions (pending
  sources exempt — MAINTENANCE duty 2 maps shelves when they go live) /
  malformed dossier / unseeded shelf. NEVER verbatim equality (the two
  registers legitimately diverge in wording); site/library.md covered
  TRANSITIVELY (the printed map of docs/library.md, no slugs to anchor
  on). Listed report, exit 1 on drift.
- Fixtures test/fixtures/local-source/ (3 real dossiers distilled from
  library.md prose + quarantine rig + README/manifest). Docs:
  architecture §16 shelf three + third gateway, ops.md §14 workflow,
  02-sources row 60, site/MAINTENANCE.md duty 5, CLAUDE.md ground rule.
  Tests +44 across 9 new/extended files. Suite 2,913 runs / 34,805
  assertions exit 0 (0 skips) · lint 372 files exit 0.
- Owner queue: `bin/nabu list --export-source-dossiers` (eyeball seeded
  descriptions + the stub list), `bin/nabu sync local-source`,
  `bin/nabu list edh` (description under the header), `bundle exec rake
  site:check`.

# ── Phase 25 ──────────────────────────────────────────────────────────

## P25-4 · Celtic quarantine-noise hotfix — Celtic quarantine noise: discovery must not mint refs the parser cannot fill  [tier: fable] [status: done 2026-07-17 — both adapters aligned; expected at next parse-only sync: riig 242→9 quarantines, ogham 214→5] [deps: P25-1]

The first live sync of the P25-1 pair surfaced 444 noise quarantines on
perfectly good records — both adapters' cheap discovery peeks (raw-byte
regexes) DISAGREED with the parsers' real extraction. One principle fixes
both: the minting decision now IS the parser's own extraction (428 + 503
files ≤70 KB — parsing at discovery is cheap; no approximation gets to
disagree with parse).

- riig: `translated?` was a byte peek over `<div type="translation">…</div>`
  whose non-greedy close swallowed FOLLOWING divs (a self-closed
  translation div + prose-bearing commentary → phantom sibling) and whose
  literal prefix missed attribute-reordered divs (real prose unminted).
  Corpus census: 291 minted siblings = 233 phantoms ("no translation
  prose found" noise) + 56 loading + 2 on broken bases; 18 real siblings
  MISSED. Now `translated?` = `RiigEpidocParser#translations(path).any?`
  (rescue ParseError → false: an unreadable record's base ref already
  carries the honest quarantine) — a -fr ref exists iff parse_translation
  would find prose. Expected: 504 refs (76 siblings), 495 loaded (+18 new
  siblings, NOTHING withdrawn — the 56 loading siblings are a subset of
  the 76), 9 quarantines = the 7 known base defects (bdr-04-05 lb@n,
  bdr-17-01 bad language tag, 5 × no-citable-text) + their 2 prose-bearing
  -fr riders (bdr-17-01-fr, gar-02-03-fr — honest, base-broken).
- ogham: the byte peek only recognized SELF-CLOSED edition divs as empty
  and read straight through XML comments. Census of the 214 quarantines:
  195 DECLARED-but-empty layers (open divs carrying only <ab><lb/></ab> —
  never-encoded stones; the EDH lost-edition lesson in a new costume) +
  14 commented-out divs (not declared at all — DOM-invisible) + 3 charDecl
  glyph-drift refs + 2 W-PEM lb defects. New
  `OghamEpidocParser#layer_census` (shared by discover + discovery_skips):
  a declared layer with no citable text mints NO ref (skip-by-rule,
  censused — 197 skips corpus-wide); a structurally BROKEN layer (lb
  without @n, unresolvable glyph) stays citable so its ref mints and
  quarantines honestly; commented divs count nowhere. VERDICT on the
  all-empty stone (censused: 39 upstream, none with any citable layer):
  the local-library metadata-only precedent FITS — conformance already
  ships the P19-4 marker-driven hook, Document/store accept zero-passage
  documents — so each mints ONE bare-urn metadata-only document
  (`text_layer: "none"`, stone-grain header metadata, new
  `parse_metadata_only`): catalogued, never quarantined. Expected: 878
  refs, 873 loaded (834 text docs UNCHANGED + 39 metadata-only stones),
  5 quarantines = W-PEM-006/012 translit (lb@n, kept per spec) + 3
  glyph-drift (i-ker-054-roman chi-rho, s-abd-003 ×2 stemline_space —
  real parse failures on non-empty layers, NOT empty-layer noise; honest,
  kept).
- Fixtures (byte-verbatim from the canonical trees, READMEs + manifests
  updated): riig AIS-01-01 (the self-closed-div phantom shape; red first —
  reproduced the exact noise quarantine), ogham E-STS-001 (declared-empty
  layers → metadata-only) + E-CON-X01 (all divs commented out, textLang
  removed upstream → und metadata-only). ALL-01-01 (already a fixture)
  turned out to be a MISSED sibling — the old test asserted the bug
  ("ALL-01-01 has none"); its -fr ref now mints and parses (Bratronos).
- Deviation from the hotfix brief: projected floors are 9 (not ~7) and 5
  (not ~2) — the brief's census lumped the 3 glyph-drift and 2 broken-base
  -fr quarantines into the noise; they are honest errors and stay.

## P25-2 · Celtic config batch — kaikki ×3 + UD ×2 + survey-reference truth-pass rider  [tier: fable] [status: done 2026-07-17 — config + fixtures shipped, zero new code; extracts/treebanks flow at the next owner-fired syncs] [deps: —]

The Celtic axis's two config-shaped lanes (queue items 2 + 4; survey
.docs/surveys/celtic-survey.md) plus the survey-reference rider.

- KAIKKI ×3 (the ett-precedent EXTRACTS pattern: three rows on the live
  wiktionary-recon source, zero new code; enabled state UNCHANGED —
  extracts land at the next owner-fired `bin/nabu sync wiktionary-recon`,
  ~22.4 MB across three GETs, +8,097 entries): `wiktionary-sga` Old Irish
  (19,776,265 B / 6,564 records / 5,828 distinct words — DIL-derived
  depth: 2,093 with descendants, 3,116 with etymology text, 1,427 naming
  Proto-Celtic, 1,263 naming PIE), `wiktionary-mga` Middle Irish
  (1,267,269 B / 767 / 710), `wiktionary-wlm` Middle Welsh (1,343,469 B /
  766 / 695). ATTESTED languages on the recon source — the wiktionary-cu
  precedent: reflexes minted, no display asterisk; upstream lang_codes
  are already the ISO 639-3 sga/mga/wlm, adopted as themselves. Manifest
  name extended ("+ attested Celtic"). License statement re-verified
  verbatim 2026-07-17, unchanged: "This data is made available under the
  same licenses as Wiktionary - both CC-BY-SA and GFDL." → attribution.
  CROSSWALK LIGHTS (fixture-pinned, the ReflexViews path): sga rí "king"
  carries the cel-pro/ine-pro etymology verbatim in its body (*rīxs,
  *h₃rḗǵs) AND mints the mga rí reflex edge whose target is the mga
  shelf's own headword — the shelf-visited ascent runs Middle Irish rí →
  Old Irish rí; mga clann → en clan rides the borrowed flag. NOTE:
  cel-pro itself is NOT a served kaikki extract (no Proto-Celtic shelf
  yet); the sga etymology text is the join surface a future cel-pro
  witness (CorPH/eDIL era) will land on.
- UD ×2 (config rows on the existing ud source, the P10-2/P13-1b
  pattern; rows flow at the next owner-fired `bin/nabu sync ud` — no
  per-treebank enablement exists, the source syncs its whole TREEBANKS
  map): `old-irish-dipsgg` — diplomatic St Gall Priscian glosses (Bauer's
  data, conv. Adrian Doyle), 3,471 glosses in the collection, test-set
  only (64 dependency-annotated sentences served today; fixture = head
  50); license verbatim, the ENTIRE LICENSE.txt: "CC BY-NC-SA 4.0" →
  rides the UD source's `nc` class unchanged, no override.
  `old-irish-dipwbg` — diplomatic Würzburg glosses, 42 glosses (tiny;
  upstream: growing), 34 test sentences (fixture = whole file); license
  verbatim "CC BY-SA 4.0" (LICENSE.txt: "The treebank is licensed under
  the Creative Commons License Attribution-ShareAlike 4.0 International")
  → `attribution` via the P10-4 per-document license_override (the
  birchbark/RNC mechanics). Language `sga` both (code-mixed Latin inside
  the glosses — the one-tag-per-treebank honesty RNC practices under
  orv). OVERLAP NOTE, journaled per the packet: DipSGG's text = the same
  St Gall glosses CorPH (P25-0, sibling packet) carries at a DIFFERENT
  grain — UD dependencies here, CorPH morphology there. Two honest
  witnesses, the MW-beside-kaikki precedent; NO dedup wanted (the UD
  dedup guard is for re-exports of already-synced sources, which this is
  not). sga joins the lemma-indexed languages (lebarda/airbág fixture
  rows pinned).
- RIDER (survey-reference truth-pass; owner reorg 2026-07-16: ALL
  surveys → gitignored .docs/surveys/): every LIVING reference to a
  `docs/<x>-survey.md` path rephrased to `.docs/surveys/<x>-survey.md`
  (annotated "gitignored planning material" at first mentions) or
  dropped where the sentence works without it — docs/02-sources.md (25),
  docs/architecture.md (2), docs/library.md (2), docs/improvements.md
  (4), README.md (6: prose mention de-linked, the doc-map table row
  DROPPED — a public table row cannot link a gitignored file),
  CONTRIBUTING.md (6: links replaced with prose + a 02-sources pointer),
  .github/ISSUE_TEMPLATE/request-a-source.md (3), config/sources.yml (3)
  + config/alignments.yml (2) comments, lib/** code comments (16 files),
  test/** comments + fixture READMEs/manifest prose (15 files).
  docs/backlog.md + docs/worklog.md history lines untouched (the record
  of what was true then), likewise the local-source fixture dossier
  test/fixtures/local-source/edh.md + its manifest `reason:` line
  (fixture PAYLOADS — dated provenance records tests may pin, not
  reader-facing pointers). The owner's own docs/*-survey.md deletions
  remain the owner's uncommitted act — no survey file deleted here.
- Fixtures: 9 byte-verbatim JSONL lines into test/fixtures/
  wiktionary-recon/ (recipe + full-download sha256s in its README;
  post-check asserts literal-line membership) + 2 real trimmed CoNLL-U
  under test/fixtures/ud/ (DipSGG head-50, DipWBG whole at 34 blocks;
  README records both license verbatims). Tests +2 (recon: the Celtic
  etymology/crosswalk pin + the ReflexViews-after-load proof; UD tests
  extended in place: 9-file discover, OVERRIDE/BARE license split,
  sga lemma plumbing, conformance over the new fixtures). Suite 2,981
  runs / 35,771 assertions exit 0 (0 skips) · lint 384 files exit 0.
- Owner queue: `bin/nabu sync wiktionary-recon` (~22.4 MB, +8,097
  entries; then eyeball `nabu define rí` + `nabu etym rí`) and
  `bin/nabu sync ud` (two small clones; eyeball `nabu show
  urn:nabu:ud:old-irish-dipsgg:sga_dipsgg-ud-test:1` and the license mix
  in `nabu list ud`).

## P25-0 · CorPH adapter — the first Celtic gold lemmas  [tier: fable] [status: done 2026-07-17] [deps: —]
The Celtic-axis keystone (queue item 3): CorPH / Corpus PalaeoHibernicum
(ERC ChronHib, Maynooth) — 78 deep-annotated Early Irish texts, 7th–10th
c., from the 39 MB MySQL dump `chronhibdev_2020.sql` in
chronhib-MU/Chronhib-Website, PINNED to commit e7ef75d5f9a6 (dormant repo,
2021-05-11): fetch is the ordinary GitFetch (attic + breaker) plus a pin
gate — HEAD ≠ pin aborts loudly (owner review + re-pin; GitFetch ref: is
branch/tag-only, so the pin is verified post-fetch). License verbatim "MIT
License / Copyright (c) 2020 [Chronologicon Hibernicum]" (repo LICENSE
covers the dump) → attribution; the CODECS CC BY-SA 3.0 footer is CODECS's
own, never cited (the survey's trap note, kept in sources.yml + row 63).

SHIPPED:
- CorphSqlParser — the corph-sql family: streaming MySQL-dump INSERT
  walker (File.foreach + StringScanner; only the current tuple buffered;
  \' \r\n ''-escapes, NULL→nil, Integer natively; multi-statement
  chunking; truncation → ParseError). No SQL evaluated, ever.
- Adapter corph: document per TEXT row (urn:nabu:corph:<Text_ID>, FROZEN),
  passage per SENTENCES text unit (<doc>:<Text_Unit_ID>, Textual_Unit
  VERBATIM incl. CRLF computus tables, Sort_ID order), MORPHOLOGY tokens
  in the P7-5 contract → passage_lemmas: THE FIRST sga GOLD (e2e pinned:
  lemma search "caur" finds S0003-1 caur AND S0003-13 cur/Caincur — the
  attestation surface search misses). Homonym indices ("macc 1") split
  into lemma + "homonym" so the headword searches. Mutation/verbal-flag/
  onomastic/problematic/Var_Status columns verbatim per token; loci,
  translation, Latin_Text context per passage; BIBLIOGRAPHY resolved into
  document metadata references.
- LANGUAGE HONESTY (census 2026-07-17, full dump): 80.5% Early Irish /
  12.4% Latin / 6.2% lang-less lemmata / rarities. Three grains: token
  "lang" (mapped: sga/lat/ang/non/grc) or "lang_source" verbatim
  (Pictish, British… — never a guessed code); PASSAGE = majority over its
  tokens (the gold-index grain: 16,535 sga / 1,050 lat / 11 ang voted +
  351 no-vote fallbacks — a pure Old Irish gloss inside a Latin computus
  stays sga, a Latin annal stays lat); document = majority over all (71
  sga + 4 lat: 0035/0039/0060/0077 minor glosses on Latin texts).
- Date axis: AxisBuilder::CorphDates — TEXT.Date via the honest ladder
  (ChronHib "date range … is/are used" phrase, "(for text)"-tagged range
  preferred else envelope; "Text: N-M"/"N X M" fallback): 73/78 dated,
  5 honest residues (AU's 431–1131 annalistic spread + 4 MS-only proses)
  counted undated, never guessed. Summary +corph/+corph_undated.
- eDIL bridge: CorphDilReferences (producer corph, kind=reference) — one
  edge per distinct (document, dil id) pair, from document urn to
  urn:nabu:dict:edil:<id> (the dictionary-urn convention the future eDIL
  shelf will mint; ~12,321 pairs / 5,846 distinct ids projected), detail
  names the carrying lemma; wired via the NEW Adapter.reference_producer
  seam (default LibraryReferences — SyncRunner no longer hardcodes the
  P19-4 producer; local-library behavior byte-identical).
- Registry corph enabled:false sync_policy:manual; fixtures = real
  trimmed dump (0003 Baile Chuinn / 0008 Paris Priscian / 0077 Einsiedeln
  Computus + sentence-less 0067 + the stray Text_ID "6" wart; six tables,
  LEMMATA across 23 real INSERT statements) + README (retrieval date,
  pinned sha, MIT quote) + manifest (git-extract, refetchable:false).
  02-sources row 63; conformance suite + double-load idempotency green.

FOLLOW-UPS (journaled, not built):
- Etymology column (4,562 LEMMATA rows, cited PC/PIE reconstructions,
  e.g. caur ← *karut-, Schrijver-style citations) — crosswalk-shaped
  (piet/Pokorny/cel-pro); needs a citation-prose parser, deliberately not
  this packet.
- AU passage-grain annal dates: SENTENCES Locus1 carries the annal year
  (554.01 …) for text 0001 — the TOROT ChronicleAnnals shape, would date
  ~7k passages of the one undated flagship text.
- SENTENCES Variant_Readings/Subunit + VARIATIONS registry prose, and
  MORPHOLOGY Stressed_Unit/Syntactic_* (phrase trees) — annotation layers
  beyond the v1 token contract.
- Language dossier: `nabu ingest --shelf language sga` once live (owner).

## P25-3 · Reference-docs + site truth pass — the public face catches up with Phases 20–25  [tier: fable] [status: done 2026-07-17] [deps: P25-0, P25-1, P25-2]
The owner asked whether the reference documentation and site were updated
after the expansion; the answer was no — ~6 phases stale since the
P19/v1.0.0 sync. Scope: docs/library.md per-shelf stories for every
`rake site:check` drift shelf; site catch-up; one news post; README
numbers + command table; 02-sources/ops only where flat-out false.
All numbers verbatim from the 2026-07-17 live census (38 sources ·
172,189 docs · 4,308,814 passages · 633,137 entries).

SHIPPED:
- docs/library.md: header totals rewritten (38 sources, 27 dictionary
  shelves, gold-lemma languages 15→17 with the row-census caveat stated
  honestly); new sections §8j StarLing (five bases, the written grant +
  compiler-credit story), §8k sl-lexica (Pleteršnik/JSV/besedje16), §8l
  Celtic axis (corph/riig/ogham + the kaikki/UD riders); §8e gains the
  damaskini block; §8i local shelves rewritten (four shelves;
  local-library 20 docs/8,725 passages, ingest URL intake; local-source
  37 dossiers; local-notes); §6 treebank counts + Old Irish pair; §4/§8g
  papyri + EDH counts refreshed; §9 gains list/note/dossier-gate bullets
  and the ingest-URL story; `lexica`/`bosworth-toller`/`mw` slugs
  backticked so the P24-0 mention rule sees them. Drift rule re-run
  clean: every enabled slug now backtick-mentioned.
- README.md: numbers paragraph (2026-07-17 census), shelf table (papyri/
  EDH/treebanks corrected, Slavic row + damaskini, new Celtic row,
  reference row at 633,137), registry paragraph (38 sources, StarLing/
  sl-lexica/damaskini/Celtic), Epigraphists updated + Celticists bullet,
  command table gains `nabu note` and URL-aware `ingest`, lemma rows
  15→17 languages.
- site/: library.md (intro, table + Celtic row, new Celtic section,
  damaskini/reference/local-shelves prose), index.md holdings, sources.md
  (34 upstream sources, six new rows, UD row, local shelves,
  acknowledgements), tools.md (lemma count, ingest URLs, new list/note
  subsections, define/etym StarLing truth), faq.md (holdings + ingest-URL
  answers), languages.md (sga/xtg/pgl/bul rows, new dictionary rows,
  gold-lemma section 17 languages). News post
  2026-07-18-the-library-since-1-0.md — the expansion since 1.0, honest
  numbers, explicitly NOT a release (the v1.1 tag question stays open).
- docs/02-sources.md: rows 56–60/63–65 status fragments READY→LIVE with
  census counts (nothing else touched). docs/ops.md checked — §13 already
  truthful (URL intake documented), no edit.

HONESTY (numbers not verifiable from the census, stated as such in the
docs): fresh passage_lemmas row total (last verified 2,852,069 at
2026-07-14; sga/bul layers landed since), EDH per-language split and
dated-doc count (2026-07-14 figures kept with their as-of date), papyri
per-language split (same). Suite + lint green at hand-off; sha in
worklog `—` (orchestrator fills at merge).

# ── Phase 26 queue: biblical–Indic batch (owner-approved as-is, 2026-07-17; behind Celtic) ─
# Survey: .docs/surveys/biblical-indic-survey.md (all 5 lanes READY, no
# unlock emails). Phasing per survey §6:
# 1. lemma-tier column + DCS (one packet): `lemma_tier` per source
#    (absent = gold), carried per passage_lemmas row (drop-and-rebuild,
#    no migration); attested_count stays GOLD-ONLY, labeled
#    silver_count beside it ("attested 12 (+340 silver)"; silver-only
#    renders "silver 340", never a bare number); LemmaSearch tier
#    labels + --gold-only. DCS: OliverHellwig/sanskrit dcs/data/conllu
#    (NOT "dcs-data" — 02-sources row 7 stale twice: repo + format),
#    15,900 CoNLL-U chapters / 270 texts / CC BY 4.0 verbatim; GOLD
#    gated on machine-readable <layer type="gold"> per chapter;
#    dedup pin vs UD sanskrit-vedic (same Vedic Treebank). Sanskrit
#    gold lights MW + piet IND attested counts (fold spot-verified).
# 2. OSHB — three-legged ot hub (MT ↔ LXX ↔ Vulgate): 39 OSIS books,
#    cts-verse extractor + P13-5 Psalms numbering table verbatim; WLC
#    text PD, morphology CC BY 4.0; hbo + arc per-word axes; lemmas =
#    augmented Strong's. GATE DECISION AT PACKET: upstream anti-NFC
#    warning is MEASURED TRUE (Ruth 1:1 not NFC-stable) — first
#    collision with the NFC invariant, owner rules. Hold out JER/DAN-3/
#    1KI (LXX reorderings). TAHOT (CC BY) = second-witness option.
# 3. SuttaCentral — bilara-data published branch, whole Tipiṭaka roman
#    Pali (7,289 flat-JSON files), 138/140 CC0 + 1 PD + 1 BY-SA
#    (override); shared segment ids → exact -en siblings; new pli axis;
#    sc-data parallels graph (8,221 relations, non-copyrightable) =
#    intertext packet material; legacy NC-ND html_text EXCLUDED.
#    UD_Pali-PaliCanon lands v2.19 (2026-11-15, manual-native lemmas,
#    BY-SA) = future config-only gold.
# 4. SARIT — 83 TEI texts / 178 MB, all headers censused BY-SA/MIT,
#    ZERO NC (the GRETIL upgrade); ~60 works GRETIL lacks incl.
#    complete MBh (38.6 MB); sibling parser (not GretilParser
#    regexes); 41/83 Devanagari (transcode policy verdict); MBh
#    recension check before promising MW citation lights.
# 5. Diorisis — ONLY behind the silver tier: 820 XML (figshare zip
#    md5-pinned), automatic annotation by upstream's own words =
#    SILVER never gold; 806/809 works already held (a lemma layer over
#    our canon, arriving as second editions); IN-FILE CC BY-SA 3.0 US
#    governs over figshare's CC BY 4.0 (in-file doctrine proof #3);
#    the 53 Rahlfs-lineage LXX files EXCLUDED by rule (row 44,
#    machine-readable per-file provenance); upstream's token-gated
#    JSON update channel = license_watch item.
# Riders: 02-sources row 7 correction at DCS promotion; row 44
#    footnote (Diorisis LXX = another Rahlfs dead end).

# ── Phase 26 ──────────────────────────────────────────────────────────

## P26-1 · SuttaCentral — the Pali axis  [tier: fable] [status: done 2026-07-18 — adapter + bilara-json family + fixtures shipped, enabled:false awaiting the owner-fired first sync; verdicts below] [deps: —]

Queue item 3 (biblical–Indic batch): `suttacentral/bilara-data`, branch
`published` — the whole Tipiṭaka in roman-script Pali, English as `-en`
sibling documents keyed by THE SAME segment ids.

SHIPPED:
- `BilaraJsonParser` (NEW family `bilara-json`): flat ordered JSON segment
  map → passages. Citation = segment id minus the redundant `<stem>:`
  prefix; RANGE-STEM files (dhp21-32, sn23.23-33, pli-tv-bu-vb-as1-7 —
  6,707 segments censused) keep the FULL per-item id, colons intact.
  Blank segments (14 corpus-wide) skip by rule; edge whitespace stripped,
  interior verbatim (pdhp's inline `<unclear>` kept); heading block
  (leading `0.x` run of the first item) → title, stem fallback.
- `Suttacentral` adapter: scope root/pli/ms (Mahāsaṅgīti, 7,289 files; the
  xplayground sandbox skips by rule) + root/pra/pts (Patna Dhammapada, 22
  files, `pra` — in scope because its English translation IS the license
  outlier). urn urn:nabu:suttacentral:<stem>, frozen. GitFetch PINNED to
  branch `published` (the P17-1 ref pin). `-en` siblings file-driven with
  the frozen TRANSLATOR_PRIORITY pick (104 double-covered stems, all
  sujato+other); 179 orphan en stems (sujato name/ glossaries, patton's
  Āgama translations of lzh roots) skip by rule. Per-publication license
  gate machine-read from _publication.json: 138 CC0 + 1 PD (scpub64, the
  root) + 1 CC BY-SA 3.0 (scpub69, Ānandajoti's en pdhp) → pdhp-en mints
  license_override "attribution" (P10-4); no-record trees ride LICENSE.md's
  CC0 blanket; unmappable license = loud FetchError; gate only where the
  file exists (the ORACC attic stance verbatim).
- Query::Parallel SUTTACENTRAL_DOCUMENT work family (the Damaskini literal
  `-en` tail split — stems are hyphen-rich); honest one-sided rows pinned
  (en expands the root's blank `…pe…` ellipsis at sn35.24:1.5, leaves the
  `Dutiyaṁ.` colophon untranslated).
- New `pli`/`pra` language axes on the generic fold (dhammā/dhamma pinned;
  no LANGUAGE_FOLDS key needed — measured).
- Registry `enabled: false`, sync_policy manual, translations: true; docs
  02-sources row 66; fixtures = 8 whole byte-verbatim upstream files + a
  _publication.json slice (entry blocks byte-identical), commit
  cebbf6181dafbbde155cce7f0357426cc65e5668 pinned in the README.

JOURNALED (not built, by rule):
- The sc-data parallels graph (8,221 relations / 49,685 refs, upstream
  declares it non-copyrightable) = a FUTURE intertext packet — different
  repo, not fetched here.
- language-notes rider (witness:suttacentral on pli): NOT honest today —
  the accretion hook lives in Store::DictionaryLoader
  (accrete_adapter_language_notes) and suttacentral is a :passages source
  routed to Store::Loader, which has no such hook. The pli dossier is the
  owner's scaffold (canonical/ is not written from a worktree); wire a
  witness lane if/when a passages-loader hook exists.
- The 32 non-English translation languages, root/san + root/lzh parallels,
  and the alternate translators of double-covered stems (suddhaso/soma/
  kovilo variants) = future scope decisions; UD_Pali-PaliCanon v2.19
  (2026-11-15, BY-SA, manual-native lemmas) = future config-only gold.
- Owner sync expectation: ~353 MB clone (310 MB tree + 43 MB .git at
  census); ≈7,310 root docs / ≈445,600 passages + ≈4,712 -en siblings
  (≈12,022 docs total).

## P26-3 · OSHB — the Masoretic witness (the ot hub goes three-legged)  [tier: fable] [status: done 2026-07-18 — adapter + oshb-osis family + NFC-exemption seam + alignment config shipped, enabled:false awaiting owner sync; verdicts below] [deps: —]
Queue lane 2 of the biblical–Indic batch (survey
.docs/surveys/biblical-indic-survey.md; owner-approved 2026-07-17). The
Westminster Leningrad Codex (openscriptures/morphhb, OSIS XML, 39 books)
as the alignment hub's MASORETIC witness: `align "GEN 1.1"` renders
MT ↔ LXX ↔ Vulgate.

SHIPPED:
- THE OWNER RULING IMPLEMENTED (2026-07-18, gate decision): per-language
  NFC exemption. hbo/arc passage text is stored BYTE-VERBATIM — NFC
  reorders Masoretic combining marks (dagesh/shin-dot ccc 21/24 vs vowel
  points 10–19; upstream's anti-NFC warning measured true, Ruth 1:1 the
  pinned byte-identity fixture). Seam: Normalize::NFC_EXEMPT_LANGUAGES
  (["hbo","arc"], primary-subtag scoped) + Normalize.nfc_exempt? +
  Validation.verbatim_text! + a language-keyed branch in Passage.new; the
  conformance suite's NFC assertion branches on the SAME central list (no
  adapter can opt another language out); text_normalized/query folding
  still NFC-fold, so folded Hebrew lookup is unaffected (tested end to
  end: unpointed בראשית finds pointed Gen 1:1 through FTS). Docs:
  architecture §3 exception bullet + conventions §1 paragraph in the
  same change (keep-docs-truthful).
- NEW oshb-osis parser family (DOM, largest book 1.9 MB): verse text
  assembled from the file's own bytes (morpheme-divider `/` = OSHB
  markup, removed; joins follow the source's own inter-element
  whitespace — maqqef/sof-pasuq attach, words space); <w> → P7-5 tokens:
  lemma = AUGMENTED STRONG'S id VERBATIM (the honest modeling — no
  headword exists upstream; "b/7225" indexes into passage_lemmas as-is),
  morph = OSHM code verbatim, immutable word id, lang from the OSHM
  H/A prefix; ketiv/qere notes attach the qere reading(s) to the ketiv
  token; alternative/bare notes = annotations, never running text.
- Language honesty: per-word hbo/arc → per-passage majority (the corph
  mechanics; Jer 10:11 votes arc, Gen 31:47 keeps token-grain Aramaic
  inside an hbo verse), document majority hbo.
- ALIGNMENT (the point): ot work gains "OSHB (WLC, Masoretic)"
  (cts-verse, 29/39 books). HOLDOUTS journaled in-registry: JER/DAN/1KI
  per the survey's conservative map (DAN-3: the numbering: remap is
  witness-global, not chapter-scoped, so the whole book holds out) PLUS
  PRO/JOL/MAL — measured chapter-grain divergence at packet time (MT
  31/4/3 vs Swete 29/3/4, read-only census 2026-07-18); EZR/NEH/ECC
  have no work token. PSA joins the psalms work with the P13-5
  Hebrew→Greek numbering table REUSED VERBATIM (asserted equal to the
  WEB witness's table). Three-legged GEN 1.1 fixture-level align test;
  the live render is the owner's eyeball at sync time.
- License per layer verbatim (fixture README + manifest + 02-sources row
  66): WLC text Public Domain, morphology CC BY 4.0 with the "credit the
  Open Scriptures Hebrew Bible Project" wording carried in the manifest
  license text; class open.
- Fixtures: byte-verbatim slices of morphhb@3d15126f (Gen 1+31, Ruth 1,
  Ps 23, Jer 10, trimmed VerseMap.xml pinned as the non-book); registry
  oshb enabled:false / sync_policy manual; full first-sync clone ≈174 MB
  (wlc/ ≈27 MB).

Owner queue: bin/nabu sync oshb, eyeball nabu show urn:nabu:oshb:gen:1.1
(pointed WLC mark order intact) + 5 random verses + `align "GEN 1.1"`
three-legged, then flip enabled.

## P26-2 · SARIT adapter — the open scholarly Sanskrit shelf  [tier: fable] [status: done 2026-07-18 — adapter + `sarit` family + `Nabu::Deva` shipped, `enabled: false` awaiting the owner-fired first sync (~204 MB clone)] [deps: —]

The GRETIL-posture upgrade: 83 scholarly TEI editions (~170 MB,
github.com/sarit/SARIT-corpus @ `1eac9ee`) whose headers were ALL censused
at parse-scout AND re-verified by this packet's whole-corpus dry run —
**CC BY-SA 4.0 ×56, CC BY-SA 3.0 ×26, MIT ×1, zero NC** → class
`attribution` (GRETIL stays nc-locked). ~60 works GRETIL lacks, incl. a
complete Mahābhārata (38.6 MB) and full Caraka/Suśruta.

Shipped:
- `Nabu::Deva` — one-way Devanagari→IAST transcoder (Slp1/Betacode
  precedent; inherent-a logic is context-sensitive, so it can never be a
  conventions-§9 fold rule and must run before the virāma-stripping generic
  fold).
- `SaritParser` — new bespoke streaming family (SIBLING of GretilParser:
  rung strategy, but citations mined from TEI apparatus, never in-text
  marker regexes). Unit grain lg/standalone-l/p; ladder @n → stripped
  @xml:id → block-quote inheritance (base-text sūtras) → div-scoped
  ordinals (non-canonical flag); `:b<k>` collision suffixes; per-file
  license gate (BY-SA/MIT else quarantine) carried in
  `Document#metadata["license"]`; `<lb break="no"/>` word joins; apparatus
  `<note>`/`<head>` drops. Reader-only (9 files >5 MB; static streaming
  proof à la EpidocParser).
- `Sarit` adapter — flat-root discover (teiCorpus wrapper + header template
  skipped by rule, censused), language ladder text→body→script-sniff
  (sa→san, braj→bra, avadhi→awa), urn `urn:nabu:sarit:<filename-stem>`,
  GitFetch. Registry `enabled: false`, `sync_policy: manual`.
- SCRIPT VERDICT: native script stays the canonical surface (41/83
  Devanagari); the search layer folds the Deva→IAST transcode
  (text_normalized = san fold of `Deva.to_iast`, the ccmh-txt
  documented-derivation mechanism). Proven end-to-end in the adapter test:
  one IAST FTS query lands on the IAST aṣṭāvakragītā AND the Devanagari
  MBh. v1 limitation, documented: Devanagari-TYPED queries are not
  transcoded query-side (query_forms' generic fold strips the virāma
  first) — future packet if wanted.
- MBh RECENSION VERDICT: SARIT's MBh is the SOUTHERN RECENSION (Kumbakonam,
  Krishnacharya & Vyasacharya 1906–1910, per its own editionStmt) — not
  BORI, not the Calcutta vulgate MW's `MB.` citations reference → NO
  MW-citation joins promised on it (docs say so; MwSigla untouched).
- Fixtures (4): astavakragita + samanyadusana whole; nyāyabhāṣya sūtras
  1.1.1–1.1.2 trim; MBh two-parva trim (147 KB, the trimmed-but-big
  streaming fixture) — README + manifest, license verbatim.
- Dry run over the full clone (projected first sync): 78 docs / 345,601
  passages; 5 honest quarantines, all named (4 `<ab>`-shaped Braj/Awadhi
  texts + list-shaped ayurvedasutram — small v2 rungs, the P9-4c
  precedent).

Docs: 02-sources row 68; fixtures README. Suite + lint green at hand-off;
sha in worklog `—` (orchestrator fills at merge).

## P26-0 · lemma-tier column + DCS — gold Sanskrit  [tier: fable] [status: done 2026-07-18 — tier machinery + DCS adapter shipped, enabled:false awaiting owner sync; verdicts below] [deps: —]
Queue item 1 (biblical–Indic batch, survey §6): the gold/silver lemma
tier lands BEFORE any silver source exists (Diorisis is queue item 5),
so the semantics are pinned by tests while every live source is still
gold; then DCS proves the gold path with the first gold Sanskrit.

SHIPPED — the tier:
- sources.yml `lemma_tier: gold|silver` per source, ABSENT = GOLD (zero
  churn for every existing entry; SourceRegistry validates, and
  #lemma_tiers hands only the non-gold map downstream — absent-is-gold
  is the wire format end to end).
- TIER-MECHANISM VERDICT: the per-row tier lives on passage_lemmas in
  fulltext.sqlite3 — a FULLTEXT-side column, NOT a catalog migration.
  passage_lemmas is Indexer-built, drop-and-rebuild, never migrated
  (the P7-5 stance), and the tier is registry posture × source
  identity, both known at index-build time; sync's reindex and rebuild
  both thread SourceRegistry#lemma_tiers into Indexer.rebuild!, which
  resolves source_id→tier once per pass (no third join on the
  streaming query). Pre-tier fulltext files keep serving: consumers
  probe for the column and read all-gold (the borrowed_column?
  pre-migration precedent) — correct, since only gold sources existed
  before the column.
- attested_count stays GOLD-ONLY everywhere; ReflexViews resolves a
  separate labeled silver_count beside it. Renders (define/etym CLI +
  MCP reflex payloads): "1 passage (+2 silver)"; silver-only reflexes
  get their own "silver-only (automatic lemmatization…)" section,
  "silver N passages" — the NEVER-A-BARE-NUMBER rule is pinned by
  explicit render tests stated as refutations (a silver count must
  never render where a reader could take it for gold, and gold+silver
  must never sum).
- search --lemma includes silver hits with per-hit [silver] labels
  (gold stays unlabeled — the pre-tier render exactly), a silver
  footer total, and --gold-only (requires --lemma; refuses --near);
  MCP lemma hits mirror the labels (tier key on non-gold hits only).
  `nabu language` scopes its gold-labeled lemma counts to the gold
  tier.
- JOURNALED for the Diorisis packet (not built — no silver rows exist
  yet, so behavior today is identical): the OTHER lemma-table
  consumers still read both tiers unlabeled — cognates' witness
  lookups, vocab's corpus frequencies, concord/proximity's
  surface-form expansion, ReflexRootsIndexer's language scope. Each
  needs a labeled-or-scoped decision WHEN silver rows first land;
  grep Store::Indexer::LEMMA_TABLE for the census.

SHIPPED — DCS (Digital Corpus of Sanskrit):
- 02-sources row 7 was stale TWICE (nonexistent "dcs-data" repo,
  "custom text format") — CORRECTED: the corpus is standard CoNLL-U
  (UD-compliant since Aug 2022) at dcs/data/conllu/ inside
  OliverHellwig/sanskrit. Census at fixture commit 04e0778d
  (2026-07-18): 15,900 .conllu chapter files / 270 text dirs /
  ~844 MB / ~5.46M words, + 7,227 .conllu_parsed automatic siblings
  (NEVER ingested — the *.conllu glob cannot match them, test-pinned)
  + one stray zero-byte extensionless file (ignored). CC BY 4.0
  verbatim in BOTH data readmes (quoted in MANIFEST.license, row 7,
  fixture README).
- GOLD GATED ON THE MACHINE DECLARATION: lookup/chapter-info.xml
  (8.9 MB, XML::Reader-streamed per the >5 MB rule) declares
  <layer type="gold">lexicon</layer> + morpho-syntax for ALL 15,900
  chapters (1,780 add gold syntax = the Vedic Treebank, the only
  chapters with filled HEAD/DEPREL); an undeclared or non-gold
  chapter QUARANTINES with a message naming the gate — never a silent
  skip, never prose-based gold. lemma_tier ABSENT in sources.yml =
  gold, by the tier's own contract.
- GRAIN VERDICT (censused): document per chapter FILE — the corpus's
  own unit ("each chapter … is in a separate file"); passage per
  sentence block; urns from upstream's permanent numeric ids,
  urn:nabu:dcs:<textId>:<chapterId>:<sent_id> (filenames carry
  spaces/commas/diacritics — names live in titles/metadata). sent_id
  shapes vary per chapter ("556276_1" vs "10902") — verbatim, both
  honest. Chapter metadata rides the document: text/chapter names +
  ids, position, dcsTimeSlot, gold_layers, Vedic <details>
  (register/veda → document facets).
- THE FOLD-JOIN PROOF (scout 7/7, now test-pinned): DCS kaṇṭha (2
  fixture passages) and śīghrá light ReflexViews attested_count
  through a reflex row folded exactly as starling piet folds its IND
  stems (fold("kaṇṭha")="kantha", fold("śīghrá")="sighra"); DCS aṃśa
  hits carry the MW gloss end-to-end on real fixtures of both sources
  (fold("aṃśa")="amsa"=fold(SLP1 "aMSa")) — zero new fold rules.
- DEDUP PIN (no dedup wanted): ud/sanskrit-vedic is the same Hellwig
  Vedic material at a different grain (UD conversion there, native
  chapters here) — two honest witnesses, the MW-beside-kaikki
  precedent; the UD dedup guard is for RE-EXPORTS of already-synced
  sources, which this is not. Pinned in the adapter test header so
  nobody "fixes" it later.
- FETCH DESIGN: GitFetch grew an optional sparse: cone (blobless
  --no-checkout clone + sparse-checkout set --no-cone + checkout;
  pulls scope the deletion diff/attic to the cone) — the repo is
  ~1.7 GB, the cone (dcs/data/conllu + dcs/data/readme.md) ~844 MB on
  disk; git compresses CoNLL-U hard, so expect the first sync to
  TRANSFER a fraction of that (hundreds of MB), then discover/parse
  15,900 chapters. Registry enabled:false, sync_policy manual.
- Fixtures: 3 real chapters (AU 1,1 whole ×35 blocks incl. gold
  syntax + details; two Suśruta chapters trimmed to header + first 3
  + the kaṇṭha/śīghra/aṃśa blocks), the trimmed .conllu_parsed
  sibling (never-discovered pin), the 3 chapter-info entries
  byte-verbatim, both readmes whole; README + manifest.yml with the
  pinned commit and re-trim procedure.

Tests +42 (registry 2, indexer 2, lemma search 4, reflex_views 4 [new
mirror file], language_info 1, cli 4, mcp 2, git_fetch 2, dcs 21 incl.
conformance/idempotent double-load/gold-gate quarantines/tier + join
pins/sparse local-git fetch). Suite 3,156 runs / 37,959 assertions
exit 0 (0 skips) · lint 406 files exit 0. OWNER QUEUE:
bin/nabu sync dcs (sparse clone, ~844 MB cone), eyeball
urn:nabu:dcs:5:3656 + `nabu search --lemma kaṇṭha` + 5 random chapters,
flip enabled, rebuild/reindex.

## P26-4 · Diorisis — the SILVER Greek lemma layer  [tier: fable] [status: done 2026-07-18 — adapter + `diorisis` streaming family + fixtures + the per-surface tier verdicts shipped, enabled:false awaiting the owner-fired first sync; verdicts below] [deps: P26-0]
Queue item 5 (biblical–Indic batch, survey §6): the tier's first
occupant — ~10.2M words of automatically lemmatized Greek arriving as
silver, never gold, over a canon the catalog already holds bare.

SHIPPED — the corpus:
- ARTIFACT: figshare v1 (2018) zip, 194,443,428 bytes, md5
  f3a26efa7e7d2b93d1bcca26900d180a — VERIFIED byte-for-byte against
  figshare's own published computed_md5 at the census download —
  sha256 fb32b7ff…19b65 pinned in the adapter (ZipFetch, the IE-CoR
  prepare→verify-pin→breaker→complete choreography; a mismatch aborts
  with the tree untouched). 820 XML / ~2.5 GB unpacked. Whole-corpus
  census run over the real zip: 538,011 sentences / 10,206,421 words /
  98.5% lemmatized (81.8–100% per file); provenance Perseus 752 /
  Bibliotheca Augustana 60 / Mikros Apoplous 8; body inventory CLOSED
  (sentence/word/lemma/analysis/punct); sentence ids unique per file;
  TreeTagger=true on 1.84M words with 1/n disambiguated fractions
  (1.0/0.5/0.33/…); 153,593 entry-less (unlemmatized) words; 429
  non-NFC lemma entries (NFC'd at the boundary).
- LICENSE (in-file doctrine proof #3): figshare page says CC BY 4.0;
  ALL 820 files' own publicationStmt declare "Creative Commons
  Attribution-ShareAlike 3.0 United States License" — the in-file
  declaration GOVERNS; both quoted in the manifest + 02-sources row
  69; class attribution.
- SILVER, NEVER GOLD: upstream's own in-file words are "corpus
  conversion and automatic annotation" (editionStmt) — sources.yml
  `lemma_tier: silver`; the whole tier render verified end to end on
  REAL fixture bytes (silver rows in passage_lemmas, [silver]-labeled
  LemmaSearch hits, --gold-only exclusion, ReflexViews silver_count
  beside a nil attested_count — never a bare number).
- THE RAHLFS EXCLUSION (row 44 xref): 53/820 files are the Septuagint
  — machine-readable header identity tlgAuthor 0527 (sourceDesc
  Bibliotheca Augustana = the Rahlfs lineage; scout text-diffed
  divergent from held Swete tlg0527). discover skips by rule with an
  honest discovery_skips census (53 upstream / 1 in fixtures); parse
  refuses belt-and-braces (a rights exclusion deserves both layers);
  the fetched artifact stays whole in canonical.
- SECOND EDITIONS, deliberately: 806/809 works already held (742
  Perseus, 102 First1K) — Diorisis mints its own documents
  (provenance-distinct second editions, the MW-beside-kaikki
  precedent); no dedup, no cross-links; the value IS the lemma layer.
- PARSER VERDICT: new bespoke `diorisis` streaming family (sibling of
  ProielParser's shape) — TEI.2 P4-era XML, no namespace, no XML
  declaration, so no TEI/EpiDoc family fits; Reader-only pinned
  structurally (76 files >5 MB, Polybius 76.1 MB). Word forms are TLG
  Beta Code decoded through the EXISTING Nabu::Betacode (census: zero
  out-of-inventory characters; zero new fold rules); punct marks kept
  VERBATIM glued left (")" is a Beta Code breathing — decoding punct
  would fabricate combining marks); lemma entry = Unicode, NFC'd.
  Annotations: lean tokens (id/form/lemma/lemma_id/pos + tree_tagger/
  disambiguated only where TreeTagger actually fired + analyses); the
  Perseus-style prose morph strings are a THIRD morphology dialect —
  deliberately NOT wired into --morph (MorphFacets speaks UD+PROIEL;
  absence over a wrong mapping).
- GRAIN VERDICT (frozen minting): document per work file,
  urn:nabu:diorisis:<tlgAuthor>:<tlgId> (header-peeked, streamed);
  passage per sentence on upstream's file-stable sentence ids
  (censused unique; the zip is frozen, so ids are the stability
  contract). location is NOT identity — it repeats (poetry lines),
  goes empty (142 files incl. all 53 LXX + Aristides), and free-forms
  ("APr.Α", "6,7", "fragment") — it rides as the verbatim citation in
  annotations. Header metadata (author/title/genre/subgenre/creation
  date/provenance ref+URL/tlg ids) rides document metadata.
- Registry: enabled:false, sync_policy manual (frozen artifact),
  lemma_tier: silver; license_watch deliberately UNSET (figshare API
  body carries volatile stats — hash compare would false-alarm); the
  token-gated per-file JSON update channel (v1.6) journaled in
  sources.yml comments as the future-refresh watch item.
- PROJECTED first sync: ≈767 docs / ≈516,500 passages / ≈9.6M words →
  ≈6–7M silver lemma rows (the fulltext db roughly triples; the
  2.85M-row gold index is untouched by every gold-scoped surface).

SHIPPED — the P26-0 journaled per-surface verdicts (each TDD'd):
- cognates: GOLD-SCOPED (witness lookups + suppression df both) —
  reconstruction evidence; a silver witness contributes NO cognate
  evidence (refutation-pinned), and a silver flood cannot re-judge a
  gold lemma common.
- ReflexRootsIndexer: GOLD-SCOPED (closure language scope + stats
  gold_passages denominators) — a silver-only language stays out of
  the closure; numerator and denominator agree with cognates.
- vocab: LABELED + gold reference — silver documents DO profile (that
  is the Diorisis value) under an explicit "silver lemmas / lemma
  tier: silver (automatic lemmatization…)" render, never the gold
  name; corpus reference frequencies, corpus total and the
  gold-bearing-languages listing stay gold-scoped (the documented
  denominator keeps its meaning).
- concord: LABELED pass-through — a formatter over LemmaSearch
  inherits the hit tier; CLI tags [silver] rows + silver footer, MCP
  rows carry tier key on non-gold only (the lemma-hit mirror); text
  mode claims no tier (nil).
- proximity: BOTH TIERS, deliberately — the lemma anchor is retrieval
  expansion (hits are real text judged from snippets, no annotation
  claim rendered); silver-attested inflections expand the anchor,
  mirroring search --lemma's inclusive stance (test-pinned).
- parallels (censused beyond the journal's four): BOTH TIERS,
  deliberately — lemma echoes are a heuristic discovery signal, and
  silver df IMPROVES the rarity estimate (gold-rare-but-corpus-common
  is genuinely undiagnostic); test-pinned.
- language_info: already gold-scoped at P26-0 (no change).

Fixtures: Hymn 13 To Demeter WHOLE (8.3 KB — repeating locations,
entry-less lemma, TreeTagger fractions, Beta Code capitals/elision),
Thucydides trimmed to header + 3 sentences (dotted citations, the
36.9 MB file the streaming rule exists for), LXX Abdias trimmed +
PINNED AS EXCLUDED (empty locations documented), README with both
license quotes + md5/sha256 + re-trim procedure.

Tests +23 net adapter/parser (10 parser + 23 adapter incl.
conformance, exclusion census + belt-and-braces refusal, idempotent
double-load, silver tier end-to-end, sha-pin fetch trio) + 11 tier
surfaces (cognates 2, reflex_roots 2, vocab 4, concord 2 [+1 MCP],
proximity 1, parallels 1, cli 3). Suite + lint exit 0 at hand-off
(exact counts in worklog). OWNER QUEUE: bin/nabu sync diorisis
(194 MB download, md5/sha-pinned), eyeball urn:nabu:diorisis:0012:001
+ `nabu search --lemma θεός` (expect [silver] labels) + 5 random
passages, confirm the 53-file skip census line, flip enabled,
rebuild/reindex.

## P26-5 · Incremental per-source indexing — syncs stop paying the corpus-wide reindex  [tier: fable] [status: done 2026-07-18 — refresh_source! + inert-grain skip + honest sync line shipped; verdicts below] [deps: P26-0]

The owner-triaged defect: every sync of every source ended in
SyncRunner#reindex! → Indexer.rebuild!, which drops the fulltext +
lemma tables and re-inserts all ~4.3M live passages, then rebuilds the
trigram and alignment indexes — minutes per sync regardless of what
changed; a two-file `sync local-notes` paid the full price. Owner
decision 2026-07-18: A+B approved; NO `nabu index` command; syncs keep
auto-indexing where it makes sense; `nabu rebuild` owns full
re-indexing.

SHIPPED — Part A (index-inert grains skip indexing entirely):
- Content kinds `:notes`, `:language`, `:source` mint neither passages
  nor dictionary entries → their syncs perform NO index work at all
  (`SyncRunner::INDEX_INERT_KINDS`; `indexed: nil`, the CLI omits the
  fragment). Pinned by an every-entry-point spy test (hand-rolled
  singleton swap — minitest 6 ships no stub): rebuild!,
  refresh_source!, rebuild_trigram!, AlignmentIndexer.rebuild!,
  ReflexRootsIndexer.rebuild! all raise; a notes/language/source-shelf
  sync completes without even creating the fulltext file.

SHIPPED — Part B (passage/dictionary syncs index incrementally):
- `Indexer.refresh_source!(catalog:, fulltext:, slug:, …)`: delete the
  source's rows from passages_fts + passage_lemmas (+ trigram slice),
  re-insert from the current catalog, tier map preserved. CONTRACT =
  ROW IDENTITY: after a refresh the fulltext state equals a
  from-scratch rebuild! of the same catalog — pinned by building both
  and comparing full row sets (fts, lemmas incl. tiers, trigram +
  scope, reflex closure + stats) across add/revise/withdraw mutations.
- FTS-DELETION VERDICT: passages_fts/passages_trigram are REGULAR
  (contentful) FTS5 tables — per-row DELETE is real deletion (the
  contentless/'delete'-command hazard does not apply); proven by
  search-before/after tests. passage_id is UNINDEXED, so deletion is
  ONE streaming rowid scan (collect doomed rowids by Set membership —
  withdrawn ids included, since the loader never hard-deletes, every
  indexed id resolves forever) + batched rowid deletes — never a scan
  per IN-batch. passage_lemmas deletes by its indexed urn column.
- TRIGRAM VERDICT (measured live 2026-07-18): 1,713,160 rows, scope
  papyri-ddbdp/oracc/edh (all sync_policy manual/frozen — rarely
  synced). Per-source slice refresh: rows deleted+reinserted only when
  the source is flagged now OR was indexed by the last build; a
  de-flagged source loses rows AND scope row (honest coverage); a
  non-fuzzy source's sync never touches the table.
- ALIGNMENT VERDICT (measured live): alignment_refs = 157,285 rows,
  registry-scoped — full AlignmentIndexer.rebuild! per sync is cheap
  AND gated: it fires only when the synced source holds a registry
  witness document; every other sync skips it (sentinel-pinned).
- REFLEX-CLOSURE VERDICT (measured live): reflex_roots 84,150 +
  stats 17 rows — rebuilt only when the source's lemma rows changed
  (delete/insert counts) or, for dictionary syncs, unconditionally
  (`reflexes_changed:` — the crosswalk feeding the closure changed);
  a lemma-less passage source skips it (sentinel-pinned).
- FALLBACKS (honest, one-time): fulltext missing any table (first-ever
  sync) or passage_lemmas predating the P26-0 tier column → full
  rebuild!, then the SOURCE's live count is still what's reported —
  so the first sync against the owner's live pre-P26-5 file just works.
- OUTPUT HONESTY: the sync line's fragment is now
  "indexed N passages (slug)" — the SOURCE's live rows, never the
  corpus total; suppressed at nil (inert) and 0 (dictionary grains,
  compact zero-field rule). `nabu rebuild`'s corpus-total line is
  untouched — there it IS the corpus.
- `nabu rebuild` keeps the full rebuild! path byte-untouched — the
  from-scratch guarantee and the only full-reindex surface.
- PROJECTED sync-time impact (queued P26 syncs): the per-sync
  fixed cost drops from a full 4.3M-passage + 3.0M-lemma-row rebuild
  (+1.7M trigram + alignment + closure) to one fts rowid scan +
  the source's own slice — e.g. corph re-sync re-inserts 17,942
  passages, dcs ≈516k projected inserts instead of ~4.8M, diorisis
  likewise; local-notes/language/source syncs do zero index work.
  Live timing proof is the review gate's (orchestrator).
- DOCS: architecture §5 index-lifecycle bullet (rebuild stays the pure
  function; syncs maintain incrementally under the row-identity
  guarantee) + §10 rebuild-safety and §12 closure choke-point sentences;
  ops.md "What `nabu sync <source>` actually does" (fetch/attic → load/
  quarantine → derived layers → incremental index maintenance, one
  annotated example line); site/faq.md "What happens when I sync a
  source?" (+ why notes/dossier syncs are instant); site/tools.md
  checked — wording not falsified, untouched.
- Tests +18 (indexer refresh 15 incl. row-identity + both fallbacks +
  trigram/alignment/reflex gates; sync_runner 3 spy/honesty/withdrawal
  pins + dictionary-indexed assertion; cli pins updated/added in-place).
  Suite 3,368 runs / 45,501 assertions exit 0 (0 skips) · lint 424
  files exit 0.

## P26-6 · ZipFetch/FileFetch follow redirects — figshare's 302 front door  [tier: fable] [status: done 2026-07-18 — RedirectFollow extracted + both fetchers wired; verdicts below] [deps: P26-4]

The owner's live incident 2026-07-18: `bin/nabu sync diorisis` →
`diorisis fetch failed … HTTP 302 for
https://ndownloader.figshare.com/files/11296247`. figshare's
ndownloader ALWAYS 302s to a rotating S3 mirror; ZipFetch and
FileFetch treated any non-200/304 as an error (every earlier zip/file
upstream served 200 directly — first contact). UrlDownload already
carried the proven bounded follow loop (P20-0, the archive.org case).

SHIPPED:
- SHARED-SEAM VERDICT: the loop is EXTRACTED to `Nabu::RedirectFollow`
  (one module, three riders — not three copies, not a wrapper on
  default_http, which would have hidden the terminal-status/error-class
  differences). Parameterized by the caller's error class, the accept
  list ([200] UrlDownload, [200, 304] the sync fetchers) and per-hop
  headers. Doctrine verbatim from UrlDownload: 301/302/303/307/308,
  MAX_REDIRECTS 5, relative Location via URI.join against the CURRENT
  url, honest errors naming the hop cap / the missing Location / the
  transport failure. UrlDownload adopted it — behavior byte-identical,
  its tests untouched and green (constants re-exported by reference).
- CONDITIONAL-GET VERDICT: If-Modified-Since rides EVERY hop, and 304
  sits in the sync fetchers' accept list — so a 304 is honored whether
  it arrives at the FIRST hop (pre-redirect; upstream answered the
  conditional itself) or from the mirror after the 302 (figshare's
  actual shape: ndownloader 302s even conditional GETs; S3 answers).
  Both flows test-pinned for ZipFetch AND FileFetch.
- ORIGINAL-URL DOCTRINE: state files (.zip-fetch.json/.file-fetch.json
  Last-Modified + sha pins) key off the ORIGINAL url, never the
  redirect target — mirror targets rotate (the UrlDownload precedent);
  pinned by asserting state "url" after a redirect-delivered fetch.
- RIG FIX (found by the new assert_requested counts): ZipFetchTest and
  FileFetchTest defined `teardown` without `super`, silently clobbering
  webmock/minitest's alias-chained WebMock.reset! — the request
  registry accumulated across tests in exactly those two classes.
  `super` restored; no existing assertion depended on the accumulation.
- Diorisis regression: the adapter's fetch against a WebMock'd
  figshare 302 → S3 200 completes with the sha pin verified on the
  FINAL body (the mirror-request asserted).
- Tests +16 (zip_fetch 5, file_fetch 6, redirect_follow 4 helper-
  contract pins, diorisis 1). Suite 3,384 runs / 45,549 assertions
  exit 0 (0 skips) · lint 426 files exit 0. The live
  `bin/nabu sync diorisis` is the orchestrator's review proof.

# ── Phase 27 ──────────────────────────────────────────────────────────

## P27-0 · Display policy core + script-level mark classes  [tier: fable] [status: done 2026-07-18 — Nabu::Display shipped, six render commands wired; verdicts below]

Owner-gated design (2026-07-18, "one big Display phase"): ONE render-only
policy module applied where passage text reaches the terminal; MCP and
export always pristine; canonical/db untouched.

SHIPPED:
- `Nabu::Display` (lib/nabu/display.rb): named mark classes (data-driven,
  one place), per-language policies from `config/display.yml`
  (missing file = pass-through; unknown class/language/isolates value =
  named ConfigError), a MODE REGISTRY (the sibling seam), grapheme-safe
  stripping, RTL isolate wrapping, `visible_length` for width math.
- CENSUS (real fixture bytes, 2026-07-18 — the sets are census-backed):
  · cantillation U+0591–05AF: OSHB Gen/Jer/Ps/Ruth carry 25 distinct
    accents, ×1,436 total (0591 ×133, 0596 ×254, 05A3 ×243, 05A5 ×248,
    05B* points excluded by definition).
  · points: U+05B0–05BC ×5,538, shin/sin dots 05C1 ×230 / 05C2 ×74,
    05C7 ×0; METEG U+05BD ×252 INCLUDED (Unicode names it HEBREW POINT
    METEG; census-backed) — a deliberate extension of the spec's
    enumeration; rafe U+05BF censused ×0 → left OUT ("never strip what
    you haven't censused"). Sof pasuq 05C3 ×138 / paseq 05C0 ×14 are
    punctuation — unclassified, always kept.
  · maqaf U+05BE ×258 — its own class; strips to a SPACE (never fuses
    the joined words); in `keep` for hbo (default shows it).
  · vedic-accents U+0951/0952: censused ×0 across the san shelves — DCS
    is IAST romanization, the SARIT Devanagari fixtures are unaccented.
    The class is live machinery, honestly journaled as a measured no-op
    today (policy scoped by primary subtag: san/san-Deva/san-Latn).
  · titla U+0483 + U+0487 + U+2DE0–2DFF: torot 0483 ×49, ud (orv
    birchbark) ×51, wiktionary-cu 0483 ×39 / 0487 ×1 / 2DED ×2. The
    CCMH FIXTURES CARRY NONE — that corpus stores the Helsinki 7-bit
    ASCII transliteration verbatim (titlo encoded as `!`), so the spec's
    "OCS shelves use these heavily" is true of TOROT, not CCMH — journaled
    as measured. Palatalization U+0484 (torot ×22) is NOT a titlo → NOT
    in the set.
  · monotonic (grc, OPTIONAL — definable, never defaulted): U+0300/0313/
    0314/0342/0343/0345; a STRIP, not a polytonic→monotonic conversion
    (conversion = a later packet's mode).
- GRAPHEME SAFETY: NFC languages strip via NFD→delete→NFC (precomposed
  marks reachable); NFC-EXEMPT hbo/arc (P26-3) strip IN PLACE, bytes
  never normalized — test-pinned on a dagesh+sheva+etnahta sequence.
- MODES: default (policy strip lists) / full (no transforms, no
  isolates — the byte-honest escape hatch) / plain (strip+keep union =
  consonantal Hebrew). Registry seam: modes are objects (#name,
  #description, #render(text, language:, policy:) → Rendered,
  #isolates?(policy)); `Display.register_mode` adds (duplicate name =
  error, never silent replace); `Display.mode` names the registry on a
  miss. Sibling packets (reading/translit/mono) register and appear in
  --display without reshaping CLI or module.
- CALL-SITE CENSUS (cli.rb; every place passage text reached stdout):
  print_show_passage/_document/_range; parallel_line + block translation
  (show --parallel); print_align_witness + print_align_range_witness +
  collation cell/edits/aside (align, --collate); print_search_results
  (search + --near), print_fuzzy_results, print_lemma_results (pristine
  line); print_concord_rows; print_parallel_hit evidence + lemma echoes'
  surfaces stay folded-label; print_cognates witness lemma + surfaces.
  All funnel through ONE helper (display_text) + per-command
  print_display_footer. define/etym/vocab/export untouched (dictionary
  shelf + data surfaces, out of scope).
- FOOTER: once per invocation, only when a transform actually changed
  bytes (compact rule): `display: cantillation stripped · rtl isolates
  (--display full shows all marks)`; chu form byte-pinned as
  `display: titla stripped (--display full shows all marks)`.
- ISOLATES: U+2067/U+2069 wrap for hbo/arc runs (config-driven);
  excluded from ALL width math (Display.visible_length); concord re-pads
  its KWIC columns over visible characters post-transform (keyword
  column pinned at exactly --width); align layout byte-identical apart
  from the text runs (structural-lines pin).
- INDEPENDENCE PINS: same search hits under every --display mode;
  `show --display full` byte-identical to db text; MCP nabu_show serves
  pristine bytes with the shipped display.yml present (tools_test pin).
- Config seam: `Config#display_path` (`paths: display:` override,
  default config/display.yml, kwarg default beside sources.yml — test
  rigs opt IN by placing a display.yml; all pre-P27 rigs untouched).
- DEVIATIONS (from the letter of the spec, argued): (1) meteg U+05BD
  into `points` (Unicode name + census ×252; without it "plain" is not
  consonantal); (2) maqaf strips to space, not empty (deleting would
  fuse עַל־פְּנֵי into one word); (3) mixed-language documents render
  document-listing lines under the DOCUMENT language policy
  (PassageLine carries no language; hbo/arc Daniel-Ezra splits land in
  the same script family, correct in practice).
- DOCS: NEW public docs/display.md (owner addendum 2026-07-18) — nabu's
  display layer + the verified terminal-side facts (iTerm2 ≥3.6.0
  experimental RTL toggle under Settings→General→Experimental;
  Terminal.app no bidi; non-ASCII font slot is per-codepoint → Noto Sans
  Mono same-size, Ezra SIL/SBL Hebrew via a dedicated profile; Noto
  script casks join the fallback cascade) + per-script quick table with
  real-shelf test commands. ops.md §16 summary → links it; site/faq.md
  new Q (terminal display) → links it; site/tools.md checked — no
  display discussion, untouched.
- Tests +37 (display_test 25 unit incl. fixture-byte pins for
  hbo/chu/san + config validation + registry seam; cli 9 e2e incl.
  footer presence/absence, full byte-identity, consonantal plain,
  search-mode independence, KWIC column, align layout; config 2; mcp 1
  pristine pin). Suite 3,421 runs / 45,701 assertions exit 0 (0 skips)
  · lint 428 files exit 0.

## P27-1 · Edition-level display transforms — reading/diplomatic + per-edition choices  [tier: fable] [status: done 2026-07-18 — reading/diplomatic modes on the P27-0 seam; censuses & verdicts below] [deps: P27-0]

Layer B of the Display phase (owner-approved): transforms keyed to SOURCE
editorial conventions, not language — `sources:` in config/display.yml,
executed only by the new `reading` mode; `diplomatic` is the byte-honest
counterpart.

SHIPPED:
- `reading` mode (Display::ReadingMode, registered on the P27-0 registry
  untouched): ketiv/qere substitution → per-source edition rules → the
  language policy's default strips, in that order (qere runs on the
  pristine stored bytes so token forms match exactly; Hebrew reading =
  qere + cantillation stripped TOGETHER). Without edition context the
  mode degrades to exactly default-mode behavior. Edition context is an
  OPT-IN mode capability (#render_edition) — every P27-0 mode and the
  registered-mode seam are byte-untouched.
- `diplomatic` mode: no transforms, no isolates — byte-identical to the
  stored text (pin over every shelf's fixture bytes). Today it renders
  identically to `full`; registered under the editorial name so the
  reading-mode footer's "--display diplomatic shows the edition marks"
  has a real counterpart.
- EDITION_RULES (census-first, STORED bytes): lacuna ("[…]" → "…",
  ellipsis|keep), erasures (⟦…⟧, keep|unwrap — default KEEP, an erasure
  is content), surplus ({…}, keep|unwrap — default KEEP, unwrapping would
  present the carver's error as fluent text), sigla (⸀⸂⸃, strip|keep).
  Shipped sources: papyri-ddbdp/edh/riig lacuna ellipsis; edh erasures
  keep; riig surplus keep; sblgnt sigla strip; oshb qere_display qere.
- Ketiv/qere (oshb): STORAGE VERDICT — the running text carries the KETIV
  (<w type="x-ketiv">); the qere reading(s) attach to that token as
  "qere" word hashes inside annotations["tokens"] (OshbOsisParser P26-3).
  Display substitution walks the tokens in document order with a cursor
  (the text was assembled from those very forms — exact, no re-parse);
  qere_display: qere|ketiv|both, "both" renders "ketiv [qere]". Fixture
  census: 3 qere tokens (jer 10.13, 10.17, ruth 1.8), all 1-word qere,
  every ketiv form found verbatim in its passage text.
- Query::Show carries annotations (PassageResult + PassageLine, parsed
  from the stored annotations_json) — the CLI show family (passage,
  document listing, range) passes source + annotations to display_text;
  every other call site renders under language policies alone (search
  rows carry no source_slug; extending them is future work, not silently
  half-done). MCP payloads untouched — pristine.
- Footer: strips vocabulary unchanged; edition transforms hint as
  `apparatus simplified: qere, …` and swap the escape hatch to
  `(--display diplomatic shows the edition marks)`.

PER-SHELF CENSUS (stored passage bytes, parser output over checked-in
fixtures, 2026-07-18):
- papyri-ddbdp (32 passages): "[…]" ×2 — NOTHING else. The DdbdpParser
  print-edition doctrine already reads through supplied/expan/unclear
  markerless at parse time; supplements/additions/expansions/underdots
  censused ×0 stored → NO rules invented for them (census-first pin).
- edh (17 passages): "[…]" ×4; ⟦…⟧ ×2 (HD000082 damnatio memoriae).
  Upstream "[---]"/"//" lacuna spellings normalize to "[…]" at parse
  time — censused ×0 stored.
- riig (42 passages): "[…]" ×9; surplus {…} ×2 (nanton{t}icnos).
- ogham (17 passages): ZERO edition marks — no sources: entry (nothing
  censused, nothing stripped).
- sblgnt (90 passages): ⸀ ×69, ⸂ ×30, ⸃ ×30; ⸁/⸄–⸇ ×0 → excluded from
  the sigla set. Parentheses ×1 (John 1:15) are the edition's own
  punctuation — never touched (pin).
- oracc (59 passages): {} ×25 — DETERMINATIVES ({d}, {ki}, {iti}), not
  Leiden surplus: keep-text-drop-marker would fuse the silent classifier
  into the word ({d}amar-{d}suen misreads "damar-suen") — deliberately
  left. Standalone x ×72 = illegible-sign placeholders (content); "()"
  ×1 = metrological notation (2(BARIG)); ⸢⸣ half-brackets ×0. NO oracc
  entry; all three leaves journaled here.
- oshb (138 passages): no bracket apparatus in text; ketiv/qere as above.

ORIG/REG VERDICT (riig): no display-time choice exists to wire — RIIG's
parallel editorial readings mint SIBLING passages by seg id
(ahp-01-01:HRD-a:1 καρε[…]μ vs :PTL-b:1 καρβ[…]μ; the P25-1 grain), and
within one passage CelticLeiden <choice> keeps the reg branch (orig is
apparatus, dropped at parse). Reading-mode's Leiden handling suffices;
no work invented.

DEVIATIONS (from the packet letter, argued):
- Leiden supplements/additions/expansions/underdot rules NOT implemented:
  censused ×0 in every shelf's STORED bytes (the parsers resolve raw
  Leiden at parse time) — "never strip what you haven't censused" wins
  over the packet's rule list.
- surplus defaults KEEP (packet named only erasures configurable): {t}
  marks a carver's error the editor excludes; unwrapping by default would
  present the misspelling unmarked. unwrap is config-reachable.
- sigla set is ⸀⸂⸃ exactly as the packet names (⸁ ⸄–⸇ censused ×0,
  excluded per census-first).
- Edition rules scope: the show family only (search/concord/align result
  rows carry no source_slug today); documented in display.md §1a, and
  matching-independence pinned across reading/diplomatic regardless.

Tests +27 (display_test +22: per-shelf before/after real-byte pins,
diplomatic byte-identity, qere qere/ketiv/both, config validation,
shipped-config pin; cli_test +5 e2e: reading qere + footer, diplomatic
hint-free byte-identity, sblgnt sigla, default-mode silence, document
listing qere; +2 modes on the search-independence pin). Suite 3,448 runs
/ 45,834 assertions exit 0 (0 skips) · lint 428 files exit 0.

## P27-2 · Cross-script search folding + transliteration display + language coloring  [tier: fable] [status: done 2026-07-18 — awaiting review; owner repro pins in tests; live rebuild is the review gate's]

Owner-approved; driven by two LIVE incidents (2026-07-18): (a) `search
'धर्मन्'` silently missed what `search dharman` found — while nabu's own
reflex render prints the Devanagari form beside a "nabu search --lemma"
hint; (b) `search vъsta` (3 hits, damaskini Latin-diplomatic) vs `search
въста` (20 hits, Cyrillic shelves) — one word, disjoint sets by script.

SHIPPED — Part 1, the cross-script FOLD (index-affecting):
- `Normalize::SCRIPT_NEUTRALIZATIONS`: per-language script neutralization
  BEFORE the generic fold, symmetric at index (search_form) and query
  (query_forms) time; each neutralizer is a with_map callable so
  fold_with_map composes maps and KWIC points a skeleton match back at
  the pristine Devanagari/Cyrillic span (map-correctness pins).
- san → Deva.to_iast (P26-2 transcoder PROMOTED from the SARIT adapter
  into the fold; idempotent on IAST shelves — DCS/GRETIL/MW refold to
  identical bytes). ORDER IS THE INCIDENT: the fold's \p{Mn} strip eats
  the virāma (क्त vs कत) — the transcode must run first. OWNER REPRO
  PINNED end-to-end: `search 'धर्मन्'` ≡ `search dharman` (union of the
  Devanagari and IAST shelves), and query_forms('धर्मन्') covers the DCS
  lemma form (the reflex-render → search --lemma round-trip contract).
- chu/orv/bul → `Nabu::Cyrl` (NEW), the census-built Cyrillic↔scholarly-
  Latin skeleton. bul included by census: 20 of damaskini's 23 witnesses
  are bul under the SAME diplomatic conventions (packet said chu/orv;
  without bul the vъsta pin fails on the majority shelf — deviation,
  argued). CENSUS (ingested damaskini conllu FORM/lemma columns vs
  torot/ud-orv/wiktionary-cu inventory; damaskini TSV layers censused
  but NOT ingested — evidence only): Latin side carries š ž č ě ę ź,
  x for х (xodinie, xva), literal jers ъ/ь, "št" for щ (šte), j-iotation
  (ljubovъ), "ou" for оу (oubi = оуби; upstream's OWN lemma column folds
  it to ubija), literal residues ѯ ѳ ћ џ ꙫ. THE WIDENINGS (ambiguity →
  one skeleton, never a guess, each with a fixture example):
  · щ ≡ шт ≡ "št" (šte / щедроты) — the digraph both spellings share.
  · оу ≡ у ≡ "ou" ≡ "u" (oubi/оуби; ꙋ ×111 ud-orv; ѹ) — a genuine o+u
    hiatus (по-учение → pučenie) conflates IDENTICALLY on both sides,
    so the fold stays symmetric. Note the bounded cross-language cost:
    an "ou"-bearing ASCII query gains a u-variant in the union (the
    þing→thing precedent).
  · iotated vowels → j-digraphs: ю→ju ꙗ/я→ja ѥ→je ѩ→ję ѭ→jǫ й→j
    (нашей → našej — scholarly j, where pre-P27-2 the breve strip gave и).
  · ѵ→v on damaskini's own evidence (Параскеѵи → its diplomatic
    Paraskevi); the izhitsa i-reading is context the fold cannot
    recover — journaled, not guessed.
  · letterforms by census: і/ї/ꙇ→i, ꙑ→y, ѡ/ѻ→o, ѿ→ot, ѕ/ꙃ→dz, ѯ→ks,
    ѱ→ps, є→e, ꙁ→z; unlisted precomposed Cyrillic decomposes so its
    base maps and its marks fall to the generic strip (torot ӑ).
  DELIBERATE NON-RULES (evidence said no): ѳ/ћ/џ/ꙫ stay literal — BOTH
  layers carry the characters, so identity already crosses the scripts,
  and ѳ→f vs ѳ→th would guess between readings; jers stay DISTINCT — the
  apostrophe-jer convention (kól'koto) lives only in the NON-ingested
  accented TSV column, ʼ/ʹ/ʺ censused ×0 in every ingested surface; х→x
  only (no h/ch widening — h is a real Latin letter in the corpus);
  Glagolitic UNREGISTERED (wiktionary-cu carries it only as headword
  variant forms → the script-miss hint, below). Wiktionary's ŭ/ĭ jer
  romanization stays covered by the dictionary shelves' dual
  word_folded/roman_folded keys, not by the fold.
- OWNER REPRO PINNED end-to-end: `search vъsta` ≡ `search въста` ≡ the
  union of the Latin-diplomatic and Cyrillic hits (query/search test).
- No silent script misses: `CLI::SCRIPT_MISS_HINTS` — a zero-hit search
  (text or --lemma) whose query carries Glagolitic (U+2C00–2C5F) or
  Gothic-script (U+10330–1034F) codepoints prints ONE hint naming what
  to try; ordinary misses and neutralized scripts stay silent (pins).
- CCMH DEVIATION (censused): the packet's "proiel/CCMH Cyrillic" premise
  is half-true — CCMH stores the Helsinki 7-bit ASCII transliteration
  verbatim (S=š as capitals, titlo as `!`), a THIRD convention that is
  case-significant and would need a parser-scoped decode (the P14-5
  search_source seam), NOT a language-keyed fold (capital S in other chu
  shelves is just S). Journaled as follow-up; the Cyrillic side of the
  incident is torot/ud-orv/wiktionary-cu, all covered. The fold DOES
  apply to CCMH text as-is (ASCII passes through; its one pinned
  text_normalized is byte-unchanged).
- RIPPLES, argued in-commit: folded-key pins across the dictionary/
  reflex chain update to the skeletons (богъ→bogъ …); reflex-walk test
  helpers now fold their lookup lemmas exactly as production readers do;
  etym's bare-form headword fallback is SUPPRESSED under an explicit
  --lang (the cross-script fold made Cyrillic spellings reach Latin
  proto headwords directly — the fallback would leak past the filter).
- CONSEQUENCE (stated, not executed): the fold change invalidates
  text_normalized for san/chu/orv/bul → ONE `nabu rebuild` (or
  per-source resyncs) refreshes the live fulltext index. NOT run here —
  the owner's live db is untouched (docs/display.md §1c + ops.md note).

SHIPPED — Part 2, `--display translit` (render-only, P27-0 registry):
- san→IAST (Deva), hbo/arc→SBL-style (NEW `Nabu::Hebr`), chu/orv/bul→
  scholarly Latin (Cyrl's display direction; damaskini's own Latin
  surface passes through byte-identical — render never rewrites the
  source's surface; оу→u is deterministic scholarly practice, applied).
- Hebr STYLE JOURNAL (census-scoped to the OSHB codepoint inventory;
  per-codepoint cluster reader, order-independent over the NFC-exempt
  Masoretic bytes): general-purpose SBL base + academic ʾ/ʿ/ḥ/ṭ/ś kept
  where general-purpose merges distinct letters; begadkefat splits only
  where audible (b/v, k/kh, p/f — dagesh decides); NO dagesh-forte
  doubling; every shewa → ə (vocal/silent not inferred); matres
  lectionis render as consonants (bəreʾshiyt, not bereshit) — a
  transcoder, not a vocalization engine; shuruq (ו+dagesh, no vowel)→u,
  holam male (ו+holam alone)→o; maqaf→"-", sof pasuq→".", paseq→"|";
  cantillation+meteg leave no residue. LTR Latin output → NO isolates
  (also the most legible Masoretic view on bidi-less Terminal.app).
- OGHAM VERDICT (censused): the transliteration is a line-aligned
  SIBLING DOCUMENT (…-translit, urn-suffix alignment; `show --parallel`
  inlines it today — one indexed lookup, cheap at the db). Wiring that
  lookup into the render seam would cross the render-only boundary (a
  mode sees text + language, never the store) → journaled follow-up
  (a show-level inline), documented pointer to --parallel instead of a
  hack. No pgl transcoder invented.
- Modes registered: translit + mono; --display desc + docs updated;
  footer vocabulary extended (transliterated / spacing / token colors —
  strips keep the exact P27-0 byte-pinned forms).

SHIPPED — Part 3, per-token language coloring:
- COLORING CENSUS (how token language rides annotations, per shelf):
  corph — annotations.tokens[].lang, mapped ISO (sga/lat/ang/non/grc)
  or lang_source verbatim when unmappable; oshb — tokens[].lang from
  the OSHM H/A morph prefix (hbo/arc; Jer 10:11 the live case);
  damaskini — NO token-level language: the chu/bul split is DOCUMENT
  grain (adapter DOCS map), CoNLL-U MISC is `_` on every token →
  damaskini renders uncolored, correctly (the packet's "damaskini
  (chu/bul)" expectation is document-grain reality — deviation, argued).
- `Display::TokenColors.paint`: tokens tagged with a language OTHER than
  the passage's own wrap in ANSI (stable palette, first-seen order);
  untagged/base-language tokens uncolored; unlocatable forms paint
  nothing (never a fabricated span); legend only for languages actually
  painted. Applied in `nabu show` (single-passage view — the one render
  with the tokens annotation at hand; Show::PassageResult now carries
  annotations, {} default). Gates: mode#colors? (mono/full → no),
  Display.color? (NO_COLOR any-non-empty always wins; NABU_COLOR forces;
  else TTY only — captured/piped output stays clean, pinned). Composes
  with snippet-bracket highlighting (ANSI is ASCII; pins) and with mark
  stripping (paint pristine forms first, strip regexes never touch
  escapes). Footer: `display: token colors: lat=cyan …`.

SHIPPED — Part 4, grapheme spacing:
- `spacing:` per-language display.yml key (validated boolean; full mode
  never spaces). RENDER JUDGMENT (journaled): Ogham letters are stroke
  clusters hanging on ONE shared stemline — abutting letters merge into
  unsegmented stroke runs in a monospace terminal, so spacing genuinely
  aids letter-by-letter reading; the separator between two Ogham letters
  is U+1680 OGHAM SPACE MARK, whose glyph IS a stemline segment — the
  line stays one continuous stem (an ASCII space would break it); plain
  space elsewhere; existing separators never doubled. DEFAULT-ON for pgl
  (Primitive Irish is attested ONLY in Ogham — the primary-subtag key is
  collision-free). RESIDUE (journaled): sga-Ogam and und ogham layers
  cannot be keyed per-language without spacing corph's Latin-script sga
  — follow-up would need script-scoped (not language-scoped) policies.
- orv/bul get deliberately EMPTY display.yml policies (a policy row is
  the translit reach-through; orv titla stripping was NOT part of the
  P27-0 owner gate and is not smuggled in).

Pins: search hits identical under every --display mode (P27-0 pin, now
covering translit/mono); `show --display full` byte-identity; MCP
pristine; export pristine under forced colors; fold/query symmetry
round-trip property over both scripts per neutralized language.

Tests +72 methods (cyrl 17, hebr 8, deva 2, normalize 9, display 19,
cli 13, search 2, lemma-search 2 — plus reworked folded-key pins across
8 files). Suite 3,490 runs / 45,970 assertions exit 0 (0 skips) · lint
432 files exit 0.

# ── Phase 28 ──────────────────────────────────────────────────────────

## P28-4 · `nabu list --sources` — the one-page grouped map of the library  [tier: fable] [status: done 2026-07-18 — mode + derived grouping + docs shipped; verdicts below] [deps: P24-0 (dossier descriptions), P22-1 (Query::List)]

Owner ask (2026-07-18, verbatim): "bin/nabu list --sources that gives a
one-liner DESCRIPTION of every source - possibly, grouped by
similarity/language groups? We need to give new user a one-page view of
what may be relevant for him. Essentially, a short CLI version of
site/sources."

SHIPPED — the mode:
- `nabu list --sources`: a fourth list mode beside
  --documents/--entries/--collections; composes with NOTHING (no SOURCE,
  no enumeration flag, no --long/--prefix/filters/--export flags — a
  named guard, first in validate_list_flags!). One line per catalog
  source under family headers: `slug — <first sentence of the dossier
  description>` (source_records kind=description, the P24-0 lane),
  truncated at 100 chars with an honest ellipsis (truncate_line, the
  --long census's own measure). Undescribed sources render the honest
  stub hint (`slug — no description; nabu ingest --shelf source SLUG`).
  Disabled sources stay VISIBLE with an `(off)` tag — a new user should
  see what exists — enablement read from the REGISTRY (the P23-3b
  authority ruling; the catalog flag only for registry orphans). One
  footer line points deeper (`nabu list SLUG for the full card ·
  docs/library.md for the survey`); NO counts on this view — the census
  is the numbers surface, descriptions are the payload here.

SHIPPED — grouping, fully derived (zero per-source curation debt):
1. `group:` front-matter lane in a SOURCE dossier — OWNER-ONLY, wins
   verbatim (a curated SourceDossier key: parsed/flattened to
   source_records kind=group/rendered/carried by with_section; the
   seed exporter, `ingest --shelf source` scaffold, and every other
   write path NEVER set it — pinned by test; the owner hand-edits the
   dossier and re-syncs local-source). CONTRACT journaled here: absent
   = derive; present = wins; unknown labels form their own group.
2. Local shelves (adapters LocalLanguage/LocalSource/LocalNotes/
   LocalLibrary — content grains :language/:source/:notes + the
   library) → "Your shelves".
3. Otherwise the source's languages (live census passages + dictionary
   languages) join the language dossiers' family lanes
   (language_records kind=family; hyphenated codes fall back to their
   prefix lane — the Languages#family_fallback rule) through a keyword
   net (Query::List::FAMILY_GROUPS — free-prose lanes like "South
   Slavic" / "Italic < Indo-European" keyed on family words, the
   specific ordered before the general so "Egyptian < Afro-Asiatic"
   never lands in the Semitic net): ONE family → that header; families
   SPANNED by a dictionary-owning source → "Reference & dictionaries"
   (single-family dictionaries stay in their family group); spanned on
   a passage shelf → the DOMINANT language's family (most live
   passages, ties by code); nothing derivable → honest "Other".

VERDICTS / journal:
- Header order is a FIXED curated constant (Query::List::GROUP_ORDER):
  Greek & Latin · Biblical & Near Eastern · Slavic · Celtic · Indic &
  Iranian · Egyptian & Coptic · Germanic & Old English · Reference &
  dictionaries · Your shelves · Other — pinned verbatim by test.
  Derived families the net does not know (e.g. an "Indo-European
  trunk" lane) mint their own header from the lane's first
  `<`-segment, trailing parenthetical stripped, and append SORTED
  before Other; groups with no sources are absent, not empty.
- Scope verdict: the map enumerates CATALOG sources (the `nabu list`
  census scope — descriptions and census languages live in the
  catalog); a registered-but-never-synced source appears at its first
  sync, exactly like the census.
- First-sentence heuristic: up to the first terminal punctuation
  followed by whitespace (whole prose when single-sentence);
  abbreviation-splitting accepted as the honest cheap rule — the
  ellipsis and the full card cover the residue.
- MCP verdict: NO change — nabu_status already serves each source's
  full dossier description; the grouped render is a human-onboarding
  surface first (extend serving only when an MCP consumer actually
  wants groups).

Tests +18: Query::List 10 (curated-order pin, family join, dominant
language, dictionary span vs single-family, local shelves, override
wins, unknown-label placement, hyphen fallback, line payload, ordered
assembly), SourceDossier 3 (group lane parse/flatten/round-trip,
absent-never-rendered, with_section carry), CLI 5 (grouped render with
truncation/stub/footer, (off) from the registry, composes-with-nothing
guards, help anchors). Suite 3,535 runs / 46,169 assertions exit 0 ·
lint 432 files exit 0.

## P28-2 · TLA official Hugging Face datasets — demotic + late Egyptian  [tier: fable] [status: done 2026-07-18 — adapter + `tla-jsonl` family + passage-grain date axis shipped, `enabled: false` awaiting the owner-fired first sync (~9.2 MB, two GETs); verdicts below] [deps: —]

The TLA's OFFICIAL Hugging Face org (`thesaurus-linguae-aegyptiae`):
`tla-demotic-v18-premium` (13,383 sentences — the only bulk demotic
artifact anywhere) + `tla-late_egyptian-v19-premium` (3,606 sentences,
with hieroglyphs). The FRESHNESS channel (corpus v18 2023 / v19 2024,
published 2024–2025) vs the frozen 2018 AES snapshot (02-sources row 15).

SHIPPED (2026-07-18):
- `Nabu::Adapters::TlaHf` + `Nabu::Adapters::TlaJsonlParser` (the
  `tla-jsonl` family: ONE reader shared by adapter and axis extractor so
  numbering/date parsing can never drift), registry `tla-hf`
  `enabled: false`, `sync_policy: manual`, `translations: true`.
- FETCH: FileFetch ×2 over the plain-HTTPS resolve URLs
  (`…/resolve/main/train.jsonl` — censused card file layout: README.md +
  train.jsonl per dataset, nothing else; the CDN 302 rides the shipped
  RedirectFollow; NO hf CLI, NO new gems), each dataset in its own
  subdir, the wiktionary-recon two-phase choreography (both prepare →
  breaker sees the combined doomed set → both complete). Probe :http_zip
  per resolve URL against the FileFetch state pins. Full artifact sizes
  for the owner's sync: demotic 7,284,199 B, late Egyptian 1,904,138 B
  (sha256s in test/fixtures/tla-hf/README.md).
- ONE-OR-TWO-SOURCES VERDICT: ONE source, two DATASETS rows (the
  starling-BASES / wiktionary-recon EXTRACTS configuration pattern) —
  same org, same JSONL shape modulo two optional fields, same license,
  same fetch machinery; two adapters would duplicate everything but a
  hash literal.
- FIELD CENSUS (full artifacts, 2026-07-18): shared `transliteration` /
  `lemmatization` (`<TLA lemma ID>|<lemma>` pairs — demotic `d`/`dm`
  prefixed 99,102+18,212 tokens, late bare numeric 24,437; 0 malformed) /
  `UPOS` / `glossing` / `translation` (German) /
  `dateNotBefore`+`dateNotAfter` (integer strings or empty); demotic-only
  `authors`; late-only `hieroglyphs` (Unicode v15 + `<g>JSesh</g>`
  fallback tags, kept verbatim in annotations). The four token fields
  split to IDENTICAL counts on every record of both corpora (censused 0
  misalignments → a mismatch is ParseError damage, never a shrug).
- IDENTITY VERDICT (journaled): upstream ships NO sentence/text ids —
  identity is the record's 1-based line number in the sha-pinned
  canonical file (urn:nabu:tla-hf:demotic-v18:207; the starling
  file-order precedent). Deterministic while the frozen artifact is
  unchanged; a changed upstream file is a new fetch and honestly
  re-mints. Fixture trims renumber accordingly (documented in the
  fixture README — provenance, not identity).
- LANGUAGE VERDICT (journaled): passages `egy` (ISO 639-3, both cards'
  own tag), translations `deu`. The cards' prose "egy-Egyd" /
  "egy-Egyp, egy-Egyh" are ISO 15924 SCRIPT subtags — and the stored
  surface is LATIN transliteration, so a script subtag would
  misdescribe what we hold. STAGE (Demotic / Late Egyptian) rides as a
  document facet (`stage`) — the damaskini Norm precedent; no invented
  subtags, journaled here.
- DATE AXIS: `Store::AxisBuilder::TlaHfDates` — the pre-cooked
  dateNotBefore/dateNotAfter signed integers (censused: historical
  years, no year 0, no inverted ranges; demotic -664..475, late
  -1539..-332) wired at PASSAGE grain (dates vary per sentence — the
  ChronicleAnnals shape): one document envelope row + one row per dated
  record (passage_seq_from/to = sequence), expected 16,281 rows at the
  first live rebuild (12,673 demotic + 3,606 late dated sentences + the
  2 document envelopes); 710
  undated demotic records skipped, counted, never guessed. Summary
  gains tla_hf/tla_hf_undated (defaulted — prior constructions stay
  valid); the rebuild CLI line prints the new source.
- LEMMA FLOW: expert-generated lemmatization → gold tier (the P26-0
  absent-is-gold contract); tokens carry form/lemma_id/lemma/upos/gloss,
  the lemma transliteration feeds passage_lemmas (e2e-tested), and
  lemma_id keeps the TLA lemma-ID join open for a future AED/AES shelf.
- NFC: 118 demotic + 9 late transliterations (and 13 demotic
  translations) ship decomposed h+U+0331 → NFC ẖ U+1E96 at the adapter
  boundary (egy is not NFC-exempt); pinned on a byte-verbatim fixture
  record.
- -de SIBLINGS: German translations as `-de` sibling documents (the
  damaskini -en pattern), suffix-aligned; Query::Parallel gains
  TLA_HF_DOCUMENT (-de tail anchor — no dataset slug ends in "-de",
  censused, frozen).
- Tests: conformance + adapter pins (32 runs) + axis extractor (5 runs)
  incl. idempotent double-load, the gold-lemma e2e, the date-axis pins
  and the extractor↔adapter mint drift pin. Fixtures byte-verbatim
  (lines 1/2/306/355 demotic — incl. the first non-NFC and first
  undated records — and 1/2/782 late), README with verbatim license
  quotes + full-artifact sha256s + sizes.
- Docs: 02-sources row 72; registry comments carry the freshness-channel
  framing.

## P28-0 · AES — the Egyptian corpus and gold-lemma mint  [tier: fable] [status: done 2026-07-18 — adapter + aes-json family + AesDates axis + -de siblings shipped; verdicts below]

The phase headliner: `github.com/simondschweitzer/aes` — the TLA/BBAW
January-2018 snapshot, 101,796 lemmatized sentences / 13,026 texts / 16
subcorpus JSON files (~342 MB). License VERBATIM in the repo README:
"All files: CC-BY-SA 4.0" → `attribution` (quoted in manifest + fixture
README + 02-sources row 70).

CENSUS VERDICTS (whole-corpus, at pinned commit 35276d25):

- **Grain**: sentences CONTIGUOUS per text in file order in all 16 files;
  a text never spans subcorpora; sentence ids globally unique;
  owner/date/findspot constant per text (0 conflicts). Document = the AED
  TEXT (`urn:nabu:aes:<subcorpus>:<AED-id>`), passage = the sentence on
  upstream's stable sentence id, sequence = file order.
- **Language codes**: the JSON carries NO language or stage tags (no such
  field in schema or data; the snapshot brands itself "Earlier Egyptian"
  yet spans OK–Roman) → uniform `egy` (ISO 639-2 Egyptian (Ancient)),
  stage subtags never invented.
- **Surface**: the Unicode TRANSLITERATION (written_form, space-joined) —
  the scholarly citation surface, the ORACC-translit precedent.
  Hieroglyphs (entity-decoded), MdC and Gardiner numbers ride the token
  annotations. JOURNALED (not wired): a `--display` hieroglyph mode over
  the token `hiero_unicode` layer — the P27 mode registry makes it a
  render-only follow-up, no re-parse.
- **THE TRAP, confirmed live and pinned with real fixture bytes**:
  `hiero_unicode` is HTML-entity-encoded (`&#x13099;`; all 241,414
  occurrences hex-numeric, zero literal hieroglyphs, zero entities in any
  other field) — decoded at the adapter boundary. Second boundary
  regression: 13,682 written forms carry deprecated U+2329/U+232A angle
  brackets → NFC-composed to U+3008/3009 by the standard boundary nfc
  (both pinned on offending bytes).
- **Token-less sentences**: 3 corpus-wide, never a whole text — no
  citable Egyptian surface → no original passage (their German still
  rides the sibling as a one-sided parallel row). Fixtured (the real
  NS6BAIQRENELJM2A2LDNHIYK6E).
- **Sibling verdict**: sentence_translation is the editor's German,
  100,633/101,796 = 98.9% coverage → the translations:true machinery FITS
  (the Damaskini shape): one `-de` sibling per text with ≥1 translated
  sentence (12,985 of 13,026), language `ger` (the Freising German tag),
  passages on the SAME sentence ids; Query::Parallel gained the AES work
  pattern (text ids are uppercase [A-Z0-9], none ends in "-de" — the
  literal-tail stance) → `show --parallel ger` renders verse pairs. Same
  CC BY-SA grant ("All files") — no license override.
- **Axis coverage**: date takes SIX values corpus-wide ("OK & FIP"
  ×36,326 / "NK" ×33,177 / "TIP - Roman times" ×16,426 / "MK & SIP"
  ×14,205 / "unknown" ×1,660 / degenerate "k" ×2 — both bbawarchive,
  fixtured); findspot 8 coarse regions. AxisBuilder::AesDates maps the
  four real periods to conventional Egyptological envelopes (Shaw 2000;
  the corpus's own thesaurus doi 10.5281/zenodo.3581069 defines the
  vocabulary, no absolute years) — OK&FIP [-2686,-2025], MK&SIP
  [-2055,-1550], NK [-1550,-1069], TIP-Roman [-1069,395] — place verbatim
  ("unknown" is not a place); unmapped values counted undated, never
  guessed. Projected: 12,893 dated + 14 place-only rows, 119 undated.
  Facets: subcorpus (16) / period (4) / findspot (7).
- **Fetch**: sparse GitFetch (P26-0 recipe) cone `files/aes` + root
  `README.md` — sparse IS warranted: the `files/relANNIS/` ANNIS
  re-export (~114 MB of zips, same data) stays outside the cone.
  Frozen snapshot (TLA at corpus v20) → sync_policy manual; the official
  TLA HF datasets are the freshness channel (P28-2's lane).

THE LEMMAID JOIN CONTRACT (P28-1 builds on this): every lemmatized token
annotation carries `lemma` = lemma_form (the shared treebank contract →
passage_lemmas, tier GOLD — TLA lemmatization is editor-verified; absent
from lemma_tiers = gold, the P26-0 contract) AND `lemma_id` = the AED
lemmaID VERBATIM ("123130" — the TLA lemma space, AED at
simondschweitzer.github.io/aed). P28-1's AED dictionary mints its entry
ids from the SAME space, so the join is EXACT STRING EQUALITY
lemma_id == entry_id — no folding, no transliteration round-trip, no
homograph heuristics. Token `_id` and `zaehler` deliberately not ingested
(zaehler = position we already keep; _id joins only the excluded relANNIS
export).

Projected first sync: 26,011 docs (13,026 texts + 12,985 -de) / 202,426
passages (101,793 translit + 100,633 German) / ≈779k gold egy lemma
tokens; ~342 MB cone on disk (git compresses JSON heavily on the wire).

Fixtures: byte-verbatim sentence-block slices of 3 real subcorpora
(tuebingerstelen: NK + findspot + `&#x13099;` + U+2329; bbawarchive: the
real "k" text + the token-less sentence; sawlit: an untranslated
sentence + lemma-less tokens) + aesschema.json whole; upstream commit
35276d2527cca1a055e31ed5f6683e777717170f pinned in README + manifest
(root README.md quoted, not fixtured — path collides with the house
fixture README).

Tests +34 methods (adapter 28 incl. conformance suite, entity-decode +
NFC-bracket regressions on real bytes, idempotent double-load, the
lemma-index e2e — LemmaSearch finds both attesting AES passages at tier
gold — parallel verse-pair pin, sparse local-git fetch; axis 6 incl. the
frozen-mint drift pin). Suite 3,551 runs / 46,843 assertions exit 0
(0 skips) · lint 436 files exit 0.

OWNER QUEUE: `bin/nabu sync aes` (sparse ~342 MB cone), eyeball
`nabu show urn:nabu:aes:tuebingerstelen:3F5KUVWQG5EPBM7GMQ6ZFVO5OQ
--parallel ger` + `nabu search --lemma ẖn.w` + 5 random passages + the
axis line (expect aes 12,907 dated/placed), then flip enabled.
## P28-1 · AED — the Egyptian dictionary shelf (define/etym for egy)  [tier: fable] [status: done 2026-07-18 — awaiting review; verdicts below]

Source: github `aed-tei` (the TLA/BBAW dictionary export),
`files/dictionary.xml` — 35,052 entries, 18 MB, TEI P5. In-file
`<availability>` verbatim: "Metadata and texts are released as Creative
Commons, Attribution-ShareAlike 4.0 (CC BY-SA 4.0)" → `attribution`,
quoted in the manifest. One authorized clone to scratch; fixture = a
byte-verbatim 31-entry slice + README (license quote, upstream sha
`462c722e0323e05641aea2eee8cdf1e27303d939`).

THE JOIN CONTRACT (the packet's point, as implemented): AED entry ids
are the upstream `xml:id` VERBATIM ("tla550034") — the TLA lemmaIDs the
AES corpus (P28-0, sibling in flight) mints as gold lemmas — so the
minted urn

    urn:nabu:dict:aed:<lemmaID>

is exactly what an AES annotation predicts. AES token references spell
the id in TEI prefix notation ("tla:550034", per the corpus's own
prefixDef); normalizing that to "tla550034" is the AES side's one
obligation. Test-pinned END-TO-END through the REAL DictionaryLoader:
the fixture loads, a hand-made AES-SHAPED lemma reference (honestly
labeled — P28-0's code is not merged) predicts the urn, and
Define#by_urn resolves it to the nfr adjective with gloss and license
intact. `define nfr` fans out the homograph cluster; ReflexViews
attested counts light when both shelves are live.

SHIPPED:
- `Nabu::Adapters::AedTeiParser` (new `aed-tei` family — TEI P5 default
  namespace, NOT the PersDict shape): Nokogiri Reader streaming
  (18 MB > the 5 MB DOM rule), per-entry strict mini-DOM +
  remove_namespaces!. Censused over all 35,052 entries: exactly one
  form/orth, one gramGrp/term, one sense, one bibl each — the parser
  raises ParseError on missing id/orth, honest to that census.
- `Nabu::Adapters::Aed`: content_kind :dictionary, slug `aed`, language
  `egy`, GitFetch with SPARSE CONE ["files/dictionary.xml", "README.md"]
  (the DCS recipe) — the repo's other ~55,000 files are AES text
  surfaces (651 MB working tree) that belong to P28-0's own source, not
  this shelf. Registry `enabled: false`, `sync_policy: manual`.
- conventions §9 `egy` fold: ꜣ→a (Ꜣ via downcase), ꜥ→a, ʾ (U+02BE, Lm)
  dropped — census-argued (ꜣ ×12,753, ꜥ ×6,451, ʾ ×1,036 are the ONLY
  letters the generic fold cannot reach); everything else measured to
  fall to the generic strip (ḥ ḫ ẖ š ṯ ḏ ṱ decompose; i̯/macron-below
  are Mn; yod is spelled j upstream — no rule; 〈〉 ×1 stays paste-only).
  `define nfr`, `define aa` (ꜥꜣ), `define hap-r` (ḥꜣp-rʾ), `aj.wj` all
  land from ASCII — test-pinned. Journaled: keyed by primary subtag so
  the two live papyri egy-Egyd Demotic documents refold at the next
  planned `nabu rebuild` (the §9 rebuild-storm caveat, NOT vacuous this
  time — flagged, trivial at 2 documents).

VERDICTS (censused from real data, per the packet):
- Wb page citations → dictionary_citations, the ZRC print-citation
  shape (the Hebrew-BDB deep-link pattern): label + urn_raw = the bibl
  segment VERBATIM, cts_work nil (⇒ Define resolves nothing — honest
  until a Wb local-library scan exists; JOURNALED SYNERGY: when a
  scanned Wb lands in the local library, `citation` already carries
  volume.page as the deep-link key). Segment rule /\AWb\s/ per
  ";"-split segment: 13,369 bibl-initial + 34 mid-bibl = 13,403 minted
  upstream; the "Wb 3. 293.2-6" dot-after-volume quirk (×32) parses
  too. Other print references (MedWb, KoptHWb, Meeks, GDG, LGG, FCD…)
  mint NO rows — they read verbatim in the body's bibl line.
- Root cross-refs → BODY CROSS-REFERENCE LINES, not reflex rows: the
  census killed the reflex option honestly — an xr ref is an EMPTY
  `<ref target="tla…"/>` carrying no surface form and no language, so
  a DictionaryReflex (word required) cannot be minted without
  fabrication. All eight censused types land as "type: id, id" lines
  verbatim (root ×13,470, rootOf ×3,254, partOf ×1,674, contains ×837,
  referencing ×82, referencedBy ×78, predecessor ×2, successor ×2),
  and every id resolves through the join contract (`nabu show
  urn:nabu:dict:aed:<id>`).
- Gloss lane = GERMAN (the file's complete lane: de on 35,053 cits =
  100% of entries, TLA's own curated Bedeutung; en covers only 16,971)
  — one language per shelf beats a mixed en-else-de lane; the English
  (and the two fr/it oddball) translations ride the body verbatim as
  their own labeled lines, searchable and rendered by define.
- Language `egy`: the file's own claims censused — the dictionary
  header carries no ISO tag (title "Ägyptische Wortliste"; the repo's
  text files say mainLang="Egyp", a non-ISO local code); `egy` is the
  ISO 639-2 code for Egyptian (Ancient), the shelf-level tag.

Tests +32 methods (aed-tei parser 17, aed adapter 14 incl. the
cross-shelf join pin, normalize egy fold 1 with 9 assertions, fixture
manifest rides the existing sweep). Registry census untouched
(enabled: false). Suite 3,549 runs / 46,353 assertions exit 0 (0
skips) · lint 436 files exit 0.

OWNER QUEUE: bin/nabu sync aed (sparse ~18 MB cone), eyeball
`nabu define nfr` / `define aa` / 5 random entries, flip enabled; next
`nabu rebuild` refolds the two egy-Egyd papyri documents under the new
fold.
## P28-3 · CCL — the Coptic dictionary + the egy↔cop diachronic bridge  [tier: fable] [status: done 2026-07-18 — adapter + `ccl-tei` family + `CclEtymologies` producer + fixtures shipped, `enabled: false` awaiting the owner-fired first sync; verdicts below] [deps: — (sibling contracts honored dangling: P28-1 aed urns, P28-2 demotic corpus)]

Two halves, one goal: the 3,000-year lemma chain (hieroglyphic → demotic
→ Coptic) as real links-journal edges against the live Coptic
Scriptorium shelf.

SHIPPED — Half 1, the CCL shelf:
- Source `ccl` (Comprehensive Coptic Lexicon v1.2, Refubium fub188/27813,
  11,284 entries, `content_kind :dictionary`, language cop, urns
  `urn:nabu:dict:ccl:<C-id>`). License verbatim BOTH layers: in-file
  `<licence>` "Licence for this TEI document: Creative Commons,
  Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)"; record page
  "Creative Commons: Namensnennung, Weitergabe unter gleichen
  Bedingungen" → `attribution`.
- SCHEMA VERDICT (censused from the full 12,343,129-byte artifact, never
  assumed): TEI P5 against the project's own Coptic_Lemma_Schema-v1.2.xsd
  — NOT PersDict, NOT TEI-Lex0 (`<entry xml:id="C<n>">`, no @key, 5,417
  body-level + 5,867 nested in 1,181 id-less `<superEntry>` groups;
  entries never nest in entries, so the Reader yields every entry once,
  flat). NEW small family `ccl-tei` (streaming Reader — 11.77 MB > the
  5 MB DOM rule — entry-at-a-time DOM; LexiconTeiParser's PATTERN, not
  its class). Headword = form[@type="lemma"]/orth; exactly ONE lemma-less
  entry corpus-wide (C11273) → first-orth fallback, pinned. Glosses
  multi-language confirmed (en ×15,889 / de ×8,911 / fr ×8,911): gloss =
  first EN quote, all three languages + dialect sigla (usg[@type="geo"])
  + gramGrp + etym + xr + print bibls linearized into the body. The
  bibls are print-dictionary strings (CD/CED/KoptHWb/DELC/ChLCS — zero
  CTS urns): NO citation rows from the TEI itself.
- FOLD VERDICT (reuse, never invent — the packet's order): the existing
  P17-1 `cop` fold (Normalize LANGUAGE_FOLDS: delete ⳿ U+2CFF + generic
  downcase/mark-strip) is what the Scriptorium shelf already searches;
  CCL headwords fold through the same `Normalize.search_form` with the
  LexiconTeiParser fold-key strip of morph `-` and `⸗` U+2E17 (×471
  orths) first. Orth census: Coptic block + shared-Greek Coptic letters
  (ϣϥϩϫϭϯϧ), supralinear strokes as combining FE24/FE25/FE26 + 0304/0305
  (all \p{Mn} → the generic strip handles them); zero orths fold empty.
- ATTESTED-COUNT VERDICT (census honestly, don't force): the
  lemmatization spaces JOIN — fixture census 319/418 distinct Scriptorium
  gold lemmas (76.3%) land on CCL headwords through the shared fold
  (misses: punctuation lemmas, "unknown", names, Greek loanwords); ⲕⲁϩ →
  C1494+C1495, pinned end-to-end (a real Encomium-of-Michael gold token
  lemma → folded lookup → both homograph entries). `define ⲕⲁϩ` ↔
  `search --lemma ⲕⲁϩ` round-trips by fold symmetry with ZERO new
  machinery; no attested-count column was forced onto define (CCL entries
  carry no reflexes — ReflexViews stays reconstruction-shelf machinery).
- Dictionary-mirror conformance + two-artifact WebMock fetch + loader
  idempotency + crosswalk-revision test + registry row `enabled: false`,
  `sync_policy: manual` (frozen 2020 deposit).

SHIPPED — Half 2, the ORAEC crosswalk edges:
- CENSUS (fetched, counted): **2,177 rows**, not the survey's 2,176 (no
  header row; recount deviation journaled); all width 3, C-ids unique,
  1,345 both / 350 hiero-only / 482 demotic-only, 220 NEGATIVE demotic
  word ids; **every crosswalk C-id exists in CCL v1.2** — the fact the
  packaging verdict rests on.
- PACKAGING VERDICT: config of the `ccl` adapter, not its own source —
  its only content is edges (no catalog grain of its own), and the
  full-coverage census means entry-riding loses nothing. The CSV is the
  adapter's SECOND FileFetch artifact (`crosswalk/` subdir, the
  wiktionary-recon two-phase choreography + two probe targets); at parse
  each matched entry carries its ancestor ids as DictionaryCitations
  (cts_work/citation nil — the links journal, not the CTS path, resolves
  them), content-sha'd so a crosswalk change honestly REVISES the entry
  (pinned). Missing crosswalk file = citation-less parse (day-one state),
  entries revise when it lands.
- EDGE-KIND VERDICT: NEW kind `etymology` (the journal's kind vocabulary
  is open — intertext-design §7 "{parallel, formula, cognate, …}").
  kind=reference asserts CITATION (manifests, DIL headwords, RIG
  concordance); a crosswalk row asserts diachronic DESCENT of one lemma —
  a different claim that must not blur into the citation render.
- `Nabu::CclEtymologies` — producer #6 on the P25-0 reference_producer
  seam (seam unchanged; a pure function of the catalog exactly like
  CorphDilReferences: reads the urn:nabu:dict:-targeted citation rows of
  the live entries, reruns supersede, rebuild never touches the journal).
  Edges: `urn:nabu:dict:ccl:<C-id>` → `urn:nabu:dict:aed:<id>` (the
  P28-1 sibling's stated contract, ids verbatim — dangling until that
  shelf merges, the established honest pattern) and →
  `urn:nabu:dict:tla-demotic:<id>` (ids VERBATIM incl. negatives;
  DELIBERATE forward edges into a stable external space, the dil.ie
  doctrine — NO bulk demotic lemma list exists anywhere per
  egyptian-survey §10 risk 6; thesaurus-linguae-aegyptiae.de/lemma/d<id>
  resolves every one, verified live incl. d-1427; if a future shelf keys
  the modern "d<id>" spelling, the prefix is a one-line change + rerun).
  Expected full-corpus yield 3,522 edges (1,695 aed + 1,827 demotic).
- CHAIN E2E (fixture-level, real bytes end to end): real adapter + real
  DictionaryLoader over the trimmed fixtures → producer → Query::Links
  on `urn:nabu:dict:ccl:C1494` shows BOTH ancestor edges of the
  survey-verified row (ⲕⲁϩ ← qꜣḥ 159410 ← qh 6439), out-direction,
  score nil, detail naming the headword.
- Query::Links grew the DICTIONARY-ENTRY resolution grain (own title +
  counterpart): an INGESTED shelf's dict urns resolve to "headword —
  dictionary title" + language + source license class — once the shelf
  is in the catalog, "(not in catalog)" would be dishonest; NOT-ingested
  dict urns (edil, aed until P28-1 merges) still render unresolved,
  honestly. Guarded for pre-shelf catalogs.

Fixtures: trimmed byte-verbatim TEI (full teiHeader incl. the licence +
17 entries across 6 blocks: the C1–C5 superEntry, C9–C10, C16 foreign,
C74, the C1494–C1500 ⲕⲁϩ cluster, lemma-less C11273) + 6 line-verbatim
crosswalk rows (hiero-only / entry-less C6 / dem-only / negative /
both×2); README carries both license quotes verbatim + full-artifact
shas; manifest.yml wired for the sentinel.

Tests +36 methods (parser 12, adapter 17, producer 6, links reader +1;
fixture manifests/sentinel ride the existing sweeps). Suite 3,553 runs /
46,327 assertions exit 0 (0 skips) · lint 438 files exit 0.

## P29-0 · OpenEtruscan + the Larth riders  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

The gate-approved P17-5 Phase B scope (owner 2026-07-13) + the two feeds
Larth's CC-BY LICENSE unlocked (thread closed 2026-07-14). Posture:
`attribution` throughout.

- **OpenEtruscan CSV adapter** — Zenodo record 20075836 v1.0.0
  (2026-05-07, cc-by-4.0; license_watch on the record; check for a v2
  deposit at build time and use the newest version). NEW **flat-csv
  parser family**. Skip `ocr_failed` rows by rule (discovery-skip
  accounting); `fuzzy_index: true`; BCE sign-flip regression pin (dates
  are BCE-positive upstream — flip to signed years, pin with a fixture
  row). Language `ett`. Carry the author's own data-quality caveat
  verbatim in 02-sources: "many inscriptions are really noisy and not
  really reliable".
- **kaikki `ett` EXTRACTS row** on the wiktionary-jsonl dictionary
  adapter (config + fixture only — the wiktionary-recon EXTRACTS
  precedent).
- **ETP_POS glossary via Larth** (`gh repo GianlucaVico/Larth-Etruscan-NLP`,
  LICENSE CC-BY-4.0 re-verified 2026-07-18): `ETP_POS.csv` (vocabulary,
  POS, translations — Wallace-project scholarly lineage) as a second
  Etruscan dictionary row. ETPWords/ETPNames/ETPSuff journaled, not
  ingested.
- **Larth findspot side-join**: `Data/Etruscan.csv` carries 456
  city-tagged rows OpenEtruscan dropped; side-join on the shared ids →
  `document_axes` place rows (EtruscanDates/places extractor as
  fits — no dates promised, places only).
- **Etruscan→Latin curated loan edges** (P17-3 `borrowed` pattern).
- **ett gold-join measurement** at fixture time; report the number,
  promise nothing.
- Registry `enabled: false`, sync_policy per artifact freshness
  (frozen Zenodo pin). Fixtures: trimmed real CSV rows incl. one
  ocr_failed skip + BCE pin; README with license quote + sha.

## P29-1 · CEIPoM — the pre-Roman-Italy corpus  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

Zenodo 6475427 v1.3 (Pitts, KU Leuven, 2022-04-21; concept DOI
10.5281/zenodo.4759134), license field `cc-by-sa-4.0` → `attribution`
(SA rider recorded). Five UTF-16 CSVs, 16.8 MB, FileFetch per CSV,
`sync_policy: frozen`. **UTF-16 (BOM) is a first for flat CSV — fixture
must pin it.** Flat-csv family sibling of P29-0 (different shape:
relational five-file; share helpers only if natural — orchestrator
reconciles at merge).

- Grain: document = text (3,875 in texts.csv), passage = sentence
  (5,303 in sentences.csv; sentence 2 = Fibula Praenestina "Manios med
  fhefhaked Numasioi", sentence 5 = Duenos — pin both). Languages:
  Latin 1,834 (variety Faliscan 420 → `xfa`; Faliscan/Latin 35;
  archaic Latin stays `lat`) · Oscan 902 `osc` · Messapic 591 `cms` ·
  Venetic 411 `xve` · Umbrian 68 `xum` · Old Sabellic 59 (South Picene
  → `spx`) · Greek 10 `grc`.
- **CeipomDates axis**: 3,872/3,875 dated (signed years, e.g. -675.0),
  3,815 lat/long → date AND place rows; honest undated/unplaced
  residues in the Summary (AxisBuilder pattern).
- **Script facet** from the per-text script column (Latin/Oscan/
  Messapic/Venetic/Greek/Etruscan/South Picene/Nocera + mixed).
- tokens.csv (dependency relations SBJ/OBJ/PRED + head pointers) +
  analysis.csv (lemma, morph, POS, gloss, meaning category,
  Classical_Latin_equivalent) → `annotations["tokens"]` + passage
  lemmas. **Lemma tier: gold WITH the single-scholar curation caveat
  verbatim in 02-sources** (owner-gated 2026-07-18); never call it
  "treebank-gold" in docs.
- **Classical_Latin_equivalent join measurement** against the gold
  Latin lemma keys — report the number, journal wiring as v2.
- links.csv: 3,630 TM ids → reference edges (Burman precedent);
  EDCS/CIL/"(Imagines Italicae)" reference strings carried verbatim.
- Fixture check: Iguvine Tables presence among the 68 Umbrian texts
  (tablet VII?) — report honestly.
- **Rider: kaikki Umbrian EXTRACTS row** (`xum`; the only served
  Italic language — 500 records, 373 with etymology_text, 30
  romanization stubs; 1.13 MB JSONL): config + fixture on
  wiktionary-jsonl.
- Registry `enabled: false`. New language dossiers accreted with
  `family:` lanes for osc/xum/xfa/xve/cms/spx (the P28-4r lesson).

## P29-2 · Corpus_ItAnt — the EpiDoc edition witness  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

github.com/DigItAnt/Corpus_ItAnt (CNR-ILC/UniFI PRIN 2017; cite Murano
et al., JOCCH 16.3 (2023), 10.1145/3606703). License verbatim README +
license.txt + per-file TEI availability: CC BY-NC-SA 4.0 → `nc`.
**Existing EpiDoc parser family + GitFetch** (riig precedent).

- `Oscan_inscriptions_newEditions` 502 files + `CelticOfItaly_…` 10
  (Lepontic → `lep`, xtg-adjacent; riig's neighbors). Venetic_/
  Faliscan_ dirs are README-only — journal the re-sync watch, promise
  nothing.
- EpiDoc 9.5, word-tokenized `<w xml:lang="osc-Ital-x-oscetr">` with
  ligature/direction markup, diplomatic + interpretative divs (keep
  both citable — the corpus's own structure decides the rung).
- Headers: Trismegistos ids + Imagines Italicae concordances ("ImIt
  Bouianum 104, 2") → reference edges; Getty AAT object/material →
  facets; GeoNames findspots → axis places; editors in metadata.
- Second-witness doctrine beside CEIPoM's Oscan (MW-beside-kaikki):
  deliberately unmerged, provenance-distinct.
- **Rider: Sabellic→Latin curated loan edges** (P17-3 `borrowed`
  pattern; en.wiktionary categoryinfo verified 2026-07-18: Latin ←
  Oscan 23 borrowed/48 derived, ← Umbrian 6/11, ← Sabine 13).
- **Rider: Old Italic display row** — display.yml + docs/display.md
  gain the U+10300 Old Italic note + `font-noto-sans-old-italic` cask
  beside the ogham/coptic entries (CEIPoM script column + ItAnt lang
  tags + kaikki-Umbrian headwords all land in this block).
- Lexicon_ItAnt (OntoLex-lemon TTL sibling): v2, journaled — first RDF
  dictionary-format decision deferred (owner-gated 2026-07-18).
- Registry `enabled: false`, sync_policy manual.

## P29-3 · LexLep + TIR — the Vienna wiki family  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

The ogham precedent: both wikis' own Project:Terms-of-Use pages grant
CC BY-SA 3.0 + GFDL (fetched verbatim via api.php 2026-07-18) while the
LexLep footer says BY-NC-SA and both preambles say "scientific use
only" → ingest at `nc`-conservative NOW; licensing email №17 (queued,
owner sends) relabels to attribution later via P10-4 override
mechanics. NEW **wiki-family parser** (MediaWiki api.php: page dumps
per category; the two sites share templates and machinery — ONE family,
TWO sources).

- **lexlep** (lexlep.univie.ac.at, Stifter/Salomon/Braun): Lepontic +
  Cisalpine Gaulish. Census verbatim: Inscription 628 · Word 202 ·
  Object 516 · Site 441 · Morpheme 42 · Character 1475 · Reference
  3544. Documents = inscriptions; the **202-word etymological lexicon
  → dictionary shelf row** (`lep`); sites/objects → axis places and
  facets as the data supports.
- **tir** (tir.univie.ac.at, Schumacher/Salomon/Kluge/Bajc/Braun):
  Raetic (`xrr`) corpus of record, actively updated. Census:
  Inscription 155 · Object 389 · Site 294 · Word 11 · Character 926.
- Respect the wikis: throttled fetches, sync_policy manual, cache
  pages under canonical (the fetch analogue conventions).
- Language dossiers for `lep`/`xrr` with family lanes (Celtic /
  unclassified-Tyrsenian? — record what scholarship says, honestly).
- Registry `enabled: false` both.

SHIPPED (2026-07-18, worktree; sha in worklog). CENSUS VERDICTS from the
design probe (api.php categoryinfo, ground truth): the brief's advertised
counts were LABEL-SHUFFLED — lexlep actual: Inscription 494 (+ subcat
Coin) · Word 628 · Object 419 · Site 134 · Morpheme 202 · Character 34 ·
Reference 1,475 (the brief's "628 inscriptions" is the Word category; the
lexicon is 628 words, not 202 — 202 is Morpheme); tir actual: Inscription
389 · Word 155 · Object 294 · Site 82 · Character 37 · Reference 926 (the
brief's "155 inscriptions" is the Word category). THREE registry rows,
not two: content_kind is one closed routing per adapter, so lexlep's two
grains are `lexlep` (:passages) + `lexlep-words` (:dictionary), beside
`tir` — the aes/aed precedent. Reading grammar deciphered against the
wiki's own HTML rendering: " / " line separator, "A!B" tokens (B = the
marked scholarly form = passage text; A = the Word-page link form →
passage "words" annotations), literal `space` = word divider, `unknown`
reading → metadata-only document (the ogham path). V2 JOURNALED:
tir-words (155 {{word}} pages, same parser — real content, e.g. aχvil ↔
Etr. acvil per Rix 1998), lexlep Morpheme pages (202),
Character/Reference categories, print sigla PID/IR/MLR/Mancini,
reading→Word-page edges (annotations already carry the link forms).
OWNER QUEUE:
- `bin/nabu sync lexlep` → eyeball `show urn:nabu:lexlep:bi-8` + 5
  random, flip; `bin/nabu sync lexlep-words` → `define --lang lep`
  eyeball, flip; `bin/nabu sync tir` → `show urn:nabu:tir:bz-10.1` + 5
  random, flip.
- Language dossiers once live: `nabu ingest --shelf language lep` (name
  Lepontic, family "Celtic < Indo-European"), `--shelf language xcg`
  (Cisalpine Gaulish, same lane), `--shelf language xrr` (name Raetic,
  family honest per scholarship: "Tyrsenian (with Etruscan and Lemnian;
  Rix 1998) — non-Indo-European", context from the TIR main page).
- Licensing email №17 (queued): on reply, relabel lexlep/lexlep-words/
  tir license_class in one commit (P10-4 mechanics, no urns change).

## P29-4 · I.Sicily — the epigraphy of ancient Sicily  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

github.com/ISicily/ISicily (Prag, Oxford; ERC Crossreads) — license
field CC-BY-4.0 (gh api, 2026-07-18), pushed 2026-07-18, Zenodo DOI
10.5281/zenodo.2556743. TEI EpiDoc, "the inscriptions of ancient
Sicily, across all languages". **Existing EpiDoc family + GitFetch.**

- ≥1,000 files by API cap (~4–5k expected) — census at fixture time
  and report the real language mix. Majority Greek/Latin
  (Hellenistic–Roman); the unique value: **Sicel `scx`, Elymian `xly`,
  Sicilian Punic, Mamertine Oscan** — their only machine-readable home.
- Overlap honesty: Latin items may intersect EDH Sicily — provenance-
  distinct witnesses (standing doctrine); census the intersection,
  promise nothing.
- Dating/findspot TEI headers → axis extractor if present (census
  first); I.Sicily ids + concordances → reference edges as the headers
  support.
- Language dossiers for scx/xly with honest family lanes.
- Registry `enabled: false`, sync_policy manual (live repo).

## P30-1 · hebrew-lexicon — define for augmented Strong's  [tier: fable] [status: done 2026-07-18 — adapter + `oshb-lexicon` family + fixtures shipped, `enabled: false` awaiting the owner-fired first sync; verdicts below] [deps: —]

SHIPPED (2026-07-18, worktree; sha in worklog). VERDICTS:
- SHELF GRAIN (censused at fixture time): ONE source, TWO dictionaries
  (the lexica LSJ+LS precedent) — `hebrew-lexicon` (one entry per
  AugIndex row, 9,299 upstream: id = the aug value VERBATIM incl. the 8
  non-numeric particle ids b/c/d/i/k/l/m/s; headword/xlit/pos/gloss from
  LexicalIndex via aug→LI (0 dangling), full Strong body from
  HebrewStrong (numeric bases, 0 missing; particles honestly have none),
  strong/aug/bdb/twot xrefs as body lines) + `bdb` (one entry per
  BrownDriverBriggs entry, 11,845 upstream; mod/type markers, head line,
  sense tree one line per <sense> with @n prefixes; <status> workflow
  values excluded from body). The two shelves meet at `define <hebrew
  word>` on the folded consonantal skeleton (pinned: ברא finds both).
- JOIN CONTRACT: `HebrewLexicon.normalize_lemma` ships on the adapter
  (final /-segment → strip spaces → strip trailing +); fixture-measured
  1,906/1,906 tokens = 100.000% (506/506 types) over the OSHB fixtures,
  live survey number 49,946/49,946 carried; the adapter test resolves
  EVERY real token lemma of Gen 1:1 + Gen 31:13 + Gen 31:47 + Jer 10:11
  (real OSHB fixture bytes) through the real DictionaryLoader +
  Define#by_urn.
- SPEC DRIFT, named: the spec's "BdbMedium.xml" does not exist upstream —
  the BDB outline file is BrownDriverBriggs.xml (survey had it right).
- NFC EXEMPTION EXTENDED (model change, the Passage P26-3 precedent):
  DictionaryEntry headword/gloss/body validate verbatim-UTF-8 for
  NFC-exempt languages (measured upstream: 4,053 LI / 3,796 HS / 4,720
  BDB headwords not NFC-stable — dagesh-before-vowel Masoretic order);
  headword_folded stays NFC for every language. architecture §3 updated.
- BDB print pages: <status p> (+ the ×2 mid-entry <page p> turns, one
  fixtured) → citation rows label "BDB p. NNN", cts_work nil, citation =
  the page — the aed Wb-pages pattern, resolution deferred to the BDB
  1906 scan (§7 one-liner). Scripture <ref> display text rides the body;
  the machine @r is deliberately NOT minted (P30-2's verse-keyed lane).
- ATTESTED-COUNTS MEASUREMENT (honest): gold hbo/arc lemma-index keys vs
  the shelf at fixture level — 944/1,906 (49.5%) equal a shelf entry id
  verbatim (bare-number lemmas); 962 (50.5%) need normalize_lemma at
  query time; the Define#glosses folded-headword handshake lights on 0
  (OSHB gold lemmas are ids, not Hebrew forms). A define-side aug-id
  lane (or index-side normalization) is the natural follow-up one-liner,
  NOT silently claimed.
- LANGUAGE HONESTY: dictionaries-table grain is one language per shelf →
  both register hbo (majority: 8,589/9,299 aug entries heb, 23/46 BDB
  parts); per-entry hbo/arc preserved on domain entries (28/15 in the
  fixture censused), folds identical; `define --lang arc` filters at
  dictionary grain — recorded in 02-sources row 83.
- Registry `enabled: false`, sync_policy manual, plain GitFetch (9.2 MB,
  no sparse cone needed). Fixtures byte-verbatim slices of all four
  files (43 aug rows = the COMPLETE normalized-lemma inventory of the
  four join verses; 43 LI + 41 HS + 19 BDB entries incl. Aramaic parts
  and the dagesh-first ברא), README with license quote + commit +
  full-file sha256 pins + the normalization rule.
- Tests +41 methods (model 3, parser 20 incl. damage paths, adapter 18
  incl. registry pin). Suite 3,991 runs / 50,709 assertions exit 0
  (0 skips) · lint 491 files exit 0.
- OWNER QUEUE: bin/nabu sync hebrew-lexicon, eyeball define ברא /
  define אלהים / show urn:nabu:dict:hebrew-lexicon:1254a + 5 random
  entries, flip enabled.

github.com/openscriptures/HebrewLexicon (the OSHB project's own lexicon,
9.2 MB, CC BY 4.0 → attribution). THE JOIN CONTRACT (survey-measured
live, 2026-07-18): entries keyed by augmented-Strong id — the exact ids
OSHB lemmas carry; 49,946/49,946 tokens (100.000%) joined across
Gen+Ruth+Dan+Jer INCL. Aramaic Daniel after ONE mechanical
normalization: OSHB lemma "b/1254 a" → strip prefix segments before the
final "/" → collapse internal space → "1254a". Zero dangling refs at any
hop of the AugIndex → LexicalIndex → BDB chain.

- Four XML files (own OSHB namespace — new small XML family):
  HebrewStrong.xml (Strong's entries, headwords, xlit, POS, full
  definitions), AugIndex.xml (augmented ids → Strong base), LexicalIndex
  .xml (id → BDB outline + gloss), BdbMedium.xml (the BDB outline with
  print-page anchors `<status p="NNN">`).
- content_kind :dictionary, TWO shelves or one? — census the natural
  grain at fixture time (Strong's entries + BDB outline could be one
  source, two dictionaries — the lexica LSJ+LS precedent). Language hbo
  + arc entries per the id space (H/A prefixes).
- `define` resolves an OSHB lemma id directly (the aed lemmaID→urn
  precedent: urn:nabu:dict:hebrew-lexicon:<id>); attested counts light
  via the existing gold hbo/arc lemma index — measure and report.
- BDB print-page anchors mint print-page citation rows (the aed Wb-pages
  pattern: label verbatim, cts_work nil, resolution deferred until the
  BDB 1906 scan lands in local-library — the §7 one-liner pairs with
  this packet).
- Registry enabled: false, sync_policy manual (GitFetch, small).
- Fixtures: byte-verbatim entry samples from all four files incl. an
  Aramaic entry and a `1254a`-style augmented id; README with license
  quote + shas + the normalization rule pinned.

## P30-2 · sdbh — the UBS semantic dictionary  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

UBS Semantic Dictionary of Biblical Hebrew via github.com/ubsicap/
ubs-open-license (CC BY-SA 4.0 → attribution; quote verbatim from the
repo). v0.9.2 at survey time: 7,932 entries / 16,220 definitions /
23,879 glosses / semantic domains / 260,813 verse-word-level scripture
references. `<StrongCodes>` in the same H/A number space as P30-1/OSHB.

- SAX/Reader family (the file is large); content_kind :dictionary,
  language hbo (+arc as tagged). Second shelf beside P30-1
  (MW-beside-kaikki, deliberately unmerged).
- Semantic domains → the entry body (and a facet-like lane if natural);
  scripture references → citation rows (verse-keyed — they resolve
  against oshb urns; measure the resolution rate, report honestly).
- HONESTY CARRIED: survey-measured token coverage vs OSHB is 78–80%;
  the misses include high-frequency function words (בֵּן, כִּי, עַל absent
  upstream v0.9.2) — record verbatim in 02-sources, never paper over.
- Registry enabled: false, sync_policy manual.

## P30-3 · sefaria — the Targum column  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

Sefaria-Export RESTRUCTURED upstream (2026 reality; old row 11 stale):
texts live in a public GCS bucket (~26 GB total — NOT fetched), the git
repo is a lightweight monthly index (books.json, 19,705 version entries
/ 6,456 titles). THE ONE-PHASE BITE: the Targum shelf — 46 titles / 200
files / 28.1 MB: Onkelos, Jonathan on all Prophets, the Writings
targums, Neofiti, Jerusalem, Sheni. Verse-aligned to the same Tanakh
versification → the ot alignment hub gains its ARAMAIC leg (five-legged:
MT ↔ LXX ↔ Vulgate ↔ English ↔ Targum).

- NEW fetch shape: index-driven named-file GETs (books.json → the Targum
  subset's per-version JSON files from the bucket). Scope discipline:
  ONLY the Targum shelf this phase; the index rides in canonical so the
  scope is reproducible.
- THE LICENSE GATE (per-version, machine-readable): each version JSON
  carries a "license" field — ingest named versions only, class per
  version (PD/CC-BY/CC-BY-SA → attribution or open; any CC-BY-NC
  version → nc with license_override per document); **merged.json files
  carry NO license field and are NEVER ingested** (pin this rule in a
  test).
- Schema-driven JSON family (Sefaria's own schema/section structure);
  language arc (Aramaic); document per title/version, passage per verse;
  hub wiring via the cts-verse refs (the oshb/vulgate precedent —
  eyeball `align "GEN 1.1"` shows the Targum column after sync).
- Registry enabled: false, sync_policy manual.

## P30-4 · text-fabric family + BHSA — the syntax axis  [tier: fable] [status: SHIPPED 2026-07-18 — worklog P30-4, sha TBD] [deps: —]

SHIPPED (packet result): family `Nabu::Adapters::TextFabric` (Feature +
Dataset; anchors/ranges/empty-value cursor/escapes/otype/oslots;
@edgeValues refused — untested support would be invented format) + adapter
`Nabu::Adapters::Bhsa`; every briefed census number verified exact against
otype.tf EXCEPT "64,514 sentences" = the sentence_ATOM count (sentences
proper 63,717; neither ingested — journaled). Spans contract published in
architecture §5 for the dss re-registration; qere shape pinned e2e against
the shipped P27 display policy on the SAME Ruth 1:8 K/Q instance oshb's
fixture pins. 02-sources row 83 (next-free at packet time — renumber on
merge collision), registry enabled: false/manual, ot+psalms hub witnesses
config-only. bridging journaled, not wired.

github.com/ETCBC/bhsa — license README verbatim: CC BY-NC 4.0, cite DOI
10.17026/dans-z6y-skyh; the GitHub MIT badge covers code only → class
nc, MCP-excluded (PROIEL discipline). Version PINNED: tf/2021 (sparse
GitFetch cone, 118 files ≈ 173 MB of the 1.6 GB repo).

- NEW `text-fabric` parser family in PLAIN RUBY (~150 lines, no new
  gems): each .tf = @key=value header block, blank line, then one value
  per line with line position encoding the node number (explicit
  node<TAB>value anchors allowed); otype.tf = range<TAB>type; oslots.tf
  = the edge file. Build the family for REUSE — P30-5 dss registers
  second (and peshitta/SP later).
- Census (verified): 426,590 words / 39 books / 929 chapters / 23,213
  verses / 88,131 clauses / 253,203 phrases / 64,514 sentences / 9,230
  lexemes. Document = book, passage = verse (OSIS-style refs from
  book+chapter+verse features → the ot hub via cts-verse, the oshb
  precedent). SECOND MT witness at a different grain — deliberately
  unmerged (MW-beside-kaikki).
- Features riding annotations: words + morphology + per-lexeme English
  gloss (gloss.tf) + freq_lex/freq_occ + language (H/A — cross-checks
  OSHM) + the ketiv-qere hybrid layer (kq_hybrid; the P27 qere display
  contract applies). NABU'S FIRST CONSTITUENCY DATA: clause/phrase spans
  as span annotations — write a SHORT design note in the packet (docs/
  architecture-worthy if it generalizes) BEFORE implementing.
- Sibling repo `bridging` (MIT — the OSHB↔BHSA word-level crosswalk):
  journaled, not wired.
- Registry enabled: false, sync_policy manual.

## P30-5 · dss — the Dead Sea Scrolls  [tier: fable] [status: STAGGERED — dispatch after P30-4 merges] [deps: P30-4 (text-fabric family)]

github.com/ETCBC/dss (206 MB, active). LICENSE: the expected Abegg/
Accordance encumbrance DISSOLVED — docs/about.md verbatim: "Martin
Abegg graciously gave permission to Jarod Jacobs to use his data and to
distribute the results under a CC-BY-NC license"; every .tf header
carries @license=CC BY-NC 4.0 machine-readable → nc, MCP-excluded.

- Second text-fabric registrant (the P30-4 family verbatim). Version
  pinned tf/2.0. Census: 1,430,241 signs / 500,995 words / 52,895 lines
  / 11,182 fragments / 1,001 scrolls / 10,450 lexemes; hbo + arc per
  word; biblical vs non-biblical feature → facet.
- Document = scroll, passage = fragment+line (the corpus's own citation
  grain: 1QS f1:3). Reconstructed/uncertain sign flags (cor/alt/
  brackets) ride annotations VERBATIM, never flattened — pin the policy
  with real fixture bytes.
- v2.0 ML-derived clause/phrase boundaries = SILVER (the goo300k
  discipline; label, never gold). Lexeme lane joins OSHB only via
  consonantal folding — measure at fixture time, report the honest
  number, promise nothing.
- Period/script metadata → date axis (the biggest Hebrew date-axis
  extension; census the feature shapes at fixture time, extractor if
  structured — the isicily discipline).
- Registry enabled: false, sync_policy manual.

## P30-6 · iip — Inscriptions of Israel/Palestine  [tier: fable] [status: dispatched 2026-07-18] [deps: —]

Brown University's IIP: 5,536 EpiDoc XML files, Hebrew/Aramaic/Greek/
Latin inscriptions ~500 BCE–640 CE, CC BY-NC 4.0 → nc, MCP-excluded.
EXISTING EpiDoc family + GitFetch (riig/isicily precedent — the cheap
real-corpus packet).

- CENSUS FIRST (the isicily discipline): real file count, language mix
  (@xml:lang histogram), dating/findspot header structure — axis
  extractor only if the headers carry structure; report what you found.
- Languages mapped honestly (heb/arc/grc/lat + whatever the census
  shows); mixed-language inscriptions per the isicily subtag policy.
- Concordances/ids in headers → reference edges as supported.
- Registry enabled: false, sync_policy manual.

## P31-0 · ORACC config expansion + UD Hittite  [tier: fable] [status: dispatched 2026-07-19] [deps: —]

Near-zero code (the survey's cheapest big win). FOUR new Oracc::PROJECTS
rows + ONE ud TREEBANKS row; the standing cdl guard applies (unknown
node ⇒ stop), per-project licenses machine-read at sync.

- **ario** — Achaemenid Royal Inscriptions online
  (oracc.museum.upenn.edu/json/ario.zip, 2.7 MB): the peo+elx+akk royal
  trilinguals; license CC0 VERBATIM in metadata.json (verify at fixture
  time). Old Persian (peo) and Elamite (elx) enter the library as
  config. Language dossiers for peo/elx with family lanes (Iranian <
  IE; Elamite isolate — honest lanes).
- **epsd2/literary** (39.5 MB) — the ETCSL literary corpus
  ORACC-lemmatized; **epsd2/royal**; **epsd2/earlylit**; AND
  **epsd2/admin-ur3** (561.8 MB zip — owner-approved 2026-07-19: IN).
  Expect the Ur III administrative mass to dominate counts; census
  honestly, quarantine loudly, never guess at unknown nodes.
- **UD_Hittite-HitTB** row in the ud TREEBANKS map: 136 sentences /
  1,309 tokens (Hoffner & Melchert examples with real KBo/KUB lines),
  LICENSE.txt verbatim CC BY-SA 4.0 → license_override attribution
  (P10-4 mechanics). Fixture per the ud sibling precedent.
- Fixtures: trimmed real zip members per project + the HitTB conllu
  slice; registry rows enabled: false where new source rows exist
  (ORACC projects ride the existing oracc source — flips n/a; document
  the expected sync deltas in the registry comment).

## P31-1 · TLHdig — the Hittite corpus  [tier: fable] [status: dispatched 2026-07-19] [deps: —]

Zenodo record 20328284, TLHbasisONLINE25_1_ZENODO_Beta_03.zip (74.4 MB,
published 2026-05-21, versioned DOI → sha-pin, ZipFetch). License:
Zenodo metadata cc-by-4.0 both versions → attribution; prescribed
citation VERBATIM in the manifest ("Thesaurus Linguarum Hethaeorum
digitalis, hethiter.net/: TLHdig – Beta Version 0.3 (2025-11-01)").
Census expectation (Beta 0.2 enumerated): 21,868 per-manuscript XML in
662 CTH folders; site claims >98% of published Hittite fragments.

- NEW **AOxml parser family** (hethiter.net/ns/AO/1.0 — NOT TEI):
  <lb> lines carry transliteration AND Unicode cuneiform (cu=); <w>
  elements carry CANDIDATE morphological analyses
  (mrp1="tarn=a-@lassen@1SG.PRS@II.3@" — lemma + German gloss + morph);
  Sumerogram/Akkadogram markers; damage brackets. PROBE REAL FILES
  FIRST; never invent the format.
- Multi-candidate analyses are upstream's own hypothesis layer → ride
  annotations verbatim; the lemma-tier verdict follows what the data
  honestly claims (multi-candidate ≠ gold — likely annotation-only or
  silver-labeled; census and report). THE SYNERGY PRIZE: the mrp lemmas
  should light the 323 starling-piet HITT reflex rows — measure the
  join at fixture level, report the number.
- CTH folder layout → facets (CTH number, genre bands if derivable).
  Language hit (+ embedded Sumerian/Akkadian graphies as annotations,
  never invented subtags). Surface = transliteration (the ORACC
  precedent); Unicode cuneiform rides annotations.
- Registry enabled: false, sync_policy manual (frozen versioned DOI).

## P31-2 · CDLI — the atf family and the universal catalog  [tier: fable] [status: dispatched 2026-07-19] [deps: —]

NEW **atf (C-ATF) parser family** + the cdli adapter. Fetch: GitFetch of
github.com/cdli-gh/data (LFS: cdli_cat.csv 154.8 MB + cdliatf_unblocked
.atf 86.9 MB — HEAD-verified live), honestly labeled the 2023-10
snapshot (the daily dump is dead; the cdli.earth API is the freshness
channel — journaled, not wired). LICENSE = bespoke open grant VERBATIM
in the manifest ("Text in the pages of CDLI may be freely copied,
aggregated and re-used … we request … that mention be made of the
source") → attribution; images entirely out of scope.

- C-ATF: &P-number document headers, #atf: lang lines, @obverse/@column
  structure, numbered lines, $ state lines, >>Q composite links. NO
  #lem lines → **silver tier** (lemma search stays ORACC-gold); the
  translit fold conventions (§9) carry over.
- **Catalog scope (owner-approved 2026-07-19): ALL artifacts** — every
  catalog row without ATF becomes a metadata-only document (ogham/
  isicily precedent at scale — expect ~200-300k at snapshot vintage);
  periods/proveniences/collections/rulers → date/place axes + facets.
  A CdliDates axis extractor over the catalog CSV (period → year
  envelopes where the catalog carries them; honest undated counts).
- P/Q-number urns (urn:nabu:cdli:p000725). ORACC ids ARE CDLI numbers →
  reference edges (producer cdli), NEVER deduped (provenance-distinct
  witnesses). Unique text mass: proto-cuneiform qpc + proto-Elamite
  (their only home), ED I-III, Old Akkadian, Old Assyrian; 43 catalog
  languages mapped honestly (unknown → und, never guessed).
- BUILD THE FAMILY FOR REUSE: P31-3 eBL registers an eBL-ATF dialect
  right after — keep CDLI policy out of the family core.
- Registry enabled: false, sync_policy manual. Fixtures: trimmed real
  ATF slices (incl. P000725 proto-cuneiform + a composite >>Q case) +
  catalog CSV rows; README with the grant verbatim + shas.

## P31-3 · eBL Fragmentarium  [tier: fable] [status: SHIPPED 2026-07-19 — worklog P31-3, sha TBD] [deps: P31-2 (atf family)]

Zenodo 10.5281/zenodo.10018951 snapshot (fragments.json 73.9 MB, 2023;
~25k tablets) as the bootstrap; the sanctioned
ebl.lmu.de/api/fragments/retrieve-all endpoint (37,296 fragments
live-verified) as the OWNER-FIRED refresh channel only (4-8 min/batch —
never automatic). LICENSE held at **nc** (JOHD data paper 10.5334/
johd.148 License section verbatim: CC BY-NC-SA 4.0 for fragments.json)
against the Zenodo field's cc-by-4.0 — record BOTH verbatim; email №24
may relabel to attribution (P10-4 mechanics).

- **eBL-ATF as a dialect of the P31-2 atf family** (their Lark grammar
  in ebl-api is the reference): #tr.en: inline English translations
  (→ -en siblings or inline annotations — decide from the real data
  shape, report), #note: apparatus, @i{...} markup, $ ruling lines.
- Fragment JSON carries museum-number id, script/period, joins, genre,
  externalNumbers: cdliNumber on ~96% → reference edges into the P31-2
  space (urn:nabu:cdli:p… — dangling-but-stable if cdli unsynced).
- The Corpus side (Gilgameš chapter editions) OUT: no packaged dump,
  the license covers fragments only — journal.
- Period metadata → axis extractor if structured (census first).
- Registry enabled: false, sync_policy manual. nc → MCP discipline.

## P31-4 · The Syriac & Ugaritic cluster  [tier: fable] [status: dispatched 2026-07-19] [deps: —]

Three sources; two ride the EXISTING text-fabric family (P30-4) as
registrants #3/#4 — zero family edits expected.

- **syriac-corpus** (github.com/srophe/syriac-corpus; CC BY 4.0 verbatim
  per-file <availability> + about page, base texts PD → attribution):
  632 TEI documents of classical Syriac literature. Small NEW
  srophe-TEI family (their own schema, NOT EpiDoc — probe real files).
  Language syc; document/passage grain per the TEI structure (census
  first). The survey's "lowest-friction big win".
- **cuc** — Copenhagen Ugaritic Corpus (github.com/DT-UCPH/cuc; nc
  verbatim in every .tf header): 279 tablets / 27,770 words / 146,017
  signs / 7,616 lines (otype ranges). Text-fabric registrant #3;
  language uga (NEW axis language — dossier with family lane
  "Northwest Semitic"). KTU concordances as metadata if carried.
- **peshitta** — ETCBC/peshitta OT incl. deuterocanon (nc verbatim in
  docs/about.md): text-fabric registrant #4; language syc. IF the
  features carry book/chapter/verse, wire the ot-hub witness column
  (the BHSA precedent — Peshitta joins the six-legged align); census
  first, report the verdict.
- SEDRA III journaled (research_private candidate), NOT in this phase.
- All registry rows enabled: false, sync_policy manual.

## P31-5 · ETCSL native  [tier: fable] [status: dispatched 2026-07-19] [deps: —]

The Oxford ETCSL TEI zip via OTA (4.68 MB; the server was FLAKY at
scout time — VERIFY the artifact first; if it stays unreachable,
report honestly and ship nothing rather than substitute). License CC
BY-NC-SA 3.0 → nc, MCP discipline. Value: the ENGLISH TRANSLATIONS +
the original ETCSL lemma layer as the second witness beside
epsd2/literary (P31-0) — MW-beside-kaikki, deliberately unmerged,
meeting at Q-number/ETCSL-number concordances (reference edges).
Registry enabled: false, sync_policy manual.

## P31-6 · UD Perseus treebank pair  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
Owner-added 2026-07-19 (anc.md check: the one cheap unclaimed open item —
"Perseus Ancient Greek and Latin Treebanks", 02-sources row 17's UD half).
The P31-0 HitTB shape exactly: TWO `UniversalDependencies::TREEBANKS`
config rows, no new code expected — `ancient-greek-perseus`
(UD_Ancient_Greek-Perseus, ~202k tokens: Homer, Hesiod, tragedy,
Herodotus per the AGLDT canon) + `latin-perseus` (UD_Latin-Perseus,
~29k tokens: Caesar, Cicero, Vergil, Ovid…). LICENSE GATE AT FIXTURE
TIME, never from memory: read each repo's LICENSE.txt + README metadata
verbatim; BY-SA → the P10-4 per-document attribution override
(birchbark/RNC/HitTB mechanics), BY-NC-SA → ride the source `nc` class
bare (the DipSGG posture). Whichever verdict, record it verbatim.
DEDUP HONESTY: these convert the NATIVE AGLDT treebanks (row 17), which
nabu has never synced — the chu-PROIEL re-export guard does NOT apply;
and no overlap with `greek-proiel`/`latin-ittb` (different upstream
data). vs perseus-greek/latin TEXT sources: same works at treebank
grain = distinct witnesses, never deduped (standing doctrine, the
DipSGG-beside-CorPH precedent). Languages grc/lat — both already
lemma-indexed; treebank lemmas join the existing gold lanes (measure a
sample join at fixture time, promise nothing). Fixtures: head-slice per
treebank (the HitTB recipe: real bytes, upstream sha256 pinned, README
date+URL+recipe); check the breaker-threshold test still balances at 12
treebanks (the P31-0 rebalance precedent — 2/12 = 16.7% must not trip).
Registry: NO enabled flip (`ud` is live; expected sync delta documented
in sources.yml comments — docs at UD's one-doc-per-treebank-split
grain). Docs: 02-sources row 4 (ud) + row 17 cross-note, worklog.

# Phase 32 — the Sino axis opens (approved 2026-07-19: all six packets; HDIC in P32-4; kaikki-zh in P32-3; Kanripo non-blocking → P33)

Source of truth: the owner-approved plan (orchestrator holds it); licenses
below were live-verified at scout time 2026-07-19 and MUST be re-read
verbatim at fixture time. Standing rules apply: TDD, real-byte fixtures,
license gates never from memory, enabled: false until owner flip, worklog
sha TBD for orchestrator fill, 02-sources row collisions renumbered at
merge (current max row: 96).

## P32-0 · UD Classical Chinese rows  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
`Ud::TREEBANKS` 12 → 14: **classical-chinese-kyoto**
(UD_Classical_Chinese-Kyoto — 86,239 sentences / 433,169 tokens / 9,641
lemmas; 論語/孟子/禮記/十八史略/楚辭/戰國策/唐詩三百首 + three sutras; v2.18
active) + **classical-chinese-tuecl** (100 sentences, test-only rider).
Language `lzh` both. LICENSE GATE: Kyoto LICENSE.txt verbatim CC BY-SA
4.0 vs README metadata `License: PD` — record the discrepancy,
LICENSE.txt authoritative (Ruthenian precedent) → P10-4 attribution
override; TueCL LICENSE.txt CC BY-SA (README agrees). The P31-0/P31-6
HitTB shape: config rows + real head-slice fixtures (sha256 + date +
recipe in test/fixtures/ud/README.md, manifest extended) + breaker-test
rebalance re-derived at 14 (never weakened). SCALE HONESTY: ~42 MB
conllu, ~86k sentences — this one treebank dwarfs the whole current ud
source; document the expected sync delta in sources.yml comments
loudly. UD_Old_Japanese-LMJ NOT taken (misnamed Heike/LMJ, master
branch empty — journal in the ud row, watch upstream). Docs: 02-sources
row 4 extension. Measure (promise nothing): sample join of Kyoto lemmas
vs any existing lzh keys (SuttaCentral lzh may land in the sibling
packet — no dep, just report).

## P32-1 · SuttaCentral lzh scope flip  [tier: fable] [status: SHIPPED 2026-07-19 — worklog P32-1, sha TBD] [deps: —]

SHIPPED (packet result): ROOT_TREES + "root/lzh/sct" → [lzh, sct] — one
config row, no machinery changes (siblings/publication-gate/segment grain
all pre-existed). 272 lzh roots + patton's 54 ma/sa -en siblings mint
(orphan census 179 → 125); lzh publications censused verbatim: scpub39
(roots) + scpub20/scpub35 (patton) all "Creative Commons Zero"/"CC0" →
no overrides. NB the spec's "synced sc-data tree" is bilara-data's own
_publication.json (sc-data is a separate, never-synced repo). SYNERGY
MEASURED against the scout's 2026-07-16 sc-data parallels snapshot:
237/8,221 relations pair minted pli/pra with minted lzh (223 parallels +
14 mentions; 129/272 lzh stems touched; ~110 more await unpublished da*
roots). Delta in sources.yml: +326 docs / ≈+42,676 passages via
--parse-only. Fixtures from canonical byte-verbatim (commit 84d9560);
02-sources row 66 updated (incl. truthing the stale READY→LIVE status).

ORIGINAL SPEC — ZERO FETCH: 272 root/lzh files already in
canonical/suttacentral/root/lzh/sct/ (MA/SA/EA/minor/abhidhamma),
skipped today by the adapter's own scope rule (lib/nabu/adapters/
suttacentral.rb:21), plus Charles Patton's English translations of lzh
roots among the "179 orphan en stems" (02-sources row 66). Widen the
scope rule: mint lzh root documents (+ paired -en siblings via the
standing sibling machinery), segment grain like the Pali shelf,
language lzh. License: census the lzh publication entries in the synced
sc-data tree at fixture time — per-file/publication license machinery
already exists; quote what the lzh publications actually declare.
Fixtures FROM CANONICAL (trimmed real files, README recipe; no
network). THE SYNERGY MEASURE (promise nothing): the sc-data parallels
graph (8,221 relations) — census how many pli↔lzh parallels RESOLVE
once lzh mints; report the number. Re-parse via --parse-only mechanics;
document the expected doc/passage delta in sources.yml comments. Docs:
02-sources row 66 update. NB the orphan-en census may include non-lzh
stems — only the lzh-paired ones mint; the census stays honest.

## P32-2 · ONCOJ — Old Japanese  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
The Japanese flagship: github.com/ONCOJ/data, GitFetch PINNED to the
"release" tag (2021-12-26 — the sanctioned periodic release; document
that the project site continues and re-pin is an owner decision).
4,991 texts — complete Man'yōshū (MYS 1–20), Kojiki kayō (KK), Nihon
Shoki kayō (NSK), Bussokuseki-ka (BS), Fudoki kayō (FK), Senmyō —
lemmatized + parsed (Frellesvig, Oxford-NINJAL). LICENSE verbatim
README §D: "The corpus annotation (the grammatical analysis) is
licensed under the Creative Commons Attribution 4.0 International
License." (texts 7th–8th c. PD) → attribution; the prescribed citation
format (§C) verbatim in the manifest. THE FORMAT DECISION at fixture
time: probe oncoj.csv (11.6 MB flat spine) vs xml/ (4,991 per-text
files, richer) — pick with reasons in the fixture README, never invent
structure. Document = text (urn:nabu:oncoj:<corpus-id>, upstream ids —
MYS.1.1 shapes); passage = the corpus's own unit; carry OJ romanization
AND man'yōgana (which is display text vs annotation = what the data
honestly distinguishes; a display.yml row only if the census supports
it). lexicon.xml (3.4 MB) = a dictionary-kind SIBLING shelf (one
source, two content kinds is NOT the house shape — register a second
source `oncoj-lexicon` sharing the fetch tree if needed; follow the
lexica precedent) → ojp joins the lemma-indexed languages; lemma links
from tokens into the lexicon censused and measured. NEW family (name it
honestly by what the format is). Docs: 02-sources row 97 claim
(renumber-on-merge note). Language dossier one-liner for ojp queued for
the owner (canonical/ unreachable from worktrees).

## P32-3 · The reconstruction shelf — baxter-sagart + tshet-uinh + kaikki-zh  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
Three lanes, one packet (all dictionary-machinery):
(1) **baxter-sagart**: the ~4,959-row TSV from
yawnoc/baxter-sagart-old-chinese (pushed 2026-07-11; zi/pinyin/MC/OC/
gloss/GSR/HYDZD/radical/strokes/Unicode) via FileFetch, sha-pinned.
LICENSE = THE PROVENANCE CHAIN, recorded verbatim in the manifest: the
original host's grant "are licensed under CC BY 4.0" (dead site;
wayback capture 2025-03-12 — quote + capture URL), content CC BY →
attribution to Baxter & Sagart 2014; the TSV repo itself is
license-less (the content license governs); the wayback xlsx
(BaxterSagartOC2015-10-13.xlsx) named as second witness, not fetched
unless cheap. Entries mint och (OC) + ltc (MC) lanes.
(2) **tshet-uinh**: nk2028/tshet-uinh-data, CC0 (GitHub license field —
verify in-repo too). 廣韻.csv with the 校本 correction-annotation syntax
(documented upstream — parse honestly, corrections as annotations not
silent fixes), 王一/王三, 韻鏡 ×2, fanqie tables. Census the file set
whole; grain = character × phonological position; ltc. zhongyuan-data
(中原音韻, CC0) as a second registrant IF the family fits — else
journaled with reasons.
(3) **wiktionary-zh** (OWNER-APPROVED disk call): the kaikki Chinese
extract (~1.1 GB JSONL) as a wiktionary-recon EXTRACTS row — the
existing wiktionary-jsonl family reads the shape; scout sample showed
per-entry Middle Chinese sound rows + BOTH Baxter-Sagart and Zhengzhang
OC. CENSUS the full file at fixture time (counts of MC/OC-bearing
entries); the extract is canonical-verbatim (never trimmed). Expected
sync ~1.1 GB download — document loudly. B-S-beside-kaikki =
MW-beside-kaikki, never deduped; Zhengzhang arrives ONLY via kaikki
(ytenx is blocked — the survey's license fork, note in docs).
Docs: 02-sources rows 98–99 claims + wiktionary-recon row 50 extension.
Dossier one-liners for och/ltc queued for the owner.

## P32-4 · The Sinoxenic character bridge — unihan + edrdg + hdic  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
Three dictionary-kind registrants (owner-approved incl. HDIC):
(1) **unihan**: Unihan.zip (8.5 MB, Last-Modified 2025-08-18) —
LICENSE = Unicode License V3, verbatim ("Permission is hereby granted,
free of charge … without restriction …") → open. Shelf keyed by
codepoint: kJapaneseOn/kJapaneseKun (the on'yomi strata — the bridge's
spine), kHanyuPinyin, kDefinition, variant fields (census which
k-fields are dense enough to carry; report the field census).
(2) **edrdg**: KANJIDIC2 (kanjidic2.xml.gz 1.49 MB) + JMdict
(JMdict_e.gz 10.5 MB) — EDRDG licence page verbatim: "The dictionary
files are made available under a Creative Commons Attribution-ShareAlike
Licence (V4.0)." → attribution. Upstream builds NIGHTLY → sync_policy
manual with Last-Modified pins (FileFetch mechanics); fixture = a
stable trimmed slice with the build date recorded. KANJIDIC2
on/kun/nanori readings; JMdict as the modern jpn gloss backstop.
(3) **hdic**: github.com/shikeda/HDIC (the ACTIVE upstream — pushed
2026-07-15; nk2028/HDIC is a stale 2022 mirror, do not fetch it).
README verbatim: "Creative Commons Attribution-ShareAlike 4.0
International License (CC BY-SA 4.0) … Open access" → attribution.
Heian-period hanzi dictionaries (Yuanben Yupian lanes sampled upstream;
census the actual file set/databases at fixture time — TBM/Shinsen
Jikyō presence is project-claimed, verify before promising). Entries =
the earliest Japanese lexicography, character-keyed.
JOIN MEASURE (promise nothing): Unihan↔KANJIDIC2 by codepoint,
HDIC↔Unihan where ids allow — censused percentages in the report.
Docs: 02-sources rows 100–102 claims (renumber-on-merge note).

## P32-5 · kaikki Old Japanese extract  [tier: fable] [status: dispatched 2026-07-19] [deps: —]
One wiktionary-recon EXTRACTS row: **wiktionary-ojp** (kaikki.org
Old Japanese extract, 1.2 MB, 532 entries / 390 with etymology_text /
178 citing the Man'yōshū — counted whole at scout time; re-census at
fixture). The P25-2 attested-language pattern verbatim (sga/mga/wlm
precedent): EXTRACTS row + registry pins + fixture slice + README.
Language ojp; joins the recon crosswalk beside ONCOJ's corpus
attestations (measure the folded-lemma overlap vs the ONCOJ lexicon IF
P32-2 has landed in your base — no dep otherwise, just report). Docs:
wiktionary-recon row 50 extension (NB P32-3 also extends row 50 —
sibling collision expected, orchestrator merges).

## P32-6 · SuttaCentral parallels graph  [tier: fable] [status: dispatched 2026-07-19] [deps: P32-1 merged (lzh minted)]
Owner-added rider 2026-07-19 ("add parallels graph as a rider", off the
live lzh tour). The sc-data parallels graph — journaled since P26-1
(02-sources row 66) — becomes reference edges. SOURCE OF TRUTH:
`misc/parallels.json` in the SEPARATE suttacentral/sc-data repo (the
bilara-data sync never touches it): 8,221 relation lists of sutta uids
(shapes: {"parallels": [...]}, {"mentions": [...]}; uid grammar
`uid#segment`, `~`-prefixed = resolved-by-inference — census the full
shape vocabulary before parsing, never invent). FETCH: FileFetch of the
raw file (sha-pinned; document the upstream commit) — do NOT clone
sc-data whole. EDGES: producer `suttacentral` via the standing
reference-edges machinery (Adapter.reference_edges? / LibraryReferences
with a custom producer — study the etcsl/cdli/riig producers first);
from_urn/to_urn = urn:nabu:suttacentral:<uid> document urns (segment
suffixes recorded in detail, not minted as passage targets — parallel
relations are document-grain upstream); relation kind (parallels vs
mentions vs resembling — whatever the census finds) rides the edge
detail; `~` inference flags preserved. HONESTY: most uids in the graph
are NOT in the catalog (unpublished da*, t* Taishō beyond the published
subset, vinaya…) — dangling-but-stable edges are the isicily tm:
precedent BUT since these ARE suttacentral's own id space, mint the
urn:nabu form anyway (they resolve the day upstream publishes; the 237
pli↔lzh measured pairs resolve TODAY). Census: how many edges have both
ends minted / one end / neither — the three-way count in the report and
the 02-sources row. The links surface (`nabu links <urn>`) then serves
the Kālāma Sutta ↔ MA 16 hop natively. Registry: this rides the
existing suttacentral source (no new source, no flip); sync_policy note
— the graph refresh is owner-fired with the ordinary sync. Fixtures:
a trimmed real parallels.json slice covering every censused shape.
Docs: 02-sources row 66 extension, worklog (sha TBD). Tests: producer +
loader idempotency + the an7.68↔ma1 edge pinned end-to-end.

# Phase 33 — the Sino axis, second phase: Kanripo + CBETA (approved 2026-07-20: all five packets; Kanripo first wave KR1+KR3+KR4; CBETA T+X; pacing = conservative defaults, owner-adjustable; KR6 = excluded this phase, doctrine call journaled)

Source of truth: `.docs/surveys/sino-survey.md` lanes SINO-D/E + the P32
outcomes. Standing rules apply (TDD, real-byte fixtures, licenses verbatim
at fixture time, enabled: false until owner flip, worklog sha TBD for
orchestrator fill, 02-sources rows renumbered at merge — current max 103
after P32; №25 Wittern is SENT and NON-BLOCKING).

## P33-0 · Kanripo — many-repo fetch + mandoku family, wave 1: KR1+KR3+KR4  [tier: fable] [status: dispatched 2026-07-20] [deps: —]
nabu's FIRST many-repo source (github.com/kanripo: 9,355 one-text repos).
DESIGN NOTE BEFORE CODE (the BHSA precedent) on the fetch: KR-Catalog
repo (org-mode catalogs, 3.4 MB) cloned as the discovery index; per-text
SHALLOW fetches of scoped texts only; polite sequential pacing with a
configurable delay (default conservative — document the knob; owner had
no constraint, design for resumability: an interrupted wave resumes
without refetching); per-text commit pins in a fetch ledger (sefaria
index-driven precedent, git-flavored). SCOPE = registry `classes:` list,
THIS WAVE **KR1 (classics) + KR3 (masters) + KR4 (belles-lettres)**
(owner-widened at the gate) — CENSUS SIZES FIRST from the catalog
(text counts + estimated bytes per class) and REPORT before any bulk
fetch; the Kyoto treebank's source texts (論語 = KR1h0004 …) fall in
this wave. NEW `mandoku` family: org-mode headers (#+TITLE, #+DATE,
#+PROPERTY ID/BASEEDITION/JUAN), `<pb:KRnXXXX_ed_NNN-Na>` page anchors →
citation grain text:juan:leaf-side(-line per the census), ¶ line marks,
** chapter headings; gaiji refs verbatim as annotations, NOT resolved
(KR-Gaiji journaled). Document = text urn:nabu:kanripo:<KR-id>; edition
choice per text (BASEEDITION vs multiple edition dirs — census the real
layout, never invent). LICENSE: the org-level grant verbatim
("Comprehensive collection of premodern Chinese texts. Licensed as CC
BY SA 4.0.") + ytenx corroboration + the №25-pending note → attribution.
KR6 EXCLUDED this phase (doctrine call journaled — CBETA is the
scholarly Buddhist shelf; a future witness wave stays possible). KR2/KR5
excluded from this wave (P33-1). Registry enabled: false, sync_policy
manual. Docs: 02-sources row 104 claim (renumber-on-merge note). lzh
dossier accretion queued for the owner.

## P33-1 · Kanripo wave 2 — KR2 histories (+ KR5 census)  [tier: fable] [status: staggered — dispatch after P33-0 merges] [deps: P33-0]
`classes:` config extension + censuses + fixtures for KR2's quirks
(dynastic-history volume structure — the 二十四史 may be the largest
single class; census text counts + bytes and REPORT, the owner decides
the sync moment per class). KR5 censused and REPORTED (in/out = owner
call at merge; no ingestion without the report). The dss-behind-bhsa
stagger: same family, second registrant wave.

## P33-2 · CBETA — Taishō + Xuzangjing  [tier: fable] [status: dispatched 2026-07-20] [deps: —]
cbeta-org/xml-p5 (1.2 GB, 29 canon dirs, active). SCOPE (owner-widened):
**T (Taishō vols 1–85) + X (Xuzangjing)**. NEW family `cbeta-tei`
(TEI P5 + cb: namespace: gaiji <g>, interlinear notes, witness
apparatus 【CB】【大】…; SAX/Reader per the >5 MB house rule — census file
sizes). Passage grain = the encoded Taishō/Xuzangjing
volume/page/register/line (census the lb/xml:id encoding on real files
FIRST). THE CANON-LEVEL LICENSE GATE (Sefaria precedent at canon
grain): Category A (T, X, …) = CC BY-NC-SA 4.0 verbatim from
cbeta.org/copyright + in-file availability headers → nc, MCP-excluded;
the named Category B exclusions (Y 印順法師佛學著作集, 呂澂, 太虛, 演培 …)
NEVER ingested — refuse by canon dir, test-pinned, the exclusion list
quoted verbatim. Fetch: GitFetch sparse cone [T/, X/, canons.json,
schema] if the layout allows (census; report the cone size). OVERLAP
HONESTY: SuttaCentral lzh Āgamas re-edit T sutras — provenance-distinct
witnesses, never deduped; Taishō-number reference edges measured at
fixture time, promised nothing. Registry enabled: false, sync_policy
manual. Docs: 02-sources row 105 claim.

## P33-3 · Kyoto↔Kanripo crosswalk  [tier: fable] [status: dispatched 2026-07-20] [deps: P33-0]
The UD Kyoto treebank names its source texts by Kanripo id (README +
Kyoto's ud-kanbun GitLab). Once P33-0 mints those texts: census the id
map first (how many Kyoto source ids fall inside the KR1/3/4 wave),
then reference edges via the P32-6 producer seam (study it; a small
dedicated producer or the ud adapter's — pick with reasons). Document-
grain edges treebank↔kanripo; measured coverage in the report. SMALL.

## P33-4 · TLS — Thesaurus Linguae Sericae  [tier: fable] [status: dispatched 2026-07-20] [deps: —]
tls-kr org: tls-texts + tls-data, BOTH LICENSE.md verbatim CC BY-SA 4.0.
A NEW shelf kind (onomasiological concept net: concepts → member words →
text attestations). Census the eXist-db XML layout WHOLE before shaping;
then a short DESIGN NOTE: how a concept shelf maps onto the dictionary
machinery (entries = concepts? words? both as linked shelves?) — OR an
honest deferral proposal with reasons (a valid packet outcome: ship the
census + design note + nothing else if the machinery genuinely doesn't
fit; the orchestrator/owner decide at merge). If shaped: registry
enabled: false, manual; docs row 106 claim. Trim-first candidate —
if your census says the fit is bad, say so early and cheaply.

# Phase 34 — the weave phase: journaled follow-ups & cross-source seams (approved 2026-07-20 as recommended: five packets; P34-0 seam = REGISTRY key; P34-3 tier = distinct "equivalence" label. D34-a KR5 ruling, owner 2026-07-20: keep for the next Sino phase — P34-5 does not dispatch this phase; the P33-1 census + overlay characterization stay the entry point when that phase elaborates)

Next-phase request (owner, 2026-07-20): group the grown source list
logically with user personas as a first-rate consideration — research
AXES as a registry dimension so `nabu list --axis` and
`nabu sync celtic`/`slavic`/… work naturally. Plan drafted
(orchestrator holds it: personas distilled, ~15-axis tag set + draft
79-slug mapping, `axes:` registry seam per the P34-0 `siblings:`
precedent, slug-collision validation, 4-packet sketch); elaborates
after the P34 gate per the loop. D35 RULINGS (owner, 2026-07-20, all
six landed — details in the orchestrator-held plan): axis set approved
+ `hebrew`/`syriac`/`hittite` added; cross-cutting axes IN with a
use-case brief (treebank/lexicon candidates, axis-scoped ops
follow-ups); "axis" = research axis everywhere and ALL date
nomenclature moves to "timeline" (new packet P35-4); dual-tagging over
folding (tlhdig = cuneiform+hittite); docs/axes.md public; `--all`
flat, `--axis NAME[,…]` selects and groups.

Second next-phase request (owner, 2026-07-20): Sinitic character
display — design note drafted (orchestrator-held): four workstreams —
East-Asian-width-aware column math (the cli.rb/concord.rb self-named
gap; P35 candidate), kanripo gaiji placeholder policy in display.yml
(cbeta needs no rule — upstream <g> fallback text already stored),
unihan-derived trad/simp/z-variant SEARCH fold for lzh (conventions §9
seam, semantic variants excluded; index re-derive consequence), CJK
fonts/ambiguous-width doc section (Noto CJK + Jigmo for Ext-B+).
Recommended split: width → P35; variant fold + gaiji config/docs +
KR-Gaiji resolution → the next Sino phase beside KR5 (D34-a).
Owner addendum (2026-07-20): variant-fold approach agreed (semantic
variants OUT of standard search) — AND a separate char-structure
search mode (components/radicals/strokes/visual similarity, à la
Jisho) is requested: own option set, survey of decomposition sources
first (cjkvi-ids/CHISE/BabelStone IDS/edrdg RADKFILE; unihan kRS*
fields = same held zip). Survey precedes the next Sino phase plan;
never silently mixed into text search. Presentation bar (owner
2026-07-20): match Jisho's kanji-page completeness field-for-field
where shelves back it (live 棄-page inventory in the orchestrator-held
note is the acceptance benchmark), exceed it on the historical axis
(OC reconstruction, Qieyun, hdic positions, TLS senses, classical
attestation) — sino/jap workflows designed to that bar.
Gate observation (2026-07-20, P34 runbook step 3): `show` has no view
of a passage's token annotations — eyeballing the new bhsa osm lane
took an export|grep pipeline. Journal: a `show --tokens` (raw stored
annotations, honest verbatim render) is a small QoL packet candidate
for P35's CLI pass.
№25 CLOSED (2026-07-20): Wittern confirms in writing — org-level CC
BY-SA 4.0 governs all KR text repos (registry comment upgraded). NEW
watch item from the same mail: "Bunkankun", his Kanripo successor;
catalog component at ask.bunkankun.org — next-Sino-phase survey
candidate (catalog/fetch seam). Reply draft in the thread log.
Gate observation ×2 (2026-07-20, runbook steps 7/8): the shared
inner-window pattern (limit×10 FTS candidates pre catalog filtering;
LemmaSearch INNER_LIMIT_FACTOR and Search alike) renders a bare "no
matches" when the window exhausts before the filters — matches EXIST
at higher limits. Journal: an honesty hint ("page may be incomplete —
raise --limit") when the inner window was exhausted with filters
active; P35 CLI-pass candidate beside show --tokens. Pre-existing,
bit twice at one gate.
P35 PACKET PAIR ADDED (owner-approved 2026-07-20): P35-5 assumption
inventory (mechanical sweep of era-bound literals/enumerations/silent
fallbacks into one census table; no behavior changes) + P35-6
recalibration & honesty invariants [deps: P35-5] (re-measure each site
against the live catalog; OK/HARDEN/GENERALIZE/RETIRE; the journaled
gate finds land here; residue = render-conformance suite, `# census:`
comment convention in the gate scan, gate-checklist re-diff line).
Process ratified into dev-loop §6b (recalibration after growth waves).
Full sketches in the orchestrator-held plan; elaborate after the P34
gate with the rest of P35.

Source of truth: the owner-approved plan (orchestrator holds it). Standing
rules apply (TDD, no behavioral drift without a pinned reason, worklog sha
TBD for orchestrator fill, 02-sources renumber at merge — current max 106).
ZERO new large syncs this phase: every packet ships capability over data
already held; the owner's ongoing Kanripo/CBETA syncs must be undisturbed
(no adapter/fetch changes to kanripo/cbeta outside P34-4's read-only census).

## P34-0 · --parallel work-pattern generalization + the I.Sicily siblings  [tier: fable] [status: done — merged ecc9b0f 2026-07-20] [deps: —]
The Query::Parallel work-pattern chain is ten hand-frozen regexes (CTS,
ORACC, FREISING, DAMASKINI, SUTTACENTRAL, TLA_HF, AES, RIIG,
OPEN_ETRUSCAN+ITANT, ETCSL) — it has bitten in P29, P30 AND P32 (every
new sibling shape = an owner repro + a rider). GENERALIZE, seam =
REGISTRY (owner-decided): a `siblings:` key on the source row declaring
the suffix grammar (e.g. `["-en"]`, `["-fr"]`, `["-(eng|ita|dipl)"]`,
or the CTS dotted-version form) → ONE generic matcher; study all ten
patterns first and write the design note (what each literal tail
encodes — version-token ordering, the CTS `.%` LIKE shape — before
unifying). MIGRATION DISCIPLINE: every existing source's parallel tests
pass UNCHANGED (behavior pinned exactly — zero drift); the ten regex
constants retire only when their registry declarations reproduce them
test-for-test. Then the journaled invisible siblings ride free:
**isicily -en/-it** (1,182 en / 389 it non-empty translation divs,
censused P29-4) and **-translit** (631 transliteration editions) —
sibling MINTING in the isicily adapter (study its metadata-only and
quarantine rules; the census numbers are the contract) + registry
declarations + corresp-style honesty where alignment is loose.
Docs: architecture §parallel note, 02-sources isicily row, worklog.

## P34-1 · The Masoretic word crosswalk — ETCBC/bridging  [tier: fable] [status: done] [deps: —]
ETCBC `bridging` repo (MIT — verify in-repo verbatim): the OSHB↔BHSA
word-level crosswalk, journaled at P30-4. Census the format WHOLE
(what grain, what coverage, which versions it pins — the repo maps
specific OSHB/BHSA releases; verify ours match, report honestly if
not). Design per what the data IS: word-grain reference edges vs a
crosswalk lane on annotations (say why). Payoff surfaces named in the
packet report with live examples: OSHB verse → its BHSA constituency
data. ALSO census (report-only) the DSS consonantal-fold lane vs OSHB
(the P30-5 "honestly partial" join) — numbers, no wiring unless clean.
Fetch: plain GitFetch, small. Registry: a links-journal producer or a
lane, NOT a text source (no enabled flip involved unless a real source
row is needed — justify either way). Docs + worklog per convention.

## P34-2 · Coptic loans facet + the Egyptian etymology chain  [tier: fable] [status: done 2026-07-20] [deps: —]
Ship the P17-1 promise: the per-passage loan-code counts already stored
in annotations become a readable facet (`--loans` on search/list — study
how existing facets read document_facets vs annotations; the design
said "a future --loans facet reads them without reparse" — honor that).
Plus the borrowing surface: find Coptic passages whose loan tokens come
from Greek (language-of-origin tags ride per-token since P17-1). Then
MEASURE the egy↔cop↔grc chain end-to-end via CCL's etymology edges
(P28-3) — a real tour exemplar in the report (a Pyramid-Texts word →
its Coptic descendant → its Greek loans neighborhood), promised
nothing, measured. CLI surface changes need tests at the CLI level
(the house cli_test patterns). Docs + worklog.

## P34-3 · CEIPoM Classical-Latin-equivalent lemma wiring  [tier: fable] [status: done 2026-07-20] [deps: —]
The P29-1 measured join (3,952 CLE values; 37.0% types / 79.9% tokens
vs live gold Latin keys) goes live: CLE values mint lemma-index rows as
LATIN keys on the non-Latin passages (Oscan/Umbrian/Faliscan/Venetic…),
under a DISTINCT tier label **"equivalence"** (owner-decided — silver
means upstream-automatic; this is scholar-curated cross-language
equivalence, a different honesty). Every surface that renders tiers
learns the label (search hits, --gold-only exclusion, ReflexViews if
touched — census the tier-consuming surfaces first and list them in
the design note). The single-scholar caveat rides verbatim. Measured
outcome in the report: `search --lemma quinque` surfacing the Iguvine
Tables, real output. Re-derive at rebuild — the lemma index is derived
data; no canonical changes. Docs + worklog.

## P34-4 · TLS attestation crosswalk  [tier: fable] [status: done 2026-07-20] [deps: none hard — censuses whatever Kanripo state exists]
The P33-4 deferred lane: 111,484 sense-level attributions (notes/doc
38,346 + notes/swl 73,138; 36,764 distinct senses, 99.6% resolvable
into tls-words). The attested texts are largely Kanripo-format ids —
CENSUS how many attested text ids match the owner's SYNCED kanripo
tree at packet time (read-only on /Users/vb/Dev/nabu/canonical/kanripo
if present — the owner's wave sync may still be running; census
whatever exists, report the resolution rate honestly, design for the
rate to grow as waves land). Mint dictionary_citations where targets
resolve to real passages (study how citations resolve — LSJ/MW
precedent) OR reference edges where only document grain resolves —
per what the seg-ids honestly support (they are TLS-side seg ids, not
page anchors: the mapping decision is the packet's design note; an
honest partial wiring beats a fake complete one). Fetch: the notes/
dirs join the tls sparse cone (~more MB — census and report). Docs +
worklog.

# Phase 35 — the atlas phase: personas, research axes, honest surfaces (elaborated 2026-07-20 post-P34 gate; all six D35 rulings in hand + the owner-approved audit pair + the Sinitic width workstream)

Source of truth: the owner-approved plan + rulings (orchestrator holds
it). D35 rulings binding throughout: axes = the research dimension
("axis" everywhere; ALL date nomenclature moves to "timeline");
18-axis tag set (the 15 distilled + hebrew/syriac/hittite); axes are
TAGS (multi-membership by design, dual-tagging over folding — tlhdig
= cuneiform+hittite); `--all` stays flat, `--axis NAME[,NAME…]`
selects AND groups; docs/axes.md is PUBLIC. Zero syncs, zero new
sources — this phase makes the registry's shape visible and the
surfaces honest.

## P35-0 · The axes registry seam + the ratified mapping  [tier: fable] [status: done 2026-07-20] [deps: —]
Goal: axis definitions block (name, persona one-liner, desc, order)
+ list-valued `axes:` key on EVERY source row, the owner-ratified
mapping (the plan's draft table + D35-a/D35-d amendments; re-verify
every row against its adapter manifest, not the table).
Acceptance: registry validation invariants test-pinned — every source
declares ≥1 axis; every declared axis exists in the definitions
block; axis names NEVER collide with source slugs (the resolution
guarantee); the design note argues axes.yml-vs-sources.yml placement.

## P35-1 · `nabu list --axis` + status grouping  [tier: opus] [status: done 2026-07-20] [deps: P35-0]
Goal: `list --axis` = grouped listing (axis header: name + persona
line; members with held counts; a source appears under each of its
axes, tag semantics stated once); `--axis slavic` one axis;
`--axis a,b` multi; unknown axis errors naming the known set;
`status --axis` rides along if it fits the layout.
Acceptance: house cli_test patterns; persona line renders; `--all`
surfaces unchanged.

## P35-2 · `nabu sync --axis` / bare-axis expansion  [tier: opus] [status: done] [deps: P35-0]
Goal: `sync celtic` resolves exact-slug-first-then-axis; expands to
the axis's ENABLED members; disabled members reported by name as
skipped (one line, never silent); `sync --axis a,b` selects+groups;
composes with --parse-only and every sync flag.
Acceptance: per-source report lines byte-unchanged (frozen contract —
grouping is pure expansion); resolution + skip-reporting test-pinned;
`sync --all` output stays flat.

## P35-3 · docs/axes.md — the public atlas page  [tier: opus] [status: done] [deps: P35-0, P35-1, P35-2]
Goal: the personas + axes + membership page, PUBLIC (D35-e), written
from the live registry (never hand-duplicated rows); languages.md
refresh rides the gate as usual.
Acceptance: page documents shipped behavior only; a registry-drift
check ties the page's axis list to the definitions block.

## P35-4 · The timeline nomenclature move  [tier: opus] [status: done 2026-07-20] [deps: —]
Goal: D35-c executed — date/place vocabulary becomes "timeline"
across docs prose, user-facing strings, and code names (DateAxis,
require_axis!, print_axis, AxisBuilder → timeline names); schema
stays put (derived-table rename only if the rebuild path regenerates
it anyway — argue in the design note).
Acceptance: zero output drift outside the renamed words themselves
(suite pins); docs grep-clean of the old sense ("axis" = research
axis only).

## P35-5 · The assumption inventory  [tier: opus] [status: done 2026-07-20] [deps: —]
Goal: dev-loop §6b pass 1 — harvest every era-bound-assumption site
in lib/ into ONE census table (file:line · literal/enumeration ·
stated justification or none · failure mode if false · growth axis
that kills it). Sweep classes: numeric literals in query/render/fetch
code; hand-enumerated lists over slugs/languages/shapes; every
.limit(/.first(/truncation; rescue-or-empty fallbacks; render paths
that can print "no X"; lazy resource initialization; confessing
comments ("fine for", "for now", "does not model", "today").
Acceptance: the table in the packet report (NO behavior changes) +
a `# census: <number>, <date>` comment-convention proposal for the
gate's conventions scan.

## P35-6 · Recalibration + the honesty invariants  [tier: fable] [status: done 2026-07-20] [deps: P35-5]
Goal: dev-loop §6b passes 2–3 — per inventoried site: blame the era,
RE-MEASURE against the live catalog, classify OK (document with
census+date) / HARDEN / GENERALIZE / RETIRE; the journaled gate finds
land here (show --tokens; the exhausted-inner-window "page may be
incomplete" hint; any remaining silent caps). Durable residue: the
render-conformance suite (every truncating surface announces what it
hid; every empty result under active filters explains itself), the
`# census:` convention wired into the gate scan, a phase-gate
checklist line re-diffing recorded census numbers.
Acceptance: HARDEN/GENERALIZE verdicts adjudicated by the owner at
the gate like decision items; suite green with the new conformance
suite enforced.

## P35-7 · East-Asian-width-aware rendering  [tier: opus] [status: done 2026-07-20] [deps: —]
Goal: the Sinitic display note's workstream A — one
Nabu::Display.width (grapheme × EAW class: W/F=2, isolates/ANSI=0)
used by every column-aligned surface (concord KWIC, align, show
card, status tables); ambiguous-width census over held lzh/ojp
passages recorded in display.md §2 (+ the iTerm2 ambiguous-width
toggle note); measurement not policy — no --display mode, no footer.
Acceptance: KWIC alignment pinned on real lzh fixture lines; the
cli.rb/concord.rb "does not model East-Asian width" confessions
retired; grc/lat/chu rendering byte-unchanged (suite pins).

Next-phase candidates (owner question 2026-07-20, rebuild duration): the
P36 REBUILD PAIR — (1) rebuild profiler: measure parse vs insert vs FTS
tokenize vs trigram vs timeline/facet/lemma builders on the live corpus
(§6b: numbers before optimization); (2) derivation stamps: per-source
input fingerprint (canonical tree sha + parser-family code digest +
fold-rules version + migration level) recorded at load; `rebuild
--incremental` skips fingerprint-clean sources with per-source FTS
delete+reinsert; full rebuild remains, incremental ≡ full pinned by
test. Ruling context: frozen/unchanged sources need NO re-derivation
IFF all four inputs are unchanged — bytes alone don't suffice (this
week's parser/fold churn is the counterexample). Bulk-load pragmas +
deferred index creation + parallel parse workers as riders per the
profile.

# Phase 36 — the engine phase: rebuild performance & deferred maintenance (approved 2026-07-20; rulings D36-a corpus-relative · D36-b silent confirmed · D36-c house line · D36-d hdic license GO, flipped)

Source of truth: the owner-approved plan (orchestrator holds it). Zero
syncs, zero new sources, zero canonical changes; nothing may disturb
the owner's ONGOING rebuild — fixture-corpus measurement + read-only
run history only, until the owner declares the reindex settled (it
reached kanripo, the tail source, as this was committed).

## P36-0 · The rebuild profiler  [tier: opus] [status: done 2026-07-20] [deps: —]
Per-source/per-stage timing (parse / insert / FTS tokenize / trigram /
timeline-facet-lemma builders / corpus-wide reindex): `rebuild
--profile` report + kept-on stage lines in normal progress. The
running rebuild can't be instrumented retroactively — recover coarse
numbers from run history/progress timestamps, say so honestly.
Acceptance: the hotspot table (numbers before optimization, §6b);
tiers the P36-2/P36-3 dispatch decisions.

## P36-1 · Derivation stamps + `rebuild --incremental`  [tier: fable] [status: done 2026-07-20] [deps: —]
Per-source fingerprint at load: canonical tree sha + parser-family
code digest + fold-rules version + migration level. `--incremental`
skips fingerprint-clean sources; dirty ones re-derive with per-source
FTS delete+reinsert. THE INVARIANT IS SACRED: full rebuild remains the
reference; test pins incremental ≡ full (counts + shas) on a fixture
corpus with one dirtied source.

## P36-2 · Bulk-load engineering  [tier: opus] [status: done 2026-07-20] [deps: P36-0]
Rebuild-only pragmas, per-source transactions, deferred secondary-index
creation — each measured against the P36-0 baseline; no un-measured
optimizations.

## P36-3 · Parallel parse workers  [tier: fable] [status: ready — P36-0 verdict: warranted, awaiting the parse/insert split from the next instrumented rebuild] [deps: P36-0]
N parsers, one writer behind a queue. If FTS reindex dominates, does
not dispatch; journal says why.
VERDICT (instrumented rebuild, 2026-07-21): parse 42m20s vs insert
119m58s of 164m22s load — the corpus is INSERT-bound, not parse-bound;
by the packet's own rule it does not dispatch. (Producer-consumer
overlap could at most hide the 42m under the 120m insert — journaled
as a future rider IF insert ever stops dominating.) The insert side is
the frontier: P37-7's design note + further bulk-load work.

## P36-4 · The aed etymology-edge reconcile  [tier: opus] [status: done 2026-07-20] [deps: —]
The P34-2 defect: 1,695 aed-side edges dangle (`dict:aed:159410`
producer vs `dict:aed:tla159410` shelf). Decide re-mint vs
resolution-normalize (study the canonical id space; links journal
supersede makes re-mint clean); acceptance = the egy↔cop tour resolves
end-to-end via `nabu links`/`etym`.

## P36-5 · Gate-docs refresh + the re-measures  [tier: opus] [status: done 2026-07-20] [deps: —]
languages.md + library.md live refresh; the three reindex-blocked
census stamps re-measured; D36-a corpus-relative df cutoffs implemented
in parallels.rb (measured before/after — the ruling's execution).

D36-e (journaled at the rebuild's isicily warning, classified 2026-07-20):
the +29 quarantine delta = P34-0 sibling docs of structurally-defective
upstream files (lb/@n, textpart/@n, urn mismatch, dup urns) meeting the
full canonical tree at first rebuild — working as designed, baseline
advanced, ~2,170/~2,200 siblings minted. Owner call: leave quarantined
(honest, recommended) vs teach sibling parse to tolerate missing lb @n
via synthesized anchors. Full classification in the orchestrator-held
baseline note.

# Phase 37 — the Sino phase: the largest shelf gets its instruments (approved 2026-07-20; rulings: all 8 packets + axis rider = 9 · fold ships NOW (owner schedules the lzh re-derive) · KR-Gaiji fetch PRE-APPROVED · axis ops ride as P37-8)

Source of truth: the owner-approved plan (orchestrator holds it). lzh
= 13.0M passages, the library's largest language. New data this phase:
KR5 (~84 MB, owner-fired) + KR-Gaiji (pre-approved, small). The
owner's overnight `rebuild --profile` may run concurrently — the hard
fence (no main-checkout db/canonical writes) binds every packet.

## P37-0 · Char-structure + Bunkankun survey  [tier: survey/network] [status: done 2026-07-20 — survey delivered, no repo diff by design] [deps: —]
`.docs/surveys/char-structure-survey.md`: decomposition-source
verdicts (cjkvi-ids license lineage/CHISE GPL; BabelStone IDS; edrdg
RADKFILE; nk2028 phonetic series) + ask.bunkankun.org (catalog shape,
license, fetch) + the Jisho 棄-page benchmark (display-note inventory).
Output: ratified source list + option grammar for P37-4.

## P37-1 · KR5 Daozang witness-overlay parser  [tier: fable] [status: done 2026-07-20] [deps: —]
Per the P33-1 characterization: overlay repos need `<md:>` milestones
+ witness-scheme pb anchors + @fw running headers. Overlay extension
(loud on anything new), KR5 joins `classes:`, censuses + fixtures per
the P33-1 pattern. Owner-fired ~84 MB sync at the gate.

## P37-2 · The lzh variant fold  [tier: fable] [status: done] [deps: —]
Trad↔simp↔z-variant fold derived from HELD unihan (semantic variants
OUT); lzh (+och headwords); canonical form = traditional; conventions
§9 entry; census of participating held codepoints. RULED: ships now;
the fold-version bump dirties lzh sources and the owner schedules the
~13M-passage re-derive.

## P37-3 · Gaiji: placeholder + KR-Gaiji resolution  [tier: opus] [status: done 2026-07-20] [deps: —]
display.yml `kanripo: { gaiji: placeholder }` (⬚ + honesty footer;
cbeta = documented non-entry). KR-Gaiji fetch PRE-APPROVED (owner
ruling): registry row + sanctioned fetch config + refs→Unicode/IDS
mapping where upstream provides; poor mapping ⇒ placeholder-only +
journal.

## P37-4 · `nabu char` + component search  [tier: opus] [status: done 2026-07-20 — BabelStone IDS + KRADFILE acquired (enabled:false), Unihan kRS* + KANJIDIC2 desk-code expansion, `nabu char` card, `search --radical/--strokes/--char-component`] [deps: P37-0]
The Jisho bar: char card (radical+name, strokes, components, variants,
readings incl. Mandarin/Korean, OC/Qieyun/HDIC/TLS diachronic column,
corpus attestation) + explicit modes (--radical/--strokes/
--char-component); unihan kRS* field expansion; CJK fonts doc rides.
Match synchronic field-for-field where shelves back it, exceed
diachronically, never render an unbacked field.

## P37-5 · TLS attestation growth re-census  [tier: opus] [status: done 2026-07-21] [deps: —]
Wave complete: re-census KR-shaped ann resolution vs the 80.3%
dispatch-day rate; tls re-parse re-mints citations; report new rate +
the define surface. Rider-sized.

## P37-6 · Parallel parse workers  [tier: fable] [status: NO-GO 2026-07-21 — profile verdict: INSERT-bound] [deps: profile]
The P36-3 carryover: dispatch ONLY on a parse-bound split from the
owner's instrumented rebuild. NO-GO ⇒ journaled why.

## P37-7 · External-content FTS5 design note  [tier: fable, DESIGN ONLY] [status: done] [deps: —]
The 16-minute target: fixture-scale prototype + what-breaks note
(refresh_source! delete contract, query paths); NO production switch.
PROFILE CONTEXT (2026-07-21): corpus index total 11m30s (fts+lemma
9m09s fused · trigram 18.9s · reflex 10.7s · alignment 2.6s) — already
−40% vs the pre-P36-2 16m16s; the note's real target is now ALSO the
insert side (fulltext double text storage, 12 GB) and the 120m
catalog insert.

MEGA-SOURCE LOAD REGRESSION (found in the same profile — investigation
journaled, owner-visible): sources with MANY passages per document got
SLOWER vs the pre-P36 baseline at identical doc counts — kanripo
17m47s→61m13s wall (×3.4), cbeta 21m48s→35m51s (×1.6), diorisis
5m16s→11m09s (×2.1), ud 34s→1m46s (×3) — while many-docs-few-passages
sources got FASTER (cdli −30%, edh −40%, papyri/aes/mw/lexica all
faster) and the corpus reindex −40%. Prime suspect: the P36-2 stack
(batch grain or a deferred index a per-passage path needs) interacting
with mega-documents — exactly the fixture-scale blind spot P36-2's
report flagged. Needs a one-source bisect at live scale (kanripo,
toggling pragmas/batch/deferred-index) BEFORE any further bulk-load
work; net grand total still ≈3h (175m52s) vs the 2h35m-ish prior, so
this regression more than ate the fixture-projected wins on the lzh
giants. Rides P37-7's owner or its own rider — orchestrator call at
dispatch.

## P37-8 · Axis-scoped operations  [tier: opus] [status: done] [deps: —]
The D35-b follow-ups ride (owner-ruled): `search --axis` (membership
filter composing with every search path), `export --axis`, the
`nabu axis NAME` desk card (persona, members, held counts, gold
coverage — the `nabu language` mold). health --axis only if it fits
cleanly; journal otherwise.

## P37-9 · Per-axis site pages — /axis/<name>/  [tier: opus] [status: done 2026-07-21] [deps: —] [owner-requested at the P37 gate]
Owner ask (2026-07-21, verbatim intent): second-layer site pages, one
per research axis (nabu/axis/celtic …), each carrying ALL relevant
usability context FOR THAT axis. Ship: site/axis/<name>.md × 18
(Jekyll, permalink /axis/<name>/), GENERATED from the live registry +
per-axis curated context — persona + desc verbatim, member table
(source, holdings kind, license class, sync status), the desk's
gold-lemma/dictionary/alignment coverage, axis-specific CLI recipes
(list/sync/search/export --axis, nabu axis card, plus the axis's OWN
surfaces: char/variant-fold for sinitic, --loans for egyptian, MT/DSS
alignment for hebrew, timeline/facets for epigraphy…), and the
axis-relevant terminal/display setup (RTL+fonts for hebrew/syriac, CJK
fonts/width for sinitic/japonic, Ogham spacing for celtic — mined from
docs/display.md). An /axis/ index page + site nav link. Generator =
committed script (rake task) reading config/axes.yml + sources.yml +
docs sources; pages committed (the static-site discipline); drift
check in the suite pinning the 18 pages' member lists to the registry
(the docs/axes.md precedent). Curated prose lives in a per-axis
fragments file the generator merges — hand-edited, never overwritten.

## D37 rulings (owner, 2026-07-21, post-gate)
- D37-a (gaiji substitute lane): SUPERSEDED by the display-ladder
  ruling — per-character ladder: real codepoint → IDS composition →
  MARKED substitute (never silent) → ⬚ + counted footer as true last
  resort; plus the CJK font-install note in docs/display.md.
  Implementation = P38-1/P38-2 (plan: .docs/p38-japanese-plan.md).
- D37-b (contentless FTS5 implementation): DEFERRED — "index rework
  we can do other time." Stays journaled as a future-phase candidate
  with the P37-7 design note as its spec.
- P38 direction (owner): the Japanese phase — Aozora Bunko + the
  gaiji display ladder as the phase essence.

# Phase 38 — the Japanese phase: Aozora Bunko + the gaiji display ladder (approved 2026-07-21: all five packets; D38-a Aozora scope ruled post-survey)

Source of truth: .docs/p38-japanese-plan.md (orchestrator holds it).
Ground truth censused 2026-07-21 from held canonical/kr-gaiji
charlist: 5,254 refs — 982 direct glyph (shipped 972), 707
substitute-only, 1 composition, 3,564 image-only tail. Ladder target:
faithful+marked-substitute ≈ ~88% of occurrences visible (vs 36%
faithful today). Hard fence binds every packet: no main-checkout
db/ or canonical/ writes; canonical reads via absolute path only.

## P38-0 · Aozora Bunko survey  [tier: survey/network] [status: done 2026-07-21 — survey delivered (.docs/surveys/aozora-survey.md), no repo diff by design] [deps: —]
FINDINGS: 17,831 works / 17,676 with text / text = Shift_JIS(CP932)
zips inside a 22.8 GB repo of which text is only ~210 MB zipped
(~0.7 GB raw). License: 17,343 PD (作品著作権フラグ=なし) vs 488
in-copyright (354 with text) — per-work flag in the 55-column index
CSV, which also carries orthography class, 底本 colophon, and
per-file URLs+encodings. Gaiji: 3 classes — JIS X 0213 kuten
(mechanical→Unicode), explicit U+XXXX (direct), component-description
only (→ IDS lane / sentinel). Fetch: sparse partial clone
(--filter=blob:none + sparse-checkout on cards/*/files/*_{ruby,txt}_*.zip
+ index) through GitFetch — needs a GitFetch sparse capability
(P38-3 seam); canonical = the zips, adapter unzips on read.
Orthography census: 10,956 新字新仮名 · 4,569 新字旧仮名 · 2,184
旧字旧仮名 · 101 旧字新仮名 · 21 その他 (incl. kanbun); classical
tail thin and mostly modern critical editions (Kojiki = Takeda 校註).
Survey rec for D38-a: PD-text-only (~17.5k works, single license
class); in-copyright 488 deferred to per-work opt-in.
Upstream shape (aozorabunko GitHub mirror: size, layout, index CSV —
NO full clone; API/raw reads only), per-work license census (PD vs
CC), the Aozora format spec (ruby grammar; gaiji notation classes:
JIS X 0213 refs / component descriptions / image-only), fetch
strategy + volume, scope options. Feeds D38-a + the P38-3 parser
spec. Delivered via report (survey doc is orchestrator-held).

## P38-1 · Gaiji ladder tables  [tier: opus] [status: done 2026-07-21 — merged e3dc9d7; HEADLINE: 547 PUA rows purged from the shipped faithful table (P37-3 bug, independently verified); lanes 427 faithful / 562 substitute / 0 IDS (kanripo); occurrence coverage 36.55% + 45.25% = 81.80%, ⬚ 18.20%; owner glance at gate — display changes for 547 refs, strictly more honest] [deps: —]
From held charlist: reconcile 982 direct-glyph refs vs shipped 972
(`?`-uncertainty policy stated in table header); substitute table
(707 refs) as its OWN config/gaiji/ lane, never merged with faithful;
the lone composition → IDS; verify faithful codepoints against held
Unihan; occurrence-weighted coverage report before/after (col 2 =
occurrence counts), census-stamped per §6b. Acceptance: tables +
counts, suite green.

## P38-2 · The display ladder  [tier: opus] [status: done 2026-07-21 — merged 17bb70b; `gaiji: ladder` shipped as kanripo policy; substitute mark ⌈…⌉ (U+2308/09, collision-surveyed); placeholder mode preserved as config; suite 5,079 green] [deps: P38-1]
Reading-mode render: faithful glyph → IDS → marked substitute
(visibly bracketed, distinct from edh erasure ⟦…⟧) → ⬚ + counted
footer. display.yml grammar `gaiji: ladder` (`placeholder` stays
valid = rungs 1+4, preserving P37-3 as config). Render-conformance
tests per rung incl. footer counts; docs/display.md CJK font-install
section (Jigmo, Plangothic, BabelStone Han). Acceptance: golden
renders exercising all four rungs; conformance suite green.

## P38-3 · Aozora adapter  [tier: fable — first-of-family parser] [status: done 2026-07-21 — merged 04f1f00; GitFetch needed NO change (P26-0 sparse: takes glob cones — 2 new pin tests); suite 5,115 green. JOURNALED: attic-rediscovery gap (index-driven discovery can't rediscover atticked works — future design); license_class mapped to `open` (no public_domain enum; vulgate precedent — owner may want a distinct class, gate flag); ~5 UTF-8-text works skip-by-rule; first-sync watch: unknown-command census, gaiji_unresolved (旧字-heavy), ruby orphans, delimiter-structure quarantines] [deps: P38-0, D38-a]
New parser family: Shift_JIS→UTF-8 NFC at the boundary; ruby
(furigana) as annotation layer, never inline text; gaiji resolved at
parse time — JIS X 0213 → real codepoint, component description →
IDS, unresolvable → loud ref for the display ladder. Per-work
license rows; language jpn; japonic axis; conformance suite + real
trimmed fixtures (one ruby-dense, one gaiji-bearing);
enabled:false until owner-fired first sync verifies.

## P38-4 · Japanese char-desk closure  [tier: opus] [status: done 2026-07-21 — merged; fold GO: 173 kyūjitai↔shinjitai pairs from held Unihan kJinmeiyoKanji (Nabu::Jpn, rake fold:jpn, hani-composed: Jpn.fold("国")==Hani.fold("國")=="國"; merges refused, 0 found); char card cross-references old/new forms; japonic fragment + conventions §9 refreshed; suite 5,137 green] [deps: P38-3]
kyūjitai↔shinjitai fold: survey held Unihan/KANJIDIC variant fields —
config-only lane (hani-fold mold) if the data supports; else journal
with the census. Char card jpn corpus counts; japonic axis page +
docs refresh; gate news post rides.

## P38-i1 · Aozora first-sync crash (incident, live 2026-07-21)  [status: done — merged; fix 20a7521, worklog entry has the full account]
Crash at doc ~9,471: real zips carry junk-byte member filenames
(neither UTF-8 nor CP932) — unzip -Z1 listing decode raised, and the
unrescued ArgumentError ABORTED the sync (ParseError contract
violation). Also ≥2 genuinely corrupt upstream zips found in the live
canonical. Fix: binary-safe member handling (never decode names),
ParseError wrap on the zip-read path, real regression fixtures from
the live canonical (offender whole + corrupt trim). 613-quarantine
census read after a clean pass.

## D38 decision items
- P38-r1 DONE 2026-07-21 (merged; rider commit 79553a5): 744 fold entries = 173 jinmeiyō + 341 kanjidic 1:1 + 79 admitted merges/185 olds; jis212 refused-and-proved (宋 misread pin); intersection jōyō signal; stroke-count discriminator keeps Chinese simplifications (弃/笔) from becoming fold canonicals; NEW/OLD char-card cross-ref stays jinmeiyō-only (honesty); search --exact live (candidates-then-verify, loud refusals, empty-page honesty). Suite 5,147 green post-merge; fold equalities + Hani-lane distinctness + --exact verified live by orchestrator.
- D38-b RULED (owner, 2026-07-21): jōyō-filtered extension, NOW as
  rider P38-r1 (not P39) — "THIS is japonic-focused Phase after all";
  the owner's pending full rebuild amortizes the fold-change
  re-derive. AMENDED same day: merges ADMITTED ("match modern reading
  habits by default — as long as there is an option to look for EXACT
  match along with it") → named admitted-merges census list
  (reversible), merge entries fold to Hani.fold(shinjitai) (1:1 pairs
  keep Hani.fold(old); lzh lane untouched), and `search --exact`
  ships in the rider (folded-FTS candidates + glyph-literal
  post-filter on stored text; loud refusal on unsupported paths;
  empty-result honesty). Original item: The shipped
  fold covers ONLY the 173 jinmeiyō-listed old-forms — the one clean
  1:1 signal held Unihan provides. The famous high-frequency reform
  pairs (學/学, 體/体, 醫/医, 觀/観 …) are NOT jinmeiyō-listed and stay
  literal: a search for 学 does not reach 學 in kyūjitai works.
  Extension would mine KANJIDIC2's kuten variants, which are
  one-to-many (學→{学,斈}) and need a disambiguation policy (plausible
  rule: fold only pairs whose target is jōyō-listed) — a policy
  invention the mold forbids without an owner ruling. Options:
  (1) ship as-is, journal the gap; (2) rule the jōyō-filtered
  KANJIDIC2 extension for a P38 rider or P39. Recommendation: (2) —
  the gap sits exactly on the desk's main use case.
- D38-a (owner, 2026-07-21): RULED — Option 1, PD text only:
  every work with 作品著作権フラグ=なし and a text file (~17,488
  works, ~0.7 GB raw, single license_class public_domain with 底本
  colophon attribution). The 488 in-copyright works are excluded from
  discovery (skip, not quarantine) and remain per-work opt-in
  candidates for a later phase. No orthography cut — the 旧字 slice
  stays a curated view idea, not an ingest boundary.

# ── P39 candidates (journaled at the P38 gate) ─────────────────────
#
# 1. REGISTRY SEMANTICS (owner-raised 2026-07-21/22, design agreed in
#    chat — the P39 opener): (a) kind: source | shelf | module — the
#    86-row registry conflates true upstream sources with local-*
#    gateway shelves and feature modules (kr-gaiji/bridging); list/
#    status group by kind, modules behind --all, sync on a module
#    prints its nature, censuses become "80 sources + 4 shelves + 2
#    modules" everywhere (README/02-sources/axis pages — §6b honesty).
#    (b) sync vocabulary: sync_policy gates ONLY sync --all membership
#    but reads as an upstream-activity claim; rename live→auto, keep
#    manual with an honest legend on every surface, frozen stays,
#    local DROPPED (redundant with kind: shelf). Owner leaned rename.
#    OWNER OUTPUT SPEC (verbatim, 2026-07-22) — grouped by type
#    (modules, shelves, sources), compact, no noise-OK, errors inline:
#      local-notes         -     shelf   up=local     notes=2   2026-07-21 18:02 (+0 ~0 -0 !0) <errors if any>
#      edh                 on(f) source  up=frozen    docs=81881 pass=406306 2026-07-21 17:58 (+0 ~0 -0 !2) <errors if any>
#      liv                 on(m) source  up=?(2d)      entries=305 2026-07-21 17:59 (+0 ~0 -0 !0) <errors if any>
#      kr-gaiji            -     module  up=module  2026-07-21 20:13 (+0 ~0 -0 !0)  <errors if any>
#      perseus-greek       on(a) source  up=ok(2d)   docs=1418 pass=394706 2026-07-21 17:15 (+0 ~0 -0 !1) <errors if any>
#    Decode: col2 = enabled+cadence fused (on(a)/on(m)/on(f); "-" for
#    kinds where enablement is moot; off(x) for disabled sources);
#    up= freshness (local/frozen/module structural; ok(Nd) probed-good
#    N ago; ?(Nd) unprobed manual upstream, age of last contact);
#    holdings label per content kind (docs+pass / entries / notes);
#    then last-sync stamp + delta (+added ~updated -withdrawn !errored)
#    + inline errors. Packet pins the residual semantics (off rows,
#    probe source for ok/?, label vocabulary) in its spec — no further
#    rulings needed.
# 2. FOLD-DIGEST GRANULARITY (journaled 2026-07-21): per-language fold
#    digests + language-scoped fold-module seam so a jpn-only fold
#    change stops dirtying all sources (the P38 all-dirty event).
# 3. jpn fold coverage watch: NEW/OLD char-card cross-ref stays
#    jinmeiyō-only; 碕/嵜 ambiguity refusals; merge list reversible.
# 4. Aozora quarantine-census triage (~1.5k gap classes: index↔tree
#    re-proof drift, delimiter-less legacy, UTF-8 five, corrupt zips)
#    + attic-rediscovery design + the display-ladder aozora wiring
#    (aozora-ids lane for description-only gaiji).
# 5. Carried: contentless-FTS5 implementation (P37-7 note), Aozora
#    in-copyright per-work opt-ins, Bunkankun watch, KR2p,
#    MAX_LEMMA_FORMS=400 watch, KR2o0001/KR3l0002 duplicate anchors.

# ── Post-P38 rebuild journal (2026-07-22, first full rebuild on the
# merged phase — owner log reviewed, verdict healthy; deferred items) ──
#
# CENSUS MOVED: 27,595,983 passages (was 24.4M — aozora 2.98M + desk
#   re-syncs). DEFERRED by owner ruling: axis-page/docs/README census
#   refresh waits for the next REGULAR docs update pass — pages
#   currently show pre-rebuild counts; fold into the next docs packet.
# DIORISIS URN COLLISION (confirmed in catalog): 0060:001 minted 3x
#   (rev=3), 0086:029 2x in a from-scratch rebuild — two canonical
#   files claim one URN each, last-writer-wins nondeterminism. Fix
#   shape: loud collision (quarantine or refuse), never silent.
# CBETA 50m26s — SLOWER than regression-era 35m51s despite the P37-7
#   batch fix (kanripo improved to 47m34s with +47% docs). Suspect:
#   hani/jpn fold translation over mega-passages at derive (pre-fold
#   profile blind to it). One-source profile BEFORE further engine work.
# AOZORA 49m16s / 17k docs ≈ 0.17s/doc — per-work unzip subprocess
#   (~17k spawns). P39 optimization: in-process extraction.
# PERSEUS-LATIN 27/561 quarantined (4.8%) vs greek 1/1419 — no P38
#   parser change can explain it; check against the owner PRIOR full-
#   rebuild log if retained (likely longstanding). Papyri 9,321 (13%)
#   believed longstanding, biggest quarantine pool — standing note.
# AOZORA QUARANTINE TRIAGE: 1,191 (6.9%) — classify by error message
#   (index-vs-tree re-proof drift / delimiter-less legacy / UTF-8 five
#   / corrupt zips) — already a P39 candidate, counts now live.

# Phase 39 — the registry & aftercare phase (approved 2026-07-22: all six packets; source of truth .docs/p39-registry-aftercare-plan.md)

## P39-0 · Registry semantics  [tier: opus] [status: done 2026-07-22 — merged cc26cee; 78+4+2=84 real rows; live→auto trio; sabellic-loans→frozen wrinkle; live smoke: perseus BEHIND surfaced day one] [deps: —]
kind: source|shelf|module + sync auto|manual|frozen (live→auto,
local dropped) + the owner output format verbatim (journal above);
sync --all = source∧auto; module sync prints nature; censuses become
80+4+2 everywhere; axis-generator grouping rides or journals (gate
docs pass; hand-edit precedent in catalog-less worktrees).

## P39-1 · Fold-digest granularity  [tier: fable — fingerprint semantics] [status: done 2026-07-22 — merged; language-scoped fold digests via catalog census; rake stamps:rebless attestation-gated] [deps: —]
Fold modules leave shared core → language-scoped fold digest
(lzh/och→hani; jpn→jpn+hani); normalize.rb stays global; dirty-MORE
asymmetry preserved; pins per plan; owner-gated rake stamps:rebless
(attestation flag) so the formula change skips a forced full rebuild.

## P39-2 · Aozora quarantine triage  [tier: opus] [status: done 2026-07-22 — merged 46a2b3e; ONE class (no-legend legacy txt kind), 1,191/1,191 recovered at prototype scale; hash-drift/UTF-8/corrupt = 0 live; attic answer = accept-as-designed (Option C, owner ratification at gate); perseus-latin 27 = longstanding upstream TEI (ISO-entity journal)] [deps: P39-3]

## P39-r2 · Site journey pass  [tier: opus] [status: done 2026-07-22 — merged 8815049; persona funnel + action calls; rake bless alias + ops §8b rake reference rode the merge] [deps: —, owner-requested at the gate]

## P39-r1 · Bare-kuten named-symbol resolution  [tier: opus] [status: done 2026-07-22 — merged 84db148; 16,137/19,094 occurrences (85%) resolve, 0 table failures; disjointness pinned] [deps: P39-2, P39-5]
KUTEN_GAIJI misses named symbols with bare men-ku-ten (二の字点、1-2-22 —
no 第N水準 prefix): 16,148/19,094 unresolved occurrences (85%). Widen
the notation grammar to accept bare-kuten where the code resolves via
config/jis0213 — resolved char INTO text (upstream identity claim, the
existing kuten precedent); unresolvable stays sentinel; census pins.
Classify live 1,191 by stored reason; recover mechanical classes
(census-backed only); attic-rediscovery design; perseus-latin 27
baseline check.

## P39-3 · Load-cost pair  [tier: opus] [status: done 2026-07-22 — merged; ZipReader 146x at fixture scale; CBETA ROOT CAUSE: String#tr per-call table rebuild → gsub precompiled 325x, byte-identical] [deps: —]
In-repo single-member zip reader (stdlib zlib, binary-name
discipline, byte-identical vs unzip -p across all fixture zips) +
cbeta derive-stage attribution incl. fixture-scale fold on/off
measurement. Live confirmation owner-fired.

## P39-4 · Diorisis URN collision  [tier: opus] [status: done 2026-07-22 — merged; distinct-works diagnosis → adapter disambiguation (5 URNs) + loud within-pass collision loader invariant] [deps: —]
Within-pass URN re-encounter with different content = loud collision
(quarantine later file + journal), revise-on-resync untouched; real
trimmed fixtures from the actual colliding files; upstream cause
reported.

## P39-5 · Aozora gaiji display wiring  [tier: opus] [status: done 2026-07-22 — merged 359c477; 244 IDS derived (46.2% of composition occurrences); RIDER FLAGGED: bare-kuten named symbols = 85% of unresolved occurrences, parse-time widening → P39-r1 after P39-2] [deps: P39-3]
Structured component descriptions → aozora IDS lane (conservative
grammar; ＋→⿰, ／→⿱; unresolvable stays sentinel); display.yml
aozora gaiji: ladder; resolvable census.

## P39-s1 · Germanic axis scout  [tier: survey/network] [status: done 2026-07-22 — survey delivered (.docs/surveys/germanic-survey.md); headline: 2 new parser families unlock 4 languages — IcePaHC config-only (CC BY-SA), Menotec ON+Edda (PROIEL family, nc), Penn family = YCOE 1.5M OE prose (nc) + HeliPaD Old Saxon (CC-BY); DDD CorA family = whole diachronic German lane (ReM CC BY-SA confirmed); Rundata runic ODbL dual-axis; PPCME2 blocked-license; OFris/ODu blocked-format (inquiry)]
## P39-s2 · Latin→Romance scout  [tier: survey/network] [status: done 2026-07-22 — survey delivered (.docs/surveys/latin-romance-survey.md); headline: Romance end completely empty + no romance axis exists; UD pack = 4 rungs config-only (LLCT charters CC BY-SA!); openMGH CC BY 4.0 = medieval-Latin bulk prize; digilibLT CIRCSE; BFM 6.45M words Etalab-open; bridge (REW PD-but-OCR / DÉRom / FEW) = R&D track; OVI/COM blocked]

# ── Long-term journal: ATTIC REVISION/REDESIGN (D39-a ruling, owner 2026-07-22) ──
# Ruled: Option C (withdrawal-as-designed) FOR NOW; the redesign is a
# standing future item with two owner-set requirements:
# 1. REMOVAL-CAUSE TAXONOMY: distinguish extrinsic/copyright removals
#    from error-correction/replacement/reorganization churn. Today the
#    attic records only that+when a file vanished (FETCH_HEAD sha),
#    never why — the taxonomy likely needs upstream commit-message
#    heuristics + an owner-annotation lane.
# 2. ACCESSIBLE **AND SEARCHABLE**: honesty check 2026-07-22 — only
#    half-true today. Withdrawn works: text retained, list --withdrawn
#    + show reach them, but ALL query paths filter withdrawn:false.
#    Redesign scope: an explicit withdrawn search scope (never
#    default-on), and the FTS index question it drags in (withdrawn
#    passages currently in or out of passages_fts? — verify then).
# Phase-sized when picked up; not before a concrete need or the next
# storage phase (contentless-FTS5 would touch the same index seams —
# natural pairing).

# ── Post-P39 (merged 728c70a, 2026-07-22) ──
# P39-r3 (search --limit semantics + stored-text snippets) was IN
# FLIGHT at merge time — owner ruling: "the fix goes into the next
# phase." It lands as the opening packet of P40 (branch cut when the
# agent delivers; spec + scope amendment recorded in the P39 plan
# doc). Until it lands, jpn search snippets show the search skeleton
# (known, documented) and --exact --limit reads as candidate-pool.
# P40 direction still open: Germanic package vs Romance package
# (.docs/surveys/) vs storage phase (contentless-FTS5 + searchable-
# withdrawn + attic redesign pairing).

# Phase 40 — the Germanic phase (approved 2026-07-22: full scope; D40-a one axis · D40-b nc ok · D40-c mint odbl · D40-d fetches pre-approved; source of truth .docs/p40-germanic-plan.md)

## P40-0 · Search UX fix (carried P39-r3)  [tier: opus] [status: done 2026-07-22 — merged e1c0f24; owner repro verified live 3/3 hits, real text; Greek accents restored to snippets; JOURNALED: proximity two-term stored highlighter rider]
## P40-g · Fixture groundwork  [tier: opus/network — D40-d pre-approved] [status: done 2026-07-22 — merged 6af11d4; findings: Menotec INESS-only (session API), Rundata bulk = 47MB sqlite + JSON API + ZERO runic codepoints, YCOE gated (owner fetch per FETCH-GATE.md)]
Sample fixtures + manifests + READMEs for icepahc(ud)/menotec/helipad/ycoe/rem/rundata; Rundata dump schema documented (feeds P40-6 design); YCOE gating verified (journal owner-fetch if click-through).
## P40-1 · IcePaHC via ud  [tier: opus] [status: done 2026-07-22 — merged cb06aeb; breaker latent-boundary catch; one stall-resume]
## P40-2 · Menotec adapter  [tier: opus] [status: done 2026-07-22 — merged 6f186bc]
## P40-3 · Penn family + HeliPaD  [tier: fable] [status: done 2026-07-22 — merged 016a021; fingerprint constant-poisoning trap found]
## P40-4 · YCOE — DROPPED (owner ruling 2026-07-22: ignore; OTA gate + nc terms not worth it)
## P40-5 · CorA family + ReM  [tier: fable] [status: done 2026-07-22 — merged 074006a]
## P40-6 · Rundata + runic display  [tier: fable] [status: done 2026-07-22 — merged cd862c1; odbl minted, migration 018]
## P40-7 · Organization + desk refresh  [tier: opus] [status: done 2026-07-22 — merged 0d7f604; germanic persona/desc + axes.md + news post]
## P40-9 · Docs architecture + site review  [tier: FABLE — orchestrator personally, owner-mandated no-delegation] [status: done 2026-07-22 — 99bd8f8 (stage 1: where-truth-lives map in maintenance-and-extension §0; README/library/languages/02-sources/quickstart refreshed from the live catalog; three inconsistent gold censuses reconciled; library.md gained the missing Japanese + Germanic sections) + 75d4d53 (stage 2: site index/library/sources/languages/tools/faq/about; +24 sources rows; ODbL attribution; fragments-level fix of the Greek-on-Celtic example and ALL placeholder recipes with live-verified real commands; site:axes regenerated ×19; dossier drift fixed through the gateway). JOURNALED → P41 candidate: ~37 older source dossiers still carry seeded sync-queue debris in their descriptions — one curation sweep wanted]

## P40-r1 · ReM quarantine recovery  [tier: fable — orchestrator direct] [status: done 2026-07-22 — 7b2abc3; all 46 quarantines one class (duplicate folio.line): two-column codices now cite 5ra.1 (cb tracked in CoraTeiParser), entry-wise restarts take the house :b2; +46 docs / 355,449 rem lines / gmh gold 2.10M / corpus gold 15.0M; D40-e minted (68 loaded docs re-minted same-day — gate ratification)]

## P40-flips · [status: done 2026-07-22 — eb66f2f; owner-verified counts in sources.yml comments; IcePaHC landed at the owner's same-day `sync ud`]

# P42 — the efficiency phase (owner-picked 2026-07-23: "make these commands fly, not crawl"; plan: .docs/p42-efficiency-plan.md)

## P42-0 · source_stats + global census derived table  [tier: fable] [status: in-progress — dispatched 2026-07-23] — status/list/axis/language 130–250s → ms; migration 019; D42-a health invariant
## P42-2 · ubiquitous-term guard  [tier: fable] [status: in-progress — dispatched 2026-07-23] — fts5vocab df probe; the الله class ~10s → sub-second
## P42-1 · vocab lemma-frequency table + etym probe  [tier: opus] [status: ready] [deps: P42-0 (migration 020)]
## P42-3 · language column into passages_fts  [tier: fable] [status: ready] — activates at the owner rebuild (D42-b)
## P42-4 · load hygiene: post-load bounded ANALYZE + PRAGMA pass  [tier: opus] [status: ready]
## P42-5 · re-measure matrix + docs  [tier: orchestrator] [status: gate-time]
## P42-6 · term-less filtered browse  [tier: opus] [status: optional — rolled from P41-r1]

## P41-r2 · --random instant (id-probe sampler)  [status: done 2026-07-23 — 98ef4b6; 2m19s → 0.3s; join-free probe pattern documented]

## P41-r1 · Recipe honesty: term-less filtered search never existed  [status: done 2026-07-22 — six recipes + README/tools composed with live-verified queries; riders journaled: term-less filtered-browse mode, catalog-side filter window starvation (P40-r2 genus)]

# P41 — the Arabic phase (owner-picked 2026-07-22: "A, full scope, display considerations, new arabic(islamic?) axes, whole shebang"; plan: .docs/p41-arabic-plan.md)

## P41-g · OpenITI fixture groundwork + mARkdown census  [tier: opus/network — D41-d gated] [status: done 2026-07-22 — merged 7444280; findings in plan doc; D41-e evidence awaiting owner ruling]
Goal: format census from real files + 3-4 trimmed fixtures + metadata index + D41-e sizing.
Acceptance: test/fixtures/openiti/ with P5-4 manifest+README; findings memo reshapes P41-1/2.

## P41-1 · mARkdown parser family  [tier: fable — first-of-family] [status: done 2026-07-22 — merged b36bfd6; end-of-page retro-assignment semantics; five fixture catches; census keys enumerated for the adapter]
## P41-2 · OpenITI adapter + fetch + AH timeline  [tier: fable] [status: done 2026-07-22 — merged 5564340+b2dc180+dd46244; first wave ≈ 9,106 docs (MSS∩pri resolved), ~5,001 censused skips; streamed md5-pinned fetch; zip-nesting watch item for first sync]
## P41-3 · Arabic folding + display  [tier: fable — semantics-adjacent] [status: done 2026-07-22 — merged c923a21+f26675d; ara/fas shared fold, evidence-ruled; P41-2 MUST mint ara/fas not per; riders journaled: romanization mode, tashkeel display class, digit fold]
## P41-4 · arabic axis + registry + desk + news  [tier: opus] [status: done 2026-07-22 — merged f4e9a6f + completion dcde669; desk live at /axis/arabic/, dossiers installed, site:check clean]
## P41-5 · License-inquiry drafts  [tier: orchestrator] [status: done 2026-07-22 — №41-1 DASI / №41-2 MPCD / №41-3 TITUS-Avestan / №41-4 CEToM / №41-5 DĀMOS drafted in full, contacts researched (two bot-walled, browser-reveal noted); owner sends]

## gate40 · [status: done 2026-07-22 — merged 65cf8ec (PR #52); v1.2.0 tagged at acc4c96, GitHub release published, Zenodo DOI auto-minting; D40-e ratified at merge]

## P40-r2 · --lang is dead on arrival  [tier: fable — orchestrator direct] [status: done 2026-07-22 — code_variants always includes the typed code (catalog stores `is`; 639-1 hop swallowed it) + --lemma lang filter moved INDEX-side (homograph window starvation); owner's runbook repro was the catch; gold now 16.24M in 28 langs (is #4, lzh joins)]
Stale Library/Languages/Sources; axis pages with off-desk examples
(Greek search on the Celtic page); thoughtful page-by-page pass
against the live catalog, generator/fragments improved so fixes
survive regeneration.

## P40-8 · License inquiry drafts  [tier: opus] [status: done 2026-07-22 — 5 drafts in .docs/licensing-emails.md; contacts verified-live except INT servicedesk (eyeball first); DISCOVERY: Tarrin Wills heads BOTH Skaldic and ONP — one reply could resolve both]

# Micro-journal (2026-07-22): search --exact vs NFC-exempt languages —
# hbo/arc storage is deliberately not NFC-normalized; the exact filter
# NFCs the query then substring-matches stored text, so forms whose
# Masoretic mark ORDER differs from NFC order can miss. Live spot-check
# (בְּרֵאשִׁית) hits, but the exemption exists because divergent orders
# exist. Fix shape: NFC both sides AT MATCH TIME only (storage
# untouched). Rider-sized; pair with the proximity stored-highlighter.

# Rider candidate (owner, 2026-07-22): --word flag for search —
# word-exact matching alongside --exact (glyph-exact is substring: ἦ
# also finds ἦμαρ). Composes with --exact (word-and-glyph exact) and
# plain search (word-bounded fold match). Boundary definition per
# script needs care: whitespace/punct for alphabetic scripts; CJK has
# no word boundaries — flag refuses or degrades honestly there
# (spaceless runs = one FTS token already). Pair with the proximity
# stored-highlighter + NFC-exempt match riders (one search-polish
# rider bundle).

## P40-f · Focus profile  [tier: opus] [status: queued — dispatches after P40-s merge] [owner-approved: axes AND single sources]

## P40-w · Search-polish bundle  [tier: opus] [status: done 2026-07-22 — merged 354deb7; --word (CJK refusal, Hangul ok), proximity stored highlighter, NFC-exempt display fix on real WLC bytes]
