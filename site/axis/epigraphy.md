---
title: "Epigraphy — The Papyrologist-Epigraphist"
permalink: /axis/epigraphy/
description: >-
  The Papyrologist-Epigraphist's desk: its shelves, instruments, CLI recipes and terminal setup.
---

> The Papyrologist-Epigraphist — reads what survives on stone, sherd, papyrus and tablet, lacunae and all.

Documentary corpora at the artifact grain: papyri, the Latin/Greek and Levantine and Sicilian inscription databases, the Continental Celtic, Italic and Tyrsenian editions, ogham stones, Hittite tablets — the shelves where fragment search and findspots earn their keep.

New here? The [Quickstart]({{ '/quickstart/' | relative_url }}) sets up the library in minutes.

## The shelves

A source wears every desk it serves — these 26 answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 3 September 2026)</span> |
|---|---|---|---|---|
| `papyri-ddbdp` | papyri | attribution | wired · manual | 61,414 docs / 925,496 passages |
| `edh` | inscriptions | attribution | wired · frozen | 81,881 docs / 406,306 passages |
| `riig` | inscriptions | attribution | wired · manual | 495 docs / 1,357 passages |
| `ogham` | inscriptions | nc | wired · manual | 873 docs / 1,053 passages |
| `isicily` | inscriptions | attribution | wired · manual | 6,723 docs / 17,921 passages |
| `itant` | inscriptions | nc | wired · manual | 1,160 docs / 1,283 passages |
| `trismegistos` | feature module | attribution | wired · manual | nothing held yet |
| `pleiades` | feature module | attribution | wired · manual | nothing held yet |
| `trismegistos-geo` | feature module | attribution | wired · manual | nothing held yet |
| `tlhdig` | tablets | attribution | wired · manual | 23,486 docs / 402,195 passages |
| `ceipom` | inscriptions | attribution | wired · frozen | 3,871 docs / 5,303 passages |
| `open-etruscan` | inscriptions | attribution | wired · frozen | 8,047 docs / 8,047 passages |
| `lexlep` | inscriptions | nc | wired · manual | 494 docs / 570 passages |
| `lexlep-words` | dictionary | nc | wired · manual | 627 entries |
| `tir` | inscriptions | nc | wired · manual | 389 docs / 434 passages |
| `iip` | inscriptions | nc | wired · manual | 5,499 docs / 17,823 passages |
| `rundata` | inscriptions | odbl | wired · manual | 30,647 docs / 30,645 passages |
| `edr` | inscriptions | attribution | wired · manual | 115,590 docs / 596,064 passages |
| `elephantine` | papyri & ostraca | attribution | wired · manual | 15,539 docs / 69,350 passages |
| `nabu-places` | feature module | attribution | wired · manual | nothing held yet |
| `ucd` | feature module | open | wired · manual | nothing held yet |
| `dharma-khmer` | texts | attribution | wired · manual | 1,219 docs / 50,165 passages |
| `dharma-campa` | texts | attribution | wired · manual | 121 docs / 2,728 passages |
| `dharma-nusantara` | texts | attribution | wired · manual | 291 docs / 5,893 passages |
| `dharma-pyu` | texts | attribution | wired · manual | 145 docs / 629 passages |
| `obi-burmese` | texts | attribution | wired · manual | 1,121 docs / 25,238 passages |

**Languages on this desk** <span title="read live from the catalog">(live doc-or-entry counts as of 3 September 2026)</span>: `lat` 195,002 · `grc` 74,274 · `hit` 21,209 · `non` 20,442 · `eng` 14,964 · `ett` 6,259 · `swe` 3,393 · `egy` 3,047 · `arc` 2,970 · `cop` 2,515 … and 68 more (`nabu axis epigraphy` lists all).

## The desk's instruments

