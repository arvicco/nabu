---
title: Examples
permalink: /examples/
description: >-
  Worked examples of the Nabu library in use, by discipline: classics,
  papyrology, Slavic philology, comparative linguistics, Assyriology,
  sinology, medieval Latin, Old English, and biblical studies.
---

{% assign census = site.data.census -%}
Worked walk-throughs, one per discipline, using real commands and output
from live runs between July and September 2026 (each section notes its
date where it matters). Nothing below is a mock-up; trims are marked
with ellipses. Each discipline is also a **research desk** — one of the
{{ census.desks }} [research axes]({{ '/axis/' | relative_url }}), where that
desk's shelves, instruments, CLI recipes and terminal setup live on one page.

## For the classicist

*The [Classical desk]({{ '/axis/classical/' | relative_url }}).*

The Perseus Greek and Latin canons and First1KGreek put 2,209 Greek and
Latin editions on the desk, 872 of them with aligned English translations —
`show <urn> --parallel` pairs Vergil or Homer line by line (an example
appears on the [Tools]({{ '/tools/' | relative_url }}) page). Proximity
search supports collocation questions in the manner of the TLG interface,
and is aware of lemmas, so suppletive paradigms do not escape it. A simple
example — where does λόγος stand within five words of θεός?

```
$ bin/nabu search λόγος --near θεός --window 5 --lang grc
urn:nabu:ddbdp:p.oxy:8:1151:18   [θεοσ] ην ο [λογοσ].          ← a papyrus amulet…
urn:cts:…:tlg0031.tlg004…:1.1    …και [θεοσ] ην ο [λογοσ].     ← …quoting John 1:1
```

The first hit is not a literary text at all: it is a Christian amulet from
Oxyrhynchus quoting the opening of John — the kind of cross-shelf find
(papyri beside literature in a single index) that motivated the library's
design.

## For the Latinist, across a millennium and three tiers

*The [Classical]({{ '/axis/classical/' | relative_url }}) and
[Romance]({{ '/axis/romance/' | relative_url }}) desks — live run of
3 September 2026.*

Latin in this library runs from archaic dedications to Migne's
Patrologia, and lemma search answers across all of it — with every
annotation honestly labelled by *who made it*. One dictionary form, three
tiers in three hits:

```
$ bin/nabu search --lemma gratia --lang lat --limit 3
urn:nabu:ceipom:88:97 [lat] [equivalence]  gratia → gratia  (Favor which one finds with others)
  Orcevia Numeri [uxor] / nationu(s) gratia / Fortuna Diovo fileia / Primogenia / donom dedi
urn:nabu:corph:0016:S0016-2 [lat]  gratia → gratias  (Favor which one finds with others)
  Finit amen deo gratias ago oroit do dimmu . , . .
urn:nabu:digiliblt:dlt000003:116 [lat] [silver]  gratia → gratia  (Favor which one finds with others)
  gratia et bonae et malae rei causa;
3 hits (exact lemma match; text is pristine) — 1 silver (automatic lemmatization; --gold-only excludes) — 1 equivalence (scholar-curated Classical-Latin equivalents; --gold-only excludes)
```

