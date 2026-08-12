---
title: Places
permalink: /places/
description: >-
  The places of the Nabu library: the gazetteer namespaces (Pleiades,
  Trismegistos Geo, CIGS, GeoNames), the nabu-places decisions registry,
  and the coverage — how named documents become place-queryable.
---

As of **9 August 2026** — a live census: **585,682 documents carry a
machine place reference** (of 708,905 that name a place at all, across
~975,000 documents) — up from 151,157 before the places program, a 3.9×
gain in two phases. The maintained original of this page is
[docs/places.md](https://github.com/arvicco/nabu/blob/main/docs/places.md)
in the repository; this page states the system and the headline coverage.

Place is the library's third dimension, after language and time: `nabu
place Girsu` answers with the gazetteer card and every source's holdings
at that place, and the axis filters compose it with everything else.

## The gazetteers, held locally

The library never queries a gazetteer online — it holds them, as
canonical assets with provenance, and derives one namespaced place index:

| Namespace | What | Held rows | License |
|---|---|---:|---|
| `pleiades:` | [Pleiades](https://pleiades.stoa.org/) — THE ancient-world gazetteer | 42,284 | CC BY 3.0 |
| `tm:` | [Trismegistos Geo](https://www.trismegistos.org/geo/) — finest grain for Greco-Roman Egypt | 64,857 | CC BY-SA 4.0 |
| `cigs:` | [CIGS](https://zenodo.org/records/14568765) — the cuneiform world's site index | 598 | CC BY 4.0 |
| `np:` | [nabu-places](https://arvicco.github.io/nabu-places/) native records (minted by scholarship, evidence required) | 0 — the lane is new | CC BY 4.0 |

Namespaces are parallel claims; equivalences between them are **crosswalk
data with provenance** (3,438 rows: CIGS's own columns + a Wikidata
harvest), never inferred. The Trismegistos dump is a *manually acquired*
asset — its download sits behind a captcha, so a human fetches it and
`nabu sync` ingests it with full provenance: the Manual Adapter pattern,
built for exactly this class of high-value, human-only-accessible data.

## The decisions registry

Gazetteers hold the places; what no shared resource held is the
**matching decision** — which identity a source's verbatim place-name
string denotes. [nabu-places](https://arvicco.github.io/nabu-places/)
records exactly those judgments: 550 rows across 7 sources at this
census, each reviewable. Three real rows tell the story:

- CDLI's `"Girsu (mod. Tello)"` → **matched**: `cigs:GIR`,
  `pleiades:912855`.
- EDR's `"Mediolanum"` — six Pleiades places carry that title; the row
  says *the Insubrian Milan* and names the five rejected homonyms.
- `"Irisagrig (mod. uncertain)"` → **unlocatable** — the site is
  unidentified in reality, and that is an answer, not a failure.

An unlisted name is honestly unmatched (the identity-default doctrine,
shared with [nabu-lects](https://arvicco.github.io/nabu-lects/)); regional
bins are `region`, examined-and-undecidable names are `rejected` with the
reason. Adapter-asserted upstream references always win over registry
mints — the registry only ever fills silence.

## Coverage, per source (the applied registry)

| Source | Axis rows with refs | Share |
|---|---:|---:|
| cdli | 250,484 / 337,572 | 74% (from zero) |
| oracc | 101,983 / 117,419 | 87% |
| edr | 99,249 / 115,590 | 86% |
| edh | 73,507 (upstream-asserted) | — |
| papyri-ddbdp | 49,030 | — |
| elephantine | 3,690 / 7,973 | 46% |
| iip | 1,828 / 5,499 | 33% |
| ceipom | 1,036 (restored TM ids) | — |

Honest limits, on the record: 12 upstream references cite defective
Pleiades ids (digit-mangled or superseded — flagged loudly by the health
invariants, reported upstream in due course); rundata's 30k findspots are
modern parishes with coordinates of their own, a different feature;
long-tail names below the curated waves stay visibly unmatched until
their wave lands.

## Try it

```
nabu place Girsu                  # the card + holdings at the place
nabu place 462281                 # by Pleiades id
nabu place apply                  # project new registry decisions
nabu search lugal --place cigs:GIR --scan   # search by place IDENTITY (August 2026)
nabu search --within 59.86,17.64,30         # find-locations inside a radius
```

The MCP surface serves the same card as `nabu_place` for conversational
use. Place data composes with the timeline: the epigraphy desks read
findspot and date off the same axis row. Since August 2026 the layer has
its search consumer: `--place` accepts a namespaced identity or a name
resolved through the registry's decisions (crosswalk equivalences
included, verbatim-name recall kept), the place card renders its
equivalences as an `=` line, and `--within` cuts by recorded
find-coordinates.
