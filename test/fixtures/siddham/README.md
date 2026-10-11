# siddham fixtures

Four WHOLE, uncut zip members of "Siddham Texts Archive 20190221.zip"
(1,210,929 bytes, sha256
f9ebbf9938f6357daac3e12c0467db7ff1fe13d2b85e3130024318474694ac73, md5
741d7331e6bdf2c58fefc26e5bfb6f59 = Zenodo's published checksum), the
2019-02-21 version of Zenodo record 2574901 ("Siddham Epigraphic
Archive - Texts in EpiDoc", Dániel Balogh), retrieved 2026-10-11 from
https://zenodo.org/api/records/2574901/files/Siddham%20Texts%20Archive%2020190221.zip/content

License: CC BY-SA 4.0 — the Zenodo RECORD's license field
(cc-by-sa-4.0, API-read 2026-10-11). The TEI headers are deliberately
blank (title + idno only, no <availability>), so the record-level grant
is the basis, recorded at source level and per document.

The zip is flat: 427 `IN<5 digits>_TEI.xml` editions plus
`tei-epidoc.rng` and a stray `desktop.ini` (the census skips both).

- `IN00002_TEI.xml` — Eran Stone Inscription of Samudragupta: VERSE with
  nested half-verse `<lg type="halfverse">` groups, `<lb>` inside `<l>`,
  and upstream's duplicated line number (lb n="27" twice).
- `IN00021_TEI.xml` — Gadhwa Donation 3 of the Time of Kumāragupta I,
  GE 98: the ERA-TYPED title year (Gupta era) the date lane converts; a
  line that opens in one `<p>` and continues into the next.
- `IN00077_TEI.xml` — Khoh Charter 1 of Hastin, year 156: textparts
  (seal + body), plate `<pb>`s, standalone `<sic>` (read through) beside
  `<choice><sic/><corr/></choice>` (corr wins), surplus, and the UNTYPED
  title year (no era named — never converted).
- `IN00121_TEI.xml` — Sanchi Pillar Inscription of the 5th Century: a
  one-line `<ab>` text whose title carries a century attribution.

Recipe: download the record file above, `unzip` it, copy the four
members verbatim (`cp IN00002_TEI.xml IN00021_TEI.xml IN00077_TEI.xml
IN00121_TEI.xml test/fixtures/siddham/`).