An archaic Praeneste dedication answering through a scholar-curated
`[equivalence]`, an Insular colophon on gold annotation, a late-antique
grammarian through machine (`[silver]`) lemmatization — and the summary
line tells you exactly which is which. `--gold-only` restricts to the
human-verified tier; the tier system itself ({{ census.gold_lemmas_m }}M
gold, {{ census.silver_lemmas_m }}M labelled silver annotations) is
written up in
[lemma enrichment](https://github.com/arvicco/nabu/blob/main/docs/lemma-enrichment.md).

Historical *stages* are a filter of their own — `--lect lat:med` keeps
only shelves resolving to Medieval Latin, so a formula query stays inside
its period:

```
$ bin/nabu search misericordia --lect lat:med --limit 2
urn:nabu:corpus-corporum:8706:d15.p1 [lat]
  …mino quoniam bonus: quoniam in aeternum [misericordia] ejus. Confitemini Deo deorum: quoniam i…
urn:nabu:corpus-corporum:9349:d142.p1 [lat]
  …mino quoniam bonus, quoniam in aeternum [misericordia] ejus. Confitemini Deo deorum, quoniam i…
```

## For the papyrologist

*The [Epigraphy desk]({{ '/axis/epigraphy/' | relative_url }}) — papyri, stones and sherds.*

The library holds 61,414 documents of the Duke Databank of Documentary
Papyri, with the Leiden editorial conventions preserved. Fragment search is
built for damaged texts: type the line as the edition prints it, brackets
and all, and the trigram index matches it inside words:

```
$ bin/nabu search --fuzzy ']ανδρα μοι εν['
urn:nabu:ddbdp:bgu:6:1470:ctr:6 [grc]
  μαρτυροι. [ανδρα μοι εν]νεπε μουσα πολυτρο
1 hit (fuzzy substring; highlights are diacritic-folded)
fuzzy index covers: oracc, papyri-ddbdp
```

— BGU 6.1470, a Hellenistic writing exercise that breaks off mid-word
through the *Odyssey*'s opening line (…Μοῦσα πολύτρο[πον). Since the papyri
carry HGV dating and provenance, chronological and geographic filters
compose with any search: `search 'στρατηγ*' --from 101 --to 300 --place
oxyrhynch%` scopes to the Oxyrhynchite strategoi of the second and third
centuries.

## For the sinologist

*The [Sinitic desk]({{ '/axis/sinitic/' | relative_url }}) — live run of
3 September 2026.*

Classical Chinese writes without word boundaries, which defeats ordinary
full-text engines; since September 2026 the library maintains a dedicated
character-pair index over the Sinitic, Korean and Japanese shelves, so a
Han query is exact, fast, and never depends on guessed segmentation. The
six dragons of the *Yijing*'s first hexagram, across three corpora in one
query:

```
$ bin/nabu search 六龍 --limit 3
urn:nabu:classical-modern:汉书:志:礼乐志:298 [lzh]
  吾知所乐，独乐[六龙]，六龙之调，使我心若。
urn:nabu:cbeta:X37n0675:0802a05 [lzh]
  槃如晝夕窹，遠離夢想也。倒正如[六龍]舞，以六龍
urn:nabu:cbeta:X86n1600:0170a04 [lzh]
  乘[六龍]以御天。知時之乘六龍，則知一句之具三
3 hits (snippet shows the text as stored; matching is fold-aware)
```

— the *Book of Han*'s music treatise (in simplified-character
transmission, found by the same fold-aware query) beside two Buddhist
commentaries quoting the *Yijing* line 乘六龍以御天, "riding the six
dragons to drive across the sky." The character itself then goes on the
desk — one card from modern readings back to Old Chinese:

```
$ bin/nabu char 龍
龍  U+9F8D  ·  16 strokes  ·  radical 212 龍 dragon
…
readings (ja, KANJIDIC2):
  on: リュウ、リョウ、ロウ
  kun: たつ、いせ
…
readings (sinoxenic, Unihan):
  Mandarin: lóng
  Korean (hangul): 룡:0E 용:0
  Vietnamese: long
…
Old Chinese (Baxter-Sagart):
  [baxter-sagart-oc] dragon
    OC: *[mə]-roŋ
    MC: ljowng (l- + -jowng A)
    pinyin: lóng
…
```

## For the slavist

*The [Slavic desk]({{ '/axis/slavic/' | relative_url }}).*

The Old Church Slavonic canon is held complete across its editions:
Marianus, Zographensis, Assemanianus, Savvina kniga, and Suprasliensis
(folio-line cited, with hyphen-split words searchable whole), beside Old
East Slavic from birchbark letters to Ruthenian chancery texts, and the
~1000 CE Freising Manuscripts in three aligned transcription layers. The
gospel codices join the New Testament alignment hub, so
`align REF --collate` turns the witnesses into a working apparatus — a
raw-token diff per script family, with the four Helsinki-transliteration
codices collated against each other and the Cyrillic witnesses set beside
them, honestly uncollated, because a mechanical fold cannot bridge the two
transcription systems. One verse across the tradition:

