# The trickle runner — a standing paced crawl

Some sources are days of requests away from complete at the pace their
upstream asks for. A phase's rail slices (`rake "rail:step[SLUG]"`,
`rake "crawl:chain[SLUG,N]"`) spend a capped allotment and stop; the
**trickle runner** is the other mode: one command detaches a crawl of
the source that runs slice after slice, at the source's own declared
pace, until the crawl is done or something stops it. It needs no open
terminal or session, survives the one that started it, and resumes
where it left off when started again.

It only **crawls**: payloads land in `canonical/<slug>/` through the
source's paced-crawl engine, and nothing is loaded into the catalog.
Loading stays with the normal sync, run whenever you want the new
material searchable:

```sh
bin/nabu sync <slug> --parse-only
```

The executable truth is `Nabu::Ops::Trickle`
(`lib/nabu/ops/trickle.rb`), exercised by `test/ops/trickle_test.rb`;
architecture §19 has the design.

## Which sources

Any source whose adapter declares paced-crawl lanes (`paced_crawls`):
today wellcome, ndl-kotenseki, damos, niupepa, korpus16,
mdz-protestant, pleias-french-books. Any other slug is refused.

## Fire

```sh
bundle exec rake "trickle:start[wellcome]"
```

EXPECT, within a few seconds:

```
trickle wellcome started (pid 12345) — 1 lane(s): zips
log: /path/to/nabu/local/trickle/wellcome.log
stop: bundle exec rake "trickle:stop[wellcome]"; status: bundle exec rake trickle:status
```

Refusals (nothing is started; the command exits nonzero):

- `… has no paced_crawls lanes …` — not a paced-crawl source.
- `a trickle of wellcome is already running (pid N) …` — one trickle per
  source; stop it first.
- `a sync or rail step is fetching wellcome …` — a sync or rail step of
  that source holds its fetch lock right now; wait for it to finish.
- `the trickle runner … exited at once — log tail: …` — the runner died
  at birth (an unreadable census, say); the tail says why.

While a trickle runs it holds the source's fetch lock, so a plain
`bin/nabu sync wellcome` (which would crawl a slice of its own and
double the request rate) fails fast with "another nabu process is
syncing wellcome". `bin/nabu sync wellcome --parse-only` is never
blocked — that is the way to load during a trickle. To refresh a
source's census or do a full sync, stop the trickle, sync, start again.

## Watch

```sh
bundle exec rake trickle:status
```

EXPECT one line per source that has ever trickled:

```
wellcome: RUNNING (pid 12345) — held 1234, remaining 30064; last: 2026-11-23T10:30:02Z SLICE wellcome/zips #1 [yield]: +58 held, held 1234, remaining 30064 (60 asked, 60 request(s) in 30m01s)
```

`finished` means the runner exited and wrote its SUMMARY line. `DIED`
means its process is gone without one (killed hard, or the machine went
down) — start it again; the crawl resumes at its frontier. With no
trickles at all: `no trickles (…/local/trickle holds no runner state)`.

The full progress log is `local/trickle/<slug>.log`, written line by
line as it happens (safe to `tail -f`): a `START` line per lane (held,
remaining, the pace and slice size), one `SLICE` line per slice with
that slice's full report indented under it, and at the end a `STOP`
line with the reason and a `SUMMARY` line.

## Stop

```sh
bundle exec rake "trickle:stop[wellcome]"
```

The stop is graceful: the runner finishes the request it is making (the
id stays un-ledgered and is the first one asked next time) and exits.
The command waits up to 90 seconds (`TRICKLE_STOP_WAIT=<seconds>`
changes that). EXPECT:

```
trickle wellcome stopped (pid 12345): 2026-11-23T14:00:31Z SUMMARY wellcome: 8 slice(s), +451 held, held 1685, remaining 29613, 241m10s — stop requested
```

or, when the request in flight takes longer than the wait,
`stop requested for wellcome (pid 12345) — …`; `trickle:status` shows
the SUMMARY line once it lands. With nothing running:
`no trickle running for wellcome` (and any leftover state of a dead
runner is cleared) — safe to repeat. Killing the runner's pid with a
plain `kill` (TERM) is the same graceful stop.

## When it stops by itself

The SUMMARY line names the reason:

- `cone end — every lane exhausted` — the crawl is complete.
- `N consecutive zero-yield slice(s) — the declared budget …` — the
  source's own declared stop (a refusal desert or a block); read the
  last slice reports in the log before restarting.
- `clean stop at …` — upstream asked the crawl to stop (a quota floor).
- `upstream outage — …` — the source's outage breaker tripped; restart
  once upstream answers again.
- `fatal: …` — an error the engine does not classify (an HTTP 429 or
  5xx, a network failure). Nothing learned is lost; start again later.

## The pace

The runner never chooses a pace. Every request waits the lane's
declared delay — the adapter's reading of the upstream's robots rule —
including across slice boundaries, and each run opens with one full
delay before its first request so a quick restart never arrives early.
A lane declaring no delay is refused.

## Worked example — the wellcome first drain

The wellcome zip lane asks one bnumber per 30 seconds
(`iiif.wellcomecollection.org/robots.txt`: `Crawl-delay: 30`). With
~30,124 bnumbers remaining, a full drain is

    30,124 × 30 s ≈ 903,700 s ≈ 10.5 days

of continuous crawling, landing roughly 9 GB of zips under
`canonical/wellcome/zips/`. Fire it once, check `trickle:status` when
convenient, load with `bin/nabu sync wellcome --parse-only` whenever the
held count has moved enough to matter, and let it run. If the machine
sleeps or restarts, `trickle:status` reports `DIED`; start it again.

## Where the state lives

`local/trickle/` (inside the instance folder, never in git; created on
first start): `<slug>.pid` while the runner lives, `<slug>.log` (kept;
delete it whenever you like), `<slug>.stop` only between a stop request
and the runner's exit. The crawl's own state — the held payloads and
the crawl ledger in `canonical/<slug>/` — is what makes it resumable;
the files here are only the runner's.
