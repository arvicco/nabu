# Slavic sources survey II — dictionaries + South Slavic/Slovenian (P13-1, 2026-07-11)

Second Slavic scouting survey, following `docs/slavic-survey.md` (P9-6), which
covered the treebank/OCS-canon axis and produced the UD Birchbark/RNC expansion
(live) and the CCMH pick (P13-2, this phase). This survey covers what that one
did not, driven by the owner's three questions: **can we do more OCS/Slavic? are
there dictionary sources? is there something for South Slavic/Slovenian?**
Three axes: (a) Slavic dictionary sources for the reference shelf, (b) South
Slavic / Slovenian, (c) status re-check of survey-I blocked items.

No bulk fetching was done — page-level `WebFetch`/`WebSearch` and `gh api`
metadata only, per the packet. One small sample was viewed to confirm a format
(the DIACU JSON head, ~1.5 KB). Every load-bearing license below was verified
against the machine-readable source where one exists, not just the landing page
— which mattered (see Freising).

**Bottom line up front — the owner's three questions answered.**

1. **More OCS/Slavic?** Modestly. The OCS-canon gap is already being closed by
   CCMH (P13-2). Beyond it, this survey found ONE genuinely new, clean,
   config-only treebank win (**UD Ruthenian**, `CC BY-SA 4.0`, 1380–1650 —
   recommend THIS phase) and confirmed that no other openly licensed
   machine-readable Church Slavonic edition exists in the Croatian, Serbian,
   Bulgarian or Macedonian recensions — all institutional web-UIs or print/PDF,
   no license grants.
2. **Dictionary sources?** The honest answer: **the scholarly OCS dictionaries
   are not openly available today.** GORAZD (Prague SJS, ~33k entries) is a
   query-only web UI with no content license; the Miklosich TEI edition (41,338
   entries, BCDH/ELEXIS) exists but sits on CLARIN.si as a **metadata-only
   deposit with zero files**; Sreznevsky re-verified scans/query-only; Derksen
   is Brill copyright. The only clean ingest is the Wiktionary OCS extraction
   (kaikki.org, `CC-BY-SA + GFDL`, ~4.5k senses) — real but modest. The two
   high-value unblocks are each **one email away** (BCDH for Miklosich, the
   Prague Institute for SJS) — owner decision, no emails sent per packet rules.
3. **South Slavic/Slovenian?** **Yes — this is where the survey's real finds
   are.** The Freising Manuscripts electronic edition is fully downloadable
   TEI (diplomatic + critical + phonetic transcriptions, six translations, a
   glossary) but is **CC BY-ND** — the survey's most consequential license
   read. CLARIN.SI holds two genuinely open historical-Slovene corpora
   (goo300k `CC BY 4.0` gold, IMP `CC BY-SA 4.0`, 17.7M tokens) — Early Modern
   (1584+), so a scope call for the owner. No Old Slovene or historical South
   Slavic UD treebank exists.

---

## Recommended picks (ranked)

### 1. UD_Old_East_Slavic-Ruthenian — config-only, this phase

The survey's one drop-in win, and the exact shape of the P10-2 expansion: a UD
treebank the `ud` adapter's `TREEBANKS` map does not list, ingestable with
**zero new parser family and zero new fetch path**.

- **Content:** "prosta mova" (Ruthenian — Old Belarusian/Old Ukrainian, the
  western descendant of Old East Slavic), **ca. 1380–1650**: Polotsk letters,
  Lithuanian Metrica Book of Inscriptions vol. 3 (1440–1498), Lokhvitsa
  town-hall book (1654–56) — legal/chancery prose from the Ruthenian Corpus
  partnership. First released UD v2.11 (2022), grown through v2.16 (2025-11).
- **License (verified via `gh api` — README machine-readable metadata block,
  quoted verbatim):** `License: CC BY-SA 4.0` → `attribution` class,
  MCP-surface-safe (per-document override, the P10-4 pattern — the `ud` source
  class stays `nc` for the PROIEL-derived treebanks).
- **Repo:** <https://github.com/UniversalDependencies/UD_Old_East_Slavic-Ruthenian>
  (GitHub license field reads NOASSERTION; the authoritative grant is the UD
  README metadata, same as Birchbark/RNC at P10-2 fixture time).
