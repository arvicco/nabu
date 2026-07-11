# Improvements register

*A living register of candidate capabilities, born from the strategic reviews
of 2026-07-06 and 2026-07-08. This is NOT the backlog: nothing here is
committed work. Items graduate into a phase at a gate, the way the 07-06
review became Phases 7–8 and the 07-08 plate became Phase 9. Each entry
carries enough context to decide with, honestly including the case against.
Status legend: **candidate** (nobody picked it), **queued** (owner-picked,
awaiting a phase), **gated** (needs an owner decision or hardware),
**register-only** (small known debt, batched opportunistically).*

---

## 1. Research capabilities

### 1.1 Intertext engine — the corpus reads itself  [candidate — Phase 12 proposal]

**What.** Quotation/allusion detection across the whole corpus: index folded
n-grams and rare-lemma co-occurrences per passage; score candidate parallels
by shared rare material (the Tesserae method, well documented in the DH
literature). `nabu intertext <urn>` → ranked echoes across all sources; an
`intertexts` table in the derived layer, rebuilt by the Indexer.

**Why.** The corpus has already produced two accidental finds (a papyrus
school exercise quoting Odyssey 1.1; scholia embedding quoted lines). Nobody
else holds papyri + scholia + literature + treebanks in one store with
stable ids — our intertext hits would be *resolvable citations*, not fuzzy
matches in a paper. Scholia→lost-works, NT→LXX, school-texts→classics are
all real research veins.

**Pros.** Entirely local (SQLite n-gram tables, no ML, no cluster);
compounds with lemma coverage (each lemmatized passage scores better);
foundation for the citation-graph frame (§1.8). Genuinely novel capability
at our corpus mix.
**Cons/costs.** Index size (n-gram tables over 2.1M passages — needs batching
and pruning discipline: rare-material-only indexing, or it balloons);
scoring quality needs tuning against known quotations (a golden set of
attested quotations should be built first — good packet structure: goldens,
then index, then scorer); cross-language intertext (OCS translating Greek)
is a research problem, out of v1 scope.
**Effort.** fable design (scoring + pruning policy) + opus impl; 2–3 packets.

### 1.2 Cross-source alignment hub — parallel Gospels  [SHIPPED — Phase 11 P11-3/P11-5: `align` + nabu_align, NT ≤7 witnesses + OT, architecture §10]

**What.** Extend `--parallel` from *editions of one work within a source* to
*verse-aligned texts across sources*: a citation-mapping layer that knows
Codex Marianus (TOROT) ↔ Greek NT (PROIEL) ↔ Wulfila's Gothic NT (UD) share
book:chapter:verse addressing. `show <urn> --parallel chu,got` → three
columns. Later fed by cheap adapters for the Clementine Vulgate, LXX,
SBLGNT (§2.1).

**Why.** The OCS gospels ARE translations of the Greek we already hold; the
Gothic NT rides in UD. Reading the Vorlage beside the translation is *the*
working method of comparative philology and of learning OCS — and every
byte needed is already on disk. This is the single highest personal-value
item on the register for the owner's stated Slavic axis.

**Pros.** Zero new data for v1; reuses the span-grouping renderer (P8-1b);
MCP `nabu_show` inherits it; each new biblical-corpus adapter multiplies it.
**Cons/costs.** Citation-scheme mapping is genuinely fiddly: sources cite
verses differently (PROIEL sentence ids ≠ verse numbers — the treebank
carries citation metadata per sentence, which must be surfaced into
citable form; versification differences LXX-vs-Masoretic-vs-NT editions are
a known scholarly swamp — v1 should scope to the Gospels where numbering is
stable). Needs a mapping table design (which source-pairs align, keyed how)
— a real fable packet, not config.
**Effort.** fable (mapping design + PROIEL citation surfacing) + opus
(renderer/CLI); 2 packets + optional source adapters.

