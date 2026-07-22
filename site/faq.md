---
title: FAQ
permalink: /faq/
description: >-
  Frequently asked questions about Nabu: getting started, the collections,
  licensing and use, AI assistants, contributing, and contact.
---

Short answers to the questions newcomers ask most, each pointing at the
page or repository document that carries the full context.

## Getting started

### What is Nabu, and who is it for?

Nabu is personal research infrastructure: a local, searchable, citable
library of ancient-text corpora — the Greek and Latin canons, documentary
papyri, cuneiform, Sanskrit, Old English, the Slavic canon, and more —
built for scholars who want to hold their sources rather than query a
service. It is a command-line pipeline and database, not a website or a
reading application. What it is and why it exists is set out on
[About]({{ '/about/' | relative_url }}); worked walk-throughs for ten
scholarly personas are on [Examples]({{ '/examples/' | relative_url }}), and
the full set of eighteen [research desks]({{ '/axis/' | relative_url }}) —
one scholarly hat per field, each with its own shelves and recipes — is the
reader's-eye map of the whole collection.

### How do I try it in minutes?

Clone the repository, run `bundle install`, then `bin/nabu quickstart` —
one command that syncs a curated four-source starter shelf (about 690 MB
on disk, measured 2026-07-13) and prints the first commands to try:
a Gospel verse aligned across seven witnesses, search by dictionary
lemma, and a full LSJ entry with resolved citations. The complete
walkthrough is [Quickstart]({{ '/quickstart/' | relative_url }}).

### What does it need?

Ruby 3.3 or newer, git, and disk space: about 1 GB covers the starter
shelf (canonical files plus derived databases), while a full library
build occupied roughly 45 GB canonical plus 43 GB derived SQLite on the
reference machine as of 2026-07-22 — growth is entirely at your
discretion, shelf by shelf. There are no cloud requirements at runtime
and the dependency set is deliberately small. Details and per-shelf
sizes are on [Quickstart]({{ '/quickstart/' | relative_url }}).

### Which platforms does it run on?

