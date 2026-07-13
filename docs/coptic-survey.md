# Coptic Scriptorium survey (P17-1 Phase A, 2026-07-13)

Scouting survey for the Coptic axis (improvements §2.2, "candidate — strong").
The corpus today holds ~28k **unannotated** `cop` passages via papyri-ddbdp;
Coptic Scriptorium would add the literary Sahidic (and, since 2024–25,
Bohairic) canon WITH gold-to-automatic lemma/POS/syntax, entity, and
language-of-origin annotation — lemma language #15 and alignment-hub witness
#14. Everything below is from direct inspection: the GitHub org repo list
(`gh api orgs/CopticScriptorium/repos`), the `corpora` repo README, tree
(6,089 entries, recursive git-trees API) and release notes (v6.2.0), the
aggregated `meta.json` (2.3 MB, all 2,390 document records, censused in
scratch), and real sample files read byte-level: `besa.letters` TT/TEI/CoNLL-U
(`on_lack_of_food.*`), `sahidica.mark` TEI (`Mark_01.xml`) and gold TT
(`Mark_04.tt`), `sahidica.nt_TT.zip` (all 259 chapter files censused in
scratch), `AP.004.poemen.65.tt`, `AP.007.n139.laughing.tt`,
`doc.papyri/cpr.2.237.tt`, plus the UD_Coptic-Scriptorium README and the
J. Warren Wells Sahidica license page. Samples live in scratch only; nothing
touched `canonical/` or `db/`.

