# CLARIN.SI repository survey (P17-6, 2026-07-13)

Owner request: "check what else is available on clarin.si in addition to
goo300k/imp/freising." Method: **full OAI-PMH harvest** of the repository
(`www.clarin.si/repository/oai/request`, oai_dc, 11 resumption pages) —
**1,002 active items** (1,010 records, 8 deleted): 556 corpora, 303 lexical
resources, 142 tools/services. Keyword/facet sweeps over all titles +
descriptions + subjects (historical/diachronic/medieval/Slavonic/treebank/
dictionary/etymology + per-language nets), then **per-item DSpace REST
bitstream checks** (34 handles) to separate real deposits from metadata-only
stubs, then small format samples to scratchpad (Damaskini CoNLL-U + TSV,
Pleteršnik, JSV, besedje16, Trubar concordance, Franček historical module,
HyperVerb). Every license below is the deposit page's verbatim CC label from
the OAI record; access class (PUB/ACA/RES) from the same field. Freising is
NOT a clarin.si deposit (it lives at nl.ijs.si/e-zrc) — the three held
clarin.si-adjacent sources are goo300k (11356/1025), IMP (11356/1031), and
the eZISS Freising edition.

**Bottom line up front.** The repository is ~90% modern Slovenian/South
Slavic NLP (Gigafida/ParlaMint/MaCoCu/CLASSLA class — out of scope by the
packet's own ruling). What remains on-axis splits cleanly in three: (1) ONE
genuinely new, gold-annotated, openly licensed historical corpus we hold
nothing like — the **Damaskini pre-standardized Balkan Slavic corpus**,
which partially fills the Bulgarian/Macedonian gap survey II declared
blocked everywhere; (2) a **Slovenian historical dictionary shelf** (three
ZRC SAZU dictionaries, all CC BY 4.0, real XML files, keyed to the exact
period and texts goo300k/IMP already hold); (3) the **ELEXIS mirage**: 141
ELEXIS-titled dictionary records (Monier-Williams, Old Norse ONP, Middle
High German, Daničić, Karadžić, Miklosich...) that are ALL metadata-only —
every one of the 18 checked has zero bitstreams. Nothing on-axis is ACA/RES;
every real candidate is PUB with an explicit CC label.

---

## Ranked verdict — v1 picks

### 1. Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1 ("Damaskini") — the find

**Status: SHIPPED (P23-1, 2026-07-15) — adapter + registry landed,
`enabled: false` awaiting the owner-fired first real sync.** The fixture
pass confirmed the survey's read with three corrections: the CoNLL-U's
surface text is the mixed Latin/Cyrillic *diplomatic* transliteration (the
fully Cyrillic layer lives only in the TSV); the corpus assigns NO
per-document language — the philological PDF's Norm classification (read
at Phase B as planned) maps veles/vukovic/kievski → chu and the rest →
bul, with Norm+Origin as facets; and the TSV token layers are genuinely
phase-2 (per-file column layouts vary 15–20 cols, 5 files disagree with
the CoNLL-U by 1–3 sentences — censused, journaled in backlog P23-1).
02-sources row 57 is the full record.

- **Handle:** <http://hdl.handle.net/11356/1441> (v1.0 = 11356/1368, GPL-3,
  superseded — ingest 1.1 only).
- **License (verbatim):** "Creative Commons - Attribution-ShareAlike 4.0
  International (CC BY-SA 4.0)", access **PUB** → `attribution`, MCP-safe.
- **Content:** 24 documents (23 samples + preface), **6,036 sentences /
  53,257 tokens** (counted in the downloaded CoNLL-U) of "damaskini" and
  other Balkan Slavic manuscripts and prints, **15th–19th c.** — hagiography
  and apocalyptica on the Church-Slavonic-to-Bulgarian/Macedonian continuum
  (languages tagged `bul,mkd`). The majority are **independent witnesses of
  one work** — Euthymius of Tarnovo's *Life of St. Petka* (berlinski,
  ljubljanski, tixonravovski, vukovic, nedelnik1806, nbkm728, nbkm1064... —
  ~10 witnesses of the same vita across four centuries).
- **Format:** 3.8 MB, five bitstreams — one corpus-wide **CoNLL-U** file +
  per-document **TSV source** + plain text + philological/technical PDFs.
