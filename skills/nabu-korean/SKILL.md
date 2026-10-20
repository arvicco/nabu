---
name: nabu-korean
description: "Methodological guidance for the korean desk of a Nabu library (Koreanist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: korean
  origin: generated
  sources: "bibyeonsa goryeosa goryeosa-jeoryo itkc itkc-catalog ko-wikisource-mk okhc sillok sjw"
---

# The Koreanist — the `korean` desk

The Koreanist — the hanmun state record and the first hangul vernacular.

The Korean desk opens on the dynastic record itself: the Veritable Records of Joseon (sillok) in the original hanmun via NIKH's open XML dumps, joined by the Goryeosa family on the same DTD (the pre-Joseon dynastic history, its chronological digest, and the state council's daily register), with the Seungjeongwon ilgi and the ITKC classics to follow, and the Middle Korean Wikisource shelf as the vernacular leg. Since the OKHC historical slice widens the desk beyond the state record: the Samguk sagi (the oldest Korean history), the Ilseongnok, the ITKC munjip mass, and the AKS/Kyujanggak/NHM old-literature shelves, each record carrying its own PD-vs-nc label.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `bibyeonsa` | 비변사등록 원문 — Records of the Border Defense Command (NIKH) | attribution |
| `goryeosa` | 고려사 원문 — History of Goryeo (NIKH) | attribution |
| `goryeosa-jeoryo` | 고려사절요 원문 — Essentials of Goryeo History (NIKH) | attribution |
| `itkc` | 한국고전번역원 고전원문·고전총간 — ITKC classical originals (open datasets) | attribution |
| `itkc-catalog` | ITKC 한국고전종합DB 서지 catalog — author-era instrument (OpenAPI MO/GO/KP 서지) | nc |
| `ko-wikisource-mk` | 용비어천가 — Middle Korean vernacular shelf (Korean Wikisource) | attribution |
| `okhc` | Open Korean Historical Corpus (historical slice) | nc |
| `sillok` | 조선왕조실록 원문 — Veritable Records of the Joseon Dynasty (NIKH) | attribution |
| `sjw` | 승정원일기 — Daily Records of the Royal Secretariat (NIKH) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `bibyeonsa` — 비변사등록 — the Records of the Border Defense Command (Bibyeonsa deungnok; National Institute of Korean History): the daily register of the council that became later Joseon's de-facto supreme organ of state, surviving for 1617–1892 — 273 register books of hanmun memoranda, deliberations on defense, taxation, famine relief and appointments, each session opening with the attendance roster of the assembled ministers. The working record behind the polished dynastic annals. Served under Korea's open public-data grant, credited to the institute.
- `goryeosa` — 고려사 — the History of Goryeo (1451; Jeong Inji and the Joseon court historiographers): the official history of the Goryeo dynasty (918–1392), compiled in the traditional Chinese annals-treatises format — royal annals (世家), thematic treatises (志) on astronomy, geography, law and music, chronological tables (表), and the biographies (列傳) of ministers, generals, rebels and loyalists — in hanmun across 139 fascicles. The National Institute of Korean History's edition, served under Korea's open public-data grant, credited to the institute.
- `goryeosa-jeoryo` — 고려사절요 — the Essentials of Goryeo History (1452; Kim Jongseo and the Joseon court historiographers): the strictly chronological digest of the Goryeo dynasty's history, compiled one year after the full 고려사 as its year-by-year companion — 35 fascicles of hanmun annals that condense the reigns of 918–1392 and preserve editorial judgments and details the full history's topical format does not carry. The National Institute of Korean History's edition, served under Korea's open public-data grant, credited to the institute.
- `itkc` — The open slice of the Institute for the Translation of Korean Classics' 한국고전종합DB: seventeen complete hanmun works from the classical-originals and 고전총간 series — Yu Deuk-gong's scholarly miscellany 고운당필기, the royal-precedents compilation 국조보감, Yi Yu-won's 임하필기, the legal digest 전율통보, the great geographic compendia (신증동국여지승람, 대동지지) and the biographical and memorial collections (국조인물고 among them). Article-grain texts with the institute's genre classifications, proper-name tags and authors' dates. Served under Korea's open public-data grant, credited to the institute.
- `itkc-catalog` — The bibliographic catalog of the Institute for the Translation of Korean Classics (한국고전번역원) for three of its collections: the 한국문집총간, the standard corpus of 1,259 collected works (munjip) of Korean literati from late Silla to the end of Joseon, plus 257 classical originals (고전원문) and 24 works of the 한국고전총간. Each record names a work, its author in hangul and hanja, the author's birth and death years and the year the work was first printed. It holds no texts: the author years date the munjip records of the Open Korean Historical Corpus and the institute's own fascicles held in the library, as the era of each work's author. Read from the institute's open search API; the institute reserves its database content, so only these facts are used, for non-commercial research.
- `ko-wikisource-mk` — 용비어천가 — Songs of the Dragons Flying to Heaven (1447; Jeong Inji, An Ji & Gwon Je), from Korean Wikisource: all 125 cantos of the dynastic eulogy composed for the new Joseon house — the first work ever printed in hangul. The Middle Korean verse is carried in the archaic orthography (arae-a, light lip sounds, side-dot tone marks), beside the 1447 print's parallel Chinese verse where the contributors have transcribed it and a modern Korean rendering. The 1447 text is public domain; the Wikisource transcription layer is CC BY-SA 4.0, credited to the contributors.
- `okhc` — The historical core of the Open Korean Historical Corpus (Seyoung Song et al., KAIST), which compiles 1,300 years of Korean historical text from institutional archives. The portion held here covers the Samguk sagi (1145, the oldest Korean history), the Ilseongnok (Records of Daily Reflections), the Korean Classics' collected-works mass, the Gaksa deungnok, the Copyright Commission's public-domain collection, the old-literature databases of the AKS, Kyujanggak and National Hangeul Museum, and the Hanmun legation records. In all that is about 1.2 million records, each titled and dated. Most are Literary Chinese, with Korean, a little Middle Korean, and some Japanese, English and French. Archives held elsewhere in the library, the modern newspapers and contemporary North Korean material are left out. CC BY-NC 4.0, confirmed by the author for personal research (2026), with the OKHC paper credited; records marked public domain are open.
- `sillok` — 조선왕조실록 — the Veritable Records of the Joseon Dynasty (National Institute of Korean History): the complete dynastic annals of the 25 Joseon reigns (1392–1863) with the colonial-era supplements for Gojong and Sunjong, in the original literary Chinese (hanmun). Compiled reign by reign by the state historiographers from the daily records of the court, the sillok carry day-by-day articles under seven parallel calendar systems, interlinear editors' notes, and the archive citations of the mountain repositories that preserved them; a UNESCO Memory of the World inscription. Served under Korea's open public-data grant, credited to the institute.
- `sjw` — 승정원일기 — the Daily Records of the Royal Secretariat of Joseon (Seungjeongwon ilgi; National Institute of Korean History): the day-by-day register of the office through which every document to and from the throne passed, surviving from 1623 (Injo) to 1910 — over 240 million characters of hanmun, one of the largest single historical records in existence. Every day opens with the weather entry (one of the longest daily weather series anywhere), then the duty roster of secretaries and scribes, then the audiences, memorials and royal orders of the day. Served under Korea's open public-data grant, credited to the institute.

