---
name: nabu-sinitic
description: "Use when searching, reading or citing Literary Chinese texts and Chinese historical phonology through the nabu MCP tools: CBETA, Kanripo, TLS, the Wikisource and Đại Việt classical shelves, Baxter-Sagart and the Qieyun reconstructions, Unihan and the character databases, CHGIS and CBDB. Covers lzh/zho/och/ltc tags, the narrow Han variant fold, the character-bigram lane, print-line citations, gaiji substitutes, reconstructions as attributed hypotheses, duplicate canon editions, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: sinitic
  origin: hand-tuned
  sources: "babelstone-ids baxter-sagart cbdb cbeta chgis classical-modern hdic kanripo kr-gaiji menggu-ziyun obimd qieyun-restored shuowen suttacentral tls tshet-uinh ud unihan viet-wikisource wiktionary-recon zh-wikisource zhongyuan"
---

# The Sinologist — the `sinitic` desk

The Sinologist — the classical Chinese written world and its phonological deep past.

Literary and classical Chinese with its reconstruction instruments: Kanripo and CBETA, TLS, Baxter-Sagart and the Qieyun-system database, Unihan, the Heian hanzi dictionaries, the UD lzh treebanks, SuttaCentral's Agamas, the kaikki zh extract riding wiktionary-recon —, the Đại Việt classical shelf (the sinographic cosmopolis reaching Vietnam, as sillok reaches Korea) — and,, the desk's instruments: the CHGIS historical gazetteer (TGAZ placenames, 221 BCE–1911) and the CBDB prosopography artifact (~658k persons, held for the persons-layer ruling).

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `babelstone-ids` | BabelStone IDS — Ideographic Description Sequences for CJK Ideographs (Andrew West) | open |
| `baxter-sagart` | Baxter-Sagart Old Chinese reconstruction (2015-10-13 TSV, yawnoc dump) | attribution |
| `cbdb` | CBDB — China Biographical Database (prosopography instrument) | nc |
| `cbeta` | CBETA — Chinese Buddhist Electronic Text Archive | nc |
| `chgis` | CHGIS/TGAZ — China Historical GIS Temporal Gazetteer (gazetteer instrument) | open |
| `classical-modern` | Classical-Modern — Classical↔Modern Chinese parallel corpus (NiuTrans) | attribution |
| `hdic` | HDIC — Hanzi Dictionaries in Early Japan (Heian lexicography) | attribution |
| `kanripo` | Kanripo — Kanseki Repository 漢籍リポジトリ (waves 1–3: KR1 classics, KR2 histories, KR3 masters, KR4 belles-lettres, KR5 Daoist canon) | attribution |
| `kr-gaiji` | KR-Gaiji — Kanseki Repository not-yet-encoded characters (gaiji resolution map) | attribution |
| `menggu-ziyun` | menggu-ziyun-data — 蒙古字韻 'Phags-pa rhyme book (nk2028) | attribution |
| `obimd` | OBIMD — Oracle Bone Inscriptions Multi-modal Dataset (KLOBIP) | attribution |
| `qieyun-restored` | qieyun-restored — 切韻 Fujita restoration (nk2028) | attribution |
| `shuowen` | 說文解字 Shuowen Jiezi — the shuowen.org data repo | attribution |
| `suttacentral` | SuttaCentral — bilara-data segmented canon (Pali Tipiṭaka + Chinese Āgamas + aligned English) | open |
| `tls` | TLS — Thesaurus Linguae Sericae (tls-kr/tls-data: concepts + words) | attribution |
| `tshet-uinh` | tshet-uinh-data — 廣韻 critical edition (nk2028 Qieyun-system database) | open |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `unihan` | Unihan — the Unicode Han Database | open |
| `viet-wikisource` | Đại Việt classical shelf — 大越史記全書 + chữ Hán showpieces (Wikisource) | attribution |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
| `zh-wikisource` | Chinese Wikisource — censused works (全唐文 · 續資治通鑑 · 元朝秘史) | attribution |
| `zhongyuan` | zhongyuan-data — 中原音韻 Old Mandarin rhyme book (nk2028) | open |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `babelstone-ids` — BabelStone IDS, compiled by Andrew West (魏安) — Ideographic Description Sequences giving a structural decomposition for every CJK Unified Ideograph: 97,680 entries at Unicode 16.0, each character analyzed as a tree of components (棄 = ⿳亠厶⿻廿木), with alternative sequences for regional glyph forms. The reference table for finding Chinese characters by their parts. Released with a public-domain dedication.
- `baxter-sagart` — Baxter and Sagart's reconstruction of Old Chinese (Old Chinese: A New Reconstruction, Oxford, 2014) in tabular form — 4,959 entries over 4,056 distinct characters (722 polyphones), each with pinyin, a Middle Chinese transcription and structural analysis, the Old Chinese reconstruction, an English gloss, and GSR and Hanyu Da Zidian references. The field's standard reference reconstruction of Old Chinese. CC BY 4.0 from the authors.
- `cbdb` — The China Biographical Database (Harvard, Academia Sinica and Peking University; Peter Bol et al.), the prosopography of Chinese history. It covers some 658,000 people from the 7th to the 19th century, with their names and transcriptions, dates, offices, kinship and place associations, and it is held as the project's own SQLite release, checked against the checksum the project publishes. It is a reference instrument behind the person lookups, not a text shelf. CC BY-NC-SA 4.0 as stated on the project site (the Hugging Face dataset card agrees); mainland-China commercial rights are licensed separately. Kept verbatim for local research.
- `cbeta` — The Chinese Buddhist Electronic Text Archive (CBETA Foundation) in TEI — five collections of the Chinese Buddhist canon. The two central ones are the Taishō Tripiṭaka 大正新脩大藏經 (volumes 1–85) and the Xuzangjing 卍新纂大日本續藏經 (volumes 1–88). Beside them sit the Tripiṭaka Koreana texts that have no Taishō parallel, and the Jiaxing canon 嘉興大藏經: the late-Ming and Qing private canon carved at Jingshan and Jiaxing, rich in Chan recorded sayings (yulu), poetry and monastic writings by Ming–Qing masters. The fifth is the Yuan Heng Temple Hanyi Nanchuan Dazangjing 漢譯南傳大藏經 (70 volumes, 1990–98), a modern Chinese translation of the Pāli Tipiṭaka. It was made from the Japanese Nanden daizōkyō 南傳大藏經 of 1935–41 and keeps Pali Text Society page references beside its lines; it is modern written Chinese, not Literary Chinese. Every text keeps its printed page-register-line citation scheme, so standard references (T85 No. 2884 p.1390a24) apply directly. For the Taishō, the variant readings of the Song, Yuan and Ming editions are carried as apparatus. CC BY-NC-SA 4.0.
- `chgis` — The China Historical GIS Temporal Gazetteer (TGAZ), from Harvard and Fudan: historical Chinese placenames from 221 BCE to 1911. It holds about 82,000 names in Chinese characters and pinyin, each with its years of validity, feature type, parent administrative unit and map point, released as the 2018 database dump on Harvard Dataverse. It holds no texts. It serves as the gazetteer behind place lookups and place-mention mining on the Sinitic shelf, at some 81,000 distinct places. The Dataverse record releases the data under CC0 1.0.
- `classical-modern` — NiuTrans's Classical-Modern corpus, the largest Classical-to-Modern Chinese parallel collection: about 967,000 sentence pairs across 97 classical works, held chapter by chapter (some 7,300 chapters). Each chapter pairs the classical text, one sentence per line, with a line-aligned Modern Chinese translation held as its own sibling document, so the two can be read side by side. The modern translations were crawled from the web, as the project itself says, and each chapter carries the list of sites it came from; they are not scholarly translations. Both sides are in simplified characters, a modern re-encoding rather than a traditional-script witness. MIT licence.
- `hdic` — HDIC — Hanzi Dictionaries in Early Japan (Ikeda Shoju, Hokkaido University): the earliest Japanese lexicography, character-keyed, in five databases — the Yuanben Yupian fragments (543 CE), Kūkai's Tenrei Banshō Meigi (c. 827–835), the Shinsen Jikyō (c. 898–901) with its Japanese readings, the Songben Yupian (1013), and the Ruiju Myōgishō (Kanchiin manuscript, 12th century) — 96,415 entries in all, cross-linked between dictionaries. Literary Chinese with a Japanese-readings layer. CC BY-SA 4.0.
- `kanripo` — The Kanseki Repository 漢籍リポジトリ (Christian Wittern, Kyoto): the open Classical Chinese library — thousands of premodern Chinese texts organized by the traditional fourfold classification, the classics (經), histories (史), masters (子), and belles-lettres (集), together with the Daoist canon (道). Each text is transcribed against a named base print edition, with the print pagination carried in the text. CC BY-SA 4.0.
- `kr-gaiji` — Feature module, not a corpus (kind: module — mints no documents): the Kanripo gaiji resolution map (KR-Gaiji charlist, a few hundred KB). Censused whole: 5,254 refs / 1.75M occurrences in the kanseki corpus, 972 refs (36.4% of occurrences) resolving to real codepoints in `--display reading`; the rest render an honest ⬚ with a counted footer. The row exists so config/gaiji/kanripo.tsv can be regenerated through the sanctioned GitFetch path when KR-Gaiji advances. Nothing to serve or flip.
- `menggu-ziyun` — The Menggu ziyun (蒙古字韻, 1308), the rhyme book in 'Phags-pa script that is the primary phonological record of Old Mandarin, in nk2028's digitization of Shen Zhongwei's 2015 collated edition, with revisions and reconstructions by unt (2023) and variant forms from ccamc.org. It is a dictionary shelf of about 9,450 character entries across 853 small rhymes. Each entry gives the 'Phags-pa spelling, tone, rhyme class, a reconstruction and transcription, variant forms, editorial verdicts and the matching Qieyun-system position, which ties it to the Guangyun on the same shelf. Language is held coarsely as Chinese at the Old Mandarin stage. MIT licence over the digitization; the 1308 book itself is public domain.
- `qieyun-restored` — The Qieyun (切韻) of Lu Fayan (601 CE), the founding rhyme dictionary of Middle Chinese and the parent of the Guangyun, in Fujita Takumi's restoration (2017 thesis, 2023 monograph), extracted from the thesis's appendix table by nk2028. It is a dictionary shelf of about 11,160 character entries. Each gives the phonological position, tone, rhyme heading, small-rhyme number, headword and definition, with the fanqie spellings inside the definitions, and each is cited by its page and row in Fujita's table. Li Yongfu's parallel restoration, which ships in the same repository, is not included. MIT licence over the extraction; the 601 text itself is public domain.
- `suttacentral` — The Pali Tipiṭaka from SuttaCentral — the Buddhist canon in roman-script Pali (Mahāsaṅgīti edition) plus the Patna Dhammapada, with segment-aligned English translations riding the same citation ids.
- `tls` — TLS — Thesaurus Linguae Sericae (Christian Harbsmeier et al.) — an onomasiological concept net over Classical Chinese: 3,018 concepts linked to 20,163 words and over 60,000 senses, with definitions, synonym-group criteria, concept-graph relations (hypernymy, antonymy, taxonomy), per-form pinyin plus Middle and Old Chinese readings, and roughly 190,000 textual attestations keyed to classical editions. CC BY-SA 4.0.
- `tshet-uinh` — A critical edition of the Guangyun (廣韻), the Middle Chinese rhyme dictionary, from the nk2028 Qieyun-system database: 25,336 entries at character-by-phonological-position grain across 3,884 homophone groups, each with its phonological formula, fanqie spelling, direct readings, and definition — the Zezuntang (澤存堂) base text with scholarly corrections carried as explicit annotations, never silent fixes. CC0 1.0.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `unihan` — The Unicode Han Database (Unihan) — the character reference spine of the CJK world: of 102,999 encoded Han codepoints at Unicode 17.0, 65,092 carry reading or variant data — Mandarin, Japanese on/kun, Korean, and Vietnamese readings, Tang-era readings and Middle Chinese fanqie, English definitions, and the six variant-relation fields. Unicode License V3.
- `viet-wikisource` — The Đại Việt classical shelf, from Chinese and Vietnamese Wikisource: the 大越史記全書 (Đại Việt sử ký toàn thư — the Complete Annals of Đại Việt, in the 1697 Chính Hòa edition) whole, front matter plus its 29 books of outer and basic annals, together with the showpieces of Vietnamese chữ Hán letters — Nguyễn Trãi's 平吳大誥 (Bình Ngô đại cáo, 1428) beside its Hán-Việt reading, and Trần Hưng Đạo's 諭諸裨將檄文 (Hịch tướng sĩ, 1284). All in the literary Chinese of Vietnam's scholarly tradition. The texts are public domain; the transcription layer is CC BY-SA 4.0, credited to the Wikisource contributors.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.
- `zh-wikisource` — Three complete works from Chinese Wikisource. The first is the Quan Tang wen (全唐文), the Qing-compiled canon of Tang prose, in all 1,001 juan, each assembled from its individual piece pages. The second is Bi Yuan's Xu Zizhi tongjian (續資治通鑑) in 221 parts. The third is the Yuanchao mishi (元朝秘史, the Secret History of the Mongols) in the Ming Chinese summary translation, which is what the wiki hosts; no Mongolian text is present, so the work is claimed as Chinese. That makes about 1,240 documents. No page states its base edition, and each records that honestly. Texts public domain; transcriptions CC BY-SA 4.0.
- `zhongyuan` — The Zhongyuan yinyun (中原音韻) of Zhou Deqing (1324), the rhyme book for qu verse that is the arch-source of Old Mandarin phonology, in nk2028's dataset. It holds about 5,880 character entries, each with its initial, final and tone in the Zhongyuan system (the entering tone already redistributed), and four scholarly reconstructions side by side: 楊耐思 (1981), 寧繼福 (1985), 薛鳳生 (1990) and unt (2021). The editorial notes on corrections and variant readings are kept verbatim. Together with the Menggu ziyun it completes the Old Mandarin pair beside the Qieyun and Guangyun. CC0.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Scan 仁義 usage across the Chinese canon.* — `nabu_concord 仁義 (lang: lzh)`: KWIC rows in corpus order from CBETA's historiographical treatises — left context, keyword, right context in the pristine text.