```
$ bin/nabu align "MARK 2.3"
…
marianus — Codex Marianus [chu]   license: nc
  urn:nabu:proiel:marianus:36421
    Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми.
…
```

## For the comparativist

*The [Etymology desk]({{ '/axis/etym/' | relative_url }}).*

The reconstruction shelf walks attested words to their proto-forms and
cognates, with corpus attestation counts at every step:

```
$ bin/nabu etym богъ --lang chu
богъ [chu] → *bogъ [sla-pro] — gloss: god
← *bʰeh₂g- [ine-pro] — gloss: to divide, distribute, allot
  reflexes: [grc] ἔφᾰγον, [sa] भक्ष (bhakṣá), …
```

Pure-ASCII input works for reconstructed forms (`etym bhewgh`). The
`cognates` command then crosses this crosswalk with the alignment hub:
verses where the witnesses use reflexes of the same root, found without any
surface resemblance —

```
$ bin/nabu cognates "LUKE 14.34" --langs got,chu
LUKE 14.34  *sḗh₂l [ine-pro · attribution]
    chu  соль — attested as солъ
    got  salt
```

The whole Gothic × OCS New Testament yields roughly 300 such verses across
30 roots in under a second (*hlaifs* ~ хлѣбъ, *malan* ~ млѣти, *menoþs* ~
мѣсѧць), and each hit is labelled with the dictionary shelf on which the
two languages meet — a Proto-Germanic meet for a Slavic word reads as a
likely borrowing, not common descent.

## For the Old English scholar

*The [Germanic desk]({{ '/axis/germanic/' | relative_url }}) — live run
of 3 September 2026.*

The Anglo-Saxon Poetic Records sit beside the prose, the Bosworth-Toller
dictionary, and the runic and continental Germanic shelves. The formula
miner reads oral-formulaic poetry the way its scholarship does — by
finding the repeated building blocks and counting them:

```
$ bin/nabu formulas aspr --min-count 5
formulas in aspr — 30550 passages / 175736 tokens
13×  ic waes ond mid
     e.g. urn:nabu:aspr:A3.11:59, urn:nabu:aspr:A3.11:60, urn:nabu:aspr:A3.11:61
12×  ond thaet word acwaeth
     e.g. urn:nabu:aspr:A2.6:1071, urn:nabu:aspr:A3.1:316, urn:nabu:aspr:A3.1:474
12×  saga hwaet ic hatte
     e.g. urn:nabu:aspr:A3.22.3:72, urn:nabu:aspr:A3.22.8:8, urn:nabu:aspr:A3.22.10:11
…
```

*Saga hwæt ic hatte* — "say what I am called" — is the Exeter Book
riddles' closing refrain, surfacing here with the exact riddles that use
it; the speech formulas (*ond þæt word acwæð*) rank right beside it. The
Germanic ladder is also growing downward in time: the Deutsches
Textarchiv adapter (the German print corpus, 1473–1969) is built and
awaiting its first sync.

## For the assyriologist

*The [Cuneiform desk]({{ '/axis/cuneiform/' | relative_url }}).*

The cuneiform shelf now holds 104,722 ORACC documents (CC0) across 38
projects — the complete State Archives of Assyria, the ePSD2 corpora with
the Ur III administrative mass, the Achaemenid trilinguals — with upstream
gold lemmatization feeding `search --lemma` for Akkadian and Sumerian.
Beside it sit the CDLI's 353,156 catalogued artifacts (135,201 of them
transliterated: proto-cuneiform and proto-Elamite's only machine-readable
home), the eBL Fragmentarium's 23,288 fragments with inline English, and
the Sumerian literary canon in two scholarly editions (ETCSL beside
ePSD2, deliberately unmerged, meeting at reference edges — all
synchronized 19 July 2026). A state letter reads with its facing English,
line-anchored:

