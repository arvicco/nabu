---
title: The Library
permalink: /library/
description: >-
  The collections of the Nabu library: classical Greek and Latin, papyri,
  Sanskrit and the Indic canons, cuneiform, Arabic and Persian, the Chinese
  and Tibetan canons, Korean, Japanese, Southeast Asian epigraphy,
  Egyptian, Hebrew, Ethiopic, the Middle Iranian and Turkic east, Romance,
  Germanic, English, Slavic, Celtic, and the colonial Americas — with the
  reference shelf of dictionaries.
---

{% assign census = site.data.census -%}
Live counts as of **{{ census.as_of }}**: **{{ census.documents_display }} documents /
{{ census.passages_display }} passages** across {{ census.live_sources }} registered, synced
sources (the full registry counts {{ census.registry_rows }} rows: {{ census.corpus_sources }}
corpus sources, {{ census.local_shelves }} local shelves, and {{ census.feature_modules }}
feature modules), plus **{{ census.dictionary_entries_display }} dictionary entries** on the
reference shelf and **{{ census.gold_lemmas_m }} million gold lemma annotations in
{{ census.gold_languages }} languages** (a further {{ census.silver_lemmas_display }} lemma
rows in {{ census.silver_languages }} languages ride an honestly labelled silver tier —
machine-suggested or upstream-undisambiguated, excluded from gold-only search).
{%- assign t0 = census.top_languages[0] %}
{%- assign t1 = census.top_languages[1] %}
{%- assign t2 = census.top_languages[2] %}
{%- assign t3 = census.top_languages[3] %}
{%- assign t4 = census.top_languages[4] %}
{%- assign t5 = census.top_languages[5] %}
{%- assign n0 = site.data.language_notes[t0.code] | split: " — " | first %}
{%- assign n1 = site.data.language_notes[t1.code] | split: " — " | first %}
{%- assign n2 = site.data.language_notes[t2.code] | split: " — " | first %}
{%- assign n3 = site.data.language_notes[t3.code] | split: " — " | first %}
{%- assign n4 = site.data.language_notes[t4.code] | split: " — " | first %}
{%- assign n5 = site.data.language_notes[t5.code] | split: " — " | first %}
{{ n0 }} is the largest language in the catalog at {{ t0.millions }} million
passages, ahead of {{ n1 }} ({{ t1.millions }} million) and {{ n2 }}
({{ t2.millions }} million), with {{ n3 }}, {{ n4 }} and {{ n5 }} next;
{{ census.language_codes }}
language codes appear in all, and since August 2026 stored codes also resolve through the lect
layer — historical-stage ladders on the language cards and stage-scoped
search, described on the [Languages]({{ '/languages/' | relative_url }})
page. The authoritative shelf map, refreshed at every
development gate, is
[docs/library.md](https://github.com/arvicco/nabu/blob/main/docs/library.md)
in the repository. The collection sizes in the table below were read from
the live catalog on 11 October 2026, not estimated; the per-shelf figures
in the sections after it are dated where they appear.

The same shelves, grouped by the owner's research desks rather than by
collection — each with its instruments, CLI recipes and terminal setup — are
the [research axes]({{ '/axis/' | relative_url }}).

| Collection | Contents | Period | Size | License class |
|---|---|---|---|---|
| Classical Greek | Perseus: Homer, the tragedians, Herodotus, Plato, Galen, with 650 aligned English translations | 8th c. BCE – 3rd c. CE | 1,418 docs / 394,705 passages | CC BY-SA |
| Post-classical Greek | First1KGreek: Athenaeus, Philo, church fathers, Swete's Septuagint | 3rd c. BCE – 6th c. CE | 1,129 / 256,480 | CC BY-SA |
| Greek silver layer | Diorisis and GLAUx: machine-lemmatized second editions of the Greek canon, honestly labelled | Homer – early Byzantium | 2,188 / 1,485,083 | CC BY-SA / mixed per document |
| Classical Latin | Perseus: Vergil, Ovid, Cicero, Livy, Tacitus, with 181 English translations | 3rd c. BCE – Late Antiquity | 554 / 401,207 | CC BY-SA |
| Latin–Romance continuum | digilibLT late-antique Latin, openMGH, CroALa, Corpus Córporum's Patrologia; BFM Old French, the Galician-Portuguese cantigas, Old Spanish, Portuguese, Catalan, Occitan, Sardinian and Judeo-Spanish shelves | 2nd c. CE – early modern | 11,309 / 3,271,768 | CC BY / CC BY-SA / NC / written grant |
| Documentary papyri | Papyri.info DDbDP: contracts, letters, tax receipts (Greek, Coptic, Latin, Arabic, Demotic) | c. 300 BCE – 8th c. CE | 63,659 / 1,105,279 | CC BY |
| Latin inscriptions | Epigraphic Database Heidelberg: epitaphs, dedications, milestones from the whole empire, with genre facets | Republic – Late Antiquity | 81,881 / 406,306 | CC BY-SA |
| Inscriptions of Italy | Epigraphic Database Roma: the peninsula itself, the geographic complement of Heidelberg's provinces — dated and faceted end to end | Republic – Late Antiquity | 115,590 / 596,064 | CC BY |
| Celtic | CorPH Early Irish (gold-lemmatized), the RIIG Gaulish inscriptions, the Ogham in 3D stones | c. 2nd c. BCE – 10th c. CE | 1,444 / 20,352 | CC BY / MIT (ogham held `nc` pending clarification) |
| Coptic | Coptic Scriptorium: the complete Sahidic and Bohairic New Testaments, monastic and patristic prose, gold-lemmatized | c. 3rd – 10th c. CE | 482 / 74,169 | CC BY per document (source class `nc`) |
| Sanskrit | GRETIL: Rāmāyaṇa, purāṇas, kāvya, śāstra, the Ṛgveda with Vedic accents | c. 1200 BCE – 18th c. CE | 780 / 703,068 | CC BY-NC-SA |
| Indic expansion | SARIT, SuttaCentral (the segmented Pali canon with aligned English and its variant apparatus), the gold-lemmatized DCS, Classical Newar (DACON) | Veda – early modern | 28,171 / 1,797,358 | CC BY / CC BY-SA / NC per source |
| Treebanks | PROIEL, TOROT, UD, ISWOC: gold lemma, morphology, and syntax | 5th c. BCE – 18th c. CE | 136 / 413,135 | mostly CC BY-NC-SA |
| Cuneiform | ORACC, over a hundred projects: the complete State Archives of Assyria, the Achaemenid trilinguals, the ePSD2 corpora, the CC0 project pack, with aligned English translations | late 4th mill. – 4th c. BCE | 118,367 / 1,800,218 | CC0 |
| Ancient Near East | TLHdig Hittite and the glossed Hittite texts, the Luwian corpus, the CDLI catalog, eBL Fragmentarium, Achemenet Babylonian, SEAL, Ugaritic (CUC), Peshitta and the Syriac corpus, ETCSL Sumerian literature | late 4th mill. BCE – 13th c. CE | 412,228 / 3,223,988 | CC BY / CC0 / NC / personal grants per source |
| Ugarit (Ras Shamra) | The RSTI tablet inventory: RS↔KTU concordances, findspots, published editions at line grain | Late Bronze Age | 5,075 / 740 | CC BY-NC-SA (written grant) |
| Hebrew &amp; Aramaic | OSHB and BHSA Masoretic text, the Dead Sea Scrolls, the Sefaria Targums, the inscriptions of Israel/Palestine | c. 1000 BCE – 10th c. CE | 7,499 / 591,787 | CC BY / NC per source |
| Elephantine | The island's multilingual documentary record: Aramaic, Greek, Demotic, Egyptian, Coptic, with English translation siblings | 3rd mill. BCE – Islamic Egypt | 15,539 / 69,350 | CC BY-SA |
| Arabic &amp; Persian | OpenITI: Quran and hadith, history and biography, fiqh, kalām and falsafa, the dīwāns and adab; the Persian classics; the DiCCAS disaster corpus | 7th c. – early modern | 9,089 / 34,632,378 | CC BY-NC-SA |
| Iranian &amp; the Silk Road | The Invisible East documents, Skjærvø's Khotanese manuscripts, the trilingual Kaʿba-ye Zartošt inscription, Hafez in Perseus | 3rd – 14th c. CE | 3,678 / 37,857 | CC BY / CC BY-SA |
| Turkic &amp; Mongolic | ATMO's Eastern Turki manuscripts, Street's *Secret History of the Mongols* | 13th – 20th c. | 16 / 8,457 | CC BY-SA / use grant |
| Egyptian | The TLA sentence corpora (AES + Late Egyptian/Demotic), gold-lemmatized | late 4th mill. – 1st c. BCE | 26,017 / 261,950 | CC BY-SA |
| Ethiopic (Gǝʿǝz) | Beta maṣāḥǝft works incl. the Gǝʿǝz Bible; the TraCES gold-analyzed corpus with the Aksumite royal inscriptions | Aksumite – the manuscript tradition | 3,825 / 142,352 | CC BY-SA / NC |
| Pre-Roman Italy &amp; Sicily | CEIPoM, ItAnt, the Etruscan editions, TIR, Lexicon Leponticum, I.Sicily | 7th c. BCE – Roman | 20,684 / 33,558 | CC BY per source |
| Biblical editions | Clementine Vulgate (73 books), SBL Greek New Testament, World English Bible | — | 184 / 81,372 | PD / CC BY |
| Old English poetry | The complete Anglo-Saxon Poetic Records: Beowulf, the Exeter Book, Dream of the Rood | c. 700–1150 | 351 / 30,636 | CC BY-SA |
| Middle and Early Modern English | The Corpus of Middle English Prose and Verse; EEBO-TCP, the first printed books in English | c. 1100 – 1700 | 60,622 / 26,421,200 | PD / CC0 |
| Slavic | CCMH OCS gospel codices, the Freising Manuscripts, Early Modern Slovenian, the damaskini, Scripta Bulgarica, nine Wikisource cones, the Ipatiev chronicle, the 1488 Prague Bible, Protestant prints, the Croatian school canon, the Serbian novel and Bible, the German Slavistics canon | c. 1000 – early 20th c. | 11,743 / 2,261,982 | CC BY / CC BY-SA / PD / NC (Freising BY-ND) |
| Chinese libraries | Kanripo (KR1 classics – KR5 Daoist canon), the CBETA Buddhist canon (Taishō + Xuzangjing), Chinese Wikisource's censused works, the Classical↔Modern parallel corpus, the Đại Việt classical shelf | Zhou – Qing | 24,717 / 15,497,485 | CC BY-SA / CC BY-NC-SA / MIT |
| Korean | The Joseon Veritable Records and the Royal Secretariat diaries, the Goryeo histories, the Border Defense Command register, the ITKC classical originals, the Open Korean Historical Corpus, the *Yongbi eocheon ga* | Goryeo – late Joseon | 1,210,839 / 6,027,145 | KOGL open / CC BY-NC |
| Tibetan | The Derge Kangyur and Tengyur complete, the 84000 English translations, the Old Tibetan documents (OTDO), the SOAS gold-POS corpus | 8th c. – the 18th-c. Derge woodblocks | 5,368 / 1,497,590 | PD / CC BY / CC BY-NC-ND (84000) |
| Japanese | Aozora Bunko, the National Diet Library's classical OCR stacks, Minna de Honkoku, Japanese Wikisource, the NIJL and Genji TEI editions, ONCOJ's gold-morphology Old Japanese | 7th c. – 20th c. CE | 55,959 / 4,094,528 | open / CC BY / CC BY-SA |
| Southeast Asia | The DHARMA epigraphy of Old Khmer, Cham, Pyu and the Nusantara charters, the Old Javanese kakawin library, the Old Burmese inscriptions of Bagan | c. 5th – 15th c. CE | 2,989 / 131,135 | CC BY / CC BY-SA |
| Germanic | Menotec and Menota Old Norse, Old Swedish, the Old Saxon *Heliand*, ReM, ReN and ReF (Middle High, Middle Low and Early New High German), the Deutsches Textarchiv, Old and Middle Dutch, the Rundata runic corpus | c. 200 – 1969 CE | 39,525 / 2,497,571 | nc / CC BY / CC BY-SA / ODbL / `research_private` |
| The Americas | Ticha's colonial Valley Zapotec, Guaman Poma's *Nueva corónica* | 16th – 18th c. CE | 1,282 / 7,014 | PD / CC BY-SA |
| Reference shelf | LSJ, Lewis &amp; Short, Bosworth-Toller, Monier-Williams, Wiktionary lexica and reconstruction dictionaries, the IE-CoR, LIV, and de Vaan etymological witnesses, the StarLing / Tower of Babel databases, three Slovenian historical dictionaries, Brückner and Nasovič, the Welsh GPC, the Hebrew and Egyptian lexica, the Sino-Japanese desk (Unihan, KANJIDIC2/JMdict, HDIC, the Chinese rime books), the Tibetan rack (Mahāvyutpatti, the Verbs Database, the Monlam headwords), Dillmann's Gǝʿǝz lexicon, DÉRom, CLICS and WOLD | — | {{ census.dictionary_entries_display }} entries | CC BY-SA / CC BY / CC BY-NC-SA / written grant |

## Classical Greek literature

The backbone of the Greek canon, from the Perseus Digital Library's
canonical-greekLit collection: Homer, Hesiod, the tragedians, Aristophanes,
Herodotus, Thucydides, Plato, Aristotle, the orators, Plutarch, Galen, and
more — 768 Greek editions spanning the Archaic period to roughly the third
century CE, of which 650 carry an aligned English translation displayable
side by side. Citations follow the canonical schemes (book and line,
Stephanus pages) under stable CTS URNs, so a range such as *Iliad* 1.1–1.32
resolves natively.

## Post-classical Greek

The First Thousand Years of Greek project (Open Greek &amp; Latin) supplies
the long tail Perseus does not cover: Athenaeus, Philo, the church fathers,
grammarians, scholia, minor historians, and medical and mathematical
writers — 1,088 Greek editions, mostly Hellenistic through Late Antique.
English coverage is thin (41 editions) but present. Swete's edition of the
Septuagint lives on this shelf and serves as the Greek witness of the Old
Testament alignment axis.

## The Greek silver layer

Two machine-annotated editions of the Greek canon sit deliberately
unmerged beside the Perseus and First1K copies of the same works, and
every count they contribute is labelled *silver* — machine-produced
analysis, never presented as gold attestation, and excluded from
gold-only search. The Diorisis Ancient Greek Corpus (Vatri &amp;
McGillivray, CC BY-SA) supplies 764 documents / 502,865 passages —
roughly 10.2 million words tokenized, lemmatized, and morphologically
analyzed, Homer to early Byzantium. GLAUx ("the Greek Language
Automated", Keersmaekers, Leuven; joined 25 July 2026) adds 1,421
documents / 968,578 passages — about 20 million tokens automatically
annotated for morphology, syntax, lemmas, animacy, and word senses.
Together they make lemma search possible across the whole Greek canon
where the gold treebanks cover only samples.

## Classical Latin literature

Vergil, Ovid, Horace, Cicero, Caesar, Livy, Tacitus, and Seneca, from
Perseus canonical-latinLit — 353 Latin editions with 181 aligned English
translations. Orthographic variation (u/v, i/j) is folded at the search
layer, so *iuvenis*, *juvenis*, and *iuuenis* all resolve to the same word.

## The Latin–Romance continuum

Since late July 2026 the Latin shelf continues past antiquity as one
readable band. digilibLT (Biblioteca digitale di testi latini
tardoantichi, Vercelli, CC BY-SA) covers late-antique *secular* Latin
prose of the second through seventh centuries — Ammianus, the
grammarians, the agrimensores, the jurists — in 372 documents / 459,451
passages. openMGH (the digital Monumenta Germaniae Historica, CC BY)
brings the medieval-Latin backbone: the SS rer. Germ. series — Einhard,
Widukind, Liudprand, Regino, Adam of Bremen, Otto of Freising — and the
critical editions published upstream since, 153 volumes as of October
2026. CroALa
(Croatiae auctores Latini, CC BY) adds 570 documents / 309,180 passages
of Croatian Latinity across a near-millennium, 454 of them dated
(999–1984). On the vernacular side, the Base de français médiéval (ENS
de Lyon) holds 219 complete medieval French texts / 333,819 passages —
roughly 6.45 million words from the Serments de Strasbourg of 842
through the end of the fifteenth century, every text dated. And the
Cantigas Medievais Galego-Portuguesas (Projeto Littera, held under a
written grant from the project's coordinator; joined 31 July 2026)
supply the complete secular Galician-Portuguese lyric corpus — 1,676
cantigas de amigo, de amor, and de escárnio e maldizer / 34,058 verse
passages, with author, genre, manuscript sigla, and rubrics carried as
metadata. On the reference shelf, DÉRom — the Dictionnaire Étymologique
Roman — reconstructs the Proto-Romance side of the same band (see
below).

The August 2026 waves filled out both ends of the band. Corpus Córporum
(University of Zurich, non-commercial) brings Migne's Patrologia Latina
and the wider Latin library — 5,248 texts / 896,770 passages — and the
vernacular side gained the Old Spanish Textual Archive, DISCO's
diachronic Spanish sonnets, BDCamões's Portuguese literary works, the
public-domain works of the Catalan CTILC, and smaller shelves of
Occitan (six dialects, French-aligned), Aranese, Sardinian, and
Judeo-Spanish — the last three modern, held for the continuum's living
end and labelled honestly where an upstream says its text is
synthetic.

## Documentary papyri

The everyday written record of a millennium of Egypt, from the Duke Databank
of Documentary Papyri via papyri.info: contracts, tax receipts, petitions,
private letters, census returns, leases, and court records — 63,659
documents (October 2026) from Ptolemaic to early Islamic Egypt, chiefly Greek with Coptic,
Latin, Arabic, and Demotic minorities. Leiden-convention editorial markup
(restorations, cancellations) is preserved, and the fragment-search index
(see [Tools]({{ '/tools/' | relative_url }})) is built over this shelf.

## Latin inscriptions

The Epigraphic Database Heidelberg, ingested on 13 July 2026 as a
preservation snapshot (the upstream project was archived in 2021): 81,881
inscriptions — epitaphs, dedications, honorific and building inscriptions,
milestones — in Latin (80,561), Greek (1,290, the bilinguals), from
provinces across the whole empire. 81,416 documents carry dates on the
chronological axis, and the shelf brings the library's first genre facets:
searches can be filtered by inscription genre, province, material, and
object type, composing with the date and place filters. Leiden-convention
rendering and the fragment-search index apply here as on the papyri.

Since 26 July 2026 the Epigraphic Database Roma (Sapienza) completes the
record geographically: 115,590 inscriptions of Italy itself — the
peninsula Heidelberg's provinces surround — in 596,064 passages, every
document dated and faceted (genre, material, object type, and a
fifteen-value region axis), released under CC BY 4.0.

## Coptic

The Coptic Scriptorium corpora, synchronized on 13 July 2026 with 482 of
the 483 upstream corpora aboard: the complete Sahidic
and Bohairic New Testaments, monastic and patristic prose, and
hagiography — 74,169 passages with upstream gold lemmatization, making
Coptic the library's fifteenth lemma-searchable language (233,020 lemma
rows). The two New Testament dialects join the alignment hub as witnesses
fourteen and fifteen, and the corpus's language-of-origin annotations make
the Greek loan stratum of Coptic queryable.

## Celtic

The Celtic language axis, synchronized on 17 July 2026, in
three sources. CorPH — the Corpus PalaeoHibernicum of the ERC ChronHib
project at Maynooth — supplies 76 Early Irish documents of the seventh
through tenth centuries (the Annals of Ulster, Adomnán's Vita Columbae,
the poems of Blathmac, and the Milan, St Gall, and Würzburg gloss
corpora, with law, poetry, and computus), carrying 136,559
gold-lemmatized tokens: the library's first Old Irish lemma layer, with
per-token language honesty for the Latin the glosses interleave. The
RIIG corpus (Recueil informatisé des inscriptions gauloises, Ausonius /
Bordeaux, CC BY 4.0) brings 428 Gaulish inscriptions in Gallo-Greek and
Gallo-Latin scripts, each with its editorial readings, dated findspot on
the chronological axis, and French translation as an aligned sibling.
The Ogham in 3D corpus (DIAS / Maynooth) adds some 500 ogham stones in
real Ogham codepoints, each with aligned transliteration and
romanization layers; its two published license statements conflict, so
the shelf is held at the restrictive non-commercial reading pending
clarification. Old and Middle Irish and Middle Welsh dictionary extracts
on the reference shelf, and the two Old Irish treebanks under Universal
Dependencies, complete the axis.

## Sanskrit

The GRETIL corpus (Göttingen Register of Electronic Texts in Indian
Languages): 780 editions and 703,068 passages spanning the Vedic saṃhitās,
the Rāmāyaṇa, the purāṇas, kāvya, dharmaśāstra, philosophy, and the
technical traditions — the longest chronological span of any shelf. Vedic
accents are preserved; commentary layers are separately citable (kārikā
against vṛtti). This shelf is licensed for non-commercial research use
(CC BY-NC-SA) and is handled accordingly.

## The Indic expansion

Three shelves, synchronized 18 July 2026, widen the Indic axis beyond
GRETIL. The Digital Corpus of Sanskrit (Hellwig, CC BY) contributes
15,741 documents / 753,093 passages — 270 texts, about 5.46 million
words with human-verified sandhi splitting, lemmatization, and
morphology: the first gold-annotated Sanskrit in the lemma index. SARIT
adds 78 scholarly TEI editions / 345,601 passages of works GRETIL
lacks, including a complete Mahābhārata in the Southern Recension.
SuttaCentral supplies the whole Tipiṭaka — 12,022 documents / 654,974
passages of roman-script Pali (the Mahāsaṅgīti edition, overwhelmingly
CC0) with translator-picked English siblings riding the same segment
identifiers, so a sutta reads with facing translation. Together with
GRETIL these put the Sanskrit shelf past 1.8 million passages in three
independent witnesses of the tradition — a breadth corpus, a
gold-annotation corpus, and critical editions — with the canon of a
second Indic language beside them. Since October 2026 every root passage
of the Tipiṭaka also carries what SuttaCentral's sidecar trees attest:
variant readings with their witness sigla, the concordances to the PTS
and other print editions, and the translators' notes. DACON (Zenodo,
CC BY) adds Classical Newar manuscripts, morphosyntactically annotated.

## Morphosyntactic treebanks

Gold-standard linguistically annotated corpora — lemma, morphology, and
dependency syntax per token — from four families: PROIEL (the parallel New
Testament in Greek, Latin, Gothic, Classical Armenian, and Old Church
Slavonic, with classical prose), TOROT (Old East Slavic and OCS, from
birchbark letters to Avvakum), ISWOC (Old English prose and the West-Saxon
Gospels), and the ancient-language treebanks of Universal Dependencies —
Thomas Aquinas, Vedic Sanskrit, Ruthenian, the two Old Irish glosses
treebanks, Hittite (HitTB), Classical Chinese (Kyoto), Old Icelandic
(IcePaHC), Old Turkic, the Jesuit-era Tupinambá and Old Guaraní, and the
two Perseus conversions for Ancient Greek and Latin.
Together with the gold layers of ORACC, DCS, AES, Coptic Scriptorium,
CorPH, ReM, ReN, IcePaHC, goo300k, damaskini, TraCES, and ETCSL these
feed a gold lemma index of **{{ census.gold_lemmas_m }} million rows in
{{ census.gold_languages }} languages** (as of {{ census.as_of }}).

## Cuneiform and the Ancient Near East

The Open Richly Annotated Cuneiform Corpus (ORACC), over a hundred
projects: 118,367 documents and 1,800,218 passages (October 2026),
including the **complete State Archives of Assyria**, the Achaemenid
royal trilinguals (Old Persian and Elamite enter the library here), the
four ePSD2 corpora with the Ur III administrative mass, and the Oracc
CC0 project pack (Urartian among it) — with upstream gold lemmatization for Akkadian and
Sumerian, so a tablet displays transliteration beside running English,
line by line. Released by ORACC under CC0.

Around it, since 19 July 2026, the rest of the cuneiform world: the
**CDLI universal catalog** (353,156 artifacts under CDLI's open grant,
135,201 of them transliterated — proto-cuneiform and proto-Elamite's
only machine-readable home, with periods, proveniences, and collections
as browsable axes from Uruk IV to the Achaemenids); the **TLHdig Hittite
corpus** (23,486 tablet manuscripts, >98% of published Hittite
fragments, CC BY, with candidate morphology carried at an honest silver
tier); the **eBL Fragmentarium** (23,288 fragments with inline English,
cross-linked to their CDLI records); the **Electronic Text Corpus of
Sumerian Literature** (394 hand-lemmatized composites with English prose
siblings, deliberately unmerged from ePSD2's editions of the same
poems); and the **Copenhagen Ugaritic Corpus** (279 KTU tablets with
per-sign cuneiform and damage flags).

Later waves widened both ends. Achemenet's annotated Babylonian texts of
the Achaemenid period (Helsinki, CC BY) and SEAL — the Sources of Early
Akkadian Literature, held under its editors' scholarly-use grant — sit
on the Akkadian side. Anatolia gained a glossed Hittite corpus with
German translations (Zenodo, CC BY, 7,099 texts) and, by the editor's
personal grant, the **Annotated Corpus of Luwian Texts**: 266
Hieroglyphic Luwian inscriptions of the Iron Age, each clause paired in
a morphologically analyzed transcription and a sign-by-sign
transliteration — the Hittite desk now spans Old Hittite to the Luwian
monuments.

The **Ras Shamra Tablet Inventory** (University of Chicago, OCHRE;
joined 31 July 2026 under a written grant) adds the inventory spine of
Ugarit: 5,075 records — one per inscribed object of Ras Shamra and Ras
Ibn Hani, with RS number, KTU/CTA/UT concordances, findspot, and museum
number — and line-grain published editions (740 passages, Ugaritic and
Akkadian) where OCHRE publishes one. Inventory-first by design: the
concordance layer is what Ugaritologists join their citations against.

## Egyptian

Three millennia of Egyptian in Unicode transliteration (synchronized 18
July 2026): 101,793 gold-lemmatized sentences from the Pyramid Texts to
the sawlit literary canon (AES, CC BY-SA), the only bulk Demotic
anywhere (13,383 sentences) plus Late Egyptian from the Thesaurus
Linguae Aegyptiae's official datasets, the 35,052-entry Ägyptische
Wortliste as the dictionary shelf, and the Comprehensive Coptic Lexicon
whose egy↔cop crosswalk turns Egyptian etymology into resolvable edges.

## Hebrew and Aramaic

The Masoretic text of the Leningrad Codex byte-verbatim (the
combining-mark order is never normalized), fully morphology-tagged with
ketiv/qere preserved; the ETCBC BHSA beside it with full clause/phrase
syntax — the library's first constituency data; the Dead Sea Scrolls
(1,001 scrolls under Abegg's own CC BY-NC grant); the verse-aligned
Targums; the **Peshitta Old Testament** as the alignment hub's Syriac
leg; the **Digital Syriac Corpus** (632 documents — a millennium of
classical Syriac, CC BY); the augmented-Strong's lexicon that resolves
every OSHB lemma to its BDB entry; the UBS Semantic Dictionary; and the
epigraphy of Israel/Palestine (5,499 inscriptions). Since October 2026
the BHSA rides every word-level feature its dataset publishes, and the
Scrolls carry the ETCBC's lexeme crosswalk: virtually every scroll word
resolves to its Hebrew Bible lexeme.

## Elephantine

The multilingual documentary record of one island community (the Berlin
ERC papyri and ostraca database, Ägyptisches Museum und Papyrussammlung,
CC BY-SA; joined 28 July 2026): 15,539 documents / 69,350 passages at
the artifact grain. Imperial Aramaic leads with 5,568 passages — the
Judean garrison's archives, the library's first substantial Aramaic
document shelf — beside Greek (18,164), Demotic (5,322), earlier
Egyptian (3,194), Coptic (3,237), Arabic, Latin, and Phoenician slices
of the same community's record, with 32,877 English translation siblings
displayable page by page and line by line. 7,973 documents carry dates
on the chronological axis, with genre, material, and object-type facets
on roughly ten thousand.

## Arabic and Persian

The OpenITI corpus — the premodern Islamicate library, and the largest
openly licensed historical corpus in existence — was ingested on 22 July
2026: **9,079 documents / 34,631,499 passages**. Classical Arabic
(33,294,039 passages) is thereby the library's largest language: Quran
and hadith, history and biography, fiqh, kalām and falsafa, the dīwāns
and adab. The Persian shelf (1,337,472 passages) rides the same release —
Ḥāfiẓ, Niẓāmī, ʿAṭṭār, Ibn Sīnā. Passages are cited by volume, page, and
paragraph; the Arabic-script search fold strips tashkeel and bridges the
Persian keyboard (ی/ي, ک/ك), so Arabic-typed queries find Ḥāfiẓ and vice
versa. Licensed CC BY-NC-SA — non-commercial research use, never
redistributed. Beside it sit the KITAB text-reuse alignments over the
same library, the DiCCAS corpus of disaster accounts in Classical Arabic
sources, and the al-Ṯurayyā gazetteer of the early Islamic world as the
desk's place instrument.

## Iranian and the Silk Road

The corridor between Iran and China opened in September 2026. Oxford's
**Invisible East Digital Corpus** (CC BY) brings 1,316 documents of the
medieval Islamicate East — New Persian, Sogdian, Bactrian,
Judeo-Persian, Middle Persian, Arabic — with typed dates and located
toponyms; Prods Oktor Skjærvø's catalogue of the **Khotanese manuscripts**
in the British Library (CC BY) contributes 2,357 manuscript records with
14,574 transliterated lines, parsed record by record so the upstream
draft's damage stays local; and the **Kaʿba-ye Zartošt inscription**
arrives sentence-aligned in all three of its versions — Middle Persian,
Parthian, Greek — the library's first Parthian. Ḥāfeẓ's *Dīwān* rides
the Perseus Persian shelf beside the OpenITI Persian classics, and the
CDLI and ORACC Old Persian royal inscriptions serve the same desk.

## Turkic and Mongolic

Two desks opened together in September 2026. The Turkologist's starts
with **ATMO** — Annotated Turki Manuscripts from the Jarring Collection
Online (Indiana University and Lund University Library, CC BY-SA):
Eastern Turki manuscripts of the eighteenth to twentieth centuries,
Perso-Arabic text with a full Latin transliteration on every line,
marginalia served with their provenance marked — beside the Old Turkic
treebank, Wiktionary extracts for Old Turkic, Old Uyghur and Chagatai,
and the West Old Turkic loanword dictionary. The Mongolist's opens on
John C. Street's romanized text of the *Secret History of the Mongols*
(Monumenta Altaica, by the maintainer's grant, Street's own copyright
notice carried verbatim): 3,523 lines at Street's own numbering, beside
the Ming Chinese transcription on the Chinese Wikisource shelf.

## Ethiopic (Gǝʿǝz)

The Ethiopic axis, joined 26 July 2026. Beta maṣāḥǝft (Hiob-Ludolf-Zentrum,
Hamburg, CC BY-SA) supplies the text-bearing works of its catalog — 3,796
documents / 66,516 passages, carrying the Gǝʿǝz Bible: a near-complete Old
Testament, all four Gospels, and Acts, the Epistles, and Revelation. The
TraCES corpus (ERC, Hamburg) adds 15 documents / 75,436 morphologically
analyzed word tokens — the Gospel of Matthew, the Kebra nagast prologue
and twenty-five chapters, the royal chronicle of ʿAmda Ṣǝyon, the
Testamentum Domini, and seven Aksumite royal inscriptions — the gold
lemma lane of the shelf, with each analyzed token linked to its entry in
Dillmann's 1865 *Lexicon linguae aethiopicae* (13,727 entries) on the
reference shelf: text, gold analysis, and the standard lexicon closed
into one loop.

## Pre-Roman Italy and Sicily

The Etruscan corpus (6,248 OpenEtruscan inscriptions with English
siblings and the ETP glossary), CEIPoM's lemmatized epigraphy of the
whole peninsula (3,871 texts — Oscan, Umbrian with the complete Iguvine
Tables, Venetic, Messapic, South Picene, Faliscan, archaic Latin
including the Fibula Praenestina), Corpus ItAnt's critical editions,
the Lexicon Leponticum and Raetic corpora of record from Vienna, and
I.Sicily's 5,074 inscriptions across all the languages of ancient
Sicily. Synchronized 18 July 2026.

## Biblical editions

Editions serving the alignment hub: the complete Clementine Vulgate (73
books, public domain), the SBL Greek New Testament (CC BY), and the World
English Bible (public domain) as the readable English witness. With these
aboard, one Gospel citation renders across up to fifteen registered
witnesses (the two Coptic dialects joined on 13 July 2026), and
the Old Testament axis runs seven-legged — Masoretic text (twice, at two
annotation grains) ↔ Septuagint ↔ Vulgate ↔ English ↔ Targum Onkelos ↔
Peshitta — with the Greek/Hebrew Psalm numbering divergence mapped
explicitly.

## Old English

The complete six-volume Anglo-Saxon Poetic Records — Beowulf, the Junius
Manuscript, the Vercelli Book, the Exeter Book, the Paris Psalter, and the
Minor Poems — cited by the canonical printed line numbers, alongside the
ISWOC treebank (Ælfric, Apollonius, the Chronicles, Orosius, and the
West-Saxon Gospels, gold-annotated) and the Bosworth-Toller dictionary on
the reference shelf, with æ/þ/ð-tolerant lookup.

## Slavic

The Old Church Slavonic canon: four gospel codices in the Helsinki CCMH
transliteration (Zographensis, Marianus, Assemanianus, Savvina kniga),
folio-line cited, beside the PROIEL/TOROT editions — a substrate for
collation. The ~1000 CE Freising Manuscripts, the oldest Slavic text in
Latin script, appear in three aligned transcription layers with five modern
translations (CC BY-ND; held under the library's strictest access class).
Early Modern Slovenian print is covered by goo300k (gold-annotated,
1584–1899) and the IMP corpus (658 documents), all dated per document and
feeding the chronological axis.
Since 17 July 2026 the damaskini corpus (CLARIN.SI, CC BY-SA) extends
the axis southward: 23 gold-annotated Balkan Slavic witnesses of the
fifteenth through nineteenth centuries on the Church Slavonic–Bulgarian
continuum — roughly ten of them independent witnesses of the *Life of
St. Petka* — each paired with a full English sibling translation, with
the corpus's own norm and origin classifications carried as document
facets.

October 2026 opened the shelves end to end. Nine Wikisource cones —
Serbian epic song and Vuk's collections, the Croatian premodern
centuries, Macedonian nineteenth-century letters, Slovene to 1899,
Czech from Dalimil to Comenius, the Polish premodern canon, Bulgarian
charters, and the Old East Slavic chronicles in Russian and Ukrainian
— were each censused category by category under written exclusion
rules (texts keyed to in-copyright editions are turned away). Beside
them: Scripta Bulgarica's 124 medieval Bulgarian monuments (CC
BY-NC-SA), the complete Ipatiev chronicle from the 1908 Petersburg
edition, the 1488 Prague Bible as a medieval Czech ground truth, the
Slavonic *Zrcalo* of 1445, the Slovene and Croatian Protestant prints
of Trubar and Bohorič in page OCR, the long Slovenian prose of KDSP and
PriLit, the Croatian school canon, the Serbian ELTeC novels and the
ijekavian Vuk–Daničić Bible — each work admitted on its own
public-domain record — and the German Slavistics canon, Miklosich to
Jagić's *Archiv*, as a reference shelf with its OCR quality measured per
volume.

## The Chinese libraries

The step change of 20 July 2026: the Kanseki Repository (Kyoto's
premodern-Chinese library, KR1 classics through the KR5 Daoist canon)
and the CBETA Buddhist canon (Taishō and Xuzangjing in TEI) together
hold **13.2 million passages of Literary Chinese** — the library's
second-largest language, behind only Classical Arabic. The
Thesaurus Linguae Sericae adds sense-level attributions into the
classics, and the character instruments (Unihan, the BabelStone IDS
decompositions, Baxter-Sagart Old Chinese, the Guangyun rime dictionary,
the Heian-period HDIC dictionaries) feed the `nabu char` card — a Han
character answered across four millennia of structure, sound, and
attestation. Traditional, simplified, and z-variant spellings fold to
one search skeleton, so a modern-script query reaches the
traditional-script corpus.

Since late August 2026 the Sinitic desk has grown around that core: the
NiuTrans Classical↔Modern parallel corpus (1.9 million sentence pairs —
its modern side web-crawled, as its README says, and labelled so),
Chinese Wikisource's censused works (the complete 全唐文, the 續資治通鑑,
and the Ming Chinese 元朝秘史), the Đại Việt classical shelf, the rime
books from the restored *Qieyun* through the 'Phags-pa *Menggu ziyun*
to the *Zhongyuan yinyun* (the *Qieyun* and *Guangyun* cross-linked rime
by rime), and two instruments of Chinese history — the China
Biographical Database behind `nabu person` and the China Historical GIS
gazetteer.

## Korean

The Koreanist's desk opened in August 2026 on the open datasets of the
National Institute of Korean History and the Institute for the
Translation of Korean Classics (KOGL, unrestricted use with credit):
the **Veritable Records of the Joseon Dynasty** (414,321 entries), the
**Daily Records of the Royal Secretariat** (1.9 million entries), the
two Goryeo histories, the Border Defense Command register, and the
ITKC's classical originals in hanmun — beside the Open Korean Historical
Corpus's historical slice (1.2 million records, CC BY-NC), whose dated
records make Korea the largest single block on the library's
chronological axis. The *Yongbi eocheon ga* of 1447, from Korean
Wikisource, opens the Middle Korean vernacular shelf.

## The Tibetan canon

The fourth canon leg — after the Pali, Sanskrit, and Chinese Buddhist
canons — joined on 28 July 2026, complete. The Digital Derge Kangyur
(1,200 documents / 461,304 passages: 103 volumes, Tohoku 1–1108) and
Derge Tengyur (3,362 documents / 897,142 passages: 213 volumes, Tohoku
1109–4569, the commentarial half of the canon) are cited by page and
line as an exact representation of the Derge woodblocks — carving
variants preserved on purpose — and are public domain. Beside them,
84000 ("Translating the Words of the Buddha") supplies the published
English Kangyur translations — 388 documents / 124,223 passages, CC
BY-NC-ND — for orientation. Old Tibetan Documents Online (ILCAA, Tokyo,
CC BY) brings the earlier stage of the language: 413 critically edited
documents in Wylie transliteration — Dunhuang manuscripts, the
imperial-period pillar inscriptions including the Zhol pillar and the
821/822 Sino-Tibetan treaty pillar, and five Old Zhangzhung texts — with
the Old Tibetan Annals and Chronicle (the two foundational histories,
the Annals with an aligned English translation) in a companion corpus.
The SOAS Classical Tibetan corpus contributes four texts with
hand-corrected segmentation and gold part-of-speech tags (318,230
tokens). The desk's dictionary rack sits on the reference shelf: the
Mahāvyutpatti — the ninth-century imperial Sanskrit–Tibetan translation
glossary, the crosswalk between the Sanskrit shelves and this canon —
plus the Tibetan Verbs Database and a Wiktionary-derived Tibetan
lexicon.

## The Japanese reading desk

Aozora Bunko — the volunteer-transcribed Japanese public-domain library —
joined on 21 July 2026: **2,983,332 passages** (October 2026) of Meiji-and-later
literature with a thin classical tail, ruby readings preserved as
annotations rather than flattened into the text, and the ~2,285 works in
kyūjitai orthography reachable from modern-form queries through the
kanji reform fold (国 finds 國). Only copyright-expired works are
ingested — the in-copyright remainder is excluded before a single file
is opened. Beside it sit ONCOJ's gold-morphology Old Japanese
(the Man'yōshū-era corpus) and the EDRDG dictionaries.

The classical side arrived in late September 2026. The National Diet
Library's next-generation digital library serves machine-OCR full text
for its copyright-expired classical books, and a resumable crawl walks
them at a deliberately gentle pace — 26,860 documents so far, each
labelled as machine OCR and carrying its permalink to the NDL viewer.
Beside it: Minna de Honkoku's citizen transcriptions of premodern
documents (CC BY-SA), Japanese Wikisource's era cone from Asuka to Edo
with the *Man'yōshū* cited by poem number, the National Institute of
Japanese Literature's TEI *Kokinshū* and *Man'yōshū* witnesses, and
Ikeda Kikan's critical *Genji* — the Heian texts staged onto Early
Middle Japanese in the lect layer. The NRCT historical placenames serve
the desk's place lane.

## Southeast Asia

The Indic cosmopolis at its eastern edge, opened in September 2026: the
ERC DHARMA project's epigraphy of Old Khmer (1,219 inscriptions under
their Cœdès K-numbers), Champa, the Pyu city-states and the Nusantara
charters in Old Javanese, Old Malay and Old Sundanese, with its
philology repository's Old Javanese kakawin library; the Old Burmese
stone inscriptions of Bagan (OBI); and the Old Javanese Wordnet as the
desk's glossary — most of these languages in their only
machine-readable form.

## The Germanic shelves

22 July 2026 completed the desk across all three branches.
**North**: Menotec's seven Old Norwegian treebanks with the Poetic Edda
of Codex Regius (20,308 gold-annotated sentences), and Rundata — the
Scandinavian runic corpus, ~6,800 inscriptions in up to five text lanes
each (scholarly transliteration primary, Old-West-Norse and
runic-Swedish normalisations, English and Swedish translations), the
damage notation stored verbatim as content. **West**: the Old Saxon
*Heliand* parsed to the token with gold form-lemma pairs (HeliPaD), and
the Referenzkorpus Mittelhochdeutsch — 406 manuscripts / 355,449
diplomatic manuscript lines whose gold annotation makes Middle High
German one of the corpus's largest lemma pools (2.10 million rows) on day
one. **East** was already home: Wulfila's Gothic on the PROIEL treebank.
Old Icelandic went live with the owner's same-day Universal
Dependencies sync — 44,029 IcePaHC passages whose 812,484 gold rows
entered among the largest lemma pools. The Hanseatic rung followed on
26 July 2026: ReN, the Referenzkorpus Mittelniederdeutsch/
Niederrheinisch 1200–1650 (CC BY), with 235 documents / 297,504
passages — 161 of them gold-annotated, about 1.49 million tokens with
lemma, part of speech, and morphology — between ReM's Middle High
German and the Norse and Old English shelves. Since October 2026 both
reference corpora also ride their CorA layer: full morphology,
dictionary-form lemmas, and real dates.

The August 2026 waves completed the ladder. **Menota**, the Medieval
Nordic Text Archive (CC BY-SA), adds 91 Old Icelandic, Old Norwegian,
Old Swedish and Old Danish manuscripts in multi-level transcription;
Språkbanken's **Fornsvenska textbanken** the Old Swedish laws, prose and
verse; **ReF** carries Early New High German 1350–1650; and the
**Deutsches Textarchiv** (BBAW, CC BY-SA) the German print corpus from
1473 to 1969 — 5,478 works. Dutch joined from both ends: the Old Dutch
word material of the Corpus Oudnederlands and the thirteenth-century
Early Middle Dutch of the Corpus Gysseling, lemmatized — both held for
private research, as their non-commercial terms grant no
redistribution.

## Middle and Early Modern English

The **Corpus of Middle English Prose and Verse** (Middle English
Compendium, University of Michigan; public domain) holds 297 texts —
1,355,279 passages from Chaucer to the mystery plays — and the
**EEBO-TCP** transcriptions of Early English Books Online (Text
Creation Partnership, CC0) hold 60,325 printed books from 1473 to 1700:
25 million passages that make early modern English the library's
second-largest language. The transcriptions are the TCP's own; the page
images were never fetched.

## The Americas

The library's first American wing opened in October 2026, colonial era
first. **Ticha** (Haverford College, CC BY-SA) brings colonial Valley
Zapotec in TEI — Córdova's 1578 *Arte*, Agüero's 1666 *Miscelaneo*, and
two centuries of notarial testaments, each postured honestly as original
or period translation. The Royal Danish Library's public-domain edition
of **Guaman Poma's *Nueva corónica y buen gobierno*** arrives entire, page
by page, Spanish with its Quechua and Aymara passages. And the Jesuit-era
**Tupinambá and Old Guaraní** treebanks ride the Universal Dependencies
shelf.

## Reference shelf

Dictionary shelves as structured data rather than page
images — **{{ census.dictionary_entries_display }} entries** as of {{ census.as_of }}.
Liddell-Scott-Jones (116,497 entries), Lewis &amp; Short (51,636),
Bosworth-Toller (62,815), the Monier-Williams Sanskrit-English dictionary
(193,890, synchronized 13 July 2026, with transliteration-tolerant lookup
and citations resolving into the Sanskrit shelf), a Wiktionary-derived Old
Church Slavonic lexicon (4,615), seven reconstruction dictionaries
(Proto-Indo-European, Proto-Slavic, Proto-Germanic, Proto-West Germanic,
Proto-Balto-Slavic, Proto-Italic, Proto-Indo-Iranian) whose entries carry
machine-readable descendant trees, and — since 17 July 2026 — Old Irish,
Middle Irish, and Middle Welsh extracts on the same Wiktionary shelf.
Three etymological witnesses joined on
14 July 2026: the IE-CoR Indo-European cognacy database (4,981
expert-curated cognate sets with loan events flagged), the LIV-LOD
dictionary of Proto-Indo-European verbs (305 verbal etymons), and de
Vaan's <em>Etymological Dictionary of Latin</em> (2,860 etymons, LiLa
linked-data edition) — independent, expert-curated chains beside the
Wiktionary-derived ones.

