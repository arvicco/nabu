---
title: Tools
permalink: /tools/
description: >-
  The command-line instruments of the Nabu library, organized by scholarly
  task: search, citation, alignment, lexicography, etymology, and intertext.
---

Nabu is operated from the command line (`bin/nabu`), and the same
capabilities are exposed to AI clients through a read-only
[MCP server](https://github.com/arvicco/nabu/blob/main/docs/mcp.md). The
commands below are grouped by scholarly task; every example is a real
command with output pasted from live runs of 11–12 July 2026 (trims marked
with …).

## Finding text

**Full-text search** (`nabu search QUERY`) runs over the whole corpus with
per-language orthographic folding: unaccented μηνιν finds μῆνιν; *iuvenis*,
*juvenis*, and *iuuenis* all resolve; Old English æ/þ/ð and cuneiform
determinatives are handled analogously. Results can be filtered by
language, license class, and — where documents are dated and placed — by
historical year and provenance:

```
$ bin/nabu search 'στρατηγ*' --from 101 --to 300 --place oxyrhynch%
```

finds the strategoi of the Oxyrhynchite nome in the papyri of the second
and third centuries. The chronological axis covers 61,670 dated and placed
documents as of 13 July 2026, growing to 83,233 at the next index rebuild.

**Lemma search** (`search --lemma FORM`) queries by dictionary form rather
than surface string, over 2,619,049 gold lemma annotations in fourteen
languages — inflection and suppletion included:

```
$ bin/nabu search --lemma λέγω --limit 3
urn:nabu:proiel:chron:108755 [grc]  λέγω → ῥηθέντος  (lay)
  ὅ περ ἦν καὶ αἴτιον τοῦ μὴ ἐλθεῖν τὸν γενήσαντά με εἰς τὸν Μορέαν μετὰ τοῦ αὐθεντοπούλου κὺρ Θωμᾶ εἰ…
urn:nabu:proiel:chron:121080 [grc]  λέγω → εἶπον, εἰπὲ  (lay)
  Πολλῶν οὖν λόγων δαπανηθέντων, τέλος ἐστάλησαν πρὸς τὸν ἄνθρωπον δύο τῶν κελλιωτῶν καὶ συντρόφων μου…
urn:nabu:proiel:chron:121083 [grc]  λέγω → εἴπω  (lay)
  Ἐγὼ δὲ νὰ ἀκούω παρὰ μὲν τῶν, ὅτι καλή ἐστι, παρὰ δὲ τῶν, ὅτι οὐ καλή, διὰ τὶ νὰ μηδὲν εἴπω·
3 hits (exact lemma match; text is pristine)
```

A morphology filter (`--morph case=gen,number=pl`, in Universal
Dependencies vocabulary) restricts hits to attestations with the stated
gold morphology.

**Proximity search** (`search A --near B --window N`) keeps only passages
where the second term occurs within *N* words of the first — collocation
probing in the tradition of the TLG interface, and composable with lemma
search:

```
$ bin/nabu search λόγος --near θεός --window 5 --lang grc
urn:nabu:ddbdp:p.oxy:8:1151:18   [θεοσ] ην ο [λογοσ].          ← a papyrus amulet…
urn:cts:…:tlg0031.tlg004…:1.1    …και [θεοσ] ην ο [λογοσ].     ← …quoting John 1:1
```

**Fragment search** (`search --fuzzy FRAGMENT`) matches a damaged-text
fragment anywhere inside a passage, mid-word included, typed straight off
the edition with its editorial brackets:

```
$ bin/nabu search --fuzzy ']ανδρα μοι εν['
urn:nabu:ddbdp:bgu:6:1470:ctr:6 [grc]
  μαρτυροι. [ανδρα μοι εν]νεπε μουσα πολυτρο
1 hit (fuzzy substring; highlights are diacritic-folded)
fuzzy index covers: oracc, papyri-ddbdp
```

— BGU 6.1470, a Hellenistic writing exercise breaking off mid-word through
the opening line of the *Odyssey*. The character-trigram index behind this
is scoped to the documentary shelves (papyri and cuneiform), where
fragment search earns its cost; until the production index is built the
command reports that plainly rather than degrading.

**Concordance** (`nabu concord QUERY`) prints classic keyword-in-context
lines, column-aligned in the pristine (accented) text and in corpus order —
for scanning usage rather than ranking relevance:

```
$ bin/nabu concord --lemma virtus --width 30
…vetii quoque reliquos Gallos virtute praecedunt, quod fere cotidi…  urn:nabu:proiel:caes-gal:52552 [lat]
…i populi Romani et pristinae virtutis Helvetiorum.                   urn:nabu:proiel:caes-gal:52635 [lat]
…b eam rem aut suae magnopere virtuti tribueret aut ipsos despicer…  urn:nabu:proiel:caes-gal:52636 [lat]
…
```

## Reading and citing

**Retrieval by citation** (`nabu show URN`) returns a passage, a whole
document, or a citation range, with license, revision, and the full
provenance trail. `--random` pulls something off a shelf; `--parallel`
pairs the aligned English translation, span-grouped and honest when the
translation's citation grain is coarser than the original:

```
$ bin/nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.5 --parallel
urn:cts:greekLit:tlg0012.tlg001.perseus-grc2 — Iliad [grc]
  parallel: urn:cts:greekLit:tlg0012.tlg001.perseus-eng4 — Iliad [eng]
  aligned by citation: 0 paired, 1 block covering 5 lines, 0 grc only, 0 eng only
  :1.1
    grc  μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος
  :1.2
    grc  οὐλομένην, ἣ μυρίʼ Ἀχαιοῖς ἄλγεʼ ἔθηκε,
  …
  eng [:1.1 — covers :1.1–:1.39; range shows :1.1–:1.5]
    Sing, O goddess, the anger [mênis] of Achilles son of Peleus, that brought
    countless ills upon the Achaeans. …
```

**Alignment** (`nabu align REF`) renders one citation across every witness
of a registered work — the parallel New Testament (up to thirteen
witnesses) and the Septuagint ↔ Vulgate ↔ English Old Testament ship as
flagships; a full example opens the [Home]({{ '/' | relative_url }}) page.

**Collation** (`align REF --collate`) turns the aligned witnesses into a
compact apparatus: a base reading with per-witness divergences, computed
per language-and-script group. Witnesses in a different script family are
rendered undiffed and labelled as such — the tool does not pretend that a
Cyrillic and a Latin-transliteration witness can be mechanically collated.

```
$ bin/nabu align "MARK 2.3" --collate --base zographensis
```

**Export** (`nabu export --format plain|jsonl`) streams the corpus out
with language and license filters — the exit format, so the collection is
never captive to its own tooling.

## The reference desk

**Dictionary lookup** (`nabu define LEMMA`) queries the reference shelf
(LSJ, Lewis &amp; Short, Bosworth-Toller, and the reconstruction
dictionaries), with the entry's citations resolved to live passages in the
local catalog:

```
$ bin/nabu define μῆνις
μῆνις — A Greek-English Lexicon (Liddell-Scott-Jones) [attribution]  urn:nabu:dict:lsj:n67485
  gloss: wrath

μῆνις, Dor. and Aeol. μᾶν-, ἡ, gen.
A. μήνιος Pl. R. 390e , later μήνιδος Ael. Fr. 80 , … —wrath; from Hom.
downwds. freq. of the wrath of the gods, Il. 5.34 , al., A. Ag. 701 (lyr.),
… but also, generally, of the wrath of Achilles, Il. 1.1 , al. …

resolved citations (in this corpus — nabu show <urn>):
  Il. 1.1 → urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
  Il. 5.34 → urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:5.34
  A. Ag. 701 → urn:cts:greekLit:tlg0085.tlg005.1st1K-grc1:701
  …
```

**Etymology** (`nabu etym LEMMA`) walks an attested lemma to the
reconstructions that name it among their descendants, then one hop up the
proto-to-proto chain, each stage listing cognates with corpus attestation
counts. Plain-ASCII input is accepted for reconstructed forms:

```
$ bin/nabu etym богъ --lang chu
богъ [chu] → *bogъ [sla-pro] — gloss: god
← *bʰeh₂g- [ine-pro] — gloss: to divide, distribute, allot
  reflexes: [grc] ἔφᾰγον, [sa] भक्ष (bhakṣá), …
```

**Cognates in parallel** (`nabu cognates TARGET`) crosses the etymological
crosswalk with the alignment hub: verses of an aligned work where witnesses
in two or more languages use reflexes of the same reconstructed root, found
without any surface-form resemblance:

```
$ bin/nabu cognates "LUKE 14.34" --langs got,chu
LUKE 14.34  *sḗh₂l [ine-pro · attribution]
    chu  соль — attested as солъ
    got  salt
```

The whole Gothic × Old Church Slavonic New Testament yields roughly 300
such verses across 30 roots in under a second; each hit names the
dictionary shelf on which the languages meet, so a Proto-Germanic meet for
a Slavic word is flagged as a likely borrowing rather than common descent.

## The corpus reads itself

**Intertext** (`nabu parallels URN`) is passage-anchored quotation and echo
discovery: point at one passage and find where the corpus quotes or reworks
it, ranked by shared rare phrases, with elision folded across editions (so
Matthew 4:4 finds Septuagint Deuteronomy 8:3). Gold-lemmatized anchors also
surface re-inflected allusions through rare lemmas.

```
$ bin/nabu parallels urn:nabu:sblgnt:matt:4.4
```

**Formula mining** (`nabu formulas SCOPE`) points the same machinery inward:
the repeated formulas within a corpus slice, ranked by count and length —
Homer's ὣς ἔφαθ᾽ οἵ δ᾽ (72 occurrences), the *Beowulf maþelode bearn
Ecgþeowes* speech formula, the Old English riddle refrain *saga hwæt ic
hatte*.

```
$ bin/nabu formulas aspr --min-count 5
```

**The links graph** (`nabu links URN`) reads back the mined cross-reference
graph: every batch-produced edge touching a URN — parallels, formulas,
cognates — with its evidence and a provenance footer naming the producing
run. Edges live in their own journal database and survive catalog rebuilds.

## Profiling

**Vocabulary profiling** (`nabu vocab URN`) computes a lemma-frequency
profile of a document or range against the gold-lemma corpus: distinctive
vocabulary by log-odds (Caesar surfaces *legio* and *proelium*; Cicero's
*De officiis* surfaces *officium*, *honestas*, *decorum*) and the
in-document hapax legomena. With `--by-century` it plots the shape of the
dated corpus, or one word's fortunes, across historical centuries:

```
$ bin/nabu vocab --by-century 'στρατηγ*' --lang grc
```

peaks in the second century CE.

## Stewardship

The remaining commands keep the collection alive: `nabu sync` fetches and
loads a source (idempotent and non-destructive, with every run recorded);
`nabu status` and `nabu health` report per-source counts, run history, and
upstream drift; `nabu verify` re-parses every canonical file and compares
content hashes against the catalog; `nabu rebuild` regenerates the entire
database from canonical data, proven byte-identical by test; and
`nabu backup` copies everything non-derivable to external storage, with a
rehearsed restore drill. These are documented in the repository's
[operations runbook](https://github.com/arvicco/nabu/blob/main/docs/ops.md).
