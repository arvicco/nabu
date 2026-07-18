# LexLep (Lexicon Leponticum) fixtures — P29-3

Real wiki pages for the `lexlep` adapter (`Nabu::Adapters::Lexlep` /
`WikiTemplateParser` / `Nabu::WikiFetch`). Retrieved **2026-07-18** from
`https://lexlep.univie.ac.at/api.php` (MediaWiki 1.38 + Semantic MediaWiki)
via the exact request shapes the fetcher uses: 50-title batches of
`action=query&prop=revisions&rvprop=content|ids|timestamp&rvslots=main`
over `generator=categorymembers`.

- Layout mirrors the canonical workdir WikiFetch fetches into:
  `pages/<Category>/<percent-encoded title>.json` (the fetcher's per-page
  envelope: title/pageid/ns/revid/timestamp + the **wikitext byte-verbatim
  as api.php served it**) and `map/<Category>.json` (member lists TRIMMED
  to the checked-in pages; each member row's title/pageid/revid verbatim
  from the API).
- Pages chosen for shape coverage:
  - `AO·1.1` — minimal two-letter reading ("ap"), object+site join
    (AO·1 Aosta → Aosta, coordinates, sortdate −100), Morandi concordance.
  - `BG·1` — `A!B` reading token with `&#93;`/`&#91;` entities (renders
    "]?ume"), language=unknown, Morandi + Solinas concordances.
  - `BI·8` — the `space` word-divider marker + fragment tokens linking one
    Word page ("sipiu koil[ ]ios", words sipiu/koilios/koilios); its object
    page (BI·8 Cerrione) is deliberately NOT checked in — the
    missing-join-page honesty path.
  - `BE·1` — reading=unknown (the Münsingen glass bead): the
    metadata-only document path.
  - Objects `AO·1 Aosta` (dated, coordinates) and `BG·1 Bergamo`
    (sortdate=0 + date=unknown — the wiki's undated filler); Sites
    `Aosta`, `Bergamo`.

## License (all layers, verbatim — the conflict held at `nc`)

- `Project:Terms of use` (fetched via api.php 2026-07-18): *"Lexicon
  Leponticum (LexLep) is an interactive online dictionary and lexicon
  created and licenced for **scientific use only**. In line with
  Wikimedia's terms of use the content of this site is is available under
  conditions specified by the following licences: (1) the Creative
  Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0) license
  (2) the GNU Free Documentation License."* [sic]
- The wiki's rightsinfo/footer (api.php `meta=siteinfo&siprop=rightsinfo`):
  `https://creativecommons.org/licenses/by-nc-sa/4.0/` — *"Creative
  Commons Attribution-NonCommercial-ShareAlike"*.
- The grants contradict and the preamble scopes to scientific use →
  class `nc` pending the licensing clarification (email №17, queued);
  relabel-on-reply.

Envelope note: the JSON envelope is the fetch layer's own on-disk shape
(there is no upstream per-page file to mirror); the `wikitext` string
inside each envelope is the byte-verbatim `slots.main.*` content of the
API response. A re-GET returns whatever revid upstream then has, so the
sentinel manifest marks these `refetchable: false`.
