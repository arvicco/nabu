# PIE/comparativistics sources survey (P17-8 Phase A, 2026-07-13)

Scout survey for the owner's comparativistics axis ("I feel we're thin").
Everything the library holds on this axis today is **one witness**: English
Wiktionary via wiktextract/kaikki (sla-pro/ine-pro/gem-pro live; ine-bsl-pro/
itc-pro/iir-pro/gmw-pro landing per docs/recon2-survey.md). The question
this survey answers: what NON-Wiktionary machine-readable comparativistics
exists, and does any of it join our corpus? Method: page-level WebFetch/
WebSearch, GitHub/Zenodo API reads, and small samples downloaded to scratch
(`scratchpad/pie/`) and censused first-hand — every URL and file named
inline. The live db was NOT touched (owner rebuild in progress); gold
yardsticks are recon2-survey's numbers (131,175 distinct gold
(language, lemma) keys; held gold-lemma languages grc, lat, san/san-Latn,
got, ang, chu, orv, sl, xcl, hit, akk, sux), so joins here are
language-mapped and form-spot-checked, projected honestly rather than
measured record-level — the record-level measurement is a Phase B step
against the rebuilt db.

**Bottom line up front.** The field splits cleanly in three. (1) The
CLDF/Lexibank cognacy world has exactly one prize for us and it is a real
one: **IE-CoR** (Heggarty/Anderson/Scarborough 2023, the *Science* paper
dataset), CC BY 4.0, expert-curated cognate sets whose historical-language
wordlists land on TEN of our held gold languages at once — a genuinely
independent second witness minting held-to-held cognate edges (2,261
measured candidate pairs) plus its own laryngeal-notated PIE roots (1,596)
and a curated loan-event layer that feeds the P17-3 `borrowed` design.
(2) The LiLa LOD corner holds a small surprise: **LIV** (Rix's PIE verb
lexicon) and **de Vaan's EDL skeleton** exist as licensed RDF —
publisher-permitted, Latin-slice only, tiny but scholarly-grade.
(3) The Pokorny digitizations (Starling, dnghu, UT LRC, Köbler) are all
license-blocked or format-blocked despite the data being technically
reachable — censused below with the exact block and unblock path each.

---

## 1 · IE-CoR — the pick (CC BY 4.0, measured in full)

**What/where.** Indo-European Cognate Relationships database, the dataset
behind Heggarty et al. 2023 (*Science* 381: "Language trees with sampled
ancestors…"). CLDF (multi-table CSV) at
<https://github.com/lexibank/iecor> (git, ~11 MB, releases tagged), Zenodo
DOI 10.5281/zenodo.13304537, browsable at <https://iecor.clld.org>
(clld app: `clld/cobl2` — "CoBL" is this database's editing platform, not a
separate source). License read three ways, all agreeing: GitHub license
field CC-BY-4.0, README verbatim "This dataset is licensed under a
https://creativecommons.org/licenses/by/4.0/ license", Zenodo record
cc-by-4.0 → `license_class: attribution`, MCP-surface-safe.

**Census (all CSVs downloaded and counted, 2026-07-13):** 160 language
varieties / 170 concepts (Concepticon-linked) / 25,731 lexemes / 25,741
cognate judgments in 4,981 cognate sets (2,341 singletons) / 1,036 loan
events (`loans.csv`). Files: `cldf/{languages,parameters,forms,cognates,
cognatesets,loans}.csv` + `cldf-metadata.json` + `sources.bib`.

**The held-language landing (measured from `languages.csv`,
`historical=true` = 52 varieties):** 12 varieties map to 10 held gold
languages —

| IE-CoR variety | forms | our tag |
|---|---|---|
| Hittite | 137 | hit |
| Old Church Slavonic | 175 | chu |
| Vedic: Early | 170 | san |
| Greek: Ancient / NT / Mycenaean | 172 / 160 / 47 | grc (gmy off-gold) |
| Latin | 172 | lat |
| Armenian: Classical | 170 | xcl |
| Old Novgorod | 102 | orv |
| Slovene: Early Modern | 172 | sl |
| Old English | 170 | ang |
| Gothic | 123 | got |

Plus 40 more historical varieties we don't hold (Tocharian A/B, Avestan,
Old Persian, Old Irish, Oscan, Umbrian, Luvian, OHG, Old Icelandic, Old
Prussian, Old Polish, Old Czech…) that ride along as display witnesses —
and modern IE for breadth.

