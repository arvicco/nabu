# Operating the library — the administrator's process map

*Every recurring process an instance administrator performs, each with
its commands and a link to the detail document. This page is the
index and the home of last resort: routines with a dedicated document
get a paragraph and a pointer; routines that had no public home until
now are written out here in full. Where truth lives is
[maintenance-and-extension.md](maintenance-and-extension.md); the
scheduled runbook (launchd jobs, backups, drills, releases) is
[ops.md](ops.md) — this page maps the processes across both and fills
the gaps between them.*

## 1 · The daily/weekly frame

The scheduled jobs, their cadence, red-job triage, notifications:
**[ops.md](ops.md)** §1–§7. Health is the pulse — `nabu health`
(catalog-side anomalies: staleness, added-collapse, quarantine creep,
unresolvable place refs, the golden replay) and `nabu health --remote`
(upstream probes + license drift). Anomalies are triaged when seen,
not accumulated; `nabu health --accept-creep <slug>` is the deliberate
acknowledgment, never the reflex.

## 2 · Adding a source (the whole lifecycle)

The decision procedure (is it worth holding? what license class?) is
[maintenance-and-extension.md](maintenance-and-extension.md) §4; the
build checklist (fixtures → conformance suite → adapter → registry)
is CLAUDE.md's adapter checklist in the repository root. What follows
the build is the part that was never written down:

**The first-sync verification round.** A new source's first real sync
is verifying, not routine — expected counts are stated *before* the
run (from the fixture census and any upstream row counts), then
checked against the store:

```
nabu enable <slug>            # sync refuses un-enabled sources
nabu sync <slug>              # the first real fetch + parse + load
nabu status                   # counts vs the stated expectation
nabu list <slug>              # the shelf card: languages, license mix
nabu show <urn>               # eyeball ~5 random passages against upstream
```

Triage every quarantine class the round surfaces the same day — a
quarantine at first sync is a parser gap or an upstream quirk worth
knowing, never a shrug. Read the upstream's license terms verbatim at
this round (the page can differ from the survey that scoped the
source; drift is caught exactly here). Only then flip `wired: true`
in `config/sources.yml` — the registry's "this source's first sync
was verified" bit. `nabu list wired|unwired|enabled|disabled|locked|unlocked`
filters the registry by any of the three state axes.

**Core-layer postures.** Every text source declares how it relates to
the four core layers before the suite passes it:

```
nabu layer suggest <slug>     # one report: lect / dating / places / script census
```

The report's numbers drive the declarations: a lect rule in
`config/lect_facet_rules.yml` or a posture row in
`config/postures.yml` (`identity` — the bare language code is the
claim — is an honest answer; so are `undatable` and `unplaced`).
Dating lanes can be projected without a re-parse:

```
nabu lect infer-dates --source <slug> --dry-run   # then without --dry-run
nabu layer dates <slug>       # re-project one source's timeline lane
```

**Manual acquisitions.** Upstreams a machine cannot fetch follow the
manual-drop contract: `nabu sync <slug>` prints the instruction card
while `incoming/<slug>/` is empty; the human places the files; the
re-run validates, ingests, and sha-pins. Every such source has a
replayable document in **[manual/](manual/README.md)**.

## 3 · Keeping sources current

**Re-sync cadence** rides the ops schedule (ops.md §1); staleness
past a source's cadence shows in `nabu health`.

**Re-parse without refetch** — after a parser fix, the held canonical
bytes are re-read in place; no network, and the sha-skip census shows
exactly what changed:

```
nabu sync <slug> --parse-only
```

**The gazetteer refresh round.** The place gazetteers are held dumps
and drift upstream; refresh them together, reading the drift from the
derive counts (unchanged counts = zero drift):

```
nabu sync pleiades ; nabu sync trismegistos-geo ; nabu sync cigs ; nabu sync chgis
```

**Fixture drift** — monthly, `rake fixtures:check`; a drifted fixture
is re-cut with `rake fixtures:refresh[<source>]` (network,
deliberate). Detail: ops.md §1, maintenance-and-extension.md §6.

