# Etruscan axis survey (P17-5 Phase A, 2026-07-13)

Scouting survey for the owner's Etruscan axis (voiced 2026-07-13, adjacent to
the in-flight Proto-Italic shelf work). Etruscan (`ett`, ISO 639-3; script
Old Italic `Ital`, U+10300–1032F) is a small, epigraphy-only, non-IE corpus —
no proto-shelf ascent exists or ever will. The survey's job was to find what
is MACHINE-READABLE, read the licenses precisely, and rank honestly.

**Evidence base (all numbers from actually-inspected files, named
throughout):** `openetruscan_clean.csv` (770.6 kB, 6,567 rows, read in full);
`kaikki.org-dictionary-Etruscan.jsonl` (637 kB, 493 records, read in full);
the Larth repo tree + `Data/README.md` + `Data/Etruscan.csv` (7,139 rows,
read in full); the Burman concordance CSV (1.06 MB, 14,986 rows, read in
full); two en.wiktionary category-member API responses; `gh api` metadata for
three repos; live probes of kaikki.org, etp.classics.umass.edu (connection
refused), trismegistos.org (403s fetchers), zenodo records 20075836 / 7801485
/ 6475427. All samples in scratch `etruscan/`; census scripts retained there
for the Phase B recipe.

**Bottom line up front.** The axis is REAL but THIN, and almost everything
editorial upstream is dead, print-only, or unlicensed. There is exactly one
licensed machine-readable Etruscan text corpus: **OpenEtruscan**
(Zenodo, **CC BY 4.0**, 2026) — 6,567 inscriptions (6,094 clean) including
the Pyrgi tablets, seven Liber Linteus columns, the Tabula Capuana and the
Cippus Perusinus, with 1,800 English translations — carrying one honest
provenance caveat the owner must weigh (§1.7). Beside it: the **kaikki `ett`
extract** (attribution; 420 substantive glossary entries — served, unlike
Proto-Semitic) and a **public-domain 14,986-row id concordance**
(TM/CIE/ET1/ET2/TLE) from Uppsala. The contact-layer census is the headline:
Wiktionary marks **191 Latin lemmas as derived from Etruscan (66 strictly
borrowed)**, and **58 of them (20 of the strict set) join the live gold Latin
lemma set** — persona, histrio, populus, triumphus, fenestra all among them —
the P17-3 `borrowed` flag's first attested-into-gold feed from a non-IE
donor. The famous names (ETP, CIE, Rix/Meiser ET, Trismegistos) are all
blocked, each with a named unblock path.

---

## 1. Corpus inventory — every digital collection found, with license verdicts

### 1.1 ETP — Etruscan Texts Project (UMass) · DEAD

The packet's first-named lead is gone. `etp.classics.umass.edu` refuses
connections (probed 2026-07-13, `ECONNREFUSED`); the Digital Classicist wiki
records the site "last seen online 2009-12-28". It was a searchable database
of 300+ post-1990 inscriptions (an online continuation of Rix's ET), planned
EpiDoc, never bulk-downloadable, license never stated. **The data is not
lost:** the Larth repo (§1.6) carries ETP-derived files verbatim
(`ETPWords.txt`, `ETPNames.txt`, `ETPSuff.txt`, `ETP_POS.csv`,
`ETP_fix.csv`), and 380 `ETP n` ids survive in Larth's merged CSV (324 in
OpenEtruscan). → **SURVEYED-BLOCKED** (dead upstream, no grant ever).
*Unblock:* contact Rex Wallace (UMass Amherst, emeritus — the ETP PI) for the
database and a grant; the Larth/OpenEtruscan chain is the de-facto archive
meanwhile.

### 1.2 Rix, Etruskische Texte editio minor (1991) / Meiser ET² (2014) · PRINT

The corpus of record and the id spine every digital derivative keys on
(`Cr 2.20`, `Pe 8.4`, `LL n` sigla). No official digital release located —
ET² is a two-volume Baar-Verlag print edition (€150). Its content reaches
machine-readable form only through derivatives: the "CIEP" PDF compilation
that Larth text-extracted (PyMuPDF — `Data/CIEP_pymupdf.csv`), and
Trismegistos' metadata cooperation (§1.4). → **not ingestable as such**;
in-copyright edition, `research_private` at best via derivative PDFs.
*Unblock:* none realistic at the edition layer; the ancient TEXTS are PD and
arrive via §1.7.

