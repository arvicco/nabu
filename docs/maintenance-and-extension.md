# Maintenance, Extension & Source Adoption

How this stays a living system rather than a one-off scrape. The design premise: upstream corpora change slowly but *do* change (new editions, restructured repos, dead projects), models improve yearly, and the owner's attention is intermittent. Everything below optimizes for "pick it back up after three months and nothing has rotted."

## 0. Where truth lives

Every aspect of the project has exactly one authoritative surface; everything
else is a projection or a dated snapshot of it. When two surfaces could
disagree, one is declared the projection and (wherever practical) a gate
check pins the agreement. The map:

| Aspect | Source of truth | Derived surfaces | Kept honest by |
|---|---|---|---|
| Holdings & census (documents, passages, entries, lemma rows) | The live catalog (`db/catalog.sqlite3` + `db/fulltext.sqlite3`), read via `nabu status` / `list` / `axis` / `language` | Every number in README, docs, and the site is a **dated snapshot** read from the catalog | Gate-time refresh (library.md §10); site numbers are *copied* from README/library.md with their as-of dates, never re-derived (`site/MAINTENANCE.md`) |
| Source registry (what exists, kind, axes, license class, sync policy, enablement) | `config/sources.yml` | `nabu list`/`status` rows; docs/library.md sections; site pages | Enablement flips only after an owner-verified first sync; conformance suite per adapter |
| Per-source scouting & license record | [docs/02-sources.md](02-sources.md) (one row per source: access path, scores, license verbatim, status) | Site *Sources & Licensing* page | Status column updated when a source's lifecycle moves (built → synced → flipped) |
| Curated per-source prose (dossiers) | `canonical/local-source/` (one Markdown dossier per source, `nabu ingest --shelf source`) | `nabu list SOURCE` card; catalog `source_records` | `rake site:check` cross-checks dossier descriptions against docs/library.md (drift = exit 1) |
| Research axes (desks, personas, ratified order) | `config/axes.yml` + the list-valued `axes:` tags in `config/sources.yml` | [docs/axes.md](axes.md) membership listing; `nabu axis`; `site/axis/*` pages | `test/docs/axes_page_test.rb` fails the build if docs/axes.md and the registry disagree; `rake site:axes` *generates* the site pages from registry + `site/axis/_fragments.yml` + live counts |
| Languages (codes, curated context) | `canonical/local-language/` dossiers (edit in any editor; `nabu sync local-language` re-derives) → catalog `language_records`; derived names census `language_names` | `nabu language CODE`; [docs/languages.md](languages.md) (dated snapshot) | Gate-time refresh alongside library.md |
| Commands & flags | The CLI itself — `bin/nabu help <command>` carries worked examples | README feature table (a pointer summary); site *Tools* page | The test suite pins CLI behavior; docs demos are dated live-run pastes |
| Search folding & display rules | Folding: [conventions §9](conventions.md) + the folding code (test-pinned). Fonts/terminal setup: [docs/display.md](display.md) | Per-axis display notes in `site/axis/_fragments.yml` | Fragments header rule: name no font/feature display.md doesn't |
| Architecture & invariants | [docs/architecture.md](architecture.md) | — | CLAUDE.md rule: implementation deviations update the doc in the same change |
| Operations (schedules, alarms, backup/restore, release rail) | [docs/ops.md](ops.md) — the runbook | §1 cadence table below (the summary view) | Owner-executed drills (`rake ops:drill`) |
| Per-document license | Catalog rows (`license` class as data, per document) | Every CLI/MCP surface prints the label; README/site summaries | Per-source terms recorded in 02-sources.md; license baselines probed by `nabu health` |

Two corollaries worth stating plainly. **The catalog is the territory;
prose is the map** — no document in `docs/` is ever the source of truth for
a number, so a stale count is a staleness bug, not a data bug. And **curation
lives on the canonical shelves** (language dossiers, source dossiers, notes),
not in docs files — edit the dossier, re-sync the shelf, and every surface
that projects it follows.

## 1. Cadence

The operative schedule, commands, and launchd templates live in
[docs/ops.md](ops.md) — that runbook wins wherever this summary drifts.

| Frequency | Action | Mechanism |
|---|---|---|
| Nightly | `nabu verify` (hash canonical vs catalog), db snapshot | launchd job (ops.md templates) |
| Weekly | `nabu sync --all` + `nabu health` review | launchd or manual; health trend rules flag anomalies |
| Quarterly | Review `runs` anomalies, upstream release notes for git-based sources, RuboCop/gem updates; library.md full review (§10) | Manual, ~1 hour |
| Yearly | License re-verification pass over `sources.yml`; (once embeddings exist) embedding model review | Manual |

The >20% withdrawal circuit-breaker (architecture §8) is the main guard against silent upstream restructures gutting data during unattended syncs.

## 2. Keeping upstream sync sane