Two further shelves arrived with the 17 July 2026 synchronizations. The
StarLing / Tower of Babel etymological databases (56 shelves and 113,419
entries as of October 2026, held under a written grant from their
maintainer with per-compiler credit rendered on every surface) carry
the Moscow-school apparatus: Pokorny's
complete <em>Indogermanisches Etymologisches Wörterbuch</em> (2,222
roots), Nikolayev's Walde-Pokorny-based PIE database (3,291 etymologies
with per-branch reflex columns), Vasmer's etymological dictionary of
Russian in the Trubachev edition (18,239 entries), the Common
Germanic, Baltic and Kartvelian databases, and — since the September
2026 wave — the Altaic dictionary (Starostin-Dybo-Mudrak) with its
Japanese companion, North Caucasian, Sino-Tibetan, Dravidian, the
Chukchee-Kamchatkan family trio, and Yenisseian — and, since October
2026, the thirteen lexicostatistical tables that shipped inside the
Indo-European package, Swadesh-grain wordlists whose every form carries
a cognation number. The Slovenian historical dictionary shelf
(ZRC SAZU via CLARIN.SI, CC BY, 139,405 entries) unites Pleteršnik's
Slovene-German dictionary of 1894–95, the lexicon of Janez Svetokriški's
Baroque sermons, and the complete word inventory of sixteenth-century
Slovenian print — closing the gold-lemma-to-dictionary loop for
Slovenian as LSJ closes it for Greek. The expansions of 18–21 July 2026
added the Hebrew desk (the augmented-Strong lexicon, the BDB outline,
and the UBS Semantic Dictionary of Biblical Hebrew), the Egyptian
dictionary chain (the TLA Wortliste and the Comprehensive Coptic
Lexicon), and the Sino-Japanese desk — Unihan's 65,092 codepoint
records, KANJIDIC2 and JMdict, the Heian-period HDIC dictionaries, the
Guangyun rime dictionary, and the ONCOJ Old Japanese lexicon.

