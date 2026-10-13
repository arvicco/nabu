---
title: About
permalink: /about/
description: >-
  What Nabu is, why it exists, how it is built, and how to reach the
  maintainer.
---

{% assign census = site.data.census -%}
## What this is

Nabu is **personal research infrastructure**: one scholar's local library
of ancient-text corpora, built to serve that scholar's reading and research
first, and shared because the approach — local, license-honest, citation
native, rebuildable — may be useful to others: the readers it pictures wear
one of {{ census.desks }} scholarly hats, the [research desks]({{ '/axis/' | relative_url }})
from the Classicist to the Assyriologist, each with its own shelves and
recipes. It is a young project:
versioned releases begin with v1.0.0 (July 2026), there is no packaged
gem or versioned API, and command-line flags may still change between
releases; the documentation aims to be more honest than polished.

The name is that of the Mesopotamian god of scribes and writing, divine
custodian of the library of Ashurbanipal at Nineveh — a fitting patron for
a project whose founding dream included holding the tablets themselves
(the ORACC shelf now does).

## The project family

Nabu is the eldest of five siblings, each with one job; where a sibling
produces something the library can use, Nabu consumes it back as an
ordinary optional module — the same ingestion door every external source
walks through.

- **[Nabu](https://github.com/arvicco/nabu)** — the library itself: the
  canonical texts, the catalog, the query tools, this site.
- **[nabu-data](https://github.com/arvicco/nabu-data)** (the **Data ↗**
  link above) — the publishing arm: **twenty-five datasets** as of its
  v1.3.0 release (September 2026), from form-to-lemma tables and
  orthography folds to metrical
  scansions, a Tibetan segmentation layer, the cuneiform value-to-sign
  table, the re-publications (stable anchors for ACTib's segmented
  Tibetan canon; the first machine-readable edition of the complete
  secular Galician-Portuguese lyric), and the whole-catalog corpus
  layers: per-document historical-stage assignments and document-kind
  classifications, normalized datings, gazetteer-ready place references
  with a Linked Places Format export, the character frequency census,
  compiled cuneiform sign cards with real attestation counts and their
  sense glosses, the Egyptian hieroglyph spine with its frequency
  census, and the curated language and script dossiers. Plain CSV
  with Frictionless Data Package manifests carrying full derivation
  provenance and measured quality in-band; CC BY 4.0 with stated
  share-alike carve-outs; archived with a version DOI under concept
  [10.5281/zenodo.21757475](https://doi.org/10.5281/zenodo.21757475).
  Several of the datasets — the Sanskrit form-to-lemma table, the
  Tibetan verb and segmentation layers, the language dossiers — feed the
  library's own query surfaces back from the published files.
- **[nabu-lects](https://arvicco.github.io/nabu-lects)** (the **Lects ↗**
  link above) — the first registry sibling (August 2026, CC BY 4.0,
  versioned releases since v1.0): a curated registry of *lects* — language varieties as genealogical
  anchor × historical stage × variety × script × orthography — with a
  universal
  mapping from standard language codes onto them. Born from this
  library's holdings, universal by construction; Nabu consumes it for
  the stage ladders, stage-aware search, and reconstruction honesty
  described on the [Languages]({{ '/languages/' | relative_url }}) page.
- **[nabu-places](https://arvicco.github.io/nabu-places)** (the
  **Places ↗** link above) — the second registry sibling (August 2026,
  CC BY 4.0): a curated registry of *place-matching decisions* — which
  gazetteer identity (Pleiades, Trismegistos Geo, CIGS, GeoNames, and
  since autumn 2026 CHGIS, NRCT and al-Ṯurayyā) each
  source's verbatim place-name string denotes, with *unlocatable* and
  *region* as first-class answers — plus a native lane for minting
  evidence-backed place records where scholarship establishes a place no
  gazetteer registers. Nabu consumes it to turn hundreds of thousands of
  named-but-unlinked documents into place-queryable ones.
- **[Edubba](https://arvicco.github.io/nabu-edubba)** (the **School ↗**
  link above) — the scribal school: where Nabu curates the texts, Edubba
  teaches the scripts, consuming the library's sign-resolution contract
  for its reading panels — and its curated course overlay rides back
  onto the library's hieroglyph cards.

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
3. **License terms are data.** Aggregating
   {{ census.live_sources }} sources under dozens of
   different licenses is workable only if every text's terms are recorded
   per document and consulted mechanically — especially once AI tools can
   quote from the collection.

## How it is built

Nabu is a Ruby command-line application (Ruby 3.3+), developed and tested
on macOS, with a deliberately small dependency set and no cloud
requirements at runtime. Storage is plain files, git, and SQLite — nothing
that cannot be restored from a file copy.

The central engineering guarantee is **the derivability law**: everything
permanent lives in three plain-file folders — the canonical texts (the
universal asset), the project configuration, and the local instance
(the owner's rulings, annotations, and operational ledger) — and every
database is derived from them: `nabu rebuild` regenerates the entire
catalog offline, proven byte-identical by test, and a dedicated drill
proves the stronger claim by restoring ONLY those three folders and
re-deriving the rest from scratch. Around that guarantee sit the
retention mechanisms: files an upstream deletes are preserved and remain
searchable, honestly labelled; the run-history ledger rides in the
permanent set and survives rebuild and restore alike; backups are
exercised by the actual restore drill, not assumed; and a standing
verification command re-parses every canonical file against the
catalog's content hashes.

Development proceeds by a documented agent loop — work packets executed by
Claude language models under test-driven ground rules, with owner-reviewed
phase gates — described in
[docs/dev-loop.md](https://github.com/arvicco/nabu/blob/main/docs/dev-loop.md).
The full test suite (network-blocked, fast) and a linter run in continuous
integration on every push; the repository README and this site are
refreshed at every gate to reflect what actually works.

## What is deliberately out of scope, for now

The original concept's enrichment layer has been landing piece by piece,
always on-box: ingestion of one's own PDFs and scans shipped in July 2026
(`nabu ingest`), September 2026 brought semantic search over a local
vector store (`nabu embed`, `search --similar`) and local lemmatization
campaigns that project machine-suggested lemmas, honestly labelled
*silver*, onto passages without gold annotation (`nabu lemma-enrich`),
and October 2026 added the research-export surface (`nabu export`,
every table shipped with a license manifest), lemma attestation
profiles from precompiled rollups (`nabu lemma`), and a parallel
shelf for machine-suggested *datings* under the same silver
discipline (`nabu silver-dates`).
What still waits — on local inference hardware and on demand — is
on-demand glossing and text recognition for image-only scans; no paid
cloud service is ever a runtime requirement.
A public read-only query endpoint is a distant possibility for which the
MCP server is the rehearsal: the tool contract that would face outward
runs locally first, against the real corpus, under the same license gates.
The register of candidate capabilities, each argued with the case against,
is
[docs/improvements.md](https://github.com/arvicco/nabu/blob/main/docs/improvements.md).

## Licensing

- **Code:** [MIT](https://github.com/arvicco/nabu/blob/main/LICENSE).
- **Data:** every ingested text keeps its upstream license, recorded per
  document; the site's [Sources]({{ '/sources/' | relative_url }})
  page carries the full inventory. The data licenses belong to the upstream
  projects, not to Nabu.

## Contributing

The project is early and personal — expect the backlog to be driven by the
maintainer's research needs — but contributions are genuinely welcome:
a well-argued source proposal that leads with license evidence, a report
of a passage where the library's text departs from the source, a feature
request stated as the scholarly question it would answer, or a small clean
adapter patch with real trimmed upstream fixtures. The house rules — TDD,
fixture discipline, license honesty, the DCO sign-off — are stated in
[CONTRIBUTING.md](https://github.com/arvicco/nabu/blob/main/CONTRIBUTING.md).

Requests go straight to a prepared issue form:

- [Request a source](https://github.com/arvicco/nabu/issues/new?template=request-a-source.md)
  — upstream name and URL, the license as far as known (quoted verbatim),
  which reader or axis it serves, size if known.
- [Request a feature](https://github.com/arvicco/nabu/issues/new?template=feature-request.md)
  — the scholarly task first: what question can you not ask today.
- [Report a wrong reading](https://github.com/arvicco/nabu/issues/new?template=wrong-reading.md)
  — the URN, what nabu shows, what the source shows, the edition context.

Anything else fits a
[new issue](https://github.com/arvicco/nabu/issues/new/choose) of any
shape.

**Cite it:** concept DOI [10.5281/zenodo.21361956](https://doi.org/10.5281/zenodo.21361956), which always resolves to the latest release (v1.6.0, September 2026, as of this writing; v1.0.0 is [10.5281/zenodo.21361957](https://doi.org/10.5281/zenodo.21361957)); see the FAQ for the full citation form.

## Contact

Questions, corrections, and conversation are welcome through
[GitHub issues](https://github.com/arvicco/nabu/issues). The maintainer is
Ar Vicco &lt;[arvicco@nabu.ac](mailto:arvicco@nabu.ac)&gt;.
