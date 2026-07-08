# Slavic sources survey (P9-6, 2026-07-08)

Scouting survey for the owner's stated Slavic research axis (Old Church Slavonic
`chu` / Old East Slavic `orv` / Church Slavonic), which the corpus today serves
**only** through the two PROIEL-family treebanks already live — `torot` (40 docs
incl. Codex Zographensis, Kiev Missal, Psalterium Sinaiticum, Codex
Suprasliensis, the OES canon) and `proiel` (Codex Marianus Gospels). This
document assesses what *else* is digitized, licensed, and machine-readable, with
cited evidence and an honest license read, and ends with a ranked recommendation
of **at most two** candidates for Phase 10.

No bulk fetching was done — page-level `WebFetch`/`WebSearch` and `gh` metadata
only, per the packet.

**Bottom line up front.** The Slavic axis has one genuinely cheap, clean win
sitting in machinery we already own (UD CoNLL-U treebanks the `ud` adapter does
not yet list), and one clean canonical-OCS breadth win in an openly-downloadable
Helsinki corpus (CCMH). The famous prizes (TITUS, the full RNC historical
corpora) are **not bulk-ingestable** — custom scholarly-use-only terms and
query-only web UIs respectively — and are recorded as `SURVEYED-BLOCKED` with the
path that would unblock them.

---

## Recommended for Phase 10 (ranked, ≤2)

### 1. UD Slavic treebank expansion — Birchbark + RNC Middle Russian (`ud` adapter, zero new family)

The single cheapest and cleanest additive win on the whole axis. Universal
Dependencies ships **three** Slavic treebanks; two of them are data the corpus
does **not** have and can ingest with **no new parser family and no new fetch
path** — they are CoNLL-U in a UD GitHub repo, exactly the shape
`lib/nabu/adapters/universal_dependencies.rb` already clones. The adapter's
`TREEBANKS` map currently lists only `gothic-proiel`, `greek-proiel`,
`sanskrit-vedic`, `latin-ittb` (verified in-tree); adding two keys + fixtures is
the entire code change, and the adapter already skips on-disk treebanks it has no
entry for (forward-compatible by design).

