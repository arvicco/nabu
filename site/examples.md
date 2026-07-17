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

The cuneiform shelf holds 21,692 ORACC documents (CC0) across 33 projects,
including the complete State Archives of Assyria, with upstream gold
lemmatization feeding `search --lemma` for Akkadian and Sumerian, and 8,911
aligned English translations. A state letter reads with its facing English,
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

The Old Testament runs on the Septuagint ↔ Vulgate ↔ English axis, with the
Greek/Hebrew Psalm numbering divergence mapped rather than hidden:
`align "PSA 22.1"` shows the World English Bible's 23.1, labelled as such.
Dictionary lookups close the loop — the LSJ entry for μῆνις resolves its
citations to live passages in the catalog (see
[Tools]({{ '/tools/' | relative_url }})).