**Measured edge potential:** 1,772 held-language forms sit in cognate
sets; **273 sets contain ≥2 distinct held languages**, yielding **2,261
held-form pair edges**. Top pairs: chu~sl 146, chu~orv 92, ang~got 88,
orv~sl 86, lat~san 54, grc~san 50, grc~lat 47, grc~xcl 46. The promised
example verified first-hand — set 6458 "heart" holds **eleven** held
witnesses in one set (grc καρδία, hit ker/kard(i)-, lat cor, chu срьдьцє,
san hā́rdi, xcl սիրտ, orv сердьце, sl ſerzè, ang heorte, got
𐌷𐌰𐌹𐍂𐍄𐍉/hairto) under `Root_Form` **\*k̑erd-** / `Root_Language`
Proto-Indo-European.

**Form shape (the join story, spot-checked honestly).** Each form carries
`Form` (romanized citation form), `native_script`, `phon_form`/`Segments`
(IPA — for display/phonology only, NOT the join key), `Comment`, and for
grc/lat even per-form **Perseus LSJ/Lewis-Short entry URLs**. These are
dictionary citation forms, not raw IPA — the fear that "IPA-ish
transcriptions may not fold" does not materialize for the join-bearing
fields:

- grc: native_script polytonic (κακός, νῶτον) — folds to gold grc lemmas
  under the §9 grc rule; roman `kakós` as backup.
- lat: plain citation forms (cinis, tergum, malus) — direct.
- got: `Form` romanized (ains, hairto) = the PROIEL gold-lemma convention,
  native_script Gothic besides — the recon2 "roman is load-bearing"
  pattern repeats.
- chu: Cyrillic native_script (зълъ, кора) + scientific translit — TOROT
  gold lemmas are Cyrillic; direct.
- ang: heorte — direct.
- sl: `Form` in Bohorič orthography (ſerzè) with EMPTY native_script — the
  §9 sl ſ→s fold already exists (goo300k precedent); accent strip via
  generic fold.
- Real gaps, stated: **san** forms are accented nom.sg. (ā́saḥ,
  pr̥ṣṭhám) where UD-Vedic/GRETIL gold lemmas are stem-shaped — expect a
  depressed san join, measure at Phase B, do not promise; **hit** forms
  are hyphenated stems `ḫāš(š)-` with parens (needs a strip rule; hit gold
  is 14 lemmas ≈ 0 join regardless — corpus-side, per recon2); **orv** is
  the Novgorod dialect (сердьце with polnoglasie vs TOROT's OCS-leaning
  lemmas) — partial; **gmy** is Linear B, off-gold. Multi-form values
  ("popelŭ, pepelŭ" in one field) are a parser policy decision to pin at
  fixture time.

**The independent-witness payoffs beyond edges:**

1. **Root_Form/Root_Language on cognate sets**: 4,326 sets carry a curated
   root + 655 more a computed one — **1,596 labeled Proto-Indo-European**,
   proper laryngeal notation (\*h₂ster-, \*h₃mei̯gʰ-, \*kʷetu̯or-). 2,001
   of 4,981 sets root in a language mapping to a live-or-landing proto
   shelf (ine-pro 1,596, gem-pro 169, iir-pro 113, sla-pro 90,
   ine-bsl-pro 21, itc-pro 12) — a Wiktionary-independent cross-check of
   the kaikki shelves' roots. Notation differs in diacritic choice (IE-CoR
   \*k̑erd- vs kaikki \*ḱerd- — k+U+0311 vs U+1E31) but both fold to `kerd`
   under the generic Mn-strip: the cross-witness join works through the
   existing §9 fold, spot-checked on heart/hound/star.
2. **The loans layer** (`loans.csv`, 1,036 events, set→set with
   Source_languoid/Source_form): measured against held members — the xcl
   ←Iranic layer (the same layer iir-pro flags, now second-witnessed), chu
   +orv+sl ←Turkic (set 1171), sl ←Gothic hûs (set 5196), sl ←German
   Forst, hit ←Hattic (sets 3334, 7641), grc ←Pre-Greek substratum (set
   1531 \*gʷlep⁽ʰ⁾-). This is curated per-SET loan attribution with a
   named source — richer than the kaikki `borrowed` tag and exactly the
   P17-3 rider's shape.
3. Doubt flags on judgments, `Ideophonic`/`parallelDerivation` on sets,
   clade tree with per-variety dating priors (`clades.csv`,
   logNormalMean/fossil columns — axis-adjacent metadata), authors per
   variety, `sources.bib`.

