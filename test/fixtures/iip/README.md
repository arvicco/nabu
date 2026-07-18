# IIP fixtures — P30-6

Six real EpiDoc records for the `iip` adapter (`Nabu::Adapters::Iip` /
`IipEpidocParser`) — Inscriptions of Israel/Palestine (Brown University).
Retrieved **2026-07-18** from
`https://github.com/Brown-University-Library/iip-texts` at commit
`0b7dc8358ccdfd0c9391f049da4839fbd91c26e5` (master tip, verified against
`git ls-remote` the same day), **byte-identical, whole files** (largest
record is 11.3 KB — nothing needed trimming). Raw-file URL pattern:
`https://raw.githubusercontent.com/Brown-University-Library/iip-texts/0b7dc8358ccdfd0c9391f049da4839fbd91c26e5/epidoc-files/<id>.xml`.
Per-file git blob shas in `manifest.yml`.

- Layout mirrors the canonical workdir GitFetch clones into:
  `epidoc-files/<4 letters><4 digits>[letter].xml` (the repo also carries
  `archival-files/`, `pelagios/`, `scripts/`, `include_taxonomies.xml`
  etc.; discovery only globs record-shaped names under `epidoc-files/`,
  which also excludes upstream's own `aaTestFile.xml` template —
  counted as skipped-by-rule in `discovery_skips`).

Six is one over the packet's 3–5 guideline — the corpus has four major
languages (grc/arc/he/la) AND three distinct record shapes
(transcription / diplomatic-fallback / metadata-only), and no five files
cover both spreads.

## License (what the bytes say)

- The repo has **NO LICENSE file** and GitHub's `license` API field is
  **null**.
- The working files (`epidoc-files/`) carry no license either: their
  `<publicationStmt>` is an **`xi:include` of
  `http://cds.library.brown.edu/projects/iip/include_publicationStmt.xml`**
  (a Brown server, not in the repo).
- The **archival copies in the same repo** (`archival-files/`, xi:includes
  resolved, "ingested periodically into the Brown Digital Repository")
  carry the resolved statement verbatim:
  `<availability status="free"><licence>This work is licensed under a
  Creative Commons Attribution-NonCommercial 4.0 International License.
  <ref target="http://creativecommons.org/licenses/by-nc/4.0/">Distributed
  under a Creative Commons licence CC BY-NC 4.0</ref>` plus "All reuse or
  distribution of this work must contain somewhere a link to the DOI of
  the Inscriptions of Israel/Palestine Project:
  https://doi.org/10.26300/pz1d-st89".

→ class **nc** (matches the backlog's expectation). NonCommercial: local
research use only; never redistribute, never expose to any external or
commercial surface.

## Corpus census (2026-07-18, full clone at the pinned commit)

5,536 `epidoc-files/*.xml` (5,535 records + upstream's `aaTestFile.xml`
template). `textLang/@mainLang`: grc 2,919 · arc 1,755 · he 376 · la 273
· phn 20 · syc 4 · xcl 4 · heb 2 · geo/Geo 2 · "Other" 3 · x-unknown 1 ·
empty/absent 4; 171 records add `@otherLangs` (he 74 · grc 53 · arc 24 ·
la 16 · syc 2 · phn 2). Editions: transcription 5,349 ·
transcription_segmented 5,160 (`<w id lang>` only — no lemmas, not
mined) · diplomatic 4,159; translation divs 5,213 (not minted, the
I.Sicily precedent). **Zero `<lb n>` corpus-wide** (15,968 lb, all
unnumbered → ordinal line policy); textparts 132 (only 44 carry `@n` →
ordinal `p<k>` path policy). `origin/date` on 5,534 records —
`@notBefore/@notAfter` on 5,261 (2,218 signed-negative BCE files, zero
year-0), `@period` on 5,519 (4,903 Periodo URIs). Findspot
region/settlement nearly universal; numeric `<geo>` on 470 only. **No
concordance idnos at all** (the only `idno/@type` corpus-wide is IIP
itself) → no reference edges. 7 malformed-XML files and 29
filename↔`publicationStmt` idno drift files (e.g. all four `arch000N`
claim `jeri0017`) quarantine honestly.

## Records (whole, byte-identical)

| File | mainLang | Quirks it preserves |
|---|---|---|
| `abur0001.xml` | grc | Greek invocation mosaic: implicit first line (text before the first unnumbered `<lb/>`), `expan/abbr/ex` nesting ("Κύριε"), `lb break="no"` mid-word, bare `<orig>` kept, supplied/gap, `<geo>` coordinates inside `<settlement>`, geogName site + geogFeat locus, text-valued `@period` ("Talmudic"), `<idno type="IIP">` present and agreeing. |
| `dabb0001.xml` | arc | **Jewish Aramaic, NFC-exempt byte-verbatim** (the file's edition text is not NFC); `@otherLangs="grc"`; inline `<foreign xml:lang="grc">` Greek spans inside Aramaic lines; edition div tagged `lang="heb"` on an `arc` record — the exemplar for why div/@lang never overrides `textLang/@mainLang`; Periodo-URI `@period`. |
| `jeru0490.xml` | he | Hebrew (→ heb, NFC applied at the boundary — the file is not NFC): `choice` of two `<unclear>` readings (first wins), word-dividing-dot `<g>` kept, BCE `notBefore="-0100"`, TWO space-separated Periodo URIs in `@period`, **no publicationStmt idno at all** (the 3,744-record norm — absence is never drift). |
| `caes0022.xml` | la | Latin with **textpart divs** (`subtype="section"` n="a"/"b") → ordinal `p1`/`p2` urn path + textpart annotation; a **stray `<lb/>` between textparts** (mints nothing); heavy `expan` + supplied-wrapped expans; empty `<ab/>` children. |
| `hkur0001.xml` | arc | **Diplomatic-only record** (no transcription div at all) → the diplomatic fallback layer, `text_layer: "diplomatic"`; leading `<lb/>` before any text (no phantom empty line 1); internal xml:ids say `hamm0071` (upstream copy-paste drift — filename is the only identity); **un-hashed multi-token facets** (`class="dedicatory building"`, `ana="jewish"`, objectDesc `ana="floor mosaic"`). |
| `caes0371.xml` | x-unknown | **Metadata-only record**: no edition divs at all → zero passages, `text_layer: "none"`, language und; `@period="Unknown"` with no notBefore/notAfter (dateless but placed — the axis place-only row). |