- **Documentary corpora at the artifact grain:** papyri (papyri-ddbdp),
  the Latin inscriptions of the Empire (EDH, with genre/province/material
  facets), the Continental Celtic (RIIG), Italic (ItAnt, CEIPoM), Etruscan
  and Raetic (TIR) editions, ogham stones, Hittite tablets (TLHdig), and
  the Levant (IIP).
- **The fragment desk:** the `--fuzzy` trigram index covers the documentary
  shelves — **papyri-ddbdp, EDH, EDR, Elephantine, ORACC and
  open-etruscan** (3.8M passages as of 28 July 2026). The other
  epigraphic shelves (RIIG, ogham, ItAnt, Rundata…) are searched with
  plain `search --axis epigraphy`.
- **The timeline desk:** 549,771 documents carry a date or place (as of
  26 July 2026 — CDLI's tablets, the Heidelberg inscriptions and the
  papyri foremost), so `--from/--to`, `--century` and `--place` scope
  the stones and sherds by when and where. EDH's genre facets
  (`--type/--province/--material`) live.
- **The gazetteer (P44–P46):** `nabu place NAME` resolves a findspot
  against the Pleiades gazetteer (42,242 places in a derived index —
  millisecond lookups) and counts this library's holdings found there;
  an inscription's `nabu show` names its findspot with the Pleiades id.

## Working the epigraphy desk

The generic axis surfaces — every desk answers to these, in working
order (enable once, sync, then query):

```
nabu enable epigraphy               # first time: put this desk's shelves in this box's profile
nabu sync epigraphy                 # fetch/refresh the desk's enabled members
nabu list --axis epigraphy          # the shelf census, this desk only
nabu axis epigraphy                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis epigraphy   # a query scoped to this desk's shelves
```

This desk's own surfaces:

```
nabu place Segesta                    # the place card — Pleiades id, period band, coordinates, holdings found there
nabu search --fuzzy ']ανδρα μοι εν['  # damaged-line substring search, typed straight off the edition
nabu search manibus --type epitaph --province Britannia  # EDH genre facets composing with a text query (dis manibus on British epitaphs)
nabu search "στρατηγ*" --from 101 --to 300 --place oxyrhynch%  # the Oxyrhynchite strategoi by date and provenance
nabu search "στρατηγ*" --century 2 --axis epigraphy  # a query scoped to one century (negative = BCE, no year 0)
nabu search --century 2 --axis epigraphy  # term-less browse — every 2nd-c. inscription in corpus order, the century the content filter
nabu show urn:nabu:ogham:e-dev-001 --parallel  # an ogham stone beside its transliteration sibling
nabu search --lemma precor --axis epigraphy  # CEIPoM equivalence keys reach the Iguvine Tables' pesnimu
```


## Ask your model

With the [MCP server]({{ '/mcp/' | relative_url }}) connected, this desk answers conversational research questions. Each example ran live against this library:

- **“What survives from Segesta, across every corpus here?”** → `nabu_place Segesta` — The gazetteer card (Segesta/Egesta, Pleiades 462487 — settlement, archaic to late-antique, 37.94, 12.84) plus per-source holdings of documents carrying that upstream-asserted Pleiades id, and a labelled tail of findspot text-mentions not yet id-linked.
- **“Wage receipts from Oxyrhynchus?”** → `nabu_search μισθός (place: oxyrhynch%)` — Documentary papyri hits with provenance-filtered dating — the DDbDP at the artifact grain, lacunae preserved.

## Terminal setup

- **Ogham (pgl):** nabu spaces the letters with U+1680 (stemline-continuing)
  so they do not merge; install `font-noto-sans-ogham`.
- **Old Italic / Runic:** the inscription text is stored in Latin
  transliteration (the language tags name the alphabet); the native blocks
  surface only in headwords — install `font-noto-sans-old-italic` and
  `font-noto-sans-runic` for those.
- **Cuneiform / Hittite tablets:** stored in Latin transliteration, so no
  cuneiform font is needed.

The full guidance, per script, is on the [display page](https://github.com/arvicco/nabu/blob/main/docs/display.md).

---

One of the [twenty-five research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
