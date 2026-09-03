---
title: Tools
permalink: /tools/
description: >-
  The instruments of the Nabu library, organized by scholarly task:
  word search, lemma and semantic search, citation, alignment,
  lexicography, etymology, intertext — and the same capabilities in
  conversation through the built-in MCP server.
---

{% assign census = site.data.census -%}
Nabu is operated from the command line (`bin/nabu`), and everything the
command line can do for a reader, a connected AI assistant can do in
conversation through the built-in read-only MCP server — see
[Ask your model](#ask-your-model) below. The commands are grouped by
scholarly task; every pasted example is a real command with output from
live runs (trims marked with …).

## Finding text

**Full-text search** (`nabu search QUERY`) runs over the whole corpus
({{ census.passages_display }} passages, {{ census.as_of }}) with
per-language orthographic folding: unaccented μηνιν finds μῆνιν; *iuvenis*,
*juvenis*, and *iuuenis* all resolve; Old English æ/þ/ð and cuneiform
determinatives are handled analogously. Results can be filtered by
language, license class, and — where documents are dated and placed — by
historical year and provenance:

```
$ bin/nabu search 'στρατηγ*' --from 101 --to 300 --place oxyrhynch%
```

finds the strategoi of the Oxyrhynchite nome in the papyri of the second
and third centuries. The chronological axis covers 688,562 dated and
placed documents as of 4 August 2026 — the CDLI tablets, Italy's EDR
(115,590), the Heidelberg inscriptions and the papyri foremost among
them. On the faceted shelves
(currently the inscriptions), genre facets compose with the same filters:

```
$ bin/nabu search manibus --type epitaph --province Britannia
```

draws on 256,518 facet rows recording inscription genre, province,
material, and object type, with uncertain upstream attributions preserved
as such.

**Chinese, Japanese and Korean text** searches first-class (September
2026): the classical Sinitic shelves — the Chinese canons, the Korean
state records, the Japanese library — write without word boundaries, so
the library maintains a dedicated character-pair index over those
shelves (fifteen sources). A query in Han characters or kana
(`nabu search 六龍`) matches exact character sequences at full speed,
composing with every filter below; no segmentation is guessed, ever.

**Stage-aware search** (`search --lect LECT-ID`, August 2026, with the
optional [nabu-lects](https://arvicco.github.io/nabu-lects) registry
synced) filters hits by *historical stage* rather than bare code:
`--lect lat:med` keeps only collections resolving to Medieval Latin,
`--lect lat` matches every Latin stage — prefix semantics over the
registry's `anchor[:stage][/variety][~script][@ortho]` grammar, with stored
codes never touched. See the [Languages]({{ '/languages/' | relative_url }})
page for the lect layer.

**Place-identity search** (`search --place NAME|ns:id`, August 2026): the
provenance filter understands place *identities*, not just spellings. A
namespaced ref (`--place cigs:GIR`, `--place pleiades:912855`) matches
every document whose place claim cites that identity in any spelling —
upstream URL or namespaced mint alike — and a plain name resolves through
the held gazetteers and the [nabu-places](https://arvicco.github.io/nabu-places)
registry's decisions, crosswalk equivalences included, while still
matching verbatim name fields. The page names the lane that answered:

```
$ bin/nabu search lugal --place Girsu --scan --limit 5
…
note: place: "Girsu" → cigs:GIR = pleiades:912855 = cdli-provenience:88 = geonames:93976 (identity refs + name match)
```

`--scan` there is the **filter-first mode** (August 2026): where plain
search asks "where does this term rank corpus-wide?" — and answers with a
corpus-wide sample when the term is too common to rank — `--scan` asks
"which of *these* documents carry the term?", walking the matches in
corpus order intersected with the active filters: deterministic, never
sampled, built for a common word under a selective filter.

**Script search** (`search --script TAG`, August 2026) cuts by writing
system: the held text's script axis or the artifact's original system
where the two differ. `--script ogam` walks the Ogham stones, `--script
grek` finds Greek-alphabet Gaulish:

```
$ bin/nabu search --script grek --limit 3
urn:nabu:riig:ahp-01-01:HRD-a:1 [xtg-Grek]
  καρε[…]μ
```

**Sign search** (`search --sign GLYPH|NAME`, August 2026) is the inverse
of the [sign desk](#the-reference-desk): one cuneiform sign
expands into an OR over its OSL reading values, each hit bracketing the
value that matched:

```
$ bin/nabu search --sign 𒊬 --lang sux --limit 3
sign: 𒊬  SAR — 26 reading values: e₁₄ kiri₆ ma₄ mu₂ mud₆ … and 14 more
urn:nabu:etcsl:0.2.06:31 [sux]
  cubur-e cu [mu2]
```

**Geo-radius search** (`search --within LAT,LON,KM`, August 2026) keeps
documents whose recorded find-location falls inside a radius —
`--within 59.86,17.64,30` walks the runestones raised within 30 km of
Uppsala. All of these compose with each other and with the date, genre,
license, and lect filters.

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
is scoped to the documentary shelves, where fragment search earns its
cost; the scope has grown in waves — the Heidelberg inscriptions joined
13 July 2026, Italy's EDR and the Elephantine archives 28 July 2026 —
and the production index covers 3,801,508 passages across the papyri,
cuneiform, and inscription shelves as of 28 July 2026.

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

**The attic** (`search --withdrawn TERM`, September 2026) searches what
the library no longer serves: passages upstream revised away and
documents upstream withdrew, each hit labelled with *why* it was
withdrawn (an upstream deletion, a revision that pruned it). The
catalog never hard-deletes — text that once entered the library remains
findable, honestly marked, in its own view.

## Words and meanings

Above the letter-for-letter layer sit two ways of searching by what a
word *is* rather than how it is spelled.

**Lemma search** (`search --lemma FORM`) queries by dictionary form
rather than surface string — inflection and suppletion included, so one
query finds a Latin noun in all its cases or a Greek verb across its
stems:

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

The coverage comes in two honestly separated tiers:
**{{ census.gold_lemmas_m }} million gold annotations** in
{{ census.gold_languages }} languages — human-verified, from the
treebanks — and **{{ census.silver_lemmas_m }} million silver
annotations** in {{ census.silver_languages }} languages, proposed by
machines and *labelled* `[silver]` wherever they surface; `--gold-only`
restricts any lemma query to the human-verified tier, and a machine
guess is never blended into a gold count. The silver tier is grown by
the library's own local lemmatization campaigns — the how and the
honesty rules are written up in
[lemma enrichment](https://github.com/arvicco/nabu/blob/main/docs/lemma-enrichment.md).
A morphology filter (`--morph case=gen,number=pl`, in Universal
Dependencies vocabulary) restricts hits to attestations with the stated
gold morphology.

**Semantic search** (`search --similar URN`, September 2026) finds
passages by *meaning*: anchor on any passage of the literary core and
get its nearest same-language neighbors — the same line in another held
edition, a quotation drifted by memory, a paraphrase — ranked and
banded *close / near / loose*, with the model named so a statistical
match is never mistaken for a curated alignment. Behind it is a local
vector store the owner builds once with `nabu embed` (fully on-box; no
text leaves the machine) and tops up incrementally after every sync.
The plain-language write-up — what embedding is, what it can and cannot
answer — is
[embed.md](https://github.com/arvicco/nabu/blob/main/docs/embed.md).

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
of a registered work — the parallel New Testament (up to fifteen
registered witnesses, the Sahidic and Bohairic Coptic among them since
13 July 2026) and the Septuagint ↔ Vulgate ↔ English Old Testament ship as
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
({{ census.dictionary_shelves }} dictionary shelves,
{{ census.dictionary_entries_display }} entries as of
{{ census.as_of }}: LSJ, Lewis &amp; Short, Bosworth-Toller,
Monier-Williams, the reconstruction dictionaries, the StarLing bases
with Vasmer, the Slovenian historical dictionaries, the Hebrew and
Egyptian lexica, the Sino-Japanese desk, and on), with the
entry's citations resolved to live passages in the local catalog:

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
reconstructions that name it among their descendants, then up the
proto-to-proto chain — through the intermediate shelves where they exist
(Latin through Proto-Italic to Proto-Indo-European, for instance) — each
stage listing cognates with corpus attestation counts, and curated loan
events labelled as such. Plain-ASCII input is accepted for reconstructed
forms:

```
$ bin/nabu etym богъ --lang chu
богъ [chu] → *bogъ [sla-pro] — gloss: god
← *bʰeh₂g- [ine-pro] — gloss: to divide, distribute, allot
  reflexes: [grc] ἔφᾰγον, [sa] भक्ष (bhakṣá), …
```

Since 14 July 2026 three expert-curated witnesses answer beside the
Wiktionary-derived chains: the IE-CoR cognacy database (4,981 cognate
sets), the LIV verbal roots, and de Vaan's Latin etymological dictionary —
so the same walk can be checked against independently curated scholarship.
The StarLing bases joined on 17 July 2026 (Pokorny, Nikolayev's PIE
database, Vasmer, Common Germanic, Baltic), and where the crosswalk has
no reconstruction path for a form, `etym` now falls back to the plain
dictionary lookup rather than missing what `define` would find.

**Language cards** (`nabu language CODE`) explain any language code the
library surfaces — the corpus languages and the 803 Wiktionary etymology
codes that appear in `etym` cognate lists — on one card: name, family,
curated historical context, and the code's live holdings in the catalog.
Where the code is a registered anchor in the
[nabu-lects](https://arvicco.github.io/nabu-lects) registry, the card
ends with the **stage ladder** — live holdings per historical stage
(Classical, Late, Medieval Latin…), reconstructed stages asterisked.
An unknown code is reported honestly, with a family hint;
`nabu language --list` prints the held languages.

```
$ bin/nabu language gkm
```

**Sign cards** (`nabu char CHAR`) put one glyph on the desk, dispatched
by script. A Han character gets the dictionary-shelf card (structure,
readings, and a diachronic column from Old Chinese through the Heian
dictionaries) — and the door works in reverse: a pinyin reading
(`nabu char wen`, tones optional) or a Japanese on/kun reading — kana
(`nabu char ひと`) or plain romaji on the dictionary-caps convention,
CAPS for on'yomi (`nabu char TAI`), lowercase for kun'yomi
(`nabu char kuni`) — lists every character that carries it. A **cuneiform** sign — glyph, sign name, spelled value, or sign-list
number (`nabu char 𒊬`, `nabu char SAR`, `nabu char szesz`,
`nabu char MZL535`, bare `nabu char 852` matched across every held
list) — gets the Oracc Sign List card: sign name, the MZL/LAK/ABZL/HZL/ŠL print-list
concordances, every reading by language, the CDLI meaning glosses,
Wiktionary's sense glosses (𒊬: "orchard", "to write (on), inscribe" —
the kaikki Sumerian shelf), variant forms, and how often each spelled
value actually occurs across the held tablet corpora. An **Egyptian
hieroglyph** (`nabu char 𓅃`, or
by Gardiner-style code `nabu char G5`) gets the Unicode 17 Unikemet
card: catalog code, description, function, phonetic value, the
JSesh/Hieroglyphica/IFAO concordances, and the sign's attestation across
the held AES corpus's sign annotations. An ambiguous value lists every
candidate sign, never one silently; `--json` on the sign cards emits a
frozen machine contract. The token-by-token sibling is `nabu signs`,
which reads whole transliterated lines through the same sign list.

```
$ bin/nabu char 𒊬
𒊬  SAR  ·  U+122AC
sign lists: LAK 215 · ABZL 385 · HZL 353 · MZL 541 · …
values (OSL): kiri₆ · mu₂ · nisi · sar · šar · …
meanings (CDLI): sar → v. to write; n. vegetable · kiri₆ → n. garden
in the corpus: sar 100333 · nisi 27997 · kiri₆ 8737 · …
```

**Place cards** (`nabu place NAME|ID`) are the library's third dimension,
after language and time: one ancient place resolved through the local
Pleiades gazetteer dump — title, id, place types, attested period span,
representative point — followed by each source's holdings at that place,
counted over the Pleiades ids the epigraphic sources themselves assert in
their headers (never fuzzy-matched). Input is a Pleiades numeric id or an
exact title; id-less documents whose findspot text mentions the name are
listed as a separate, honestly labelled tail. When a shown inscription
carries such an id and the dump is on disk, `nabu show` adds a one-line
findspot resolution too. Since the places program (August 2026) the
holdings side reads a **multi-gazetteer index** (Pleiades, Trismegistos
Geo, CIGS) and `nabu place apply` projects the
[nabu-places](https://arvicco.github.io/nabu-places/) registry's matching
decisions into the catalog — see [Places]({{ '/places/' | relative_url }})
for the system and the coverage census.

```
$ bin/nabu place Segesta
$ bin/nabu place apply
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
surface re-inflected allusions through rare lemmas. Its statistical
sibling is `search --similar` [above](#words-and-meanings) — parallels
ranks shared *phrases* with evidence, semantic search ranks shared
*meaning*; the two answer different questions and neither pretends to be
the other.

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

## Ask your model

Everything above is also available *in conversation*: the library ships
a read-only [MCP server](https://github.com/arvicco/nabu/blob/main/docs/mcp.md)
(`bin/nabu mcp`) exposing thirteen tools — `nabu_search`, `nabu_show`,
`nabu_define`, `nabu_etym`, `nabu_links`, `nabu_parallels`,
`nabu_cognates`, `nabu_align`, `nabu_concord`, `nabu_place`,
`nabu_char`, `nabu_signs`, and `nabu_status` — so an AI assistant wired
to your library can search, cite, align, and etymologize over it
mid-discussion. Registration for Claude Code and Claude Desktop is in
the [server documentation](https://github.com/arvicco/nabu/blob/main/docs/mcp.md);
restricted material is excluded by default, license classes ride every
payload, and nothing is ever written. The command-line search modes
travel with it: `nabu_search` takes the `lect` historical-stage filter
and, since September 2026, a `similar_to` anchor — the
[semantic-search lane](#words-and-meanings) in conversation, banded and
model-named like its CLI twin.

The point is composition: a research question is usually two or three
tools, not one. Every example below — and every "Ask your model" block
on the [axis pages]({{ '/axis/' | relative_url }}) — was run live
against this library before it was written down; nothing is invented.

- **“Who quotes the opening of the Iliad?”** — `nabu_parallels` on
  Iliad 1.1 returns Galen, Aristotle's *Ars Rhetorica*, and Sextus
  Empiricus (seven loci) sharing μῆνιν ἄειδε, each with the matched
  phrase and a urn `nabu_show` opens in pristine text.
- **“Show me MARK 2.3 in every witness.”** — `nabu_align` returns
  fourteen columns at once: Greek, Latin, Gothic, Armenian, four Old
  Church Slavonic codices, Old English, Sahidic Coptic, English.
  `collate: true` turns them into an apparatus.
- **“Where does Gothic *guþ* come from?”** — `nabu_etym` walks it to
  Proto-Germanic *\*gudą* (64 cognates, nine attested here with counts)
  and the PIE ancestors above it.
- **“What survives from Segesta?”** — `nabu_place` resolves the
  gazetteer card (Pleiades 462487) and counts the library's holdings
  at that place, per source.
- **“Attestations of *šarru* 'king'?”** — `nabu_search` by lemma
  resolves the logogram LUGAL through ORACC's lemmatization; the first
  hits are the Cyrus Cylinder.

Each desk has its own examples — and its own conventions (Hittite is
typed syllabified, Old Japanese romanized) — on its
[axis page]({{ '/axis/' | relative_url }}) under **Ask your model**.

## Stewardship

**Lect rulings** (`nabu lect …`, added 4 August 2026) manage the layer beneath language
codes: which historical stage of a language a document actually
attests, in [nabu-lects](https://arvicco.github.io/nabu-lects)
identifiers (`lat:med`, `akk:ob`, `grc:koi`). Assignments live in
their own journal (`db/lects.sqlite3`) that survives `nabu rebuild`
and rides backups, at three grains: `lect assign URN LECT` records a
single ruling; `lect apply-rules` compiles the ratified facet rules
(a CDLI period label, an AES corpus slice, a DCS Vedic school tag
names the stage of every document carrying it); `lect infer-dates`
assigns a stage when a document's date interval sits inside exactly
one stage band — containment, never overlap, so an inscription dated
across a stage boundary stays honestly unstaged. Both batch commands
render a full census under `--dry-run` before anything is written,
re-runs supersede only their own rows, and a hand ruling is never
overwritten by a rule. `lect check-dates` audits the reverse
direction: assignments whose document dates contradict the assigned
stage's band. The resolved lect is materialized as an ordinary
document facet, so `show` prints it, `search --lect` filters by it,
and the `language` card's stage ladder counts by it.

```
$ bin/nabu lect assign urn:nabu:perseus-latin:phi0119.phi001 lat:arch --note "Plautus"
$ bin/nabu lect apply-rules --dry-run
$ bin/nabu lect infer-dates --source edh --dry-run
$ bin/nabu lect check-dates
```

**Enrichment campaigns** (`nabu embed`, `nabu lemma-enrich`) are the two
owner-fired long runs that grow the layers above: `nabu embed` builds
and incrementally maintains the semantic-vector store behind
`search --similar`, and `nabu lemma-enrich` runs the local lemmatizer
over a language's uncovered passages to grow the silver tier. Both are
census-first (an honest count and time estimate before anything runs),
resumable at fine grain, and fully on-box; their tool stacks install
with one idempotent command each (`rake tools:embed`,
`rake tools:stanza[la]`). The plain-language write-ups:
[embed.md](https://github.com/arvicco/nabu/blob/main/docs/embed.md) ·
[lemma-enrichment.md](https://github.com/arvicco/nabu/blob/main/docs/lemma-enrichment.md).

**Ingest** (`nabu ingest FILE...`) files your own material — scanned
grammars, offprints, reading notes — into the local library shelf: the
file is copied in (never moved), metadata candidates are derived
mechanically (PDF metadata, filename heuristics, sha256) and confirmed
interactively, with AI assistance (`--assist` pipes a brief to any
suggester command and prefills the prompts), or scripted (`--yes` plus
flags); the shelf then syncs and the new urn is printed. The command
also accepts http(s) URLs, downloading first (redirects followed) and
recording the given address in the manifest. Everything on
this shelf defaults to the `research_private` license class — catalogued
and searchable locally, never served or redistributed. The same command
scaffolds a language dossier (`ingest --shelf language CODE`) or a
source dossier (`ingest --shelf source SLUG`).

**The content census** (`nabu list [SOURCE]`) is the what-is-held view
beside `nabu status`'s sync-state view: bare, it prints one line per
shelf with document, passage, and entry counts, languages, and the
effective license-class mix; with a source it prints that shelf's card —
identity, credit line, the curated dossier description, per-language
breakdown, and date-axis and facet coverage — and
`--documents` / `--entries` / `--collections` enumerate the holdings
with filters.

```
$ bin/nabu list
$ bin/nabu list corph --documents --limit 10
```

**Working by research desk.** The flat source list is also tagged into
{{ census.desks }} [research axes]({{ '/axis/' | relative_url }}) — the owner's
scholarly desks (the Classicist, the Assyriologist, the Sinologist…). A
source wears every desk it serves, and four surfaces read those tags:
`nabu enable NAME` puts a desk's shelves in this box's profile (the first-time
step — `sync` acquires only enabled sources), `nabu list --axis NAME` groups
the census under a desk, `nabu search --axis NAME` scopes a query to a desk's
shelves (the multi-source generalization of `--source`), `nabu sync NAME`
syncs a desk's enabled members, and `nabu axis NAME` prints the desk card —
members, live holdings, and gold coverage. Each desk's own page collects its
shelves, instruments, CLI recipes and terminal setup.

```
$ bin/nabu axis celtic
$ bin/nabu search μηνιν --axis celtic
```

**Owner notes** (`nabu note URN [TEXT]`) record your own annotations —
scholia of one's own — against any citable URN the corpus knows:
documents, passages, ranges, or dictionary entries. The URN is resolved
against the catalog before anything is written; the notes live as plain
YAML on a local shelf, render wherever the target is shown (`show`,
`define`, `links`), and are served to AI clients under the same
withholding rules as their targets. A bare `nabu note URN` reads back
what you said; `--list` enumerates.

```
$ bin/nabu note urn:nabu:ccmh:mar:mt "Collate against Jagić 1883 before citing."
```

The remaining commands keep the collection alive: `nabu quickstart` syncs
a curated starter shelf (four sources, about 690 MB) and prints the first
commands to try; `nabu sync` fetches and
loads a source (idempotent and non-destructive, with every run recorded);
`nabu status` and `nabu health` report per-source counts, run history, and
upstream drift — `health` also checks a set of mechanical invariants
(failed or partial loads, configuration-versus-catalog mismatches, pending
migrations, quarantine counts measured against an audited baseline) so
that a sync that did not do what it claimed is surfaced rather than
discovered; `nabu verify` re-parses every canonical file and compares
content hashes against the catalog; `nabu rebuild` regenerates the entire
database from canonical data, proven byte-identical by test; and
`nabu backup` copies everything non-derivable to external storage, with a
rehearsed restore drill. These are documented in the repository's
[operations runbook](https://github.com/arvicco/nabu/blob/main/docs/ops.md).

These instruments read best in use. The
[Examples]({{ '/examples/' | relative_url }}) put them in the hands of a
classicist, a papyrologist, an assyriologist and others — real sessions, end
to end — and each [research desk]({{ '/axis/' | relative_url }}) then gathers
the commands, shelves and terminal setup for one field.