**Bottom line up front.** One source, one repo
(`github.com/CopticScriptorium/corpora`): **77 corpora / 2,390 documents /
2,375,875 words** (upstream's v6.2.0 release-note count, 2025-12-12),
semiannual versioned releases archived on Zenodo, license **CC BY 3.0/4.0 or
CC BY-SA for ~87% of documents** with three censused exception classes (the
Sahidica NT's custom "academic use only" terms being the one that matters —
it is witness #14, ingestable under the `nc` posture exactly like the PROIEL
NT five). The machine-readable source of record is the **TreeTagger-SGML
`*.tt` layer** (upstream's own README: "generally contain the most complete
representations"), present for all 78 corpus directories, carrying in ONE
file per document: full metadata header, verse-grain CTS URNs, per-verse
English translation, diplomatic + normalized + morph token layers, bound
groups, gold-to-automatic lemma/POS/dependency, entity spans with
Wikification, language-of-origin tags, and manuscript page/column/line
breaks. The census also surfaced layers the packet lead did not know about:
**embedded verse-aligned SBL Greek** in the gold Sahidica book corpora, and
per-document **parallel-witness CTS cross-references**. A new bespoke parser
family is required (the format is SGML-ish stacked tags, not TEI); the
adapter is otherwise a standard git source.

---

## 1. Corpus inventory

**2,390 documents in 77 corpora** (`meta.json`; the repo has 78 corpus
directories — the two treebank collections are upstream-documented
duplicates, see below). Words: 2,375,875 total (v6.2.0 release notes; my
own count of the Sahidic NT TT zip — 245,146 `<norm>` tokens over 259
chapter files — is consistent with that total's scale). Dialect split by
document: 1,567 Sahidic, 815 Bohairic, 8 others (Lycopolitan, Fayumic- or
Lycopolitan-tinged Sahidic; census of `languages`/`language` fields).

The big blocks (documents per corpus, from meta.json):

- **Bible**: `sahidic.ot` 911 + `bohairic.ot` 507 + `bohairic.nt` 260 +
  `sahidica.nt` 259 (all chapter-grain documents, automatic annotation),
  plus gold/checked single-book corpora `sahidica.mark` 16,
  `sahidica.1corinthians` 16, `sahidic.ruth` 4, `sahidic.jonah` 4, and
  Bohairic gold siblings (`bohairic.mark` 16, `bohairic.1corinthians` 16,
  `bohairic.jonah` 4, `bohairic.habakkuk` 3). 2,016 documents carry a
  `chapter` field.
- **Monastic literature**: `apophthegmata.patrum` 126 (the AP corpus, gold
  entities/identities), 26 `shenoute.*` corpora (~110 docs — Canons and
  Discourses of Shenoute of Atripe, White Monastery), `besa.letters` 5,
  `johannes.canons` 14, `pachomius.instructions` 2.
- **Hagiography & homiletics**: 14 `life.*`/martyrdom corpora,
  `pseudo.*` homily corpora (~40 docs), `proclus.homilies`,
  `theodosius.alexandria` 9, `john.constantinople` 2.
- **Apocrypha & Gnostica**: `pistis.sophia` 28 (Askew codex),
  `thomas.gospel` 1 (Dilley's new edition, v6.2.0), `book.bartholomew` 3,
  `acts.pilate`, `mysteries.john`, `dormition.john`, `lament.mary`.
- **Documentary/magical** (the papyri-ddbdp adjacency): `doc.papyri` 3
  (each carries `source="http://papyri.info/ddbdp/…"` — alt-editions of
  items we may already hold; never dedupe, conventions §3),
  `magical.papyri` 8 (Kyprianos cross-refs).

**Formats per corpus** (censused from the git tree): every one of the 78
corpus dirs has TT and CoNLL-U; TEI is loose XML for 1,458 docs but ABSENT
for `sahidica.nt` and `sahidic.ot` (the two biggest corpora); ANNIS
(1,012 MB) and PAULA (97 MB) are query-tool exports we do not need. The four
big bible corpora ship formats as in-repo zips (e.g.
`sahidic.ot/sahidic.ot_TT.zip`, 15.4 MB) — and `sahidica.nt`'s loose
CoNLL-U files are **2-byte placeholders** (verified: `40_Matthew_01.conllu`
= 2 bytes; the real data is only in the zips). Blob totals: TT 183 MB loose
+ ~38 MB zipped; CoNLL-U 148 MB; TEI 101 MB.

**Upstream-documented duplicates** (README, verbatim): the `coptic-treebank`
(86 docs; = UD_Coptic-Scriptorium, 58,974 tokens per the UD README) and
`bohairic-treebank` (22 docs) directories are "convenient collection[s] of
all gold-standard treebanked data, all of which is included in other source
corpora … **identical** to the same documents in the source corpora" —
EXCLUDE both by rule. The gold single-book corpora (sahidica.mark etc.) are
*distinct editions* from their automatic twins inside sahidica.nt (CTS urns
differ: `nt.mark.sahidica_ed` vs `nt.mark.sahidica`) — both ingestable,
never deduped. 17 documents carry `redundant="yes"` (parallel witnesses of
the same conceptual text) — carry the flag as an annotation, upstream's own
double-counting honesty device.

## 2. Update model & fetch → sync_policy

Living master + **semiannual tagged releases** (20+ tags v1.1→v6.2.0;
v6.2.0 2025-12-12 "Late 2025 Release", v6.1.0 2025-09, v6.0.0 2024-12), and
"As of release v6.2.0 corpora releases are also archived on Zenodo"
(DOI 10.5281/zenodo.17917497). Verdict: **sync_policy: versioned** — pin the
release TAG (the UD per-repo pinning precedent), owner-fired re-pin each
release; never track master (it moves between releases — pushed_at
2026-06-10). `license_watch` candidate: the raw README.md URL (the license
section lives there). Repo weight: git size ~2.8 GB (API `size` field);
working-tree blobs ~1.54 GB of which ~1 GB is ANNIS dead weight we never
parse. Fetch verdict in §8.

## 3. Licenses → license_class

Per-document `license` field censused across all 2,390 records (meta.json;
individual files carry the same string in the TT `<meta>` header — verified
in every sample):

| terms (verbatim class) | docs | corpora | license_class |
|---|---|---|---|
| CC-BY 4.0 (incl. "CC-BY 4.0 -" variants) | 349 | AP, Shenoute, Besa, lives, doc/magical papyri… | `attribution` |
| CC-BY-SA 4.0 | 919 | sahidic.ot/jonah/ruth | `attribution` |
| "CC-BY-SA" (unversioned) | 767 | bohairic.nt, bohairic.ot | `attribution` |
| CC BY-SA 3.0 Unported | 14 | johannes.canons | `attribution` |
| "Text is in public domain. Annotations … CC-BY 4.0" | 39 | bohairic.mark/1cor/jonah/habakkuk | `attribution` |
| "(c)2000-2006 by J Warren Wells, for academic use only." | 291 | sahidica.nt/.mark/.1corinthians | **`nc` posture** |
| CC BY-NC-SA 4.0 | 11 | life.aphou/longinus.lucius/paul.tamma/phib | `nc` |
| missing | 3 | book.bartholomew | skip until upstream states one |

The Wells terms (read on the license page the metadata links,
`copticscriptorium.org/download/corpora/Mark/coptic_nt_sahidic.html`):
free of charge "for use in free electronic editions of the New Testament as
long as the full title and copyright information are included"; print
requires written permission. Custom, no-redistribution-beyond-that grant —
same practical posture as the PROIEL NT witnesses (`nc`): local research
fine, MCP-withheld by default, never redistributed. So: **source
`license_class: nc`** (most-restrictive-present, the P10-4 rule) **with
per-document `license_override: attribution` for the ~2,085 CC-BY(-SA)
documents** — the exact P10-4 UD-treebanks mechanism, just inverted in
proportion (here the open class is the majority). Upstream also states the
default in one line (README): "All the documents are licensed CC-BY 3.0 …
or 4.0 unless otherwise indicated," with the three exception classes above
named — our census agrees with their README exactly, plus the NC-quartet
and book.bartholomew gaps their README does not mention. The parser should
read the per-document field, never hardcode (ORACC precedent).

## 4. Annotation layers, exhaustively → nabu surfaces

The `.tt` file is a stack of SGML-ish span tags over tokens (sample:
`besa.letters_TT/on_lack_of_food.tt`; gold NT sample `Mark_04.tt`). Census
of every layer found, each mapped to a surface:

**(a) Three token grains.** Bound group (`orig_group`/`norm_group` — Coptic
orthographic units fusing clitics), word (`orig`/`norm` — the POS/lemma
bearing unit; CoNLL-U MWT ranges = bound groups), morph (`morph` — sub-word
segmentation, e.g. ϣⲡ|ϩⲓⲥⲉ). The word is the annotation grain; NONE of
these is the citable grain (see §7 — passages are verse/translation units;
all three grains ride in `annotations["tokens"]`, the goo300k shape).

**(b) Lemma + POS + dependencies.** Every `norm` carries `lemma`, `pos`
(Scriptorium fine-grained tagset: CFOC, PPERS, VSTAT, ANEGPST…), `func` +
`head` (UD deprels — `nsubj`, `acl:relcl`; the CoNLL-U twin carries the same
tree plus UPOS and UD FEATS `Definite|Gender|Number|Person|PronType|VerbForm`).
Quality is per-document, per-layer metadata (upstream's three-value
vocabulary automatic/checked/gold): tagging gold 122 + checked 244 =
**366 docs gold-or-checked** (all of AP, the gold bible books, most
Shenoute, Besa, magical.papyri, doc.papyri); parsing gold 117; segmentation
gold+checked 423. The rest is release-quality automatic NLP. → Surface:
`passage_lemmas` (lemma language #15). Policy knob for the gate: default
mints lemma rows from gold+checked docs only (the goo300k/IMP gold-only
precedent); the "include automatic" flip would light up the whole 2.38M
words (upstream ships them as citable releases, quality labels carried
per document in annotations) — owner call, stated openly. → Morph facets:
v1 can map the Scriptorium tagset through the P13-6 UD façade table
(the PROIEL-positional-tag precedent); the CoNLL-U FEATS join is the v2
richer path.

**(c) LANGUAGE-OF-ORIGIN token tags — the language-contact layer.**
`<lang lang="…">` spans wrap loanword tokens. Censused over the whole
Sahidic NT (259 files in scratch): **21,127 of 245,146 tokens = 8.6%**
tagged — Greek 18,345, Hebrew 2,716, Aramaic 57, Egyptian 5, Latin 4;
4/97 tokens (4.1%) in the Besa sample, 70 spans in gold Mark 4. This is a
census-density gold mine nabu has no surface for yet. Proposed surfaces:
(1) per-passage loan counts + per-token `lang` in `annotations["tokens"]`
(free, v1); (2) a **language-contact facet** — `search --loans grc` scoped
like `--morph` (needs a small indexer pass over the token annotations, a
passage_lemmas-style derived table or a column on it; argue schema at the
gate); (3) the borrowing signal for cognates/etym: a Coptic loanword's
lemma (ⲁⲣⲭⲏ, ⲉⲩⲁⲅⲅⲉⲗⲓⲟⲛ) is a *Greek word in Coptic clothing* — a
crosswalk from tagged loan lemmas to grc gold lemmas would mint
`dictionary_reflexes`-style borrowed edges, converging with the P17-3
`borrowed` column work. v1 ships (1); (2)/(3) are named v2 packets.

**(d) Entities + Wikification.** `<entity head_tok text entity="person|
place|abstract|object|organization|…">` spans (upstream documents ten
categories; five observed in samples), nested, with
**`identity="Poemen"`-style Wikipedia links** on named entities (verified
in `AP.004.poemen.65.tt`) — and a doc-level `people`/`places` roster in
the metadata header (1,157/893 docs; e.g. Matthew 1's full genealogy
roster, "Mary, mother of Jesus; …"). Quality: entities gold 168/checked
107/automatic 1,286; identities gold 186/checked 220/automatic 1,141.
This is GOLD NER arriving free — the improvements §3.5 prosopography seed
without the cluster. Proposed surfaces: entity spans in annotations (v1);
`people`/`places` rosters into document-level metadata; a v2 links-journal
producer minting passage→identity edges (`nabu links` already has the
edge vocabulary); place identities as a document_axes place enrichment.

**(e) Verse-aligned English translations.** `<translation translation="…">`
spans (or `verse_n/@translation` in the older TT dialect — BOTH shapes are
live in the repo, version_n 4.1.0 vs 4.5.0 files) aligned to the verse
units; 2,373 of 2,390 docs name a translation source (WEB for NT, Brenton
1851 for OT, named scholars for literary texts; 142 "none"). CoNLL-U
carries the same as `# text_en`. → `--parallel`: mint `-en` sibling
documents per translated doc (the ORACC P13-4 shape: one passage per
translation unit at its anchor citation) — the readable-corpus win, v1.
**Arabic translations exist for 76 docs but upstream ships them only in
ANNIS** (v6.2.0 release notes, verbatim: "the Arabic translations are only
available in ANNIS") — deferred, format-blocked; unblock = parse relANNIS
for just that layer or wait for upstream TT export.

**(f) Embedded verse-aligned SBL Greek (not in the packet lead).** The
gold Sahidica book corpora carry per-verse `sbl_greek` (the full SBLGNT
verse text, apparatus sigla included) + `sbl_apparatus` spans — verified
in Mark_04.tt (41 sbl_greek spans / 41 verses); `Greek_source` metadata
credits SBLGNT on 141 docs (the AP's are Nau-collection *citations*, not
embedded text). We already hold SBLGNT as a source — this layer is a
ready-made Coptic↔Greek verse bitext and an integrity cross-check, but the
alignment hub ALREADY aligns sahidica verses to sblgnt via the registry, so
v1 just carries `sbl_greek`/`sbl_apparatus` per passage in annotations
(license: SBLGNT is CC BY — compatible); a v2 idea is apparatus-aware
collation (§1.9's edition-vs-edition case).

**(g) Diplomatic/normalized parallel layers + manuscript topology.**
Per token: `orig` (diplomatic — supralinear strokes U+FE24/FE25/FE26,
overlines, ⳿ kept) vs `norm`; per bound group: `orig_group`/`norm_group`.
Page topology: `pb_xml_id` (manuscript page — "BB553" = MONB.BB p. 553),
`cb_n` (column), `lb_n` (line) — with words and even MORPHS split across
line breaks (ϣⲡ ends lb 1, ϩⲓⲥⲉ opens lb 2 *inside one norm token* —
the parser quirk to preserve). `hi_rend` rendering spans. 8 docs carry
`facsimile`/`image` URLs. → §7 for the text-layer verdict; page/column/line
ride in annotations (the diplomatic layout is how a future facsimile or
codicology surface would anchor).

**(h) Citation structure.** `chapter_n`, `p_n` (edition paragraph, "I.1"),
`verse_n`, and `vid_n` = a full CTS URN per verse unit
(`urn:cts:copticLit:besa.food.monbbb:1.1`) — upstream mints verse-grain CTS
identity for literary texts too, not just scripture. Document-level
`document_cts_urn` on all 2,390 docs (`copticLit`/`copticDoc` namespaces).
→ URNs and passage grain, §7–8.

**(i) Parallel-witness cross-references.** 77 docs carry `witness` =
CTS URN(s) of the *other manuscript's* version of the same text (e.g.
theodosius.alexandria Budge vs Vatican witnesses; 432 docs say
`redundant="no"`, 17 `yes`). → a links-journal edge class (v2 producer:
witness edges are hand-asserted upstream — cheap, high-value for the
collation surface); also the honest filter for quantitative work.

**(j) Reading order.** `next`/`previous` CTS chains (1,643/1,640 docs) +
`order` (209) — codex reading order across fragmentary Shenoute leaves.
→ annotations v1; nothing else needs it yet.

## 5. Document metadata → document_axes

- **Dates: 234 docs** carry `origDate` + `origDate_notBefore`/`notAfter`
  (4-digit CE strings, e.g. 0500/0799) + `origDate_precision`
  (high 20 / medium 178 / low 35) — manuscript dates (copying), mostly
  literary codices ("between 500 and 799 C.E.", theodosius colophon-dated
  983/987 — precision "high" IS colophon dating). Maps 1:1 onto
  `document_axes(not_before, not_after, precision, date_raw)`; a
  `CopticScriptorium` extractor in AxisBuilder is a straight field read
  (the HGV shape, no join needed). The bible corpora are undated
  (digital editions) — honest absence, no row.
- **Places**: `origPlace` (White Monastery 227, St. Mercurius 38, Hagr
  Edfu 12, Hamuli…), `placeName` (Atripe…), `country` (Egypt, 430) →
  `place_name`. **Trismegistos ids on 83 docs** + `kyprianos_*` on the
  magical papyri → `place_ref`-adjacent stable ids; Trismegistos also
  joins toward HGV/papyri metadata (a future links edge).
- **Repositories**: 362 docs, 28 collections (Naples Biblioteca Nazionale
  118, British Library 113, ÖNB 33, BnF ~42 with spelling variants…) +
  `collection`, `idno` (shelfmark), `msName` (57 sigla: MONB.EG, MERC.AI…),
  `objectType` (codex/papyrus/ostracon), `pages_from/to`. → annotations +
  the place/repository axis note; spelling variants carried verbatim
  (we never clean upstream).
- **Authorship**: `author` (395: Besa, Shenoute, Johannes…),
  `attributed_author` (78 — the pseudo-* corpora's honest attribution
  field), `copyist` (26), plus `paths_authors/works/manuscripts` ids
  (376/318 docs) linking to the Italian PATHS project's authority lists.
- **Editions**: `Coptic_edition` (391 — printed edition citations),
  `source` (2,240 — e-text provenance incl. papyri.info URLs),
  `Arabic_translation` credits (76), `endnote`/`note` (codicological
  notes, lacunae).

## 6. The alignment hub — witness #14 (and #15–17)

**Witness #14, verdict: YES — `sahidica.nt`, the complete Sahidic NT at
verse grain.** Verified: 259 chapter documents, all 27 books, **7,906
verse units** (my census of the TT zip; NT convention counts ~7,957 —
the gap is upstream's edition, carried honestly), every verse under
`verse_n` with per-verse WEB English. Registration shape: adapter merges
chapter files into per-book documents (the CTS work id `nt.matt.sahidica`
is shared by a book's chapters — the merge is a grouping, not surgery),
passages `<chapter>.<verse>` → the **existing `cts-verse` extractor** with
a `documents:` per-book map, registry `books:` aliases mapping upstream
book tokens (matt, mark, 1cor…) onto the work vocabulary (MATT, MARK…) —
zero new extractor code, the SBLGNT/Vulgate shape exactly. License nc →
the hub renders it like the PROIEL five (labels are the point;
MCP-withheld unless `include_restricted`).

Three more witnesses ride the same adapter, all `attribution`:
**bohairic.nt** (260 chapter docs — witness #15, a second Coptic dialect
column), and for the `ot` work **sahidic.ot** (911 docs, CC BY-SA 4.0) +
**bohairic.ot** (507). Caveat carried from upstream's own metadata note:
"Versification may not always align with traditional Septuagint
versification" — the `ot` work's registrar claim (Greek-tradition
numbering) should be spot-checked at gate time on Psalms/Jeremiah before
those books enter the registry map; registering the clean books first and
extending from minted urns is the P11-5 precedent. The gold sahidica.mark
(`nt.mark.sahidica_ed`) stays an alt-edition OUTSIDE the registry (one NT
witness per edition; two Sahidica editions would false-double Mark).

## 7. Passage grain + text-layer verdict

**Passage = the verse/translation unit** (`verse_n`/`vid_n`, upstream's own
citable grain — CTS URNs exist at exactly this grain), NOT bound group or
word: search wants readable spans, the hub wants verses, and the
translations are aligned at this unit. Citation = `chapter.verse` (bible)
or the vid_n tail (literary; falls back to `p_n`/ordinal where a corpus
lacks verse_n — flagged non-canonical, the GRETIL stance). All token grains
ride in `annotations["tokens"]` (per token: orig, norm, morphs, lemma, pos,
func/head, lang, entity spans by reference).

**Text layers**: passage `text` = the **diplomatic reading** (orig_group
sequence, strokes kept, the witness's spelling — canonical means canonical;
the goo300k precedent where historical spelling is the text and the
regularized layer is annotation). The upstream-normalized layer (norm) is
carried per token; `text_normalized` is minted through the ONE folding
boundary (conventions §9) over the **norm-layer sequence** as derivation
source — the ccmh-txt precedent exactly (derivation source carried in the
row, recomputable, honest search: queries hit regularized spellings, KWIC
shows the diplomatic). Conventions §9 needs a new `cop` entry: strip
combining overlines/supralinear strokes (U+0304/0305, U+FE24–FE26),
ⲟ⳿-class editorial marks, fold nothing else (the improvements §2.2
"supralinear strokes" question, answered).

## 8. Ingestion design sketch

- **Adapter**: `Nabu::Adapters::CopticScriptorium`, ONE git source
  (registry `coptic-scriptorium`, `enabled: false`), single repo — not the
  UD per-repo pattern; per-corpus subdirectories walked like ORACC walks
  projects. Fetch via `Nabu::GitFetch` **pinned to the release tag**
  (v6.2.0; owner re-pins per semiannual release). Clone ~2.8 GB one-time
  (the latinLit precedent; ~1 GB of it ANNIS/PAULA dead weight we never
  read — honest cost, stated). The four bible corpora's TT zips are
  unzipped into the workdir at discover time (in-repo zips — a small new
  wrinkle; the unzip helper exists from ZipFetch/freising work).
- **Parser family**: new bespoke `CopticTtParser` (TT/TreeTagger-SGML is
  not XML — unbalanced-looking span stacks, attributes-as-layers; a
  line-oriented stack parser, DdbdpParser-tier). TEI is NOT viable as
  primary (absent for the two biggest corpora; its gold-TT information is
  strictly poorer). CoNLL-U join deferred to v2 (UD FEATS; everything else
  TT already carries).
- **Documents**: one per TT file, EXCEPT bible chapter files merged to
  per-book documents (§6). Corpus dirs `coptic-treebank`,
  `bohairic-treebank` excluded by rule (upstream-documented duplicates);
  `book.bartholomew` skipped until it carries a license.
- **URN**: `urn:nabu:coptic-scriptorium:<cts-tail>:<citation>` where
  cts-tail is the upstream `document_cts_urn` minus
  `urn:cts:copticLit/copticDoc:` (stable, upstream-minted:
  `besa.food.monbbb:1.2`, `nt.mark.sahidica:1.1`,
  `papyri_info.tm82127.cpr_2_237:…`).
- **Language**: `cop` (the live papyri code); dialect (Sahidic/Bohairic/
  Lycopolitan) as a document annotation, not a language split (the orv-be
  BCP-47 precedent — finer tag noted, coarse tag ruled).
- **License**: source `nc`, per-document `license_override: attribution`
  from the per-file license field (P10-4 mechanism, §3).
- **Size estimate**: ~75–80k passages (2.38M words / ~31 words per verse
  unit measured on the NT), ~2.4M token records in annotations —
  annotations JSON is the bulk, order ~300–400 MB in the catalog
  (flagged estimate); passage_lemmas at the gold+checked default is a
  small fraction of that. FTS growth modest (Coptic script, ~15 MB of
  verse text).
- **Guards**: UD-source dedup — `UD_Coptic-Scriptorium` must never enter
  the `ud` TREEBANKS map while this source is live (the chu-PROIEL
  exclusion, inverted: the native repo is richer and wins). The two TT
  metadata dialects (translation-as-element vs verse_n/@translation) both
  in fixtures. `sahidica.nt`'s 2-byte CoNLL-U placeholders must never be
  parsed as documents (skip-by-rule, counted).

## 9. Fixture plan (the gate deliverable)

Real files, trimmed, into `test/fixtures/coptic-scriptorium/` with a
README noting retrieval date + URLs — snapshots happen AFTER the owner
gate (CLAUDE.md fixture rules):

1. **`besa-letters/besa.letters_TT/on_lack_of_food.tt`** (22 KB, whole
   file — already small). Preserves: modern TT dialect (translation
   elements), gold everything, full MS metadata block (MONB.BB, Naples,
   origDate 0500–0799 medium → the axis assertion, Trismegistos 108395),
   entity spans, morphs, **the morph-split-across-lb quirk** (ϣⲡ|ϩⲓⲥⲉ),
   Greek `lang` spans, `vid_n` CTS verse urns, CC-BY 4.0 override.
   Sibling `on_lack_of_food.conllu` (9.7 KB) rides along for the future
   FEATS join test.
2. **`sahidica.nt_TT.zip` members `41_Mark_01.tt` (trimmed to the meta
   header + verses 1–12) + `57_Philemon_01.tt` (whole, one-chapter
   book)**. Preserves: the in-repo-zip discover path, the OLDER TT dialect
   (verse_n/@translation, v4.1.0), the Wells license string → `nc`
   override + MCP-withheld test, chapter-file→book merge INCLUDING the
   single-chapter edge case, `people` roster metadata, witness-#14 verse
   grain.
3. **`AP/apophthegmata.patrum_TT/AP.004.poemen.65.tt`** (19.6 KB, whole).
   Preserves: `identity` Wikification, `Greek_source` (Nau citation),
   `Arabic_translation` credit (metadata-only, the honest ANNIS gap),
   gold entities, AP corpus shape.
4. *(optional 4th, if the owner wants the documentary hook now)*
   `doc-papyri/doc.papyri_TT/cpr.2.237.tt`: `copticDoc` urn namespace,
   `source=papyri.info` alt-edition cross-reference, `pb` recto/verso.

Quirks the set must keep: supralinear strokes in orig vs stripped norm,
nested entity spans, the license-string HTML entities
(`&lt;a href=…&gt;`), `redundant`/`witness` fields, `sbl_greek` spans
(present in a Mark_04 trim if the owner prefers it over Mark_01 —
either works; Mark_04 also carries `sbl_apparatus`).

## 10. Ranked verdict

**v1 ships (one packet, post-gate):** the `coptic-scriptorium` source as
sketched — all 75 non-duplicate, licensed corpora; TT parser; verse-grain
passages; diplomatic text + norm-derived search form + `cop` folding entry;
token annotations with all grains + lang + entities + identities;
`-en` translation siblings (`--parallel`); document_axes extractor
(234 dated docs + places); passage_lemmas from gold+checked (366 docs;
"include automatic" = explicit gate knob); alignment-hub registry entries
for witness #14 (sahidica NT, nc) + #15 (bohairic NT) + `ot`-work Sahidic
and Bohairic OT books (clean books first); P10-4 license overrides; UD
dedup guard.

**v2 defers (named, in likely order of value):** (1) the loanword search
facet `--loans` + the Coptic→Greek borrowing crosswalk into
dictionary_reflexes (converges with P17-3's `borrowed` column); (2) the
links-journal producers for witness edges and entity identities;
(3) CoNLL-U FEATS join for full UD morph facets; (4) Arabic translations
(format-blocked in ANNIS — unblock: relANNIS single-layer parse or
upstream TT export); (5) the Coptic Dictionary Online lexicon
(`CopticScriptorium/dictionary`, CC BY-SA 4.0, BBAW XML — the desk-loop
occupant `CDO:cop`, a dictionary-shelf packet of its own); (6) apparatus-
aware collation over `sbl_greek`/`sbl_apparatus`.

**Blocked/skipped + unblock paths:** `book.bartholomew` (3 docs, no
license — unblock: upstream issue asking for one); `editions-public-domain`
repo (upstream's own "not ready for public release" — watch);
`paths-longtexts-dev` (MIT-licensed PATHS hagiographies, active dev repo —
material flows into future corpora releases; ingest via releases, not the
dev repo); Arabic translations (above).

## 11. Honest unknowns

- Per-corpus word counts are not published; my token counts are measured
  only for sahidica.nt (245,146) — others estimated from file sizes.
  Fixture-time parsing will give exact counts.
- The `ot` versification question (§6) is asserted by upstream as
  imperfect but uncensused; needs the gate-time spot-check before OT
  registry entries go in.
- The TT dialect inventory (translation-element vs attribute; `verse_vid`
  in gold files) is verified on 8 samples across 6 corpora, not all 77 —
  the parser must fail loudly on unknown span types (the ORACC cdl-node
  guard stance).
- Whether `sahidica.nt`'s Wells terms taint the ANNOTATION layer (Coptic
  Scriptorium's own work, CC-BY-labeled elsewhere) is legally untested;
  the survey takes the conservative read (whole-document nc).
- Bohairic OT/NT "CC-BY-SA" carries no version number upstream; treated
  as attribution-class regardless of version.
