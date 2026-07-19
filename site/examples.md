---
title: Examples
permalink: /examples/
description: >-
  Worked examples of the Nabu library in use, by discipline: classics,
  papyrology, Slavic philology, comparative linguistics, Assyriology, and
  biblical studies.
---

Six short walk-throughs, one per discipline, using real commands and output
from live runs of 11–12 July 2026. Nothing below is a mock-up; trims are
marked with ellipses.

## For the classicist

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

## For the papyrologist

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

## For the slavist

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

## For the assyriologist

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
