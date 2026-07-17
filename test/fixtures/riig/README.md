# RIIG (Recueil informatisé des inscriptions gauloises) fixtures — P25-1

Real EpiDoc records + a trimmed corpus map for the `riig` adapter
(`Nabu::Adapters::Riig` / `RiigEpidocParser`). Retrieved **2026-07-17** from
`https://riig.huma-num.fr` (the owner-authorized fixture-sample crawl —
not the full 428; AIS-01-01 added in P25-3 from the canonical crawl of the
same date): each record from the verified stable pattern
`https://riig.huma-num.fr/documents/data/documents/RIIG/<ID>.xml`,
**byte-identical**; the corpus map extracted from
`https://riig.huma-num.fr/corpus.html?collection=RIIG`.

- Layout mirrors the canonical workdir the adapter fetches into:
  `documents/<ID>.xml` (the crawled records), `map/corpus.html` (the
  fetched corpus page — here TRIMMED: the real page head + its embedded
  `placesgeo` GeoJSON FeatureCollection reduced from 428 features to these
  four records' features, **each feature object byte-identical**; the full
  page is 2.6 MB of facet HTML).

## License (both layers, verbatim — the in-file grant governs)

- Every record's `<availability>`: *"Cette œuvre est mise à disposition
  selon les termes de la Licence Creative Commons Attribution 4.0
  International"* (`<licence target="http://creativecommons.org/licenses/by/4.0/">`)
  → **CC BY 4.0**, class `attribution`.
- The project page (fr), over the site documentation: *"L'ensemble de cette
  documentation est fournie en Open Access, sous la licence CC BY-NC-ND
  4.0"* — noted, never governing the records; per-image facsimile rights
  (CC BY-NC-ND, museum copyrights) live in `<facsimile>` and are never
  fetched.

## Records (whole, byte-identical)

| File | RIG | Lang | Quirks it preserves |
|---|---|---|---|
| `documents/AHP-01-01.xml` | G593 | xtg-Grek | **Two alternative readings** (segs HRD-a / PTL-b: καρε[…]μ vs καρβ[…]μ), `unclear` + mid-word `gap` (marker fuses: καρε[…]μ), BCE `origDate notBefore="-0100" notAfter="-0001" cert="low" evidence="context"`, decimal-comma WGS84 `<geo>44,0655 5,688</geo>`, Trismegistos settlement `@corresp`, TM idno in a `tei:`-prefixed element (namespace quirk), altIdentifier localID `G-593` (hyphen variant of `G593` — the dedup case). |
| `documents/VAU-13-01.xml` | G153 | xtg-Grek | The **Segomaros dedication** (Vaison-la-Romaine): THREE concurring readings (MLE-a / PLT-a / RIIG-a, 7 lines each), per-glyph `<g>` letter forms in `orig` (dropped — reg governs), a **non-empty French translation div** (`corresp="#MLE-a"`) → the -fr sibling, full msd/pos/type word layer. |
| `documents/ALL-01-01.xml` | L6 | xtg-Latn | **Gallo-Latin** (Néris-les-Bains): `expan/abbr/ex` (NANTONICN → nanton{t}icnos), `<surplus>` (Leiden braces), `<lb break="no"/>` mid-word (epađateχto\|rici), `rs` stem/suffix wrappers inside reg, two readings. |
| `documents/GAR-10-03.xml` | G205 | xtg-Grek + la | **Bilingual** (Nîmes): two textparts (no `@n` — seg ids disambiguate), Latin readings with `xml:lang="la"` → per-passage `lat`, `supplied reason="lost"` (βρατουδεκ-), explicit `<space/>` word dividers inside `<w>` (votum solvit libens merito), translation div per textpart. |
| `documents/AIS-01-01.xml` | G617 | xtg-Grek | **P25-3 sibling-noise regression** (byte-verbatim from the canonical 2026-07-17 crawl): `<div type="translation"/>` **self-closed**, followed by prose-bearing commentary divs — the shape that fooled the retired byte peek's non-greedy `(.*?)</div>` into minting 233 corpus `-fr` siblings the parser could never fill. No translation prose → no sibling ref. `documents/` only — NOT added to the map trim (discovery globs `documents/`, never the map; the fetch tests keep their 4-id map). |

## Known upstream quirks the fixtures document

- Files are pretty-printed with NO `xml:space="preserve"` — word-internal
  indentation is formatting noise (the parser's strip-inside-`<w>` rule);
  real word division inside a `<w>` is the explicit `<space/>` element.
- `<textLang mainLang>` carries the honest script subtag (xtg-Grek /
  xtg-Latn); ~5 corpus records are mapped "Indéterminé" and may parse to
  zero citable lines → honest quarantines at first sync, triage then.
- The corpus map's `"riig"` properties are the crawl seed; RIG concordance
  and coordinates are read from the records themselves.
