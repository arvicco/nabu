# Source Inventory & Ranking

Sources that need (or may eventually need) dedicated adapters. Scores are 1–5, higher is better. **Ease** = ease of integration (format cleanliness, bulk access, stability). **License** = openness/clarity (5 = CC/PD with bulk grant, 1 = restricted/unclear). Verify licenses and endpoints at implementation time — this table reflects the landscape as of mid-2026 and these projects do change terms and infrastructure.

## Tier 1 — build first (large, open, clean formats)

| # | Source | Content | Format | Size | Value | Ease | License | Notes |
|---|--------|---------|--------|:----:|:-----:|:----:|:-------:|-------|
| 1 | **PerseusDL canonical-greekLit / canonical-latinLit** | Core classical Greek & Latin literature | TEI XML (EpiDoc/CapiTainS), CTS URNs, git | 5 | 5 | 5 | 5 (CC BY-SA) | The backbone. Clean, versioned, citation scheme built in. Adapter here defines the reference implementation. **Status: LIVE (greekLit)** — first sync 2026-07-03: 744 docs / 238,525 passages, 25 quarantined (upstream `@n` gaps); latinLit pending a sibling subclass. |
| 2 | **OpenGreekAndLatin / First1KGreek** | Greek works not in Perseus (first 1,000 years CE) | TEI XML, CTS, git | 4 | 5 | 5 | 5 (CC BY-SA) | Same conventions as Perseus — nearly free once adapter #1 exists. **Status: LIVE** — first sync 2026-07-04: 1,054 docs / 226k passages, 37 quarantined. |
| 3 | **PROIEL treebanks** | Gothic (Wulfila), OCS Codex Marianus, Greek NT, Classical Armenian, Latin — fully lemmatized/parsed | PROIEL XML, git | 3 | 5 | 4 | 5 (CC BY-NC-SA) | Highest linguistic value per byte for comparative IE work. NC clause: record it. **Status: LIVE** — first sync 2026-07-04: 12 docs (release 20180408, frozen), 0 quarantined. |
| 4 | **Universal Dependencies (ancient treebanks)** | Ancient Greek, Latin, OCS, Old East Slavic, Vedic Sanskrit, Gothic, Coptic, Classical Chinese | CoNLL-U, git | 4 | 5 | 5 | 4–5 (mostly CC) | One parser handles a dozen languages. Overlaps PROIEL (TOROT/PROIEL data appear here too) — dedupe by document ID. **Status: LIVE** — first sync 2026-07-04: 4 treebanks / 12 docs, 0 quarantined. |
| 5 | **TOROT (Tromsø OCS & Old Russian Treebank)** | OCS + Old East Slavic, lemmatized | PROIEL XML / CoNLL-U | 3 | 5 | 4 | 5 | Directly serves the Slavic research axis. Shares PROIEL adapter. **Status: LIVE** — first sync 2026-07-04: 40 docs incl. Zographensis, 0 quarantined. |
| 6 | **GRETIL** | Vast Sanskrit (+ Pali, Prakrit) e-texts | TEI XML (recent), legacy HTML | 5 | 4 | 3 | 4 (mostly free for research) | Heterogeneous quality; TEI subset first, legacy files later. |
| 7 | **Digital Corpus of Sanskrit (DCS)** | Lemmatized Sanskrit corpus | Custom text format, git (dcs-data) | 4 | 5 | 4 | 5 (CC BY) | Every token analyzed. Complements GRETIL (analysis vs breadth). |
| 8 | **ORACC** | Assyriology projects: royal inscriptions (RINAP), SAA, ETCSRI… | JSON/ATF bulk downloads per project | 4 | 4 | 4 | 5 (CC BY-SA) | JSON is well-documented. One adapter, many sub-projects. |
| 9 | **CDLI** | Cuneiform catalog + transliterations (~350k artifacts) | ATF + catalog dumps, git/API | 5 | 3 | 3 | 5 (CC) | Huge but many entries are catalog-only. Ingest transliterated subset. |
| 10 | **Papyri.info (DDbDP/HGV/APIS)** | Documentary papyri | EpiDoc TEI, full git dump (idp.data) | 4 | 4 | 4 | 5 (CC BY) | Everyday Greek/Latin — legal texts, letters. Own DDbDP parser (no CTS layer upstream). **Status: LIVE** — P5-1 restart-minting fix + owner sign-off 2026-07-04: 61,347 docs / 920,766 passages; 9,354 remaining quarantines audited honest (text-less cross-reference stubs; ~40 recoverable `<del>`-wrapped docs → Phase 6 candidate). |
| 11 | **Sefaria (sefaria-export)** | Hebrew Bible, Talmud, rabbinics + translations | JSON, git | 5 | 4 | 4 | 4 (varies per text, mostly PD/CC) | Massive, well-structured, per-text licensing metadata included. |
| 12 | **Wulfila Project** | Gothic corpus with Streitberg apparatus | HTML/XML | 2 | 4 | 3 | 4 (research use) | Small; PROIEL covers the text, Wulfila adds edition detail. Low priority if #3 done. |

## Tier 2 — high value, moderate friction

