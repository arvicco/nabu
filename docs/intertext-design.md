# Intertext design — the corpus reads itself (P14-7)

The Phase 15 planning input. This document re-founds four engine-shaped
register entries (improvements §1.1 intertext, §1.4 time/place, §1.5
fragment search, §1.8 links) under the owner-endorsed persona frame of
2026-07-12, adds the three capabilities that frame surfaced (collation,
formula mining, cognate-in-parallel), and prices everything against the
LIVE corpus — every number below is measured, not guessed. Probes ran
read-only on 2026-07-12 (scripts in the session scratchpad; quoted inline).

**The corpus at measurement time.** 3,762,778 passages / 84,446 documents;
626.5M folded chars, ~98.2M folded tokens (space-split approximation).
`passage_lemmas`: 2,619,049 rows over 388,732 gold-lemmatized passages
(10.3% of the corpus), 121,260 distinct folded lemmas. `alignment_refs`:
141,382 rows (nt 8,008 refs / ot 30,595 / psalms 2,538).
`dictionary_reflexes`: 78k-order edge rows incl. got 2,225, cu 4,531,
plus proto-to-proto (gem-pro 2,346, sla-pro 1,209, ine-pro 6,071).
fulltext.sqlite3 = 1.7 GB, of which (dbstat) FTS content copy 1,077 MB,
FTS inverted index 326 MB, passage_lemmas 212+44 MB, alignment_refs 21 MB.

**The design's one big finding, up front.** The intertext engine the
register imagined — a materialized corpus-wide n-gram table with pruning
discipline — is not needed. The EXISTING word-level FTS index answers
per-passage parallel queries in 1–111 ms end-to-end (measured below), and
per-slice streaming handles batch mining without any index at all. Phase 15
should ship query surfaces, not schema.

## 1. `parallels <urn>` — passage-anchored quotation/allusion finding

**Persona and question.** A classicist reading a passage asks about THIS
passage: "who quotes this? where does this line echo?" The register's §1.1
framed the engine corpus-first (build index, then query); the persona frame
inverts it: interactive-first, batch mining second. That inversion is what
makes the measured architecture below possible.

