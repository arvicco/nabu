# TLHdig fixtures

Real files from TLHdig — Thesaurus Linguarum Hethaeorum digitalis, Beta
Version 0.3: retrieved 2026-07-19 from
https://zenodo.org/records/20328284/files/TLHbasisONLINE25_1_ZENODO_Beta_03.zip
(record https://zenodo.org/records/20328284, DOI 10.5281/zenodo.20328284,
published 2026-05-21). The zip is 74,449,198 bytes;
**md5 `f9acbc8db3111cc7dd88d82f7819a912`** — verified byte-for-byte against
the Zenodo record's own published checksum at download — and
**sha256 `c845a23223bb9461eeb215f5ede0e223c8871473873c6123eadaeb72114fcd36`**
(the adapter's `ZIP_SHA256` pin, computed from that verified download).

## License

Zenodo record license field, both Beta versions: **`cc-by-4.0`** →
class `attribution`. Prescribed citation (verbatim, carried in the
manifest): "Thesaurus Linguarum Hethaeorum digitalis, hethiter.net/:
TLHdig – Beta Version 0.3 (2025-11-01)".

## Recipe

Every file is a **byte-verbatim WHOLE in-zip file** at its real relative
path under the zip's `TLHbasisONLINE25_1_ZENODO_Beta_03/` corpus
directory (no trims — AOxml manuscripts are small; the two quarantine
exemplars moved under `quarantine/` so discover, which scans only
`CTH *` folders, never yields them: their damage is exercised via
hand-built refs). `unzip` the artifact and `cp` the six paths below.

## Corpus files (discoverable)

- `CTH 626_XML_HFR/KBo 52.195+.xml` (16,722 B, sha256 `87ae57c6…`) — the
  WELL-PRESERVED merged manuscript: 4-witness join (header `docID`
  "KBo 52.195++" ≠ filename — the ++ quirk pinned; nested `<merged>`
  history; `AO:Manuscripts` sigla KBo 52.195 / Bo 7016 / Bo 6803 /
  KBo 52.113 with `{€n}` sigla in line numbers), 32 lines, digit
  selections with letter sub-alternatives (`mrp0sel=" 1a"`), ① markers
  inside mrp values, kolon breaks (`clb`), **both ḫūmant- attestations
  the piet-seam test rides**, the slash-variant lemma `dai-/te-/ti(ya)-`,
  Sumerograms/Akkadograms/determinatives, ⌈ ⌉ damage.
- `CTH 433_XML_BESRIT/KBo 43.277.xml` (4,215 B, sha256 `73ac692e…`) — the
  DAMAGE-HEAVY fragment: `mrp0sel="DEL"` words, illegible `x` signs,
  UNRESOLVED multi-candidate analyses (`tarn=a-`/`tarn=aḫḫ-` under
  `mrp0sel=" "` — the no-lemma rule's pin), a 13-alternative brace list
  (ŠU.GI), Akkadogram `I-NA`, single-candidate-blank-selector words
  (EGIR-pa), `▒` damaged-glyph blocks in the cuneiform layer, `<space>`
  indentation, gap ("Rs.? bricht ab") + note.
- `CTH 314_XML_TLH/KUB 4.8.xml` (12,048 B, sha256 `cbb6c9a1…`) — the
  BILINGUAL (Hittite–Akkadian hymn): 19 `lg="Hit"` + 8 `lg="Akk"` lines,
  `mrp0sel="AKK"` word-language selectors, the header's `XXXlang`
  placeholder (the majority-language fallback's pin), `<c type="sign">`.
- `CTH 786_XML_HFR/KBo 20.119.xml` (25,974 B, sha256 `2e63b516…`) — the
  HURRIAN ritual: 92 `lg="Hur"` + 4 `lg="Hit"` lines → xhu majority,
  `mrp0sel="HURR"` throughout, `<subscr c="i"/>` sign-variant subscripts
  (wiᵢ), numeral Sumerograms (`<sGr>10</sGr>`), Akkadogram divine names.

## Quarantine exemplars (NOT discoverable — under `quarantine/`)

- `quarantine/KUB 10.7.xml` (2,173 B, sha256 `e20b3151…`; upstream path
  `CTH 612_XML_TLH/KUB 10.7.xml`) — NOT WELL-FORMED XML (mismatched
  tags; the transliteration got mangled into `AO:Manuscripts` blocks
  upstream). One of **224** such files in Beta 0.3 (censused with a
  strict parser over all 23,937) — ParseError quarantine, pinned.
- `quarantine/304_e.xml` (1,004 B, sha256 `44b0d475…`; upstream path
  `CTH 222_XML_TLH/304_e.xml`) — well-formed but LINE-LESS (a seal-
  impression stub: gap only, zero `<lb>`). One of **226** zero-line
  files — ParseError quarantine, pinned.

## Corpus censuses behind the numbers in tests and docs (2026-07-19)

Measured over the whole unpacked Beta 0.3 deposit:

- 23,937 manuscript XML files in 826 `CTH n_XML_<project>` folders
  (663 distinct CTH numbers; suffixes TLH 393 / HFR 143 / BESRIT 84 /
  HDivT 53 / SVH 40 / HAnn 37 / MYTH 35 / GEBET 17 / PTAC 11 / luw 6 /
  KULTINV 5 / LUWGR 3 / ARINNA 2). `__MACOSX` + `.DS_Store` junk ride
  the zip and stay unscanned.
- ONE byte-identical urn twin: `CTH 999_XML_TLH/{BESRIT,TLH}/KUB 46.39+
  .xml` (cmp-verified identical) — the skip-by-rule censused in
  discovery_skips. `(cth, project, basename)` is otherwise unique.
- Line languages (`lb/@lg`): Hit 370,217 · Akk 17,866 · Hur 13,466 ·
  Hat 6,400 · Luw 3,643 · Sum 1,601 · Pal 587 · Hattian 46 — the censused
  map — plus junk (`5f_` 484, `ign` 75, empty 44, attribute damage ≤13,
  `Lu` 1) → und + verbatim raw, never guessed.
- Morphology: 757,728 words carry ≥1 mrp candidate; 453,819 digit-
  selected + 95,986 single-candidate = 72.6% disambiguated (mint
  lemmas, silver); 207,923 multi-candidate unresolved (annotations
  only).
- THE PIET SEAM: 316 HITT reflex rows mint from the full canonical
  starling piet.dbf (306 distinct folded keys; the P31-1 brief's "323"
  was the scout's raw-cell estimate — 360 non-empty HITT cells, 316
  pass the starling citation-form gate). Corpus-wide join vs TLHdig
  folded lemma keys: **205/306 = 67.0%** (disambiguated subset),
  215/306 = 70.3% (all candidates). Fixture-level: 11 folded keys join
  (arha, da, dai, epp, hark, ḫūmant→humant, ka, maḫḫan→mahhan, nu,
  parā→para, te). The starling piet FIXTURE carries 0 HITT-bearing
  records (chosen for other columns before P31-1), so the strict
  fixture×fixture join is vacuous — the seam test seeds a real piet
  HITT word (ḫūmant-) with the starling member fold instead.
