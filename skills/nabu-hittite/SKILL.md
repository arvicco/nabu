---
name: nabu-hittite
description: "Methodological guidance for the hittite desk of a Nabu library (Hittitologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: hittite
  origin: generated
  sources: "aclt hittite-glossed tlhdig ud wiktionary-hit"
---

# The Hittitologist — the `hittite` desk

The Hittitologist — Anatolia in cuneiform, KBo and KUB by tablet and line.

The Hittite desk: TLHdig's tablet corpus (dual-tagged cuneiform by ruling — its lines also carry Akkadian, Sumerian, Luwian, Hattic, Hurrian), the glossed Hittite texts, the UD Hittite treebank, and ACLT's Hieroglyphic Luwian inscriptions.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `aclt` | ACLT — Annotated Corpus of Luwian Texts (Yakubovich) | research_private |
| `hittite-glossed` | Glossed Hittite Texts with German Translation (Zenodo) | open |
| `tlhdig` | TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Beta 0.3, Zenodo 20328284) | attribution |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `wiktionary-hit` | Wiktionary Hittite — kaikki.org machine-readable extract | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `aclt` — The Annotated Corpus of Luwian Texts: Ilya Yakubovich's annotated edition of the Hieroglyphic Luwian inscriptions, served on Timofey Arkhangelskiy's Tsakorpus platform (luwian.web-corpora.net). About 266 inscriptions, cited by their conventional names (KARKAMIŠ A4b and the like), are divided into some 2,700 clauses. Each clause is held twice: as a broad transcription with full morphological analysis (lemma, part of speech, case, gender, number, English gloss) and as a sign-by-sign hieroglyphic transliteration. Only the hieroglyphic tradition is covered; cuneiform Luwian is not. Held under a personal research grant from I. Yakubovich (2026) that credits the corpus and his editorship on every text. Never redistributed.
- `hittite-glossed` — Glossed Hittite Texts with German Translation for Machine Learning (Zenodo, version 1.0; presented at ALP 2025): some 7,100 Hittite texts in about 170,000 glossed words. Every word carries a broad transcription, its syllabic transliteration, a morphological gloss and a German translation gloss, aligned word by word. Texts are cited by their publication numbers (KUB, KBo, IBoT and so on) and read manuscript line by manuscript line, and each is tagged with its CTH catalogue number, so the shelf lines up with the Hittite fragment editions. The deposit carries no dates or findspots. CC BY 4.0.
- `tlhdig` — TLHdig — Thesaurus Linguarum Hethaeorum digitalis (Hethitologie-Portal Mainz): the Hittite corpus, covering more than 98% of published cuneiform fragments from the Hittite tablet collections in transliteration — 23,937 per-manuscript documents organized by CTH number, with line-grain transliteration, Unicode cuneiform, and candidate morphological analyses. Predominantly Hittite, with Akkadian, Hurrian, Hattic, Luwian, Sumerian, and Palaic passages. CC BY 4.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `wiktionary-hit` — English Wiktionary's Hittite lexicon, as extracted by kaikki.org (wiktextract, Tatu Ylönen): about 480 entries with sense glosses, etymologies and descendant trees. Most entries (some 414) are headed in cuneiform (𒉿𒀀𒋻 wātar "water"), so their senses attach to the cuneiform sign cards beside the Hittite tablet corpus. About a hundred are romanization pointers. The descendant trees record borrowings such as the Hittite-to-Akkadian lane. CC BY-SA and GFDL, as Wiktionary.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Find nepišaš — 'of heaven' — in the tablets.* — `nabu_search "ne-pi-ša-aš" (lang: hit)`: Mythological fragments (KBo 26.91, KBo 26.120) with damage brackets preserved. The desk's lesson: TLHdig stores the syllabified transliteration, so type it hyphenated — the diacritic fold maps pí to pi for you.

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
