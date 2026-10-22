# AGENTS.md

A pointer file for coding and research agents working with this repository.

## What Nabu is

Nabu is a local, license-honest library of the ancient world: a Ruby
pipeline that fetches openly licensed digital corpora of antiquity into
`canonical/` (plain files under git) and derives a SQLite catalog and
full-text index under `db/` from them. Every passage has a stable URN;
every document records its upstream license class. It runs on the
researcher's own disk — it is not a hosted service.

- Project site: https://arvicco.github.io/nabu/ (agent entry file:
  https://arvicco.github.io/nabu/llms.txt; the site as one plain-text file:
  https://arvicco.github.io/nabu/llms-full.txt)
- Cite: concept DOI [10.5281/zenodo.21361956](https://doi.org/10.5281/zenodo.21361956)
  (resolves to the latest release; see `CITATION.cff`)
- Code license: MIT (`LICENSE`). Ingested texts keep their upstream licenses.

## Where the documentation lives

- `docs/README.md` — the index and suggested reading order.
- `docs/architecture.md` — the system design (stores, pipeline, MCP server).
- `docs/conventions.md` — URNs, NFC, language codes, licensing, dates.
- `docs/02-sources.md` and `config/sources.yml` — every source, its
  upstream and its `license_class` (the registry is machine-readable).
- `docs/mcp.md` — the MCP server contract, tool by tool.
- `docs/manual/` — per-source and per-tool operating notes.
- `CLAUDE.md` — repository conventions for code changes (TDD, Minitest,
  `bundle exec rake test`, `bundle exec rake lint`, no network in tests).

## The MCP server

`bundle exec bin/nabu mcp` runs a read-only Model Context Protocol server
over stdio (JSON-RPC 2.0, newline-delimited). The repository's `.mcp.json`
registers it for project-scoped clients. The stores are opened read-only;
there are no write tools, and every tool is annotated `readOnlyHint: true`.
It answers from the local catalog — a box that has synced nothing has
nothing to serve.

| Tool | What it does |
| --- | --- |
| `nabu_search` | Full-text, lemma, morphology, gloss, proximity, fuzzy, translation and sense search, with language, license, date, place, script, kind and lect filters |
| `nabu_show` | Read by URN: one passage, a whole document, a range, or a parallel-aligned translation |
| `nabu_concord` | Keyword-in-context concordance rows over the corpus |
| `nabu_align` | One citation of a registered work rendered across every aligned witness |
| `nabu_define` | Dictionary lookup across the held lexica, citations resolved to passages |
| `nabu_etym` | Walk from an attested lemma to its reconstructed ancestors and their reflexes |
| `nabu_parallels` | Passages that quote or echo a given passage (intertext), with score decomposition |
| `nabu_cognates` | Aligned verses where two or more languages use reflexes of the same root |
| `nabu_links` | Batch-mined cross-reference edges touching a passage or document |
| `nabu_char` | The character / sign identity card for one glyph |
| `nabu_place` | One ancient place from the held gazetteers, with the library's holdings at that place per source |
| `nabu_signs` | Cuneiform transliteration resolved token by token into sign identities |
| `nabu_clarify` | Normalize a partial or misspelled work or passage reference to URNs |
| `nabu_status` | Coverage: sources, counts by language and license class, index state |

## License-class etiquette

Every passage the tools return carries `urn`, `language` and
`license_class` (most rows also carry the `source` slug). The classes are:

- `open` — public domain or CC0-equivalent.
- `attribution` — CC BY and CC BY-SA terms: credit the source edition; for
  share-alike sources, derivatives carry the same license.
- `nc` — non-commercial terms: no commercial reuse.
- `odbl` — Open Database License terms for database-derived material.
- `research_private` and `restricted` — excluded from every MCP tool by
  default; a caller opts in per call with `include_restricted: true` only
  when it will honor the restriction. Never republish these.

Agents must respect each text's class: preserve `urn`, `source`,
`license_class` and any `credit` field when quoting, check the source's
exact license line (`docs/02-sources.md`, `config/sources.yml`) before
reuse, and never strip attribution or mix classes in an export without
filtering. Derived datasets published in nabu-data carry their own terms.