**Honest scope statement:** IE-CoR is a basic-vocabulary cognacy matrix
(170 meanings), NOT an etymological dictionary. It will not widen coverage
the way kaikki shelves do; per held language it brings ~100–175 curated
lemmas. Its value is (a) independence — a third witness after kaikki and
MW-derived data, expert-curated, with a named editorial process; (b) the
held-to-held edges landing on exactly the languages our alignment/cognates
tools care about; (c) the loan layer.

**Surface recommendation (argued): reflexes rows, not a new table.**
Model each cognate set as a dictionary entry of a new `iecor` source
(`content_kind :dictionary`), headword = `Root_Form` (falling back to
`Root_Form_calc`, else the set id), each member form = a
`DictionaryReflex` row (lang_code = variety id/Glottocode verbatim;
language = mapped tag; word = native_script or Form; roman = Form;
folded per §9). Why A over a bespoke cognacy-set table (option B):

- 40% of sets are root-headed in a shelf-language we already speak
  (ine-pro/gem-pro/…), i.e. entries ARE reconstruction-headed exactly like
  kaikki shelf entries — `nabu etym`, Cognates, the reflex closure and MCP
  light up with **zero new query code**, and the closure's shelf-visited
  walk (recon2 §2) treats iecor as one more reflex-owning shelf, giving
  cross-witness chains (IE-CoR \*k̑erd- and kaikki \*ḱerd- both reachable
  from chu срьдьцє, each labeled by its source).
- The set-grain extras (Doubt, loan events, concept id) ride in the
  entry's annotations + the `borrowed` boolean the P17-3 migration already
  plans — loans.csv ORs into member edges the same way the hlaibaz
  proto-to-proto flag does.
- Costs, named: sets whose Root_Language is an attested language (Latin
  123, Sanskrit 102, Greek 102…) or absent get headwords that are not
  reconstructions — carried under one dictionary language tag. Proposal:
  dictionary language `ine` (the ISO 639-2 collective code, shape-valid,
  already a PROTO_FOLD key), per-set root language verbatim in
  annotations; entry display prefixes \* only when the root is a
  reconstruction. Singleton sets (2,341) mint entries with ≤1 reflex —
  harmless, or skippable by rule at parse (decide at the gate).
- Option B (cognate_sets + cognate_judgments tables) buys cleaner
  semantics and a place for alignment strings, at the price of a new
  query/MCP/closure surface for what is, at our grain, the same
  "reconstruction-or-set → attested members" shape. Not worth it for
  source #1 of this kind; revisit only if a second cognacy-matrix source
  lands and the entry-shaped modeling chafes.

**Fetch/size:** git clone (existing git fetch path — lexibank repos are
ordinary GitHub repos, release-tagged) or the Zenodo zip via ZipFetch;
~11 MB. Pin the release tag; kaikki-style DEPRECATED risk does not apply.

---

## 2 · The LiLa LOD corner — LIV and de Vaan as licensed RDF

Found via the LIV digital-state check: CIRCSE (Università Cattolica Milan,
the LiLa: Linking Latin project) published two Brill/Reichert-copyrighted
etymological dictionaries as Linked Open Data **with publisher
permission**, entries omitted, etymological skeleton included.

### 2.1 CIRCSE/LIV — Rix's Lexikon der indogermanischen Verben (CC BY-SA 4.0)

<https://github.com/CIRCSE/LIV> — `ttl/LIV.ttl` (657 KB Turtle, lemonEty/
Ontolex model), censused first-hand: **305 PIE etymons** (laryngeal
notation: \*dʰu̯eh₂-, \*lei̯d-), **385 Latin lexical entries / 340
writtenReps** (suffio, pinso, parco, uireo, facio…), stem-type layer
(present/aorist/perfect/causative/desiderative… stems — a NEW annotation
axis no kaikki shelf carries). README verbatim: "The publisher of the
dictionary allowed us to model and publish the etymological relations
between PIE roots, stems and Latin word forms" + CC BY-SA 4.0 badge →
`attribution`. Latin slice ONLY (550 word forms per the README; the
Germanic/Greek/etc. reflex columns of print LIV are not included).
Join: writtenReps are u-spelling Latin (uireo) — the §9 lat u/v fold
covers it; spot-checked facio/edo/fundo = certain gold lat lemmas.
Small, scholarly, non-Wiktionary — the reference PIE **verb** inventory
second-witnessing kaikki's ine-pro verb roots on the lat axis.

