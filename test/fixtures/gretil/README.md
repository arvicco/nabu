# GRETIL fixtures (P9-4b)

Three real TEI P5 texts from GRETIL (Göttingen Register of Electronic Texts in
Indian Languages), spanning the full addressability spectrum the `gretil`
parser family must survive (P9-4a scout census). Retrieved **2026-07-08**.

## Provenance — two byte-identical URL sets

Every file was fetched from the **GitHub TEI mirror** `mmehner/gretil-corpus-tei@master`,
which serves **byte-identical** copies of the primary GRETIL site files (verified
2026-07-08: the two whole fixtures match the live site bytes exactly). Both URL
sets are recorded so `rake fixtures:check[gretil]` can re-verify liveness against
either.

| File | Site URL (primary) | Mirror URL (raw — the fetch used) |
|------|--------------------|-----------------------------------|
| `sa_brahmabindUpaniSad.xml` | https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_brahmabindUpaniSad.xml | https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_brahmabindUpaniSad.xml |
| `sa_prajJApAramitAhRdayasUtra.xml` | https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_prajJApAramitAhRdayasUtra.xml | https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_prajJApAramitAhRdayasUtra.xml |
| `sa_Rgveda-edAufrecht-m1s1-3.xml` | https://gretil.sub.uni-goettingen.de/gretil/corpustei/sa_Rgveda-edAufrecht.xml | https://raw.githubusercontent.com/mmehner/gretil-corpus-tei/master/sa_Rgveda-edAufrecht.xml |

**Mirror-scope verification (P9-4b).** Despite the mirror's 2021 `pushed_at`, it
covers the **full current** TEI corpus: the live `corpustei/` directory holds
**784 XML files** (781 `sa_` + 2 `xct_` + 1 `ta-sa_`) — the identical count and
language mix as the mirror. GRETIL's TEI conversion has been stable since 2021.
The fuller, actively-maintained `INDOLOGY/GRETIL-mirror` (whole-site, ~1 GB,
pushed 2026-02) is the cross-check that confirmed the 784-file current count.
The adapter therefore fetches via the shared git clone path against the mirror.

## The three shapes

1. **`sa_brahmabindUpaniSad.xml`** — mass-converted **verse**, whole. Flat
   `<lg>`/`<l>` with no `@n`/`@xml:id`; the verse number is an in-text marker
   `// BrbUp_N //` at the END of the last `<l>` of each verse (it closes the
   verse it follows). 22 verses → citations `1`…`22`.
2. **`sa_prajJApAramitAhRdayasUtra.xml`** — **prose**, whole. Flat `<p>` with no
   numbering of any kind. 9 paragraphs → synthetic ordinals `p1`…`p9` (flagged
   non-canonical addressing).
3. **`sa_Rgveda-edAufrecht-m1s1-3.xml`** — hand-crafted **fully addressable**,
   **TRIMMED**. Nested `<div type="maṇḍala|sūkta" n>` → `<lg xml:id>` →
   `<l n="1.001.01a">`; Vedic accents ride in bare `<orig>` (combining U+0331
   anudātta / U+030D udātta), KEPT as pristine text. Citations are the `<l>/@n`
   verbatim (`1.001.01a` …).

## Trim procedure (file 3 only)

Files 1 and 2 are `whole: true` (complete short texts, byte-identical to
upstream). File 3, the full Ṛgveda-Saṁhitā, is ~5 MB; it was trimmed to
**teiHeader + Maṇḍala 1, Sūktas 1–3** (`whole: false`): kept lines 1..471 of the
upstream file (through the `</div>` closing sūkta 003), then closed the open
`maṇḍala` div, wrapper div, `<body>`, `<text>`, `<TEI>`. Result is well-formed
(nokogiri strict, 0 errors): 3 sūkta divs, 30 verses (`<lg>`), 60 padas (`<l>`),
311 `<orig>` accent elements. Re-applying the trim after a `fixtures:refresh` is
required (refresh would overwrite it with the full upstream file). Because the
fixture filename carries the trim suffix, its urn is a fixture urn
(`urn:nabu:gretil:sa_Rgveda-edAufrecht-m1s1-3`); the real corpus file
`sa_Rgveda-edAufrecht.xml` mints `urn:nabu:gretil:sa_Rgveda-edAufrecht`.

## License (verbatim, identical in all three `<availability>` blocks)

> This e-text was provided to GRETIL in good faith that no copyright rights have
> been infringed. If anyone wishes to assert copyright over this file, please
> contact the GRETIL management at gretil(at)sub(dot)uni-goettingen(dot)de. The
> file will be immediately removed pending resolution of the claim.
> Distributed under a Creative Commons Attribution-NonCommercial-ShareAlike 4.0
> International License.

→ `license_class: nc`. GRETIL is an **aggregator**, not the rights-holder (data
entry credited to individual contributors); the CC grant is GRETIL's, under the
takedown disclaimer above. The legacy pre-TEI HTML/text holdings (with their
older per-contributor notices) are **out of scope** — this source ingests the
mass-converted TEI corpus only, whose license is uniform and clean.
