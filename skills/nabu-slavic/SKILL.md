---
name: nabu-slavic
description: "Methodological guidance for the slavic desk of a Nabu library (Slavicist): what its sources hold, their license classes, and the cautions to observe when searching, reading and citing them through the nabu MCP tools."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: slavic
  origin: generated
  sources: "archiv-slav-phil bg-wikisource ccmh cs-wikisource damaskini elektire eltec-srp freising gams-zrcalo goo300k hr-wikisource imp kdsp korba litopys mdz-protestant mk-wikisource pl-wikisource prague-bible-1488 prilit proiel ru-wikisource scat scripta-bulgarica sl-lexica sl-wikisource slavistics-pd slouniki-nasovic sr-wikisource torot ud uk-wikisource vuk-danicic wiktionary-cu"
---

# The Slavicist — the `slavic` desk

The Slavicist — Cyril and Methodius to the damaskini, canon to vernacular.

Old Church Slavonic and its daughters: the OCS/Old Russian treebanks, the gospel and monument corpora, Freising, the Slovenian historical lane with PriLit's earliest narrative prose (1643–1866), Balkan damaskini, and the Church Slavonic dictionary shelves.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `archiv-slav-phil` | Archiv für slavische Philologie, Bd. 1–35 (archive.org scans, uncorrected OCR) | open |
| `bg-wikisource` | Bulgarian Wikisource — medieval charters + История славянобългарска | attribution |
| `ccmh` | CCMH — Corpus Cyrillo-Methodianum Helsingiense (Kielipankki) | attribution |
| `cs-wikisource` | Czech Wikisource — censused premodern works (Dalimil · Bible kralická · Komenský · Harant) | attribution |
| `damaskini` | Damaskini — Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1 (CLARIN.SI) | attribution |
| `elektire` | eLektire — the Croatian school canon (CARNET / Bulaja naklada) | open |
| `eltec-srp` | ELTeC-srp — the Serbian novel collection of the European Literary Text Collection | attribution |
| `freising` | Freising Manuscripts / Brižinski spomeniki (eZISS, ZRC SAZU) | research_private |
| `gams-zrcalo` | Zrcalo člověčaskago spasenja (1445) — GAMS digital edition (Kramarić & Schneider, Graz) | attribution |
| `goo300k` | goo300k — reference corpus of historical Slovene (CLARIN.SI) | attribution |
| `hr-wikisource` | Croatian Wikisource — the premodern century cone (srednji vijek–18. stoljeće) | attribution |
| `imp` | IMP — digital library and corpus of historical Slovene (CLARIN.SI) | attribution |
| `kdsp` | KDSP — Corpus of longer narrative Slovenian prose 1836–1918 (ZRC SAZU, CLARIN.SI) | attribution |
| `korba` | KorBa — manually annotated subcorpus 2.0 (17th–18th-c. Polish, IJP PAN) | attribution |
| `litopys` | Izbornyk (litopys.org.ua) — the PD-edition subset: the Ipatiev chronicle + glossaries | open |
| `mdz-protestant` | MDZ — 16th-century Slovene/Croatian Protestant prints, page OCR (Bayerische Staatsbibliothek) | open |
| `mk-wikisource` | Macedonian Wikisource — the 19th-century cone (Миладиновци · Шапкарев · Цепенков · Пејчиновиќ · Крчовски · Пулевски) | attribution |
| `pl-wikisource` | Polish Wikisource — the premodern Polish-literature cone (+ Brückner's etymological dictionary) | attribution |
| `prague-bible-1488` | Prague Bible 1488 — HTR Winter School 2024 Medieval Czech ground truth | attribution |
| `prilit` | PriLit — older Slovenian narrative prose (ZRC SAZU/JSI, CLARIN.SI) | attribution |
| `proiel` | PROIEL Treebank | nc |
| `ru-wikisource` | Russian Wikisource — the Old East Slavic cone (edition-filtered) | attribution |
| `scat` | SCAT — St. Petersburg Corpus of Hagiographic Texts (Saint Petersburg State University) | attribution |
| `scripta-bulgarica` | Scripta Bulgarica — Old/Middle Bulgarian written monuments (BAS) | nc |
| `sl-lexica` | sl-lexica — Slovenian historical dictionary shelf (ZRC SAZU / CLARIN.SI) | attribution |
| `sl-wikisource` | Wikivir (Slovene Wikisource) — the dated cone to 1899 | attribution |
| `slavistics-pd` | PD Slavistics reference shelf — Miklosich, Berneker, Leskien, Vondrák, Jagić (archive.org scans, uncorrected OCR) | open |
| `slouniki-nasovic` | Насовіч — Словарь бѣлорусскаго нарѣчія (1870), Slouniki digitization | open |
| `sr-wikisource` | Serbian Wikisource — the oral-tradition cone (епске песме · Ерлангенски рукопис · Vuk) | attribution |
| `torot` | TOROT — Tromsø Old Russian and OCS Treebank | nc |
| `ud` | Universal Dependencies — ancient treebanks | nc |
| `uk-wikisource` | Ukrainian Wikisource — the chronicles (Літописи, edition-filtered) | attribution |
| `vuk-danicic` | The Vuk–Daničić Serbian Bible (NT 1847, OT 1865) — ijekavian text, via Rs1Bible USFM | open |
| `wiktionary-cu` | Wiktionary OCS — kaikki.org machine-readable extract | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `archiv-slav-phil` — Vatroslav Jagić's Archiv für slavische Philologie (Berlin: Weidmann), the journal of record of nineteenth-century Slavistics, as the run of scans on the Internet Archive. It covers 33 volumes (Bd. 1, 3–12 and 14–35, 1876–1914), one document per volume and one passage per page. The journal is mostly in German, with Russian, Serbo-Croatian and other Slavic contributions mixed in: scholarship about Slavic, not Slavic texts as such. The text is the scans' uncorrected OCR, declared as such, and a few volumes are scans of the 1964 facsimile reprint. Public domain in the US (published before 1931); the EU term, which runs per article, has not been audited.
- `bg-wikisource` — The premodern holdings of Bulgarian Wikisource, a deliberately small set. About nineteen medieval Bulgarian and Serbian charters are read in their original Church Slavonic text, each dated by its issuance year where the page states one; the modern Bulgarian renderings beside them are set aside. With them comes Paisiy's Istoriya slavyanobolgarskaya (1762), which the wiki hosts only as a modern literary Bulgarian rendering after Ivanov's 1914 edition, and which is declared as such. The texts are public domain; the transcriptions are CC BY-SA 4.0.
- `ccmh` — The Old Church Slavonic canon in diplomatic transcription — Marianus, Zographensis, Assemanianus and Suprasliensis from the Corpus Cyrillo-Methodianum Helsingiense.
- `cs-wikisource` — The premodern Czech works on Czech Wikisource (Wikizdroje), chosen work by work since the wiki has no period categories. The set is the rhymed Chronicle of so-called Dalimil (early 14th century) in Jireček's 1877 edition; the Kralice Bible, both in the 1613 print's own Brethren orthography for the books hosted that way and complete in the modernized spelling of the 1918 reprint; Komenský's Labyrint světa a ráj srdce (the 1663 text); and Harant z Polžic's travel account Cesta z Království Českého (1608). Each work carries the edition it was transcribed from; a hymn keyed to a 1959 hymnal is left out. Language is held coarsely as Czech, Old to Early Modern. Texts public domain; transcriptions CC BY-SA 4.0.
- `damaskini` — Early modern Bulgarian damaskini — sermon-book manuscripts in diplomatic transcription (with Church Slavonic layers) and aligned English translations.
- `elektire` — eLektire, CARNET's school reading portal (lektire.skole.hr), with books produced by Bulaja naklada: the Croatian literary canon as e-books. It runs from Marulić's Judita (1501) and the Dubrovnik and Hvar Renaissance (Držić, Vetranović, Nalješković, Hektorović, Lucić, Zoranić) through Gundulić's Osman and Dubravka, Kačić and Relković, the Illyrians, Šenoa, Kovačić, Matoš and Kamov to the moderns, along with folk prose, drama and verse in Čakavian, Štokavian and Kajkavian. About 205 works are held, read verse by verse and paragraph by paragraph, and each is dated by the portal's century of origin. The publisher's glossaries, notes and teaching pages are left out. A work is admitted only if its own imprint declares it public domain and its author died by 1955 or is anonymous; the printed edition behind each e-book is not stated, and is recorded as such.
- `eltec-srp` — ELTeC-srp, the Serbian collection of the European Literary Text Collection (COST Action "Distant Reading for European Literary History", edited by Cvetana Krstev with JeRTeH and the University of Belgrade). It holds Serbian novels in their first editions of 1852 to 1920, OCR-corrected by JeRTeH and partner libraries, almost all in Cyrillic with two in Latin script. About 96 novels are held, each dated and placed by its first edition, and many record the printed edition they were digitized from. Four novels whose authors died after 1955 are left out under the life-plus-70 term. The texts are public domain and the markup is CC BY 4.0.
- `freising` — The Freising Manuscripts — the oldest continuous Slavic texts (late 10th century), in the ZRC SAZU critical edition with diplomatic and normalized layers.
- `gams-zrcalo` — Zrcalo člověčaskago spasenja, the Croatian Glagolitic Speculum humanae salvationis that the deacon Luka wrote in 1445 for the priest Grgur of Vrbnik (Vatican, Borg. illirico 9), translated from the Old Czech Zrcadlo. It is held in the GAMS digital edition by Martina Kramarić and Gerlinde Schneider (University of Graz, 2022). The text covers the foreword and chapters 1–42, with the manuscript's lacunae, in a semi-diplomatic Latin-script transliteration of the Glagolitic. The scribe's own readings are kept, and the editors' corrections and notes travel beside them. The language is mostly Old Croatian with Church Slavonic elements and traces of Old Czech. CC BY 4.0.
- `goo300k` — Gold-annotated Early Modern Slovenian — the goo300k reference corpus with hand-verified lemmas and morphology.
- `hr-wikisource` — The premodern Croatian literature of Croatian Wikisource, from the Middle Ages through the 18th century. It includes Marulić's Judita, Marin Držić's plays, Vetranović, Bunić Vučić, Zoranić's Planine and the Siget epics, Gundulić's Osman, Đurđević and Frankopan, and Kačić's Razgovor ugodni, about 1,390 texts in all. Each text is dated only by the century the wiki files it under, as a coarse era band. The transcriptions follow their editions' normalized Latin script; translations and 19th-century and later literature are left out. Texts public domain; transcriptions CC BY-SA 4.0.
- `imp` — The IMP corpus of historical Slovenian — 658 books and periodicals (1584-1918) with automatic annotation.
- `kdsp` — KDSP 1.0, the Corpus of Longer Narrative Slovenian Prose (Korpus daljše slovenske proze) by Mandić and Erjavec at ZRC SAZU (CLARIN.SI). It holds 262 tales, novels and novellas of at least 20,000 words published between 1836 and 1918. Each work is classed by period, length, text type, theme and canonicity, and the corpus's own author records (birth, death, occupation) are attached. KDSP draws its texts from Wikivir, ELTeC and dLib and names the digital source of each, so some works also appear on other Slovene shelves in a different rendering. Every work is dated by its year of publication. CC BY 4.0.
- `korba` — The manually annotated subcorpus of KorBa, the Electronic Corpus of 17th- and 18th-century Polish Texts (to 1772), from the Institute of the Polish Language, Polish Academy of Sciences (W. Gruszczyński et al.), in its edition 2.0. It holds samples of every text in the Baroque corpus, drawn from prints, manuscripts and later editions — 2,091 texts and some 850,000 tokens, gathered over the project's two stages (2013–2018 and 2018–2023). Each sample is transcribed in its original spelling, and every word carries a hand-checked modernized spelling, lemma and grammatical tag, resolved by an adjudicator between two independent annotation passes (or, for a marked minority, a single annotator). Texts are dated (1601–1800), placed and regionally classed from the corpus's own headers, with genre and prose-or-verse recorded, and any modernized edition a text was keyed from is noted. CC BY-SA 4.0.
- `litopys` — The public-domain editions on Izbornyk (litopys.org.ua), the volunteer-keyed library of East Slavic sources. The centrepiece is the complete Ipatiev chronicle as printed in the Complete Collection of Russian Chronicles, vol. 2 (St Petersburg, 1908, ed. A. A. Shakhmatov): the Povest' vremennykh let, the Kievan svod and the Galician-Volhynian svod, cited column by column with the 1908 variant readings and notes, the codex's folio breaks and the annal years. Three early glossaries, after 19th-century publications, are also held: the Leksis of Amfilokhii's 1884 publication, the 1282 onomasticon of "Hebrew words" and a glossary of 1431. Texts the site keyed from Soviet-era editions are left out. Both the medieval texts and the editions used are public domain.
- `mdz-protestant` — Six 16th-century Slovene and Croatian Protestant prints from the Bavarian State Library, as page OCR from the Münchener DigitalisierungsZentrum. They are Trubar's Articuli oli Deili (Tübingen 1562), Dalmatin's Jesus Sirah (Ljubljana 1575), the 1584 Wittenberg catechism with hymns and the prayer book Karszhanske lepe molitve, Bohorič's Arcticae horulae (Wittenberg 1584, the first Slovene grammar) and the Latin-script Croatian Spovid ispoznanie of the Urach press (Tübingen 1564), about 1,550 pages in all. The text is MDZ's uncorrected machine OCR of 16th-century type, read page by page; it is not an edition, and is declared as such. Each print is dated and placed from its imprint. Public Domain Mark, except two Google-digitized copies (Sirah, Spovid) held for non-commercial use only.
- `mk-wikisource` — The 19th-century Macedonian holdings of Macedonian Wikisource, chosen by named collection and author. They are the Miladinov brothers' 1861 folk-song collection, Šapkarev's collection, Marko Cepenkov's folk tales, and the works of the early writers Kiril Pejčinović, Joakim Krčovski, Ǵorǵija Pulevski, the Miladinovs and Rajko Žinzifov, about 840 texts in all. Most of the collection is hosted in modernized Macedonian orthography; each page records which orthography it uses (Pulevski's is the original), and pages that state a print year are dated by it. Partisan and reworked songs, Prličev (who wrote in Greek) and modern-spelling duplicates are left out. Texts public domain; transcriptions CC BY-SA 4.0.
- `pl-wikisource` — The premodern Polish literature of Polish Wikisource, about 1,230 texts drawn from the Polish-literature categories of the wiki's period tree and its two Old Polish sermon collections. Most are transcriptions of 19th- and early 20th-century scholarly editions such as the Biblioteka Pisarzów Polskich and the Academy of Learning's series, and each text names the edition it follows. Texts are dated only by their literary period, Old to Middle Polish. Editors' introductions, glossaries and notes are left out, as is one 1932 edition. Alongside the texts sits Aleksander Brückner's Słownik etymologiczny języka polskiego (Kraków 1927), about 5,700 entries from its proofread scan. Texts public domain; transcriptions CC BY-SA 4.0.
- `prague-bible-1488` — A ground-truth transcription of selected pages of the Prague Bible (Bible pražská, printed 1488; Vienna, ÖNB Ink 13.C.5), the first complete printed Czech Bible. It was made by the Medieval Czech group of the Vienna HTR Winter School 2024 and corrected by Anna Michalcová (Zenodo, 2024). Eight segments are covered (from Genesis, Joshua, Judith, Psalms, Ezekiel, Luke, Hebrews and Revelation), 31 pages and about 2,940 lines of Old Czech in bastarda type. They are transcribed semi-diplomatically, with long s, line-break hyphens and abbreviation marks kept and the expansions noted beside them. Each page is one document read line by line and carries its segment, the edition's year 1488 and Prague as the imprint place. CC BY 4.0 on the record, CC BY-SA 4.0 in the deposited citation file; the share-alike reading is honoured.
- `prilit` — PriLit, the corpus of older Slovenian narrative prose by Žejn and Erjavec (ZRC SAZU and the Jožef Stefan Institute; CLARIN.SI): 43 texts of 37 works by 12 authors, from 1643 to 1866, the earliest Slovenian narrative prose. Cigler's Sreča v nesreči is present in several editions, held as separate documents for collation. Every text is dated by its print year and read block by block in the plain TEI edition. The corpus's automatic linguistic annotation is not included. CC BY 4.0.
- `proiel` — Gold dependency treebanks of the earliest Indo-European Bible translations — Greek NT, Vulgate, Gothic, Classical Armenian and Old Church Slavonic, morphologically analyzed to the token.
- `ru-wikisource` — The Old East Slavic texts of Russian Wikisource, filtered edition by edition: a page is held only if the edition it was keyed from is itself public domain. What remains is a small set of about a dozen texts. They include the Igor Tale (Slovo) in its 1800 edition, Kostomarov's 1862 Pamyatniki, Bychkov's 1897 text, the 1893 text of Vladimir Monomakh, Kozhanchikov's prints of 1861 and 1862, and web-sourced pages that name no edition, such as Nikitin's journey, the tale of Savva Grudtsyn and Avvakum's Life. Pages keyed to Soviet and later editions, translations and duplicates are left out. Texts are dated by the composition era the page states. Texts public domain; transcriptions CC BY-SA 4.0.
- `scripta-bulgarica` — Scripta Bulgarica, the portal of Old and Middle Bulgarian written monuments from the Institute for Literature of the Bulgarian Academy of Sciences (principal investigator Anisava Miltenova). It holds about 125 source texts from the 11th to the 18th century, among them inscriptions such as the Bitola inscription, the Tărnovo charters, chronicles, damaskini, and homiletic and hagiographic texts. They are given in Unicode Cyrillic with the combining diacritics and titla kept. Each text names the printed edition it was keyed from, and that citation travels with it. Language is held coarsely as Bulgarian across the whole span. CC BY-NC-SA 2.0 per the site's terms.
- `sl-lexica` — The Slovenian historical dictionary shelf: Pleteršnik's Slovene-German dictionary, the vocabulary of Janez Svetokriški, and the 16th-century literary wordstock — 139,405 entries.
- `sl-wikisource` — Wikivir, the Slovene Wikisource, through its year categories up to 1899: about 1,540 dated works, from the 1584 Dalmatin and Trubar hymnal pages through the press peak of 1848–51 to the end of the century. Most of the 19th-century layer is the Hladnik project's human-corrected transcription of prints scanned in dLib, and each text names the print it follows. Every work is dated by its year, and texts in the old bohoričica orthography or in the Prekmurje variety are marked as such, never normalized. Translations and works in other languages are left out. Some works also appear on the other Slovene shelves in different editions, and are held separately. Texts public domain; transcriptions CC BY-SA 4.0.
- `slavistics-pd` — The public-domain reference canon of German-language Slavistics, as Internet Archive scans. It holds Miklosich's Etymologisches Wörterbuch der slavischen Sprachen (1886) and Vergleichende Grammatik (I–IV), Berneker's Slavisches etymologisches Wörterbuch I, Leskien's Handbuch der altbulgarischen Sprache (1905), Vondrák's Altkirchenslavische Grammatik (1900) and Frisinské památky (1896), the Glagolita Clozianus in Kopitar's (1836) and Vondrák's (1893) editions, and a dozen Slavistics monographs from the Vienna Academy, 1858–1913. There are 23 volumes, one passage per scanned page. This is scholarship about Slavic, in German, Latin or Czech prose. The text is the archive's uncorrected OCR, declared as such with a measured quality figure per volume; the prose reads, but Cyrillic and Glagolitic forms are garbled. All authors died by 1952 and every print predates 1931: public domain.
- `slouniki-nasovic` — Ivan Nasovič's Slovar' belorusskago narěčija (St Petersburg: Imperial Academy of Sciences, 1870), the founding dictionary of Belarusian, as keyed by the Belarusian dictionary-digitization volunteers (Slouniki). It holds about 35,000 entries of the 19th-century vernacular, glossed in Russian with proverbs and folk-speech examples. Each entry keeps the 1870 headword verbatim with its stress marks, and the volunteers' modern spelling and equivalents are labelled as their own layer. Cross-reference entries carry no gloss. It is the library's first Belarusian shelf. Public domain, as the volunteers declare and as the 1870 text is by age.
- `sr-wikisource` — The oral-tradition holdings of Serbian Wikisource. They hold the Serbian epic folk songs with their cycles (Marko Kraljević, Starina Novak, Bajo Pivljanin); the c. 1720 Erlangen manuscript in the Detelić, Samardžija and Delić rendering after Gesemann (1925), whose editorial normalizations are recorded; and Vuk Karadžić's collections, among them the Vienna and State editions, the Academy manuscript volumes and the women's songs from Herzegovina. About 4,600 texts are held, verse by verse, each naming the edition it was taken from. Cyrillic pages are claimed as Serbian and the Croatian-collected Latin-script pages as Croatian. Bulgarian-source collections and partisan songs are left out. The songs are undated; recording is not composition. Texts public domain; transcriptions CC BY-SA 4.0.
- `torot` — The Tromsø Old Russian and OCS Treebank — gold dependency annotation over chronicles, birchbark letters and the OCS canon, the living successor to PROIEL's Slavic side.
- `ud` — Dependency treebanks from the Universal Dependencies project: Classical Armenian, Coptic, Gothic, Old Church Slavonic, Old East Slavic, Old French, Latin, Ancient Greek and the Old Irish gloss pair — morphology and lemmas that feed the corpus's attested counts. The released treebanks are gold-standard; the St Gall glosses also carry their maintainer's unreleased, not-yet-proofed layer, marked as a draft on every document.
- `uk-wikisource` — The chronicles of Ukrainian Wikisource, filtered by the edition each page follows. Seven texts are held: the 17th- and 18th-century Cossack-era chronicles in their pre-1930 editions, namely four from the Sbornik letopisei (Kyiv 1888), two of the Chronicle of Samovydets (Kyiv 1878) and one from Kievskaya starina (1890). The Lviv chronicle and Ostroh chronicler, which the wiki keys to a 1971 edition, are left out, as are modern Ukrainian retellings. Language is held coarsely as Old East Slavic, the Ruthenian chronicle register, and each chronicle is dated by its terminal year. Texts public domain; transcriptions CC BY-SA 4.0.
- `vuk-danicic` — The Serbian Bible of Vuk Stefanović Karadžić (New Testament, Vienna 1847) and Đura Daničić (Old Testament, completed 1865 and printed in the 1868 Bible): the founding text of Vuk's Neo-Štokavian ijekavian standard, in the translators' own language ("U početku bješe riječ"). All 66 books are held, about 31,100 verses cited by chapter and verse, in Latin transliteration of the Cyrillic original. The text comes from a USFM conversion of the Unbound Bible's text; its book titles are the converter's English names. A widely circulated modernized, ekavian edition was deliberately not used. Each testament is dated by its translation era. Public domain by age.
- `wiktionary-cu` — Wiktionary's Old Church Slavonic extract — attested OCS headwords with etymologies chaining into the Proto-Slavic reconstruction shelf.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Show me MARK 2.3 in every witness — Greek against all four OCS codices.* — `nabu_align "MARK 2.3" (work: nt)`: Fourteen witness columns in one reply: PROIEL Greek, Vulgate, Gothic, Armenian, Codex Marianus beside the CCMH Assemanianus / Marianus / Savvina / Zographensis diplomatic transcriptions, the West-Saxon Gospels, Sahidic Coptic, SBLGNT, WEB. `collate: true` turns the columns into a witness apparatus.

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