- **`UD_Old_East_Slavic-Birchbark`** — the RNC Corpus of Birchbark Letters,
  East-Slavic **vernacular** written 1025–1500 (letters 61.7%, household/business
  records 21.6%, official documents, church-service records, charms), ~27k
  tokens, manually UD-annotated. Genuinely new register: everyday vernacular OES,
  not the ecclesiastical canon TOROT/PROIEL carry.
  License (README, quoted verbatim): **`CC BY-SA 4.0`** → `license_class:
  attribution`.
  Source repo: <https://github.com/UniversalDependencies/UD_Old_East_Slavic-Birchbark>
  (digital originals at <http://gramoty.ru>).
- **`UD_Old_East_Slavic-RNC`** — a sample of the RNC **Middle Russian** corpus
  (1300–1700): legal documents, correspondence, historical narrative, folklore
  charms. License (README, verbatim): **`CC BY-SA 4.0`** → `attribution`.
  Repo: <https://github.com/UniversalDependencies/UD_Old_East_Slavic-RNC>.

**Why this is #1.** (a) Effort ≈ a config change: reuse `ConlluParser` + the UD
adapter's existing multi-repo fetch/probe/dedup plumbing; URN scheme is the
frozen `urn:nabu:ud:<treebank>:<sent_id>`. (b) License is **`attribution`, not
`nc`** — so unlike GRETIL (`nc`) or the obdurodon edition below, this data is
**MCP-surface-safe** and republishable-with-credit, materially improving the
*shareable* Slavic coverage, not just local. (c) It carries gold
lemma+morphology, so the P7-5 lemma index lights up for OES vernacular for free.
(d) It is disjoint from current holdings: birchbark letters and Middle Russian
chancery/folklore are absent from TOROT/PROIEL.

**Overlap discipline (important).** UD *also* ships `UD_Old_Church_Slavonic-PROIEL`
and `UD_Old_East_Slavic-TOROT`, but those are **conversions of the very
PROIEL/TOROT data already synced** — ingesting them would double-load the OCS
canon. Recommendation: add **only** Birchbark + RNC to `TREEBANKS`; deliberately
*exclude* the chu-PROIEL and orv-TOROT UD conversions (note this in the registry
comment so a future maintainer does not "complete the set" and duplicate).

### 2. Corpus Cyrillo-Methodianum Helsingiense (CCMH) — canonical-OCS breadth, openly downloadable

The cleanest *canonical-OCS text* candidate: seven of the core OCS manuscripts as
**transliterations + structured XML**, openly downloadable from the Language Bank
of Finland (Kielipankki / CLARIN), collected at Helsinki 1986–2017.

- **Contents (7 texts):** Codex Assemanianus, Codex Marianus, Codex
  Suprasliensis, Codex Zographensis, Savvina kniga (Liber Sabbae) — the five
  canonical OCS witnesses — plus Vita Constantini and Vita Methodii (later
  copies). Source page: <https://www.kielipankki.fi/corpora/ccmh/>; catalogue
  record <https://datakatalogi.helsinki.fi/items/342b3dd2-d1d7-4ee6-ad93-9f25cf31b3bf>.
- **Format:** per-text transliteration + a *simple* structured XML (the corpus's
  own light schema — **not** TEI/EpiDoc, no `refsDecl`/CTS, no CoNLL-U). The
  catalogue itself warns "the encoding and annotation of the texts is mostly very
  simple, and not all texts have been properly checked." A new **small bespoke
  parser family** is needed (nearer a First1K-sized job than DdbdpParser —
  flat line/verse XML, no Leiden markup).
- **License / access:** the Finnish data catalog marks the resource **`Open`**;
  Kielipankki's own page states "Some versions of this resource are available
  publicly (PUB), whereas others might require you to log in as an academic user
  (ACA) or to apply for individual access rights (RES)." The `-src` bundle is
  the PUB, browsable/downloadable one
  (<https://www.kielipankki.fi/download/ccmh-src/www/>). **Action at ingestion:**
  read the exact CC string from the bundle's LICENSE/META-SHARE record and map it
  (`open` if CC-BY/PD-declared, `attribution` if CC-BY, worst case `nc`); do not
  hardcode — same discipline the ORACC scout adopted.
- **Citation / URN:** keys on manuscript + the text's own scheme (Gospel
  chapter:verse for Marianus/Zographensis/Assemanianus; folio for Suprasliensis).
  Sketch `urn:nabu:ccmh:<manuscript>:<ref>`.

**Why #2 and not #1.** Real value is **Codex Assemanianus + Savvina kniga**,
which are absent from TOROT/PROIEL — plus *alternative editions* of Marianus,
Zographensis and Suprasliensis (two editions of a work are two versions, never a
dedupe — conventions §3). But three of its seven texts overlap the canon we
already hold, it needs a new parser family, and the "simple, not fully checked"
encoding warns of fixture archaeology. Still: openly licensed, bulk-downloadable,
plain enough to parse, and it closes the two canonical gaps — a solid second pick.

---

## Assessed but not top-two (ingestable, lower priority)

### Codex Suprasliensis — the obdurodon critical edition (`nc`, crawl friction, overlap)

The richest *single* OCS manuscript edition in existence online: the largest
extant OCS manuscript (Preslav school, saints' lives + homilies), as a full
diplomatic transcription with photographic facsimile, **parallel Greek**, English
translation, glossary, and grammatical analysis, by Anisava Miltenova & David J.
Birnbaum. Home: <https://suprasliensis.obdurodon.org/> (mirror
<http://csup.ilit.bas.bg/>).

- **Format / access:** XML-backed (the editorial-principles page publishes the
  RelaxNG schema — `element line { attribute text, attribute folio, attribute
  side {"r"|"v"}, attribute line, mixed {…} }`), and individual texts expose a
  "Raw XML" view. But there is **no located bulk download or git repo for the
  transcription source** — `gh` search surfaces only Birnbaum's `repertorium`
  (Old Bulgarian *archaeography/metadata*, not running text) and `normalization`
  (OCS tooling), plus third-party `StabiBerlin/Stanza-NLP-Supr` (a case study).
  Ingestion would mean a **per-text HTTP crawl of the site's XML** — new friction
  (ORACC-like, but against a website, not a clean zip endpoint).
- **License (verbatim):** "Creative Commons **BY-NC-SA 3.0** Unported License"
  (David J. Birnbaum) → `license_class: nc` — ingestable for local research,
  **default-excluded from the MCP surface** (P8-1), never redistributed.
- **Citation:** text-number · folio · side · line (e.g. `1 008r 18`) →
  `urn:nabu:suprasliensis:<text>:<folio><side>.<line>`.
- **Overlap:** TOROT already carries a Suprasliensis; obdurodon's is far fuller
  (whole codex + apparatus + Greek), so it is an *alternative, richer edition*,
  not a dedupe — but that fuller value competes with a heavier crawl and an `nc`
  license. **Verdict: worthy future packet, behind the two above.**

---

## Not ingestable (license- or format-blocked) — one line each, with the unblock path

- **TITUS (Frankfurt)** — the prize and the pain. Custom terms (quoted): "Those
  texts that can be downloaded via http can be used freely for scholarly purposes,
  provided that they are quoted as sources … The texts must not be used for any
  kind of commercial usage," and "Downloading of some texts is restricted to
  members of the TITUS project" (<https://titus.uni-frankfurt.de/texte/texte2.htm>).
  No redistribution grant, no standard license, legacy HTML + custom encodings,
  directory index 403s bots. → **`SURVEYED-BLOCKED`, maps to `research_private`
  at best.** *Unblock:* per-text scholarly-use caching for the owner's private
  research only (segregated `research_private`), and/or written permission — but
  the encoding archaeology makes ROI low while CCMH/obdurodon cover the OCS canon
  more cleanly.
- **Russian National Corpus — full historical corpora** (Old Russian, Middle
  Russian, Birchbark, `ruscorpora.ru/en/corpus/old_rus`) — query-only web UI;
  stated policy "the copyright to texts in the Russian National Corpus resides
  with respective publishers/authors, and the texts cannot be distributed." →
  **`SURVEYED-BLOCKED`.** *Unblock:* already partially unblocked — the RNC's own
  **UD releases** (Birchbark, Middle-Russian RNC, both `CC BY-SA 4.0`) are the
  ingestable slice, and they are recommendation #1. The bulk corpus itself would
  need written permission (`research_private`).
- **"Манускриптъ" / Manuscript (manuscripts.ru, Udmurt State University)** — 130+
  transcribed Slavonic/Russian manuscripts, 10th–15th c., >3.5M word occurrences
  (Gospels, menaia, chronicles), with fragment-level annotation. But it is a
  full-text *retrieval system* — no located bulk export or license grant. →
  **`SURVEYED-BLOCKED`.** *Unblock:* write to the Izhevsk team for a data grant
  (a legitimate `research_private` path after owner contact); high potential value
  (vernacular + liturgical OES at scale) if it lands.
- **Sreznevsky, *Materialy dlya slovarya drevnerusskogo yazyka*** — the great Old
  Russian historical dictionary with citable attestations from ~2700 sources, but
  digitally it exists only as **page scans** (HathiTrust, Presidential Library);
  no machine-readable TEI with structured citations was located. → **not
  ingestable as machine-readable text.** *Unblock:* a future HTR/OCR pass on the
  PD scans (the docs/03 "unlock by reconstruction" strategy) — out of scope here.
- **SEENET / eSlavistik** — no distinct, locatable open machine-readable Slavic
  *corpus* is published under these names (the searchable OCS corpora are the ones
  already assessed: CCMH, TITUS, obdurodon, UD/TOROT). → nothing new to ingest.
- **obdurodon *Repertorium* of Old Bulgarian literature** (noted for
  completeness) — SGML/XML **archaeographic/codicological metadata** (manuscript
  catalogue data), not running transcribed text; out of scope for a text corpus,
  but a future *catalog crosswalk* the way Trismegistos is for papyri.

---

## What should shape Phase 10 planning

- **Headline stays ORACC** (P9-5b). Both Slavic picks slot *behind* it cheaply:
  #1 (UD expansion) is a `TREEBANKS`-map + fixture change to an already-live
  adapter — the smallest possible packet, and it needs no owner fixture-approval
  ceremony beyond confirming the two repos (both `CC BY-SA 4.0`). #2 (CCMH) is a
  small new bespoke family + a normal fixture-approval plan.
- **Both top picks are `attribution` (CC BY-SA 4.0) / `Open`** — MCP-surface-safe,
  unlike the `nc` obdurodon/GRETIL material. The Slavic axis currently reaching the
  conversational surface is only the `nc`-adjacent PROIEL family plus TOROT (`nc`);
  adding openly-shareable OES vernacular + canonical OCS improves *both* local and
  MCP coverage.
- **Overlap-dedup is a live hazard here** more than anywhere else in the corpus:
  the OCS canon (Marianus, Zographensis, Suprasliensis, Kiev Missal, Psalterium
  Sinaiticum) recurs across TOROT, UD-chu-PROIEL, CCMH, and obdurodon. The rule
  (conventions §3) is that distinct *editions* are distinct version-URNs and must
  never be deduped — but *the same edition re-converted* (UD-chu-PROIEL vs native
  PROIEL) **must** be excluded, not loaded twice. Every Slavic packet must state
  its overlap posture explicitly, as #1 does above.
- **Recommended Phase 10 Slavic scope:** ship #1 (UD Birchbark + RNC Middle
  Russian) as a low-risk companion to the ORACC headline; queue #2 (CCMH) as the
  follow-on scout→plan→adapter track; hold the obdurodon Suprasliensis edition
  (`nc`, crawl) and the write-for-permission sources (Manuscript, RNC-bulk, TITUS)
  as a documented backlog of `research_private` opportunities.
</content>
</invoke>
