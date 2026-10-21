---
name: nabu-etym
description: "Use when tracing etymologies, reconstructions, cognates and loans through the nabu MCP tools (nabu_etym, nabu_define with *proto forms, nabu_cognates): the Wiktionary reconstruction shelves, IE-CoR, LIV, the StarLing bases, WOLD, CLICS, DÉRom and de Vaan. Covers reflex edges and the upward walk, gold attested counts versus null, ASCII-folded proto headwords, typed relations and the borrowed flag, colexification versus cognacy, loans hidden in descendant trees, and license classes."
license: MIT
compatibility: "Requires the nabu MCP server (`bin/nabu mcp`, read-only, stdio) over a locally built Nabu catalog; tool names are the nabu_* set (nabu_status, nabu_search, nabu_show, and the desk instruments)."
metadata:
  desk: etym
  origin: hand-tuned
  sources: "calfa-lexicon cldf-spine clics derom edl iecor liv nabu-lects sabellic-loans starling westoldturkic wiktionary-recon wold"
---

# The Comparative Indo-Europeanist — the `etym` desk

The Comparative Indo-Europeanist — laryngeals, reflex chains, the long descent of words.

The reconstruction shelves: the kaikki proto-extracts, IE-CoR cognacy, LIV, the Leiden Latin dictionary, StarLing's bases, and the curated loan edges. Non-IE lanes of the same shelves ride their own axes too — dual-tagging, never folding.

## Sources on this desk

The class is the machine-actionable reading of each source's data license; the
verbatim upstream terms are in `docs/02-sources.md` of the Nabu repository.

<!-- nabu:skill-sources:begin — generated from config/sources.yml by `rake skills:scaffold`; edit outside this block -->
| Source | Upstream | License class |
| --- | --- | --- |
| `calfa-lexicon` | Calfa — Classical Armenian dictionary databases (NBHL, Bedrossian, Calfa 1861, Ačaṙean) | nc |
| `cldf-spine` | Concepticon + Glottolog — the CLDF reference spine (concept/languoid resolver instrument) | attribution |
| `clics` | CLICS³ — Database of Cross-Linguistic Colexifications (aggregate network, v1.1) | attribution |
| `derom` | DÉRom — Dictionnaire Étymologique Roman (ATILF/Ortolang) | nc |
| `edl` | de Vaan — Etymological Dictionary of Latin (Brill 2008), LiLa LOD skeleton (CIRCSE) | nc |
| `iecor` | IE-CoR — Indo-European Cognate Relationships database (lexibank/iecor v1.2) | attribution |
| `liv` | LIV — Lexikon der indogermanischen Verben (Rix 2001), LiLa LOD (CIRCSE) | attribution |
| `nabu-lects` | nabu-lects — the lect registry (anchor x stage x variety x orthography resolver) | attribution |
| `sabellic-loans` | Sabellic → Latin loans — en.wiktionary curation (Oscan/Umbrian/Sabine) | attribution |
| `starling` | StarLing / Tower of Babel — etymological databases (Pokorny IEW + PIET + Vasmer + Germanic + Baltic + Kartvelian + Altaic + North Caucasian + Sino-Tibetan + Dravidian + Chukchee-Kamchatkan + Yenisseian + IE lexicostatistical wordlists + the Altaic/Caucasian/Dravidian/Kiranti branch bases) | attribution |
| `westoldturkic` | West Old Turkic — Turkic loanwords in Hungarian (Róna-Tas & Berta 2011, CLDF) | attribution |
| `wiktionary-recon` | Wiktionary reconstructions + attested Celtic, Italic, Etruscan, Old Japanese and Chinese — kaikki.org machine-readable extracts (Proto-Slavic, PIE, Proto-Germanic, Proto-Balto-Slavic, Proto-West Germanic, Proto-Italic, Proto-Indo-Iranian; Old Irish, Middle Irish, Middle Welsh, Umbrian, Etruscan, Chinese) | attribution |
| `wold` | WOLD — World Loanword Database (Haspelmath & Tadmor eds.; lexibank/wold v4.2) | attribution |
<!-- nabu:skill-sources:end -->

