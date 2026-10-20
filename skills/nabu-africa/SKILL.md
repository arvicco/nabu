---
name: nabu-africa
description: "Methodological guidance for the africa desk of a Nabu library (Africanist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: africa
  origin: generated
  sources: "africa-pd bu-ajami old-nubian-ud"
---

# The Africanist — the `africa` desk

The Africanist — Ajami manuscripts beyond the Nile–Ethiopia axis, Hausa praise poems to Wolof Murid verse.

Africa beyond the Egyptian and Ethiopic desks: the NEH Ajami collection's Hausa, Mandinka, Fula and Wolof manuscripts in romanized transcription, the public-domain reference shelf in archive.org's uncorrected OCR — Griffith's Old Nubian texts, the Swahili of Steere, Taylor, Büttner and Velten, Schön's and Robinson's Hausa, Hanoteau's Tuareg grammar and Kabyle poetry, Koelle's Vai — and the Old Nubian UD treebank, the medieval Nile kingdoms' language parsed word by word.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `africa-pd` | PD African-languages reference shelf — Griffith, Steere, Taylor, Büttner, Velten, Schön, Robinson, Hanoteau, Koelle (archive.org scans, uncorrected OCR) | open |
| `bu-ajami` | African Ajami Library — NEH Ajami collection (Boston University): Hausa, Mandinka, Fula and Wolof manuscripts in romanized transcription | nc |
| `old-nubian-ud` | Old Nubian UD Treebank (Innokentii Smirnov) | nc |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `africa-pd` — The public-domain reference canon for African languages beyond Egypt and Ethiopia, as Internet Archive scans. It holds Griffith's edition of the Old Nubian texts of the Christian period (1913); four Swahili classics — Steere's Swahili Tales as told by natives of Zanzibar (1870), Taylor's African Aphorisms (1891), Büttner's Anthologie aus der Suaheli-Litteratur (1894) and Velten's Prosa und Poesie der Suaheli (1907); two Hausa collections — Schön's Magána Hausa (1885) and Robinson's Specimens of Hausa Literature (1896); Hanoteau's Tuareg grammar (1860) and his Kabyle popular poetry (1867); and Koelle's Vai grammar (1854). There are ten volumes, one passage per scanned page. Most are missionary and academic editions in English, German or French presenting the African texts with translation, so each claims its editorial language and names the African language it presents; Velten's reader, Swahili throughout, claims Swahili. The text is the archive's uncorrected OCR, declared as such with a measured quality figure per volume: the prose and Latin-transcribed texts read, while Old Nubian, Arabic-script, Tifinagh and Vai-script matter is garbled. All authors died by 1935 and every print predates 1914: public domain.
- `bu-ajami` — Manuscripts in Ajami — African languages written in Arabic script — from Boston University's NEH Ajami collection, led by Fallou Ngom: eighty items, twenty each in Hausa (northern Nigeria), Mandinka (Casamance, southern Senegal), Fula (the Pular of Fuuta Jalon, Guinea) and Wolof (Senegal, mostly from the Murid community of Touba). They are praise poems and admonitions, elegies and devotional verse by poets such as Nana Asmaʾu, Serigne Moussa Ka, Serigne Mor Kayre and Sitookoto Daabo, alongside letters, community minutes, family histories, biographies, speeches of the Murid Caliph, a numerology manual and a Wolof Ajami newspaper — from the nineteenth century to the 2000s. The text held here is the editors' typed romanized transcription of each manuscript, one passage per transcription page; each item keeps its provenance, genre, the manuscript's description and links to the manuscript images and the English and French translations. Licensed CC BY-NC 4.0: non-commercial use with credit to the original author and the collection.
- `old-nubian-ud` — The first machine-readable treebank of Old Nubian, the written language of the medieval Nile kingdoms of Nobadia and Makuria (attested from about the 8th to the 15th century), built by Innokentii Smirnov in Universal Dependencies. Its 124 sentences, given in Latin transliteration rather than the manuscripts' Coptic-derived alphabet, come from the Miracle of Saint Menas — a woman's vowed egg, a forgetful ship's captain and the saint on his white horse — from a homily on church offerings and the eucharist, and from short scriptural fragments including the Emmanuel verse. Every word is lemmatized, tagged for part of speech and grammatical features, placed in a dependency tree and segmented into glossed morphemes, and nearly every sentence carries a Russian (the Menas miracle) or English translation; lacunae and editorial restorations are kept as the edition marks them. CC BY-NC-SA 4.0, by the author's grant.

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
