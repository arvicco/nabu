# GRETIL fixtures (P9-4b + P9-4c + P10-3)

Nine real TEI P5 texts from GRETIL (Göttingen Register of Electronic Texts in
Indian Languages): three shipped with the adapter (P9-4b, below) spanning the
original addressability spectrum, four (P9-4c) that exercise the
quarantine-recovery rung + collision handling (see the P9-4c section), plus two
(P10-3) for the line-terminated marker shapes (see the P10-3 section at the
bottom). The first seven were retrieved **2026-07-08**; the two P10-3 fixtures
were cut from the same local canonical clone **2026-07-09**.

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

## P9-4c quarantine-recovery fixtures (4 more, cut from local canonical)

The first GRETIL real sync (P9-4b) quarantined 118/781 files in two classes;
P9-4c added a fourth addressability rung + collision tolerance to recover them.
These four fixtures are trimmed REAL slices from the **same local canonical
clone** (`mmehner/gretil-corpus-tei@master`), retrieved **2026-07-08**, same
verbatim CC BY-NC-SA 4.0 notice as above (`license_class: nc`). Each keeps the
actual quirk it exercises:

4. **`sa_RgvidhAna-a1.xml`** — the **xml:id rung** (fix 1). Flat `<lg
   xml:id="RgV_1.1.1">` with `<l xml:id="RgV_1.1.1a">` children, **no `@n`, no
   in-text marker, no prose**: the lg IS the passage, citation = the id with
   the `RgV_` prefix stripped (`1.1.1`). TRIM: teiHeader + upstream lines
   308..350 (Adhyāya 1, 8 lg) + closing tags. Recovered via the second-pass
   xml:id fallback (the primary rungs find nothing).
5. **`sa_bAdarAyaNa-brahmasUtra.xml`** — the **single-pipe marker** variant
   (fix 2). `<l>… | BBs_1,1.1 |</l>` (single-pipe delimiters, comma level
   separators) instead of `// Abbr_N //`. `whole: true` (complete short sūtra
   text, 545 sūtras → citations `1,1.1` … `4,4.22`). Recovered via the pipe
   fallback pass (kept out of the primary pass so clean docs that merely
   contain `| … |` reading text are untouched).
6. **`sa_AnandabhaTTa-vallAlacarita-c1.xml`** — the **single-prefix collision**
   (fix 3). The real upstream duplicate `// Valc_1.70 //` (two different verses
   both numbered 1.70). TRIM: teiHeader + upstream lines 698..738 (verses
   1.70–1.76 + the duplicate 1.70) wrapped in a `<div>`. The second 1.70 is
   disambiguated to `1.70:b2` (document order); neighbours untouched.
7. **`sa_Anandavardhana-dhvanyAloka-comm-u1.xml`** — the **multi-prefix**
   interleave (fix 3). `// DhvK_1.1 //` (kārikā) and `// DhvA_1.1 //`
   (commentary) collide on bare `1.1`; the prefix joins the citation
   (`DhvK.1.1` vs `DhvA.1.1`). TRIM: teiHeader + the real DhvK_1.1 / DhvA_1.1 /
   DhvK_1.2 lg (upstream lines 470–473, 1594–1598, 1857).

All four carry a `-a1`/`-c1`/`-u1` trim suffix (or are whole, file 5) so the
fixture urn is a fixture urn, never claiming the real corpus file's slug — the
same convention as file 3.

## License (verbatim, identical in all `<availability>` blocks)

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

## P10-3 line-terminated marker recovery fixtures (2 more, cut from local canonical)

The P9-4c census left 8 files quarantined; 4 were genuinely unaddressable flat
lists and 4 carried marker shapes the matched-delimiter passes cannot see —
both variants sit at the **end of an `<l>`, terminated by the `</l>` boundary**.
P10-3 adds a line-terminated marker fallback pass (LINE_MARKER, `LineMarker-
Extraction`) to recover those 4. These two fixtures are trimmed REAL slices from
the **same local canonical clone** (`mmehner/gretil-corpus-tei@master`), cut
**2026-07-09**, same verbatim CC BY-NC-SA 4.0 notice as above
(`license_class: nc`):

8. **`sa_vimalamitra-abhidharmadIpa-h1.xml`** — the **hyphenated closed marker**
   `// Abhidh-d_N //`. The primary `// Abbr_N //` pass rejects it because the
   prefix charset excludes the hyphen in `Abhidh-d`. TRIM: teiHeader + first
   4 `<lg>` (upstream lines 1..343 + closing tags) → citations `1`…`4`,
   addressing `verse-marker`.
9. **`sa_somAnanda-zAktavijJAna-l1.xml`** — the **leading-`//`-only marker**
   `// SomSv_N</l>` (no closing delimiter; the `</l>` terminates it). TRIM:
   teiHeader + first 4 `<lg>` (upstream lines 1..328 + closing tags) →
   citations `1`…`4`, addressing `verse-marker`. (The other two files of this
   shape — `sa_sAtvatatantra`, `sa_puruSottamadeva-ekAkSarakoza` — differ only
   in prefix/number form, e.g. `// SatvT_1.5`, and need no separate fixture.)

Both carry an `-h1`/`-l1` trim suffix so the fixture urn is a fixture urn,
never claiming the real corpus file's slug — the same convention as the P9-4c
fixtures above. The remaining 4 quarantines (`sa_abhinavagupta-paramArthasAra`,
`sa_bIjanighaNTu`, `sa_lagadha-RgvedavedAGgajyotiSa`,
`sa_vAmadeva-janmamaraNavicAra`) are genuinely unaddressable flat `<lg>`/`<l>`
with zero `@n`/xml:id/marker/prose and stay quarantined by design.
