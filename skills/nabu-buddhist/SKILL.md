---
name: nabu-buddhist
description: "Methodological guidance for the buddhist desk of a Nabu library (Buddhologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: buddhist
  origin: generated
  sources: "cbeta derge-kangyur derge-tengyur e84000 gretil mvp sarit suttacentral"
---

# The Buddhologist — the `buddhist` desk

The Buddhologist — the dharma across the Pali, Sanskrit, Chinese and Tibetan canons.

Cross-cutting by design: SuttaCentral, CBETA, SARIT, and GRETIL whole — membership is whole-source, so GRETIL rides here although only part of its shelf is Buddhist — and,, the Derge Kangyur and Tengyur: the fourth canon leg.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `cbeta` | CBETA — Chinese Buddhist Electronic Text Archive | nc |
| `derge-kangyur` | Digital Derge Kangyur (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur) | open |
| `derge-tengyur` | Digital Derge Tengyur (Esukhia/Barom Theksum Choling faithful copy of the Derge edition) | open |
| `e84000` | 84000 — Translating the Words of the Buddha (English Kangyur translations) | nc |
| `gretil` | GRETIL — Göttingen Register of Electronic Texts in Indian Languages (TEI corpus) | nc |
| `mvp` | Mahāvyutpatti — Sanskrit–Tibetan–Chinese glossary (DILA TEI edition) | open |
| `sarit` | SARIT — Search and Retrieval of Indic Texts (scholarly TEI editions) | attribution |
| `suttacentral` | SuttaCentral — bilara-data segmented canon (Pali Tipiṭaka + Chinese Āgamas + aligned English) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `cbeta` — The Chinese Buddhist Electronic Text Archive (CBETA Foundation) in TEI — five collections of the Chinese Buddhist canon. The two central ones are the Taishō Tripiṭaka 大正新脩大藏經 (volumes 1–85) and the Xuzangjing 卍新纂大日本續藏經 (volumes 1–88). Beside them sit the Tripiṭaka Koreana texts that have no Taishō parallel, and the Jiaxing canon 嘉興大藏經: the late-Ming and Qing private canon carved at Jingshan and Jiaxing, rich in Chan recorded sayings (yulu), poetry and monastic writings by Ming–Qing masters. The fifth is the Yuan Heng Temple Hanyi Nanchuan Dazangjing 漢譯南傳大藏經 (70 volumes, 1990–98), a modern Chinese translation of the Pāli Tipiṭaka. It was made from the Japanese Nanden daizōkyō 南傳大藏經 of 1935–41 and keeps Pali Text Society page references beside its lines; it is modern written Chinese, not Literary Chinese. Every text keeps its printed page-register-line citation scheme, so standard references (T85 No. 2884 p.1390a24) apply directly. For the Taishō, the variant readings of the Song, Yuan and Ming editions are carried as apparatus. CC BY-NC-SA 4.0.
- `derge-kangyur` — The Digital Derge Kangyur (Esukhia and Barom Theksum Choling, 2014–2018, building on the 2013 UVA-SOAS eKangyur): the first half of the Tibetan Buddhist canon — the Derge Kangyur whole, 103 volumes covering Tohoku numbers 1–1108, an exact representation of the Library of Congress Derge woodblock prints with even carving and spelling mistakes preserved, proofread against independent transcriptions. Classical Tibetan, every line self-cited by page and line of the printed volumes. Public domain.
- `derge-tengyur` — The Digital Derge Tengyur (Esukhia and Barom Theksum Choling): the second half of the Tibetan Buddhist canon — the Derge Tengyur whole, 213 volumes covering Tohoku numbers 1109–4569, disjoint by design from the Kangyur's 1–1108, in the same faithful page-and-line transcription as its Kangyur companion. Classical Tibetan. Public domain.
- `e84000` — 84000 — Translating the Words of the Buddha: the English translation layer of the Tibetan Buddhist canon — 396 published Kangyur translations and 3 Tengyur publications of sutra, tantra, and dhāraṇī literature, translated by named teams under 84000's editorial process. The body text is English; Tibetan titles (with Wylie transliteration) and Sanskrit where attested ride alongside, with a glossary of terms behind each translation, and everything is keyed to the Tohoku catalogue numbers of the Derge canon. CC BY-NC-ND 3.0.
- `gretil` — Rāmāyaṇa (18,761 verses), Mahābhārata-adjacent texts, Bhāgavata and other purāṇas, Kālidāsa and the kāvya tradition, Brahmasūtra with commentaries and sub-commentaries, dharmaśāstra, Nāṭyaśāstra, Dhvanyāloka with its commentary layers (kārikā vs. vṛtti separately citable as `:DhvK.…`/`:DhvA.…`), Buddhacarita, Gītagovinda, and — recovered by the silent-skip audit — the Mitākṣarā (the standard commentary on Yājñavalkya, 4,788 passages). Only 4 of 784 upstream files remain unparsed: flat verse lists with no numbering of any kind, genuinely unaddressable (and now loudly reported as `unrecognized` in every sync's discovery line).
- `mvp` — Dual-tagged like sdbh (domain + language desk): the 9th-c. glossary IS the Tibetan translators' instrument AND a Buddhist-studies reference. NOT indic — mw itself rides [indic] alone; MVP's Sanskrit side serves the crosswalk, and whole-source membership here is the Tibetan and Buddhist desks' (multi-tagging is dual, not maximal — the house rule).
- `sarit` — Scholarly TEI editions of Sanskrit śāstra — 83 texts including a complete Mahābhārata (Southern Recension), in Devanagari and IAST.
- `suttacentral` — The Pali Tipiṭaka from SuttaCentral — the Buddhist canon in roman-script Pali (Mahāsaṅgīti edition) plus the Patna Dhammapada, with segment-aligned English translations riding the same citation ids.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *What are the Chinese parallels to the Saccavibhaṅga Sutta?* — `nabu_links urn:nabu:suttacentral:mn141`: SuttaCentral's curated parallels as edges: MN 141 ↔ 中阿含經 31 (分別聖諦經, the Madhyama Āgama parallel, lzh) plus DN 22 and two Ekottara Āgama parallels — cross-canon navigation in one call.

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
