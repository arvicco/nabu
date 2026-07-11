# Contributing to Nabu

Nabu is a personal research project under tight editorial control — the
backlog is driven by one scholar's needs, and it's built by an autonomous
model loop against strict TDD ground rules (see below). That said,
contributions are genuinely welcome: bug reports, a well-argued source
proposal, or a small clean patch are all appreciated. The rules here are the
few things that keep the library honest and rebuildable across years of
intermittent attention. They aren't negotiable, but they aren't many.

The authoritative, unabridged version of everything below is
[`CLAUDE.md`](CLAUDE.md) and [`docs/architecture.md`](docs/architecture.md);
this file is the distilled house rules for outside contributors.

## The house rules

- **TDD is the workflow, not a suggestion.** Write the failing test first,
  then the code, then refactor. New behavior arrives with its test in the
  same change. A pull request whose suite is red is not ready — full stop.
- **Fixtures are small, real, trimmed upstream samples** (2–3 documents per
  source, trimmed but structurally intact), checked into git so they
  document actual upstream quirks. Never hand-write fake TEI/CoNLL-U. Every
  fixture directory carries a `README.md` with the retrieval date and URL,
  and any content license is quoted **verbatim** in that README — license
  honesty is a first-class invariant here, not a footnote.
- **New adapters must pass the shared conformance suite**
  (`test/support/adapter_conformance.rb`): manifest validity, discover→parse
  round-trip, URN uniqueness and stability across two parses, NFC output,
  non-empty passages, license class present. A new adapter is
  conformance-suite inclusion plus source-specific assertions — not a
  bespoke test file.
- **Small diffs.** One adapter, one parser family, or one CLI command per
  change. Please don't refactor opportunistically across the codebase while
  implementing a feature; a focused diff is a reviewable diff.
- **Ask before adding a gem.** The dependency budget is deliberately small
  (thor, sequel, sqlite3, nokogiri, faraday, rubocop, minitest, webmock).
  Open an issue and make the case before reaching for a new one.
- **Canonical is read-only.** Upstream text under `canonical/` is the
  permanent asset; application code never writes it except through an
  adapter's `fetch`. All SQLite is derived and must survive
  `nabu rebuild`. "Cleaning up" upstream text during parse — fixing typos,
  modernizing orthography — is out of bounds: canonical means canonical,
  corrections are enrichments.
- **No network in tests, ever.** WebMock blocks all HTTP in the suite;
  adapter tests run against the checked-in fixtures.

Run `bundle exec rake test` and `bundle exec rake lint` before you open a
pull request; both must be green. CI runs the same two commands on every
push and pull request, so there are no surprises.

## Developer Certificate of Origin (DCO)

The code is [MIT-licensed](LICENSE). By signing off on a commit you certify
that you wrote the contribution (or otherwise have the right to submit it)
and that you are contributing it under the project's MIT license, per the
[Developer Certificate of Origin](https://developercertificate.org/). Add
the sign-off with `git commit -s`, which appends a line to your commit
message:

```
Signed-off-by: Your Name <you@example.com>
```

Content licensing is separate and unchanged: every ingested text keeps its
own upstream license, recorded per document and labeled on every surface —
the DCO covers your contribution to the code, not the corpora it ingests.

## Proposing a new source

The best way to suggest a corpus is an issue that brings **license
evidence** — a link to the upstream grant, quoted verbatim, and the class it
falls into (`open` / `attribution` / `nc`). That's the pattern the axis
surveys already follow: see [`docs/oe-survey.md`](docs/oe-survey.md) and
[`docs/slavic-survey.md`](docs/slavic-survey.md) for evidence-cited,
license-honest rankings of candidates (including what's blocked and why).
A source with no verifiable open license can't be ingested, however
desirable — so lead with the license.

If a proposal is accepted, [`CLAUDE.md`](CLAUDE.md) and
[`docs/maintenance-and-extension.md`](docs/maintenance-and-extension.md)
walk the adapter checklist end to end.

## How Nabu is built

Nabu is developed by a model-tiered autonomous agent loop — work packets
executed under the TDD ground rules above, with owner-approved phase gates —
documented in [`docs/dev-loop.md`](docs/dev-loop.md).

## Security & support

There's no packaged release and no server exposed to untrusted input (the
MCP server is local, stdio-only, and structurally read-only), so there's no
formal security policy — please just open an issue for bugs, questions, or
anything that looks like a vulnerability, and flag security-sensitive
reports as such so they can be looked at first.