### 2.2 CIRCSE/EtymologicalDictionaryLatin — de Vaan's EDL skeleton (CC BY-NC-SA 4.0)

<https://github.com/CIRCSE/EtymologicalDictionaryLatin> —
`data/BrillEDL.ttl` (4 MB Turtle), censused: **1,437 etymology nodes over
1,429 Latin headwords**, etymons staged **PIt 1,466 + PIE 1,394** (per-stage
reconstructions: lat rōdō ← PIt … ← PIE …), linked to LiLa lemma URIs.
README verbatim: de Vaan's EDL "is copyrighted by Brill… The dictionary
entries are not represented"; repo LICENSE = CC BY-NC-SA 4.0 → `nc`
(GRETIL posture: local research yes, MCP/redistribution no). The
Proto-Italic stage is a genuine crosswalk to the landing itc-pro shelf —
proto-to-proto second witness, Leiden-school laryngeals vs Wiktionary's.
Also in the org, noted: `CIRCSE/englishWiktionaryLatinEtymologies`
(same-witness, see §6) and LiLa's IGVLL (Greek loanwords in Latin) served
from the LiLa triple store, not GitHub — a future borrowed-layer lead.

**Cost, stated:** both are Turtle → nabu's first RDF input. Not a real
parser burden (regular triple shapes, no reasoning needed — a ~150-line
extraction akin to a JSONL walk), but it IS a new small family; the two
files share it. Both are single-file FileFetch syncs.

---

## 3 · Pokorny digitizations — all blocked, each differently

The underlying IEW is itself in copyright (Pokorny d. 1970; life+70 →
2040, Francke/Narr) — every digitization inherits that cloud unless it has
its own grant.

### 3.1 StarlingDB / Tower of Babel · UNBLOCKED — PERMISSION GRANTED (2026-07-15)

**License resolved by correspondence:** G. Starostin, 2026-07-15 — "all
etymological data are free for anybody to use for any purposes as long
as the source is properly acknowledged," with the express condition
that attribution name the SPECIFIC compilers of each database (roster:
starlingdb.org/descrip.php?lan=en#bases), since the databases are
individual scholarly reconstructions, not consensus snapshots. Class
recommendation `attribution` (grant email archived); per-base compiler
credit rides in source metadata and on every serving surface; his
non-consensus caveat is carried verbatim at adapter-build time. The
survey below (data census, decoding) predates the grant and stands.


<https://starlingdb.org> (starling.rinet.ru 301s here). The famous murky
terms, read: the downloads page (`downl.php?lan=en`) offers the full IE
package with **no license text at all**; the project page's only statements
are "Copyright 1998-2003 by S. Starostin" and software copyrights
(Bronnikov, Krylov). No grant on the SITE → all-rights-reserved default was the pre-grant
reading (**superseded by the 2026-07-15 written permission above**). The data reality,
censused first-hand (`download/IE.exe` — a plain zip despite the name,
6.2 MB, extracted to scratch): `pokorny.dbf` **2,222 roots**
(ROOT/MEANING/GER_MEAN/MATERIAL/PAGES + PIET crosslink — the Starostin-
scanned, **Lubotsky-corrected** IEW text), `piet.dbf` **3,291
etymologies** (Nikolayev, Walde-Pokorny-based) with per-branch reflex
columns (HITT/IND/AVEST/IRAN/ARM/GREEK/SLAV/BALT/GERM/LAT/ITAL/CELT/ALB/
TOKH — structurally the best Pokorny-family data anywhere), `germet.dbf`
1,994 (GOT/OENGL columns), `baltet.dbf` 1,651, `vasmer.dbf` 18,239, +
Swadesh-list DBFs. Second blocker measured: text lives in `.var` files in
Starling's custom encoding — in-band `\B\I` markup and font-shift byte
runs for Greek (`\x01\x83\xc2…` for ἆ) — decodable (the Starling source is
published at `/startrac/starling/`; §1's SequenceComparison conversions
prove it) but real archaeology. **Unblock path:** permission mail to
G. Starostin (gstarst@rinet.ru, on the site) — precedent cuts both ways:
the Jena group relicensed Starostin's *wordlists* CC BY 4.0 (§6/
starostinpie), but nobody has relicensed the etymological databases.

### 3.2 UT-Austin LRC "Indo-European Lexicon" · STRUCTURED HTML, NO GRANT

