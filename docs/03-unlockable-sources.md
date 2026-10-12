# Potentially Unlockable Sources

Sources not readily ingestible today, with concrete unlock paths. Ordered by expected payoff × plausibility. *Status refreshed 2026-10-11: several entries below have since been unlocked — each section says so where it applies, and [02-sources.md](02-sources.md) is the authoritative status table.* General rule for all of these: the *ancient text itself* is public domain; restrictions attach to modern editorial work, databases, and access terms. Unlock strategies must respect the terms actually in force — the goal is legitimate access, and several of these are genuinely achievable with an email or a modest fee.

## 1. TLG (Thesaurus Linguae Graecae) — the big one

**What's locked:** the most complete corpus of Greek literature (Homer to 1453), lemmatized, ~110M+ words. No export, subscription web interface only.

**Unlock paths:**
- **Individual subscription** (~$100–130/yr historically). Grants full search/reading access — legitimate for research use, but still no bulk export; it fills the gap interactively rather than filling the database.
- **Open replacement trajectory:** First1KGreek + Perseus + Patrologia Graeca digitization efforts are deliberately rebuilding TLG's coverage under open licenses. Adapter strategy: track OGL's coverage lists and re-sync — the gap shrinks yearly.
- **Underlying editions:** for any specific author TLG has and open corpora lack, the underlying pre-1930 print edition is PD → Internet Archive scan → your HTR pipeline. This is the "unlock by reconstruction" route and is entirely clean legally: same text, your own transcription.

**Verdict:** subscribe for reading access if needed; systematically reconstruct priority authors via HTR. Do not attempt to extract from the platform.

## 2. TITUS full access — largely unlocked

**What was locked:** parts of TITUS require registration/permission per agreement with original editors; the public HTML is scrapeable but encoding-hostile.

**Unlocked, in three grants from Prof. Jost Gippert (TITUS, Frankfurt), all by email:**

- **2026-07-23 — Avestan** (`titus-avestan`): non-commercial use, TITUS and the editors credited wherever the text is displayed. The letter described the specific texts and the private comparative-IE use; writing it was the entire cost — exactly as this page predicted.
- **2026-08-31 — Oscan-Umbrian** (`titus-osco-umbrian`), extending the Avestan terms: one-time download, local non-commercial use, no redistribution.
- **2026-10-06 — Tocharian and the Middle Iranian families** (the terms cover the Tocharian A and B texts of the Berlin Turfan collection; `titus-tocharian-a` holds the Tocharian A corpus today; `titus-pahlavi`, `titus-sogdian`, `titus-khotanese`, `titus-bactrian`, `titus-manichaica`): one retrieval per corpus, local personal research use only, no redistribution, TITUS and the editors credited wherever displayed.

All eight sources are wired. The grants are personal, so every one is grant-gated: each box records its own acknowledgment of the terms before its first fetch, and none of the texts ships in any public artifact.

**Remaining long tail:** Tocharian B (already covered by the 2026-10-06 terms; the members-only adapter `titus-tocharian-b` is built and awaits the TITUS member credential and its first authenticated sync) and other TITUS corpora as concrete needs arise — the same scoped-letter route, now with three precedents to cite. Hittite is served independently (the tlhdig and hittite-glossed shelves), and the hieroglyphic Luwian corpus arrived by a separate personal grant (ACLT, I. Yakubovich, 2026-09-28).

## 3. IIIF manuscript universe (Vatican, BnF, British Library, Bodleian, Munich…)

**What's "locked":** millions of digitized manuscript pages sit behind viewer UIs — but nearly all major libraries expose **IIIF manifests**, which are machine-readable JSON listing every page image at full resolution.

