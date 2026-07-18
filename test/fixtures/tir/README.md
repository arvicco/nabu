# TIR (Thesaurus Inscriptionum Raeticarum) fixtures — P29-3

Real wiki pages for the `tir` adapter (`Nabu::Adapters::Tir` /
`WikiTemplateParser` / `Nabu::WikiFetch`). Retrieved **2026-07-18** from
`https://tir.univie.ac.at/api.php` (MediaWiki 1.38 + Semantic MediaWiki —
the same machinery as LexLep, one wiki family) via the fetcher's own
50-title `prop=revisions` batch shape over `generator=categorymembers`.

- Layout mirrors the canonical workdir: `pages/<Category>/<percent-encoded
  title>.json` (fetcher envelope; `wikitext` byte-verbatim from the API)
  plus `map/<Category>.json` trimmed to the checked-in pages.
- Pages chosen for shape coverage:
  - `AK-1.1` — the Achenkirch rock wall: `A!B` tokens with combining
    U+0323 under-dots (renders "?]ṇuale ri?ienalṣẹ"), `)nuale` fragment
    Word link, Magrè alphabet, Trismegistos siglum (tm:653493),
    language=Raetic → xrr.
  - `BZ-10.1` — two reading lines (" / " separator, "tnake p̣iθamu" /
    "laþe?"), the `space` marker, `{{c|…}}` original-script templates
    kept verbatim in metadata, five print sigla params.
  - `AK-1.12` — reading "?" (upstream's illegible-marker notation, kept).
  - Objects `AK-1 rock` (sortdate=0 + date=unknown, and NO coordinates —
    withheld upstream "by request of the Department for Prehistory in
    Innsbruck"; the honest-absence path) and `BZ-10 slab` (dated −300,
    site Pfatten / Vadena); Sites `Achenkirch`, `Pfatten / Vadena` and
    `Bozen / Bolzano` (slash-bearing titles → percent-encoded filenames).

## License (verbatim — "scientific use only" scoping held at `nc`)

- `Project:Terms of Use` (fetched via api.php 2026-07-18): *"Thesaurus
  Inscriptionum Raeticarum (TIR) is an interactive online lexicon created
  and licensed for scientific use only. In line with Wikimedia's terms of
  use the content of this site is available under conditions specified by
  the following licences: (1) the Creative Commons Attribution-ShareAlike
  3.0 Unported (CC BY-SA 3.0) license (2) the GNU Free Documentation
  License."*
- The wiki's rightsinfo (api.php `meta=siteinfo&siprop=rightsinfo`) is
  **empty** — no footer grant.
- Class `nc` pending the licensing clarification (email №17, queued);
  relabel-on-reply.

Envelope note: as with lexlep, the JSON envelope is the fetch layer's own
shape; the `wikitext` inside is byte-verbatim. `refetchable: false` in the
sentinel manifest (a re-GET returns upstream's current revid).
