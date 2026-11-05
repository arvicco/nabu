---
title: Sources
permalink: /sources/
description: >-
  Every corpus and dictionary in the Nabu library, with upstream attribution
  and license terms, and the project's licensing philosophy.
---

{% assign census = site.data.census -%}
Nabu is an aggregation of other people's scholarship. Every text in the
library exists because an upstream project digitized, edited, annotated,
and published it under terms that permit this kind of use; those projects
are credited here, and their license terms travel with every passage. The
maintained inventory, including sources evaluated but not (or not yet)
ingested, is
[docs/02-sources.md](https://github.com/arvicco/nabu/blob/main/docs/02-sources.md)
in the repository.

## The licensing model

Every document carries a license class, recorded as data at ingestion and
displayed on every surface — search hits, exports, alignment rows, and MCP
responses alike:

- **`open`** — public domain or CC0. No restrictions.
- **`attribution`** — CC BY or CC BY-SA class: redistributable with credit.
  Together with `open`, this covers roughly
  {{ census.redistributable_pct }}% of documents.
- **`odbl`** — open data under the Open Database License (ODbL 1.0 + DbCL
  1.0): attribution and share-alike duties that attach to the *database*
  — name it, link it, share derived databases alike. The Scandinavian
  runic corpus is its occupant.
- **`nc`** — CC BY-NC-SA class (GRETIL, most treebanks): licensed for
  non-commercial use. Appropriate for private research, including
  AI-assisted reading; never redistributed by the tooling.
- **`research_private`** — sources whose terms (for instance CC BY-ND, or
  scholarly-use grants without a redistribution clause) do not fit the
  classes above. Held for personal research only, and excluded from the
  MCP surface by default: an AI client must opt in per call to see them.
  The Freising Manuscripts edition (CC BY-ND 2.5 SI) was the first source
  behind this gate; scholarly-use grants (SEAL, the Luwian corpus) and the
  Dutch institute corpora without a redistribution clause have joined it.
- **`restricted`** — a document whose upstream licence statement is
  unfamiliar is never silently opened: it is held at this class, withheld
  from the MCP surface like `research_private`, until a human has read the
  statement.

Two further habits belong to this model. First, licenses are read from
upstream metadata wherever it is machine-readable (ORACC's per-project
license field, for example), never hardcoded, and per-document overrides
record cases where one collection carries differently licensed layers.
Second, texts an upstream later deletes are retained and remain searchable —
honestly labelled as retired upstream — under the license they were fetched
with.

This posture is deliberately conservative: the library is personal research
infrastructure, not a redistribution service, so it can hold non-commercial
and no-derivatives material lawfully while keeping the boundary explicit in
the data. Should any part of the collection ever face outward, the license
classes are the gate that decides what may pass.

## Corpus sources

Every live public source has a row here — all {{ census.live_sources }}
of them as of {{ census.as_of }}, listed alphabetically by source id, with
sibling shelves from one upstream (a corpus and its lexicon, say) sharing a
row. The table is generated from the source registry at every
development gate, so a newly synchronized source appears without anyone
remembering to add it; a row whose description has not yet been written
says so plainly and carries the source's own name, upstream link and
license class until it is. The counts in a contents line are those of the
source's first synchronization (dated where shown), while the holdings
column is the live catalog's own count, regenerated at every development
gate (last read {{ site.data.sources.as_of }}). Each row is linkable by its
source id — `/sources/#src-oracc`. The same sources grouped by research desk —
each desk's member shelves, license mix and sync status on one page —
appear on the [research desks]({{ '/axis/' | relative_url }}), and the
collections they form are surveyed on [The Library]({{ '/library/' | relative_url }}).

{% include sources_table.md %}

## Feature modules

A further {{ census.feature_modules }} registry rows are **feature modules**, not corpora:
machinery that fetches reference data but mints no documents of its own.

| Module | What it provides | License |
|---|---|---|
| `actib` | The segmented-Tibetan anchor layer, republished through nabu-data | CC BY 4.0 |
| `althurayya` | The [al-Ṯurayyā Gazetteer](https://althurayya.github.io/) of the early Islamic world — the place lane of the Arabic desk | CC BY 4.0 |
| `bridging` | The OSHB ↔ BHSA verse crosswalk | MIT |
| `burman-concordance` | The [Burman Digital Concordance](https://zenodo.org/records/7801485) of Etruscan, Faliscan and early Latin inscriptions — the crosswalk between the Italic editions | CC0 |
| `cbdb` | The [China Biographical Database](https://github.com/cbdb-project/cbdb_sqlite) — the person index behind `nabu person` | CC BY-NC-SA 4.0 |
| `chgis` | The [China Historical GIS](https://doi.org/10.7910/DVN/H3OB28) temporal gazetteer — the place lane of the Sinitic desk | CC0 1.0 |
| `cigs` | The [Cuneiform Inscriptions Geographical Sites](https://zenodo.org/records/14568765) index — site mnemonics behind hundreds of thousands of cuneiform findspot links | CC BY 4.0 |
| `cldf-spine` | The shared Cross-Linguistic Data Formats reference tables ([Concepticon](https://concepticon.clld.org/) + [Glottolog](https://glottolog.org/)) that WOLD/CLICS rows resolve through | CC BY 4.0 |
| `edubba-overlay` | The didactic overlay from [Edubba](https://arvicco.github.io/nabu-edubba), the scribal-school sibling — course keywords and chapters riding the hieroglyph cards | CC BY-SA 4.0 |
| `hypotactic` | Greek metrical scansion — meter, pattern and caesura annotated onto held verse | CC BY 4.0 |
| `kitab` | [KITAB](https://kitab-project.org/) text-reuse alignments over the OpenITI library | CC BY-NC-SA 4.0 |
| `kitab-reuse` | The [KITAB](https://doi.org/10.5281/zenodo.11501559) pairwise text-reuse statistics over the OpenITI library | CC BY-NC-SA 4.0 |
| `kr-gaiji` | The Kanripo gaiji (rare-glyph) map | CC BY-SA 4.0 (the kanripo org grant) |
| `lila` | The [LiLa](https://lila-erc.eu/) Latin lemma bank behind `nabu define`'s variant-spelling fallback | CC BY-SA 4.0 |
| `nabu-data` | The library's own [published datasets](https://github.com/arvicco/nabu-data), consumed back as a source — e.g. the Sanskrit form→lemma table behind `nabu define`'s inflected-form expansion; the reproducibility loop closed in public | CC BY 4.0 |
| `nabu-lects` | The [lect registry](https://arvicco.github.io/nabu-lects) sister project — the stage ladders, stage-aware search and reconstruction honesty on the [Languages]({{ '/languages/' | relative_url }}) page | CC BY 4.0 |
| `nabu-places` | The [place-decisions registry](https://arvicco.github.io/nabu-places) sister project — which gazetteer identity each source's verbatim place name denotes; see [Places]({{ '/layers/' | relative_url }}#places) | CC BY 4.0 |
| `nrct` | [NRCT](https://geoshape.ex.nii.ac.jp/nrct/) — the historical placenames of Japan (日本歴史地名大系) behind the Japanese place lane | CC BY 4.0 |
| `osl` | The Oracc Sign List behind `nabu signs` | CC0 |
| `pedecerto` | Latin metrical scansion ([Pedecerto](https://www.pedecerto.eu/), digital metrical analyses) | CC BY-NC-ND 4.0 |
| `pleiades` | The [Pleiades](https://pleiades.stoa.org/) ancient-world gazetteer behind `nabu place` and the findspot line | CC BY 3.0 |
| `trismegistos` | The [Trismegistos](https://www.trismegistos.org/) TexRelations concordance crosswalk resolving `tm:` reference edges across epigraphic corpora | CC BY-SA 4.0 |
| `trismegistos-geo` | The Trismegistos Geo gazetteer — 64,857 ancient-world places behind the `tm:` lane of the place desk | CC BY-SA 4.0 |
| `ucd` | The core of the [Unicode Character Database](https://www.unicode.org/ucd/) — character identity for every script the library holds | Unicode License V3 |
| `unikemet` | Unicode's Unikemet data file — the 5,067-hieroglyph Egyptian sign spine behind `nabu char` for Egyptian | Unicode License V3 |

## The local shelves

A further {{ census.local_shelves }} registered sources hold no upstream at all — they are the
library's shelves for authored and acquired material, synchronized by
re-scanning local files rather than fetching. The language-dossier shelf
(`local-language`) carries the library's own per-language curation, one
Markdown dossier per language code. The local-library shelf
(`local-library`) files the owner's PDFs, scans, and offprints through
the `nabu ingest` command (which also accepts http(s) URLs, downloading
first and recording the address in the manifest); everything on it
defaults to the `research_private` class — catalogued and searchable
locally, never served or redistributed. The source-dossier shelf
(`local-source`) carries a curated description of every registered
source, served on the `nabu list` census. The notes shelf
(`local-notes`) records the owner's annotations on any citable URN
through `nabu note`. The lemma shelf (`local-lemmas`) keeps the raw
output of the local lemmatization campaigns (`nabu lemma-enrich`) — hours
of computation that cannot be re-derived for free, projected from there
into the silver lemma tier. What these shelves hold is, by design, the owner's
private business — their contents and counts appear nowhere public.
Licenses on
these shelves belong to whatever the owner files there; the class system
above is the gate that keeps restricted personal material private.

## Acknowledgements

This library would be empty without the sustained, mostly under-funded work
of the projects above: the Perseus Digital Library and Open Greek &amp;
Latin; the Duke Databank and papyri.info; the ORACC consortium and its
constituent projects; the PROIEL, TOROT, and ISWOC treebank teams in Oslo
and Tromsø; the Universal Dependencies community; GRETIL at Göttingen; the
Corpus Cyrillo-Methodianum Helsingiense and Kielipankki; CLARIN.SI and
LINDAT/CLARIAH-CZ; the Bosworth-Toller digitization at Charles University;
the eZISS edition of the Freising Manuscripts; the Society of Biblical
Literature and Logos; eBible.org and the open-bibles collection; the Oxford
Text Archive; the Wiktionary community and the Wiktextract project; the
Cologne Digital Sanskrit Lexicon; Coptic Scriptorium; the Epigraphic
Database Heidelberg; the IE-CoR project; the LiLa (Linking Latin) /
CIRCSE group, whose linked-data editions carry LIV and de Vaan; George
Starostin and the StarLing / Tower of Babel project, with the compilers
of its constituent databases; ZRC SAZU, whose dictionaries carry the
Slovenian lexicographic tradition; the ChronHib project at Maynooth
(CorPH); the RIIG project at Ausonius / Bordeaux; the Ogham in 3D
project at DIAS; the Hethitologie-Portal Mainz and the TLHdig team; the
Cuneiform Digital Library Initiative; the electronic Babylonian Library
at LMU Munich; the ETCBC at the Vrije Universiteit Amsterdam, whose
text-fabric editions carry the BHSA, the Scrolls and the Peshitta; the
CACCHT project in Copenhagen; the Srophé / Digital Syriac Corpus
editors; the ETCSL project at Oxford with the Oxford Text Archive; the
Kanseki Repository (Christian Wittern) and CBETA; the Thesaurus Linguae
Sericae editors; the Unicode Consortium's Unihan database; the nk2028
group's Qieyun-system edition; William Baxter and Laurent Sagart; the
HDIC project; the Electronic Dictionary Research and Development Group
(James Breen); Andrew West's BabelStone; the Oxford-NINJAL Corpus of Old
Japanese; the volunteer transcribers of Aozora Bunko; the Menotec project
and the CLARINO INESS infrastructure at Bergen; George Walkden's HeliPaD;
the Referenzkorpus Mittelhochdeutsch teams at Bochum and Bonn; the
Text Creation Partnership and the Middle English Compendium at Michigan;
the Deutsches Textarchiv at the BBAW; Menota and Språkbanken Text; the
Instituut voor de Nederlandse Taal; the National Institute of Korean
History and the Institute for the Translation of Korean Classics; the
ERC DHARMA project; the National Diet Library and NDL Lab, the National
Institute of Japanese Literature, and the volunteer transcribers of
Minna de Honkoku and the Wikisource projects; the Invisible East
programme at Oxford, Prods Oktor Skjærvø, and the Beyond Boundaries
project; ATMO at Indiana and Lund; Monumenta Altaica; Ilya Yakubovich
and the Luwian corpus team; Michael Streck and Nathan Wasserman's SEAL;
the Bulgarian Academy of Sciences' Scripta Bulgarica; ZRC SAZU and
CLARIN.SI for the Slovenian prose corpora; the Ticha project at
Haverford College; the Royal Danish Library's Guaman Poma edition; the
nk2028 group's rime-book editions; and
Uppsala University's Samnordisk runtextdatabas — this library is *based
on the Scandinavian Runic-text Database*, as its Open Database License
asks to be said. Users of
this software are bound by, and should credit, these upstream projects
under their respective terms.

Sources that could not be ingested for license reasons — however valuable —
are recorded honestly in the repository inventory with the specific
blocking terms and possible unlock paths (for instance the Rahlfs
Septuagint under CATSS conditions, and Brill's in-copyright dictionaries).
