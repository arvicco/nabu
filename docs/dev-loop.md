# Dev Loop Plan — driving Nabu's implementation with Claude models

*How Nabu gets built with maximum unattended automation, minimum Fable-tier spend, and explicit human approval gates. This document is the proposal; nothing below runs until the owner approves the "Next steps" section.*

## 1. Why this project fits an unattended loop

Nabu's own ground rules (CLAUDE.md) accidentally specify a near-perfect autonomous dev loop:

- **TDD is mandatory** → every packet has a machine-checkable definition of done (`rake test` green).
- **No network in tests** → the loop can verify everything locally, deterministically, forever.
- **Shared adapter conformance suite** → new adapters are graded by an existing oracle, not by judgment.
- **"Small diffs" rule** → the unit of work is already PR-sized; packets fall out of the docs naturally.
- **`rake lint`** → objective style oracle, no bikeshedding.

The loop's job is therefore mostly *dispatch and verify*, not *judge* — which is exactly what lets cheaper models do most of the work.

## 2. Model tiering policy

**Principle: Fable writes contracts and judges; Opus writes code that has a pattern to follow; the test suite is the real gatekeeper regardless of who wrote the code.**

| Tier | Used for | Rationale |
|---|---|---|
| **Fable** | Adapter contract + conformance suite design; loader idempotency/revision/withdrawal semantics; URN minting policy; first parser of each family (sets the pattern); phase-gate reviews of the whole phase diff; adjudicating packets the loop marked `blocked` | Mistakes here are expensive and cross-cutting; everything downstream copies these patterns |
| **Opus** | Scaffolding; CLI commands; store/query implementation against a Fable-approved schema; every *second-and-later* adapter or parser in a known family; SyncRunner/reports; test-writing for well-specified behavior; doc updates; lint cleanups and mechanical code changes | Pattern-following work with an existing reference implementation and an oracle to grade it |
| **Sonnet** | Non-coding chores only: fixture READMEs, worklog/backlog housekeeping, summarizing run reports, drafting fixture shopping lists | Cheap and adequate for prose/bookkeeping; **never writes code** |

**Only Fable and Opus write code.** Sonnet/Haiku are restricted to simple non-coding tasks. Heuristic for tagging a coding packet: **first-of-kind → Fable; everything else → Opus.** When in doubt, tag Opus and rely on the escalation rule (§4) — a wrongly-tagged packet fails verification and gets bumped up, costing one retry, not a bad foundation.

## 3. Work packets and the backlog

The backlog lives at `docs/backlog.md` — a flat, human-editable list of packets:

```markdown
## P1-04 · Loader: upsert, content hashing, revisions  [tier: fable] [status: ready] [deps: P1-03]
Goal: Loader upserts passages by urn; unchanged content skipped via content_sha256;
      changed content bumps revision and journals old hash; upstream deletion → withdrawn.
Acceptance: idempotency test (load fixture twice, counts/revisions unchanged);
            revision-bump test; withdrawal test; rake test + rake lint green.
```

Statuses: `ready` → `in-progress` → `done` | `blocked` (with a reason line). The executing session updates its own packet's status and appends one line to `docs/worklog.md` (date, packet, commit SHA, notes). The backlog is the loop's entire coordination state — no external tracker, survives any session dying.

## 4. Loop mechanics

Each iteration, regardless of execution vehicle (§5):