## Working cautions

- **Data license is not code license.** This guidance text is MIT; every passage
  carries its own `license_class` (`open`, `attribution`, `nc`, `odbl`, and — excluded
  by default — `research_private` / `restricted`). `nc` forbids commercial reuse of the
  quoted text; `attribution` and `odbl` require naming the source edition (`odbl`
  also binds derived databases to share-alike). A `credit` key, when present, must
  travel with any quotation.
- **An empty result is not absence of evidence.** Call `nabu_status` before concluding
  a text, word or form is unattested: the shelf may be unsynced on this box, the
  language may be indexed at another grain, or the class may be excluded by default.
- **Search is folded, `nabu_show` is pristine.** Matching runs over a folded form
  (case, diacritics, and per-language rules); quote only the pristine text
  `nabu_show` returns, never a search snippet or a folded phrase.
- **Lemma tiers differ in evidential weight.** `gold` lemmas are verified annotation
  and the only tier that counts as attestation; `silver` lemmas are upstream-automatic
  and always labeled; `equivalence` rows are glosses, never attestation. A lemma
  search reaches only the lemmatized minority of the corpus.
- **Dates are typed.** A document's primary dated row has a class — `artifact` (the
  object's own dating), `composition` (an attributed author-era date), `edition` (a
  print year, never the text's date), or `silver` (a tool estimate, never an upstream
  claim). Years are signed, with no year 0. Use `date_basis` to keep the classes
  apart.

## Reproducibility

Record, per claim: the passage or document `urn`, the `source` slug, its
`license_class` (and `credit` when served), the exact tool call and arguments, and the
date of the `nabu_status` snapshot the catalog answered from. Upstream editions are
revised; the urn plus the catalog date is the citation, the snippet is not.