```
$ bin/nabu show urn:nabu:oracc:saao-saa01:P224395:o.1-o.3 --parallel
:o.1  akk  a-na LUGAL EN-ia
:o.2  akk  ARAD-ka {1}10-ha-ti
…     eng  To the king, my lord: Your servant Adda-hati. …
```

And the shelf rewards browsing:

```
$ bin/nabu show --random --source oracc
urn:nabu:oracc:rinap-rinap1:Q003443:1 [akk]
  a-di {KUR}sa-u₂-e KUR-e ša ina {KUR}lab-na-na-ma it-tak-ki-pu-u₂-ni
  document: urn:nabu:oracc:rinap-rinap1:Q003443 — Tiglath-pileser III 30
  source: oracc   license: open   sequence: 0   revision: 1
```

— a royal inscription of Tiglath-pileser III, "as far as Mount Saue, which
abuts Lebanon."

## For the hittitologist

*The [Hittite desk]({{ '/axis/hittite/' | relative_url }}).*

TLHdig (Hethitologie-Portal Mainz) brings >98% of the published Hittite
tablet fragments: 23,486 manuscripts in 663 CTH compositions, each line
carrying transliteration, Unicode cuneiform, and upstream's candidate
morphological analyses — served at an honest silver tier (only
upstream-disambiguated analyses mint searchable lemmas; the rest ride as
annotations). The UD HitTB treebank adds 1,309 gold-lemmatized words from
Hoffner & Melchert's grammar, and the Anatolian reflex columns of the
comparative shelf light against the corpus:

```
$ bin/nabu search --lemma ḫūmant --lang hit     # "all/every" across the corpus
urn:nabu:tlhdig:101:tlh:kub.21.9:7 [hit] [silver]  ḫumant → ḫu-u-ma-an-da
  e-e]p-ta KUR.KUR°ḪI.A°-ia-ši ḫu-u-ma-an-da za-aḫ-ḫ[e-er]
…

$ bin/nabu etym water                           # the textbook heteroclite, now corpus-attested
  ← *wódr̥ [ine-pro] — Wiktionary — Proto-Indo-European …
  [hit] 𒉿𒀀𒋻 (wātar) — silver 704 passages
```

Both runs are pasted live (19 July 2026, trimmed lines marked).

## For the biblical scholar

*The [Biblical desk]({{ '/axis/biblical/' | relative_url }}) — one text across every witness language.*

The New Testament is held in up to fifteen registered witnesses — two
Greek editions, two Latin, Gothic, Classical Armenian, five Old Church
Slavonic manuscript editions, Old English, English, and (since 13 July
2026) Sahidic and Bohairic Coptic — and one command renders any verse
across all of them, each row carrying its license label (the run below
predates the two Coptic witnesses; the full output opens the
[Home]({{ '/' | relative_url }}) page):

```
$ bin/nabu align "MARK 2.3"
MARK 2.3 — New Testament (parallel witnesses)
  13 of 13 witnesses attest this ref
…
```