macOS (Apple Silicon) is the development platform, and the honest answer
is that no other platform is exercised. Nothing in the core is known to
be Mac-specific — it is plain Ruby, git, and SQLite — but Linux and
Windows users should expect to be the first to try. A report either way
is welcome as a [GitHub issue](https://github.com/arvicco/nabu/issues).

### Does it work offline?

Yes, once a shelf is synced: fetching a source needs the network, but
everything after — search, alignment, dictionary lookup, the MCP
server — runs against local files and local SQLite with no network
access at all. The library is designed to outlive the services it draws
from, so offline operation is a design goal rather than a side effect;
see the principles on the [home page]({{ '/' | relative_url }}).

### Why does Hebrew (or pointed, accented text) look wrong in my terminal?

Two layers are involved, and only one is Nabu's. Nabu's display layer
(`config/display.yml`, the `--display` flag) decides which marks to draw:
by default it strips Hebrew cantillation accents and Old Church Slavonic
titla at render time — announced in a footer, with `--display full` always
showing every stored byte, and the stored text itself never altered. Text
direction and fonts, though, belong to the terminal: iTerm2 has an
experimental right-to-left toggle (Settings → General → Experimental),
macOS Terminal.app has no bidi support at all, and pointed Hebrew wants a
scholarly font such as Ezra SIL. The full setup guide — what Nabu strips,
what the terminal must do, and a per-script table — is
[docs/display.md](https://github.com/arvicco/nabu/blob/main/docs/display.md).

### How does Nabu relate to Perseus and Scaife?

It complements rather than competes: Perseus and the Scaife Viewer are
reading environments served from institutional infrastructure, while
Nabu ingests Perseus's openly licensed editions (among some two dozen
other corpora) into a library on your own disk, under one query surface,
one citation scheme, and one license model. If Perseus restructures or
goes offline, a Nabu library keeps working. The shelf survey is on
[The Library]({{ '/library/' | relative_url }}).

## The library

### What is included?

As of 22 July 2026 (late): 810,254 documents and 62,807,983 passages across 83
registered, synced sources, plus 1,310,763 dictionary entries and
16.2 million gold
lemma annotations in twenty-eight languages — the Islamicate library
(OpenITI, the corpus's largest holding — Classical Arabic and Persian,
added 22 July 2026), the classical Chinese library and the Buddhist
canon, classical
Greek and Latin, papyri, Latin inscriptions, cuneiform and the Ancient
Near East, Sanskrit and the Pali canon, Hebrew and Aramaic, Egyptian,
Coptic, Japanese, Old English and the wider Germanic wave (Old Norse,
Old Saxon, Middle High German, and the runestones, added 22 July 2026),
Slavic, Celtic, biblical editions, and a reference shelf of fifty-six
dictionary shelves. The
full survey is [The Library]({{ '/library/' | relative_url }}); the
authoritative living inventory is
[docs/library.md](https://github.com/arvicco/nabu/blob/main/docs/library.md).
On your own install, `bin/nabu list --sources` prints the one-page
version: every source with a one-line description, grouped by language
family.

### Why is the TLG (or Brill, or another paywalled resource) not included?

Licensing, plainly: the TLG is a subscription service with no export or
redistribution grant, and Brill's dictionaries are in copyright (the
de Vaan etymological shelf, for instance, carries only the linked-data
skeleton its publisher permitted, not the entries). Nabu ingests only
sources with a verifiable open or research-usable license, and records
the blocked ones honestly, with the specific terms and possible unlock
paths, in
[docs/02-sources.md](https://github.com/arvicco/nabu/blob/main/docs/02-sources.md).
Requests for anything openly licensed are genuinely welcome —
[request a source](https://github.com/arvicco/nabu/issues/new?template=request-a-source.md),
leading with the license evidence.

### Can I add my own texts and PDFs?

Yes, since 14 July 2026: `nabu ingest FILE` files your own material —
scanned grammars, offprints, articles — into a local-library shelf; it
also accepts http(s) URLs, downloading first and recording the address
in the catalogue entry. The
file is copied in (never moved), metadata is derived mechanically and
confirmed interactively, with AI assistance, or fully scripted; the
document is then catalogued, page-cited where it carries a text layer,
and searchable beside the rest of the library. Everything on this shelf
defaults to the strictest access class (`research_private`): it is never
served to AI clients without an explicit opt-in and never redistributed.
The command is described under Stewardship on
[Tools]({{ '/tools/' | relative_url }}); for a *structured corpus* the
better path is still a per-source adapter, per
[CONTRIBUTING.md](https://github.com/arvicco/nabu/blob/main/CONTRIBUTING.md).

### How current are the sources kept?

Per source, by posture: live sources re-fetch on every sync
(non-destructively — texts an upstream deletes are retained and
honestly labelled), completed datasets are refetched manually and
deliberately, and frozen upstream releases are never expected to change.
`nabu health` checks the collection's invariants, and its remote probes
watch upstream reachability and license drift between syncs. The
posture and license of every source are on
[Sources &amp; Licensing]({{ '/sources/' | relative_url }}); operations are
documented in
[docs/ops.md](https://github.com/arvicco/nabu/blob/main/docs/ops.md).

### What happens when I sync a source?

Four things, in order: the upstream snapshot is fetched into the
canonical store non-destructively (anything upstream deleted is kept in
an attic, and a circuit-breaker aborts a sync that would gut the
source); every document is parsed and upserted into the catalog by its
URN, with malformed files quarantined and counted rather than silently
dropped; whatever the source derives — dictionary entries, reference
links, annotations — is refreshed; and the search indexes are brought
up to date incrementally, touching only that source's rows rather than
re-indexing the whole collection. The sync's report says exactly what
changed, down to the per-source indexed count. Syncing a notes or
dossier shelf is instant, because those shelves feed no search index —
there is simply no index work to do. A full re-index from scratch
remains available as `nabu rebuild`, which regenerates the entire
database from canonical data.

## Licenses and use

### What do the license classes mean?

Every document carries one of four classes, recorded at ingestion and
shown on every surface. `open` is public domain or CC0 — no
restrictions; `attribution` is the CC BY / CC BY-SA family —
redistributable with credit (together with `open`, roughly 99% of
documents); `nc` is the CC BY-NC-SA family — licensed for
non-commercial research use and never redistributed by the tooling;
`research_private` covers terms stricter than all of these (CC BY-ND,
scholarly-use grants without a redistribution clause) — held for
personal research only. The full model is on
[Sources &amp; Licensing]({{ '/sources/' | relative_url }}).

### Can I redistribute texts I got through Nabu?

It depends on the passage's class, which is labelled on every search
hit, alignment row, and export precisely so this is never guesswork.
`open` texts: yes, freely; `attribution` texts: yes, crediting the
upstream edition per its terms (share-alike where the license says so);
`nc` and `research_private` texts: no — they are for your own research,
and the tooling itself never redistributes anything. Per-source terms
are on [Sources &amp; Licensing]({{ '/sources/' | relative_url }}) and in
[docs/02-sources.md](https://github.com/arvicco/nabu/blob/main/docs/02-sources.md).

### Is this a commercial product?

No. The code is [MIT-licensed](https://github.com/arvicco/nabu/blob/main/LICENSE),
nothing is paid, and no one's data is hosted or resold — the data
licenses belong to the upstream projects, not to Nabu. The `nc` and
`research_private` classes exist so that restricted grants are
technically enforced in the software, not merely promised. See
[About]({{ '/about/' | relative_url }}).

### What does Nabu store, and where?

A verbatim canonical copy of each synced source, as plain files under
git, plus derived SQLite databases — all under the library's own
directory on your machine. Nothing leaves that machine: there is no
telemetry, no account, and no server component beyond the local,
read-only MCP process you may choose to run. The storage design is
described under "How it is built" on
[About]({{ '/about/' | relative_url }}).

## AI

### How do AI assistants use the library?

Through a local Model Context Protocol (MCP) server, which exposes the
library's tools — search, retrieval by URN, alignment, dictionary
lookup, the etymology walk, intertext — to clients such as Claude Code
and Claude Desktop. The surface is structurally read-only (the SQLite
engine itself is opened read-only), and every passage in every response
carries its URN, language, and license class, so an assistant can quote
and cite but never alter or launder a text. Registration recipes and
the tool reference are in
[docs/mcp.md](https://github.com/arvicco/nabu/blob/main/docs/mcp.md).

### Which content is excluded from AI serving, and why?

The `research_private` and `restricted` classes are excluded from every
MCP tool by default — they never appear in search results and retrieval
withholds them — because material held under scholarly-use or
no-derivatives grants (the Freising Manuscripts edition, for instance)
should not surface casually in a conversation. A caller who understands
and will honor the terms can opt in per call. The stance is specified in
[docs/mcp.md](https://github.com/arvicco/nabu/blob/main/docs/mcp.md);
the classes themselves are explained on
[Sources &amp; Licensing]({{ '/sources/' | relative_url }}).

### Was Nabu built with AI assistance?

Yes, extensively: development proceeds by a documented agent loop —
work packets executed by Claude language models under test-driven
ground rules, with owner-reviewed phase gates — and all code, including
every ingestion adapter, is open for inspection in the repository. The
process is described in
[docs/dev-loop.md](https://github.com/arvicco/nabu/blob/main/docs/dev-loop.md)
and summarized on [About]({{ '/about/' | relative_url }}).

## Contributing and contact

### How do I request a corpus or feature, or report a wrong reading?

Each request has a prepared GitHub issue form:
[request a source](https://github.com/arvicco/nabu/issues/new?template=request-a-source.md)
(lead with the license evidence, quoted verbatim),
[request a feature](https://github.com/arvicco/nabu/issues/new?template=feature-request.md)
(the scholarly question first), and
[report a wrong reading](https://github.com/arvicco/nabu/issues/new?template=wrong-reading.md)
(the URN, what nabu shows, what the source shows). Anything else fits a
[new issue](https://github.com/arvicco/nabu/issues/new/choose) of any
shape; the house rules are in
[CONTRIBUTING.md](https://github.com/arvicco/nabu/blob/main/CONTRIBUTING.md).

### How do I cite Nabu?

The repository carries citation metadata in
[CITATION.cff](https://github.com/arvicco/nabu/blob/main/CITATION.cff),
and versioned releases begin with v1.0.0 (July 2026) — cite the tagged
version you used, or the site and repository with your access date:
*Nabu: a local library of the ancient world*,
https://arvicco.github.io/nabu (repository:
[github.com/arvicco/nabu](https://github.com/arvicco/nabu)), adding the
version tag or commit hash where precision matters. Each release carries a DOI —
v1.0.0: [10.5281/zenodo.21361957](https://doi.org/10.5281/zenodo.21361957). Texts you quote *from* the library should be
cited to their upstream editions, which every passage's URN and license
label identify — see
[Sources &amp; Licensing]({{ '/sources/' | relative_url }}).

### Who maintains it?

Ar Vicco &lt;[arvicco@nabu.ac](mailto:arvicco@nabu.ac)&gt;, whose research
needs drive the backlog. Questions, corrections, and conversation are
welcome through
[GitHub issues](https://github.com/arvicco/nabu/issues); more on the
project's shape and history is on
[About]({{ '/about/' | relative_url }}).
