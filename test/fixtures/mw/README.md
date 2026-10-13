# Monier-Williams fixtures (P17-4 Phase B — dictionary shelf, fourth occupant)

Real upstream sample from the **Cologne Digital Sanskrit Lexicon (CDSL)**
MW 1899 XML edition (CLAUDE.md fixture rules; fixture plan owner-approved
2026-07-13, .docs/surveys/mw-survey.md §6). Every kept record line is **byte-verbatim**
upstream data; only the record SET was trimmed. `mw.dtd` and `mwheader.xml`
are verbatim whole files — the license grant travels inside the fixture
exactly as upstream ships it inside the zip.

- **Upstream:** sanskrit-lexicon.uni-koeln.de, MW download page
  `/scans/MWScan/2020/index.html`.
- **Retrieved:** 2026-07-13, from
  `https://www.sanskrit-lexicon.uni-koeln.de/scans/MWScan/2020/downloads/mwxml.zip`
  (11,685,470 bytes, sha256
  `092a586e5ffe7ad7e5a21bf64bffa2c8d916ff125bb0a7c5f645b3b469978cc8`,
  Last-Modified `Sun, 05 Jul 2026 10:53:32 GMT` — upstream is actively
  corrected, NOT frozen; survey §1). Zip contents: `xml/mw.xml` (64 MB,
  sha256 `1e1932ce…7558b9`, 286,530 lines / 286,525 records), `xml/mw.dtd`,
  `xml/mwheader.xml`, `xml/mw-meta2.txt` (coding manual, not snapshotted).
- **License (mwheader.xml `<availability>`, verbatim):** "Copyright © 2014
  The Sanskrit Library and Thomas Malten … Creative Commons Attribution
  Non-Commercial Share Alike license … Permission is granted to build upon
  this work non-commercially, as long as credit is explicitly acknowledged
  exactly as described herein, and derivative work is distributed under the
  same license." → CC BY-NC-SA 3.0, license_class `nc` (survey §1 verdict).
- **Attribution:** The Sanskrit Library and Thomas Malten; Cologne Digital
  Sanskrit Lexicon (CDSL), sanskrit-lexicon.uni-koeln.de.

## Upstream format reality (what this fixture preserves)

- One record per LINE inside `<mw>…</mw>` (`<!DOCTYPE mw SYSTEM "mw.dtd">`);
  a streaming line parser is mandatory over the 64 MB whole (no DOM).
- Record shape `<H1|H2|H3|H4[A|B|C|E]><h><key1/><key2/><hom?/></h><body>…
  </body><tail><L/><pc/></tail>`. Main records H1–H4 open an entry; lettered
  records (A sense-continuation, B gender block, C inflected form,
  E etymology) continue the immediately preceding main. `<L>` is the stable
  Cologne id (fractions mark supplement inserts: 27.1, 92.1).
- Headwords and in-body `<s>` Sanskrit are **SLP1** (`aMSa` = aṃśa); `key2`
  additionally carries accent (`a/MSa`) and compound seams (`aMSa—karaRa`).
  No Devanagari anywhere. Greek cognates (`<gk>`) are polytonic Unicode.
- Machine-readable apparatus on `<info>`: `lex=` normalized gender
  (`m`, `m:f:n`, `f#A:n`, `inh` = inherited from the main record), `verb=`
  root class + `cp=` class-pada (`1Ā,1P`; also EMPTY `cp=""` — L 87),
  `westergaard=`/`whitneyroots=` Dhātupāṭha/Whitney links, `n="sup"` marks
  supplement records.
- Citations are tagged `<ls>`; elliptical continuations are pre-resolved
  upstream via `@n` (`<ls n="RV.">x, 109, 1</ls>` — L 313). Sigla follow
  MW's own works-and-authors key (`RV.`, `MBh.`, `L.` …).
- Cognate notes pair `<lang>` with adjacent `<etym>`/`<gk>` comparanda
  (L 92.1); `<lang>` ALSO carries register markers (`ep.` in L 150479) that
  are NOT cognate languages.

## This file — 26 record lines, 11 grouped entries

| Cluster | Records | Why |
|---|---|---|
| aṃśa (survey §6 cluster 1) | L 10 + A-continuations 11–19; H3 compounds L 20, L 26 (accented seam key2 `aMSa—BU/`, `TS.` not-held citation), L 27, L 27.1 (supplement, `RTL. 187`) | citation-dense group: `RV. v, 86, 5` (L 14) is the survey's END-TO-END VERIFIED passage-grain resolution; `L.` authority label (L 18); `TāṇḍyaBr.` not-held |
| aṃśala / aṃs | L 44 (`See aMsala/` cross-ref), L 87 (root, `verb="genuineroot" cp=""`, See-ref) | See-refs render in body via SLP1→IAST; empty cp edge case |
| aṃsa (survey §6 cluster 2) | H2 L 88 + A 89–90 + B 91–92 + E 92.1 | the cognate-note record: Goth. amsa; Gk. ὦμος, ἄσιλλα; Lat. humerus, ansa → 5 reflex rows; B-block gender continuation |
| akūpāra | L 313 | `<ls n=…>` elliptical restoration, two RV passage-grain citations |
| √bhāṣ (survey §6 cluster 3) | L 150479 | full verb apparatus (`cl. 1. Ā.`, `cp="1Ā,1P"`, `westergaard`, `whitneyroots`), `<div n="to"/>` sense breaks, `<lang>ep.</lang>` register (must NOT mint a reflex), 20 `<ls>` across all four tiers (`Pāṇ. vii, 4, 3`, `Mn.`, `Nir.`, `Bhaṭṭ.`, `MārkP.`, `R.` held; `MBh.`, `Dhātup.`, `Suśr.` not-held; `Br.`, `Kāv.`, `ib.` authority) |
| bhāṣaṇa | L 150481 + A 150482 | `lex="f#A:n"` gendered-suffix apparatus; `Sāh.` held |

## Extraction recipe (one-shot, run 2026-07-13)

From the unzipped `xml/mw.xml` (line numbers of that snapshot):

```
awk 'NR>=1 && NR<=4'  mw.xml  > fixture   # xml decl, DOCTYPE, comment, <mw>
sed -n '23,33p;39,41p;58p;101,107p;381p;164586p;164588,164589p' mw.xml >> fixture
tail -1 mw.xml >> fixture                 # </mw>
```

Every extracted line is byte-verbatim (`grep -F` of each record line against
the upstream file succeeds); re-apply after any refresh.

## `crossrefs-slice.xml` — the P124-3 cf./q.v. slice (4 records)

A second, separate slice (not named `mw.xml`, so `discover` never picks it
up) cut 2026-10-13 from the same upstream `xml/mw.xml` (sha256
`1e1932ce…7558b9`): the upstream frame lines plus four record lines,
byte-verbatim (upstream lines 2049, 2062, 12696, 12709).

| Record | Why |
|---|---|
| L 1702 aṅguri | "(for `<s>aNguli</s>`, `<ab>q.v.</ab>`)" — the q.v. shape; "(`<ab>cf.</ab>` `<s>an-aNguri</s>`, `<s>pa/YcA<srs/>Nguri</s>`, …)" — only the first, adjacent list item is a pointer |
| L 1715 aṅguli | the q.v. target (resolves) |
| L 10608 apratiṣṭabdha / L 10619 apratistabdha | a mutual cf. pair ("cf. … below" / "cf. … above") — both resolve |
