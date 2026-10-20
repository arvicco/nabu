---
name: nabu-japonic
description: "Methodological guidance for the japonic desk of a Nabu library (Japanologist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: japonic
  origin: generated
  sources: "aozora edrdg hdic honkoku ja-wikisource kokubunken kouigenji kradfile ndl-kotenseki nrct oncoj oncoj-lexicon unihan wiktionary-recon"
---

# The Japanologist — the `japonic` desk

The Japanologist — Old Japanese song to the Sino-Japanese dictionary tradition.

The Japanese lane, premodern-first: Genji in Ikeda's critical edition at manuscript-line grain, the Kokinshū and two Man'yōshū witnesses in NIJL's TEI, the みんなで翻刻 crowd-transcription mass, and the NRCT historical gazetteer — beside the ONCOJ corpus and lexicon, EDRDG's dictionaries, HDIC and Unihan shared with the Sinologist, and the kaikki ojp extract riding wiktionary-recon.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `aozora` | Aozora Bunko 青空文庫 — Japanese public-domain library (ruby-annotated text) | open |
| `edrdg` | EDRDG — KANJIDIC2 + JMdict (Electronic Dictionary Research and Development Group) | attribution |
| `hdic` | HDIC — Hanzi Dictionaries in Early Japan (Heian lexicography) | attribution |
| `honkoku` | みんなで翻刻 honkoku-data — citizen transcriptions of premodern Japanese documents | attribution |
| `ja-wikisource` | Japanese Wikisource — the premodern era cone (飛鳥–江戸) | attribution |
| `kokubunken` | NIJL kokubunken TEI — 嘉禄二年本古今和歌集 + 廣瀬本/元暦校本万葉集 | attribution |
| `kouigenji` | 校異源氏物語テキストDB — Ikeda's critical Genji, TEI (デジタル源氏物語) | attribution |
| `kradfile` | KRADFILE — EDRDG kanji→component decomposition index (Raine, Breen & EDRDG) | attribution |
| `ndl-kotenseki` | NDL 次世代デジタルライブラリー — 古典籍 OCR full text (bulk API) | open |
| `nrct` | NRCT — 日本歴史地名大系 historical placenames (gazetteer instrument) | attribution |
| `oncoj` | ONCOJ — Oxford-NINJAL Corpus of Old Japanese (release 2021-12-26) | attribution |
| `oncoj-lexicon` | ONCOJ lexicon — Old Japanese dictionary database (release 2021-12-26) | attribution |
| `unihan` | Unihan — the Unicode Han Database | open |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `aozora` — Aozora Bunko 青空文庫 — the volunteer-transcribed Japanese digital library: 17,831 works, overwhelmingly copyright-expired, with a Meiji-and-later core and a thin classical tail (Kojiki, Tosa Diary, Hōjōki in modern critical editions); some 2,285 works preserve pre-reform kyūjitai orthography. Texts carry ruby (furigana) readings alongside the base characters. The public-domain works are freely redistributable under Aozora's own handling guidelines.
- `edrdg` — The Electronic Dictionary Research and Development Group's Japanese reference pair. KANJIDIC2 covers 13,108 kanji of the JIS X 0208/0212/0213 standards with their on and kun readings, English meanings, and nanori name readings; JMdict, in its English edition, is the group's general Japanese–English dictionary of 217,951 entries. Both are living dictionaries, continuously revised upstream. CC BY-SA 4.0.
- `hdic` — HDIC — Hanzi Dictionaries in Early Japan (Ikeda Shoju, Hokkaido University): the earliest Japanese lexicography, character-keyed, in five databases — the Yuanben Yupian fragments (543 CE), Kūkai's Tenrei Banshō Meigi (c. 827–835), the Shinsen Jikyō (c. 898–901) with its Japanese readings, the Songben Yupian (1013), and the Ruiju Myōgishō (Kanchiin manuscript, 12th century) — 96,415 entries in all, cross-linked between dictionaries. Literary Chinese with a Japanese-readings layer. CC BY-SA 4.0.
- `honkoku` — The published text data of Minna de Honkoku (みんなで翻刻), the citizen-science platform where volunteers transcribe premodern Japanese documents: earthquake records, temple archives and other handwritten (kuzushiji) materials. About 6,100 transcribed items are held, one document per item and one passage per page, each linked to its page image and crediting the institution that holds the original. These are crowd transcriptions, not clean editions: the project's own check found about 1.5 errors per hundred characters. The platform's own markup for ruby, split notes and worm damage is kept verbatim. CC BY-SA 4.0.
- `ja-wikisource` — The premodern Japanese texts of Japanese Wikisource, gathered from the wiki's eight era categories from Asuka to Edo: about 840 documents. The Man'yōshū is cited by poem number, its man'yōgana original served as the text with the kundoku and kana readings beside it; prose classics such as the Tsurezuregusa are read paragraph by paragraph, and a full corpus of Bashō's haiku is included. Each page records the base edition it states, or "unstated", and is dated only by the era it is filed under. Texts public domain; transcriptions CC BY-SA 4.0.
- `kokubunken` — The TEI editions published by the National Institute of Japanese Literature (NIJL) on GitHub. The first is the Karoku 2 (嘉禄二年本) Kokin wakashū, the kana preface and 1,031 poems with their headnotes and poets, where the base text is read and variant readings are noted beside it. The second is a Man'yōshū pair: book 1 of the Hirose-bon (廣瀬本, prepared with Kansai University), the only complete witness outside the Sengaku line, and the opening of the Genryaku kōhon (元暦校本). The Man'yōshū poems are served in man'yōgana with the kun reading layer beside them, as witnesses complementary to the other Man'yōshū edition on the shelf. CC BY 4.0.
- `kouigenji` — The Kōi Genji monogatari text database (校異源氏物語テキストDB) of the Digital Genji project (Nakamura, Nagasaki et al.): Ikeda Kikan's 1942 critical edition of the Tale of Genji, all 54 chapters in TEI. The text is cited by the printed edition's page and line, about 25,000 lines, and each page links to its facsimile in the National Diet Library. The 795 waka are marked where they stand in the prose. CC BY 4.0.
- `kradfile` — KRADFILE (Raine, Breen & the EDRDG) — the kanji→component decomposition index behind Jisho's multi-radical search (6,355 kanji, one ~46 KB gz): feeds `nabu char`'s component-index row and `search --char-component` flat containment over its JIS X 0208 span (BabelStone IDS supplies the pan-CJK transitive span beyond it). Licensed by the same EDRDG CC BY-SA 4.0 document the edrdg row quotes → attribution, zero new licence surface.
- `ndl-kotenseki` — The classical books (古典籍) of the National Diet Library's Next Digital Library, as machine-OCR full text: the copyright-expired premodern Japanese books in the NDL's open bibliographic dataset, nearly 98,000 titles, gathered gradually at the gentle pace NDL asks for. Each book is one document, read image by image, labelled as uncorrected OCR, and linked to its NDL viewer permalink. Books are dated by their publication date and faceted by subject and collection. Language is held coarsely as Japanese, though the mass mixes Japanese and kanbun. Copyright-expired materials only; bulk access over this route confirmed by NDL Lab by email (2026).
- `nrct` — The historical placenames of Heibonsha's Nihon rekishi chimei taikei (日本歴史地名大系), made machine-readable by ROIS-DS/NII (GeoShape): some 80,500 Japanese placenames, each with its kana reading, its parent placename, a map point and, for about 20,000 places, the historical form where it differs from the modern one (鍛冶町 from 鍛冶村). It holds no texts. It serves as the gazetteer behind Japanese place lookups, resolving names in either modern or historical spelling. CC BY 4.0.
- `oncoj` — The Oxford-NINJAL Corpus of Old Japanese (Frellesvig et al., Oxford and NINJAL) — 4,991 lemmatized, syntactically parsed poetic texts of the Old Japanese period (7th–8th centuries): the complete Man'yōshū (4,693 texts, books 1–20) plus the song-poems of the Nihon shoki, Kojiki, the Bussokuseki-ka, the fudoki, and the Shoku Nihongi. Every line pairs a romanized grammatical analysis with its original man'yōgana. Annotation CC BY 4.0; the texts themselves are public domain.
- `oncoj-lexicon` — The dictionary database of the Oxford-NINJAL Corpus of Old Japanese: 5,871 entries with romanized headwords, part-of-speech and inflection classes, Eastern Old Japanese variant usage, and compound and derivation relations — the lexicon in which the corpus's own lemmas resolve. Annotation CC BY 4.0.
- `unihan` — The Unicode Han Database (Unihan) — the character reference spine of the CJK world: of 102,999 encoded Han codepoints at Unicode 17.0, 65,092 carry reading or variant data — Mandarin, Japanese on/kun, Korean, and Vietnamese readings, Tang-era readings and Middle Chinese fanqie, English definitions, and the six variant-relation fields. Unicode License V3.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Old Japanese lines about mountains?* — `nabu_search yama (lang: ojp)`: Kojiki kayō and Man'yōshū lines (unebwi yama — Mount Unebi) — the ONCOJ shelf stores romanized Old Japanese, so type romaji.

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
