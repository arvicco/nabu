# Old English / Anglo-Saxon sources survey (P11-1, 2026-07-09)

Scouting survey for the Old English axis (`ang`, ca. 700–1150, West-Saxon +
Northumbrian/Mercian dialects), which the corpus today serves with **nothing at
all** — zero OE documents in any live source. This document assesses what is
digitized, licensed, and machine-readable, with cited evidence and an honest
license read, and ends with a ranked recommendation of **at most two**
candidates for near-term (Phase 11/12) ingestion, plus a dedicated
biblical-axis section (the owner wants an OE Gospel witness for the P11-3
alignment hub).

No bulk fetching was done — page-level `WebFetch`/`WebSearch`, `gh api`
metadata, raw-file header peeks, and one small sample download (the 2.2 MB OTA
ASPR TEI, inspected read-only in scratch and discarded), per the packet.

**Bottom line up front.** Old English has one genuinely near-config-only win in
machinery we already own — **ISWOC**, a PROIEL-2.1-XML treebank (the exact
schema `ProielParser` already parses for proiel/torot) with five OE texts
including a verse-cited West-Saxon Gospel of Mark — and one clean open-license
breadth win, the **complete six-volume ASPR poetry corpus as a single TEI file
on the Oxford Text Archive under CC BY-SA 3.0** (Beowulf, the Exeter Book, all
of it). The prose prizes (YCOE, DOEC) are downloadable-for-research at best and
license-blocked at worst; the famous web editions (OE Poetry in Facsimile,
Electronic Beowulf, Jebson's Chronicle) are web-apps with no reuse grant. There
is **no Old English treebank in Universal Dependencies** (verified — no
config-only UD add exists). Bosworth-Toller has an official **CC BY 4.0** bulk
dump — the P11-4 dictionary-shelf candidate.

**One packet-lead correction:** ISWOC's Ælfric text is the **Lives of Saints**,
not the Catholic Homilies (backlog lead said Homilies); and its "West-Saxon
Gospels" is **the Gospel of Mark only** (see the biblical-axis section).

---

## Recommended for Phase 11/12 (ranked, ≤2)

### 1. ISWOC Treebank — five OE texts in PROIEL XML (existing parser family, near-config-only)

The single cheapest and highest-leverage OE win. ISWOC (Information Structure
and Word Order Change in Germanic and Romance; Kristin Bech & Kristine Eide,
University of Oslo) ships the **identical PROIEL XML 2.1** the corpus already
parses — verified in the raw file: `<proiel export-time="…"
schema-version="2.1">`, `<source id="wscp" language="ang">`, same `proiel.xsd`
(the README links the schema in the proiel-treebank repo itself). An `Iswoc <
Proiel` adapter is the TOROT pattern over again: manifest override + the
inherited flat-directory discover/parse/git-fetch.

- **OE contents (verified from the repo README table, token counts theirs):**
  Ælfric's *Lives of Saints* (`æls`, 3,137 tokens) · *Apollonius of Tyre*
  (`apt`, 5,541) · *Anglo-Saxon Chronicles* (`chrona`, 5,939) · *Orosius*
  (`or`, 1,728) · *West-Saxon Gospels* (`wscp`, 13,061 — Gospel of Mark, see
  below) ≈ **29,406 annotated OE tokens**, gold lemma + morphology +
  dependency syntax + information structure (the P7-5 lemma index lights up
  for `ang` for free).
- **Non-OE contents (we'd skip):** one Old French and nine medieval
  Spanish/Portuguese chronicle texts (eustace, cge1/2, coutdec-v-8,
  alfonso-xi, ce, cdeluc, ee1, ge4, varones) — medieval Romance, outside the
  corpus's scope. The `<source>` header carries `language=`, and the inherited
  discover already peeks that header cheaply, so an OE-only (`ang`) language
  filter is a few lines in the subclass. (Ingesting all 15 is the alternative;
  default recommendation is filter, noted in the adapter when built.)
- **Format:** PROIEL XML 2.1 (authoritative) + CoNLL-X exports. Flat repo root
  of per-text `*.xml` — the layout `Proiel#discover` walks verbatim.
- **License (verbatim, README at github.com/iswoc/iswoc-treebank):** "is
  freely available under a [Creative Commons Attribution-NonCommercial-ShareAlike
  3.0 License](http://creativecommons.org/licenses/by-nc-sa/3.0/us/)". Each
  per-source header agrees — `wscp.xml` carries `<license>CC BY-NC-SA
  3.0</license>` + `<license-url>http://creativecommons.org/licenses/by-nc-sa/3.0/us/</license-url>`
  (read in the raw file). → `license_class: nc`, exactly like proiel/torot:
  local research fine, default-excluded from the MCP surface, never
  redistributed. Cite as: "Bech, Kristin and Kristine Eide. 2014. The ISWOC
  corpus. Department of Literature, Area Studies and European Languages,
  University of Oslo."
- **Repos / maintenance:** original `iswoc/iswoc-treebank` (last push
  2023-05-02) is effectively frozen — its README opens "As of April 2023,
  releases of the ISWOC Treebank have moved to
  https://github.com/syntacticus/syntacticus-treebank-data." The successor
  repo carries the **byte-similar files under `iswoc/`** (verified file list +
  sizes via `gh api`) alongside `proiel/`, `torot/`, `menotec/` subdirs.
  **Overlap hazard:** if the adapter targets the successor repo it MUST scope
  to the `iswoc/` subdirectory only — `proiel/` and `torot/` there are the
  same data already synced from their own repos (double-load risk, the exact
  UD-conversion trap the Slavic survey flagged). Targeting the frozen original
  repo (proiel-treebank precedent, `sync_policy: frozen`) is the simpler v1;
  decide at adapter time.
- **URN:** TOROT precedent — inherit `urn:nabu:proiel:<source-id>` (ids wscp,
  apt, chrona, or, æls; disjoint from the proiel/torot id-space by upstream
  convention). Two flags for the adapter packet: `æls` is a non-ASCII id
  (URN-mint policy check) and `or` is two letters. Passage citations come from
  `citation-part` (already lifted by `ProielParser`, adapters/proiel_parser.rb).

**Why this is #1.** (a) Effort ≈ TOROT: subclass + manifest + language filter,
zero new parser family, zero new fetch path. (b) It opens an entire language
axis — first OE in the corpus, with gold lemmas. (c) It contains the
biblical-axis prize (verse-cited Mark, next section). (d) License is the same
`nc` class as its PROIEL siblings — no new policy surface. The one honest
minus: 29k tokens is a *sampler*, not a corpus — breadth comes from pick #2
and, later, YCOE.

### 2. ASPR — Anglo-Saxon Poetic Records, OTA 3009 (complete OE poetry, CC BY-SA, new small TEI family)

The entire canonical OE poetry corpus — all six Krapp & Dobbie volumes — as
**one downloadable 2.2 MB TEI P5 file** from the Oxford Text Archive, openly
licensed. Verified first-hand (header + structure inspected from a scratch
copy, then discarded):

- **Contents:** 374 `<head>`-titled texts, ~30,500 verse lines, spanning vol. 1
  Junius MS (Genesis, Exodus, Daniel, Christ and Satan), vol. 2 Vercelli Book
  (Andreas, Dream of the Rood, Elene…), vol. 3 Exeter Book (Christ, Guthlac,
  Wanderer, Seafarer, Widsith, Deor, the Riddles…), vol. 4 **Beowulf** ("Hwæt!
  We Gardena // in geardagum…" verified) + Judith, vol. 5 Paris Psalter +
  Meters of Boethius, vol. 6 Minor Poems (Cædmon's Hymn in **both Northumbrian
  and West-Saxon versions**, Bede's Death Song in three versions, the Leiden
  Riddle, Battle poems, metrical charms). Dialect/period precision rides in
  the text titles (Northumbrian vs West-Saxon witnesses are separate texts).
- **Source / provenance:** https://ota.bodleian.ox.ac.uk/repository/xmlui/handle/20.500.12024/3009
  (`3009.xml`, 2,214,065 bytes, fetched without auth). Machine-readable
  version by Gregory Ray Hidley, deposited by O. D. Macrae-Gibson (1993),
  revised from OTA 1936; base edition Krapp & Dobbie, *The Anglo-Saxon Poetic
  Records*, Columbia UP, 1931–1953 ("6 v." in the TEI sourceDesc).
- **License (verbatim, from the TEI header's availability element, read
  in-file):** `<licence target="http://creativecommons.org/licenses/by-sa/3.0/">
  Distributed by the University of Oxford under a Creative Commons
  Attribution-ShareAlike 3.0 Unported License</licence>` — also shown as
  "Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)", status "Publicly
  Available", on the OTA record page. → **`license_class: attribution`** —
  MCP-surface-safe, republishable with credit. The only fully-open structured
  OE text source found in this survey.
- **Format / parser verdict:** TEI P5 but **NOT EpiDoc/CTS** — no `refsDecl`,
  no CTS URNs; structure is `div → head + bibl + l*` with `<caesura/>`
  mid-line markers and `<unclear>` spans. **No `l/@n` line numbers anywhere**
  (verified by grep over the whole file) → citation must be poem-slug + ordinal
  line (`urn:nabu:aspr:<poem-slug>:<line-ordinal>`), honest-but-non-canonical
  the way GRETIL prose ordinals are; ASPR's printed line numbers are *probably*
  recoverable by counting but that claim needs fixture-time verification. A
  **new small bespoke parser family** (First1K-sized, simpler than GRETIL: one
  file, uniform structure, no Leiden, no marker archaeology).
- **Quality caveat:** an early-1990s e-text; `<unclear>` handling, editorial
  conventions, and possible transcription drift vs the print ASPR are
  fixture-archaeology risks. The single-file shape means one fetch (first
  plain-HTTP single-file fetch, or reuse of the ZipFetch-style HTTP path from
  P10-1 minus the unzip).

**Why #2.** It closes the most famous gap in the whole corpus (Beowulf, the
Exeter Book) under a genuinely open license — better license class than pick
#1 — but it needs a new (small) parser family, carries ordinal-only citations,
and has e-text-vintage risk, while ISWOC is near-zero effort with gold
annotation. Ship #1 first, queue #2 as the scout→plan→adapter track.

---

## The biblical axis: an Old English Gospel witness (for the P11-3 alignment hub)

**The direct answer: ISWOC `wscp.xml` is the best machine-readable open OE
Gospel edition, and it is the Gospel of MARK, not four Gospels.** Despite the
upstream title "West-Saxon Gospels," the file contains complete **Mark 1–16**
(671 distinct verse citations) plus two boundary fragments (Matthew 7, John
1.1) — verified from the file's `<div><title>` inventory (Mark 1…16, Matthew
7, John 1) and `citation-part` attributes. Every token carries native
`citation-part="MARK 1.1"`-style verse references, which `ProielParser`
already lifts into the passage `citation` field — so at ingest, OE Mark aligns
verse-for-verse against the five existing witnesses (greek-nt grc · latin-nt
lat · gothic-nt got · armenian-nt xcl · marianus chu) **with zero new
citation plumbing**. The hub gains its sixth version for the whole of Mark as
a registry entry.

Honest scope note: the flagship P11-3 demo verse "John 1:1" exists in wscp
(JOHN 1.1 tokens are present) but only as a fragment; the honest OE alignment
demo verse is a Mark verse (e.g. Mark 1:1 "Her ys godspelles angin…").

**Paths to the full OE tetraevangelion (all four Gospels), none cheap:**

- **YCOE `cowsgosp.o3`** — the complete four West-Saxon Gospels (Skeat-based
  e-text) in Penn-Helsinki bracketed format; verse coordinates are embedded in
  DOEC-style token ids (`Mt_[WSCp]:5.3…` — high-confidence from documentation,
  not verified token-by-token), not native attributes. Needs the new Penn
  parser family AND lives under OTA academic-use terms (below) with no
  redistribution grant on the text layer. Provenance chain worth knowing:
  ISWOC's wscp text **was imported from YCOE** (verbatim, wscp.xml header:
  "The text was imported from the York-Toronto-Helsinki Parsed Corpus of Old
  English Prose (YCOE), including the morphological annotation. … The
  syntactic annotation is independent of YCOE.") — same underlying e-text,
  distinct editions/annotation; if both are ever ingested they are distinct
  version-URNs, never a dedupe (conventions §3).
- **Public-domain reconstruction** — Skeat's *The Holy Gospels in Anglo-Saxon,
  Northumbrian, and Old Mercian Versions* (Cambridge 1871–1900) prints
  West-Saxon + Latin + **Lindisfarne (Northumbrian gloss)** + Rushworth in
  parallel with verse numbers; Bosworth & Waring 1874 prints **Gothic +
  West-Saxon** in parallel (a ready-made scaffold against our existing
  gothic-nt). Both are PD **page scans on archive.org only** — an OCR/HTR +
  verse-structuring project (the docs/03 reconstruction strategy), not an
  ingest.
- **Web display texts** (bible.com "ASXG Anglo-Saxon Wessex Gospels c1000",
  textusreceptusbibles.com mirror) — all four Gospels, clean verse divisions,
  but display-only with unstated compilation licensing → not an ingest source
  (useful as a verse-map reference at reconstruction time).
- **No open TEI edition of the OE Gospels exists** (searched GitHub, Zenodo,
  TEI archives — genuine absence at page level, not just not-found).

**Recommendation:** ship ISWOC (pick #1) and register OE Mark in the P11-3
hub now; hold the full tetraevangelion as a future YCOE-conversion or
PD-reconstruction packet.

---

## Dictionary shelf (P11-4 pattern): Bosworth-Toller — official CC BY 4.0 bulk dump

The canonical Anglo-Saxon dictionary (Bosworth & Toller + Supplement) has an
**official open data dump** from the team behind bosworthtoller.com (Ondřej
Tichý, Charles University, Prague), deposited at LINDAT/CLARIAH-CZ:

- **Record:** https://lindat.mff.cuni.cz/repository/xmlui/handle/11234/1-3532
  ("Data dump version 0.1", published 2021-04-09).
- **Format (verbatim from the record):** "The data dump is in two files:
  bosworth_backup_sql.sql Contains a complete backup of the project's database
  in SQL. bosworth_entries_export.csv … Contains three columns:
  \"id\";\"headword\";\"body\" … body = body of the entry tagged in xml" —
  i.e. **lemma-keyed CSV with project-XML entry bodies (not TEI)**, plus the
  full SQL. The `id` column resolves to `bosworthtoller.com/<id>` for stable
  web back-links.
- **License (verbatim, read on the LINDAT record page):** "Attribution 4.0
  International (CC BY 4.0)" (machine metadata
  `http://creativecommons.org/licenses/by/4.0/`) → `attribution`, MCP-safe.
  NB no license statement is readable on bosworthtoller.com itself
  (JS-rendered app); the LINDAT deposit by the same maintainer is the
  authoritative grant.
- **Caveat (verbatim from the record):** "The data is still being processed
  for accuracy and manually tagged with XML structural tags. … Not all entries
  have been checked and/or tagged." — v0.1 quality; the shelf ingest should
  tolerate untagged bodies.
- **Verdict:** the OE dictionary-shelf candidate for the P11-4 pattern (define
  + citation resolution — B-T entries cite OE works by short title, a future
  crosswalk to ISWOC/ASPR urns). The older Sean Crist / Germanic Lexicon
  Project digitization (~29 MB plain text, effectively PD: "The copyright has
  expired on all of these texts, and you may download them and use them
  however you please" — germanic-lexicon-project.org) is superseded by the
  Prague edition but is a fallback.

---

## Assessed but not top-two (ingestable-with-friction, lower priority)

### YCOE + YCOEP — the OE prose canon, academic-use terms, new Penn parser family

The York-Toronto-Helsinki Parsed Corpus of Old English Prose (YCOE, ~1.5M
words — Ælfric CH I/II + Lives, Wulfstan, Bede, Boethius, Gregory, Orosius,
the four WS Gospels, five Chronicle MSS, law codes, Benedictine Rule,
Vercelli/Blickling homilies, medical texts) and its poetry sibling YCOEP
(71,490 words). This is where OE *breadth in prose* lives outside DOEC.

- **Format:** Penn-Helsinki labeled bracketing — per text a `.psd` (parsed) +
  `.pos` (tagged) file. **A NEW parser family** (nothing in-tree reads Penn
  brackets), CorpusSearch-style. Real work, well-understood format.
- **Distribution:** Oxford Text Archive — YCOE = OTA 2462 (295 files,
  ~66.7 MB, downloadable `2462.zip` after accepting the OTA agreement), YCOEP
  = OTA 2425.
- **Terms (verbatim):** OTA marks both **"ACA (Academic Use)" — "Attribution
  Required; Noncommercial"**; the OTA user agreement permits "Use and make
  personal copies … only for purposes of non-commercial research or teaching".
  The York corpus homepage adds the layered-copyright caveat: "users are
  reminded that many of the texts in the corpus are subject to copyright
  restrictions" while "We hold copyright in the annotations, and freely grant
  users permission to reproduce the annotations in the course of
  non-commercial scholarly activity." YCOEP states: "available without fee for
  educational and research purposes, but it is not in the public domain."
- **Verdict: SURVEYED — legitimate future packet** (downloadable, research-use)
  but behind both picks: custom OTA terms with no redistribution grant on the
  text layer (posture between `nc` and `research_private` — decide at
  ingest), a new parser family, and heavy content overlap with ISWOC (æls,
  apt, chrona, or, wscp all derive from the same Toronto/York e-texts —
  distinct editions, never dedupe, but the marginal *new-text* value should be
  weighed then). The Helsinki Corpus OE slice (OTA 1477, COCOA-coded plain
  text, same ACA terms) is dominated by YCOE and adds nothing.

### PerseusDL/canonical-angLit — a stray open TEI Beowulf

`gh api` verified: the repo holds exactly one work — Beowulf, TEI, in OE
(`anon.beowulf.perseus-ang1.xml`) **plus an English translation**
(`perseus-eng1.xml`); README states CC BY-SA 3.0 US; last push 2015. Subsumed
by ASPR (pick #2) for the OE text, but the **aligned English translation** may
be worth a look when ASPR ships (P7-4-style parallel doc). SURVEYED, no own
packet.

---

## Not ingestable (license- or format-blocked) — with unblock paths

- **DOEC (Dictionary of Old English Corpus, Toronto)** — the complete
  surviving OE record (~3M OE words, TEI-P5, ~3,000 texts), and the ancestor
  e-text of nearly everything above. **BLOCKED as expected.** The Web Corpus is
  a subscription search product ($75/yr individual, $200/yr institutional, 20
  free logins/yr); the subscription terms state (verbatim, §3,
  store.doe.utoronto.ca/store/doc/webcorpussub.pdf): "Recompiling, copying,
  publication, or republication of the data, or any portion thereof, in any
  form or medium whatsoever, may be done only with specific written permission
  from the Dictionary of Old English project." Library terms additionally
  prohibit systematic downloading/TDM. *Unblock:* (a) written permission from
  the DOE project (the only bulk path, `research_private` at best); (b) NB the
  **2000 DOEC release sits on OTA as record 2488** (~26 MB SGML/TEI-P5,
  "Academic Use — Attribution Required; Noncommercial") — a real
  local-research path worth verifying at any future ingest, same
  no-redistribution posture as YCOE.
- **Old English Poetry in Facsimile** (oepoetryfacsimile.org, Foys/UW-Madison)
  — ~350 works / ~26k lines transcribed+translated, actively maintained, but a
  Digital Mappa web app with **no located data download and no reuse license
  for its transcriptions** ("open-access" = access, not a grant). *Unblock:*
  contact the project for a data grant; ASPR covers the text layer meanwhile.
- **Electronic Beowulf 4.0** (Kiernan) — web app; editorial material "©
  Kevin Kiernan and the British Library" (site 403s fetchers; read via
  snippets — a third-party "CC BY 4.0" catalog claim contradicts the primary
  source, do not trust it). *Unblock:* none realistic; ASPR + facsimile IIIF
  elsewhere.
- **Jebson's Anglo-Saxon Chronicle** (asc.jebbo.co.uk) — the fullest free ASC
  (MSS A–E + common stock), built from TEI P4 sources, but serves **rendered
  XHTML only** and states (verbatim): "Copyright © 1996-2006, Tony Jebson …
  all rights reserved"; last modified 2007, parts "unchecked, and have known
  defects". *Unblock:* email Jebson for the TEI source + a grant. Open
  alternatives are weak: OTA 0817 "selections" (CC BY-NC-SA 3.0, ~850–900 CE
  only, not year-addressable) and Wikisource (CC BY-SA but OE text only for
  MSS E/H, rest is translation). ISWOC's `chrona` (5,939 tokens) is the
  near-term ASC presence.
- **The Digital Ælfric** — commercial/subscription edition (sd-editions.com);
  no open standalone Ælfric edition exists anywhere (verified absence);
  ISWOC's æls + future YCOE are the paths.
- **CoNE / PASE / LangScape** — Edinburgh/KCL research databases:
  non-commercial-only terms (CoNE verbatim: "You may use the CoNE website only
  for non-commercial, non-profit educational and research purposes"), PASE is
  prosopographical metadata (not text), LangScape is post-project with no
  data download. Reference resources, not corpus sources.
- **MENOTA** — confirmed **no Old English** (front page, verbatim: "The
  majority of the texts are Old Icelandic or Old Norwegian, but there are also
  some Old Swedish texts and a couple of Old Danish ones."). Out of scope for
  this axis (stays a future Old Norse lead, 02-sources #21).
- **Universal Dependencies** — **no Old English treebank exists** (verified
  against the UD org repo list; no `UD_Old_English*`, no `ang` language). The
  config-only UD add the packet hoped for is not available. *Unblock:* none —
  watch UD releases; an ISWOC→UD conversion upstream would be the likeliest
  arrival route (and would then be a dedup hazard against pick #1, the
  chu-PROIEL lesson).

---

## What should shape Phase 11/12 planning

- **Pick #1 (ISWOC) is a TOROT-shaped packet:** subclass + manifest + `ang`
  language filter + fixtures (2–3 trimmed real texts incl. a wscp slice for
  the verse-citation assertion). It feeds P11-3 directly: OE Mark is a
  registry entry for the alignment hub, proving the "sixth version = registry
  entry, not code" claim on a *new language*.
- **Pick #2 (ASPR/OTA) is a scout→plan→adapter track:** new small TEI family,
  ordinal citations, single-file HTTP fetch; its CC BY-SA license makes it the
  first *shareable* OE, worth prioritizing for the MCP surface even though
  pick #1 ships first.
- **License posture of the axis:** everything treebanked (ISWOC, YCOE) is
  `nc`-or-stricter; the open material is poetry (ASPR, `attribution`) and the
  dictionary (B-T, `attribution`). Same split the Slavic axis showed — flag it
  in any MCP-coverage claims.
- **Overlap discipline:** the Toronto e-text lineage (DOEC → YCOE → ISWOC)
  means the same OE works will recur across any two ingested OE sources —
  distinct editions are distinct version-URNs, never deduped (conventions §3),
  but each OE packet must state which lineage its texts come from. And if the
  ISWOC adapter targets the syntacticus successor repo, it must scope to the
  `iswoc/` subdir to avoid re-loading proiel/torot.
- **Bosworth-Toller (CC BY 4.0, lemma-keyed CSV)** slots into P11-4 as a third
  lexicon alongside LSJ and Lewis & Short if the dictionary-shelf schema is
  built language-agnostic — worth stating in the P11-4 design note even if OE
  ships later.