## 4 · Rebuilds and the stores

`db/` is derived — a pure function of `canonical/` + `config/` +
`local/` — and `nabu rebuild` regenerates it wholesale;
`nabu rebuild --incremental` replays only changed sources. The
etiquette that was previously only tribal:

- **Never census or report from a mid-rebuild catalog** — a partial
  db answers confidently and wrongly. Wait for the close-out.
- **A fresh full rebuild holds no withdrawn tombstones** — the
  durable history ledger keeps that record; an empty
  `search --withdrawn` right after a rebuild is correct, not a loss.
- **Restart any long-lived `nabu mcp` server after a full rebuild** —
  a server started before the rebuild can hold the deleted catalog's
  inode open (the disk fills invisibly; `lsof +L1` finds the
  holder). Current servers watch for the inode change and vacate on
  their own; restarting the client session is the belt to that
  suspenders.
- New index shapes arrive only at a full rebuild; the old shape keeps
  serving syncs until then (feature-detected, by design).

Backup and restore: the three permanent folders are the backup
(`canonical/`, `config/`, `local/`); `db/` is never backed up.
**[ops.md](ops.md)** §9 (backup + `rake ops:drill`) and
**[restore.md](restore.md)** (the two restore paths).

## 5 · Enrichment campaigns (owner-fired, long)

Each lane has its own explainer; all install their tooling through
`rake tools:*` tasks — `rake tools:status` is the board of what is
installed where:

- **Semantic search**: [embed.md](embed.md) — `rake tools:embed`,
  then `nabu embed` (delta-only after the first build; overnight at
  full-library scale), `nabu search --similar`.
- **Silver lemmas**: [lemma-enrichment.md](lemma-enrichment.md) —
  `rake tools:stanza[<lang>]`, then `nabu lemma-enrich <language>`.
- **Place mining**: [places.md](places.md) §"The mining loop" — the
  numbered census → mine → report → rule → re-mine script, with
  measured costs.
- **Person census** (the prosopography lane, deliberately gated):
  `nabu sync cbdb` derives the person index (~660k persons);
  `nabu person <name|cbdb:ID>` serves the card in either script;
  `nabu person mine <source>` runs the census-only name scan — it
  writes nothing by design, and stays census-only until the numbers
  justify opening an apply lane.

## 6 · Periodic audits

- **The recalibration audit** — after any growth wave, every
  era-bound constant (caps, thresholds, "N sources" literals) is a
  stale census claim. `rake census:check` verifies the marker
  discipline (era-bound literals carry their census comments);
  re-measure the marked sites against the live catalog and re-stamp.
- **Timeline-lane hygiene** — `nabu health` surfaces dark lanes
  (dated documents whose source never registered a dates extractor)
  and malformed bounds; `nabu layer dates <slug>` re-projects a lane
  after the fix.
- **The library review** — [library.md](library.md) §10, the
  staleness pass over the shelf descriptions.
- **The license pass** — yearly, plus `license_watch:` URLs probed by
  `nabu health --remote` (ops.md §1).

## 7 · The site and the public numbers

Every library-wide number on the site comes from ONE generated file —
`rake site:refresh` regenerates the census SSOT and the axis pages
from the live catalog. Run it **after** catalog-affecting changes
land (syncs, re-parses, rebuilds), never before — the site publishes
the state, not the intention. Contract and full routine:
**[site/MAINTENANCE.md](../site/MAINTENANCE.md)**.

## 8 · The derived-dataset rail and releases

`nabu data list` / `nabu data build <slug>` produce the public
derived datasets (files only — never git); the producer contract is
**[nabu-data.md](nabu-data.md)**. Software releases and citation
follow **[ops.md](ops.md)** §12. Both end in identity acts —
publishing and releasing are decisions a human signs, by policy.

## 9 · Talking to the library

The MCP server (`nabu mcp`) and its 13 tools:
**[mcp.md](mcp.md)** — registration per client, the
restricted-source exclusion stance, and (per §4 above) the
restart-after-rebuild rule.
