---
title: Layers
permalink: /layers/
description: >-
  The add-on layers of the Nabu library — when a document was written,
  where it comes from, and what kind of text it is — one doctrine
  (extracted, never guessed), three sub-sections, every layer
  composable in search.
---

{% assign census = site.data.census -%}
Every document in the library carries its text and its language. Three
**add-on layers** answer the other questions a reader brings to it:
**when** was this written, **where** does it come from, and **what
kind** of text is it? The layers share one doctrine:

- **Extracted, never guessed** — every claim is read from what the
  source actually ships (a date attribute, a findspot, a genre label),
  and what resists an honest parse stays visibly unclaimed.
- **Honesty buckets are first-class** — "undated", "unmatched",
  "unmapped" and upstream's own "cannot determine" are counted answers,
  never silent gaps.
- **Derived and rebuildable** — all three layers regenerate from the
  canonical sources on every rebuild; the upstream claim is preserved
  verbatim beside every fold.
- **Composable** — each layer is a search filter, and they stack:
  `nabu search "dis manibus" --kind funerary --from -100 --to 100
  --place pleiades:423025`.

## When — the dates layer {#dates}

As of **{{ site.data.dates.as_of }}** — a live census:
**{{ site.data.dates.dated_documents_display }} documents carry dating
bounds** (of {{ site.data.dates.total_documents_display }} live
documents, {{ site.data.dates.coverage_percent }}%). `nabu search
--century -21`, `nabu list --by-date` and `nabu vocab --by-century`
all read the same per-document interval.

Every dating bound is an honest year interval extracted from whatever
dating form upstream actually ships:

- **Structured claims** — EpiDoc `origDate` attributes, catalogue year
  columns, machine date attrs (the Korean chronicles' per-entry
  `1617-01-00` dates), publication-year headers.
- **Banded labels** — Assyriological period labels ("Neo-Assyrian")
  through a ruled period table; century-half grids ("15,2" = 15th c.,
  2nd half); anno-mundi annal years era-converted with the ambiguity
  kept as a span.
- **Author dating** — work-composition years and author life bands
  (Patrologia Latina), floruit strings ("fl. 892").

What resists an honest parse stays **raw and unbounded**: prose
datings ("Mitte 15. Jh." without a grid), upstream's own no-date
fillers, circa strings with nothing firmer behind them. An interval is
always a real range — no fake midpoints. Documents whose range spans
several centuries are bucketed by their **earliest** bound below
({{ site.data.dates.multi_century_display }} such documents — the
announced bias, not a hidden one).

### The centuries

| Century | Documents | Largest sources |
|---|---:|---|
{% for century in site.data.dates.centuries -%}
| {{ century.label }} | {{ century.documents_display }} | {{ century.sources }} |
{% endfor %}

## Where — the places layer {#places}

`nabu place Girsu` answers with the gazetteer card and every source's
holdings at that place. The layer has two halves: the gazetteers, held
locally, and the matching decisions that connect a source's verbatim
place-name to an identity.

**The gazetteers.** The library never queries a gazetteer online — it
holds them as canonical assets with provenance and derives one
namespaced place index:

