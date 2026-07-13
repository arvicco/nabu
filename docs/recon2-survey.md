# P17-3 Phase A — Reconstruction shelf, part 2: survey & design

Scout survey, 2026-07-13. Owner gate: fixture plan (§4) + the multi-hop
closure design (§2) + the `borrowed` flag design (§3) want approval before
Phase B. Method: kaikki.org inventory read live; the three synced extracts
plus wiktionary-cu censused IN FULL from canonical/ (read-only); the four
candidate extracts downloaded to scratch — three in full (they are small),
Proto-West Germanic sampled (1,657 of ~5,900 records ≈ 28%, head + one
mid-file 10 MB range). Folds computed through the repo's own
`Nabu::Normalize.search_form` (the parser's exact join contract, word OR
roman, leading asterisk stripped). Gold sets read from the live db AFTER
the owner-fired `sync wiktionary-cu --parse-only` that ran mid-survey
completed — the P16-5 projection landed exactly: reflex_roots
50,151 → 50,395 (+244), dictionary_reflexes 609,691 → 611,901 (+2,210
chu-owned edges live).

## 1 · Extract inventory (kaikki.org, read 2026-07-13)

kaikki serves 460 per-language extracts; the alphabetical index's smallest
entries sit at ~520 senses, and every reconstruction language below that
threshold 404s. Exactly 20 Proto-* extracts exist. On our axes:

| extract | lang_code | upstream | size | records w/ descendants | notes |
|---|---|---|---|---|---|
| Proto-Balto-Slavic | ine-bsl-pro | 487 words / 491 records | 1.7 MB | 98.0% | THE intermediate shelf |
| Proto-Italic | itc-pro | 737 words / 745 records | 5.2 MB | 98.7% | Greco-Roman axis |
| Proto-Indo-Iranian | iir-pro | 758 words / 799 records | 3.3 MB | 95.7% | Sanskrit axis |
| Proto-West Germanic | gmw-pro | 5,383 words (49.4 MB; sampled 1,657 records) | 49.4 MB | 98.8% | Germanic/OE axis |

Served but off-axes: Proto-Celtic (1,933 senses; no Celtic gold),
Proto-Finnic/Samic/Uralic/Turkic/Bantu/… (skipped). **Not served (404,
verified per-URL):** Proto-Hellenic, Proto-Semitic, Proto-Indo-Aryan,
Proto-Iranian, Proto-Anatolian, Proto-Afroasiatic, Proto-Norse.

