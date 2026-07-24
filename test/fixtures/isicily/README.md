# I.Sicily fixtures — P29-4 (+ P34-0 siblings, P43-r1 @n fallback)

Seventeen real EpiDoc records for the `isicily` adapter
(`Nabu::Adapters::Isicily` / `IsicilyEpidocParser`). The original twelve
were retrieved **2026-07-18** from `https://github.com/ISicily/ISicily`
at commit `db1a4959f4bb2fc42468e7f1ac0d017b2cafe928` (master, pushed
2026-07-18T04:33Z), **byte-identical, whole files** (median upstream file
is 12.7 KB — nothing needed trimming); ISic000006/003360/020307 added
2026-07-20 (P34-0 `-en`/`-it`/`-translit` sibling minting), extracted
from the **same pinned commit** via `git cat-file`. Raw-file URL pattern:
`https://raw.githubusercontent.com/ISicily/ISicily/db1a4959f4bb2fc42468e7f1ac0d017b2cafe928/inscriptions/<ID>.xml`.
Per-file git blob shas in `manifest.yml`.

ISic000030/000419/000756 (below) and the two `quarantine/` exemplars
were added **2026-07-23** (P43-r1, the D42-c quarantine-recovery ruling):
**extracted from the local canonical snapshot 2026-07-23** — the GitFetch
clone of the same upstream repo at commit
`62e6a2868438ebb06a29f86fd88737e227043acd` (master, committed
2026-07-19T04:55Z) — byte-identical whole files, blob shas verified
against that commit's tree with `git ls-tree`.

## `quarantine/inscriptions/` — permanently-quarantining exemplars

Two real records whose parse MUST raise (`ISic001698`: mixed textpart
numbering; `ISic000469`: duplicate same-language translation cites —
upstream tags its Italian translation `xml:lang="en"`). They live in
their own `quarantine/inscriptions/` subtree, **outside the conformance
suite's discover workdir** (which scans only this directory's
`inscriptions/`), because conformance treats any `ParseError` as a
failure; tests point discovery at `quarantine/` explicitly to pin the
honest refusals.

- Layout mirrors the canonical workdir GitFetch clones into:
  `inscriptions/ISic<NNNNNN>.xml` (the repo also carries
  `documentation/`, `alists/`, `signacula/` etc.; discovery only globs
  `inscriptions/ISic*.xml`, so the fixture tree holds only that).

## License (three concordant layers — no conflict)

