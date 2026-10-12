# tamilex fixtures

Five whole real files from four TAMILEX edition repos
(github.com/UHH-Tamilex/<repo>, branch main), retrieved 2026-10-12 from
`https://raw.githubusercontent.com/UHH-Tamilex/<repo>/main/<file>`,
unmodified. Each sits under its repo's directory name, mirroring the
canonical layout `canonical/tamilex/<repo>/`.

| file | upstream HEAD at retrieval | what it pins |
|---|---|---|
| `NalayiratTivviyapPirapantam/TVM1.8.2.xml` | `a5dc69186dcc584fa831f917e14067e551ea04ce` | Tiruvāymoḻi 1.8.2 (Nammāḻvār): one verse `lg` + parallel English, a `<num>` in the title, a 13-entry wordsplit closing on an ambiguous `superEntry` (Kaṇṇaṉ / "eye-he") |
| `Kuruntokai/KT1.xml` | `1b0fdf46c9e6a345258ad343661f7d4000e489fb` | Kuṟuntokai 1 (Tipputtōḷār): the `-kilavi` situation colophon, a 43-witness `listWit` (manuscripts and printed editions with their years), footnoted English with a `choice` of renderings, two wordsplits (glide/geminated/elided `c`, sandhi and simple forms, enclitic particles) and a four-`app` variant apparatus |
| `Kuruntokai/_KTSAMPLE.xml` | `1b0fdf46c9e6a345258ad343661f7d4000e489fb` | upstream's own EMPTY poem template — skipped by discovery rule, and a ParseError ("no edition text") if parsed |
| `Tirukkural/TK1.xml` | `1522875ea875f58651fe1322eb2ec0531b834111` | Tirukkuṟaḷ 1 (kaṭavuḷ vāḻttu): the couplet plus two commentary `<text>`s (Parimēlaḻakar, Maṇakkuṭavar) with xml:id'd paragraphs and English, a `sic`/`corr` choice, `editor role="translator"` |
| `Tolkappiyam/TolC273.xml` | `8dd962839dcc4326029c4169125926cfdbc1bc81` | Tolkāppiyam Collatikāram 273: the sūtra plus four commentaries whose prose blocks carry NO xml:id (positional citations), unpaired English edition statements, quoted verses with their own wordsplits (multi-word ambiguous readings), a bare `sic` and an `app` holding only a note |

License: CC BY-NC-SA 4.0, stated by the TAMILEX maintainers by email,
2026-10-12 (the repositories carry no license file yet; one is pending
upstream). The license permits redistribution with attribution under the
same terms, so the samples ship here publicly. Credit: TAMILEX
(Universität Hamburg), Prof. Eva Wilden, Jean-Luc Chevillard and the
project of the Academies' Programme; the translators named in each file.

Recipe (re-cut): GET each URL above (or copy from
`canonical/tamilex/<repo>/` once synced) and save it whole under
`test/fixtures/tamilex/<repo>/`.
