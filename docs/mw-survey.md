# Monier-Williams (Cologne CDSL) survey (P17-4 Phase A, 2026-07-13)

Scouting survey for the fourth dictionary-shelf occupant (improvements §1.3's
named next occupant for Sanskrit): *A Sanskrit-English Dictionary* (Monier
Monier-Williams, Oxford 1899) in the Cologne Digital Sanskrit Lexicon (CDSL)
digitization, sanskrit-lexicon.uni-koeln.de. Would complete the per-language
desk loop LSJ:grc :: L&S:lat :: B-T:ang :: **MW:san**.

Method: license page/file reads first, then the actual data — both CDSL MW
download zips (mwxml.zip 11.1 MB, mwtxt.zip 10.3 MB) plus the web bundle's two
key tables were pulled to scratch and censused **in full** (the measurements
below are whole-corpus counts over all 286,525 records, not extrapolated
samples, except where a sample is stated). GRETIL join figures are read-only
queries against the live catalog. Nothing was written to canonical/ or db/.

**Bottom line up front.** License is **CC BY-NC-SA 3.0** — the GRETIL class
(`nc`), not blocked, no research_private fallback needed. The digitization is
outstanding: line-per-record XML with a DTD and a 25 KB coding manual,
machine-readable grammatical apparatus on 91% of records, 328,060 tagged
literary citations with an 871-row machine-readable works-and-authors key, and
a small but **98.9%-parseable** dictionary-native cognate layer (2,509
tagged comparanda pairs — a second, 19th-century comparativist witness for
`etym`/`cognates`, distinct provenance from kaikki). Citation resolution
against the GRETIL shelf projects honestly to ~27% document-grain / 10–15%
passage-grain — capped by what GRETIL's TEI corpus doesn't hold (no
Mahābhārata, no Vedic prose) and by two single-blob GRETIL parses (Manusmṛti,
Aṣṭādhyāyī), all itemized below.

---

## 1. License verdict — CC BY-NC-SA 3.0, class `nc` (GATE: pass)

CDSL's site and the MW download page carry **no visible license text**; the
download page points into the zips: mwheader.xml = "Description of licensing
and other details of this edition". That file (TEI header, present in both
mwxml.zip and mwtxt.zip; read 2026-07-13) is the operative grant, verbatim:

> Copyright © 2014 The Sanskrit Library and Thomas Malten
>
> All rights reserved other than those granted under the Creative Commons
> Attribution Non-Commercial Share Alike license available in full at
> //creativecommons.org/licenses/by-nc-sa/3.0/legalcode […]. Permission is
> granted to build upon this work non-commercially, as long as credit is
> explicitly acknowledged exactly as described herein, and derivative work is
> distributed under the same license.

Mapping:

- The 1899 **print** is public domain; the CDSL **digitization** (The Sanskrit
  Library + Thomas Malten, per the header; NSF/NEH/DFG-funded) asserts its own
  copyright and grants BY-NC-SA 3.0. We take the grant at face value — same
  posture as GRETIL (aggregator BY-NC-SA) and UD-PROIEL/ISWOC.
- → `license_class: "nc"`: ingestable for local research, indexed/searchable,
  **default-excluded from the MCP surface**, never redistributed. No
  research_private fallback needed (that precedent was for BY-ND; NC-SA is an
  established class here).
- Credit line for the manifest: "The Sanskrit Library and Thomas Malten;
  Cologne Digital Sanskrit Lexicon (CDSL), sanskrit-lexicon.uni-koeln.de" —
  the header says credit "exactly as described herein", so the adapter doc
  should quote the availability paragraph in full (the lexica-adapter
  pattern).
- Per-dictionary variance confirmed real: CDSL hosts 43 dictionaries and the
  license lives per-dictionary in each download's header — this verdict covers
  **MW 1899 only**.
- License drift watch: there is no probe-shaped license endpoint; like B-T,
  the license row will read unchecked, re-verified by re-reading mwheader.xml
  (inside the fetched zip — so every real refetch re-lands it in canonical).

**Not frozen upstream, and that's a finding:** the zips' Last-Modified is
2026-07-05 and the DTD carries dated change comments through 06-2026 — Cologne
actively corrects. `sync_policy: manual` (owner-fired refresh), conditional
GET via FileFetch; but do not describe upstream as frozen in the adapter doc.