## Field semantics on this desk

- **Language tags.** Literary Chinese is `lzh` (CBETA, Kanripo, the Vietnamese
  and Wikisource classical shelves); `zho` covers the character databases and
  the Yuan-era rhyme books; `och` (Old Chinese) and `ltc` (Middle Chinese) are the
  reconstruction dictionaries; `cmn` the modern side of the classical-modern
  pairs.
- **The Han variant fold is narrow and deliberate.** For `lzh` and `och`, the
  index folds Unihan's simplified/traditional and Z-variant pairs onto the
  traditional form. Semantic variants are not folded, and characters with more
  than one traditional counterpart are refused (`发` is not folded; `时` does not
  find `時`). A variant spelling can therefore hide a hit: search the
  traditional form and the attested variant both.
- **Han runs are indexed as overlapping pairs.** A pure-Han query is answered by
  a character-bigram lane over the flagged sources, so substrings inside
  unpunctuated running text are found; word-boundary matching does not exist for
  Han.
- **Citations follow the print.** CBETA documents are canon + volume + work
  (`T85n2884`), passages the print line (page, register, line: `1390a24`).
  Kanripo passages are juan and leaf side. Taishō page lines and Derge folios
  are disjoint schemes; there is no shared canon citation hub.
- **Missing characters (gaiji).** Kanripo keeps its gaiji references in the
  text; reading renders the faithful glyph where one exists, else an
  ideographic description, else a marked substitute. CBETA stores its fallback
  rendering as the text, with the references in annotations. A substitute glyph
  in a quotation must be marked as such.