- **Annotation layers (sampled, all verified):** manual (gold) **lemma**;
  custom MULTEXT-East **MSD** (`msd-bg-dam` spec, designed to carry both
  archaic ChSl and innovative Balkan features); **UD dependency relations**
  (Level-2 validated) — effectively the historical South Slavic treebank UD
  doesn't have; **`# text_en` on all 6,036 sentences** (100% English
  coverage, counted); the TSV layer adds per token: accented transliteration
  | **Cyrillic** | **diplomatic** (three orthographic layers) | folio anchor
  | aligned English | cross-text `ref`; per-document headers carry
  manuscript, place, **date range** ("Etropol?, 1650-1670s") and folio span.
- **nabu surfaces:** gold lemmas → `passage_lemmas` (bul/mkd historical
  lemma languages); MSD → morph facets; text_en → the ORACC `-en` sibling /
  `--parallel` pattern; the ~10 St.-Petka witnesses → the alignment
  hub/collation layer's best Slavic case since ccmh; dates → axis;
  accented/Cyrillic/diplomatic → collation layers (ccmh-txt precedent);
  Balkan-sprachbund MSD features are a genuinely new diachronic-syntax
  facet if wanted later.
- **Effort:** cheap — CoNLL-U rides `ConlluParser` (existing family) +
  single-zip `Nabu::ZipFetch` (the goo300k recipe verbatim). The richer TSV
  layer would need a small bespoke TSV family — defensible as phase 2 of
  the same source.
- **Dedup:** zero overlap with anything held (TOROT/PROIEL/CCMH are the
  OCS canon; this is its 15th–19th-c. Balkan descendant line).
- **Cross-reference (LOUD):** survey II axis (b) concluded Bulgarian ChSl =
  "web-search UI only... BLOCKED" (Sofia histdict) and DIACU unlicensed.
  This corpus is the first openly licensed, machine-readable slice of that
  axis — smaller than histdict, but gold and PUB.

### 2. The Slovenian historical dictionary shelf — Pleteršnik + Svetokriški + besedje16 (+ Franček crosswalk)

**STATUS (P23-2, 2026-07-15): INGESTED** — the three dictionaries shipped
as ONE source `sl-lexica` (parser family `zrc-xml`, dictionary slugs
`pletersnik`/`jsv`/`besedje16`, `enabled: false` awaiting the owner-fired
first sync). Licenses re-verified verbatim at fetch time (all three:
"Creative Commons - Attribution 4.0 International (CC BY 4.0)", PUB);
counts confirmed 103,185 / **8,461** (the delta below, reported honestly)
/ 27,759; the toneme-folding question settled WITHOUT a new conventions
§9 rule (fold from the unaccented `<ge>`; generic mark strip handles the
tonemes). The **Franček crosswalk rider was NOT ingested** — outside the
packet's three-artifact scope, still open below. Details:
docs/backlog.md P23-2, docs/02-sources.md #57–59.

Three ZRC SAZU dictionaries, all real deposits with files, all verbatim
"Creative Commons - Attribution 4.0 International (CC BY 4.0)", **PUB** →
`attribution`, MCP-safe. Together they give the sl axis what LSJ:grc /
L&S:lat / B-T:ang have — and they key onto goo300k's gold lemmas, which are
already *modernized* Slovenian:

- **Pleteršnik, Slovenian–German Dictionary 1894–95**
  (<http://hdl.handle.net/11356/1114>, 4.8 MB zip → `Pletersnik.xml` +
  XSD). **103,185 entries** (counted `<rc geslo-id>` = the description's
  number exactly). Layers: headword; accented form with **Slovenian
  tonemes** (`abecę̑da` — a folding/vocab question conventions §9 would
  gain); POS; **German glosses**; per-sense **source-authority
  abbreviations** (Cig., Jan., Levst. — an attestation apparatus);
  **dialect/region tags** (vzhŠt., BlKr., Rez. — a geo facet). Covers
  19th-c. standard AND 16th-c.-onward lexis (built on Miklošič/Caf/Levstik
  materials). This is the natural `define` target for every goo300k gold
  lemma — the gold-lemma→dictionary loop closed for sl.