## What the shelves hold

- `cldf-spine` — Concepticon and Glottolog — the reference spine of comparative linguistics: Concepticon's 4,033 concept sets (gloss, semantic field, definition) and Glottolog's 27,177 languoids (glottocode, name, ISO 639-3 code, level, family), the shared identifier systems by which cross-linguistic datasets such as WOLD, CLICS³ and IE-CoR name their meanings and languages. CC BY 4.0 (Concepticon v3.4.0; Glottolog v5.3).
- `clics` — CLICS³ — the Database of Cross-Linguistic Colexifications (Rzymski, Tresoldi et al. 2019): a network of which meanings share a single word across roughly 3,000 language varieties — 2,919 Concepticon-linked concepts joined by 4,228 colexification edges, each weighted by how many language families, varieties and words attest the pairing. A compass for semantic shift and polysemy across the world's languages. CC BY 4.0.
- `derom` — The Dictionnaire Étymologique Roman (DÉRom, dir. Éva Buchi and Wolfgang Schweickard; ATILF, CNRS/Université de Lorraine and Universität des Saarlandes) — the reference comparative-method reconstruction of Proto-Romance. Each article reconstructs one etymon (*/ˈlakt-e/ "milk", */kaˈβall-u/ "horse") strictly from the Romance evidence itself, with per-language reflex sections spanning the whole family — Romanian, Dalmatian, Italian, Sardinian, Friulian, Romansh, French, Occitan, Catalan, Spanish, Asturian, Galician, Portuguese and their historical stages — each reflex cited against the standard etymological literature. The etymons feed the library's etymology surfaces as Proto-Romance (the roa:pro lect), beside the Wiktionary-derived and expert-curated witnesses. Published openly through the Ortolang repository under CC BY-NC-SA 4.0.
- `edl` — de Vaan, Etymological Dictionary of Latin — the LiLa linked-data skeleton of lemmas and etymological relations (non-commercial license, served with its label).
- `iecor` — IE-CoR (lexibank/iecor v1.2, CC BY 4.0, sha-pinned immutable Zenodo DOI): the expert-curated Indo-European cognacy matrix as a dictionary shelf — **4,981 cognate-set entries** under the collective `ine` tag / **26,325 reflex rows** (2,308 loan-flagged, feeding `borrowed`); 143 language notes accreted as `iecor` sections in the local-language dossiers (§8i) — the dossier shelf's first programmatic writer. An independent third etymological witness beside kaikki and MW: `etym срьдьцє` now reaches \*k̑erd- on the IE-CoR card with grc καρδία ~ lat cor ~ got hairto and live attestation counts.
- `liv` — LIV-LOD (CIRCSE/LiLa, CC BY-SA 4.0 with publisher permission): **305 PIE verbal etymons** with verbal stem types in the entry bodies / **374 reflex edges**; first user of the lila-ttl (Turtle) parser family.
- `nabu-lects` — The library's lect registry, consumed from the nabu-lects sister project (github.com/arvicco/nabu-lects, CC BY 4.0): a small curated registry of language varieties — each identified by genealogical anchor, historical stage, register or recension, and orthography (lat:med is Medieval Latin, grc:koi Koine Greek, zho/lit Literary Chinese as the written register it is, roa:pro Proto-Romance as a marked reconstruction) — with a universal mapping from standard language codes onto them and explicit descent edges (Romance continues from Latin, Portuguese and Galician fork below Old Galician-Portuguese). A feature module, not a corpus: it holds no texts, but resolves the library's stored codes into historical stages — the stage ladders on language cards, stage-aware search, and the attested-versus-reconstructed distinction the code system alone cannot state.
- `sabellic-loans` — A curated set of 85 Latin lemmas with Sabellic sources — Oscan 48 (rufus, tofus, prope, Pompeii…), Umbrian 11 (omentum, Iguvium…), and Sabine 26 (hirpus, strena, Quirites, Nero…) — distinguishing explicit borrowings from derived forms, with the Old Italic script etyma kept verbatim. Compiled from English Wiktionary's borrowing and derivation data; CC BY-SA and GFDL (the Wiktionary dual license).
- `starling` — Starostin StarLing etymological bases — 2,222 Pokorny Indo-European roots and 3,291 comparative Indo-European etymologies joined into the reconstruction shelf.
- `westoldturkic` — West Old Turkic: Turkic Loanwords in Hungarian by András Róna-Tas and Árpád Berta (2011), as the CLDF dataset extracted by LoanpyDataHub (Zenodo, version 2.0). It is a dictionary of 480 reconstructed etyma of West Old Turkic, the r-Turkic (Bolgar-type) branch that Hungarian borrowed from. Each etymon is traced down its Hungarian descent (Early and Late Ancient, Old and modern Hungarian), with the borrowing step marked, the phonemic segments given and the Hungarian first-attestation year recorded. CC BY 4.0.
- `wiktionary-recon` — Wiktionary reconstruction extracts — 13,053 entries across three proto-language shelves plus the attested-Celtic dictionaries, reflex chains linking reconstructions to the corpus.
- `wold` — audit: 41 vocabulary shelves in 41 recipient languages sampled worldwide by typological design (eng/goh/jpn/vie/yaq/…) — structurally unbounded, dictionary-side. Whole-grain attribution put "axes: etym" on every recipient code's language card and folded all 41 codes into the etym desk's gold-lemma language set (claiming e.g. goh gold rows held by the germanic desk's sources); excluded from count-less surfaces.

## Worked examples

Compositions verified live against a Nabu library (holdings differ per box; check `nabu_status` first):

- *Walk прьстъ back as far as it goes.* — `nabu_etym прьстъ (lang: chu)`: The full chain *pьrstъ → Proto-Balto-Slavic *pírštan → PIE *per- "before, in front", each shelf with glosses, licenses, and corpus-attested cognate counts (Sanskrit pára ×9,769, Latin prīmus ×1,345, Hittite peran, Greek πρίν with gold and silver counts listed separately).

## Field semantics on this desk

- **Reconstructions are dictionary entries; reflexes are edges.** A
  reconstruction shelf entry (Proto-Indo-European, Proto-Slavic, Proto-Germanic
  and the other `-pro` shelves of `wiktionary-recon`; Pokorny and the other
  StarLing bases; LIV; de Vaan's Latin) carries descendant *reflexes* — the
  worded nodes of a descendants tree, each with its upstream language code, form
  and romanization. Shelf codes are Wiktionary etymology codes (`ine-pro`,
  `gem-pro`, `sla-pro`), not ISO 639-3.
- **`nabu_etym` walks upward.** An attested lemma → the reconstructions naming
  it as a descendant (`matched_via`) → their ancestors, each shelf entered once.
  Romanization bridges scripts (Gothic in its own script reaches `*gudą`
  through `guþ`). A lemma with no reflex edge falls back to a headword lookup,
  then to a prose dictionary article, then to a list of the live shelves.
- **`attested_count` is gold passages in this library.** It counts gold-lemma
  passages; `null` means not countable here, never zero. Silver and equivalence
  counts are reported beside it and must not be summed into it.
- **Proto headwords fold to ASCII** (ʰ→h, ʷ→w), so `bhewgh` reaches `*bʰewgʰ-`;
  laryngeal subscripts survive. A leading `*` scopes a lookup to the
  reconstruction shelves.
- **Relations are typed.** Edges carry `inherited`, `derived`, `borrowed`,
  `learned-borrowing` or `cognate`, and a `borrowed` flag that is three-valued:
  true, false, or null (not determined). A loan marker on any step of a chain
  marks the chain.

## What each shelf claims

- `iecor` — IE-CoR: expert cognate *judgments* for a fixed meaning list across
  Indo-European varieties; one entry per cognate set, with loan events flagging
  every member of a borrowed set.
- `liv` — LIV²: Proto-Indo-European verbal roots with their Latin continuations
  only.
- `starling` — the Tower of Babel etymological bases (Moscow school), including
  long-range families; a reconstruction there is that school's hypothesis.
  Credit is per base.
- `wold` — the World Loanword Database: per recipient language, each word's
  borrowed status on a five-point scale from clearly borrowed to no evidence;
  donor words resolved by name.
- `clics` — CLICS colexifications: meanings expressed by one word across many
  languages. **Colexification is a semantic pattern, not cognacy and not
  borrowing.**
- `derom` — DÉRom Proto-Romance articles, with first-attestation dates of the
  Romance reflexes.
- `edl` — de Vaan's Latin etymological skeleton (Proto-Italic and PIE links,
  inheritance only; the dictionary's prose is not held).
- `sabellic-loans`, `westoldturkic` — curated loan lanes (Sabellic into Latin;
  West Old Turkic into Hungarian, where only the borrowing step is marked).

## Conflation traps

- **Descendant trees include loans.** Wiktionary descendants lists do not always
  flag borrowings; a Gothic and an Old Church Slavonic word meeting at a
  Proto-Germanic root (bread: *hlaibaz*) is very possibly a Germanic loan into
  Slavic. A PIE meet is the inheritance signal; a branch-level meet across
  branches needs a loan check.
- **Absence is not evidence.** Only a minority of gold lemma types reach any
  reconstruction (roughly a third of Gothic, a fifth of Old Church Slavonic
  lemma types); a word with no etymology here may simply be uncovered.
- **Shelves disagree by design.** Pokorny, LIV, IE-CoR and Wiktionary are
  distinct scholarly positions; report which shelf a reconstruction comes from
  and do not merge their forms.

## Licensing on this desk

Wiktionary-derived shelves are CC BY-SA + GFDL (`attribution`); IE-CoR, WOLD,
CLICS and the West Old Turkic set are CC BY (`attribution`); LIV is CC BY-SA;
StarLing is free for any use with acknowledgment (`attribution`, per-base
credit). DÉRom and de Vaan's skeleton are `nc`.

## House cautions

- **Data license is not code license.** This guidance text is MIT; every passage
  carries its own `license_class` (`open`, `attribution`, `nc`, `odbl`, and — excluded
  by default — `research_private` / `restricted`). `nc` forbids commercial reuse of the
  quoted text; `attribution` and `odbl` require naming the source edition (`odbl`
  also binds derived databases to share-alike). A `credit` key, when present, must
  travel with any quotation.
- **An empty result is not absence of evidence.** Call `nabu_status` before concluding
  a text, word or form is unattested: the shelf may be unsynced on this box, the
  language may be indexed at another grain, or the class may be excluded by default.
- **Search is folded, `nabu_show` is pristine.** Matching runs over a folded form
  (case, diacritics, and per-language rules); quote only the pristine text
  `nabu_show` returns, never a search snippet or a folded phrase.
- **Lemma tiers differ in evidential weight.** `gold` lemmas are verified annotation
  and the only tier that counts as attestation; `silver` lemmas are upstream-automatic
  and always labeled; `equivalence` rows are glosses, never attestation. A lemma
  search reaches only the lemmatized minority of the corpus.
- **Dates are typed.** A document's primary dated row has a class — `artifact` (the
  object's own dating), `composition` (an attributed author-era date), `edition` (a
  print year, never the text's date), or `silver` (a tool estimate, never an upstream
  claim). Years are signed, with no year 0. Use `date_basis` to keep the classes
  apart.

## Reproducibility

Record, per claim: the passage or document `urn`, the `source` slug, its
`license_class` (and `credit` when served), the exact tool call and arguments, and the
date of the `nabu_status` snapshot the catalog answered from. Upstream editions are
revised; the urn plus the catalog date is the citation, the snippet is not.
