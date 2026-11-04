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
{{ census.language_codes }} language codes appear in all, each resolving
through the historical-stage ladders described on the
[Languages]({{ '/languages/' | relative_url }}) page.

The table lists every collection. Its sizes were read from the live catalog
on {{ site.data.sources.as_of }} and are regenerated at every development
gate. Each collection name links to its short description below, and each
row is itself linkable by shelf name — `/library/#shelf-celtic`,
`/library/#shelf-korean`. The authoritative shelf map is
[docs/library.md](https://github.com/arvicco/nabu/blob/main/docs/library.md)
in the repository; the same shelves grouped by scholarly desk, each with its
instruments, CLI recipes and terminal setup, are the
[research desks]({{ '/axis/' | relative_url }}).

{% assign shelves = site.data.sources.shelves -%}
| Collection | Contents | Period | Size (documents / passages) | License class |
|---|---|---|---|---|
| <span id="shelf-classical-greek"></span>[Classical Greek](#classical-greek-literature) | Perseus: Homer, the tragedians, Herodotus, Plato, Galen, with aligned English translations | 8th c. BCE – 3rd c. CE | {{ shelves["classical-greek"].size_display }} | CC BY-SA |
| <span id="shelf-post-classical-greek"></span>[Post-classical Greek](#post-classical-greek) | First1KGreek: Athenaeus, Philo, church fathers, Swete's Septuagint | 3rd c. BCE – 6th c. CE | {{ shelves["post-classical-greek"].size_display }} | CC BY-SA |
| <span id="shelf-greek-silver"></span>[Greek silver layer](#the-greek-silver-layer) | Diorisis and GLAUx: machine-lemmatized second editions of the Greek canon, honestly labelled | Homer – early Byzantium | {{ shelves["greek-silver"].size_display }} | CC BY-SA / mixed per document |
| <span id="shelf-classical-latin"></span>[Classical Latin](#classical-latin-literature) | Perseus: Vergil, Ovid, Cicero, Livy, Tacitus, with aligned English translations | 3rd c. BCE – Late Antiquity | {{ shelves["classical-latin"].size_display }} | CC BY-SA |
| <span id="shelf-latin-romance"></span>[Latin–Romance continuum](#the-latinromance-continuum) | digilibLT late-antique Latin, openMGH, CroALa, Corpus Córporum's Patrologia; BFM Old French, the Galician-Portuguese cantigas, Old Spanish, Portuguese, Catalan, Occitan, Sardinian and Judeo-Spanish shelves | 2nd c. CE – early modern | {{ shelves["latin-romance"].size_display }} | CC BY / CC BY-SA / NC / written grant |
| <span id="shelf-papyri"></span>[Documentary papyri](#documentary-papyri) | Papyri.info DDbDP: contracts, letters, tax receipts (Greek, Coptic, Latin, Arabic, Demotic) | c. 300 BCE – 8th c. CE | {{ shelves["papyri"].size_display }} | CC BY |
| <span id="shelf-latin-inscriptions"></span>[Latin inscriptions](#latin-inscriptions) | Epigraphic Database Heidelberg: epitaphs, dedications, milestones from the whole empire, with genre facets | Republic – Late Antiquity | {{ shelves["latin-inscriptions"].size_display }} | CC BY-SA |
| <span id="shelf-greek-inscriptions"></span>[Greek inscriptions](#greek-inscriptions) | Attic Inscriptions Online: the inscriptions of Attica in English translation, with AIO's own Greek editions | Archaic – Roman | {{ shelves["greek-inscriptions"].size_display }} | CC BY-SA |
| <span id="shelf-armenian-inscriptions"></span>[Armenian inscriptions](#armenian-inscriptions) | ArmEpiC: the Artsakh inscriptions — donation records, building texts and khachkars of the monasteries of Khachen, lemmatized and translated | 12th – 20th c. CE | {{ shelves["armenian-inscriptions"].size_display }} | CC BY-NC |
| <span id="shelf-inscriptions-of-italy"></span>[Inscriptions of Italy](#latin-inscriptions) | Epigraphic Database Roma: the peninsula itself, the geographic complement of Heidelberg's provinces — dated and faceted end to end | Republic – Late Antiquity | {{ shelves["inscriptions-of-italy"].size_display }} | CC BY |
| <span id="shelf-celtic"></span>[Celtic](#celtic) | CorPH Early Irish (gold-lemmatized), the RIIG Gaulish inscriptions, the Ogham in 3D stones | c. 2nd c. BCE – 10th c. CE | {{ shelves["celtic"].size_display }} | CC BY / MIT (ogham held `nc` pending clarification) |
| <span id="shelf-coptic"></span>[Coptic](#coptic) | Coptic Scriptorium: the complete Sahidic and Bohairic New Testaments, monastic and patristic prose, gold-lemmatized | c. 3rd – 10th c. CE | {{ shelves["coptic"].size_display }} | CC BY per document (source class `nc`) |
| <span id="shelf-sanskrit"></span>[Sanskrit](#sanskrit) | GRETIL: Rāmāyaṇa, purāṇas, kāvya, śāstra, the Ṛgveda with Vedic accents | c. 1200 BCE – 18th c. CE | {{ shelves["sanskrit"].size_display }} | CC BY-NC-SA |
| <span id="shelf-indic-expansion"></span>[Indic expansion](#the-indic-expansion) | SARIT, SuttaCentral (the segmented Pali canon with aligned English and its variant apparatus), the gold-lemmatized DCS, Classical Newar (DACON) | Veda – early modern | {{ shelves["indic-expansion"].size_display }} | CC BY / CC BY-SA / NC per source |
| <span id="shelf-south-asia"></span>[South Asia](#south-asia) | The DHARMA Tamil-country and Deccan epigraphy estates, Siddham's Gupta-era inscriptions, the printed *South Indian Inscriptions* volumes, TAMILEX's critical editions of the classical Tamil canon, Project Madurai's e-texts, Ollett's Kannada and Prakrit editions, the Gurmukhī scriptural canon, the Gujarati bhakti prints | c. 3rd c. BCE – 19th c. CE | {{ shelves["south-asia"].size_display }} | CC BY / BY-SA / BY-NC-SA / PD per source |
| <span id="shelf-treebanks"></span>[Treebanks](#morphosyntactic-treebanks) | PROIEL, TOROT, UD, ISWOC: gold lemma, morphology, and syntax | 5th c. BCE – 18th c. CE | {{ shelves["treebanks"].size_display }} | mostly CC BY-NC-SA |
| <span id="shelf-cuneiform"></span>[Cuneiform](#cuneiform-and-the-ancient-near-east) | ORACC, over a hundred projects: the complete State Archives of Assyria, the Achaemenid trilinguals, the ePSD2 corpora, the CC0 project pack, with aligned English translations | late 4th mill. – 4th c. BCE | {{ shelves["cuneiform"].size_display }} | CC0 |
| <span id="shelf-ancient-near-east"></span>[Ancient Near East](#cuneiform-and-the-ancient-near-east) | TLHdig Hittite and the glossed Hittite texts, the Luwian corpus, the CDLI catalog, eBL Fragmentarium, Achemenet Babylonian, SEAL, Ugaritic (CUC), Peshitta and the Syriac corpus, ETCSL Sumerian literature | late 4th mill. BCE – 13th c. CE | {{ shelves["ancient-near-east"].size_display }} | CC BY / CC0 / NC / personal grants per source |
| <span id="shelf-ugarit"></span>[Ugarit (Ras Shamra)](#cuneiform-and-the-ancient-near-east) | The RSTI tablet inventory: RS↔KTU concordances, findspots, published editions at line grain | Late Bronze Age | {{ shelves["ugarit"].size_display }} | CC BY-NC-SA (written grant) |
| <span id="shelf-hebrew-aramaic"></span>[Hebrew &amp; Aramaic](#hebrew-and-aramaic) | OSHB and BHSA Masoretic text, the Dead Sea Scrolls, the Sefaria Targums, the inscriptions of Israel/Palestine | c. 1000 BCE – 10th c. CE | {{ shelves["hebrew-aramaic"].size_display }} | CC BY / NC per source |
| <span id="shelf-elephantine"></span>[Elephantine](#elephantine) | The island's multilingual documentary record: Aramaic, Greek, Demotic, Egyptian, Coptic, with English translation siblings | 3rd mill. BCE – Islamic Egypt | {{ shelves["elephantine"].size_display }} | CC BY-SA |
| <span id="shelf-arabic-persian"></span>[Arabic &amp; Persian](#arabic-and-persian) | OpenITI: Quran and hadith, history and biography, fiqh, kalām and falsafa, the dīwāns and adab; the Persian classics; the DiCCAS disaster corpus | 7th c. – early modern | {{ shelves["arabic-persian"].size_display }} | CC BY-NC-SA |
| <span id="shelf-iranian-silk-road"></span>[Iranian &amp; the Silk Road](#iranian-and-the-silk-road) | The Invisible East documents, Skjærvø's Khotanese manuscripts, the trilingual Kaʿba-ye Zartošt inscription, Hafez in Perseus — and the TITUS grant estate: the Avestan canon, the Pahlavi books, the Bactrian documents, the Manichaica, the Khotanese and Sogdian books, and the complete Tocharian A and B corpora | 3rd c. BCE – 14th c. CE | {{ shelves["iranian-silk-road"].size_display }} | CC BY / CC BY-SA / personal grants (nc) |
| <span id="shelf-turkic-mongolic"></span>[Turkic &amp; Mongolic](#turkic-and-mongolic) | ATMO's Eastern Turki manuscripts, Street's *Secret History of the Mongols* | 13th – 20th c. | {{ shelves["turkic-mongolic"].size_display }} | CC BY-SA / use grant |
| <span id="shelf-egyptian"></span>[Egyptian](#egyptian) | The TLA sentence corpora (AES + Late Egyptian/Demotic), gold-lemmatized | late 4th mill. – 1st c. BCE | {{ shelves["egyptian"].size_display }} | CC BY-SA |
| <span id="shelf-ethiopic"></span>[Ethiopic (Gǝʿǝz)](#ethiopic-gǝʿǝz) | Beta maṣāḥǝft works incl. the Gǝʿǝz Bible; the TraCES gold-analyzed corpus with the Aksumite royal inscriptions | Aksumite – the manuscript tradition | {{ shelves["ethiopic"].size_display }} | CC BY-SA / NC |
| <span id="shelf-pre-roman-italy"></span>[Pre-Roman Italy &amp; Sicily](#pre-roman-italy-and-sicily) | CEIPoM, ItAnt, the Etruscan editions, TIR, Lexicon Leponticum, I.Sicily | 7th c. BCE – Roman | {{ shelves["pre-roman-italy"].size_display }} | CC BY per source |
| <span id="shelf-aegean"></span>[Aegean scripts](#aegean-scripts) | DĀMOS, the Mycenaean Linear B corpus; SigLA, the signs of Linear A; the Cypriot syllabic inscriptions (IG XV 1,1) | 2nd mill. BCE – Hellenistic | {{ shelves["aegean"].size_display }} | CC BY / NC per source |
| <span id="shelf-biblical-editions"></span>[Biblical editions](#biblical-editions) | Clementine Vulgate, SBL Greek New Testament, World English Bible | — | {{ shelves["biblical-editions"].size_display }} | PD / CC BY |
| <span id="shelf-old-english"></span>[Old English poetry](#old-english) | The complete Anglo-Saxon Poetic Records: Beowulf, the Exeter Book, Dream of the Rood | c. 700–1150 | {{ shelves["old-english"].size_display }} | CC BY-SA |
| <span id="shelf-middle-early-modern-english"></span>[Middle and Early Modern English](#middle-and-early-modern-english) | The Corpus of Middle English Prose and Verse; the TCP's EEBO, Evans and ECCO transcriptions — English print on both sides of the Atlantic; the Folger's EMMO manuscripts | c. 1100 – 1800 | {{ shelves["middle-early-modern-english"].size_display }} | PD / CC0 / CC BY-SA |
| <span id="shelf-slavic"></span>[Slavic](#slavic) | CCMH OCS gospel codices, the Freising Manuscripts, Early Modern Slovenian, the damaskini, Scripta Bulgarica, the Wikisource cones, the Ipatiev chronicle, the 1488 Prague Bible, Protestant prints, the Croatian school canon, the Serbian novel and Bible, the German Slavistics canon | c. 1000 – early 20th c. | {{ shelves["slavic"].size_display }} | CC BY / CC BY-SA / PD / NC (Freising BY-ND) |
| <span id="shelf-baltic-finnic-basque"></span>[Baltic, Finnic and Basque](#baltic-finnic-and-basque) | SENIE, early written Latvian; VAKK, Old Written Estonian; VKS, Old Literary Finnish; BIM/SAHCOBA, the syntactically annotated historical Basque corpus | 16th – 19th c. CE | {{ shelves["baltic-finnic-basque"].size_display }} | CC BY / NC per source |
| <span id="shelf-chinese"></span>[Chinese libraries](#the-chinese-libraries) | Kanripo (KR1 classics – KR5 Daoist canon), the CBETA Buddhist canon (Taishō + Xuzangjing), Chinese Wikisource's censused works, the Classical↔Modern parallel corpus, the Đại Việt classical shelf | Zhou – Qing | {{ shelves["chinese"].size_display }} | CC BY-SA / CC BY-NC-SA / MIT |
| <span id="shelf-korean"></span>[Korean](#korean) | The Joseon Veritable Records and the Royal Secretariat diaries, the Goryeo histories, the Border Defense Command register, the ITKC classical originals, the Open Korean Historical Corpus, the *Yongbi eocheon ga* | Goryeo – late Joseon | {{ shelves["korean"].size_display }} | KOGL open / CC BY-NC |
| <span id="shelf-tibetan"></span>[Tibetan](#the-tibetan-canon) | The Derge Kangyur and Tengyur complete, the 84000 English translations, the Old Tibetan documents (OTDO), the SOAS gold-POS corpus | 8th c. – the 18th-c. Derge woodblocks | {{ shelves["tibetan"].size_display }} | PD / CC BY / CC BY-NC-ND (84000) |
| <span id="shelf-japanese"></span>[Japanese](#the-japanese-reading-desk) | Aozora Bunko, the National Diet Library's classical OCR stacks, Minna de Honkoku, Japanese Wikisource, the NIJL and Genji TEI editions, ONCOJ's gold-morphology Old Japanese, NINJAL's Jesuit mission-press romanizations | 7th c. – 20th c. CE | {{ shelves["japanese"].size_display }} | open / CC BY / CC BY-SA |
| <span id="shelf-southeast-asia"></span>[Southeast Asia](#southeast-asia) | The DHARMA epigraphy of Old Khmer, Cham, Pyu and the Nusantara charters, the Old Javanese kakawin library, the Old Burmese inscriptions of Bagan, the Balinese lontar transcriptions, the Jawi-script Malay manuscripts, the Thai Collected Chronicles | c. 5th c. CE – the lontar tradition | {{ shelves["southeast-asia"].size_display }} | CC BY / CC BY-SA / PD |
| <span id="shelf-germanic"></span>[Germanic](#the-germanic-shelves) | Menotec and Menota Old Norse, Old Swedish, the Old Saxon *Heliand*, ReM, ReN and ReF (Middle High, Middle Low and Early New High German), the Deutsches Textarchiv, Old and Middle Dutch, the Rundata runic corpus | c. 200 – 1969 CE | {{ shelves["germanic"].size_display }} | nc / CC BY / CC BY-SA / ODbL / `research_private` |
| <span id="shelf-africa"></span>[Africa](#africa) | Boston University's African Ajami Library (Hausa, Mandinka, Fula and Wolof manuscripts in Arabic script), the Old Nubian treebank, a public-domain shelf of nineteenth-century African-language grammars and texts | medieval Nubia – 20th c. | {{ shelves["africa"].size_display }} | PD / NC per source |
| <span id="shelf-americas"></span>[The Americas](#the-americas) | Ticha's colonial Valley Zapotec, Guaman Poma's *Nueva corónica* | 16th – 18th c. CE | {{ shelves["americas"].size_display }} | PD / CC BY-SA |
| <span id="shelf-reference"></span>[Reference shelf](#reference-shelf) | LSJ, Lewis &amp; Short, Bosworth-Toller, Monier-Williams, Wiktionary lexica and reconstruction dictionaries, the IE-CoR, LIV, and de Vaan etymological witnesses, the StarLing / Tower of Babel databases, three Slovenian historical dictionaries, Brückner and Nasovič, the Welsh GPC, the Hebrew and Egyptian lexica, the Sino-Japanese desk (Unihan, KANJIDIC2/JMdict, HDIC, the Chinese rime books), the Tibetan rack (Mahāvyutpatti, the Verbs Database, the Monlam headwords), Dillmann's Gǝʿǝz lexicon, DÉRom, CLICS and WOLD | — | {{ census.dictionary_entries_display }} entries | CC BY-SA / CC BY / CC BY-NC-SA / written grant |

## Classical Greek literature

The Perseus Digital Library's canonical-greekLit collection: Homer, Hesiod,
the tragedians, Aristophanes, Herodotus, Thucydides, Plato, Aristotle, the
orators, Plutarch and Galen, from the Archaic period to about the third
century CE, most editions with an aligned English translation displayable
side by side. Citations follow the canonical schemes (book and line,
Stephanus pages) under stable CTS URNs. Licensed CC BY-SA.

## Post-classical Greek

The First Thousand Years of Greek project (Open Greek &amp; Latin): Athenaeus,
Philo, the church fathers, grammarians, scholia, minor historians, and
medical and mathematical writers, mostly Hellenistic through Late Antique,
with a thin English layer. Swete's Septuagint, on this shelf, is the Greek
witness of the Old Testament alignment. Licensed CC BY-SA.

## The Greek silver layer

Two machine-annotated editions of the Greek canon, Homer to early
Byzantium, kept deliberately unmerged beside the Perseus and First1K copies
of the same works: the Diorisis Ancient Greek Corpus (Vatri &amp;
McGillivray) and GLAUx (Keersmaekers, Leuven). Their lemmas and morphology
are labelled *silver* — machine-produced, excluded from gold-only search —
and make lemma search possible across the whole canon. CC BY-SA, mixed per
document.

## Classical Latin literature

Perseus canonical-latinLit: Vergil, Ovid, Horace, Cicero, Caesar, Livy,
Tacitus and Seneca, many with aligned English translations. Orthographic
variation (u/v, i/j) is folded at search, so *iuvenis*, *juvenis* and
*iuuenis* find the same word. Licensed CC BY-SA.

## The Latin–Romance continuum

Latin after antiquity and its daughter languages, held as one band. The
Latin side: digilibLT's late-antique secular prose of the second to seventh
centuries (CC BY-SA), the openMGH critical editions of the Monumenta
Germaniae Historica (CC BY), CroALa's Croatian Latinity (CC BY), and Corpus
Córporum's Patrologia Latina and wider Latin library (non-commercial). The
vernacular side: the Base de français médiéval (Old and Middle French from
the Serments de Strasbourg of 842), the complete secular Galician-Portuguese
cantigas (by written grant), the Old Spanish Textual Archive, Spanish
sonnets, Portuguese literary works, the public-domain Catalan of CTILC, and
smaller Occitan, Aranese, Sardinian and Judeo-Spanish shelves — the last
three modern, labelled where an upstream says its text is synthetic.

## Documentary papyri

The Duke Databank of Documentary Papyri via papyri.info: contracts, tax
receipts, petitions, private letters, census returns, leases and court
records from Ptolemaic to early Islamic Egypt — chiefly Greek, with Coptic,
Latin, Arabic and Demotic. Leiden-convention editorial markup is preserved,
and the fragment-search index (see [Tools]({{ '/tools/' | relative_url }}))
is built over this shelf. Licensed CC BY.

## Latin inscriptions

The Epigraphic Database Heidelberg, held as a preservation snapshot of an
archived project (CC BY-SA): epitaphs, dedications, honorific and building
inscriptions and milestones from the provinces, in Latin with the Greek
bilinguals. The Epigraphic Database Roma (Sapienza, CC BY) covers Italy
itself. Both are dated and faceted — genre, material, object type, and
province or region — and Leiden rendering and fragment search apply as on
the papyri.

## Greek inscriptions

Attic Inscriptions Online (British School at Athens, CC BY-SA): the
inscriptions of ancient Attica in English translation — decrees of the
Council and People and of the demes, laws, dedications, funerary
monuments, accounts, ephebic and prytany lists — line by line with the
translators' footnotes, AIO's own Greek editions where the project has
published them, and every record dated, Pleiades-placed and carrying
its IG/SEG concordance.

## Armenian inscriptions

ArmEpiC, the Armenian Epigraphic Corpus (EPFL): the ArtsakhEpiC
collection — the inscriptions of the monasteries, churches, bridges
and cross-stones of Artsakh, most from the thirteenth century. Donation
records of the abbots and princes of Khachen at Gandzasar and Dadivank,
building texts, khachkars raised for the souls of the dead, and
memorial lines asking passers-by for their prayers, each stone
transcribed diplomatically with its letter-numerals as carved, every
word lemmatized, the findspots mapped and the dates typed. Written
Classical Armenian (grabar) with Middle Armenian vernacular features.

## Celtic

CorPH, the Corpus PalaeoHibernicum (Maynooth): Early Irish of the seventh to
tenth centuries — the Annals of Ulster, Adomnán's Vita Columbae, Blathmac,
the Milan, St Gall and Würzburg glosses, law, poetry and computus —
gold-lemmatized, with the glosses' Latin marked token by token. RIIG
(Ausonius, Bordeaux, CC BY): Gaulish inscriptions in Gallo-Greek and
Gallo-Latin scripts with French translations. Ogham in 3D (DIAS / Maynooth):
ogham stones in Ogham script with transliteration layers, held
non-commercial because its two published license statements conflict.
Irish and Welsh dictionary extracts and the Old Irish treebanks complete the
shelf.

## Coptic

Coptic Scriptorium: the complete Sahidic and Bohairic New Testaments,
monastic and patristic prose and hagiography, with upstream gold
lemmatization. The two New Testaments are witnesses in the alignment hub,
and the corpus's language-of-origin tags make Coptic's Greek loanwords
searchable. CC BY per document; the source is held at the non-commercial
class.

## Sanskrit

GRETIL, the Göttingen Register of Electronic Texts in Indian Languages: the
Vedic saṃhitās, the Rāmāyaṇa, the purāṇas, kāvya, dharmaśāstra, philosophy
and the technical traditions. Vedic accents are preserved; commentary
layers are separately citable (kārikā against vṛtti). Licensed CC
BY-NC-SA, for non-commercial research use.

## The Indic expansion

The Digital Corpus of Sanskrit (Hellwig, CC BY), with human-verified sandhi
splitting, lemmatization and morphology — the gold Sanskrit lemma layer.
SARIT's scholarly TEI editions of works GRETIL lacks, including a complete
Southern-Recension Mahābhārata. SuttaCentral's whole Pali Tipiṭaka in roman
script (mostly CC0), with English translations on the same segments and the
variant readings, print-edition concordances and translators' notes of its
apparatus. DACON (CC BY): Classical Newar manuscripts, morphosyntactically
annotated.

## South Asia

The DHARMA project's epigraphy of the Tamil country and the Deccan (Tamil,
Telugu, Kannada, Sanskrit, Prakrit; Śaka and Kollam era dates converted to
CE), Siddham's Gupta-era inscriptions, and the printed *South Indian
Inscriptions* volumes with their original editors credited. The literary
canon: TAMILEX (Hamburg) critical editions of the Caṅkam anthologies, the
Tirukkuṟaḷ with its commentators, Tolkāppiyam and the devotional canons,
with a gold word-segmentation layer; Project Madurai's e-texts; Andrew
Ollett's Kannada and Prakrit editions; the Gurmukhī scripture of the Sikh
canon at line grain; and nineteenth-century Gujarati bhakti prints. CC BY,
BY-SA, BY-NC-SA or public domain per source.

## Morphosyntactic treebanks

Gold-standard annotation — lemma, morphology and dependency syntax per
token — from four families: PROIEL (the New Testament in Greek, Latin,
Gothic, Classical Armenian and Old Church Slavonic, with classical prose),
TOROT (Old East Slavic and OCS), ISWOC (Old English prose), and the
ancient-language treebanks of Universal Dependencies, from Vedic Sanskrit
and Hittite to Old Irish, Classical Chinese, Old Icelandic, Old Turkic and
the Jesuit-era Tupinambá and Old Guaraní. With the gold layers of the other
shelves they feed a gold lemma index of **{{ census.gold_lemmas_m }} million
rows in {{ census.gold_languages }} languages** (as of {{ census.as_of }}).
Mostly CC BY-NC-SA.

## Cuneiform and the Ancient Near East

ORACC (CC0), over a hundred projects: the complete State Archives of
Assyria, the Achaemenid royal trilinguals (Old Persian and Elamite), the
ePSD2 corpora and the CC0 project pack, with gold lemmatization for Akkadian
and Sumerian and English line by line. Around it: the CDLI universal
catalog (proto-cuneiform to the Achaemenids, by open grant); the TLHdig
Hittite corpus (CC BY, its candidate morphology at the silver tier) and a
glossed Hittite corpus with German translations; the Annotated Corpus of
Luwian Texts (Hieroglyphic Luwian, by the editor's grant); the eBL
Fragmentarium with English, cross-linked to CDLI; the Electronic Text Corpus
of Sumerian Literature; Achemenet's Babylonian texts (CC BY); SEAL, early
Akkadian literature (scholarly-use grant); and the Copenhagen Ugaritic
Corpus. The Ras Shamra Tablet Inventory (OCHRE, written grant, CC
BY-NC-SA) is the inventory of Ugarit: one record per inscribed object, with
RS↔KTU/CTA/UT concordances, findspots, and line-grain editions where
published.

## Egyptian

The Thesaurus Linguae Aegyptiae's datasets (CC BY-SA): gold-lemmatized
sentences from the Pyramid Texts to the literary canon, plus Late Egyptian
and the only bulk Demotic anywhere, with the Ägyptische Wortliste as the
dictionary and the Comprehensive Coptic Lexicon, whose Egyptian↔Coptic
crosswalk follows a word across the whole span.

## Hebrew and Aramaic

The Masoretic text of the Leningrad Codex byte-verbatim (OSHB, with
morphology and ketiv/qere) and the ETCBC BHSA with clause and phrase syntax;
the Dead Sea Scrolls (Abegg's CC BY-NC grant), linked to Hebrew Bible
lexemes; the verse-aligned Sefaria Targums; the Peshitta Old Testament and
the Digital Syriac Corpus (CC BY); the lexica that resolve every word to its
BDB entry, and the UBS Semantic Dictionary; and the inscriptions of
Israel/Palestine. CC BY or non-commercial per source.

## Elephantine

The multilingual documentary record of one island community, from the
Berlin ERC papyri and ostraca database (Ägyptisches Museum und
Papyrussammlung, CC BY-SA): Imperial Aramaic from the Judean garrison's
archives, Greek, Demotic, earlier Egyptian, Coptic, Arabic, Latin and
Phoenician, with English translations displayable line by line, and dates
and genre, material and object-type facets where recorded.

## Arabic and Persian

The OpenITI corpus, the premodern Islamicate library: Quran and hadith,
history and biography, fiqh, kalām and falsafa, the dīwāns and adab, with
the Persian classics (Ḥāfiẓ, Niẓāmī, ʿAṭṭār, Ibn Sīnā). Passages are cited
by volume, page and paragraph; Arabic-script search ignores tashkeel and
bridges the Persian and Arabic keyboards. Beside it: the KITAB text-reuse
alignments, the DiCCAS disaster accounts, and the al-Ṯurayyā gazetteer.
Licensed CC BY-NC-SA — non-commercial research use, never redistributed.

## Iranian and the Silk Road

Oxford's Invisible East corpus (CC BY): documents of the medieval
Islamicate East in New Persian, Sogdian, Bactrian, Judeo-Persian, Middle
Persian and Arabic. Skjærvø's catalogue of the Khotanese manuscripts in the
British Library (CC BY); the Kaʿba-ye Zartošt inscription aligned in Middle
Persian, Parthian and Greek; Ḥāfeẓ in Perseus. Under personal research
grants from the TITUS project (Frankfurt, held non-commercial): the Avestan
canon, the Pahlavi books, the Bactrian documents, the Manichaica, the
Khotanese and Sogdian books, and the complete Tocharian A and B corpora,
including two Tumshuqese leaves.

## Turkic and Mongolic

ATMO (Indiana University and Lund University Library, CC BY-SA): Eastern
Turki manuscripts of the eighteenth to twentieth centuries, Perso-Arabic
text with a Latin transliteration on every line. Beside it, the Old Turkic
treebank, Old Turkic, Old Uyghur and Chagatai dictionary extracts, and the
West Old Turkic loanword dictionary. For Mongolic: John C. Street's
romanized *Secret History of the Mongols* (Monumenta Altaica, by the
maintainer's grant), at Street's own numbering.

## Ethiopic (Gǝʿǝz)

Beta maṣāḥǝft (Hiob-Ludolf-Zentrum, Hamburg, CC BY-SA): the text-bearing
works of its catalog, including the Gǝʿǝz Bible. TraCES (ERC, Hamburg): a
gold morphologically analyzed corpus — the Gospel of Matthew, the Kebra
nagast, the chronicle of ʿAmda Ṣǝyon, the Testamentum Domini and the
Aksumite royal inscriptions — each token linked to its entry in Dillmann's
*Lexicon linguae aethiopicae* on the reference shelf.

## Pre-Roman Italy and Sicily

The OpenEtruscan inscriptions with English and the ETP glossary; CEIPoM's
lemmatized epigraphy of the peninsula (Oscan, Umbrian with the Iguvine
Tables, Venetic, Messapic, South Picene, Faliscan, archaic Latin); Corpus
ItAnt's critical editions; the Lexicon Leponticum and Raetic corpora from
Vienna; and I.Sicily across all the languages of ancient Sicily. CC BY per
source.

## Aegean scripts

DĀMOS, the Mycenaean Linear B corpus; SigLA, the signs of Linear A; and the
Cypriot syllabic inscriptions of IG XV 1,1. CC BY or non-commercial per
source.

## Biblical editions

The editions that serve the alignment hub: the Clementine Vulgate (public
domain), the SBL Greek New Testament (CC BY) and the World English Bible
(public domain). A Gospel citation renders across every registered New
Testament witness; the Old Testament runs Masoretic text ↔ Septuagint ↔
Vulgate ↔ English ↔ Targum Onkelos ↔ Peshitta, with the Greek/Hebrew Psalm
numbering mapped explicitly.

## Old English

The complete Anglo-Saxon Poetic Records — Beowulf, the Junius Manuscript,
the Vercelli Book, the Exeter Book, the Paris Psalter and the Minor Poems —
cited by the printed line numbers (CC BY-SA), beside the ISWOC prose
treebank and the Bosworth-Toller dictionary with æ/þ/ð-tolerant lookup.

## Slavic

The Old Church Slavonic gospel codices in the Helsinki CCMH transliteration
(Zographensis, Marianus, Assemanianus, Savvina kniga) beside the
PROIEL/TOROT editions; the Freising Manuscripts in three transcription
layers with modern translations (CC BY-ND, held at the strictest access
class); Early Modern Slovenian print (goo300k, gold-annotated, and IMP); the
damaskini (CLARIN.SI, CC BY-SA), Balkan Slavic witnesses with English.
Beyond them: Wikisource collections from Serbian epic song to the Old East
Slavic chronicles, each admitted under written public-domain rules;
Scripta Bulgarica (CC BY-NC-SA); the Ipatiev chronicle; the 1488 Prague
Bible; the Slovene and Croatian Protestant prints; the Croatian school
canon; the Serbian ELTeC novels and the Vuk–Daničić Bible; and the German
Slavistics canon as a reference shelf.

## Baltic, Finnic and Basque

SENIE, early written Latvian; VAKK, Old Written Estonian; VKS, Old Literary
Finnish; and BIM/SAHCOBA, the syntactically annotated historical Basque
corpus — sixteenth to nineteenth centuries. CC BY or non-commercial per
source.

## The Chinese libraries

The Kanseki Repository (Kyoto; the KR1 classics through the KR5 Daoist
canon) and the CBETA Buddhist canon (Taishō and Xuzangjing), with Chinese
Wikisource's censused works, the NiuTrans Classical↔Modern parallel corpus
(its modern side web-crawled, and labelled so) and the Đại Việt classical
shelf. The character instruments — Unihan, the BabelStone IDS
decompositions, Baxter-Sagart Old Chinese, the rime books, the Heian HDIC
dictionaries, the Thesaurus Linguae Sericae — feed the `nabu char` card.
Traditional, simplified and variant spellings fold together at search. CC
BY-SA, CC BY-NC-SA or MIT per source.

## Korean

The open datasets of the National Institute of Korean History and the
Institute for the Translation of Korean Classics (KOGL, free use with
credit): the Veritable Records of the Joseon Dynasty, the Daily Records of
the Royal Secretariat, the two Goryeo histories, the Border Defense Command
register and the ITKC's classical originals in hanmun. Beside them, the
Open Korean Historical Corpus's historical slice (CC BY-NC) and, from Korean
Wikisource, the *Yongbi eocheon ga* of 1447 in Middle Korean.

## The Tibetan canon

The Derge Kangyur and Tengyur, complete and public domain, cited by page and
line with the carving variants preserved; the 84000 English translations
(CC BY-NC-ND); Old Tibetan Documents Online (ILCAA, Tokyo, CC BY) —
Dunhuang manuscripts, imperial pillar inscriptions and the Old Tibetan
Annals and Chronicle; and the SOAS Classical Tibetan corpus with gold
part-of-speech tags. The dictionary rack sits on the reference shelf.

## The Japanese reading desk

Aozora Bunko's public-domain modern literature, with ruby readings kept as
annotations and old character forms reachable from modern ones (国 finds 國);
the National Diet Library's classical books as labelled machine OCR; Minna
de Honkoku's citizen transcriptions (CC BY-SA); Japanese Wikisource from
Asuka to Edo; the NIJL TEI *Kokinshū* and *Man'yōshū*; Ikeda Kikan's
critical *Genji*; ONCOJ's gold-morphology Old Japanese; and NINJAL's
transcriptions of the Jesuit mission press — the 1592 *Feiqe no
monogatari*, Aesop of 1593 and the 1596 *Contemptus Mundi*, Late Middle
Japanese printed in the mission's own phonetic romanization, with the
1603 *Nippo Jisho* headwords on the reference shelf. From Aozora
Bunko, only copyright-expired works are taken.

## Southeast Asia

The DHARMA project's epigraphy of Old Khmer, Champa, the Pyu city-states and
the Nusantara charters (Old Javanese, Old Malay, Old Sundanese), with the
Old Javanese kakawin library; the Old Burmese inscriptions of Bagan; the
Old Javanese Wordnet. The manuscript shelves: Balinese palm-leaf lontars in
Balinese script, the Jawi-script Malay manuscripts of the Leiden and
British Library collections, and the Thai Collected Chronicles. CC BY, CC
BY-SA or public domain per source.

## The Germanic shelves

North: the Menotec and Menota Old Norse manuscripts and treebanks (with the
Poetic Edda of Codex Regius), the Fornsvenska textbanken, the Old Icelandic
IcePaHC treebank, and Rundata's Scandinavian runic inscriptions with their
normalisations and translations. West: the Old Saxon *Heliand*, the
reference corpora of Middle High German (ReM), Middle Low German (ReN) and
Early New High German (ReF), the Deutsches Textarchiv's German print from
1473 to 1969, the Wolfenbüttel Grand Tour journals — four German travel
diaries of 1652–1702 edited from the manuscripts — and Old and Early
Middle Dutch (held for private research only). East: Wulfila's Gothic on
the PROIEL treebank. CC BY, CC BY-SA, ODbL or non-commercial per source.

## Middle and Early Modern English

The Corpus of Middle English Prose and Verse (University of Michigan, public
domain), from Chaucer to the mystery plays, and the Text Creation
Partnership's hand-keyed transcriptions on both sides of the Atlantic:
EEBO-TCP, the first printed books in English, 1473 to 1700; Evans-TCP,
everything printed in British America 1639 to 1800 — sermons, broadsides,
the Revolutionary pamphlet war, the first American novels; and ECCO-TCP,
the keyed selection from eighteenth-century British print — Defoe, Swift,
Pope, Johnson, Hume (all CC0; no page images are held). Beside the print,
the Folger's Early Modern Manuscripts Online: a hundred English manuscripts
of 1552–1697 transcribed word by word, with regularized spelling as an
annotation layer (CC BY-SA).

## Africa

Boston University's African Ajami Library — Hausa, Mandinka, Fula and Wolof
manuscripts in Arabic script — the Old Nubian treebank, and a public-domain
shelf of nineteenth-century African-language grammars and texts. Public
domain or non-commercial per source.

## The Americas

Ticha (Haverford College, CC BY-SA): colonial Valley Zapotec in TEI —
Córdova's 1578 *Arte*, Agüero's 1666 *Miscelaneo*, and notarial testaments,
each marked as original or period translation. The Royal Danish Library's
public-domain Guaman Poma, *Nueva corónica y buen gobierno*, page by page in
Spanish with Quechua and Aymara passages. The Tupinambá and Old Guaraní
treebanks ride the Universal Dependencies shelf.

## Reference shelf

Dictionaries as structured data rather than page images —
**{{ census.dictionary_entries_display }} entries** as of {{ census.as_of }}.
The classical and older-language lexica: Liddell-Scott-Jones, Lewis &amp;
Short, Bosworth-Toller, Monier-Williams, the Welsh GPC, Dillmann's Gǝʿǝz
lexicon, the Hebrew and Egyptian lexica, the Sino-Japanese character
dictionaries and rime books, and the Tibetan rack (the Mahāvyutpatti, the
Verbs Database, the Monlam headwords). The etymological witnesses:
Wiktionary-derived lexica and reconstruction dictionaries with descendant
trees, IE-CoR, LIV, de Vaan's Latin, DÉRom's Proto-Romance, and the StarLing
/ Tower of Babel databases (by written grant, each compiler credited).
Further: three Slovenian historical dictionaries, Brückner's Polish and
Nasovič's Belarusian, and the typological databases CLICS and WOLD.
Dictionary citations resolve to live passages where the cited work is held:
the LSJ entry for μῆνις points at *Iliad* 1.1.

## The local shelves

The library's {{ census.local_shelves }} local shelves hold material that is
authored, acquired or computed rather than downloaded: per-language dossiers
feeding the `nabu language` cards; the owner's own PDFs, scans and offprints,
filed as page-cited collections through `nabu ingest` (see
[Tools]({{ '/tools/' | relative_url }})) and never served or redistributed; a
curated description of every registered source; the owner's notes on any
citable URN through `nabu note`; and the raw output of the local
lemmatization campaigns, from which the silver lemma tier is projected.
Their contents and counts are deliberately absent from this site.