- **Dedup:** genuinely new — no text overlap with TOROT (OCS/OES canon),
  PROIEL (Marianus), Birchbark (1025–1500 novgorod letters) or RNC (Muscovite
  Middle Russian). Ruthenian is the *third* branch of the East Slavic
  diachrony; the corpus currently holds the other two. Language code is `orv`
  in UD (treebank id `orv_ruthenian`).
- **Effort:** one `TREEBANKS` entry + one trimmed fixture + the license
  verification at fixture time — the P10-2 recipe verbatim, smallest possible
  packet. Extends the dedup-guard comment (still no chu-PROIEL/orv-TOROT).
- **Verdict: RECOMMEND THIS PHASE** — rides beside CCMH exactly the way P10-2
  rode beside ORACC. (Strictly East Slavic, not South Slavic — flagged because
  the packet asked for any old-variant UD treebank we missed, and this is it.)

### 2. Freising Manuscripts / Brižinski spomeniki (eZISS) — the personal-relevance pick, blocked-for-redistribution, decide posture

The oldest Slovene — and the oldest Latin-script Slavic — text (ca. 972–1039
CE), as a genuinely excellent TEI critical edition: *Brižinski spomeniki:
Elektronska znanstvenokritična izdaja*, ed. Matija Ogrin, TEI encoding Tomaž
Erjavec (ZRC SAZU / IJS, ed. 1.0, 2007). Landing:
<https://nl.ijs.si/e-zrc/bs/index-en.html>.

- **Access:** fully downloadable, no auth: `bs.zip` (complete, with audio +
  facsimiles), `bs-text.zip` (text only, ~5 MB), and a browsable `tei/` folder
  (~40 XML files): diplomatic (`bsDT*`), critical (`bsCT*`), phonetic (`bsPT*`)
  transcriptions, translations into six languages (`bsTR-{eng,ger,ita,lat,pol,slv}`),
  glossary/lexicon (`bsLX*`), word-list (`bsWV*`).
- **License — the survey's key catch.** The English HTML page says
  "Attribution-Share Alike 2.5 Slovenia" — **the page is wrong.** The TEI
  source's own `<availability>` (verified directly in `tei/bs.xml`) reads,
  verbatim: *"Avtorske pravice za besedilo te izdaje ureja licenca Creative
  Commons Priznanje avtorstva-Brez predelav 2.5 Slovenija"* with the URL
  `http://creativecommons.org/licenses/by-nd/2.5/si/` — **CC BY-ND 2.5
  Slovenia** (NoDerivs). The machine-readable header is authoritative.
  Facsimiles © Bayerische StaatsBibliothek München (Clm 6426); audio © ZRC
  SAZU / Radio Slovenija.
- **What ND means for nabu:** local ingestion for private research is lawful
  (CC ND restricts *sharing* adaptations, not making them privately), but the
  transformed corpus form could never be redistributed and the passages must
  stay off any redistribution surface — an `nc`-tier-or-stricter posture
  (MCP-excluded at minimum; honest mapping decided at ingest, `research_private`
  is the conservative reading). The clean unblock: **one permission email to
  Matija Ogrin / Tomaž Erjavec (ZRC SAZU)** — both active CLARIN.SI
  depositors, a targeted re-license for a derivative corpus edition is
  plausible. No email sent (packet rules); owner's call.
- **Format/effort:** TEI **P4** (`<!DOCTYPE TEI.2 SYSTEM "tei2.dtd">`,
  `<TEI.2 id="bs">`) — NOT P5/EpiDoc, with ZRCola private-use-area glyph
  mappings documented in the encodingDesc. A small bespoke family (or a P4
  pre-normalization step), sized small by the corpus (~1,000 words across BS
  I–III) but not trivial. Three parallel transcription layers + translations
  raise the same alt-edition/witness questions the alignment hub already
  answers.
- **Dedup:** zero overlap with anything held — Latin-script Old Slovene is a
  new language axis (`sl`-ancestor), not the Cyrillic/Glagolitic OCS canon.
- **Verdict: LATER, with a decision gate.** Either (a) owner emails ZRC SAZU
  for a derivative grant (best), or (b) ingest under the ND-honest restricted
  posture. Outsized personal relevance; smallest text in this survey; the
  license, not the effort, is the gate. eZISS siblings (Škofjeloški pasijon
  1725–27, Kapelski pasijon, oath texts, Zois correspondence) are the same
  deal: open TEI P4 downloads, per-edition `<availability>`, Škofja Loka
  verified also CC BY-ND 2.5 SI — assume ND family-wide unless an edition
  proves otherwise.