### 1.3 CIE — Corpus Inscriptionum Etruscarum · SCANS ONLY

The 1885– print corpus. Digitally: the Uppsala University Library archival
collection (squeezes, notebooks, photographs) is being imaged into the Alvin
portal (2021–) — **images, not text**. The only machine-readable CIE text
found is OpenEtruscan's OCR of CIE Vol. I (1,855 records, §1.7), quality
honestly flagged per row. → **not machine-readable upstream**. *Unblock:* the
docs/03 HTR-on-PD-scans strategy (CIE Vol. I is 1893, PD) — which is exactly
what OpenEtruscan already did, OCR warts and all.

### 1.4 Trismegistos · METADATA ONLY, FETCH-BLOCKED

TM claims near-complete Etruscan coverage "on the basis of a cooperation with
Gerhard Meiser's new edition (2014) of Rix, Etruskische Texte" (TM coverage
page, via search snippet — the site 403s non-browser fetchers, so the exact
Etruscan count could not be read; probes 2026-07-13). Per-text pages exist
(TM 69133 = Liber Linteus). TM data services state **CC BY-SA 4.0**, but the
offered dumps are Geo/Per tables — **no transcription data exists in TM at
all, and no bulk text-metadata dump is public**. → **SURVEYED-BLOCKED** for
bulk; the PD concordance (§1.8) carries 11,723 TM ids into the open, which is
most of what TM would give us anyway. *Unblock:* TM partner agreement
(written request, KU Leuven) — low ROI while §1.8 exists.

### 1.5 EDR / EAGLE · OUT OF SCOPE UPSTREAM

EDR collects "Latin and Greek inscriptions from ancient Italy" — Etruscan is
explicitly outside its scope (edr-edr.it project statement). EAGLE aggregates
Greek/Latin epigraphy; no Etruscan channel found. → negative results,
recorded so nobody re-scouts them.

### 1.6 Larth — Larth-Etruscan-NLP (GitHub, ALP 2023) · NO LICENSE