**Algorithm options.**
(a) *Materialized n-gram inverted table* (the §1.1 original): ~95M 4-gram
instances at 98.2M tokens; naive storage 2.5–3 GB + index. Pruning to
cross-passage grams only: on the Homer slice, 26,258 of 342,624 distinct
4-grams (7.7%) recur across passages — but a 2-work slice underestimates
the corpus-wide rate, and the table still goes stale on every sync.
(b) *Query-time per-gram FTS phrase probes*: fold the anchor passage, emit
its word n-grams, run each as a quoted FTS5 phrase MATCH against the
existing index, score candidates by shared-gram count weighted by rarity
(1/document-frequency — the df comes free from each probe's hit count).
(c) *Tesserae-style rare-lemma co-occurrence* over `passage_lemmas`:
passages sharing ≥2 rare lemmas with the anchor — inflection-proof, gold
slice only.

**Pick: (b) as the engine, (c) as the lemma-aware second signal. No new
n-gram schema.** Measured on the live 3.76M-passage index:

- Odyssey 1.1 (8 tokens → 5 4-grams): **1 ms** total; finds Polybius
  12.27.10 quoting the proem, a "Homeri loci similes" compilation, and
  Themistius — resolvable citations, exactly the §1.1 promise.
- John 1:1 (17 tokens → 14 grams): **74 ms**; finds canonical John,
  Clement of Alexandria, Eusebius, Athanasius, and Irenaeus fragments —
  the NT→Fathers reception in one query.
- Thucydides 1.9.2 (120 tokens → 117 grams): **111 ms**; top non-self hit
  shares 57 of 117 grams — Dionysius of Halicarnassus's essay on
  Thucydides, quoting him at length. Per-gram cost 0.1–16 ms (median
  0.2–4 ms depending on gram frequency).
- Matthew 4:4 (20 tokens → 17 grams): **10 ms**; finds Luke 4:4, Philo,
  Origen twice — and, once elision marks are stripped (next paragraph),
  **LXX Deuteronomy 8:3 ties canonical Matthew at 9 shared grams**: the
  LXX→NT→Fathers chain demonstrated end-to-end within Greek.

**Two measured correctness riders.**
(i) *Elision folding.* SBLGNT folds the elision apostrophe as U+02BC (a
letter to the unicode61 tokenizer: "επʼ" is one token) while
First1KGreek/Swete uses U+2019 (punctuation: "επ"). Surface grams therefore
miss across editions until apostrophes are stripped at gram-build time —
without the fix the LXX hit above drops out of the top ranks. Cheapest fix
is in `parallels`' own gram builder; folding U+02BC in text_normalized
(conventions §9) is the deeper fix but re-mints shas — a fable decision,
not a rider.
(ii) *Duplicate witnesses.* The corpus deliberately holds the same text
multiple times (PROIEL greek-nt ≡ UD greek-proiel; multi-edition works).
Measured: every probe's top ranks fill with these. Ranking must group by
document (and ideally by work) with the duplicates listed under one hit.

**Lemma-grams vs surface-grams, honestly.** For verbatim quotation in
highly inflected languages, surface grams over the folded index WORK — the
quotations above are real. Lemma n-grams (sequence-of-lemmas shingles)
would catch re-inflected/reordered allusion, but only 10.3% of the corpus
carries gold lemmas (~3.2M lemma tokens: 388,732 passages × 8.2 avg — a
materialized lemma-gram index over the gold slice is only ~2–3M rows /
~100 MB if ever wanted). The cheaper v1 signal is (c): anchor's lemmas →
global df → keep rare → passages sharing ≥2. Measured: **18 ms** once the
anchor's lemmas are in hand — but the anchor lookup itself took 1.7 s
because `passage_lemmas` indexes only lemma_folded. **Rider: add a
passage_id (or urn) index to passage_lemmas** (~30–45 MB by analogy with
the existing index; also needed by item 6).

**The cross-language quotation problem, framed honestly.** Three tiers:
(1) *Within-language across corpora* — works today (all probes above; the
LXX→NT→Fathers vein is Greek all the way down). (2) *Translation-aligned
scripture* — already solved structurally by the alignment hub: `align`
shows the Greek verse beside OCS/Gothic/Latin; `parallels` should print a
"this passage is verse X, aligned witnesses exist" pointer rather than
pretend to discover it. (3) *Free-form cross-language allusion* (a Church
Father paraphrasing LXX in Syriac word order, OCS homily echoing a Greek
original we hold) — NOT solvable by symbolic n-grams; no shared surface or
lemma vocabulary exists. This is the embeddings/cluster line (see the menu:
what waits).

**Batch mode (second mode, not first).** Corpus-wide mining = loop the
interactive engine over anchor passages of a slice, or stream per-slice
in-memory counting (item 5's machinery — 0.6 s per 200k tokens measured).
Full-corpus grc (37.6M tokens) extrapolates to ~1–2 min as a batch run, no
index. Batch output persists as links (item 7); interactive output does not.

**Reuses.** Query::Search's index + CatalogJoin + Result/snippet machinery;
Query::Proximity's fold-both-sides discipline; passage_lemmas; the
frequency thinking from vocab (§1.7). MCP: `nabu_parallels`, same contract.

**Cost.** Zero new tables (one new index on passage_lemmas). Effort:
**1 opus packet** (CLI + MCP + rarity scoring + dedupe + elision-stripping
gram builder + tests incl. a golden quotation set from the probes above);
optional small rider for the lemma-co-occurrence signal if not in v1.

## 2. Collation view — witness diff over the alignment hub

**Persona and question.** The slavist/text-critic at a verse: "how exactly
do the witnesses differ?" `align` renders the columns; the eye still does
the diffing. The hub has done the hard part (alignment); collation is a
renderer.

**Measured collatable surface.** NT verses by same-language witness count:
grc **7,643** verses with ≥2 Greek witnesses (PROIEL × SBLGNT), lat
**6,974** (PROIEL × Vulgate), chu **3,764** (PROIEL Marianus × up to four
CCMH codices). 2,464 NT verses carry ≥10 witnesses overall (max 13).
MARK 2.3 in chu, live:

    proiel:marianus      Ꙇ придѫ къ немоу носѧште ослабленъ жилами…
    ccmh:marianus:mar    *J pridO k& nemu nosESte oslablen& Zilami…
    ccmh:zographensis    *(J pridoSE k& n^emu nosESte oslabl^ena Zilami…
    ccmh:savvina         (i pridoSE k& nemu nosEqe (oslabena Zilami…
    ccmh:assemanianus    */i pridO k$ nemu nosEqe /oslablena ZIlamI…

Real variation is right there (aorist придѫ vs pridoSE = pridošę;
ослабленъ vs oslabena) — and so is the honesty problem.

**The transliteration-vs-Cyrillic reality (measured).** The conventions-§9
fold does NOT bridge scripts: Cyrillic stays Cyrillic while Helsinki ASCII
merely downcases — and downcasing DESTROYS information (Helsinki S=š vs s,
E=ę vs e collapse). Folded-token diff across the script boundary would be
100% noise; folded diff even between two CCMH witnesses conflates real
variants. Therefore: **diff on RAW tokens, within one script family only;**
cross-script witnesses render side-by-side, aligned but undiffed, stated
plainly ("different transcription systems — not collated"). A deterministic
Helsinki→Cyrillic normalization layer is possible future work (the CCMH
README documents the system) but is a per-source enrichment decision, not
this packet.

**Edit grain.** Word-level LCS over raw tokens (punctuation dropped), base
witness = first in registry order or `--base URN`; variants render as
CollateX-simplified apparatus (base text with per-witness readings marked;
transpositions honestly as delete+insert). Sub-word (character) grain
rejected for v1: orthographic noise swamps it in these traditions.

**Surface.** `align REF --collate [--base URN]` (a renderer flag, not a new
lookup model — the P11-8 range grammar composes for free). MCP: a
`collate: true` arg on `nabu_align`.

**Cost.** Zero schema; ≤13 witnesses × ~20 tokens per verse — query-time
LCS is trivial. Effort: **1 opus packet.**

## 3. The timeline — generalized, not HGV-only

**Persona and question.** The historical linguist and the documentary
historian: "only 2nd-century texts", "only Oxyrhynchus", "plot this word
across centuries." The register's §1.4 scoped this to HGV; the measured
reality is that FIVE sources carry extractable dating today:

| source | coverage (measured) | shape |
|---|---|---|
| HGV (papyri) | 63,925 / 66,261 records (96.5%) machine-dated | `origDate notBefore/notAfter` (±precision) ~2/3 of sampled records, exact `when` ~1/3; `origPlace` + provenance placeName with Trismegistos/Pleiades refs in 200/200 sampled; joins DDbDP by `ddb-hybrid` idno ↔ urn triple (verified: `sb;24;16194` ↔ `urn:nabu:ddbdp:sb:24:16194`) |
| ORACC | 24,639 / 25,502 catalogue records (96.6%) | `date_of_origin` regnal ("Esarhaddon.000.00.00", "Tiglath-pileser3…") or `period` strings ("9th-8th century") — needs a small regnal→year mapping table (bounded, standard Assyriological chronology) |
| goo300k | all documents | year in urn AND title ("…— Zschokke, Heinrich, 1847"), publication year |
| IMP | all documents | same convention (same corpus family) |
| TOROT chronicles | per-DIV annals | div titles ARE annal years ("6360: Mikhail…" — Anno Mundi; CE = AM − 5508), verified in lav.xml — dating at PASSAGE-RANGE grain within one document |

**Schema pick.** A catalog-side `document_axes` table (migration), NOT
columns on documents: `(document_id, not_before, not_after, precision,
date_raw, place_name, place_ref, axis_source)` — signed astronomical years;
`date_raw` keeps the upstream string so honesty survives normalization;
`place_ref` carries the TM/Pleiades URL when HGV has one (strings, no
gazetteer — the §1.4 stance holds). Populated at load time by per-source
timeline extractors reading canonical (loader stage, so `nabu rebuild`
regenerates it — the invariant holds; the Indexer never re-parses
canonical, unchanged). The chronicle passage-grain case rides as a nullable
`(passage_seq_from, passage_seq_to)` pair on extra rows — document-grain
rows leave them NULL; only the chronicle extractor fills them. Ranges are
honest ranges: "VI–VII AD, precision low" stores (501, 700, low), never a
fake midpoint.

**Query surface.** `search --from -300 --to 200 --place oxyrhynch%`
(composing with --lang/--license/--lemma/--near through the same
CatalogJoin two-step measured in P14-8 — date rows join document-side, so
the filter is one more EXISTS/IN). `show` prints the timeline line when
present. The linguist payoff: `vocab --by-century` / `concord --from --to`
— diachronic frequency as a bucketed GROUP BY over the same table. Display
honesty everywhere: most of the corpus is undated; "no date" is an absence,
never an error, never excluded silently unless a date filter is active.

**Cost.** ≤ ~100k rows (66k HGV + 25k ORACC + hundreds Slovene + chronicle
divs) → **< 20 MB**. Effort: **2 packets** — opus for the schema + HGV +
goo300k/IMP + search flags (fable review of the date model rides the
brief), then a second small opus packet for ORACC regnal mapping + the
chronicle passage-grain extractor. HGV syncs already (same idp.data clone
— zero new network).

## 4. `search --fuzzy` — fragment and half-remembered-quotation search

**Persona and question.** The papyrologist with `]μηνιν αει[` on a scrap;
anyone typing a half-remembered phrase. FTS5 tokenizes words and prefixes
only — mid-word/infix matching needs a character-level index.

**Options.** (a) FTS5 `tokenize='trigram'` shadow table (native substring
MATCH/LIKE support); (b) spellfix1 edit-distance (not in the stock sqlite3
build; per-WORD, wrong shape for infix-in-line); (c) prefix indexes
(prefix-only, already have). **Pick (a), scoped to documentary sources.**

**Measured (scratch FTS5 trigram builds from live text).**
- 100k DDbDP passages (3.5M chars): built in **0.4 s**, **22.9 MB = 6.55
  bytes/char**; substring queries `στρατηγ` (638 hits), `οφειλ` (324) in
  **≤1 ms**.
- 50k literary Greek passages (6.6M chars): **5.79 bytes/char** — the
  overhead is per-char, not per-row.
- Projections at ~6 B/char: documentary scope (DDbDP 31.1M + ORACC 10.2M
  chars) ≈ **250–270 MB**; whole corpus (626.5M chars) ≈ **3.6–4.1 GB** —
  more than doubling fulltext.sqlite3. This is why the per-source scope
  flag from §1.5 survives review: documentary sources are where fragment
  search earns its bytes (DDbDP averages 34 chars/passage — papyrus
  lines). A config list (`fuzzy_index: [papyri-ddbdp, oracc]`), not a
  hardcode; literary opt-in possible later.

**Surface.** `search --fuzzy "FRAGMENT"` → trigram MATCH, verified against
the passage text, rendered with the standard snippet machinery; composes
with --lang/--license (CatalogJoin again) and honestly reports its scope
("fuzzy index covers: papyri-ddbdp, oracc"). Fragments < 3 chars rejected
with a clear message (trigram floor). For the half-remembered-quotation
case in LITERARY texts, the honest answer is `parallels`-style phrase
probing (item 1) or plain FTS — say so in the help text rather than grow
the index 15×.

**Cost.** ~250–270 MB derived table in fulltext.sqlite3, drop-and-rebuild
lifecycle, built by the Indexer from the catalog (the passage_lemmas
pattern — no migration). Build time for the slice extrapolates to well
under a minute. Effort: **1 opus packet.**

## 5. Formula miner — repeated n-grams within a corpus slice

**Persona and question.** The oral-formulaic scholar (Homeric, OE
alliterative): "what are the recurring formulas of this tradition, and
where does each occur?" Intra-corpus repetition, not cross-corpus
quotation — the same gram machinery as item 1 pointed inward.

**Options.** (a) materialized corpus n-gram table (rejected — same reasons
as item 1); (b) per-slice streaming count at query time; (c) offline
suffix-array job. **Pick (b)** — measured, it's already interactive:

- Homer, grc only (27,903 passages / 199,816 tokens): **0.6 s** in-memory;
  2,754 4-grams recur ≥3× (11.1% of gram instances); top hits ARE the
  formulas — ὣς ἔφαθ' οἵ δ' (72×), τὸν δ' αὖτε προσέειπε (68×), the full
  τὸν δ' ἀπαμειβόμενος προσέφη πολύμητις Ὀδυσσεύς chain (50×).
- ASPR, ang (30,550 passages / 175,736 tokens): **0.6 s**; "hwaet ic
  hatte" (the riddle refrain, 16×), "awa to feore" (20×), "to widan
  feore" (19×).
- Language filtering is mandatory (first unfiltered Homer run returned
  "the son of peleus" — the English translations ride the same urn
  prefix); slice + `--lang` must both apply.

**Surface.** `nabu formulas <urn-prefix|--lang L> [--n 3..5] [--min 3]
[--cross-passage-only]` → ranked formula list, each with count and (on
`--show`) its passage urns. Slices to ~1M tokens stay interactive (~3 s
extrapolated); full-corpus grc (37.6M tokens) is a legitimate batch run
(~1–2 min, still zero schema). Output feeds links (item 7) only in batch
mode.

**Cost.** Zero schema. Effort: **1 small opus packet** — or a rider on the
`parallels` packet, since the gram builder (fold, elision strip, tokenize,
shingle) is shared code.

## 6. Cognate-in-parallel — the comparativist's differentiator

**Persona and question.** The comparativist reading aligned scripture:
"show me verses where the Gothic and OCS witnesses use reflexes of the
same proto-root" — the alignment hub (§10) × reflex crosswalk (§12) join
no other tool can make, because no other tool holds both.

**Measured, on the live tables.** Direct same-entry join (got lemma and
chu lemma both reflexes of ONE dictionary entry): **4 NT verses, 1 root**
— *plęsati: got plinsjan ~ chu плѧсати at MATT 11.17 (the famous
Slavic↔Germanic dance-word contact case, found blind). The thinness is
structural: got and chu rarely hang off the same entry directly; they meet
one level up. With ONE proto-to-proto hop (got → gem-pro entry → PIE
entry ← sla-pro entry ← chu — the closure the `etym` walk already defines):
**413 result rows, 349 distinct NT verses, 31 proto-roots, 33 (root, got,
chu) lemma triples**, computed in **1.4 s** end-to-end once staged with
indexes. And the hits are contextually matched, not just co-present:

    LUKE 14.34  *sḗh₂l:      got salt      ~ chu соль      (the salt saying)
    LUKE 17.35  *melh₂-:     got malan     ~ chu млѣти     (two women grinding)
    LUKE 18.25  *ulbanduz:   got ulbandus  ~ chu вельбѫдъ  (camel/needle's eye)
    LUKE 20.10  *wīnagardaz: got weinagards ~ chu виноградъ (vineyard parable)
    JOHN 13.18  *hlaibaz:    got hlaifs    ~ chu хлѣбъ     (who eats my bread)
    LUKE 1.24   *mḗh₁n̥s:     got menoþs    ~ chu мѣсѧць    (months)

**Honest limits, measured.** (i) Recall is bounded by Wiktionary
descendants coverage: 1,136 of 3,381 gold got lemma types (34%) and 1,478
of 6,954 chu types (21%) reach any proto entry. (ii) Function words
produce noise (*nu: nu ~ нъ; *éti: iþ ~ отъ) — a df threshold or small
stoplist is needed, said in output ("common-word matches suppressed;
--all shows them"). (iii) One hop up only, by design — the §12 bounded-walk
stance; genuine two-hop chains (chu → sla-pro → PIE) are IN via the closure
but arbitrary graph crawls are not. (iv) The naive query without staging
ran > 8 min: the packet MUST land two indexes — passage_lemmas(urn) (shared
need with item 1) and dictionary_reflexes(lang_code, word_folded) (the
proto-to-proto edge probe; today only (language, …) is indexed) — plus a
small derived closure table `reflex_roots(language, lemma_folded,
root_entry_id)` (the probe's lem2root: ~10–20k rows, < 5 MB, rebuilt with
the crosswalk in the Indexer, measured build ~1 s).

**Surface.** `nabu cognates REF [--work nt] [--langs got,chu]` → per verse:
the root (starred headword + dictionary), each witness's lemma and surface
context; `--langs` defaults to all pairs with reflex coverage (grc, lat,
ang, orv ride the same machinery free — grc×got via ine-pro is the obvious
second pair). Also a batch mode over a book/work → report + links. MCP:
`nabu_cognates`, §9 contract (license labels per witness, bounded, honest
totals).

**Cost.** Two indexes + one tiny derived table (< 50 MB total). Effort:
**1 opus packet with fable review** of the closure semantics (which edges
count as "same root"; homograph collisions across -pro dictionaries; the
stoplist policy).

## 7. The links table — §1.8 as invisible substrate

**The stance the measurements force.** §1.8 imagined every cross-reference
persisting as an edge. The probes above split cleanly in two: interactive
results (items 1, 5, 6 in their query modes) recompute in milliseconds-to-
seconds — storing them would be caching with staleness obligations, so
DON'T; batch-run results (corpus-wide parallel mining, whole-tradition
formula sweeps, whole-work cognate maps) take minutes and answer standing
questions, so they persist as edges. The links table is therefore the
OUTPUT FORMAT of batch mode, landing when the first batch producer lands —
not before (the "design the table when the first edge-producer is
elaborated" note in §1.8 was right; the elaboration is now).

**Shape.** `links(from_urn, to_urn, kind, score, run_id, created_at)` with
`kind` ∈ {parallel, formula, cognate, …} — urn-keyed like the revisions
ledger, because catalog ids re-mint on rebuild. Rebuild-safety is the one
real design question: batch output is a function of (canonical, params,
code version) — NOT of canonical alone — so it lives outside the
drop-and-rebuild dbs, journal-style beside the enrichment pattern
(architecture §5 Phase-8 stance): replayable, exportable, honest about the
run that minted it (`run_id` → parameters). `nabu links <urn>` reads edges
both directions; `show` gains a "linked:" footer when edges exist. Every
edge cites two resolvable urns — the citation-graph long game, fed one
batch run at a time.

**Cost.** Table + journal replay + `links` command: **1 opus packet**, but
only alongside/after the first batch producer (realistically a rider on
the batch mode of item 1 or 6). Not a Phase 15 headline.

## What waits for the cluster — the symbolic/embeddings line, drawn

Everything above is symbolic and local, and the probes show the symbolic
core is not a consolation prize — verbatim and near-verbatim intertext,
formula systems, and root-level cognate joins all fall to it at
interactive speed. What it cannot do, stated exactly:

- **Cross-language allusion without alignment** (tier 3 of item 1): an OCS
  homily paraphrasing a Greek source, Fathers paraphrasing LXX loosely.
  No shared surface/lemma vocabulary exists to shingle. Needs cross-lingual
  embeddings (per-passage vectors, vectors.sqlite3 is already reserved) —
  cluster work, and evaluation-hard (a golden set should come FIRST, and
  the golden set is cheap to curate from item 1's within-language output).
- **Paraphrase detection within a language** beyond shared rare material
  (free rewording): same story, embeddings + the same golden set.
- **Semantic place/date inference** for undated texts: out entirely
  (enrichment territory, and speculative).

The embeddings row should enter improvements §3 (the inference-cluster
queue) pointed at tier-3 intertext, gated on the golden set that Phase 15's
symbolic packets generate as a side effect.

## Recommendation menu — Phase 15

**Suggested lineup (in order):**
1. **P15-1 · `parallels <urn>` (headline)** — opus, 1 packet. Query-time
   surface-gram engine + rarity scoring + document dedupe + elision-strip
   gram builder; MCP `nabu_parallels`; golden quotation tests seeded from
   this document's probes (Odyssey 1.1→Polybius, Matt 4:4→LXX Deut 8:3,
   John 1:1→Fathers). **Riders:** passage_lemmas(urn) index; the
   rare-lemma co-occurrence second signal; `formulas` (item 5) as a
   shared-machinery rider if the packet stays light, else it's P15-5.
2. **P15-2 · timeline, part 1** — opus + fable date-model review,
   1 packet. `document_axes` migration; HGV + goo300k/IMP extractors;
   `search --from/--to/--place`; `vocab --by-century` payoff. (Part 2 —
   ORACC regnal mapping + chronicle annal grain — is a follow-on small
   packet, same shape, no new decisions.)
3. **P15-3 · cognate-in-parallel** — opus + fable closure review, 1
   packet. `nabu cognates` + `reflex_roots` closure table + the two
   missing indexes; got×chu headline, grc×got free rider.
4. **P15-4 · collation view** — opus, 1 packet. `align REF --collate`,
   raw-token LCS within script family, cross-script rendered undiffed.

**Alternatives.** If Phase 15 takes ONE packet: P15-1 — it is the persona
analysis's center of gravity and every probe says it ships in a single
packet with zero schema. If the owner's current Slavic axis outweighs the
classicist axis, swap P15-3 up to second — it is the corpus's most
distinctive capability and its measured examples (salt/соль in the salt
saying) sell themselves. `search --fuzzy` (P15-5/6 · 1 opus packet,
~250–270 MB, documentary scope) is genuinely useful but serves the
narrowest persona slice today; it loses nothing by waiting a phase. The
links table lands only as the batch-mode rider (item 7), and the formula
miner rides P15-1 or ships as the smallest standalone packet.

**Waits for the cluster:** embeddings-based paraphrase and cross-language
allusion (tier 3), gated on the golden set the symbolic packets produce.
The symbolic core above needs none of it.
