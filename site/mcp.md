---
title: MCP — ask your model
permalink: /mcp/
description: >-
  The Nabu library as a read-only MCP server: eleven tools that let an AI
  assistant search, cite, align, and etymologize over the corpus — with
  desk-shaped examples run live against the library.
---

Everything the [command line](/nabu/tools/) can do for a reader, a
connected AI assistant can do in conversation: the library ships a
read-only [MCP server](https://github.com/arvicco/nabu/blob/main/docs/mcp.md)
(`bin/nabu mcp`) exposing eleven tools — `nabu_search`, `nabu_show`,
`nabu_define`, `nabu_etym`, `nabu_links`, `nabu_parallels`,
`nabu_cognates`, `nabu_align`, `nabu_concord`, `nabu_place`, and
`nabu_status`. Registration for Claude Code and Claude Desktop is in the
[server documentation](https://github.com/arvicco/nabu/blob/main/docs/mcp.md);
restricted material is excluded by default, license classes ride every
payload, and nothing is ever written.

## What asking looks like

The point is composition: a research question is usually two or three
tools, not one. Every example below — and every "Ask your model" block on
the [axis pages](/nabu/axis/) — was run live against this library before
it was written down; nothing is invented.

- **“Who quotes the opening of the Iliad?”** — `nabu_parallels` on
  Iliad 1.1 returns Galen, Aristotle's *Ars Rhetorica*, and Sextus
  Empiricus (seven loci) sharing μῆνιν ἄειδε, each with the matched
  phrase and a urn `nabu_show` opens in pristine text.
- **“Show me MARK 2.3 in every witness.”** — `nabu_align` returns
  fourteen columns at once: Greek, Latin, Gothic, Armenian, four Old
  Church Slavonic codices, Old English, Sahidic Coptic, English.
  `collate: true` turns them into an apparatus.
- **“Where does Gothic *guþ* come from?”** — `nabu_etym` walks it to
  Proto-Germanic *\*gudą* (64 cognates, nine attested here with counts)
  and the PIE ancestors above it.
- **“What survives from Segesta?”** — `nabu_place` resolves the
  gazetteer card (Pleiades 462487) and counts the library's holdings
  at that place, per source.
- **“Attestations of *šarru* 'king'?”** — `nabu_search` by lemma
  resolves the logogram LUGAL through ORACC's lemmatization; the first
  hits are the Cyrus Cylinder.

Each desk has its own examples — and its own conventions (Hittite is
typed syllabified, Old Japanese romanized) — on its axis page under
**Ask your model**.

## The desks

The [research axes](/nabu/axis/) index all twenty desks; every desk page
ends with live-verified MCP examples for that tradition.