**Unlock path:** this is the highest-leverage unlock in the whole project and it requires *no permission for access*, only attention to per-institution image licenses (Vatican: personal study use; BnF Gallica: PD images free for non-commercial; e-codices: mostly CC). Build one **IIIF adapter** (manifest → ordered page images → local cache) and every participating library becomes an input to the HTR pipeline. Glagolitic and Cyrillic manuscripts (Vatican's Assemanianus!), Greek codices, Slovenian material in Austrian libraries — all reachable through the same three hundred lines of Ruby.

**Verdict (ruled 2026-09-01):** PARKED until local HTR inference hardware exists — page images only become searchable text through HTR, so the adapter built today would deliver a browsable image cache, real but modest, while the per-institution image-license reads are the actual work. The HTR-hardware decision reopens this as a ready packet.

## 4. HathiTrust public-domain bulk

**What's locked:** full-view PD books download page-by-page without an account; bulk access requires membership or the dataset request process.

**Unlock path:** page-level OCR text of full-view items is accessible via API with a free account. (The dataset-request path through HathiTrust's research center predates the HTRC wind-down and is no longer current — recheck due 2026-11.) For 19th-century critical editions (Miklosich, Jagić, Leskien, the entire early Slavistics canon), this plus IA covers essentially everything. IA needs no unlock at all — clean APIs, bulk download tools.

## 5. Brepols (Library of Latin Texts), Loeb, TLL

**What's locked:** commercial databases of Latin texts and reference works.

**Unlock paths:** no legitimate bulk path for individuals. Substitutes: Corpus Corporum (Zurich — actually *open*, huge Latin aggregation including Patrologia Latina; **ingested since 2026-08-19** as `corpus-corporum`, and in the embedded literary core), plus PD editions via HTR. Loeb's facing translations are copyrighted; originals are PD elsewhere. Treat these as reading subscriptions, not corpus sources.

## 6. CAL (Comprehensive Aramaic Lexicon)

**Unlock path:** the project has historically shared data with researchers on request (Hebrew Union College). A specific, scoped request (e.g., Targumic corpus for comparative purposes, private use) has reasonable odds. Web interface remains the fallback.

## 7. PHI Latin / Greek inscriptions

**What's locked:** terms prohibit systematic downloading; no bulk offer.

**Unlock paths:** for Latin literature, Corpus Corporum + Perseus + DigilibLT (open, late-antique Latin — both ingested since summer 2026) substantially overlap PHI's canon. For epigraphy, the **EDH (Epigraphic Database Heidelberg)** offers open data dumps (CC — ingested; upstream no longer actively maintained per PI correspondence 2026-08-11, dumps remain) and **EDCS** has relaunched at UZH with a search API + CSV export but no license grant (last checked 2026-08: interactive use only; recheck due 2026-11) — EDH plus EDR/I.Sicily/IIP effectively unlock the inscription space PHI covers. PHI itself: use interactively, don't ingest.

## 8. Slovenian/South Slavic archival material

**What's locked:** much South Slavic manuscript heritage is digitized but scattered: NUK (dLib.si — largely open PD downloads, add a thin adapter), Matica srpska, HAZU, monastery collections (Hilandar's HMML digitizations — registration grants reading-room access online).

**Unlock paths:** dLib.si is genuinely open (adapter-worthy). HMML (Hill Museum & Manuscript Library) grants free registered access to tens of thousands of digitized Slavic and Near Eastern manuscripts — registration is the entire unlock. Manuscriptorium aggregates Czech and Slavic manuscripts with IIIF-ish access for registered users. All three are realistic wins for the OCS/Slavic axis. One caveat: registration-based unlocks (HMML, Manuscriptorium, HathiTrust) unlock *manual-drop* ingestion, not adapters — account-gated downloads fail the automation bar, so what they feed is `incoming/<slug>/` and the ingest shelf, never an unattended sync.

## 9. Institutional affiliation as a master key

A standing option worth naming: many "locked" resources (TLG, Brepols, ProQuest early books) unlock with any university library card. Universities in Ticino/Lombardy (USI, Milan) or alumni associations often extend electronic-resource access to external/associated readers for a small annual fee. One library card ≈ five subscriptions. Worth one afternoon of investigation before paying for anything individually.

## Priority actions

1. **The IIIF adapter** (unlocks #3 and feeds #8) — parked until HTR hardware exists (see §3's verdict); pure engineering once reopened.
2. **Register:** HathiTrust, HMML, Manuscriptorium — free, immediate.
3. **Email TITUS** — done: Avestan (2026-07-23), Oscan-Umbrian (2026-08-31), Tocharian and the Middle Iranian families (2026-10-06) are all in (§2).
4. **Promote the open "unlockables"** — done: DigilibLT, EDH, and Corpus Corporum are all registered and ingested.
5. **Decide on TLG individual subscription** only when a concrete research need hits the gap.