## 2. Format census

Three downloads at `/scans/MWScan/2020/downloads/` (sizes measured):

| artifact | compressed | contents |
|---|---|---|
| mwxml.zip | 11.1 MB | **mw.xml (64 MB)** — one record per line, `<!DOCTYPE mw SYSTEM "mw.dtd">`; mw.dtd; mwheader.xml (license) |
| mwtxt.zip | 10.3 MB | mw.txt (48 MB) — Cologne meta-line format (`<L>…<LEND>` blocks); mw-meta2.txt (the 25 KB coding manual — parser-spec gold); mwheader.xml |
| mwweb1.zip | 44 MB | web display app; sqlite bundles incl. **mwab.sqlite (424 abbreviations)** and **mwauthtooltips.sqlite (871 sigla key)**; SLP1↔IAST/HK/Devanagari transcoder tables; 86 MB mw.sqlite (redundant) |

**Recommend ingesting mw.xml** (mwxml.zip): same content as mw.txt but with
the DTD contract; one record per line means a streaming line parser, no DOM
over the 64 MB file (CLAUDE.md's >5 MB rule satisfied).

**Record census (whole file):** 286,525 records, 194,084 distinct headwords
(`key1`), stable per-record Cologne id `<L>` (survives upstream revisions —
the natural `entry_id`), print page/column in `<pc>`. The four "lines" of
MW's own layout are H1–H4 (main records: 32,116 / 32,500 / 112,183 / 17,091 =
193,890), with lettered continuation records (92,635 total): A = same-gender
sense continuation, B = new gender block, C = inflected form, E = etymology
section (727 — where the cognate notes concentrate). The supplement is
already merged in by Cologne (`<info n="sup"/>` marks those).

**Transliteration:** headwords (`key1`/`key2`) and in-body Sanskrit (`<s>`)
are **SLP1**; `key2` additionally carries accent (`a/MSa`) and compound seams
(`aMSa—karaRa`). Proper names in `<s1>` are Anglicized-Sanskrit display forms
with an IAST/SLP1 attribute. Greek cognates are polytonic Unicode; **no
Devanagari anywhere** (the backlog lead "headwords Devanagari + IAST" is
wrong upstream-wise — Devanagari would be a deterministic SLP1 transform,
display-only, v2). What nabu needs is **SLP1 → IAST at the adapter boundary**
(the betacode-decode precedent exactly): a ~60-rule deterministic table
(`A→ā, f→ṛ, F→ṝ, x→ḷ, S→ś, z→ṣ, N→ṇ, Y→ñ, J→ñ?` — no: `J→ñ, Y→ñ`? the
transcoder tables in mwweb1 document it; implement from those, with a
regression fixture). After that, **no conventions-§9 addition is needed**:
GRETIL text is san-Latn IAST and the generic fold (NFC → downcase → strip
marks) already sends both sides of ā/ś/ṛ/ṃ/ḥ to the same folded form. The
scout verified: fold("aṃśa") = fold(IAST of "aMSa") = "amsa". The conversion
is a transcode, not a fold rule.

**Grammatical apparatus — structured, not prose:** `<lex>` tags (206,892) for
display; machine-readable summaries on the `<info>` element: `lex=` gender in
a normalized grammar (`m:f#ikA:n`) on **261,401 records (91%)**; `verb=`
root-class on 10,606 verb records (genuineroot/root/pre/gati/nom) with `cp=`
class-pada lists (`10P,10Ā`) and `parse=` sandhi-split prefixed roots
(`ude = ud+A+i`); `lexcat=` stems for pronouns/numerals/participles;
`westergaard=` Dhātupāṭha links (1,487) and `whitneyroots=` (885). This is a
gold morphological seed for `san` far beyond what B-T offered for `ang`.

## 3. Citations layer — 328,060 tagged, sigla key machine-readable

Every literary reference is a tagged `<ls>` element: **328,060** of them.
Leading-sigla aggregation (subdivision tails stripped) yields 1,890 distinct
strings; the true vocabulary is the upstream **works-and-authors key
mwauthtooltips.sqlite: 871 rows (745 titles, 77 authors, 30 literary
categories)** — MW's own preface list, digitized and linked by Cologne ("Susan
J. Moore: tagging of the list of works and authors, and association of
abbreviations actually used"). General abbreviations (q.v., cl., ifc. …) have
their own 424-row key (mwab.sqlite). Elliptical continuation citations are
**pre-resolved upstream**: 8,829 `<ls n="…">` restore the elided context
(print "15" carries `n="RV. viii, 96,"`).

