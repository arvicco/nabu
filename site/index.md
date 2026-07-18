---
title: Home
permalink: /
description: >-
  Nabu gathers openly licensed digital corpora of the ancient world into one
  local, searchable, citable library, with a read-only interface for AI tools.
---

Nabu is a piece of personal research infrastructure that gathers the world's
openly licensed digital corpora of antiquity — Homer and the Greek canon, the
Latin classics, the documentary papyri of Egypt, the Latin inscriptions of
the Roman empire, the Sanskrit tradition and the Pali canon, cuneiform
tablets, three millennia of Egyptian sentences, the Masoretic Hebrew Bible
with its Targums, the inscriptions of pre-Roman Italy and Sicily, the New
Testament in up to fifteen parallel witnesses, the
complete corpus of Old English poetry — into a single library on the
scholar's own disk. Everything is stored as plain files plus SQLite: it is
searchable by word or by dictionary lemma, citable to the exact verse or
tablet line, explicit about every text's license, and rebuildable from its
canonical sources at any time. Because the library also exposes a read-only
[Model Context Protocol server](https://github.com/arvicco/nabu/blob/main/docs/mcp.md),
the AI assistants a researcher already uses can search, quote, and cite the
whole collection while remaining structurally unable to alter a letter of it.

The project takes its name from the Mesopotamian god of scribes, patron of
the tablet house and divine custodian of Ashurbanipal's library. It is
neither a website nor a reading application: it is a pipeline and a database,
operated from the command line, and designed to outlive the services it
draws from.

## The holdings, in brief

As of **17 July 2026**, the catalog records **172,189 documents** comprising
**4,308,814 passages** in some two dozen ancient languages — from
proto-cuneiform tablets of the late fourth millennium BCE to
nineteenth-century Slovenian, with Gaulish inscriptions and Irish ogham
stones the newest arrivals — together with **633,137 dictionary entries**
on the reference shelf and over **2.85 million gold-standard lemma
annotations in seventeen languages**. All figures on this site are read
from the live catalog, never estimated, and carry the date on which they
were read.

A survey of the collections is given on [The Library]({{ '/library/' | relative_url }})
page; the full attribution and licensing record is on
[Sources &amp; Licensing]({{ '/sources/' | relative_url }}).

## A single verse, many witnesses

One illustration, pasted from a live run (12 July 2026; trimmed lines are
marked). A single Gospel citation rendered across the aligned witnesses —
Greek, Latin, Gothic, Old Church Slavonic, Old English, and more — each
carrying its license label. Since this run, the Sahidic and Bohairic
Coptic New Testaments have joined the hub (13 July 2026), bringing the
registered witnesses to fifteen:

```
$ bin/nabu align "MARK 2.3"
MARK 2.3 — New Testament (parallel witnesses)
  13 of 13 witnesses attest this ref

greek-nt — The Greek New Testament [grc]   license: nc
  urn:nabu:proiel:greek-nt:6563
    καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων.

latin-nt — Jerome's Vulgate [lat]   license: nc
  urn:nabu:proiel:latin-nt:10368
    et venerunt ferentes ad eum paralyticum qui a quattuor portabatur

gothic-nt — The Gothic Bible [got]   license: nc
  urn:nabu:proiel:gothic-nt:37435
    jah qemun at imma usliþan bairandans, hafanana fram fidworim.

marianus — Codex Marianus [chu]   license: nc
  urn:nabu:proiel:marianus:36421
    Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми.

wscp — West-Saxon Gospels [ang]   license: nc
  urn:nabu:proiel:wscp:102359
    & hi comon anne laman to him berende, þone feower men bæron.

WEB (English) — Mark [eng]   license: open
  urn:nabu:eng-web:mrk:2.3
    Four people came, carrying a paralytic to him.

… (Armenian, SBLGNT, Clementine Vulgate, and the four CCMH OCS witnesses trimmed)
```

Every result is a resolvable citation — a stable URN pointing into the local
catalog — rather than an unverifiable quotation. The same discipline governs
all of the [tools]({{ '/tools/' | relative_url }}): dictionary citations
resolve to live passages, intertext hits name the shared phrase, and every
surface carries its license class.

## Principles

- **License honesty.** Every ingested text keeps its upstream license,
  recorded per document and displayed on every surface. Roughly 99% of
  documents are public-domain or attribution-class; non-commercial and
  no-derivatives materials are handled under correspondingly stricter rules.
  See [Sources &amp; Licensing]({{ '/sources/' | relative_url }}).
- **Longevity over convenience.** Upstream projects restructure, lose
  funding, and disappear. The canonical layer is plain files under git; all
  databases are derived and rebuildable; texts an upstream deletes are
  retained, honestly labelled. Storage is deliberately boring: files, git,
  SQLite.
- **Citations, not summaries.** The unit of work is the citable passage.
  Search results, dictionary entries, alignment rows, and machine-readable
  exports all carry stable URNs.
- **Measured claims.** Corpus numbers are snapshots of one live
  installation, dated where they appear.

## Where to go next

- [The Library]({{ '/library/' | relative_url }}) — what is on the shelves:
  collections, periods, sizes, licenses.
- [Tools]({{ '/tools/' | relative_url }}) — the command-line instruments,
  organized by scholarly task.
- [Examples]({{ '/examples/' | relative_url }}) — worked walk-throughs for a
  classicist, a papyrologist, a slavist, a comparativist, an assyriologist,
  and a biblical scholar.
- [About]({{ '/about/' | relative_url }}) — what this project is, who it is
  for, and how it is built.