**The sem-pro/cuneiform synergy is dead twice over.** No extract is served;
and measured across ALL 611,901 live dictionary_reflexes rows (which
include PIE's full descendant trees), `sem-pro` is named as a descendant
language exactly **once** and `akk` exactly **once** — wiktextract
descendants essentially never name Akkadian even where the graph could.
For the record, the transliteration fold would NOT have been the blocker:
ORACC citation forms (šarru) and Wiktionary romanizations fold identically
under §9 (š→s via the Mn strip, macrons likewise), so if a sem-pro shelf
ever lands via the full-extract filter (~2.6 GB compressed, the documented
DEPRECATED-fallback path), the join mechanics work — the naming density is
what's missing. Deferred with evidence, not assumed.

### Measured crosswalk value (full-file except gmw; word-OR-roman fold join
against today's 131,175 distinct gold (language, lemma) keys)

| extract | records naming a gold lang | of those, joining ≥1 gold lemma | gold nodes named→matched (top) |
|---|---|---|---|
| itc-pro | 693/745 (93.0%) | **533 (76.9%)** | lat 880→594, grc 2→1 |
| iir-pro | 728/799 (91.1%) | **534 (73.4%)** | san 997→626 (roman load-bearing), xcl 84→11 |
| gmw-pro (sample) | 1,226/1,657 (74.0%) | **269 (21.9%)** | ang 2,343→281, sl 155→71, lat 46→1 |
| ine-bsl-pro | 3/491 (0.6%) | 1 | orv 1→1 — see below |

Re-measured for reference on the synced shelves (full-file, today's gold):
sla-pro 58.8% (chu 4,460→1,525, orv 3,960→1,607, sl 1,429→557), ine-pro
70.0% (grc 2,634→932, lat 1,810→990, san 2,098→799, xcl 806→222, hit
391→0), gem-pro 38.7% (ang 9,107→1,234, got 2,159→1,170).

Honest readings:

- **PBS almost never names an attested gold language directly** (3 records)
  — its descendants are Baltic (lt/lv/prg/sgs…) and sla-pro. Its value is
  entirely STRUCTURAL: 509 sla-pro descendant nodes of which **450 (88.4%)
  fold-join live sla-pro shelf headwords**, and PIE names ine-bsl-pro
  1,112× of which 357 (32.1%) join PBS's 487 headwords — 332 verified
  PIE→PBS→sla-pro record chains. This is the shelf the P15-3 closure
  review named as the revisit trigger.
- **gmw-pro's low join is our corpus, not the extract**: ang gold holds
  only 2,830 distinct folded lemmas, so 12.0% node-level join here matches
  gem-pro's 13.6% exactly. New-key yield is small (below) but the shelf is
  the OE axis's proto desk: ~8,300 ang nodes projected full-file.
- hit joins 0 everywhere (gold hit = 14 distinct lemmas) — no shelf fixes
  that; corpus-side gap.

**New-key yield vs the live closure** (distinct matched gold keys /
not yet among reflex_roots' 40,061 keys): itc **559/397 new**, iir
**569/498 new**, gmw sample 266/**56 new** (most ang keys already reach
gem-pro via its flattened trees; full-file extrapolation ~950/~200),
PBS 1/0.

## 2 · The multi-hop closure design (for the gate)

**Why now.** ReflexRootsIndexer's one-hop ascent bound was argued from "a
depth-3 chain needs an intermediate shelf … that does not exist; revisit
if one lands" (class doc; P15-3 review finding 6). PBS **is** that shelf,
and gmw-pro is a second one (gem-pro names gmw-pro 4,644×). Verified live
chain, end-to-end folded: PIE *per- → ine-bsl-pro *pírštan → sla-pro
*pь̃rstъ (folds to the live headword pьrstъ) → chu прьстъ / orv пьрстъ,
both attested gold. Under the current bound, the PIE root is unreachable
from the chu lemma once the walk enters via PBS-mediated paths; with the
chu shelf minting reflexes since P16-5 the full chain is
PIE → PBS → sla-pro → (chu) → orv — four edges.

**Design — the shelf-visited walk (proposed):**

- Generalize `root_urns` to a worklist walk. From each direct target
  entry, repeatedly ascend: for entry E owned by dictionary-language S,
  add every entry of an UNVISITED shelf whose reflexes name
  (S, E.headword_folded); newly reached entries re-enter the worklist.
  Attested reflex-owning shelves (chu today) ascend like -pro shelves —
  the packet's "(chu)" link; this supersedes P16-5's direct-only stance,
  argued: descent through an attested intermediary is the same descent
  relation, and Etym renders the OCS station un-starred either way.
- **Bound = each shelf enterable once per walk** (a visited
  dictionary-language set seeded with the direct target's shelf). This is
  the same-language exclusion generalized: it provably terminates in
  ≤ (reflex-owning shelves − 1) hops regardless of malformed proto-to-proto
  cycles (a cycle's return edge re-enters a visited shelf and dies), needs
  no magic depth constant, and degenerates to EXACTLY today's one-hop walk
  when no intermediate shelf exists — the old argument preserved as a
  special case. With v1's 8 reflex-owning shelves the theoretical max is 7
  hops; the longest real chain measured is 3.
- **Determinism**: unchanged — Set accumulation, sorted emit; the walk
  order cannot affect the emitted set because membership, not path, is
  stored.
- **Projected size**: closure today 50,395 rows / 40,061 keys / <5 MB /
  ~1.4 s. Growth: itc +559 keys ≈ +1.1–1.7k rows (each key: itc root +
  PIE ascent; PIE joins itc-pro headwords on 533 of 1,484 naming edges);
  iir +569 keys ≈ +1.1–1.7k rows; gmw ≈ +1–3k rows (mostly extra root
  urns on EXISTING ang keys: gmw root + gem-pro + transitive PIE); PBS
  adds no keys but re-roots Slavic rows — 450 PBS→sla-pro joins cover
  ~8% of the 4,059 live sla-pro root urns backing 16,616 chu/orv/sl rows
  → ≈ +1.3k PBS-root rows plus a smaller transitive-PIE increment where
  PIE doesn't already name the sla-pro form directly (it does 1,137×, so
  overlap is high). **Total projection: ~56–60k rows, <8 MB, build well
  under 10 s.** Trivial by every measure the review cared about.
- **Query::Etym needs chain rendering.** `ancestors` is already a
  recursive Result shape cut at depth 1 (`ascend: false`); lift it to the
  same shelf-visited walk and render the chain indented (or inline:
  `sla-pro *pьrstъ ← ine-bsl-pro *pírštan ← ine-pro *per-`), compact
  capped per house rule, `--long` expands. MCP nabu_etym payload gains
  nesting depth, bounded identically.

## 3 · The `borrowed` flag (P15-3 review finding 4, named future work)

**Where the marker lives (measured).** Descendant nodes carry it in
`raw_tags`/`tags` as `"borrowed"` (+ 8 × `"learned borrowing"` in the
small extracts; match /borrow/i, do NOT match "reshaped by analogy…").
Also present, noted for later: `"inherited"` (1,297 nodes in PIE, 1,656 in
gem-pro), `"uncertain"`, and a `sense` field on nodes — enumerated per the
phase mandate, deferred (borrowed only in v1).

**Density census (borrow-flagged / worded nodes):**

| extract | flagged | density | flagged among gold-language nodes |
|---|---|---|---|
| wiktionary-cu (full) | 628/2,210 | **28.4%** | orv 83 of 87 (!), sl 14 |
| gmw-pro (sample) | 14,774/104,132 | 14.2% | sl 154 of 155, lat 44 |
| gem-pro (full) | 44,158/473,241 | 9.3% | lat 972, ang 110, sl 60, orv 30, chu 12 of 23 |
| iir-pro (full) | 568/8,300 | 6.8% | xcl 81 of 84, grc 24 |
| sla-pro (full) | 5,745/98,382 | 5.8% | orv 172, sl 25, lat 18 |
| itc-pro (full) | 42/2,281 | 1.8% | lat 19 (bōs, brutus — Sabellic loans INTO Latin) |
| ine-bsl-pro (full) | 43/2,366 | 1.8% | — (Baltic→Finnic loans, off-gold) |
| ine-pro (full) | 623/38,068 | 1.6% | lat 85, grc 39, xcl 39 |

The census surfaces two owner-axis payoffs beyond the P15-3 case: (i)
**Church Slavonicisms** — wiktionary-cu and sla-pro flag OCS→orv edges
(страна/градъ/глава flagged borrowed vs the inherited pleophonic
сторона/городъ/голова doublets), 83 of the cu shelf's 87 orv edges; (ii)
**Iranian loans in Armenian** — iir-pro flags 81 of its 84 xcl edges
(kšatrám → աշխարհ). Both are per-edge facts no meet-shelf heuristic can
recover.

**The hlaibaz finding (design-load-bearing).** In *hlaibaz's tree the flag
rides the PROTO-TO-PROTO edge — `Proto-Slavic *xlěbъ, tags:["borrowed"]`;
no cu leaf exists in the gem-pro tree at all. chu хлѣбъ meets *hlaibaz
via chu→*xlěbъ (direct, unflagged) then the ASCENT edge (flagged). So a
flag stored only on direct edges never fires for the P15-3 headline case:
**the closure must OR the flag along the path.**

**Design:**

- **Migration 009**: nullable boolean `borrowed` on dictionary_reflexes.
  Parser writes true (flagged) / false (parsed unflagged); pre-resync rows
  read NULL — an honest "not yet reparsed", never a fake false.
- **Parser/model**: DictionaryReflex value + wiktionary-jsonl node
  predicate on raw_tags ∪ tags; `borrowed` joins ContentHash's
  reflex_fields, so the flag re-mints revisions of reflex-carrying entries
  at the next owner-fired parse-only resync per shelf (~6.1k recon + 589
  cu entries; the exact P16-5 recovery pattern).
- **Closure**: reflex_edges carries the flag per (key → entry) edge;
  root_urns ORs it along the walk; reflex_roots gains `borrowed` (0/1,
  NULL when any contributing edge predates the resync), deduplicated by
  max() per (language, lemma_folded, root_urn) — deterministic. The OR is
  safe from inherited/borrowed conflicts at this grain because doublets
  differ in surface form (страна vs сторона are different lemma_folded
  keys); upstream flags are high-precision/low-recall, so unflagged stays
  the meet-shelf heuristic's territory (kept, as P15-3 shipped it).
- **Consumers**: Cognates' WitnessWord gains the flag → per-edge "loan"
  label; Etym's MatchedVia + ReflexViews::View + ancestor edges likewise;
  BatchCognates' detail string appends the marker; MCP payloads gain the
  boolean with the NULL-honesty note.
- **hlaifs~хлѣбъ before/after** (JOHN 13.18 / JOHN 6.5): before —
  `*hlaibaz [gem-pro]: chu хлѣбъ ~ got hlaifs`, the reader must apply the
  taught meet-shelf reading. After — `chu хлѣбъ (loan) ~ got hlaifs` at
  the same root: the loan is stated per edge, Gothic's side stays an
  inheritance claim, and gem-pro meets with NULL/unflagged edges keep the
  heuristic caption.

## 4 · Fixture plan (byte-verbatim trimmed records, the P14-1 recipe)

One JSONL per new shelf under the wiktionary-recon fixture tree, 2–3 real
records each (~12 records, tens of KB total), quirks preserved:

- **ine-bsl-pro**: *pírštan (THE multi-hop golden: named by PIE *per-,
  names sla-pro *pь̃rstъ whose accented fold joins the live shelf, chain
  bottoms at chu прьстъ + Glagolitic ⱂⱃⱐⱄⱅⱏ / orv пьрстъ gold);
  *wárˀnāˀ (the ˀ U+02C0 fold quirk ×310 in headwords, → sla *vòrna);
  *duktḗ (borrowed-flagged Proto-Finnic/Samic descendants — the flag on
  off-gold display edges — and its sla-pro child's orv дъщи Slavonicism).
- **gmw-pro**: *hlaib (→ ang hlāf gold; extends the P15-3 headline chain
  one shelf down; also named by gem-pro *hlaibaz — the second multi-hop
  path); *faru (→ sl barva flagged borrowed — the German-loan-in-Slovene
  edge); one entry with the sco/en-heavy modern tail trimmed to prove the
  gold-scoping stays quiet.
- **itc-pro**: *gʷōs (lat bōs flagged borrowed — a loan INTO the gold
  language from Osco-Umbrian, the shelf-heuristic counterexample; ʷ fold
  quirk ×56); one clean inherited lat join with a PIE parent (candidate:
  a *kʷ- root, picked at fixture build for a Vulgate-attested lemma).
- **iir-pro**: one sa record whose roman joins GRETIL san gold (the
  script bridge; candidate *bʰráHtā); *kšatrám (xcl աշխարհ flagged — the
  Iranian-loan layer against xcl gold); one ˢ/ᶻ modifier-letter headword
  (adᶻdʰáH class — the new fold chars, ˢ×12 ᶻ×9 measured).
- **Existing shelves**: re-trim *hlaibaz (or add) so the flagged
  gem→sla-pro edge is a pinned golden for the closure OR; one cu record
  with a flagged orv edge (страна) for the Slavonicism label.
- **No sem-pro→akk fixture** — did not survive the census (§1).

Normalize riders the fixtures must pin: PROTO_FOLD extensions —
`itc`/`iir` join the LANGUAGE_FOLDS proto keys (ʷ→w; ʰ→h plus new ˢ→s,
ᶻ→z), and `ine` (which already covers ine-bsl-pro via primary subtag)
gains ˀ→"" (gsub, 1→0, fold_with_map-safe). gmw headwords carry no Lm
chars (measured) — generic fold suffices. Census scripts + outputs
retained in scratch for the Phase B recipe.

Sync/size: four new EXTRACTS rows in the existing adapter (slugs
wiktionary-ine-bsl-pro/-gmw-pro/-itc-pro/-iir-pro), four FileFetch
subdirs, ~60 MB across four owner-fired GETs; +~7,900 entries
(13,053 → ~21k proto entries). Same license (verbatim kaikki dual
CC-BY-SA + GFDL), same DEPRECATED caveat + full-extract fallback.

## 5 · Ranked verdict

**v1 — all four served on-axis extracts**, one adapter extension:

1. **Proto-Balto-Slavic** — structural first: the shelf the closure
   review's bound is contingent on; 88.4% shelf-join into sla-pro, 332
   verified PIE→PBS→sla chains; Slavic axis. Zero direct gold value
   (0.6%) stated plainly — it earns its place as the chain link, not a
   crosswalk.
2. **Proto-Indo-Iranian** — largest NEW-key contributor (498), 73.4%
   record join, san via roman + the flagged xcl loan layer.
3. **Proto-Italic** — best record join (76.9%), 397 new lat/grc keys,
   Greco-Roman axis, the bōs counterexample fixture.
4. **Proto-West Germanic** — OE axis (owner-weighted): the proto desk
   above ang with ~8,300 projected ang nodes and the richest loan
   density (14.2%); ranked last only because its marginal gold keys are
   few (~200 projected) — the ang gold corpus, not the extract, is the
   ceiling.

**Deferred/blocked, with reasons:** sem-pro — blocked at inventory (no
extract) AND at naming density (akk named 1× in 611,901 live edges);
revisit only on evidence, via the full-extract filter. grk-pro
(Proto-Hellenic) — not served; the gap is real (PIE names grk-pro 1,168×)
but PIE already names grc directly 2,634×/932 joined, so only
intermediate chains are lost; revisit if kaikki serves it. inc-pro /
ira-pro — not served; no loss today (iir's flatten already attaches
sa/pal/peo nodes to the iir record). Proto-Anatolian — not served, and
hit gold (14 lemmas) joins nothing anyway. cel-pro — served, off-axes
(no Celtic gold), skip. Proto-Finnic and friends — off-axes (though PBS's
flagged Baltic→Finnic edges ride along as display-only color).