Head of the distribution (whole-corpus counts):

| siglum | count | class |
|---|---|---|
| L. (native lexicographers) | 41,349 | authority label, never passage-resolvable |
| MBh. Mahābhārata | 28,574 | **not held** (GRETIL TEI has only Mādhva's Tātparyanirṇaya) |
| RV. Ṛgveda | 16,362 | held, verse grain — resolution VERIFIED (below) |
| R. Rāmāyaṇa | 11,004 | held, verse grain (edition-numbering caveat) |
| ib. | 10,372 | propagatable from preceding citation (v2) |
| Pāṇ. Pāṇini | 8,795 | held but single-blob parse (document grain) |
| BhP. Bhāgavata-purāṇa | 8,630 | held, verse grain |
| W. (Wilson) / MW. / Cat. | 19,619 | authority labels |
| AV. / ŚBr. / Suśr. / TS. / VS. / KātyŚr. | ~29,900 | **not held** (Vedic prose + Suśruta gap in GRETIL TEI) |
| Mn. Manusmṛti | 7,129 | held but GRETIL parse = ONE p1 passage (document grain) |
| Kathās., Hariv., VarBṛS., Pañcat., Ragh., Yājñ., VP., Sāh., MārkP., Hit., Śak., Daś., Kum., Pat. | ~35,700 | held, grain varies (see below) |

**GRETIL shelf reality (read-only db census, 780 documents, 703,068
passages):** grain is mixed — 323,424 passages carry dotted numeric citations,
348,419 are `p`-numbered paragraph fallbacks, and some documents collapsed to
a single passage (sa_manusmRti: 1 × 261 KB blob; sa_pANini-aSTAdhyAyI: 1).
Verse-grain works among the MW top-cited: RV (`1.001.01a`), BhP (`01.01.004`),
R (`1.001.001`), Ragh/Yājñ/Kum/Sāh/MārkP (`1.1`-style), VP/Daś (`1,1.1`).
Harivaṃśa is held but in critical-edition numbering (`*HV_1.0*1:1`) that MW's
continuous Calcutta numbering will not match — document grain only.

**End-to-end resolution verified with a real citation:** MW s.v. aṃśa cites
"RV. v, 86, 5" → roman-to-arabic + zero-pad →
`urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05a` / `…05c` — both live in the
catalog. The existing define resolver shape fits (cts_work = GRETIL document
urn, citation = normalized dot path, candidate-probing at query time); it
needs one MW-shaped extension: per-work pad/format templates and pada-suffix
prefix probing (`05` → `05a`,`05c`), a bounded variant of the existing
citation_forms fallback.

**Honest projection** (classes over the 328,060):

- **Authority labels** (L., W., MW., Cat., ib., Kāv., Buddh., Pur., Br., Gal.,
  Sāy.): ≈83k ≈ **25%** — not misses; label them as lexicographic authority
  in display and exclude from the resolution denominator honestly.
- **Held works, top-60 sigla**: ≈89k ≈ **27% resolvable at least to
  document**; of these the verse-grain subset (RV, BhP, R, Ragh, Yājñ, Kum,
  MārkP, VP, Sāh, Daś ≈ 48.9k) projects to **10–15% of all citations at
  passage grain** after edition-numbering losses (R's Bombay-vs-GRETIL
  numbering is the big unknown; RV/BhP are safe). The long tail of GRETIL's
  780 works (Sāhityadarpaṇa, Hitopadeśa, kāvya corpus…) adds a few thousand
  more.
- **Cited but not held**: the remainder, ≈45–48% — dominated by MBh (28.6k),
  AV/ŚBr/TS/VS (Vedic prose, ~21k), Suśr./Car. (medicine, ~8k). This is a
  GRETIL-coverage fact, not a parser deficiency; report per-siglum coverage in
  the define output (the LSJ precedent: report coverage, don't fake it).
- Resolution-lifting future work, priced separately: ibid-propagation (+10.4k
  candidates), GRETIL re-grain of sa_manusmRti/sa_pANini-aSTAdhyAyI (+15.9k),
  MBh/Vedic acquisition (a source-scout question, not P17-4's).

## 4. The comparativistics layer — MW's own cognate notes: PARSEABLE, small

Measured over the **whole corpus** (all 286,525 records, not a 100-sample —
the layer is small enough to census exhaustively):

- 2,171 records carry `<lang>` tags; 114 distinct labels. Most-frequent labels
  include register markers that must be filtered (Ved. 637, ep. 345, Class.,
  Prākṛt, Pāli — usage registers of Sanskrit, not cognate languages).
- After filtering to genuine cognate languages: **973 records, 2,537 cognate
  `<lang>` tags** — Lat. 541, Gk. 520, Germ. 217, Goth. 206, Eng. 197, Lith.
  190, Zd. 142, Angl.Sax. 136, Slav. 114, Hib. 54, Russ., Armen., …
- **Parseability: 98.9%** — 2,509 of 2,537 cognate-language tags are followed
  immediately (in tag-stream order) by a **tagged comparandum**: `<etym>`
  (Latin-script cognate word, 2,723 in corpus) or `<gk>` (polytonic Greek
  Unicode, 1,168). Only 28 tags lack an adjacent tagged form. This is markup,
  not free prose: e.g. `<lang>Goth.</lang> <etym>amsa</etym>; <lang>Gk.</lang>
  <gk>ὦμος</gk>, <gk>ἄσιλλα</gk>; <lang>Lat.</lang> <etym>humerus</etym>`.
- Bounded nuances for the parser: one `<lang>` can govern several comparanda
  (`Gk. ἀ, ἀν`), and coordination shares a form across languages (`Goth. and
  Germ. un`); both are local, tag-stream-visible patterns.

**Design (v1-viable):** mint rows into the existing `dictionary_reflexes`
table as-is — `dictionary_entry_id` = the MW entry, `lang_code` = MW's label
verbatim (`Gk.`, `Angl.Sax.`), `language` = mapped catalog tag (grc, lat, got,
lit, ang; Zd.→ae; Slav. maps cautiously — MW's "Slav." is usually Church
Slavonic, map → chu or leave display-only), `word` = the comparandum,
folded forms as join keys. Provenance is automatically distinct from kaikki's
(the owning entry's dictionary is mw), so `etym`/`cognates` can display "MW
1899: cf. Gk. ὦμος" beside the kaikki-derived edges — a second, independent
19th-century witness. Expected yield: **≈3.9k comparandum tokens from ≈1k
entries** — small, high-precision, cheap. Not a v2 deferral.

## 5. Etymology cross-references between MW entries

- **"See …" cross-references:** 5,266 tagged `See <s>…</s>` refs in 5,229
  records (plus 11,916 `cf.` occurrences introducing softer comparanda/refs).
  Target resolution is an SLP1-key join against MW's own headwords at query
  time — the headword_folded machinery already does this shape.
- **Parenthetical-headword ties:** 2,362 upstream-minted `phwparent`/
  `phwchild` links (Cologne's own entry-to-entry graph for headwords minted
  out of parenthetical mentions) — machine-readable, L-id-addressed.
- **Alternate-spelling links** (`info or=/and=/orsl=/orwr=`): documented in
  mw-meta2.txt but **0 occurrences in the current mw.xml** — apparently
  retired upstream; noted so Phase B doesn't hunt for them.
- Root references: 15,532 `√` marks + key2 compound seams would support a
  root-family grouping (all derivatives of √bhāṣ) — genuinely useful but a
  new query surface; **v2**.
- v1 scope: land See-refs as dictionary_citations-adjacent display (or defer
  entirely); the links-graph (§1.8) wiring is v2 with the phw ties as the
  cleanest first edges.

## 6. Ingestion design sketch

- **Adapter** `mw` (slug also the dictionary slug; language `san`),
  `content_kind :dictionary` routing to Store::DictionaryLoader — the B-T
  pattern verbatim. Fetch: **FileFetch over mwxml.zip only** (11.1 MB;
  conditional GET, sha pin, attic + mass-deletion guard); parse opens the zip
  member (or unzips beside, the fetch report pinning the zip). mwweb1.zip (44
  MB, mostly a redundant 86 MB sqlite) is NOT fetched; the sigla→work mapping
  we need is a curated ~20–40-row config for the works we actually hold, and
  the full 871-row key stays upstream-recoverable. `sync_policy: manual`,
  `enabled: false` until the owner-fired first sync.
- **Entry model:** group each main H1–H4 record with its immediately following
  A/B/C/E continuations (file order guarantees adjacency, per mw-meta2.txt) →
  **193,890 entries**; `entry_id` = the main record's L (stable Cologne id),
  `key_raw` = key2 (accents + seams), `headword` = IAST of key1,
  `headword_folded` = generic fold, body = concatenated sense blocks with
  `<s>` SLP1 transcoded to IAST for display, gloss = first sense text (B-T
  precedent). urn `urn:nabu:dict:mw:<L>`. (Alternative considered: one row
  per L record, 286,525 rows — simpler parse, worse define output; the
  grouped shape matches what "entry" means everywhere else on the shelf.)
- **Parser family** `mw-xml`: line-streaming (one record per line), per-line
  fragment parse; no DOM over the 64 MB whole.
- **Citations:** one dictionary_citations row per `<ls>`; `cts_work` = GRETIL
  document urn for sigla in the curated map (with per-work citation
  normalization: roman→arabic, zero-padding templates), else nil + label —
  the honest-miss shape already in the schema. Resolver extension: per-work
  format templates + pada-suffix prefix probing.
- **Reflexes:** dictionary_reflexes rows per §4. **No schema changes needed
  anywhere.**
- **Folding:** no §9 addition (argued in §2 — SLP1→IAST is an adapter-boundary
  transcode, the betacode precedent; generic fold covers IAST on both sides).
- **Size estimate:** canonical +11 MB (zip); catalog ≈ +48 MB entry bodies +
  328k citation rows + ~4k reflex rows ≈ **+100–130 MB catalog**, comparable
  to B-T. Parse is single-file streaming; expect minutes, not hours.
- **Fixture plan (owner approval requested):** one trimmed mw.xml (real
  records, structurally intact, ~20 records) + mw.dtd + mwheader.xml (the
  license travels inside the fixture, as upstream ships it), README with
  retrieval date/URL. The three demonstration clusters:
  1. **Citation-dense + resolvable:** the aṃśa group (L 10–19; homonyms,
     `info lex`, and "stake (in betting), RV. v, 86, 5" — the verified
     end-to-end resolution above) with two–three of its H3 compounds.
  2. **Cognate-note entry:** aṃsa "shoulder" (L 92 + its H2E etymology record
     L 92.1: Goth. amsa; Gk. ὦμος, ἄσιλλα; Lat. humerus, ansa) — exercises
     `<lang>/<etym>/<gk>` → reflex rows.
  3. **Structured-grammar root:** √bhāṣ (L ≈ the BAz record; `cl. 1. Ā.`,
     `<info verb="genuineroot" cp="1Ā">`-shape, `westergaard`/`whitneyroots`
     attrs, Dhātup. citation) — exercises the verb apparatus.

## 7. Ranked verdict

**v1 (one Phase B packet):** mwxml.zip FileFetch adapter + mw-xml line parser
→ 193,890 grouped entries (SLP1→IAST transcode at the boundary, no fold-rule
change) + all 328k citations stored with the curated GRETIL sigla map
(~20–40 works; RV/BhP/R/Ragh/Yājñ/VP/Sāh/MārkP/Kum/Daś… at passage grain,
Mn./Pāṇ./Hariv./Kathās. at document grain) + the cognate reflex layer (≈3.9k
edges, §4 — cheap and 98.9% reliable, in v1) + define/nabu_define with
per-siglum coverage reporting. License class `nc` throughout.

**v2 deferrals:** ibid-propagation (+10.4k citation candidates); Devanagari
display forms; root-family grouping via √/key2 seams; See-ref + phwparent
edges into the §1.8 links graph; Dhātupāṭha/Whitney references as structured
links; full 871-sigla tooltip key ingestion; Pāṇini/Manusmṛti passage-grain
resolution (blocked on a GRETIL parser re-grain, a separate packet against a
different source).

**Blocked:** nothing. The one true external cap — MBh/AV/ŚBr/Suśr. citations
(~45% of the citation mass) pointing at works GRETIL doesn't hold — is
unblocked only by scouting new Sanskrit text sources (e.g. the Smith MBh),
which is future source work, not an MW-packet defect.
