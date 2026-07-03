# First1KGreek fixtures

Real upstream samples from OpenGreekAndLatin's First1KGreek corpus
(CLAUDE.md fixture rules). All files are small and kept **whole** — no trimming.

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
