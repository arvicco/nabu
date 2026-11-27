# dio-epidoc fixtures — Die Deutschen Inschriften, Epigraf EpiDoc dumps

Retrieved 2026-11-27 from the dumps page
`https://epigraf.inschriften.net/pages/dumps` ("Available data dumps"),
version 1.0, published 2025-05-18, by the Akademie der Wissenschaften und
der Literatur Mainz — Digitale Akademie (Epigraf). The page's citation:
"The German Inscriptions (2025). Structured Data Dumps (Version 1.0)
[Data set]. Epigraf. https://epigraf.inschriften.net/pages/dumps".

License, verbatim in every one of the 978 article files:
`<licence target="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0 for the text</licence>`
followed by `<p>Please note that linked images may be published under more
restricted licenses.</p>`. The page: "Where possible, data is published
under CC BY 4.0 … Images have their own copyright and are only contained as
links." The EpiDoc carries no image links. → `attribution`.

## The files (whole, byte-identical members of the v1.0 zips)

Laid out as the adapter's fetch lays out `canonical/dio-epidoc/`: one
directory per volume zip, the zip's flat member list unpacked into it.

| path | what | why it is here |
|---|---|---|
| `di7/article-BSS-001-nsn~3212.xml` | DI 7, Nr. 1 — the lost foundation stone of Kloster Riddagshausen, 1145 (Latin) | one textpart without `<lb>`; `<supplied reason="omitted">` expansions (FV(N)DAT(A)); a German translation; a "historische Nachricht / Historische Nachricht" keyword doublet; a year date |
| `di77/article-hgw-246-mv~477.xml` | DI 77, Nr. 246 — grave slab of Christoph Michaelis, St. Nikolai Greifswald, 1575 | three inscriptions in three languages (niederdeutsch / hochdeutsch / none — the grave number "160"); `<del><gap/></del>`; `<add>` restored letters; `<unclear>`; an `<app>` letter footnote; `<dimensions>`; per-inscription script rows |
| `di102/article-HST-083-mv~2048.xml` | DI 102, Nr. 83 — grave slab of Heinrich Sten, St. Nikolai Stralsund | a century-range date (M.14.–M.15.Jh.); verse `<lb type="verse">`; a numeric footnote inside the text; heraldry; a fragment textpart with no language row; Latin + Low German |
| `rejected/article-BSS-001-nsn~3212.ttl` | DI 7, Nr. 1 from `di7_ttl.zip` | the REJECTED TTL grain's specimen |
| `rejected/article-BSS-001-nsn~3212.rdf` | DI 7, Nr. 1 from `di7_rdf_xml.zip` | the REJECTED RDF/XML grain's specimen |
| `rejected/article-BSS-001-nsn~3212.jsonld` | DI 7, Nr. 1 from `di7_jsonld.zip` | the REJECTED JSON-LD grain's specimen |

The download links are the page's own (`/files/download/<id>`; each
response's `Content-Disposition` names the zip): di7_epidoc.zip = 77651,
di77_epidoc.zip = 77647, di102_epidoc.zip = 77661, di7_ttl.zip = 77655,
di7_rdf_xml.zip = 77659, di7_jsonld.zip = 77656.

## Delivery grains (enumerated at fixture time, the whole page)

The page lists, per volume, one EpiDoc zip and three RDF zips, plus one
corpus-wide catalogue dump:

- **`di7_epidoc.zip` (73 files), `di77_epidoc.zip` (448), `di102_epidoc.zip`
  (457)** — one `article-<sigil>-<nnn>-<db>~<id>.xml` per printed
  catalogue number, flat in the zip; exactly the page's "Articles" column
  (73 + 448 + 457 = 978). **ACCEPTED: one file = one document**
  (`urn:nabu:dio-epidoc:di7-001`), passage = the printed inscription
  (textpart `A1`, `B1` …).
- **`di<N>_ttl.zip`, `di<N>_rdf_xml.zip`, `di<N>_jsonld.zip`** — the same
  articles as RDF ("All archives contain the same set of triples"; 73
  files each in DI 7): title, date, location, object type and one
  flattened transcription string per inscription — a lossy projection of
  the EpiDoc. **REJECTED**, never fetched; a `.ttl`/`.rdf`/`.jsonld` file
  in the workdir is skipped by rule (specimens pinned above).
- **`epigraf-public-cgif-001.zip`** (published 2025-09-14) — the 31,197
  legacy DIO-portal articles in the Culture Graph Interchange Format
  (the page says TTL; the one member is JSON-LD, 54 MB — opened and
  censused 2026-11-27): per record a title, entity-id keywords, a year
  span, the licence (CC BY 4.0) and image URLs; no transcription,
  translation, place or literature on any of the 31,197 records, and the
  three EpiDoc volumes' 978 articles are among them. **REJECTED** (a
  catalogue, not an edition); no specimen pinned (one corpus-wide file,
  no text grain to test).

## Census of the three EpiDoc zips (2026-11-27, every file read)

- 978/978 parse; 2,699 textparts (1–32 per article), every one citable →
  978 documents / 2,699 passages (DI 7: 73 / 134, DI 77: 448 / 1,325,
  DI 102: 457 / 1,240), 0 text-less, 0 errored.
- Markup inside the edition: supplied[@reason="omitted"] 3,429 (expansions),
  lb 4,514 (3,233 "neue Zeile", 690 verse, 242 "neues Inschriftenfeld", 71
  "Fragmentwechsel", the rest arms/house-mark interruptions or unmarked),
  del 1,764 — every one wrapping a gap (1,357 with quantity 0), add 1,483,
  app 1,388 (each one note), notes 1,693 in all, unclear 245, g 4,506,
  hi 2,670, q 2,497 (inside notes), ref 124, space 4. 258 articles carry
  no lb.
- Languages (langUsage rows, German labels, `@ident` always empty):
  lateinisch 838, hochdeutsch 495, niederdeutsch 262, deutsch 201,
  hochdeutsch-niederdeutsche Mischsprache 30, 11 rarer mixed labels,
  hebräisch 4, griechisch 2; 96 articles carry no row.
  Passages: lat 896, deu 751, gml 273, heb 3, grc 1, und 775.
- Dates: 978/978 origDate — 507 bare years, the rest ranges, centuries and
  fractions; 901 parse to closed intervals, 77 open-ended, 0 unparsed;
  span 1145–1750 (the latest a "2.V.17.–A.18.Jh." range).
- Places: 977/978 origPlace (123 distinct; St. Nikolai Stralsund 183,
  St. Marien Greifswald 181, St. Nikolai Greifswald 178 …).
- Identity: filename sigil/number/id = biblScope issue = idno iri in all
  978; idno urn (urn:nbn:de:0238-…) in 975.

## Recipe

`curl -A nabu-research-library -L https://epigraf.inschriften.net/files/download/<id> -o <zip>`
into an empty temporary directory, `unzip` each, copy the six members
named above unchanged.