- **Dictionary of the Language of Janez Svetokriški (JSV)**
  (<http://hdl.handle.net/11356/1092>, 1.8 MB → `JSV.xml` + XSD). 8,540
  entries per the description (8,461 `geslo-id`s counted in the XML —
  report the delta honestly at fixture time). Baroque Slovenian from the
  233 sermons of *Sacrum promptuarium* (1691–1707). Layers: 17th-c.
  headword; grammar; modern gloss; **verbatim attestation quotes with
  volume/page citations** (`(I/1, 207)`) — resolvable against the IMP
  library if it holds Sacrum promptuarium (citation-resolution pattern,
  honest miss rate, the §1.3 discipline); **etymology notes on loanwords**
  (`← it. a … < lat. ad`) — a dictionary-native language-contact layer
  feeding the P15-3 `borrowed` direction.
- **Words of the 16th-Century Slovenian Literary Language (besedje16)**
  (<http://hdl.handle.net/11356/1127>, 0.4 MB → `besedje16.xml` + XSD).
  **27,759 entries** (counted). A complete word inventory of 1550–1603
  Slovenian print with POS and **per-word attestation sigla of the
  editions** (TA 1550, TT 1557, DB 1584...). DB 1584 = Dalmatin's Biblia —
  the very document goo300k/IMP hold as `zrc_00001-1584`: the sigla are a
  mechanical crosswalk from dictionary entries to held documents, plus
  earliest-attestation data (a word-level axis).
- **Franček portal historical module** (<http://hdl.handle.net/11356/1472>,
  0.4 MB, CC BY 4.0 PUB) — the crosswalk rider: entry-ID links joining
  Pleteršnik ↔ JSV ↔ 16th-c. Protestant first-attestations
  (author/title/year). Ingest with the shelf, not alone.

**Effort:** none of the three is TEI — a small bespoke XML dictionary
family (Bosworth-CSV-tier; entry-per-element with `geslo-id`, XSDs
shipped). One family plausibly covers all three (shared ZRC SAZU
conventions), `content_kind :dictionary`.

### 3. PriLit — older Slovenian narrative prose (scope-call rider)

- **Handle:** <http://hdl.handle.net/11356/1319>. License verbatim
  "Creative Commons - Attribution 4.0 International (CC BY 4.0)", PUB.
- **Content:** 43 texts (37 works, 12 authors), **1643–1866** excluding
  reprints — extends the sl axis a century and a half before goo300k's
  narrative material and includes the earliest Slovenian narrative prose;
  *Sreča v nesreči* (Cigler 1836) is present in **7 editions** — a ready
  collation/alt-edition case.
- **Format:** 57.7 MB — TEI + TEI.ana (automatic modernization +
  lemmatization + UD — silver, so text-only ingest per the IMP owner
  default) + txt + vert. Parser fit vs the imp-tei family to be verified
  at Phase B (same Erjavec/JSI orbit, schema not confirmed identical).
- **Dedup:** possible sigil overlap with IMP's 658 texts — check per
  document at fixture time; alt-editions never dedupe (conventions §3).
- **Verdict:** clean and cheap if the owner wants the sl axis deepened
  further; behind #1/#2 on novelty.

---

## Blocked — the ELEXIS collection (metadata-only, verified)

**141 items titled "(ELEXIS)"** sit in the repository; they look like a
dictionary goldmine and are not one. REST bitstream checks on 18 of them —
including every on-axis prize — returned **zero files** each:

| Handle | Dictionary | Why it would matter |
|---|---|---|
| 11356/1553 | **Monier-Williams Sanskrit (1899), TEI Lex-0** | P17-4's target — but the record names the real source: the **Cologne C-SALT Lex-0 edition** (CDSL). P17-4 should scout Cologne directly; nothing to fetch here. |
| 11356/1666 | **Miklosich, Lexicon Palaeoslovenico-Graeco-Latinum** | Re-checked this pass: still `"bitstreams":[]`, unchanged since survey II. The BCDH permission thread (standing, owner-gated) remains the unblock; not re-scouted. |
| 11356/1667 | Daničić, Dictionary of Serbian Literary Antiquity | Would be the Serbian ChSl-adjacent lexicon survey II found nothing for. |
| 11356/1665 | Karadžić, Srpski rječnik (1818/1852) | Foundational Serbian; srp/deu/lat. |
| 11356/1583 | Old Norse Prose (ONP) | Germanic-medieval cross-axis. |
| 11356/1644, 1645 | Middle High German (BMZ; Lexer) | Same. |
| 11356/1647–1649 | Old/Early-Middle/Middle Dutch (ONW/VMNW/MNW) | Same. |
| 11356/1654 | Welsh GPC | Celtic cross-axis. |
| 11356/1638 | Grimm DWB (1st ed.) | Germanic. |
| 11356/1660 | Russian 18th-c. dictionary | East Slavic. |
| 11356/1534 | Historical Finnish (VKS) | — |
| 11356/1531 | Latin VALLEX | Valency for the IT-treebank orbit. |
| 11356/1616–1618, 1544 | ELEXIS mirrors of besedje16/Trubar/JSV/Pleteršnik | The native deposits (above) carry the actual files — ingest those, never these. |

Also checked, empty: 1543. **Unblock path:** these records exist because
ELEXIS catalogued partner dictionaries; the data sits with each publisher
(or behind the ELEXIS/BCDH pipeline that never completed the deposits —
Miklosich's exact situation). One email to repo-help@clarin.si (Erjavec is
the repository manager) asking whether the ELEXIS bitstreams will ever land
would settle 141 records at once; per-dictionary publisher contact is the
fallback. Owner's call; no contact made (packet rules).

## Access-class sweep (honest)

The full-repo ACA/RES sweep returned ~30 items — **none on-axis** (MULTEXT-
East, KAS academic Slovene, WaC parallel web corpora, FRENK, spoken audio).
There is no blocked-with-unblock-path treasure behind CLARIN.SI auth for
our axes; the on-axis blockage is the ELEXIS zero-file pattern, not access
class.

---

## v2 / deferred (real files, weaker fit)

- **sPeriodika 1.0** (11356/1881, CC BY-SA 4.0 PUB) — Slovenian periodicals
  **1771–1914**, TEI, lemma+POS+NER, but **20.1 GB**, OCR-derived with
  automatic correction (silver on silver), 19th-c.-heavy. The scope
  precedent (goo300k ruling) covers the period, but size/quality make this
  a deliberate owner decision, not a rider.
- **Trubar, Gospel of Matthew 1555 concordance** (11356/1124, CC BY 4.0
  PUB, 1.2 MB). 23,603 KWIC records with folio refs (`B 4b`) — would be the
  **earliest Slovenian print we could hold (1555 < goo300k's 1584)**, but
  it is a concordance (overlapping context windows), not a running-text
  edition; reconstruction is derived-work territory. Deferred unless the
  owner wants it as a word-attestation layer beside besedje16.
- **Documents on Magdalena Gornik** (11356/1993) + **Holzapfel sermons**
  (11356/1995) — both CC BY-SA 4.0 PUB, TEI **diplomatic manuscript
  transcriptions** (285 + 220 pp., mid-19th c., Gornik with facsimiles,
  Holzapfel with lat/deu passages tagged). Genuinely manuscript-diplomatic
  but late and small; a future sl-manuscripts nicety.
- **SI-IUS legal texts** (11356/2026, CC BY 4.0) — "historical" = 1906/1928
  statute books; 977 MB. Out of charter period; skip.
- **KDSP** (11356/1823, CC BY, 1836–1918) / **CVET** (11356/1226, CC BY,
  1887–1916) / **Kranjska assembly** (11356/1824, CC BY, 1861–1913, 10 M
  words OCR) — all past the charter's comfort zone; named for completeness.
- **MEMIS** (11356/1376, CC BY-SA 4.0, 51 Latin inscriptions 1222–17th c.)
  — standing survey-II flag; belongs with the P17-2 epigraphy decision
  (genre facet, EpiDoc-adjacent TEI), not the Slavic axis.
- **DiCCAS** (11356/2097, **CC BY-NC-SA 4.0** PUB → `nc`) — the cross-axis
  surprise: classical **Arabic** disaster accounts (Qur'an, Bukhārī/Muslim
  ḥadīth, al-Ṭabarī, Ibn Taghrībirdī, al-Jāḥiẓ) in one 22 MB TEI with RNG
  schema. Machine-readable and real; nabu has no Arabic axis today — named
  in case the owner ever opens one.
- **imp25k** (11356/1032, CC BY 4.0, 26.7 MB TEI) — unchanged survey-II
  verdict: normalization lexicon for the goo300k/IMP pipeline, not
  dictionary-shelf material.
- **Slovene Grammars and Orthographic Dictionaries** (11356/1122, CC BY) —
  139 bibliographic *descriptions* of grammars 1584–2015, not text. Out.
- **Arcticae horulae German-borrowings dictionary** (11356/1379, CC BY) —
  honesty flag: the deposit's own description says it is an **art project**
  whose "artistic modes misdirected the public to treat the booklet as a
  reference dictionary." Not a scholarly source; excluded on that basis
  despite the tempting borrowing topic.
- **HyperVerb / WeSoSlav** (11356/1683, 1846, 1855; CC BY-SA/CC BY) —
  Western South Slavic verb morphology database, but built from Gigafida/
  WaC frequency lists — modern-synchronic, out by the packet's ruling.

## Per-axis honest gaps (nothing there)

- **OCS / Church Slavonic proper:** nothing. No OCS corpus, no Glagolitic
  edition, no ChSl recension text with files. Damaskini's early witnesses
  are the closest the repository comes.
- **Old East Slavic / historical Russian:** nothing (the one hit, the
  18th-c. Russian dictionary, is an empty ELEXIS stub).
- **Croatian/Serbian ChSl:** nothing with files (Daničić and Karadžić are
  stubs) — survey II's institutional-contact verdicts stand unchanged.
- **Historical treebanks:** no UD-style historical treebank *except*
  Damaskini itself (gold UD deps), which is why it is pick #1.
- **PIE/comparativistics, dictionaries of ancient languages:** nothing
  ingestable — the entire apparent supply was the ELEXIS mirage.
- **Old Slovene:** nothing on clarin.si; Freising remains an nl.ijs.si
  (eZISS) source, already held under the ND posture.

## Unknowns

- Whether the Damaskini TSV `ref` column's cross-text references are
  machine-complete enough to mint collation links, and how doc-level
  language (bul vs mkd) is assigned — Phase B reads the philological PDF.
- Whether IMP holds Sacrum promptuarium / the PriLit sigils (JSV citation
  resolution; PriLit dedup) — check against the synced IMP tree at fixture
  time, not from here (db untouched this pass).
- JSV entry-count delta (8,540 described vs 8,461 counted `geslo-id`s).
- Why v1.0 of Damaskini was GPL-3 and 1.1 is CC BY-SA — no action needed
  (1.1's grant governs), noted for the record.

## Fixture-plan sketches (owner approval, top picks)

1. **damaskini** (new source, `damaskini`): fetch = one 3.8 MB zip via
   `Nabu::ZipFetch` (bitstream URL, the goo300k recipe). Fixtures: trim
   `damaskini.conllu` to 3 newdocs — `berlinski--slovo-petki` (early
   Bulgarian ChSl), `nedelnik1806--skazanie-paraskevy` (print era),
   `veles--trojanskata` (Macedonian) — ~first 15 sentences each, plus the
   matching TSV file for one of them (layer evidence, even if TSV ingestion
   is phase 2). urn sketch `urn:nabu:damaskini:<doc-id>:<sent-n>`; language
   per doc from the corpus metadata; `license_class: attribution`
   (CC BY-SA 4.0, verbatim at fixture time from the deposit page); gold
   lemmas → `passage_lemmas`; `-en` sibling docs from `text_en` (ORACC
   precedent) — one passage per sentence, mechanically aligned.
2. **sl dictionary shelf** (one packet, new small XML dictionary family):
   fixtures = first ~25 entries of `Pletersnik.xml`, `JSV.xml`,
   `besedje16.xml` + their XSDs + a 20-line slice of `FR-zgodovina.xml`.
   `content_kind :dictionary`; urns `urn:nabu:dict:pletersnik:<geslo-id>`
   etc.; JSV citations parsed to `(vol, page)` pairs (resolution against
   IMP deferred, honest misses); Pleteršnik toneme folding recorded in
   conventions §9; Franček links land as entry crosswalk rows.
3. **prilit** (if scoped in): TEI zip fixture of 2 docs — one 17th-c. text
   + two editions of Cigler 1836 (the collation pair); text-only (silver
   ana not ingested), imp-tei family fit verified first.