| # | Source | Content | Format | Size | Value | Ease | License | Notes |
|---|--------|---------|--------|:----:|:-----:|:----:|:-------:|-------|
| 13 | **TITUS (Frankfurt)** | Widest IE coverage: Avestan, Old Persian, Tocharian, Hittite, Old Prussian, Vedic, OCS… | Legacy HTML, framesets, custom encodings | 4 | 5 | 1 | 2 (restrictive, access requests for some texts) | The prize and the pain. Scrape politely with per-text caching, or pursue access (see unlockables doc). Encoding archaeology required. |
| 14 | **ETCSL (Oxford)** | Sumerian literary corpus, composite texts + translations | Legacy TEI/HTML | 2 | 4 | 3 | 4 (free for scholarship) | Frozen project — scrape once, never re-sync. |
| 15 | **Thesaurus Linguae Aegyptiae (AES corpus)** | Ancient Egyptian, lemmatized | JSON/text dumps | 4 | 4 | 3 | 5 (CC BY-SA) | Earlier Egyptian corpus downloadable; hieroglyphic encoding (MdC/Unicode) needs care. |
| 16 | **Kanseki Repository (kanripo)** | Classical Chinese canon | Plain text + metadata, git (one repo per text) | 5 | 3 | 4 | 5 (open) | Thousands of small git repos; batch-clone adapter. Value depends on whether Chinese enters scope. |
| 17 | **Perseus Ancient Greek/Latin dependency treebanks (AGDT/LDT)** | Treebanked Homer, tragedy, etc. | XML/CoNLL-U | 2 | 4 | 4 | 5 | Partially inside UD already; native format has richer annotation. |
| 18 | **Monumenta Frisingensia (Brižinski spomeniki, ZRC SAZU)** | Oldest Slovenian (and oldest Latin-script Slavic) texts, diplomatic + critical transcriptions | TEI-based web edition (eZISS) | 1 | 5 | 3 | 3 (scholarly use; confirm) | Tiny corpus, outsized personal relevance. eZISS sibling editions come along for near-free. |
| 19 | **Corpus Cyrillo-Methodianum Helsingiense** | OCS canonical texts (Zographensis, Suprasliensis…) | Plaintext, transliterated | 2 | 4 | 3 | 3 (research use) | Complements PROIEL/TOROT coverage of the OCS canon. |
| 20 | **e-codices / e-manuscripta (Switzerland)** | Manuscript facsimiles incl. classical & medieval | IIIF images + metadata | 4 | 3 | 3 | 4–5 (per-MS CC) | Not text — images. Feeds the ad-hoc/HTR pipeline as a *bulk image adapter*. Swiss infrastructure, excellent IIIF. |
| 21 | **Menota** | Medieval Nordic manuscripts, multi-level transcription | TEI (Menota schema) | 3 | 3 | 3 | 3–4 (per-text) | If Old Norse enters scope; schema is well documented. |
| 22 | **Avestan Digital Archive** | Avestan manuscripts | Images + some transcriptions | 2 | 4 | 2 | 3 | Mostly facsimiles → HTR pipeline candidate. |

## Tier 3 — restricted, awkward, or specialized (adapter only if research demands)

| # | Source | Content | Blocker |
|---|--------|---------|---------|
| 23 | **PHI Latin Texts / Greek Inscriptions** | Canonical Latin corpus + epigraphy | No bulk download; terms prohibit systematic copying. Browse-only companion; see unlockables. |
| 24 | **TLG** | Most complete Greek corpus in existence | Subscription, no export. The single biggest gap in any open pipeline. See unlockables. |
| 25 | **Trismegistos** | Metadata/identifiers for papyri & inscriptions | Metadata-only, access tiers. Valuable as an ID crosswalk, not as text. |
| 26 | **ctext.org** | Classical Chinese | API with tight quotas, restrictive terms. Kanripo (#16) is the open substitute. |
| 27 | **CAL (Comprehensive Aramaic Lexicon)** | Aramaic corpus + lexicon | Web-only, restrictive. Request-based (see unlockables). |
| 28 | **Beta maṣāḥǝft** | Ethiopic (Gǝʿǝz) manuscripts | TEI on GitHub actually — promote to Tier 2 if Ethiopic enters scope. |
| 29 | **Internet Archive / HathiTrust PD scans** | The infinite long tail: every out-of-copyright edition | Not a text corpus — a scan firehose. Served by the ad-hoc pipeline plus a thin "fetch by identifier" adapter (IA has clean APIs; HathiTrust PD downloads need an account/API key). |

## Ranking synthesis

**By effort-to-value (build order):** 1 → 2 → 4 → 3/5 → 10 → 7 → 8 → 11 → 6 → 9 → 15 → 14 → 18/19 → 13.

Rationale: adapters 1–2 share one EpiDoc/CTS implementation and immediately deliver the classical backbone; 3–5 share the PROIEL/CoNLL-U implementation and deliver the annotated IE layer; 10 reuses EpiDoc. That's three parser families covering ten sources. TITUS (#13) is deliberately late despite top-tier content: it's the highest-friction integration and should be attempted only once the normalization layer is mature enough to absorb its encoding chaos.

**By content criticality for the Slavic/IE research axis:** 3, 5, 19, 18, 13, 4 — these are the corpora whose absence would actually block work.

**By licensing cleanliness (safe to ever share/publish derivatives):** 1, 2, 7, 8, 9, 10, 15, 16 (CC with attribution) > 3, 5 (NC clause) > 6, 14, 19 (research-use, keep private) > 13, 23–27 (private use only, segregate).

**Format families → shared parser components:**
- *EpiDoc/CTS TEI:* Perseus, First1KGreek, Papyri.info
- *PROIEL XML:* PROIEL, TOROT
- *CoNLL-U:* UD, DCS(convertible), AGDT
- *ATF/JSON:* ORACC, CDLI
- *Bespoke:* GRETIL, TITUS, Sefaria JSON, ETCSL, TLA, kanripo, CCMH
- *IIIF image feeds (→ HTR):* e-codices, ADA, DigiVatLib (see unlockables)