The Old Testament axis grew its Hebrew legs on 18 July 2026: `align
"GEN 1.1"` now renders the Masoretic text (byte-verbatim Leningrad Codex,
twice — OSHB and the ETCBC's BHSA) beside the Septuagint, the Vulgate,
the English, and Targum Onkelos's Aramaic — six witnesses per verse, with
the Greek/Hebrew Psalm numbering divergence mapped rather than hidden:
`align "PSA 22.1"` shows the Hebrew witnesses' 23.1, labelled as such.
Dictionary lookups close the loop — the LSJ entry for μῆνις resolves its
citations to live passages in the catalog (see
[Tools]({{ '/tools/' | relative_url }})).

## For the egyptologist

*The [Egyptian desk]({{ '/axis/egyptian/' | relative_url }}).*

Three millennia of Egyptian arrived on 18 July 2026 as one axis: the
TLA/BBAW sentence corpus with gold lemmatization, its dictionary keyed by
the same lemma ids, the only bulk demotic dataset in existence, and the
Coptic lexicon with a crosswalk that walks a word across the whole span.

```
$ bin/nabu show urn:nabu:aes:sawlit:BRMYDZFU3BFT7JLX45UAGVMKMI --parallel ger
  :IBUBd5wLLFaLn06ZvzVW4ePuFIg
    egy  šms,w Zꜣ-nh,t ḏd =f
    ger  Der Gefolgsmann Sinuhe, er sagt:
…
$ bin/nabu search --lemma nfr          # every inflection, glossed
$ bin/nabu show urn:nabu:dict:aed:tla866216   # the root nfr and its 56 derivatives
$ bin/nabu links urn:nabu:dict:ccl:C1494      # ⲕⲁϩ ← qꜣḥ ← qh, 3,000 years
```

## For the student of pre-Roman Italy

*The [Italic desk]({{ '/axis/italic/' | relative_url }}).*

Seven fragmentary languages landed 18 July 2026, most in their only
machine-readable form: the oldest Latin in existence, the complete
Iguvine Tables in Umbrian, Etruscan with a scholarly glossary, Oscan in
Greek script from Messina, and the Alpine corpora of Lepontic and Raetic.

```
$ bin/nabu show urn:nabu:ceipom:2:2
  Manios med fhefhaked Numasioi         # the Fibula Praenestina, 7th c. BCE
$ bin/nabu show urn:nabu:ceipom:995     # the Iguvine Tables, all 688 sentences
$ bin/nabu define avil                  # Etruscan "year" (ETP glossary)
$ bin/nabu etym pompeii
  Pompeii [lat] (loan) → *pompe [osc] ← *kʷenkʷe [itc-pro] "five"
```

## For the Hebraist

*The [Hebrew desk]({{ '/axis/hebrew/' | relative_url }}) — and its [terminal setup]({{ '/axis/hebrew/' | relative_url }}#terminal-setup) for right-to-left reading.*

The Masoretic text is held byte-verbatim — the Leningrad Codex's
combining-mark order is never normalized away — with full morphology,
ketiv/qere both preserved, and the verse-aligned Aramaic of the Targums
beside it. The ETCBC's BHSA adds clause-level syntax, the Dead Sea
Scrolls (Abegg's transcriptions, 1,001 scrolls) sit beside the codices,
and the augmented-Strong's lexicon resolves every OSHB lemma to its BDB
entry — all live since 19 July 2026.

```
$ bin/nabu show urn:nabu:oshb:gen:1.1
  בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים …
$ bin/nabu align "GEN 1.1"              # seven witnesses: MT ×2, LXX, Vulgate, English, Onkelos, Peshitta
```

A note on scope: the library today serves the Hebrew Bible and Second
Temple corpora. Rabbinic literature proper — Mishnah, Talmud, midrash —
is a planned campaign of its own; the Targum shelf and the Jastrow
dictionary scans are its first bridgeheads.

## For the southeast asianist

*The [Southeast Asia desk]({{ '/axis/sea/' | relative_url }}) — the
newest desk (September 2026); live run of 3 September 2026.*

The Indic cosmopolis at its eastern edge: the DHARMA project's Old Khmer,
Cham, Old Javanese, Pyu and Nusantara epigraphy, the Bagan inscriptions
of Old Burmese, and the Old Javanese Wordnet as the desk's glossary. The
shelf rewards a blind draw — every record carries its edition credit and
resolved language stage:

```
$ bin/nabu show --random --source dharma-khmer
urn:nabu:dharma-khmer:INSCIK00299-24:1 [okz-Latn]
  .kṣuradhāraparvvata . qnak· ta lvac· tamrya qseḥ yāna . pāduka . cap· ta vrāhmaṇa nu jeṅ(·) …
  document: urn:nabu:dharma-khmer:INSCIK00299-24 — K. 299-24. Eastern section of southern gallery of Angkor Wat (the hell and heaven gallery), 12th century
  source: dharma-khmer   license: attribution   sequence: 0   revision: 1
  credit: DHARMA — Corpus des inscriptions khmères (the Cœdès K-numbers) (ERC no. 809994, EFEO/CNRS; erc-dharma on GitHub). Cite the corpus and its editors wherever used.
  lect: okz~latn (codemap)
…
```

— the hell-and-heaven gallery of Angkor Wat, naming the razor-edged
mountain Kṣuradhāraparvata and the sinners it awaits: elephant thieves,
horse thieves, and those who show contempt for brahmins and pandits.

## Searching by meaning

*Built September 2026; the vector store's first overnight build is
scheduled.*

The newest search layer answers a question no word index can: *where
else does the library say this?* — same thought, different words.
`search --similar <urn>` anchors on any passage of the literary core and
returns its nearest same-language neighbors — another edition's copy of
the same line, a quotation drifted by memory, a paraphrase — ranked and
banded *close / near / loose*, with the embedding model named on every
page so a statistical match is never mistaken for a curated alignment.
The same lane serves AI conversation through the MCP server's
`similar_to` parameter. It runs on a local vector store the owner builds
once with `nabu embed` and tops up incrementally after every sync; no
text ever leaves the machine. The plain-language write-up is
[embed.md](https://github.com/arvicco/nabu/blob/main/docs/embed.md) — and
this page will gain the live walk-through once the first build lands
(nothing here is ever pasted from imagination).

## Composing the layers

*Added August 2026, live runs of 12 August — the place, script, sign, and
dating layers answering one question together.*

The library's layers — places as identities, writing systems, sign
readings, dates — long had desks of their own; since August 2026 they
compose in search. Ask for a common word at one findspot, by identity
rather than spelling, and get the same page every time (`--scan` walks
the filtered documents in corpus order — deterministic, never sampled):

```
$ bin/nabu search lugal --place Girsu --scan --limit 5
urn:nabu:oracc:dcclt:P217451:f.1 [sux]
  {d}nisaba [lugal]-ušumgal dub-sar ensi₂ lagaš{ki}
urn:nabu:oracc:epsd2-admin-ur3:P100144:o.1 [sux]
  3(aš) 4(barig) še gur [lugal]
…
5 hits (… corpus-order scan of the filtered set (--scan))
note: place: "Girsu" → cigs:GIR = pleiades:912855 = cdli-provenience:88 = geonames:93976 (identity refs + name match)
```

The note is the point: "Girsu" resolved to the place's *identities*
across four gazetteers (the crosswalk the [Places]({{ '/places/' |
relative_url }}) page describes), so tablets citing any of those refs —
in any spelling — answer, alongside plain name matches. The place card
shows the same equivalences:

```
$ bin/nabu place cigs:GIR
Girsu, cigs:GIR — 31.56, 46.18
  = cdli-provenience:88 = geonames:93976 = pleiades:912855
  axis holdings (place_ref — adapter-asserted + registry decisions): 19226 oracc
```

A cuneiform sign searches as itself — its reading values expand into one
query, and each hit brackets the value it matched:

```
$ bin/nabu search --sign 𒊬 --lang sux --limit 3
sign: 𒊬  SAR — 26 reading values: e₁₄ kiri₆ ma₄ mu₂ mud₆ … and 14 more
urn:nabu:etcsl:0.2.06:31 [sux]
  cubur-e cu [mu2]
```

Writing systems are a search cut (`--script ogam` for the Ogham stones,
`--script grek` for Greek-alphabet Gaulish), and so is geography —
`--within 59.86,17.64,30` walks the runestones raised within 30 km of
Uppsala. Every one of these composes with the date window, genre facets,
license classes, and lect filters above.

## If your field is not here

These walk-throughs sample the disciplines the library serves; they are not
the whole of it. The desk index at [Research axes]({{ '/axis/' | relative_url }})
covers all {{ census.desks }} — the Indologist, the Koreanist and the
Tibetologist among those with no walk-through above — each with its own
member shelves, instruments and CLI recipes.