### 1.3 The reference shelf — dictionaries as data  [SHIPPED — Phase 11 P11-4: LSJ + Lewis & Short, define + nabu_define, citation resolution, architecture §11; Bosworth-Toller queued per oe-survey]

**What.** Ingest the openly licensed classical lexica as a queryable layer:
LSJ, Lewis & Short, Middle Liddell (Perseus lexica repos, CC BY-SA XML),
Monier-Williams for Sanskrit (Cologne CDSL). `nabu define λόγος` (+ MCP
`nabu_define`); entries parsed with their *citations resolved against the
corpus* — LSJ cites Il. 1.1, we hold Il. 1.1, the entry links live.

**Why.** Dictionary + lemma search + concordance = a complete philology
workbench; for a learner-owner, tap-through glossing against real lexica —
not machine guesses — transforms daily reading. The citation-resolution
twist makes it bidirectional: lemma hits can pull their LSJ senses.

**Pros.** License-clean; static data (frozen upstream — sync_policy frozen);
huge usability-per-byte; the citation edges feed the graph (§1.8).
**Cons/costs.** Lexicon TEI is *gnarly* (nested senses, abbreviated
citations in idiosyncratic formats — citation-resolution will be
best-effort with an honest miss-rate; report coverage, don't fake it);
dictionaries are not passages — they need their own storage shape (entries
table, not the passages table) and their own MCP bounds (LSJ entries can be
pages long); Monier-Williams licensing needs the scout treatment (CDSL
terms vary by dictionary).
**Effort.** scout (licenses/formats) + fable (entry model + citation
resolution policy) + opus (parsers per lexicon); 3 packets.

### 1.4 Time and place as axes — HGV metadata  [candidate — Phase 12 proposal]

**What.** Ingest metadata corpora that date and locate texts we already
hold: HGV (Heidelberger Gesamtverzeichnis — dates/provenances for the
papyri, sibling dataset of DDbDP in the same idp.data repo we already
clone), ORACC catalogue dates/places (already in the fixture-planned JSON).
Schema: nullable `date_not_before/not_after`, `provenance` on documents;
`search --before -200 --after -300 --place Oxyrhynchus`; time-sliced
concordances.

**Why.** The corpus is currently timeless; for documentary texts date and
place are half the scholarly value. Language change across centuries,
archive reconstruction, social history — all unlocked by columns, not ML.

**Pros.** The HGV data is *already in the cloned repo* (idp.data carries
HGV XML beside DDbDP) — zero new network; clean schema extension;
immediately useful filters.
**Cons/costs.** HGV dating is messy by nature (ranges, "ca.", multiple
proposals — the model must store honest ranges, not fake precision);
mapping HGV records to DDbDP documents is by identifier convention
(reliable but needs verification); non-documentary sources mostly lack
dates (the axes stay sparse — display honestly). Provenance names need no
gazetteer in v1 (strings, not geo-coordinates; resist scope creep).
**Effort.** opus with fable review of the date model; 1–2 packets.

### 1.5 Fragment-aware search — trigram infix matching  [candidate]

**What.** A character-trigram index over the folded search form enabling
infix/wildcard queries: `search --fragment "]μηνιν αει["` — mid-word
matching for lacunose texts. FTS5 tokenizes words and only prefixes;
papyrologists and epigraphists search *fragments*.

**Pros.** Native search mode for a third of the corpus (921k papyri
passages, future inscriptions §2.3); local, well-understood technique
(SQLite trigram); composes with existing filters.
**Cons/costs.** Index size (trigrams over 2.1M folded passages —
comparable to the FTS index again; fulltext.sqlite3 grows accordingly);
query semantics need care (trigram candidates then verify — standard);
useful mostly for documentary corpora, so consider scoping the index to
those sources (a per-source index flag — honest and cheaper).
**Effort.** opus; 1 packet.

### 1.6 Morphology facets  [candidate — small]

**What.** `search --morph "case=Dat|tense=Aor,mood=Opt" [--lemma X]` over
the treebank annotations (features already stored per token in
annotations_json); extends the P7-5 lemma index with a morph-facet table.

**Pros.** The data is on disk and gold; a grammar learner's power tool
("every aorist optative in the Greek NT"); trivially composes with lemma
search; UD and PROIEL morph vocabularies map cleanly (UD feats are
standardized; PROIEL morphology tags documented).
**Cons/costs.** Two tagset vocabularies to normalize into one query façade
(UD `Case=Dat` vs PROIEL positional morphology — a mapping table, fiddly
but bounded); index rows multiply (passage × token × features — needs the
same dedup thinking as P7-5); only 8% corpus coverage until lemmatize-all
(§3.1) lands.
**Effort.** opus with fable review of the tagset mapping; 1–2 packets.

### 1.7 Vocabulary profiling  [candidate — small]

**What.** Corpus-wide lemma frequency tables (per language, per source);
`nabu vocab <urn-or-range>` → the passage's lemmas ranked by corpus
frequency, flagging rare ones — "learn these twelve words before reading
Odyssey 9". Optionally a personal known-lemmas file for diffing.

**Pros.** Tiny (a GROUP BY over the lemma index); daily learner value;
frequency data also feeds intertext scoring (§1.1: rare = interesting) and
future glossing prioritization.
**Cons/costs.** Same 8%-coverage ceiling until §3.1; the "personal reading
log" direction drifts toward reader-app territory the concept explicitly
excludes — keep it to frequency data and a plain file, no app.
**Effort.** opus; small packet, could ride along with 1.6.

### 1.8 The citation graph  [frame, not a packet — informs 1.1/1.3]

**What.** The unifying long-game frame: every cross-reference in the system
(intertext hits, dictionary citations, scholia references, alignment
links) is an edge between stable URNs. A modest `links(from_urn, to_urn,
kind, score, source)` table — populated by 1.1/1.2/1.3 as they land —
makes the corpus navigable as a graph (`nabu links <urn>`).

**Why noted separately.** No single packet builds "the graph"; the register
exists so each feature lands its edges in ONE shared shape instead of three
private ones. Design the table when the first edge-producer (probably 1.3
or 1.1) is elaborated.

### 1.9 Edition collation — textual criticism support  [candidate — low priority]

**What.** We deliberately ingest the highest edition per work; the other
editions sit on disk. `nabu collate <urn1> <urn2>` — word-level diff of two
editions of the same work (CollateX-style alignment, simplified).
**Pros.** Data on disk; unique offering (variant display over a personal
corpus).
**Cons.** Real collation is a discipline (transpositions, orthographic
noise — our per-language folds help); limited audience unless the owner
does textual criticism; the honest v1 is a folded-word diff, which may
underwhelm. Park until a concrete use case appears.
**Effort.** fable design if ever; defer.

### 1.10 Stylometry  [candidate — lowest priority]

**What.** Burrows' Delta / function-word profiles per document; authorship
and register clustering, locally computable.
**Cons dominate.** Methodologically loaded, needs careful normalization to
mean anything, and no stated owner use case. Register it, revisit only on
demand.

### 1.11 The reconstruction/etymology shelf — PIE and comparativistics  [candidate — P13-10 (b) scout, owner axis: "PIE/comparativistics/reconstructions that we didn't even start touching yet"]

**What.** A shelf whose headwords are *reconstructed* forms (Proto-Slavic
\*bogъ, PIE \*h₃ebʰi) linked to the attested lemmas the library already
holds across languages — the comparativist's join: from богъ in the
Zographensis to \*bogъ to the Iranian loan discussion; from a Gothic
lemma through Proto-Germanic to the same PIE root an OCS word descends
from. Query shape: `nabu define *bogъ` (or a `--reconstructed` flag),
plus the reverse edge on ordinary entries ("descends from \*bogъ; cognates
in got/orv/ru here").

**The data exists, verified (P13-10 Phase A, 2026-07-11).** kaikki.org
ships wiktextract JSONL for the reconstruction pseudo-languages, same
verbatim dual license as the OCS extract ("This data is made available
under the same licenses as Wiktionary - both CC-BY-SA and GFDL"):
- **Proto-Slavic** — `kaikki.org/dictionary/Proto-Slavic/…ProtoSlavic.jsonl`,
  45.4 MB, ~5,195 words, `lang_code "sla-pro"`. Records carry the OCS
  record shape PLUS a structured **`descendants`** tree: \*kara → {East
  Slavic: be/ru/uk ка́ра; South Slavic: **cu** …} with romanizations —
  ready-made reconstruction→attestation edges.
- **Proto-Indo-European** —
  `…/Proto-Indo-European/…ProtoIndoEuropean.jsonl`, 11.5 MB, ~1,781 words,
  `lang_code "ine-pro"`; **Proto-Germanic** (`gem-pro`) also exists (the
  царь chain crosses it: \*cěsařь ← \*kaisaraz ← Caesar).
- Same caveat as wiktionary-cu: the per-language files are flagged
  DEPRECATED (wiktextract #1178) though live; fallback = filter the full
  extract by `lang_code`.

**Two join signals are already in the library.** (i) Forward/text: every
wiktionary-cu entry body deliberately KEEPS its `etymology_text` — 2,617
of 4,615 records carry prose chains naming Proto-Slavic/PIE forms (1,797
Proto-Slavic, 279 PIE). (ii) Reverse/graph: the Proto-* extracts'
`descendants` arrays are machine-readable edges to attested reflexes,
keyed by the same `lang_code`s the catalog speaks (cu→chu, orv, got, ru).
A future packet would ingest the Proto-* extracts through the SAME
`wiktionary-jsonl` family (they parse today — the shape matches), mint a
reconstruction language posture (`sla-pro`/`ine-pro` are not ISO 639-3;
model/validation and the fold table need a decision), and build the
descendants crosswalk as its own derived table (query-time joins, the §11
citation-resolution stance: never store stale links).

**Pros.** License-clean; the parser already exists after P13-10; unique
capability — no other tool joins reconstructions to a private attested
corpus; the owner's explicitly named axis.
**Cons/costs.** Asterisk conventions and cross-extract identity are
messy (\*o(b) vs \*ob); Wiktionary reconstructions are crowd-curated (not
Derksen — and Derksen is Brill-blocked, docs/slavic-survey-2.md); the
language-code posture needs a real design call, not a hack.
**Effort.** fable (identity/posture design) + opus (adapter config +
descendants crosswalk); 1–2 packets. NO adapter in P13-10 by owner scope.

---

## 2. New sources

*(GRETIL shipped in P9-4b; ORACC queued as Phase 10 headline with an
approved fixture plan; UD Birchbark + RNC Middle Russian and CCMH ranked
#1/#2 by the P9-6 survey and queued for Phase 10 consideration. Below:
the rest of the map.)*

### 2.1 The biblical alignment trio: Vulgate, LXX, Greek NT  [SHIPPED — Phase 11 P11-5: vulgate + sblgnt sources, LXX via in-catalog Swete; Rahlfs blocked on CATSS terms]

**What.** Clementine Vulgate (public domain, multiple clean digital
sources), Septuagint (e.g. the Swete/Rahlfs-derived open texts; CCAT or
OpenLXX-lineage — scout verifies which digitization is cleanly licensed),
SBLGNT (free license with attribution) or the public-domain Byzantine
text. All verse-cited; all exist as adapters mostly reusing simple formats.
**Pros.** Fuel for the alignment hub — with these, the Gospels read in six
languages (grc/got/chu/lat + eng translations); huge cross-language value
per adapter-hour.
**Cons.** Edition/versification choices carry scholarly freight (document
what each digitization IS — e.g. SBLGNT ≠ NA28 — and don't pretend
otherwise); LXX digitization licensing needs the honest scout treatment.
**Effort.** scout + 2–3 small opus adapters.

### 2.2 Coptic Scriptorium  [candidate — strong]

**What.** Coptic corpora (Sahidic), TEI + **treebank-annotated**, CC BY.
We already hold 28k unannotated Coptic passages via papyri; this adds
literary Coptic WITH gold lemmas/morphology — joining the lemma-search club
on arrival.
**Pros.** Annotated (multiplies existing features); open license; fills a
real gap (Coptic is currently our 4th-largest language with zero tooling).
**Cons.** New format details (their TEI + relational releases — scout
verifies); Coptic-specific folding questions (supralinear strokes) for
conventions §9.
**Effort.** scout + opus adapter; possibly ConlluParser reuse (they publish
UD-format treebanks too — the cheap path, verify).

### 2.3 Epigraphic Database Heidelberg — Latin inscriptions  [candidate]

**What.** EDH: ~80k Latin inscriptions, EpiDoc TEI, CC BY-SA, bulk
downloads. **Our EpiDoc family nearly reuses directly** (Leiden conventions
= the DDbDP policy work already done).
**Pros.** Third documentary genre (inscriptions beside papyri); parser
mostly exists; dates/places included (feeds §1.4).
**Cons.** Volume (another ~1M passages? — index/backup growth); EDH's
EpiDoc dialect differs from DDbDP's in the details (scout inspects);
inscription URNs need a minting decision (EDH ids are stable — good
candidates).
**Effort.** scout + opus adapter (family reuse).

### 2.4 OpenITI — early Arabic  [candidate — big, needs an owner axis]

**What.** The Open Islamic Texts Initiative: thousands of premodern Arabic
works, open, plain-text-with-markdown-ish markup (mARkdown format).
**Pros.** We hold 256 Arabic papyrus passages as a seed; OpenITI would dwarf
every current source (multi-GB text); Arabic completes the late-antique
Mediterranean picture.
**Cons.** Scale (would double the corpus alone — storage/index/backup
implications); mARkdown = new parser family; RTL display questions
downstream; and honestly: no stated owner research axis in Arabic yet.
Park until the axis exists; the corpus can absorb it whenever.
**Effort.** scout + fable family, when wanted.

### 2.5 TITUS, Manuscript (manuscripts.ru), Sreznevsky  [gated — see docs/slavic-survey.md]

Surveyed and honestly BLOCKED (license/no-export/scans-only). The unblock
paths are noted in the survey: writing for data grants (`research_private`
ingestion — the license class exists for exactly this), or HTR for the
scan-only dictionaries once the cluster lands (§3.4). Owner-initiated
correspondence, not loop work.

---

## 3. Enrichment & the inference-cluster queue

*(Owner decision 2026-07-07: gated until the local inference cluster is
built. Recorded here with the recommended ORDER, which differs from the
original plan.)*

### 3.1 Lemmatize everything — the 13× multiplier  [gated: cluster (or CPU-only earlier)]

**What.** Run Stanza/CLTK (grc, lat models; others as available) over the
~1.96M passages without gold annotations; store as enrichments
(clearly flagged `machine` vs the treebanks' `gold`), journaled in the
P7-1 ledger, replayed after rebuild.
**Why first in the queue.** Every lemma-powered feature — search, concord,
vocab, morph facets, intertext scoring, dictionary linking — currently
covers 8% of the corpus. This single job multiplies five existing features
and two registered ones. Embeddings enable ONE new feature; this upgrades
seven.
**Pros.** Models are free and local (CPU-viable, cluster just makes it
fast); the enrichment plumbing (ledger identity scheme) was designed for
this in P7-1.
**Cons.** Machine lemmas are wrong sometimes (grc models ~90–95% on clean
text, worse on fragmentary papyri — store confidence, display the
gold/machine flag everywhere, never mix silently); Coptic/OCS/Gothic model
availability is spotty (partial coverage is fine and honest); compute time
at 2M passages is real but one-off + incremental.
**Effort.** fable (enrichment model + gold/machine display contract) +
opus (sidecar + runner); the concept's Python-sidecar design (§6) stands.

### 3.2 Embeddings + semantic search  [gated: cluster + owner menu (P8-4 preserved)]

The original P8-4 decision menu stands (model on Sparks vs API; sqlite-vec
vs brute-force; literary-first scope). One addition from the 07-08 review:
embeddings also enable *cross-language* intertext candidates (§1.1's v2),
which pure n-grams cannot — worth weighing when scoping.

### 3.3 Lazy glossing  [gated: owner API key (P8-5 preserved)]

Unchanged: gloss at the point of reading, cache in enrichments, never
batch. The dictionary shelf (§1.3) *reduces* its surface further — human
lexica beat machine glosses for single words; glossing earns its keep at
the passage level.

### 3.4 HTR / ad-hoc pipeline  [gated: cluster + demand]

The concept's original dream (camera → searchable passage), explicitly
demand-driven. The cluster makes local HTR (Kraken, or VLM-based) real.
First concrete candidates already identified: the Sreznevsky scans
(§2.5), any manuscript facsimiles the owner works with. Wake this when a
real stack of images exists.

### 3.5 NER / prosopography over the papyri  [gated: cluster — candidate]

**What.** Person/place/date extraction across 921k documentary passages →
a queryable index of names ("every attestation of a Ζήνων in the Fayum").
**Pros.** The papyri are a social-history goldmine and our largest holding;
pairs beautifully with §1.4's date/place axes.
**Cons.** NER on fragmentary polytonic Greek is genuinely hard (even with
a cluster — expect a noisy first pass; treat as research-grade, flagged);
downstream disambiguation (same name ≠ same person) is a discipline unto
itself — v1 stops at attestation indexing, no identity claims.
**Effort.** cluster-era fable design; note Trismegistos exists as the
professional reference here (licensing restrictive — worth a scout on
their open subsets before building).

### 3.6 ORACC English translations from ATF  [candidate — post-Phase-10]

The P9-5a finding: ORACC's running English lives in the ATF `#tr.en:`
source layer, not the JSON. Once the Phase 10 adapter lands (JSON), a
follow-up can parse ATF translations into aligned parallel documents —
riding the P7-4 mechanism, giving cuneiform the same grc/eng reading
experience. Deferred deliberately from the Phase 10 headline to keep it
bounded.

---

## 4. Platform & infrastructure

### 4.1 Real backup hardware  [gated: owner hardware — standing reminder]

The NabuBackup sparsebundle simulates the external volume **on the same
physical SSD**: it protects against deletion and corruption, not disk
death. When a real external disk arrives: mount it (same volume name =
zero config) and `nabu backup`. Consider a second, off-site/remote target
(the concept's nero/nexo mirror idea) once the first exists. The nightly
launchd template ships ready.

### 4.2 Incremental FTS/lemma indexing  [register-only until it hurts]

Every sync currently rebuilds the whole fulltext index (~2.1M passages,
minutes) — noted as "the future optimization" in SyncRunner since P4. With
per-source syncs now common, per-source incremental indexing (delete
source's rows, reinsert) would cut sync tail latency ~10×. Do it when the
wait annoys, not before; correctness beats speed and the full rebuild is
provably correct.

### 4.3 nabu.ac — the public read-only endpoint  [gated: owner intent — distant]

The MCP surface (P8) deliberately rehearses it: same tools, same license
discipline. Going public changes the legal posture (serving `nc` content
to the world ≠ personal use — the licensing analysis from the 07-06 MCP
review applies) and adds ops surface (auth? rate limits? uptime). Nothing
technical blocks a Tailscale-only JSON endpoint tomorrow; the *public*
version is a policy decision more than an engineering one. Revisit when
sharing becomes a goal.

**Permission points** (owner convention 2026-07-11, P13-11: tracked here
as they are incurred — any future external-access feature must clear each
entry before launch):

1. **freising (CC BY-ND 2.5 SI, `research_private`)** — ND permits private
   transformation but forbids distributing adaptations. Any external-access
   feature must exclude nd-class sources by design (the MCP
   `research_private` default-exclusion is the model) **or** secure
   permission first (contact: Matija Ogrin / Tomaž Erjavec, ZRC SAZU — both
   active CLARIN.SI depositors; a targeted re-license request is plausible).

### 4.4 Enrichment replay wiring  [queued-by-design: lands with 3.1]

`Rebuild#replay_enrichments` has been a documented no-op hook since P1-5;
the P7-1 ledger defined the identity scheme. The first real enricher (3.1
or 3.3) must implement replay — flagged here so it is costed into that
packet, not discovered during it.

### 4.5 Small parser-debt register  [register-only — batch opportunistically]

- **Union-xpath refsDecls** (7 perseus-latin files, P9-2 census): extend
  the P6-1 structural retry's step grammar with `*[self::tei:l or tei:p]`
  union leaf steps.
- **o.trim.2.783-style papyri** (P5-1 census): line numbers as plain text
  ("1.") with no `<lb>` — a tiny DDbDP pre-pass could recover them.
- **tlg0527.tlg048 mis-slugged commentary** (P9-1): upstream labels an
  appendix `1st1K-eng1b`, outranking the real translation — could special-
  case, better reported upstream.
- **heb0001 in greekLit** (P9-1): upstream mis-filing, correctly
  quarantined; report upstream.
- **The ⟦⟧-for-ALL-dels question** (P6-2, conventions §5): rendering every
  `<del>` in Leiden brackets is papyrologically righter but rewrites
  loaded passage text — a corpus-wide journaled revision needing an owner
  decision and a deliberate migration, not a parser patch.
- **UD overlap posture** (P9-6): any future UD expansion must explicitly
  exclude the chu-PROIEL/orv-TOROT conversions (re-loads of native syncs).

### 4.6 Open-sourcing the tooling  [candidate — owner call, zero urgency]

The adapter contract, parser families, retention machinery, and MCP
surface would be genuinely useful to the DH community (no maintained
local-first corpus builder exists in this shape). Costs: README-for-
strangers, issue triage, license choice (code license is still TBD in the
README), and the loss of "personal tool" freedom. Purely an owner
temperament question; the code quality is already publishable.

---

## Proposed graduation order (updated 2026-07-10)

1. ~~**Phase 10**: ORACC adapter + UD Slavic expansion~~ **SHIPPED** (PR #11).
2. ~~**Phase 11 — "the philology workbench"**: alignment hub (1.2) +
   dictionary shelf (1.3) + biblical trio (2.1)~~ **SHIPPED** (PR #12, incl.
   align ranges + WEB English witness); morph facets + vocab (1.6/1.7) were
   NOT taken (phase ran full) — still open, small, cluster-independent.
3. **Phase 12 candidates** (owner picks the headline):
   a. **The OE axis lands**: ISWOC adapter (PROIEL family, near-config-only;
      brings the West-Saxon Mark into the hub as witness #8) + ASPR poetry
      (small new TEI family — Beowulf, Exeter Book, fully open) +
      Bosworth-Toller onto the reference shelf (CC BY 4.0 CSV). All three
      pre-scouted in docs/oe-survey.md.
   b. **"The corpus reads itself"**: intertext engine (1.1) + time/place
      axes (1.4) + fragment search (1.5); links table (1.8) lands with
      whichever edge-producer ships first.
   c. Riders for either: morph facets (1.6), vocab profiling (1.7), CCMH
      (2.2-adjacent, Slavic pick #2).
4. **Cluster arrival** (whenever): lemmatize-all (3.1) FIRST, then
   embeddings (3.2), glossing (3.3), HTR (3.4), NER (3.5).
5. Continuous: sources 2.2/2.3 slot into any phase as capacity allows;
   4.5 debt batches into whichever phase touches the relevant parser.
