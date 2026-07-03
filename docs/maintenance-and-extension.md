# Maintenance, Extension & Source Adoption

How this stays a living system rather than a one-off scrape. The design premise: upstream corpora change slowly but *do* change (new editions, restructured repos, dead projects), models improve yearly, and the owner's attention is intermittent. Everything below optimizes for "pick it back up after three months and nothing has rotted."

## 1. Cadence

| Frequency | Action | Mechanism |
|---|---|---|
| Nightly | `nabu verify` (hash canonical vs catalog), db snapshot | launchd job; failures → ntfy (reuse the SMS-daemon ntfy channel pattern) |
| Weekly | `nabu sync --all --report` | launchd; report diffs passage counts per source, ntfy only on anomalies |
| Quarterly | Review `runs` anomalies, upstream release notes for git-based sources, RuboCop/gem updates | Manual, ~1 hour |
| Yearly | Embedding model review + possible re-embed; license re-verification pass over `sources.yml` | Manual |

The >20% withdrawal circuit-breaker (architecture §8) is the main guard against silent upstream restructures gutting data during unattended syncs.

## 2. Keeping upstream sync sane

- **Vendored snapshots, not submodules.** Git-based sources are cloned into a cache and *copied* into `canonical/<source>/` at a recorded upstream SHA. Submodules couple your repo's health to upstream force-pushes and renames; snapshots make every sync an explicit, diffable, revertible commit in the canonical repo.
- **Scraped sources get frozen-by-default.** ETCSL-style dead projects sync once and set `sync_policy: frozen` in `sources.yml`. TITUS-style fragile sources set `sync_policy: manual` — never in `--all`.
- **Upstream drift detection is cheap:** the weekly report includes per-source `(added, updated, withdrawn)`; a source that's been `0,0,0` for a year is a candidate for `frozen` (stop hitting it); a source suddenly showing mass updates gets manual eyeballing before the loader run is accepted (`nabu sync <source> --stage` loads into a staging schema, `--accept` promotes).

## 3. Extension axes, in expected order

1. **New adapters** — the routine case; the CLAUDE.md checklist is the whole process. Target cost for a known parser family: an evening including fixtures.
2. **New parser families** — rarer (ATF, Menota-TEI, MdC hieroglyphic). Rule: the parser is built and tested standalone against fixtures *before* any adapter uses it. Budget a weekend.
3. **New enrichers** — new annotation layers (metrical scansion, named-entity tagging, verse alignment). The `enrichments(kind, model, payload_json)` table absorbs new kinds without migration; only genuinely relational data (e.g., token-level alignment) justifies new tables.
4. **New query surfaces** — the read-only JSON endpoint over Tailscale (Sinatra, mirrors the knowledge-pipeline pattern; eventually public at nabu.ac), then possibly a thin web UI. These consume the store and never gain write paths — preserves the rebuildability invariant.
5. **HTR model upgrades** — new vision models re-run over *existing ad-hoc page images* is a standing cheap win: `nabu adhoc retranscribe <slug> --driver X` produces a new transcription candidate diffed against the committed one. Manuscript images are the durable asset precisely so transcription quality can ratchet up over time.

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
- **Embedding model changes:** new table per model-version (architecture §5) means old and new coexist during re-embed; `nabu search --semantic` pins to the version marked active in config. Cutover is a config flip; rollback likewise. Never mutate vectors in place.
- **URN policy is frozen.** Minting rules for ad-hoc URNs, once used, never change (they're in citations, notes, exports). If a rule proves wrong, new rule applies to new documents only; old URNs get an `aliases` row if remapping is truly needed.
- **Prompt versions are schema too:** HTR and glossing prompts live in `config/prompts/` under version numbers; provenance rows record which version produced each artifact. Prompt changes are commits, reviewable and bisectable.

## 6. Testing as the maintenance backbone

- The **adapter conformance suite** is the contract's enforcement arm: when the contract gains a requirement (say, `script:` tag on passages), add it to conformance, watch every adapter fail, fix each — the suite converts a cross-cutting change from "audit 15 adapters by hand" into "make the tests pass."
- **Fixture refresh discipline:** `rake fixtures:refresh[source]` re-snapshots upstream samples; run it when an upstream format change is suspected, diff the fixture, and let the failing tests describe exactly what changed. Fixtures double as an archive of upstream formats over time.
- **Golden-query smoke test:** a small set of known queries with expected results (`test/golden/`) — "search πλέων returns Od. 1.183 among top hits," "concord prisega finds Freising II." Runs after every rebuild; catches loader/normalizer regressions that unit tests miss.

## 7. Longevity hedges

- **Exit formats are first-class:** `nabu export` to plain text + JSONL and to CoNLL-U must always work. The system's value survives even if the code doesn't.
- **The canonical layer is the will.** If everything else is abandoned, `canonical/` + its git history + ad-hoc images + `sources.yml` (with licenses and URLs) is a complete, self-describing dataset another tool — or another decade's Claude — can adopt cold. Keep a `canonical/README.md` written for that reader.
- **Document the quirks where they live:** every adapter file opens with a comment block on the source's format oddities discovered during implementation (encoding traps, URN irregularities). This is where three-months-later-you looks first.