Late July and early August 2026 added four more groups. The Tibetan
rack: the Mahāvyutpatti (9,379 entries, public domain), the Tibetan
Verbs Database (2,491 entries with the grammarians' disagreements
deliberately uncollapsed, CC0), and a Wiktionary-derived Tibetan
lexicon (3,651). Dillmann's <em>Lexicon linguae aethiopicae</em> for
Gǝʿǝz (13,727 entries, the very entries the TraCES gold tokens link
to). Two cross-linguistic typological instruments: CLICS³, the database
of colexifications (1,647 concept entries whose cards show which
languages express two meanings with one word), and WOLD, the World
Loanword Database (64,289 entries across 41 recipient languages with a
curated borrowed status per word). And — 2 August 2026 — DÉRom, the
<em>Dictionnaire Étymologique Roman</em> (ATILF): 233 Proto-Romance
etymon articles with per-language reflex sections across the whole
Romance family, the comparative-method bridge between Latin and its
daughters (CC BY-NC-SA).

The shelf has kept growing with the desks. Since late August 2026: the
Monlam Tibetan headword lists (449,829 headwords), the open subset of
the Welsh *Geiriadur Prifysgol Cymru* (89,386 entries), the Chinese
rime books, Wiktionary's Chinese, Sumerian, Akkadian and Hittite
lexica, the West Old Turkic loanword dictionary, the Old Javanese
Wordnet, and — October 2026 — Brückner's 1927 etymological dictionary
of Polish and Nasovič's 1870 dictionary of Belarusian.
Dictionary
citations are resolved to live passages where the cited work is held: the
LSJ entry for μῆνις points at *Iliad* 1.1 as a resolvable URN, not a
printed abbreviation.

## The local shelves

The library's {{ census.local_shelves }} local shelves hold material that is authored, acquired, or computed
rather than downloaded. A language-dossier shelf carries the library's per-language
curation — one plain Markdown file per language code, feeding the
`nabu language` reference cards. A local-library
shelf files the owner's own PDFs, scans, and offprints as catalogued,
page-cited collections through the `nabu ingest` command (see
[Tools]({{ '/tools/' | relative_url }})), which since July 2026 also
accepts http(s) URLs, downloading first and recording the given address
in the manifest; everything on this shelf is held under
the library's strictest access class by default and is never served or
redistributed. A source-dossier shelf carries a curated description of
every registered source, served on the `nabu list` census and checked
against the shelf map at every development gate. And a notes shelf
records the owner's own annotations on any citable URN through
`nabu note` — scholia of one's own, rendered wherever the target is
shown. A lemma shelf keeps the raw output of the local lemmatization
campaigns (`nabu lemma-enrich`) — computation too costly to re-derive
for free — from which the silver lemma tier is projected. What these shelves hold is the owner's private business: their
contents and counts are deliberately absent from this site.
