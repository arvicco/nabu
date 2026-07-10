# First1KGreek fixtures

Real upstream samples from OpenGreekAndLatin's First1KGreek corpus
(CLAUDE.md fixture rules). All files are kept **whole** except the Nicomachus
edition (P6-1), a documented trim of a 442 KB file — see its table row and
manifest.yml.

- **Retrieved:** 2026-07-03, from `master` of
  [OpenGreekAndLatin/First1KGreek](https://github.com/OpenGreekAndLatin/First1KGreek)
  via `raw.githubusercontent.com`, base
  `https://raw.githubusercontent.com/OpenGreekAndLatin/First1KGreek/master/data/`.
- **License:** CC BY-SA 4.0 (repo-level). Attribution: OpenGreekAndLatin /
  First1KGreek contributors.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1).
- **Layout:** mirrors the upstream repo under `greekLit/data/<textgroup>/<work>/`.

## Files (exact URLs under the base above; sizes as fetched)

| Path (under `greekLit/data/`) | Bytes | Contents |
|---|---|---|
| `tlg2139/__cts__.xml` | 170 | textgroup metadata (Sicilus) |
| `tlg2139/tlg001/__cts__.xml` | 549 | work metadata |
| `tlg2139/tlg001/tlg2139.tlg001.1st1K-grc1.xml` | 4496 | *Sicili Epitaphium* (Seikilos), citation unit `section` |
| `tlg1126/__cts__.xml` | 178 | textgroup metadata |
| `tlg1126/tlg003/__cts__.xml` | 541 | work metadata |
| `tlg1126/tlg003/tlg1126.tlg003.1st1K-grc1.xml` | 4000 | *Fragmenta*, single-level citation unit `work` |
| `tlg2959/__cts__.xml` | 162 | textgroup metadata |
| `tlg2959/tlg008/__cts__.xml` | 535 | work metadata |
| `tlg2959/tlg008/tlg2959.tlg008.opp-grc1.xml` | 4649 | *De Martyribus (Fragmenta)*, citation unit `fragment`, edition slug `opp-grc1` |
| `tlg0358/__cts__.xml` | — | textgroup metadata (Nicomachus; copied whole from the local canonical snapshot, P6-1) |
| `tlg0358/tlg001/__cts__.xml` | — | work metadata (copied whole from the local canonical snapshot, P6-1) |
| `tlg0358/tlg001/tlg0358.tlg001.1st1K-grc1.xml` | 12131 | *Introductio arithmetica* (**trimmed**, P6-1): structural-retry exemplar — refsDecl units `book`/`section` vs body `div[@subtype="chapter"]` (renamed label); recovered from the replacementPattern xpath. Trimmed 2026-07-04 from the local canonical snapshot (synced 2026-07-03): teiHeader whole, chapter 1 reduced to section 1, chapter 2 to section 1 (chapter boundary kept), chapter 3 and remaining sections removed |
| `tlg4037/__cts__.xml` | — | textgroup metadata (Anonymi Paradoxographi; copied whole from the local canonical snapshot, P9-1) |
| `tlg4037/tlg001/__cts__.xml` | — | work metadata — carries both the grc `ti:edition` and the eng `ti:translation` (copied whole, P9-1) |
| `tlg4037/tlg001/tlg4037.tlg001.1st1K-grc1.xml` | — | *De Incredibilibus / Peri Apiston* original (**trimmed**, P9-1): `div[@type="edition"]`, citation unit `section`. Trimmed from the local canonical snapshot (synced 2026-07-03): teiHeader whole, sections 1–3 kept, 4–23 removed |
| `tlg4037/tlg001/tlg4037.tlg001.1st1K-eng1.xml` | — | *De Incredibilibus* English translation (**trimmed**, P9-1): `div[@type="translation"]`, citation unit `section`. Same trim (sections 1–3), so it aligns section-for-section with the grc original above — the P9-1 parallel-render pair |
| `tlg0527/__cts__.xml` | 164 | textgroup metadata (Septuaginta; fetched 2026-07-09 at pinned HEAD `4c9c843`, P11-5) |
| `tlg0527/tlg001/__cts__.xml` | 629 | work metadata (Genesis; Swete edition label Γένεσις) |
| `tlg0527/tlg001/tlg0527.tlg001.1st1K-grc1.xml` | 16062 | *Genesis* (LXX, Swete 1901; **trimmed**, P11-5): teiHeader whole + chapter 1 whole (verses 1–31, `chapter`/`verse` textparts), chapters 2–50 removed, document closed to the upstream shape. Ranged-fetched 2026-07-09 at pinned HEAD `4c9c843d80ee94b4371f52add5f7d68bbfe7ba4c`. The alignment hub's LXX witness exemplar (cts-verse extractor, P11-5) |

The `tlg2959` set was **conditional** in the approved plan (fetch the edition only
if both `__cts__.xml` probes returned 200). Both returned 200 on 2026-07-03, so all
three files were fetched.

## Structure notes (for the First1KGreek adapter, P3-2)

- Same CapiTainS/EpiDoc conventions as Perseus — the adapter reuses `EpidocParser`
  plus Perseus repo-layout knowledge.
- Path pattern `data/<textgroup>/<work>/<tg>.<work>.<edition>.xml`; the CTS
  namespace (`greekLit`) is the repo, not a path segment.
- `div[@type="edition"]/@n` carries the full CTS edition URN
  (e.g. `urn:cts:greekLit:tlg2139.tlg001.1st1K-grc1`).
- **Edition slugs are NOT uniformly `1st1K-grc1`.** This sample deliberately
  includes `opp-grc1` (tlg2959) so the adapter's original-language edition
  matcher is exercised against more than one slug family.
- Citation depth varies per work — trust the `refsDecl` `cRefPattern` units
  (`section` / `work` / `fragment` here), not div nesting.
- All XML parses strict (Nokogiri) as fetched.

## English translations (P9-1)

- With `translations: true` (registry, owner-directed 2026-07-08) the adapter
  also ingests the corpus's ~45 English editions. Their slug family is **not**
  the perseus base's `perseus-eng<n>` — it is dominantly `1st1K-eng<n>`, with an
  `opp-eng<n>` and letter-suffixed variants (`1st1K-eng1a`/`1b`). So
  `First1kGreek#translation_slug_pattern` mirrors its family-agnostic original
  rule and matches any `-eng<version>` tail.
- All eng editions anchor on `div[@type="translation"]` (no `edition`-typed eng
  file exists in the corpus). Of the 43 eng works a real `--parse-only` sync
  discovers, 41 parse cleanly; two quarantine **honestly** (upstream oddities,
  not adapter bugs):
  - `tlg0527.tlg048` ships letter-suffixed `1st1K-eng1a`/`1b` slugs that are
    `div[@type="commentary"]` (notes / appendix), not translations —
    highest-version selection picks the appendix (`eng1b`) and it quarantines
    (zero citable passages), rather than being folded in as a translation.
  - `heb0001.heb010.1st1K-eng1` is a Hebrew-namespace work mis-filed in the
    greekLit repo: its `div[@type="translation"]/@n` is `urn:cts:hebrewlit:…`,
    so the inherited edition-urn cross-check rejects the greekLit urn discover
    minted for it. A CTS-namespace mismatch, quarantined honestly.
- `tlg4037/tlg001` is the checked-in parallel pair: the grc original and its eng
  translation both cite at a single `section` level with identical `@n` values,
  so the pair aligns **section-for-section** (verse-style, all 1:1 pairs).
