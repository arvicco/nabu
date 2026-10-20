---
name: nabu-library
description: "Cross-desk methodology for any research through the nabu MCP server: how documents, passages and urns relate, what the license classes oblige, how dates, lemma tiers, lects and kinds are typed, why search is folded but quotation must not be, and what to record so a claim can be checked later. Load before any desk-specific nabu skill."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, nabu_concord, nabu_align, nabu_define, nabu_etym, nabu_parallels, nabu_cognates, nabu_links, nabu_place, nabu_char, nabu_signs)."
metadata:
  origin: hand-tuned
---

# Reading a Nabu library — the house methodology

A Nabu library is a local, rebuildable catalog of ancient-text corpora, each
ingested by its own adapter from a named upstream edition. The MCP surface is
read-only. Every desk skill (`nabu-cuneiform`, `nabu-classical`, …) assumes the
rules below.

## The units

- **Document** — the unit upstream delivers (a tablet, an inscription, a papyrus,
  a work in one edition, a dictionary entry). **Passage** — its citable subunit
  (a line, a verse, a section, a sentence). Both carry a `urn`; CTS urns are used
  where upstream has them, `urn:nabu:<source>:…` otherwise.
- **The urn identifies an edition, not a work.** Two editions of the same work
  (or the same tablet in two corpora) are two documents with two urns. Never merge
  them silently, and never cite one for a reading found in the other.
- **Revisions are kept, nothing is deleted.** Changed upstream content bumps the
  passage's `revision`; content withdrawn upstream is flagged `withdrawn`;
  content whose file upstream removed stays live and is flagged
  `retired_upstream`. `nabu_show` serves all three states with their flags —
  report them when you cite.
- **`language`** is a BCP-47 tag with an ISO 639 primary subtag, as upstream's
  data supports it. The finer **lect** (a nabu-lects id such as `lat:med`, grammar
  `anchor[:stage][/variety][~script][@ortho]`) is a separate axis: the `lect`
  search filter matches by prefix (`lat:med` covers `lat:med/…`, never
  `lat:cla`) and errors when the registry is not synced on the box.

## License classes — data license is not code license

The guidance text in this pack is MIT. The texts it describes are not: every
passage carries `license_class`, a closed vocabulary.

| Class | What it means for your use |
| --- | --- |
| `open` | Public domain, CC0 or equivalent; cite anyway. |
| `attribution` | Reuse permitted with credit to the source edition (CC BY, CC BY-SA and similar; share-alike terms travel with the text). |
| `nc` | Non-commercial terms (CC BY-NC and its variants): quote for research and teaching; no commercial reuse; credit required. |
| `odbl` | Open Database License: credit the database; databases derived from it are share-alike. |
| `research_private` | Personal research grants and private holdings: **excluded by default**; returned only with `include_restricted: true`; never redistributed. |
| `restricted` | Excluded by default, as above. |

A document can carry a class different from its source's (per-document grants
exist), so read the class on the passage, not from memory. When a payload
carries a `credit` key, it is a grantor's display condition: keep it with the
quotation. Verbatim upstream terms for every source are in the repository's
`docs/02-sources.md`.

## Search versus quotation

- Matching runs over a **folded** form of the text: lower-cased, diacritics
  stripped, and per-language rules (Greek final sigma, Latin v/u and j/i,
  cuneiform separators, Han variant tables, and others). The pristine text is
  never altered.
- Quote only what `nabu_show` returns. Search snippets, concordance keywords
  and `nabu_parallels` phrases are evidence that a match exists, not
  quotable readings.
- **An empty result is not absence of evidence.** Before concluding a word or
  text is unattested, call `nabu_status`: the source may not be synced on this
  box, the language may be stored in another script or transliteration
  (Hittite syllabified, Old Japanese romanized), or the class may be excluded
  by default. A no-match response carries a coverage hint — read it.
- `nabu_links` returns only edges a batch run has already mined; an empty reply
  means "not covered by a batch", not "no parallel exists" — `nabu_parallels`
  discovers on the fly.

## Lemmas, dates, places, kinds — every axis is typed

- **Lemma tiers.** `gold` = verified annotation (treebanks, hand-lemmatized
  corpora), the only tier that counts as attestation. `silver` = upstream's own
  automatic lemmatization, always labeled. `equivalence` = gloss-level
  equivalents, never attestation. Corpus counts for gold and silver are reported
  side by side and must not be summed. Lemma search reaches only the
  lemmatized minority of the library.
- **Dates.** A dated document's primary row has a `date_class`: `artifact` (the
  object's own dating — a findspot dating, a manuscript date), `composition`
  (an attributed author- or work-era date), `edition` (a print or edition year —
  never the date of the text), `silver` (a tool estimate, used only where no
  upstream date exists). Years are signed (negative = BCE) with no year 0;
  ranges are `not_before`/`not_after` envelopes matched by overlap, and an era
  attribution has precision `era`. Filter with `date_basis` to keep classes
  apart; most of the library is undated, which is an absence, not a zero.
- **Places.** A captured findspot text and a namespaced place identity
  (`pleiades:…`, `tm:…`, `cigs:…`) are different claims; `nabu_place` reports
  id-linked holdings, registry-decided holdings and unlinked text mentions in
  separate, labeled counts. Place titles match exactly — no fuzzy matching.
- **Kinds.** The `kind` filter uses the house classification tree with family
  prefix matching. `unknown` is upstream's own "cannot determine" (a claim);
  `unmapped` is a raw upstream value not yet folded (a gap). Most documents carry
  no kind and drop out under the filter.

## Owner notes are not upstream

`nabu_show` and `nabu_define` may carry `notes`: the library owner's own
annotations on a urn. They are commentary, not edition text, and must be
attributed as such if used at all.

## Reproducibility

For every claim, record:

1. the passage or document `urn`, its `revision`, and any `withdrawn` /
   `retired_upstream` flag;
2. the `source` slug, the `license_class`, and the `credit` line when present;
3. the tool call with its exact arguments (filters change results);
4. the date of the `nabu_status` snapshot — holdings differ per box and change
   with every sync;
5. for counts, the tier (gold / silver) and the grain (passage, document).

Cite the upstream edition by name as well as the urn: the urn locates the text
in this library; the edition is what a reader without the library can check.