- Repo `licence.txt`: the full **CC BY 4.0** legal text.
- GitHub license field: `CC-BY-4.0` (API-verified 2026-07-18).
- EVERY record's `<availability>`: `<licence
  target="http://creativecommons.org/licenses/by/4.0/">Licensed under a
  Creative Commons-Attribution 4.0 licence</licence>`.

→ class `attribution`. Facsimile `<graphic>` images carry separate
museum-permission language in their `<desc>` and are never fetched.
Corpus archived at Zenodo: DOI 10.5281/zenodo.2556743.

## Corpus census (2026-07-18, full clone at the pinned commit)

5,120 `inscriptions/ISic*.xml` records. `textLang/@mainLang`: grc 3,194 ·
la 1,232 · xly 319 · scx 299 · xpu 67 · osc 4 · he 2 · xx 1 · absent 2.
759 primary editions carry no text at all (catalogued monuments →
metadata-only documents); non-empty concordance idnos: TM 2,697, PHI
2,684, EDCS 1,962, EDR 875, EDH 8; `origDate` on 4,577 records
(`notBefore-custom`/`notAfter-custom`, `datingMethod="#julian"`, signed
years, 2,117 BCE files); numeric `<geo>` on 5,055 (27 placeholder "...").

## Records (whole, byte-identical)

| File | mainLang | Quirks it preserves |
|---|---|---|
| `ISic000006.xml` | la | **Non-empty en AND it translation divs** (P34-0): one prose `<p>` each → `-en`/`-it` siblings cited `p1`, the first paragraph carrying the `corresp` whole-text anchor at the primary's first line. |
| `ISic000001.xml` | la | Funerary of Zethus: interpunct `<g ref="#interpunct">·</g>` (text kept), `expan/abbr/ex` expansion, **`simple-lemmatized` edition layer** (`<w n="5" lemma="Deus">` joins primary `<w n="5">` → per-line `words` annotations), CE `origDate 0051/0300`, modern-placeName-only findspot (GeoNames ref), TM + EDCS concordances, empty `EDR/EDH/PHI` idnos (skipped honestly). |
| `ISic000451.xml` | la | **Self-closed `<g ref="#ivy-leaf"/>`** (contributes nothing), `choice/orig/reg` → reg ("hic"), **`<lb break="no"/>` INSIDE the kept reg branch** (annu\|s), `<num>` text kept. |
| `ISic000764.xml` | la | The **EDH-concordance exemplar** (one of only 8 corpus-wide): EDH 015282 → `urn:nabu:edh:hd015282` cross-catalog edge, EDR/EDCS/TM edges, `break="no"` chains, supplied/unclear/expan, Pleiades + GeoNames refs. |
| `ISic001510.xml` | xpu | **Sicilian Punic**: single Phoenician letter 𐤀, `style="text-direction:r-to-l"` on `lb`, BCE date `-0600/-0401`, Pleiades ref (Selinus). |
| `ISic001620.xml` | osc | **Mamertine Oscan in Greek script** (`xml:lang="osc-Grek"` on the edition → passage language), the Messana meddices dedication; supplied/unclear read-through, non-empty English translation div (journaled, not minted). |
| `ISic001895.xml` | grc | **Textparts** (`div type="textpart" subtype="section" n="1"/"2"`) → textpart-path urns `…:1:1` / `…:2:1` (line numbers restart per section). |
| `ISic002954.xml` | scx | **Sicel**: bare `<orig>` OUTSIDE `<choice>` is the letters-only edited text and is KEPT (ΥΡΙΕΙΑΙΡ), `unclear` counts, three `gap`s fusing into the line. |
| `ISic003475.xml` | grc | Greek epitaph with `simple-lemmatized` layer (Μέλισα → Μέλισσα), BCE date `-0400/-0201`, nested persName/name kept. |
| `ISic003360.xml` | scx | **Sicel `subtype="transliteration"` edition** (P34-0): `scx-Grek` primary beside a line-for-line `scx-Latn` transliteration → the `-translit` sibling, suffix-equal 1:1; the lang-less empty translation div mints nothing. |
| `ISic020307.xml` | xly | **Elymian PARTIAL transliteration** (P34-0): the translit div carries only `lb n="2"` of the primary's lines 1–2 — the `-translit` sibling pairs line 2, line 1 stays honestly one-sided; empty en/it translation divs mint nothing. |
| `ISic020002.xml` | xly | **Elymian metadata-only record**: primary edition holds only `<note>traces</note>` (dropped) → ZERO citable lines → metadata-only document (never a quarantine); Segesta Pleiades ref + BCE date `-0500/-0480` still feed the axis. |
| `ISic000030.xml` | la | **Bare `<lb/>` before a lost-line gap** (P43-r1): the unnumbered lb opens a gap-only line (`<gap unit="line"/>` — the upstream lost-lines idiom, 35 records at commit 62e6a28) beside numbered lines 1–3; the gap-only line is dropped as ever, so no number is needed and the document parses with upstream's own numbering. Non-empty en translation div → `-en` sibling. |
| `ISic000419.xml` | grc | **All-unnumbered textparts** (P43-r1): four `div[@type="textpart"]` carry `@subtype="gallery-1..4"` but no `@n` (6 such records at 62e6a28) → whole-edition document-order fallback paths `1..4`, every passage + the document marked `"numbering" => "document-order"`. |
| `ISic000756.xml` | la | **All-unnumbered lb, gap-only** (P43-r1): the record's single `<lb/>` (no `@n`) opens an illegible-lines gap — the ONLY all-unnumbered-lb record corpus-wide, and even it mints no citable line → metadata-only document, no numbering invented. |
| `quarantine/…/ISic001698.xml` | la | **Mixed textpart numbering — still quarantines** (P43-r1 refusal pin): unnumbered `subtype="border"` textpart with citable text beside `subtype="monogram"` textparts `n="1..4"` — implicit ordinals could collide with the explicit numbers, so the parse honestly refuses (`ParseError`). |
| `quarantine/…/ISic000469.xml` | la | **Duplicate translation cites — still quarantines** (P43-r1 regression pin, out-of-scope class): two `<div type="translation" xml:lang="en">` (the second is actually Italian — upstream mistag) both mint cite `p1` for the `-en` sibling → duplicate passage urn → `ParseError`. The BASE record parses fine. |