- **Reconstructions are dictionaries of hypotheses.** Baxter–Sagart Old and
  Middle Chinese, the Guangyun-based Qieyun system database and Fujita's
  restored Qieyun are separate shelves with separate systems; a reconstruction is
  a scholar's analysis, cite it with its author. Corrections from the critical
  apparatus of the rhyme books are annotations, never silent fixes.
- **TLS** (Thesaurus Linguae Sericae) is a concept-and-word dictionary whose
  attestations resolve into Kanripo passages.
- **Instruments.** CHGIS is a historical gazetteer (place identities with time
  spans); CBDB is a prosopography held as a module — there is no MCP person
  tool, and the Han character card is command-line only (`nabu_char` answers a
  note for Han characters).

## Conflation traps

- CBETA's Āgamas and SuttaCentral's Chinese Āgama texts are the same canon
  in two editions, not deduplicated.
- A Kanripo master-branch text is the project's base edition, not a manuscript
  witness; the Wikisource shelves are transcriptions of varying, often
  unstated, editorial basis.
- Modern translations in the classical-modern pairs are not witnesses of the
  classical text.

## Licensing on this desk

CBETA and the CBDB module are `nc`; Kanripo, TLS, Baxter–Sagart and the
Wikisource shelves are `attribution`; Unihan, the Qieyun system database and
the CHGIS gazetteer are `open`.

## House cautions

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