<https://lrc.la.utexas.edu/lex> — the Pokorny Master list (**2,222
etyma**, >67% with reflex pages; ~200 languages) built on Lehmann's
lexicon. Reflex pages are genuinely structured tables (Language / Reflex /
PoS / Gloss / source codes incl. IEW page refs) — the nicest reading
surface of any Pokorny derivative and it would join ang/got/lat/grc gold
well. But: **no bulk download, no data license** — only "© Copyright 2026"
University of Texas. A polite crawl without terms is not our posture →
blocked pending permission. **Unblock:** one email to the LRC (they are
academics with a stated educational mission; plausible `research_private`
or better grant).

### 3.3 dnghu / Academia Prisca · CC BY-SA CLAIMED, PROVENANCE MURKY, PDF

<https://indo-european.info/pokorny-etymological-dictionary/> (JS shell,
no bulk endpoint) and the 2007 PDF ("An Etymological Dictionary of the
Proto-Indo-European Language", 15 MB, mirrored widely — front matter
embeds `creativecommons.org/licenses/by-sa/3.0/` links, read from the PDF
itself). But the text is the same Starostin/Lubotsky digitization
(<https://academiaprisca.org/indoeuropean.html> credits it verbatim), so
dnghu's CC badge licenses what wasn't theirs to license; and the format is
PDF prose. Not ingestable on license honesty grounds, independent of
format cost.

### 3.4 Köbler, Indogermanisches Wörterbuch · NO FORMAL LICENSE

<https://www.koeblergerhard.de/idgwbhin.html> — ~4,500 entries, HTML +
downloadable Gesamtdatei, German glosses, Pokorny-derivative. No license
statement ("der Allgemeinheit digital zur Verfügung stellen" is not a
grant). Low value over the above; skip (an email could unblock, low
priority).

Internet Archive serves IEW page scans (e.g.
`archive.org/details/indogermanisches02pokouoft`) — scans only, and the
work is not PD anyway.

---

## 4 · PIE Lexicon (Pyysalo, Helsinki) · CC BY-SA 4.0, SMALL, SCRAPE-SHAPED

<http://pielexicon.hum.helsinki.fi> (https unreachable — cert/port dead;
plain http serves). Live Express app, "Pilot 1.1": **~200 IE roots**, ~300
new etymologies for Old Anatolian (Hittite, Palaic, Cuneiform + Hieroglyphic
Luwian), forms for "hundred most ancient IE languages" generated by Foma
sound-law scripts from the PIE reconstruction (each form's derivation chain
inspectable). License read from the page footer: CC BY-SA 4.0 badge with
`rel="license"` + "© 2014-2026 University of Helsinki" → `attribution`
(BY-SA). Machine-readability: server-rendered structured divs
(`row category` / `inwords` / per-step derivations), a "Show the entire
data in a single page" view (`?alpha=ALL`) — scrapeable with a small HTML
walk, no JSON/API/bulk file (the `handsontable` grid arrives empty;
`var searchResults = []`). Join: Anatolian-skewed (hit gold = 14 lemmas ≈ 0
per recon2), monolaryngealist notation (\*gɑɦo·nes- — NOT mainstream
three-laryngeal, so its roots would sit oddly beside kaikki/IE-CoR roots
and must be labeled as the school it is). Verdict: licensed and genuinely
non-Wiktionary, but small, theoretically idiosyncratic, and scrape-only —
**v2/watch**; contact pie-lexicon@helsinki.fi if it grows past pilot.

---

## 5 · Brill paywall + print-only roll (verified quickly, not dwelt on)

- **Brill IEDO** (`dictionaries.brillonline.com/iedo` — Kloekhorst
  Hittite, de Vaan Latin, Beekes Greek, Derksen Slavic/Baltic, Martirosyan
  Armenian, Cheung Iranian…): request 302s straight into a LibLynx
  institutional-auth wall — subscription-only, confirmed. **Blocked.**
  Partial unblock EXISTS and is §2.2 (de Vaan skeleton via LiLa); nothing
  comparable located for Beekes/Kloekhorst/Derksen (GitHub + Zenodo
  searched).