### 3. goo300k — gold historical Slovene, cleanest license of the survey

*Reference corpus of historical Slovene goo300k 1.2* (Erjavec, JSI), CLARIN.SI
<http://hdl.handle.net/11356/1025>.

- **License (verified on the deposit page, verbatim):** "Creative Commons -
  Attribution 4.0 International (CC BY 4.0)" → `attribution`, MCP-safe.
- **Content/format:** **89 texts / ~294k words, 1584–1899**, manually
  annotated: modernized form + lemma + POS + archaic-vocabulary notes per
  word, page links to facsimiles. TEI P5 (`goo300k-tei.zip`, 7.1 MB) +
  vertical. Open download, no auth.
- **Effort:** TEI P5 but the IMP schema, not EpiDoc/CTS — a small bespoke TEI
  profile (page/word-level annotations; the token layer could feed the lemma
  index the way treebanks do).
- **Dedup:** none — Early Modern Slovene is absent from the corpus.
- **Verdict: LATER, owner scope call.** The library's charter is ancient
  texts; 1584–1899 is Early Modern print. Precedent cuts both ways: RNC
  Middle Russian (to 1700) is already held, so the 16th–17th c. slice is
  defensible; the 19th c. tail is clearly beyond. If the owner wants the
  Slovenian axis, this is its cleanest-licensed foundation.

### 4. IMP — the big historical-Slovene corpus (goo300k's superset)

*Digital library and corpus of historical Slovene IMP 1.1* (Erjavec, JSI),
CLARIN.SI <http://hdl.handle.net/11356/1031>, project <https://nl.ijs.si/imp/>.

- **License (verified, verbatim):** "Creative Commons -
  Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)" → `attribution`.
- **Content/format:** **658 texts / 17,723,566 tokens / ~45,000 pages,
  1584–1919.** TEI P5 (annotated corpus zip 150 MB) + vertical + HTML
  library. Annotation is *automatic* (trained on goo300k) — errors expected,
  unlike goo300k's gold.
- **Verdict: LATER, behind goo300k** — same scope call, gold before silver,
  and 150 MB of 19th-c.-heavy material is the weakest scope fit in this
  survey. The companion *Lexicon of historical Slovene* (imp25k, 11356/1032)
  would serve normalization, not the dictionary shelf.

### 5. Wiktionary OCS extraction (kaikki.org) — the one ingestable dictionary

- **Content:** the wiktextract (Ylönen) machine-readable extraction of English
  Wiktionary's Old Church Slavonic entries: **~4,548 senses / ~4,100 lemmas**
  — headword, POS, senses, forms. JSONL (one JSON object per sense), open
  download. <https://kaikki.org/dictionary/Old%20Church%20Slavonic/>.
- **License (kaikki.org/dictionary/, verbatim):** the data is "made available
  under the same licenses as Wiktionary - both CC-BY-SA and GFDL" (+ an
  academic citation request for wiktextract). → `attribution` (SA).
- **Fit:** `content_kind :dictionary`; needs a **small new JSONL family** —
  the shelf's third format after TEI (LSJ/L&S) and CSV (Bosworth-Toller).
  Language `chu`; citations start empty (Wiktionary quotes are unanchored) —
  the Bosworth-Toller precedent exactly. Folding: OCS Cyrillic + jer/yus
  handling would need a conventions §9 entry.
- **Honesty:** a crowd glossary, NOT a scholarly critical dictionary — no
  attestation apparatus, coverage far below SJS/Miklosich. It would make
  `define` light up for `chu` lemma hits (TOROT/PROIEL/CCMH gold lemmas →
  glosses), which is real value, but it is the fallback, not the prize.
- **Verdict: LATER** — best bundled into one dictionary packet with Miklosich
  if the BCDH unblock lands (below); on its own it is a modest win.

### Flagged, not ranked

- **MEMIS 1.0** (CLARIN.SI 11356/1376, Pobežin) — *Epigraphic corpus of
  medieval/early-modern inscriptions in Slovenia*: 51 inscriptions,
  1222–17th c., Koper/Piran, **Latin** language, TEI, license verbatim
  "Creative Commons - Attribution-ShareAlike 4.0 International (CC BY-SA
  4.0)". Tiny (~156 KB) and Latin — belongs to a future epigraphy/Latin
  breadth decision, not the Slavic axis.
