---
title: Quickstart
permalink: /quickstart/
description: >-
  From a fresh clone to the first aligned verse in minutes: prerequisites,
  the starter shelf, the first three commands, and how to grow the library.
---

Nabu is operated from the command line and lives entirely under its own
directory — plain files plus SQLite, no services. Initializing your own
library takes five steps; the starter shelf below was measured at about
**690 MB on disk** and a few minutes of syncing on the reference machine
(2026-07-13).

## Prerequisites

- **Ruby 3.3 or newer** and **git**. macOS (Apple Silicon) is the
  development platform; nothing in the core is known to be Mac-specific,
  but no other platform is exercised.
- **Disk**: about 1 GB for the starter shelf (canonical files plus the
  derived databases). A full library build currently occupies roughly
  16 GB canonical + 7 GB derived SQLite on the reference machine
  (2026-07-13) — growth is entirely at your discretion, shelf by shelf.

## 1. Clone

```
git clone https://github.com/arvicco/nabu
cd nabu
```

## 2. Install

```
bundle install
```

The dependency set is deliberately small (thor, sequel, sqlite3, nokogiri,
faraday, plus test tooling). Configuration is optional: every key in
`config/nabu.yml` has a working default, so a fresh checkout runs as-is.

## 3. Sync the starter shelf

```
bin/nabu quickstart
```

This syncs four curated sources — each through its normal fetch → load →
index path — and ends by printing the first three commands to try. The
set, with sizes measured from the live canonical tree on 2026-07-13:

| Source | What it is | On disk |
|---|---|---|
| `sblgnt` | SBL Greek New Testament (CC BY) | 11 MB |
| `proiel` | PROIEL treebank — the NT in Greek, Latin, Gothic, Armenian, and Old Church Slavonic, with gold lemma and morphology annotations (non-commercial research license) | 173 MB |
| `iswoc` | ISWOC treebank — the West-Saxon gospels, Old English (non-commercial research license) | 30 MB |
| `lexica` | LSJ and Lewis &amp; Short, the dictionary shelf (CC BY-SA) | 479 MB |

On the reference machine the four first syncs took roughly three minutes
of fetch-and-load combined (the `lexica` clone dominates at about two
minutes; `sblgnt` takes seconds); allow up to ten minutes on an ordinary
connection, including the per-source index rebuilds. The command is
idempotent — re-running it is an ordinary re-sync — and one source's
failure never stops the rest: failures are reported at the end.
`bin/nabu quickstart --list` prints the set without syncing anything.

## 4. First marvels

The starter shelf lights the library's three signature surfaces.

**One verse across seven witnesses.** `bin/nabu align "MARK 2.3"` renders
the same verse in Greek (twice — PROIEL and SBLGNT), Latin, Gothic,
Classical Armenian, Old Church Slavonic, and Old English, each with its
license label. From a live run (2026-07-11, on the reference box, whose
fuller library attests further witnesses beyond the starter seven):

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

… (Armenian, SBLGNT, the WEB English, Clementine Vulgate, and the four CCMH OCS witnesses trimmed)
```

**Search by dictionary form.** `bin/nabu search --lemma λέγω` finds every
inflected attestation over the gold treebank annotations — λέγουσι,
λέγοιεν, and the suppletive εἶπας/εἰπεῖν that no surface-string query can
reach. Diacritics are optional on the query.

**Open the dictionary.** `bin/nabu define λόγος` prints the whole LSJ
entry, with its citations resolved to passages in your own catalog where
the corpus holds them (`nabu show <urn>` opens the cited line); `bin/nabu
define virtus` does the same in Lewis &amp; Short.

## 5. Connect your AI tools

The repository ships `.mcp.json`, so opening the directory in Claude Code
registers the read-only MCP server automatically — the assistant can
search, read, align, and define against everything you have synced, every
passage carrying its license class, while remaining structurally unable to
write to the library. Registration recipes for Claude Desktop and other
clients, the tool reference, and the quoting etiquette are in
[docs/mcp.md](https://github.com/arvicco/nabu/blob/main/docs/mcp.md).

## Grow the library

Each further shelf is one `sync` command; `bin/nabu sync --all` re-syncs
every enabled live-policy source in one pass. The full menu is
`config/sources.yml`; real on-disk sizes for the larger shelves, measured
2026-07-13:

| Sync | Unlocks | Canonical size |
|---|---|---|
| `bin/nabu sync vulgate` + `sync eng-web` | the Clementine Latin and English witnesses for `align`, Old Testament included | 357 MB each |
| `bin/nabu sync perseus-greek` | the Greek canon with aligned English translations | 910 MB |
| `bin/nabu sync perseus-latin` | the Latin classics | 220 MB |
| `bin/nabu sync gretil` | 780 Sanskrit editions | 303 MB |
| `bin/nabu sync papyri-ddbdp` | 61k documentary papyri | 2.3 GB |
| `bin/nabu sync oracc` | 21k cuneiform documents | 4.1 GB |

What each shelf is good for is surveyed on [The Library]({{ '/library/' | relative_url }});
every text keeps its upstream license, recorded per document — the classes
and per-source terms are on [Sources &amp; Licensing]({{ '/sources/' | relative_url }}).
The non-commercial shelves are for research use and are never
redistributed by the tooling.

The same walkthrough, kept in the repository alongside the code, is
[docs/quickstart.md](https://github.com/arvicco/nabu/blob/main/docs/quickstart.md).

## Your desk

The starter shelf is running; the natural next move is to find the desk for
your own field. `bin/nabu list --axis` prints the shelf census grouped under
the eighteen [research desks]({{ '/axis/' | relative_url }}) — scholarly hats
over the same sources, from the Classicist to the Assyriologist. Pick the one
that fits and sync its members in a single command — `bin/nabu sync celtic`,
or whichever axis is yours — then open its page: each desk carries its own
member shelves, CLI recipes, search modes, and terminal setup for its scripts.

```
bin/nabu list --axis        # the shelf census, grouped by research desk
bin/nabu axis celtic        # one desk's card: members, holdings, gold coverage
bin/nabu sync celtic        # sync that desk's enabled members
```