- **Vendored snapshots, not submodules.** Git-based sources are cloned into a cache and *copied* into `canonical/<source>/` at a recorded upstream SHA. Submodules couple your repo's health to upstream force-pushes and renames; snapshots make every sync an explicit, diffable, revertible commit in the canonical repo.
- **Scraped sources get frozen-by-default.** ETCSL-style dead projects sync once and set `sync_policy: frozen` in `sources.yml`. TITUS-style fragile sources set `sync_policy: manual` — never in `--all`.
- **Upstream drift detection is cheap:** every sync records per-source `(added, updated, withdrawn)` counts in the run ledger, and `nabu status` carries the `up=` drift column; a source that's been `0,0,0` for a year is a candidate for `frozen` (stop hitting it); a source suddenly showing mass updates gets manual eyeballing (the >20% mass-deletion breaker aborts the destructive case automatically; a staging/accept flow remains a design idea, not a shipped flag).

## 3. Extension axes, in expected order

1. **New adapters** — the routine case; the CLAUDE.md checklist is the whole process. Target cost for a known parser family: an evening including fixtures.
2. **New parser families** — rarer (ATF, Menota-TEI, MdC hieroglyphic). Rule: the parser is built and tested standalone against fixtures *before* any adapter uses it. Budget a weekend.
3. **New enrichers** — new annotation layers (metrical scansion, named-entity tagging, verse alignment). The `enrichments(kind, model, payload_json)` table absorbs new kinds without migration; only genuinely relational data (e.g., token-level alignment) justifies new tables.
4. **New query surfaces** — the read-only JSON endpoint over Tailscale (Sinatra, mirrors the knowledge-pipeline pattern; eventually public at nabu.ac), then possibly a thin web UI. These consume the store and never gain write paths — preserves the rebuildability invariant.
5. **HTR for the local library** (design-stage — waits on local inference hardware) — the intake front door shipped as `nabu ingest` (Phase 19), and image-only scans on the local-library shelf keep their page images as the durable asset precisely so that, once an HTR pass exists, transcription quality can ratchet up over time by re-running newer models against the same images.

## 4. Adopting a new source — decision procedure

Before writing anything, answer in a short note appended to `docs/02-sources.md`:

1. **What does it add** that existing sources don't? (New texts / better editions / annotations / images.) If the answer is "same texts, different edition," default to no — record it as a known alternative instead.
2. **License class?** If `restricted`, is interactive use enough? Adapters are for corpora you'll query programmatically, not everything that exists.
3. **Bulk access path?** git > dump > API > polite scrape. If scrape-only *and* the project looks alive, email them first — data requests succeed more often than people expect and produce cleaner data than scraping.
4. **Parser family?** Existing family → cheap. New family → is there a second future source in the same family? A family with exactly one source ever is a smell (fold the parsing into the adapter instead).
5. **Sync policy?** live / manual / frozen.

This note *is* the adapter's spec and becomes the fixture-selection guide.

## 5. Schema and model evolution

- **Migrations forward-only**, and `nabu rebuild` must work from any released schema version — test this by keeping one old db snapshot in test fixtures and asserting migrate-then-rebuild succeeds.
- **Embedding model changes** (design-stage — the embedding layer is not yet built): new table per model-version (architecture §5) means old and new coexist during re-embed; a future `nabu search --semantic` pins to the version marked active in config. Cutover is a config flip; rollback likewise. Never mutate vectors in place.
- **URN policy is frozen.** Minting rules for ad-hoc URNs, once used, never change (they're in citations, notes, exports). If a rule proves wrong, new rule applies to new documents only; old URNs get an `aliases` row if remapping is truly needed.
- **Prompt versions are schema too** (design-stage, alongside HTR/glossing): when model-driven enrichment lands, its prompts live in `config/prompts/` under version numbers; provenance rows record which version produced each artifact. Prompt changes are commits, reviewable and bisectable.

## 6. Testing as the maintenance backbone

- The **adapter conformance suite** is the contract's enforcement arm: when the contract gains a requirement (say, `script:` tag on passages), add it to conformance, watch every adapter fail, fix each — the suite converts a cross-cutting change from "audit 15 adapters by hand" into "make the tests pass."
- **Fixture refresh discipline:** `rake fixtures:refresh[source]` re-snapshots upstream samples; run it when an upstream format change is suspected, diff the fixture, and let the failing tests describe exactly what changed. Fixtures double as an archive of upstream formats over time.
- **Golden-query smoke test:** a small set of known queries with expected results (`test/golden/`) — "search πλέων returns Od. 1.183 among top hits," "concord prisega finds Freising II." Runs after every rebuild; catches loader/normalizer regressions that unit tests miss.

## 7. Longevity hedges

- **Exit formats are first-class:** `nabu export` to plain text + JSONL and to CoNLL-U must always work. The system's value survives even if the code doesn't.
- **The canonical layer is the will.** If everything else is abandoned, `canonical/` + its git history + ad-hoc images + `sources.yml` (with licenses and URLs) is a complete, self-describing dataset another tool — or another decade's Claude — can adopt cold. Keep a `canonical/README.md` written for that reader.
- **Document the quirks where they live:** every adapter file opens with a comment block on the source's format oddities discovered during implementation (encoding traps, URN irregularities). This is where three-months-later-you looks first.
