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

A source wears every desk it serves — these sixteen answer this desk. Holdings are read live from the catalog and dated; a shelf with nothing synced yet says so.

| Source | Holds | License | Status | Holdings <span title="read live from the catalog">(as of 24 July 2026)</span> |
|---|---|---|---|---|
| `papyri-ddbdp` | papyri | attribution | enabled · manual | 61,414 docs / 921,611 passages |
| `edh` | inscriptions | attribution | enabled · frozen | 81,881 docs / 406,306 passages |
| `riig` | inscriptions | attribution | enabled · manual | 495 docs / 1,357 passages |
| `ogham` | inscriptions | nc | enabled · manual | 873 docs / 1,053 passages |
| `isicily` | inscriptions | attribution | enabled · manual | 6,723 docs / 17,921 passages |
| `itant` | inscriptions | nc | enabled · manual | 1,160 docs / 1,283 passages |
| `trismegistos` | feature module | attribution | not enabled | nothing held yet |
| `pleiades` | feature module | attribution | not enabled | nothing held yet |
| `tlhdig` | tablets | attribution | enabled · manual | 23,486 docs / 402,195 passages |
| `ceipom` | inscriptions | attribution | enabled · frozen | 3,871 docs / 5,303 passages |
| `open-etruscan` | inscriptions | attribution | enabled · frozen | 8,047 docs / 8,047 passages |
| `lexlep` | inscriptions | nc | enabled · manual | 494 docs / 570 passages |
| `lexlep-words` | dictionary | nc | enabled · manual | 627 entries |
| `tir` | inscriptions | nc | enabled · manual | 389 docs / 434 passages |
| `iip` | inscriptions | nc | enabled · manual | 5,499 docs / 17,823 passages |
| `rundata` | inscriptions | odbl | enabled · manual | 30,643 docs / 30,641 passages |

## The desk's instruments

- **Documentary corpora at the artifact grain:** papyri (papyri-ddbdp),
  the Latin inscriptions of the Empire (EDH, with genre/province/material
  facets), the Continental Celtic (RIIG), Italic (ItAnt, CEIPoM), Etruscan
  and Raetic (TIR) editions, ogham stones, Hittite tablets (TLHdig), and
  the Levant (IIP).
- **The fragment desk:** the `--fuzzy` trigram index covers the documentary
  shelves — **papyri-ddbdp, EDH, ORACC and open-etruscan**. The other
  epigraphic shelves (RIIG, ogham, ItAnt, Rundata…) are searched with
  plain `search --axis epigraphy`.
- **The timeline desk:** 163,821 documents carry a date or place, so
  `--from/--to`, `--century` and `--place` scope the stones and sherds by
  when and where. EDH's genre facets (`--type/--province/--material`) live.

## Working the epigraphy desk

The generic axis surfaces — every desk answers to these:

```
nabu list --axis epigraphy          # the shelf census, this desk only
nabu axis epigraphy                 # the desk card: members, holdings, gold coverage
nabu search WORD --axis epigraphy   # a query scoped to this desk's shelves
nabu sync epigraphy                 # sync the desk's enabled members
```

This desk's own surfaces:

```
nabu search --fuzzy ']ανδρα μοι εν['  # damaged-line substring search, typed straight off the edition
nabu search manibus --type epitaph --province Britannia  # EDH genre facets composing with a text query (dis manibus on British epitaphs)
nabu search "στρατηγ*" --from 101 --to 300 --place oxyrhynch%  # the Oxyrhynchite strategoi by date and provenance
nabu search "στρατηγ*" --century 2 --axis epigraphy  # a query scoped to one century (negative = BCE, no year 0)
nabu search --century 2 --axis epigraphy  # term-less browse — every 2nd-c. inscription in corpus order, the century the content filter
nabu show urn:nabu:ogham:e-dev-001 --parallel  # an ogham stone beside its transliteration sibling
nabu search --lemma precor --axis epigraphy  # CEIPoM equivalence keys reach the Iguvine Tables' pesnimu
```


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

One of the [eighteen research desks]({{ '/axis/' | relative_url }}); the flat shelf map is [The Library]({{ '/library/' | relative_url }}) and the reasoning is [docs/axes.md](https://github.com/arvicco/nabu/blob/main/docs/axes.md).
