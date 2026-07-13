---
title: About
permalink: /about/
description: >-
  What Nabu is, why it exists, how it is built, and how to reach the
  maintainer.
---

## What this is

Nabu is **personal research infrastructure**: one scholar's local library
of ancient-text corpora, built to serve that scholar's reading and research
first, and shared because the approach — local, license-honest, citation
native, rebuildable — may be useful to others. It is a young,
early-development project. There is no packaged release, no versioned API,
and command-line flags may still change; the documentation aims to be more
honest than polished.

The name is that of the Mesopotamian god of scribes and writing, divine
custodian of the library of Ashurbanipal at Nineveh — a fitting patron for
a project whose founding dream included holding the tablets themselves
(the ORACC shelf now does).

## Why it exists

Three convictions, stated plainly:

1. **Scholars should be able to hold their sources.** The great digital
   corpora live on institutional servers with uncertain funding horizons.
   A local, plain-file copy under version control, with derived databases
   that can always be regenerated, is the difference between using a
   service and owning a library.
2. **Citations are the unit of scholarship.** A search result that cannot
   be cited to a verse, a folio line, or a tablet surface is a curiosity.
   Everything in Nabu resolves to a stable URN.
3. **License terms are data.** Aggregating two dozen sources under a dozen
   different licenses is workable only if every text's terms are recorded
   per document and consulted mechanically — especially once AI tools can
   quote from the collection.

## How it is built

Nabu is a Ruby command-line application (Ruby 3.3+), developed and tested
on macOS, with a deliberately small dependency set and no cloud
requirements at runtime. Storage is plain files, git, and SQLite — nothing
that cannot be restored from a file copy.

The central engineering guarantee is **rebuild-from-canonical**: upstream
texts live as plain files in a git-tracked canonical layer, which is the
permanent asset; every database is derived from it, and `nabu rebuild`
regenerates the entire catalog from canonical data — proven byte-identical
by test. Around that guarantee sit the retention mechanisms: files an
upstream deletes are preserved and remain searchable, honestly labelled; a
run-history ledger survives every rebuild; backups are exercised by an
actual restore drill, not assumed; and a standing verification command
re-parses every canonical file against the catalog's content hashes.

Development proceeds by a documented agent loop — work packets executed by
Claude language models under test-driven ground rules, with owner-reviewed
phase gates — described in
[docs/dev-loop.md](https://github.com/arvicco/nabu/blob/main/docs/dev-loop.md).
The full test suite (network-blocked, fast) and a linter run in continuous
integration on every push; the repository README and this site are
refreshed at every gate to reflect what actually works.

## What is deliberately out of scope, for now

The original concept includes an enrichment layer — projecting lemmas onto
the ninety percent of the corpus without gold annotation, embeddings and
semantic search, on-demand glossing, ingestion of ad-hoc scans — that is
designed but not built; it waits on local inference hardware and demand.
A public read-only query endpoint is a distant possibility for which the
MCP server is the rehearsal: the tool contract that would face outward
runs locally first, against the real corpus, under the same license gates.
The register of candidate capabilities, each argued with the case against,
is
[docs/improvements.md](https://github.com/arvicco/nabu/blob/main/docs/improvements.md).

## Licensing

- **Code:** [MIT](https://github.com/arvicco/nabu/blob/main/LICENSE).
- **Data:** every ingested text keeps its upstream license, recorded per
  document; the site's [Sources &amp; Licensing]({{ '/sources/' | relative_url }})
  page carries the full inventory. The data licenses belong to the upstream
  projects, not to Nabu.

## Contact

Questions, corrections, and conversation are welcome through
[GitHub issues](https://github.com/arvicco/nabu/issues). The project is
early and personal — expect the backlog to be driven by the maintainer's
research needs — but the house rules for outside contributions are stated
in
[CONTRIBUTING.md](https://github.com/arvicco/nabu/blob/main/CONTRIBUTING.md).