1. **Pick** the first `ready` packet whose deps are `done`.
2. **Dispatch** at the packet's tier (session model or `Agent` model override).
3. **Implement TDD**: failing test first, then code, then refactor. CLAUDE.md rules apply in full (no assertion-weakening, no opportunistic refactors, no invented upstream formats).
4. **Verify**: `rake test` + `rake lint` green, then a `/code-review` (medium) pass; fix findings.
5. **Commit** on the current phase branch (`phase-N`), imperative message referencing the packet ID. Update backlog + worklog.
6. **Escalate on failure**: two failed attempts at a packet → mark `blocked` with a diagnosis, move to the next packet. Never thrash. `blocked` packets are adjudicated by Fable at the next gate (or sooner if everything else is blocked → stop and notify the owner).
7. **Phase gate** (all phase packets done/blocked): Fable reviews the *entire phase diff* against `docs/architecture.md`, checks the doc is still truthful (updates it if implementation deviated — per CLAUDE.md), resolves blocked packets, **updates `README.md`** — the user-facing document describing the capabilities and commands implemented up to this point (honest about what doesn't work yet; a newcomer reading only the README should know exactly what `bin/nabu` can do today) — then opens a PR `phase-N → main`. **The owner reviews and merges the PR — this is the standing human approval gate.** The gate turn ends by arming the owner's attention alarm (sticky mode — see the global convention in `~/.claude/CLAUDE.md`), as does any blocked state needing guidance. The next phase's packets are elaborated in detail only after the merge.

## 5. Execution vehicles — two stages

**Stage A (Phases 0–2): Fable-led sessions, semi-attended.**
A Claude Code session on Fable does the design-heavy packets itself and delegates `tier: opus` packets to Opus subagents via the Agent tool. Owner is around intermittently; this is where trust in the loop is built and where Fable spend is genuinely justified anyway.

**Stage B (Phases 3–4): assembly line, unattended.**
The pattern library exists; now it's a dozen similar adapters. Run the loop as an **Opus main session** (interactive `/loop`, or headless `claude -p --model opus` per packet from a small driver script) that spawns **Fable subagents only** for gate reviews and blocked-packet adjudication. Fresh context per packet prevents drift; the backlog file carries all state between packets.

Cloud scheduled agents are deliberately *not* proposed for v1: fixtures and real syncs are local-machine concerns and the project is local-first. Revisit if Stage B proves itself.

## 6. Guardrails

The principle: **inside the sandbox, full freedom — the boundary itself is hard.** Permissions are set to minimize nagging for anything that can't damage the box or leak credentials.

**Freely allowed, no prompts:**
- All file operations inside the repo, plus free writing/experimentation in the project scratch space (`tmp/` inside the repo, gitignored) and the session scratchpad.
- `rake test` / `rake lint` / `rake lint:fix`, `bin/nabu` commands, `bundle install`/`bundle exec` against the project Gemfile, `git add/commit/branch/checkout` on non-`main` branches.
- Online research: web search and fetching docs/specs/upstream format references.
- Experimenting with external APIs (upstream corpus endpoints, IIIF manifests, etc.) — exploratory calls to understand formats are fine; only *bulk* corpus fetches follow the fixture/sync procedure (§8).

**Hard boundary (explicit owner permission, every time):**
- Anything outside the repo on this machine — dotfiles, global git config, system settings, other projects.
- **Keys, auth, credentials, tokens — never touched, period.** API keys the loop needs are provided by the owner via env/config; the loop uses them but never creates, moves, or modifies them.
- Pushes to `main`. (Phase branches: per the push policy decided in §9.)
- Installing software outside the project (brew, global gems, system Ruby changes). New gems *in* the Gemfile still follow the CLAUDE.md ask-first rule.

**Loop discipline:**
- **Two-strike rule** (§4) bounds wasted spend on any one packet.
- **The loop never marks its own phase done** — a phase ends at a human-merged PR, full stop.

## 7. Phase & packet breakdown

Build order follows `docs/02-sources.md` synthesis (1 → 2 → 4 → 3/5 → 10 …). Packet lists below are the plan; each phase's packets get their full Goal/Acceptance elaboration at the previous phase's gate.

**Phase 0 — Scaffold** *(Opus throughout; Fable reviews the result at the gate)*
- P0-1 Gemfile, Rakefile, RuboCop config, Minitest + WebMock harness (HTTP blocked globally)
- P0-2 `bin/nabu` Thor skeleton, `config/nabu.yml` loading, `--version`
- P0-3 GitHub Actions CI: `rake test` + `rake lint` on every PR (the loop's external, un-gameable oracle)
- P0-4 `Nabu::Error` hierarchy, `Nabu::Shell.run`, `Nabu::Normalize.nfc` with encoding regression-test scaffolding

**Phase 1 — Core domain** *(Fable-heavy: this is the foundation everything copies)*
- P1-1 Value objects: `Passage`, `DocumentRef`, `SourceManifest`, `Document` [fable]
- P1-2 `Nabu::Adapter` base class + contract + conformance suite skeleton [fable]
- P1-3 Store: Sequel migrations for the catalog schema (architecture §5), models [fable design → opus implement]
- P1-4 Loader: upsert-by-URN, content hashing, revision journal, withdrawal [fable]
- P1-5 `nabu rebuild` + in-memory-SQLite store tests + idempotency tests [opus]
- P1-6 `config/sources.yml` registry + `runs` table + `nabu status` [opus]

**Phase 2 — Reference adapter (Perseus)** *(the pattern-setter)*
- P2-1 Perseus fixtures: acquisition plan → owner approval → loop fetches (§8)
- P2-2 `EpidocParser`, SAX-based, standalone + tests [fable — hardest parser, defines the family pattern]
- P2-3 Perseus adapter composing EpidocParser + conformance suite pass [opus]
- P2-4 `SyncRunner`, `FetchReport`/`LoadReport`, >20% withdrawal circuit breaker [opus, fable review]
- P2-5 First real `bin/nabu sync perseus-greek` + eyeball check — **human**

**Phase 3 — Family expansion** *(Opus assembly line; fixtures batch-provisioned up front)*
- First1KGreek adapter (EpiDoc reuse — "nearly free") · `ConlluParser` + UD adapter · `ProielParser` + PROIEL adapter · TOROT adapter (PROIEL reuse) · Papyri.info adapter (EpiDoc reuse)

**Phase 4 — Query surface** *(Opus; Fable reviews normalization/search-form rules)*
- FTS5 external-content table + `nabu search` · `nabu show` / `nabu export` (plain/JSONL/CoNLL-U) · golden-query smoke tests (`test/golden/`) · `nabu verify`

**Phase 5+ — Enrichment, ad-hoc/HTR pipeline** — deliberately unplanned here; involves API keys, local sidecars, and human review by design. Planned at the Phase 4 gate.

## 8. Fixture acquisition (approve the plan, then the loop fetches)

Tests need real trimmed upstream samples. Acquisition is automated but plan-gated:

- At each phase gate, the loop builds a **fixture acquisition plan**: per source — exact URLs/repo paths, what to trim and why, expected sizes, target `test/fixtures/<source>/` layout, license note, README template.
- **The owner approves the plan** (per phase, one approval covering all that phase's sources).
- The loop then executes the fetches itself, trims, writes the fixture READMEs (retrieval date + URL per CLAUDE.md), and commits — staying strictly within the approved list; anything unexpected (moved URLs, format surprises) goes back on the plan for re-approval rather than being improvised.
- A phase never starts with an unapproved fixture plan; the gate is where approval happens, so fixtures never block mid-loop.

Real full syncs (`bin/nabu sync <source>` against complete upstream corpora) remain human-initiated per CLAUDE.md — they're bulk downloads and eyeball-verification events, not test infrastructure.

## 9. Decisions (approved by owner, 2026-07-03)

1. **Plan approved** with amendments incorporated (§2 only Fable/Opus write code; §6 sandbox-freedom guardrails; §8 plan-gated automated fixture acquisition).
2. **Push policy:** the loop pushes `phase-N` branches and opens PRs on `arvicco/nabu`; `main` stays owner-merged.
3. **Stage A attendance:** Phase 0 runs interactively (Fable orchestrating, Opus implementing); `/loop` from Phase 1 onward.
4. In effect: `docs/backlog.md` carries the elaborated packets, `.claude/settings.json` carries the permission profile, work proceeds on `phase-N` branches.
