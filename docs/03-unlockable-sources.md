# Potentially Unlockable Sources

Sources not readily ingestible today, with concrete unlock paths. Ordered by expected payoff × plausibility. General rule for all of these: the *ancient text itself* is public domain; restrictions attach to modern editorial work, databases, and access terms. Unlock strategies must respect the terms actually in force — the goal is legitimate access, and several of these are genuinely achievable with an email or a modest fee.

## 1. TLG (Thesaurus Linguae Graecae) — the big one

**What's locked:** the most complete corpus of Greek literature (Homer to 1453), lemmatized, ~110M+ words. No export, subscription web interface only.

**Unlock paths:**
- **Individual subscription** (~$100–130/yr historically). Grants full search/reading access — legitimate for research use, but still no bulk export; it fills the gap interactively rather than filling the database.
- **Open replacement trajectory:** First1KGreek + Perseus + Patrologia Graeca digitization efforts are deliberately rebuilding TLG's coverage under open licenses. Adapter strategy: track OGL's coverage lists and re-sync — the gap shrinks yearly.
- **Underlying editions:** for any specific author TLG has and open corpora lack, the underlying pre-1930 print edition is PD → Internet Archive scan → your HTR pipeline. This is the "unlock by reconstruction" route and is entirely clean legally: same text, your own transcription.

**Verdict:** subscribe for reading access if needed; systematically reconstruct priority authors via HTR. Do not attempt to extract from the platform.

## 2. TITUS full access

**What's locked:** parts of TITUS require registration/permission per agreement with original editors; the public HTML is scrapeable but encoding-hostile.

**Unlock path:** email the maintainers (Frankfurt, Gippert's successors) describing non-commercial comparative-IE research and requesting the underlying text files for specific corpora (Avestan, Tocharian, Hittite). Academic courtesy access has historically been granted to serious individuals. A personal research letter mentioning specific texts and intended private use is the entire cost. Worst case, the public HTML remains available for careful per-text scraping.

## 3. IIIF manuscript universe (Vatican, BnF, British Library, Bodleian, Munich…)

**What's "locked":** millions of digitized manuscript pages sit behind viewer UIs — but nearly all major libraries expose **IIIF manifests**, which are machine-readable JSON listing every page image at full resolution.

**Unlock path:** this is the highest-leverage unlock in the whole project and it requires *no permission for access*, only attention to per-institution image licenses (Vatican: personal study use; BnF Gallica: PD images free for non-commercial; e-codices: mostly CC). Build one **IIIF adapter** (manifest → ordered page images → local cache) and every participating library becomes an input to the HTR pipeline. Glagolitic and Cyrillic manuscripts (Vatican's Assemanianus!), Greek codices, Slovenian material in Austrian libraries — all reachable through the same three hundred lines of Ruby.

**Verdict:** build the IIIF adapter early; it converts the ad-hoc pipeline from "things I photograph" to "the world's digitized manuscripts."

## 4. HathiTrust public-domain bulk

**What's locked:** full-view PD books download page-by-page without an account; bulk access requires membership or the dataset request process.

**Unlock path:** individual researchers can request **datasets of public-domain volumes** through HathiTrust's research center, and page-level OCR text of full-view items is accessible via API with a free account. For 19th-century critical editions (Miklosich, Jagić, Leskien, the entire early Slavistics canon), this plus IA covers essentially everything. IA needs no unlock at all — clean APIs, bulk download tools.

## 5. Brepols (Library of Latin Texts), Loeb, TLL

**What's locked:** commercial databases of Latin texts and reference works.

**Unlock paths:** no legitimate bulk path for individuals. Substitutes: Corpus Corporum (Zurich — actually *open*, huge Latin aggregation including Patrologia Latina; promote to the main source list and verify current dump availability), plus PD editions via HTR. Loeb's facing translations are copyrighted; originals are PD elsewhere. Treat these as reading subscriptions, not corpus sources.

## 6. CAL (Comprehensive Aramaic Lexicon)

**Unlock path:** the project has historically shared data with researchers on request (Hebrew Union College). A specific, scoped request (e.g., Targumic corpus for comparative purposes, private use) has reasonable odds. Web interface remains the fallback.

## 7. PHI Latin / Greek inscriptions

**What's locked:** terms prohibit systematic downloading; no bulk offer.

**Unlock paths:** for Latin literature, Corpus Corporum + Perseus + DigilibLT (open, late-antique Latin — add to main list) substantially overlap PHI's canon. For epigraphy, the **EDH (Epigraphic Database Heidelberg)** offers open data dumps (CC) and **EDCS** is request-based — both effectively unlock the inscription space PHI covers. PHI itself: use interactively, don't ingest.

## 8. Slovenian/South Slavic archival material

**What's locked:** much South Slavic manuscript heritage is digitized but scattered: NUK (dLib.si — largely open PD downloads, add a thin adapter), Matica srpska, HAZU, monastery collections (Hilandar's HMML digitizations — registration grants reading-room access online).

**Unlock paths:** dLib.si is genuinely open (adapter-worthy). HMML (Hill Museum & Manuscript Library) grants free registered access to tens of thousands of digitized Slavic and Near Eastern manuscripts — registration is the entire unlock. Manuscriptorium aggregates Czech and Slavic manuscripts with IIIF-ish access for registered users. All three are realistic wins for the OCS/Slavic axis.

## 9. Institutional affiliation as a master key

A standing option worth naming: many "locked" resources (TLG, Brepols, ProQuest early books) unlock with any university library card. Universities in Ticino/Lombardy (USI, Milan) or alumni associations often extend electronic-resource access to external/associated readers for a small annual fee. One library card ≈ five subscriptions. Worth one afternoon of investigation before paying for anything individually.

## Priority actions

1. **Build the IIIF adapter** (unlocks #3 and feeds #8) — pure engineering, no permission needed.
2. **Register:** HathiTrust, HMML, Manuscriptorium — free, immediate.
3. **Email TITUS** with a scoped request — one letter, potentially the whole IE long tail.
4. **Verify Corpus Corporum, DigilibLT, EDH dump availability** and promote them into the main source list (they were "unlockables" that turned out to be open).
5. **Decide on TLG individual subscription** only when a concrete research need hits the gap.