- **CroALa** (Croatiae auctores Latini, Jovanović et al.) — ~5.6M words of
  Croatian **Latin**, TEI, **CC-BY**, on GitHub
  (`nevenjovanovic/croatiae-auctores-latini-textus`) + Zenodo. Fully open and
  clean — but Latin, not Church Slavonic; noted for a future Latin-breadth
  phase.

---

## Axis (a) — the dictionary shelf: what exists and what blocks it

The reference shelf holds TEI (LSJ, Lewis & Short) and CSV (Bosworth-Toller)
precedents; `DictionaryLoader` takes any adapter with `content_kind
:dictionary`, citations optional (architecture §11). What could occupy the
Slavic slot:

| Candidate | Format | License (verbatim/status) | ~Entries | Verdict |
|---|---|---|---|---|
| GORAZD hub: SJS + Cejtlin + Greek-OCS index | web query UI (Gulliver) | **none** — only GDPR/cookie text; the advertised GNU GPL covers the *software tools*, not the data | ~33k (SJS) | BLOCKED |
| `utajum/old-church-slavonic-dictionary` (GitHub) | JSON, 55 MB | **none** (no LICENSE; unauthorized GORAZD scrape — GORAZD record ids, card-scan paths in the data) | 33,036 (counted) | BLOCKED (inherits GORAZD's) |
| Miklosich, *Lexicon palaeoslovenico-graeco-latinum* — BCDH/ELEXIS TEI | TEI (Lex-0) | **metadata-only deposit**: CLARIN.si 11356/1666 lists 0 files, no `dc:rights` (verified on the record page + scout REST check `"bitstreams":[]`) | 41,338 | BLOCKED (data not released) |
| Sreznevsky, *Materialy* (re-check) | oldrusdict.ru query UI / PD page scans | none stated on oldrusdict.ru; scans PD by age | 40,000+ | UNCHANGED — not machine-readable |
| Derksen, *Slavic Inherited Lexicon* (Brill 2008) | print / Glossword XML | Brill copyright; the Zenodo Glossword aggregation is licensed "Other (Not Open)", README: "Please be careful with the copyrights!… explicitly discouraged to use the dictionaries in any commercial context!" | — | BLOCKED (copyright) |
| **Wiktionary OCS via kaikki.org** | **JSONL** | "made available under the same licenses as Wiktionary - both CC-BY-SA and GFDL" | ~4,548 senses | **INGESTABLE** (pick #5) |

**GORAZD in detail** (the packet's lead): the Old Church Slavonic Digital Hub
(gorazd.org, Institute of Slavonic Studies, Czech Academy; NAKI II project,
2016–2022) holds the digitized **SJS** (*Slovník jazyka staroslověnského* —
the 4-volume Prague lexicon, the most comprehensive OCS dictionary in
existence), the **Cejtlin** *Staroslavjanskij slovar'* (as "Dictionary of the
Oldest OCS Texts"), the **Greek–OCS index**, and the scanned card archive.
**Correcting the packet lead: Miklosich and Sreznevsky are NOT in the hub.**
Access is exclusively the Gulliver query UI — no download, no API, no content
license anywhere on the site; no LINDAT/CLARIAH-CZ data deposit exists (the
Academy's ASEP record is CC0 *metadata only*). Unblock: a data-sharing
agreement with the Slovanský ústav AV ČR — the single highest-value Slavic
dictionary unblock there is, since the data is already structured (the scrape
proves it: per-entry Greek/Latin equivalents + five-language glosses).

**The nearest prize is Miklosich, not SJS.** The text is PD by age (1862–65);
BCDH (the TEI Lex-0 group) has already done the TEI conversion — 41,338
entries with Greek and Latin equivalents; the deposit is announced on CLARIN.si
but carries zero files. One email to BCDH/ELEXIS (or repo-help@clarin.si)
asking them to complete the deposit could yield a large scholarly OCS
dictionary that **drops into the existing TEI dictionary adapter family** with
no new format work. That is the recommended dictionary-shelf path; kaikki (#5)
is the fallback available today.

---

## Axis (b) — South Slavic / Slovenian: full findings

The ranked picks (#2–#4) carry the Slovenian core. The rest of the axis:

- **eZISS scope** (<https://nl.ijs.si/e-zrc/>): historical editions = Brižinski
  spomeniki (~1000), Škofjeloški pasijon (1725–27), Kapelski pasijon (17th c.),
  municipal/market-town oath texts (17th–19th c.), Zois correspondence
  (1780s–1810s), Slomšek sermons; modern editions (Cankar, Podbevšek) out of
  scope. All ship open TEI P4 zips; the portal's "permanent public use"
  statement is access, not a license — per-edition `<availability>` governs,
  and both verified editions are **CC BY-ND 2.5 SI**. One permission
  conversation with ZRC SAZU likely covers the whole family.
- **Croatian Church Slavonic** (Staroslavenski institut, Zagreb): the RCJHR
  dictionary (*Rječnik crkvenoslavenskoga jezika hrvatske redakcije*) is
  published as **scanned-page PDFs** (letters A–I; only from fascicle 14 is a
  searchable layer "being prepared"); the underlying 60-source Glagolitic
  corpus (11 breviaries, 4 missals, 3 psalters, 3 rituals, 15 miscellanies, 26
  fragments) has **no public download, no CLARIN handle, no license**. BLOCKED;
  unblock = written request to the Institute (info@stin.hr).
- **Serbian Church Slavonic** (SANU): an electronic corpus of 12th–18th c.
  Serbian (~450k words medieval slice, morphologically annotated per the
  project's papers — hagiographies, charters, church poetry) exists
  *internally* for the SANU dictionary project; **no public release, no
  license, no repository**. BLOCKED; unblock = contact the Institute for the
  Serbian Language.
- **Bulgarian/Macedonian** (Sofia): **Cyrillomethodiana / histdict**
  (histdict.uni-sofia.bg) — ~147 texts, 10th–18th c., plus the digitized
  *Starobălgarski rečnik* — web-search UI only, no export, footer verbatim
  "© Софийски университет „Св. Климент Охридски" 2011-2022" — a bare
  copyright notice, no grant. BLOCKED; unblock = request to the Sofia team.
  No separate Macedonian/Ohrid-recension open edition exists.
- **DIACU** (ITSERR/CNR, BSNLP 2025) — the one new machine-readable ChSl
  dataset found: 652 documents across four diachronic periods
  (OCS → Church Slavonic → New ChSl → Ruthenian) as a single 22.8 MB JSON
  (`MariaCassese/DIACU`; format confirmed on a ~1.5 KB head sample). **No
  LICENSE file** (GitHub `license: null`; only the *paper* is CC BY 4.0), and
  the `Source` fields show the OCS core is **re-packaged TOROT/PROIEL already
  held** (the sampled Zographensis record points at
  `torottreebank/treebank-releases`). BLOCKED (unlicensed); its only novel
  slices are the New-ChSl/Ruthenian periods. Unblock: ask the author to add
  the license; low priority given the overlap.
- **Charters:** **no `monumenta.si` exists.** Slovenian medieval charters live
  on Monasterium.net (e.g. the Maribor archive's Listine) as **facsimile
  images + CEI metadata**, transcriptions sparse, licensing per institution —
  not a text corpus. The machine-readable medieval-Slovenia text resource is
  MEMIS (flagged above).
- **UD:** the full UniversalDependencies org list was checked (`gh api`) —
  Slovenian-SSJ/SST, Croatian-SET, Serbian-SET are all modern → out of scope;
  **no Old Slovene or historical South Slavic treebank exists.** The one
  historical find is Ruthenian (pick #1, East Slavic).

---

## Axis (c) — survey-I blocked items, status re-check (2026-07-11)

- **obdurodon Codex Suprasliensis — UNCHANGED.** License still verbatim
  "Creative Commons BY-NC-SA 3.0 Unported License" on the site; still no bulk
  download and no data repo (`gh api` over the obdurodon account: 5 repos,
  none Suprasliensis data; global repo search surfaces only the third-party
  `StabiBerlin/Stanza-NLP-Supr`, itself unlicensed). That third-party project
  *demonstrates* the per-folio "Raw XML" crawl works (its wget harvest +
  ~977 KB proofed text) — the crawl path survey I described remains viable
  under BY-NC-SA for local research, unchanged verdict: worthy future packet,
  `nc`, behind cleaner wins.
- **Манускриптъ / manuscripts.ru — UNCHANGED, arguably degraded.**
  `manuscripts.ru` now redirects to `io.udsu.ru` with a host-mismatched TLS
  cert; `manuscript.udsu.ru` no longer resolves (DNS); the reachable UdSU
  portal is not the manuscript app. No export, API or license appeared.
  (Honest caveat: the live app could not be rendered this pass — "unchanged"
  is inferred from reachability + literature.) Unblock still: write to the
  Izhevsk team.
- **TITUS — UNCHANGED.** Terms still verbatim "can be used freely for
  scholarly purposes, provided that they are quoted as sources" / "must not be
  used for any kind of commercial usage", some texts members-only; the UB
  Frankfurt e-media terms add "Volltexte dürfen weder elektronisch noch in
  gedruckter Form an Dritte weitergegeben und nicht öffentlich zugänglich
  gemacht werden" (no transfer to third parties, no public posting). No bulk
  endpoint, no new license; front page still stamped 2003. `research_private`
  at best, unchanged.

---

## Blocked list (one line each, unblock path)

- **GORAZD / SJS + Cejtlin + Greek-OCS index** — query-only, no content
  license → data-sharing agreement with the Institute of Slavonic Studies
  (Prague); the highest-value dictionary unblock.
- **Miklosich TEI (BCDH/ELEXIS)** — CLARIN.si 11356/1666 is metadata-only
  (0 files, no rights field) → email BCDH/ELEXIS to complete the deposit;
  would fit the existing TEI dictionary family.
- **utajum SJS scrape** — machine-readable but an unlicensed GORAZD derivative
  → same unblock as GORAZD (never ingest the scrape without it).
- **Sreznevsky** — re-verified: oldrusdict.ru is query-only/no-terms, scans PD
  → unchanged; HTR/OCR reconstruction remains the only path.
- **Derksen (Brill)** — copyright; Glossword/Zenodo aggregation "Other (Not
  Open)" → Brill license, not realistic.
- **Freising / eZISS family** — CC BY-ND 2.5 SI (verified in the TEI source;
  the English HTML mislabels it BY-SA) → permission email to Ogrin/Erjavec
  (ZRC SAZU), or ingest under a restricted local-only posture.
- **Croatian ChSl (Staroslavenski institut)** — PDF-image dictionary, corpus
  unpublished, no license → written request to the Institute.
- **Serbian ChSl (SANU)** — internal corpus, no release → contact the
  Institute for the Serbian Language.
- **Bulgarian ChSl (Cyrillomethodiana/histdict, Sofia)** — web-UI only, bare
  © notice → request bulk export + license from the Sofia team.
- **DIACU** — clean 652-doc JSON, no LICENSE, mostly re-packaged TOROT →
  ask the author for a license; low value net of overlap.
- **Monasterium charters** — images + CEI metadata, not text → out of scope
  (transcription project would be needed).
- **obdurodon / Манускриптъ / TITUS** — UNCHANGED from survey I (axis c
  above).

---

## Dedup vs current holdings

| Find | Overlap with torot/proiel/ccmh/ud holdings | Net-new |
|---|---|---|
| UD Ruthenian | none (third East Slavic branch; different texts from Birchbark/RNC/TOROT) | all of it |
| Freising (eZISS) | none (Latin-script Old Slovene; no OCS canon contact) | all of it |
| goo300k / IMP | none (Early Modern Slovene) | all of it (scope call) |
| kaikki OCS dictionary | complements, not duplicates: glosses for the `chu` lemma layer TOROT/PROIEL/CCMH carry | entry set |
| MEMIS / CroALa | none (Latin) | out of axis |
| DIACU | **high** — OCS core is TOROT/PROIEL re-packaged | only New-ChSl/Ruthenian slices |
| obdurodon Suprasliensis | TOROT Suprasliensis (alt edition — never dedupe, but not new coverage) | apparatus/Greek layer |
| GORAZD/Miklosich/Sreznevsky (if unblocked) | none — the dictionary shelf holds no Slavic lexicon | all of it |

---

## Recommendation for Phase 13 vs later

**This phase: pick #1 only** — UD Ruthenian as a config-only rider (the P10-2
recipe: one `TREEBANKS` entry, one fixture, license verified at fixture time),
beside the already-queued CCMH (P13-2). Everything else is gated on owner
decisions, not engineering:

- **Freising**: decide ND posture — permission email (best) vs restricted
  local ingest; then a small P4 packet next phase.
- **Dictionary shelf**: the recommended move is the **Miklosich unblock email**
  (BCDH); if it lands, one packet ships Miklosich (existing TEI family) +
  kaikki OCS (small JSONL family) together. Without it, kaikki alone is a
  modest standalone packet.
- **goo300k/IMP**: owner scope call on Early Modern Slovene at the phase
  review; goo300k first if yes.
- **South Slavic ChSl recensions**: nothing to build — three institutional
  contacts documented if the owner ever wants to pursue them.