The dataset paper of the axis (Vico & Spanakis, "Larth: Dataset and Machine
Translation for Etruscan"). `Data/Etruscan.csv` read in full: **7,139
inscriptions, 2,891 with English translation, 358 dated, 456 with findspot
city**, merging the ETP database with PyMuPDF-extracted CIE/"CIEP" text; ids
mix ET sigla (`Cr 2.20`), `ETP n`, `LL n` (17 Liber Linteus rows) and bare
CIE numbers. Also carries the ETP glossary files (§2.2). Repo has **no
license** (`gh api` license: null; checked 2026-07-13, last push 2025-11) →
per the Miklosich precedent, unstated = **SURVEYED-BLOCKED**, contact for
permission. *Unblock:* email the authors (Maastricht) — worth doing anyway
since OpenEtruscan builds on it; but §1.7 supersedes it for ingestion.

### 1.7 OpenEtruscan (Zenodo 10.5281/zenodo.20075836) · **CC BY 4.0 — THE PICK**

An active open-source Etruscan epigraphy platform (code MIT, last push
2026-07-07; site openetruscan.com). The data deposit (v1.0.0, 2026-05-07,
license field **"Creative Commons Attribution 4.0 International"**) is one
file, `openetruscan_clean.csv` (770.6 kB), read in full:

- **6,567 inscriptions**: ~4,712 Larth-derived + 1,855 newly-OCR'd CIE
  Vol. I. Quality flagged per row: `clean` 6,094 (92.8%) / `needs_review`
  154 / `ocr_failed` 319 (e.g. CIE 2616's raw `IAN8VJV1…` mirror-OCR
  garbage — skip-by-rule material, never quarantine).
- **10 columns**: id · raw_text · canonical_transliterated ·
  canonical_italic (regenerated Old Italic glyphs, 5,509 rows) ·
  canonical_words_only (4,622) · translation (**1,800**) · year_from/to
  (**307**) · intact_token_ratio · data_quality.
- **The showpieces are in it** (verified row-level): Pyrgi plates A and B
  (`CODEX_PY_A_1/B_1` — "ita tmia icac heramaśva … θefariei velianas");
  seven Liber Linteus columns (`LL 2/4/5/6/11…`, with translations); Tabula
  Capuana (`TCa 8`); Cippus Perusinus (`Pe 8.4`, 375 chars).

**The provenance caveat (owner must weigh at the gate).** The CC BY 4.0
grant is the depositor's own claim over a dataset that is ~71% Larth-derived
— and Larth itself carries no license and aggregates ETP + a PDF corpus of
the in-copyright ET edition. The ancient texts are PD and the *editorial*
layer in a bare transliteration is thin (sigla + readings, no apparatus), so
the CC BY claim is defensible — but it is a relabel, not a chain of grants.
Honest posture options: (a) take the Zenodo grant at face →
`license_class: attribution`; (b) ingest under `attribution` with the caveat
recorded in the manifest and a `license_watch` on the Zenodo record; (c)
demand the Larth permission email first. Recommendation: **(b)** — the
grant is explicit and machine-readable at the deposit, the caveat is
journaled, and the Larth email (§1.6) is queued as a permission point
regardless.

### 1.8 Burman concordance (Zenodo 7801485) · **PUBLIC DOMAIN**

"A Digital Concordance of Etruscan, Faliscan and Early Latin Inscriptions
from Etruria" (Annie Burman, Uppsala, 2023; license **Public Domain**). One
CSV (1.06 MB), read in full: **14,986 rows** crosswalking **Trismegistos
11,723 · CIE 11,311 · Rix ET1 9,291 · Meiser ET2 10,628 · TLE 1,128** plus
Bakkum's Faliscan corpus and four CIL/CII columns. No text — pure id spine.
This is the professional-crosswalk layer (the role tm_nr plays for EDH),
free and clean. → ingestable any time; v2 links-journal feedstock (§6).

### 1.9 CEIPoM (Zenodo 6475427) · CC BY-SA 4.0, BUT NO ETRUSCAN

Pitts' Corpus of the Epigraphy of the Italian Peninsula: Sabellic, Venetic,
Messapic + epigraphic Latin to 100 BCE, token-level linguistic annotation,
CC BY-SA 4.0. **Etruscan is excluded by design** (IE languages only).
Recorded because it is the natural future shelf for the OTHER side of the
Italic contact story (itc-pro's Sabellic-loan fixtures — bōs); out of this
packet's scope.

## 2. Lexica / glossaries

### 2.1 kaikki `ett` extract · attribution — SERVED, above the threshold

kaikki.org serves Etruscan: **485 distinct words / 622 senses** — just above
the ~520-sense serving floor that 404s Proto-Semitic (recon2 survey §1).
Full-file census of the 637 kB JSONL (493 records):

- **420 substantive entries** (419 headwords in Old Italic script, 1 Latin
  script) + **73 romanization stubs** (`vetus` → "romanization of 𐌅𐌄𐌕𐌖𐌔" —
  a free Old-Italic↔Latin crosswalk table, §5).
- POS: 224 name / 130 noun / 22 verb / 17 num / 13 adj / 6 pron / 5 suffix.
  Onomastics-heavy, as the language is.
- Glosses on all 420; `forms` on 414; `etymology_text` on 179 (93 mention
  Latin, 24 Greek); `sounds` on 237.
- License: kaikki's standard dual CC-BY-SA + GFDL → `attribution`.

A crowd glossary, not Bonfante/Wallace — but it is the ONLY licensed
machine-readable Etruscan lexicon found, and it is the same
wiktionary-jsonl family the dictionary shelf already parses. 𐌀𐌅𐌉𐌋 avil
"year", 𐌀𐌕𐌉 ati "mother", 𐌋𐌀𐌖𐌙𐌖𐌌𐌄 lauχume — which the corpus pick attests
as `lauχumeśa` in ETP 43, and whose Latin descendant `lucumo` is
borrow-flagged (§3).

### 2.2 Everything else · print or unlicensed

The Bonfante & Bonfante and Wallace (*Zikh Rasna*) glossaries exist digitally
only as archive.org page scans — no structured data, no grant. The Thesaurus
Linguae Etruscae is print. ETP's own glossary files (`ETP_POS.csv`: vocabulary
with grammatical categories, POS and translations) survive in the Larth repo
and ride its no-license block (§1.6). → the kaikki extract is the lexicon.

## 3. The contact layer — Latin loans FROM Etruscan (the P17-3 feed)

**ett-side (thin, measured):** the kaikki extract carries `descendants` on
only **10 records / 18 nodes**. The Latin nodes: Aulus, Rasennae, fala,
lanista, Carthāgō, Carthada, terra (uncertain), Tellūs (uncertain), olīva,
lucumo — **6 flagged `borrowed` in raw_tags** (+2 borrowed-uncertain),
exactly the marker mechanics the P17-3 `borrowed` design consumes. One
proto-to-proto-style analogy edge (*𐌘𐌄𐌓𐌔𐌖𐌍𐌀 "reshaped by analogy") confirms
the P17-3 do-NOT-match caveat applies here too.

**Latin-side (the real density, censused via the en.wiktionary category API,
2026-07-13):** `Latin terms borrowed from Etruscan` = **66 lemmas**;
`Latin terms derived from Etruscan` = **191 lemmas** (ns=0; superset
including suspected/partial derivations — precision caveat: members like
`de`, `te`, `o` are speculative; the 66-strong borrowed set is the
high-precision core).

**Gold join (measured 2026-07-13, BEFORE the mid-survey db-freeze order —
re-verify at review).** Methodology, stated in full since the measurement
cannot be re-run right now: read-only Sequel connection to `db/catalog.sqlite3`;
distinct gold Latin lemma keys = every `tokens[].lemma` in `passages` rows
with `language='lat'` (i.e. the proiel latin-nt and UD latin-ittb treebanks:
19,425 + 26,977 passages), folded through the repo's own
`Nabu::Normalize.search_form(lemma, language: "lat")` (generic fold + v/j →
u/i) — **11,416 distinct folded gold keys**; category lemmas folded
identically and intersected. NB the tree's catalog was mid-rebuild when read
(dictionary tables empty, fulltext.sqlite3 0 B), so these are treebank-gold
numbers only; the join list is in scratch (`lat-gold-folded.txt`, `bor.txt`,
`der.txt`).

- borrowed (66): **20 join gold** — amurca, as, atrium, Aulus, cuneus,
  fenestra, lanista, littera, massa, miles, Minerva, oliva, pulcher,
  pulpitum, Roma, Sergius, titulus, tunica, Vulcanus, Vulturnus.
- derived (191): **58 join gold** — adding persona, histrio, populus,
  triumphus, autumnus, ferrum, forma, idus, lituus, Mercurius, mundus,
  nuntius, Saturnus, tardus, Aprilis, Carthago, Hercules …

This is the P17-3 borrowed-flag story from the OTHER direction: loans INTO a
language we hold gold lemmas for, from a non-IE donor with no shelf. **Design
note for the gate:** these edges do NOT arrive via the ett kaikki extract
(10 nodes) — they live in the LATIN entries' etymologies. Minting them at
scale means either (a) the kaikki Latin extract (large; a future
dictionary-shelf packet of its own) or (b) a small curated edge list seeded
from the category census (66 rows, links-journal `kind: borrowing`, source
Wiktionary, attribution). Recommendation: record (b) as the cheap v2 rider on
the P17-3 packet; do not build it here.

## 4. Bilinguals & special monuments — status

- **Pyrgi tablets** (ET Cr 4.4/4.5): Etruscan plates A and B live in the
  pick as `CODEX_PY_A_1` / `CODEX_PY_B_1` (clean, full transliteration).
  The **Phoenician side (KAI 277) is in NO surveyed machine-readable source**
  — Wikipedia carries a CC BY-SA transliteration (reference at fixture time,
  not an ingest). So v1 gets the Etruscan text; the Etruscan–Phoenician
  alignment showpiece needs a Phoenician witness that doesn't exist
  digitally-licensed yet. Honest.
- **Liber Linteus** (the longest Etruscan text, ~1,200 words): partial —
  7 column-records in OpenEtruscan (`LL 2/4/5/6/11…`, translations present),
  17 rows in Larth. Not the full 12 columns anywhere machine-readable.
- **Tabula Capuana**: one record (`TCa 8`). **Cippus Perusinus**: one record
  (`Pe 8.4`, 375 chars). Both in the pick.
- No structured/EpiDoc edition of any of the four exists anywhere surveyed —
  the "alignment-adjacent showpieces" reduce to well-formed rows in the CSV.

## 5. Metadata depth & the search fold (deep-extraction census)

What the pick actually carries, layer by layer, mapped to surfaces:

- **Dating** → `document_axes`: 307/6,567 rows (4.7%) have year_from/to
  (Larth: 358). Values are positive floats meaning BCE ("650.0"→"625.0" =
  650–625 BCE) — the adapter must sign-flip to conventions-§11 signed years;
  pin at fixture time (ETP 43: 550–500 BCE). A small feed, taken because the
  extractor is the HGV/EDH pattern at trivial size.
- **Findspot** → thin: OpenEtruscan dropped Larth's City column; Larth has
  456 city-tagged rows. If wanted, a CSV side-join from the (blocked) Larth
  file is NOT available under the pick's license alone → place axis feed
  deferred; recorded, not lost (TM/ETP hold real findspots behind their
  blocks).
- **Genre/material/object facets** (the P17-2 `document_facets` proposal):
  **no feed** — the pick carries no typology columns. The facet the corpus
  DOES earn: `data_quality` (clean/needs_review) as a per-document
  annotation, and source-family (CIE-OCR vs Larth-derived) if the owner
  wants it. Do not invent epitaph/votive labels the source doesn't state.
- **Quality/damage** → `intact_token_ratio` per row + Leiden-ish brackets in
  the text (`[ ]`×~530, `( )`×~1,850, `{ }`×~110, `< >`×57 — supplied /
  expansions / editorial, censused over all 6,567 rows) — keep verbatim in
  `text` v1 (no parse of the bracket language; this is a flat CSV, not
  EpiDoc), annotation carries the ratio. `--fuzzy` is the real damage
  surface here.
- **Script & fold** (measured char census, all rows of
  `canonical_transliterated`): θ×2,236 · χ×476 · φ×19 · ś×224 · σ×223 ·
  ς×16 · š×16; interpuncts ·×706 / •×513 / :×2,331; residual raw Old Italic
  glyphs (𐌀×59…) and Greek capitals (Θ×438, Λ×137) = OCR residue in CIE
  rows. Fold design: `text` = canonical_transliterated (how Etruscan is
  cited and searched); `canonical_italic` rides as an annotation, never a
  second document (mechanically derivable lettering — the EDH `btext`
  argument verbatim). New `LANGUAGE_FOLDS["ett"]`: σ/ς→s (the OCR/editorial
  sigma variants join ś/š, which the generic Mn-strip already folds to s);
  θ/χ/φ KEEP (they are letters of the standard transliteration alphabet, no
  collision). The kaikki extract's 73 romanization stubs supply the
  Old-Italic↔Latin mapping for the define-join, free.
- **Translations** (1,800 EN) → annotation v1 (one-passage documents; a
  sibling `-en` document per ORACC precedent is over-machinery at this
  grain); revisit if a parallel surface is wanted.
- **URN**: `urn:nabu:etruscan:<id-slug>` — ids are the community sigla
  (`cie-2615`, `etp-43`, `ll-2`, `pe-8.4`, `codex-py-a-1`), stable within
  the versioned Zenodo deposit; `sync_policy: frozen` against the versioned
  DOI (Zenodo files are immutable per version; a new version = owner-fired
  re-sync). One passage per inscription v1 (mean text ~30 chars; the few
  long texts carry `|`/`\n` line marks — line grain deferred, recorded).
- **Fuzzy**: ~6.1k clean texts × ~30 chars ≈ 200k chars × 6.55 B/char ≈
  **1.3 MB** trigram — the cheapest `fuzzy_index: true` line the config
  will ever see, and the right surface for bracket-riddled epitaphs.

## 6. Ranked verdict & fixture plan (what the owner approves)

**The honest thin-axis statement first:** this axis is ~6k mostly-few-word
funerary/votive one-liners, no gold lemmas, no morphology, 4.7% dated, no
genre typology, in a language with no proto-shelf and no full decipherment.
What it buys, concretely: (1) the language axis existing at all — searchable,
fuzzy-indexed Etruscan beside Latin on the Italic shelf, with the four
showpiece monuments present; (2) an onomastics/vocabulary layer (420-entry
glossary + 73-entry script crosswalk) lighting `define`; (3) the
Latin-contact layer — 66/191 loan lemmas, 20/58 already gold-attested — as
the borrowed-flag's non-IE test case. That is worth one small adapter; it is
not worth more than one.

**v1 picks (ranked):**

1. **OpenEtruscan corpus CSV** — `attribution` (CC BY 4.0 at the Zenodo
   deposit, provenance caveat §1.7 recorded in the manifest +
   `license_watch` on the record). One FileFetch of one 770 kB CSV; new
   small CSV passage-parser family (the first flat-CSV corpus family —
   goo300k-sized job, no XML); skip-by-rule `ocr_failed` (319);
   `needs_review` ingested with the quality annotation; `fuzzy_index: true`;
   date-axis extractor with the BCE sign-flip; `ett` fold entry.
2. **kaikki `ett` glossary** — `attribution`; one more EXTRACTS row in the
   existing wiktionary-jsonl dictionary adapter (first ATTESTED-language row
   — verify the shelf schema takes a non-proto dictionary language;
   romanization stubs skip-by-rule, 420 entries load).
3. **Burman concordance** — public domain, v2: canonical retention now if
   trivially cheap, links-journal identification edges (TM/CIE/ET ids per
   inscription) when a links surface wants them.

**Fixture plan (one trimmed CSV, header + 5 real rows, byte-verbatim; +2-3
JSONL records for the glossary):**

- `CODEX_PY_A_1` — Pyrgi plate A: the showpiece; translit + regenerated Old
  Italic; clean.
- `LL 2` — Liber Linteus column: translation present, interpuncts (`•`),
  σ-variants for the fold, `|` line mark.
- `ETP 43` — dated (550–500 BCE, pins the sign-flip) + translated + attests
  `lauχumeśa` (joins kaikki 𐌋𐌀𐌖𐌙𐌖𐌌𐌄 → Latin `lucumo`, borrow-flagged — the
  cross-source golden thread in one fixture).
- `CIE 2615` + `CIE 2616` — the OCR pair: 2615 clean with Old Italic
  raw_text (and a visible 𐌅→𐌚 correction between raw and canonical_italic);
  2616 `ocr_failed` garbage pinning the skip rule.
- kaikki records: 𐌋𐌀𐌖𐌙𐌖𐌌𐌄 (descendants + borrowed flag), 𐌀𐌅𐌉𐌋 (plain
  gloss), one romanization stub (skip rule).

**Blocked (each with its unblock path):** Larth — no license; email the
authors (also strengthens §1.7's chain). ETP — dead host; contact Rex
Wallace. Trismegistos — no bulk; partner agreement if ever needed. CIE —
images only; HTR path already exercised by OpenEtruscan. Rix/Meiser ET² —
in-copyright print; no path at the edition layer. Bonfante/Wallace
glossaries — scans only.

**Honest unknowns:** the OpenEtruscan CC BY 4.0 provenance chain (§1.7 — the
gate question); exact TM Etruscan text count (site blocks fetchers); whether
the full ETP database (~380 ids visible in derivatives vs "300+ texts"
claimed) survives beyond the Larth snapshot; the year_from sign convention
(BCE-positive inferred from Pyrgi-era values, pinned at fixture time); the
der-category's speculative tail (`de`, `te`, `o`); and the gold-join numbers
carry the §3 re-verify-at-review caveat (measured mid-rebuild, pre-freeze,
treebank-gold only).
