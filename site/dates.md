---
title: Dates
permalink: /dates/
description: >-
  The time axis of the Nabu library: how documents carry dating bounds,
  what the honest-bounds doctrine refuses to guess, and the live
  chronological census — dated documents by century.
---

As of **{{ site.data.dates.as_of }}** — a live census:
**{{ site.data.dates.dated_documents_display }} documents carry dating
bounds** (of {{ site.data.dates.total_documents_display }} live documents,
{{ site.data.dates.coverage_percent }}%). Time is the library's second
dimension, after language and beside place: `nabu search --century -21`,
`nabu list --by-date` and `nabu vocab --by-century` all read the same
per-document interval this page censuses.

## How documents get dates

Every dating bound is **extracted, never guessed** — each source's
adapter or timeline extractor reads whatever dating form upstream
actually ships and turns it into an honest year interval:

- **Structured claims** — EpiDoc `origDate` attributes, catalogue year
  columns, machine date attrs (the Korean chronicles' per-entry
  `1617-01-00` dates), publication-year headers.
- **Banded labels** — Assyriological period labels ("Neo-Assyrian")
  through a ruled period table; century-half grids ("15,2" = 15th c.,
  2nd half); anno-mundi annal years era-converted with the ambiguity
  kept as a span.
- **Author dating** — work-composition years and author life bands
  (Patrologia Latina), floruit strings ("fl. 892").

What resists an honest parse stays **raw and unbounded**: prose datings
("Mitte 15. Jh." without a grid), upstream's own no-date fillers, circa
strings with nothing firmer behind them. An interval is always a real
range — no fake midpoints. Documents whose range spans several centuries
are bucketed by their **earliest** bound below
({{ site.data.dates.multi_century_display }} such documents — the
announced bias, not a hidden one).

## The centuries

| Century | Documents | Largest sources |
|---|---:|---|
{% for century in site.data.dates.centuries -%}
| {{ century.label }} | {{ century.documents_display }} | {{ century.sources }} |
{% endfor %}

The same table, filterable and composable, lives in the CLI:
`nabu list --by-date` for this census, `nabu list SOURCE` for one
source's coverage card, `nabu search TERM --from -700 --to -600` to put
the axis under a query.