- **LIV print/PDF** (Rix 2001; Kümmel's addenda PDFs): print-only except
  the §2.1 Latin LOD slice.
- **NIL** (Wodtko/Irslinger/Schneider 2008), **Mallory & Adams**,
  **Watkins' AHD roots** (© HMH): print-only, **no unblock path** —
  named and closed.
- **UT LRC "Early Indo-European Online"** (`lrc.la.utexas.edu/eieol`): 18
  lesson series of glossed chrestomathy texts (pedagogy, incl. Hittite/
  Tocharian/OCS/Old Russian) — not reconstruction data, no license; skip.
  (Its Unicode metrically-restored Rigveda is a corpus lead, off this
  packet's axis; GRETIL already covers RV.)

---

## 6 · Same-witness Wiktionary derivatives (named to prevent double-counting)

`droher/etymology-db` (3.8 M relations, CSV/Parquet), EtymDB 2.0
(Fourrier & Sagot, LREC 2020), CogNet, de Melo's Etymological WordNet,
`CIRCSE/englishWiktionaryLatinEtymologies`, and the SequenceComparison
CLDF ports of **modern-language** wordlists (`dunnielex` — IELex-2012
subset, 20 modern varieties; `starostinpie` — Starostin's 110-item lists,
19 modern varieties; both CC BY 4.0; **zero held-language forms**, checked)
— either re-extractions of the same English Wiktionary our kaikki shelves
witness, or gold-language-free. Also censused and passed over:
`lexibank/dyenindoeuropean` (Dyen/Kruskal/Black 1992, 95 modern
varieties), `lexibank/asjp` (CC BY 4.0 but 40-item lists, automated — not
expert cognacy), `lexibank/meloniromance` (CC BY 4.0, Latin + 5 modern
Romance, 5,419 sets — the Latin side duplicates what IE-CoR/LiLa give with
better company; hold as a v3 lead), `lexibank/germancognates` (Kluge-
derived, 4 modern varieties, 527 sets — off-gold). IELex classic
(ielex.mpi.nl) is **offline**; its successor is IE-CoR (§1); the
`evotext/ielex-data-and-tree` dump carries cognacy matrices **without
forms** (README verbatim) — phylogenetics-only, no join.

---

## 7 · Ranked verdict & fixture sketches (for the gate)

**v1 — one new source, one rider:**

1. **IE-CoR** (`iecor`, attribution). New small CLDF-CSV parser family
   (multi-table CSV join — forms×cognates×cognatesets×languages; nabu's
   first CLDF source, and CLDF is a standard worth owning a parser for).
   Entry-shaped per §1's argued Option A; reflexes rows join the existing
   etym/cognates/closure surface unchanged; `borrowed` rider fed from
   loans.csv. ~5k entries / ~26k reflex rows projected.
   **Fixture sketch** (byte-verbatim trimmed CSV set, the P14-1 recipe):
   `languages.csv` trimmed to the 12 held varieties + 1 modern (scoping
   stays quiet); `parameters.csv` to 3 concepts; sets **6458** (heart —
   the 11-witness golden: polytonic grc + dual-script got + Bohorič-ſ sl
   + hyphenated hit stem all in one record), **1171** (chu+orv+sl ←Turkic
   loan event → the borrowed-flag pin, with its `loans.csv` row), one
   `Root_Form_calc`-only set + one singleton (no-edge case), one
   comma-multiform chu record (попєлъ, пєпєлъ — the split policy pin).
   Folds to pin: k̑/ḱ cross-witness equivalence (both → kerd), ſerzè → serze,
   ḫāš(š)- paren/hyphen strip.
2. **LIV LOD rider** (`lila-liv`, attribution/BY-SA) — same phase if the
   small Turtle family is accepted, else first v2 pick. 305 etymons / 385
   entries; single-file FileFetch. **Fixture:** \*dʰu̯eh₂- and \*lei̯d-
   etymon blocks + the suffio and uireo entries (u/v fold pin) + one
   stem-type triple (the new verbal-stem annotation layer).

**v2:** de Vaan EDL skeleton (`nc` posture, same Turtle family, the
itc-pro cross-witness); PIE Lexicon (small scrape, label the
monolaryngealist school); meloniromance (only if Romance ever enters
scope).

**Blocked with unblock paths, in order of prize size:** Starling piet/
pokorny (mail G. Starostin; best-structured Pokorny data in existence,
2,222+3,291 records measured); UT LRC Lexicon (mail the LRC; structured
reflex tables, 2,222 etyma); Brill IEDO minus de Vaan (institutional
subscription only).

**Print-only, no unblock:** NIL, Mallory & Adams, Watkins/AHD, LIV beyond
the Latin slice, Beekes/Kloekhorst/Derksen/Martirosyan full content,
IEW itself (in copyright to 2040); dnghu's CC-badged PDF is declined on
provenance honesty, not format.