| Namespace | What | Held rows | License |
|---|---|---:|---|
| `pleiades:` | [Pleiades](https://pleiades.stoa.org/) — THE ancient-world gazetteer | 42,284 | CC BY 3.0 |
| `tm:` | [Trismegistos Geo](https://www.trismegistos.org/geo/) — finest grain for Greco-Roman Egypt | 64,857 | CC BY-SA 4.0 |
| `cigs:` | [CIGS](https://zenodo.org/records/14568765) — the cuneiform world's site index | 598 | CC BY 4.0 |
| `np:` | [nabu-places](https://arvicco.github.io/nabu-places/) native records (minted by scholarship, evidence required) | 0 — the lane is new | CC BY 4.0 |

Namespaces are parallel claims; equivalences between them are
**crosswalk data with provenance** (3,438 rows: CIGS's own columns + a
Wikidata harvest), never inferred.

**The decisions registry.**
[nabu-places](https://arvicco.github.io/nabu-places/) records the
matching judgments — which identity a source's verbatim place-name
string denotes — each reviewable, in the pattern of
[nabu-lects](https://arvicco.github.io/nabu-lects/). Three real rows
tell the story: CDLI's `"Girsu (mod. Tello)"` → **matched** `cigs:GIR`
+ `pleiades:912855`; EDR's `"Mediolanum"` — six Pleiades places carry
that title, the row says *the Insubrian Milan* and names the five
rejected homonyms; `"Irisagrig (mod. uncertain)"` → **unlocatable** —
the site is unidentified in reality, and that is an answer, not a
failure. An unlisted name is honestly unmatched; adapter-asserted
upstream references always win over registry mints — the registry only
ever fills silence.

**Coverage.** At the places program's close (9 August 2026), 585,682
documents carried a machine place reference, of 708,905 that name a
place at all — a 3.9× gain over the pre-program state; the largest
sources sit at 74–87% matched (CDLI 250,484 of 337,572, Oracc 87%,
EDR 86%, EDH's 73,507 upstream-asserted). The maintained coverage
detail lives in
[docs/places.md](https://github.com/arvicco/nabu/blob/main/docs/places.md).
Honest limits stay on the record: a dozen upstream references cite
defective Pleiades ids (flagged loudly by the health invariants);
long-tail names below the curated waves stay visibly unmatched until
their wave lands.

## What kind — the classification layer {#kinds}

As of **{{ site.data.kinds.as_of }}** — a live census:
**{{ census.kind_documents_display }} documents carry a kind
classification** ({{ census.kind_coverage_pct }}% of the kind-eligible
library), across {{ census.kind_class_count }} class families. What
kind of document is this — an epitaph, a receipt, a hymn, a school
exercise? Each source ships its own genre vocabulary (EpiDoc
inscription types, cuneiform catalogue genres, manuscript headings);
those upstream labels **fold onto one ruled cross-corpus class list**
(`config/kind_classes.yml`, with crosswalks to EAGLE, LCGFT and Getty
AAT where those vocabularies recognize the class).

Classification is **multi-label** — a funerary poem is both — and the
tree is **optionally deep**: a class is a family with named
sub-classes (`literary` holds `literary/poetry`,
`literary/narrative`, …), any prefix matches its whole family in
queries, and a document upstream calls just "Literary" honestly
carries the bare family head. The upstream claim is preserved verbatim
beside the fold, so the ruled class never erases what the source
actually said.

### The classes

| Class | Documents | Sources |
|---|---:|---:|
{% for class in site.data.kinds.classes -%}
| {{ class.head }} | {{ class.documents_display }} | {{ class.sources }} |
{% endfor %}

### What stays honest

Two buckets are counted beside — never inside — the classes:
**unknown** ({{ site.data.kinds.unknown_documents_display }} documents)
is upstream's own "cannot determine", a claim the library preserves
rather than overwrites; **unmapped**
({{ site.data.kinds.unmapped_documents_display }} documents) holds
values still awaiting a fold rule — a visible curation worklist, not a
silent discard. Values reviewed and found not to be genre claims at
all (a physical-layout tag, a copy marker) are declared as such in
config and render as their own census section. Sources carrying
nothing genre-shaped at all
({{ site.data.kinds.unclassified_sources }} sources,
{{ site.data.kinds.unclassified_documents_display }} documents) speak
through their recorded postures, not through silence.

## One query across the layers

```
nabu search --century -21                        # when
nabu place Girsu                                 # where: the card + holdings
nabu kind census                                 # what kind: the class board
nabu kind census --unmapped                      # the classification worklist
nabu search --kind literary/poetry --lang la     # a family narrowed to verse
nabu search lugal --place cigs:GIR --from -2200 --to -2000 --kind administrative
```

Every filter also rides the MCP tools (`nabu_search`, `nabu_place`,
`nabu_show`) for conversational use, and every document card
(`nabu show`) renders its date interval, place references and kind
line side by side — the three layers on one card.
