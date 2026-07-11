# CCMH fixtures — Corpus Cyrillo-Methodianum Helsingiense

Trimmed real slices of the CCMH `-src` bundle's CES XML files (the four
gospel manuscripts of the approved v1 scope). Retrieved **2026-07-11** from
the Kielipankki PUB download tree:

    https://www.kielipankki.fi/download/ccmh-src/www/<name>.xml

Trimming = whole chapters/books removed; every retained line is
byte-identical to upstream (closing tags re-added where a book was cut
mid-file). Corpus persistent identifier: `urn:nbn:fi:lb-2021041522`
(catalogue), data bundle metadata `urn:nbn:fi:lb-20140730106`.

## License chain (verified 2026-07-11)

- `https://www.kielipankki.fi/download/ccmh-src/README.txt` verbatim:
  "Licence: CC-BY (https://creativecommons.org/licenses/by/4.0)"
- The download index labels `ccmh-src.zip` (2.1 MB) "CC BY".
- The Helsinki data catalogue record (item 342b3dd2-d1d7-4ee6-ad93-9f25cf31b3bf)
  shows access label "Open".

→ CC BY 4.0 → `license_class: attribution`. Attribution: CCMH, University
of Helsinki / Kielipankki (The Language Bank of Finland).

## Files

| fixture | trimmed to | exercises |
|---|---|---|
| `assemanianus.xml` | MAT 1 + JOH 21 (incl. file tail) | shape A (`<ver>`-wrapped), multi-`<ver>` segs, **duplicate seg id `b.JOH.21.25`** (distinct texts — lectionary parallels), `%` uncertainty marks |
| `savvina.xml` | MAT 1 + LUK 1 | shape A control (zero dup ids); lectionary chapter starting mid-chapter (LUK 1 opens at v. 32) |
| `marianus.xml` | MAT 5 + JOH 0 | shape B (text directly in `<seg>`, no `<ver>`), non-zero-padded ids (`b.MAT.5.23`), **non-canonical chapter `0`** (chapter-heading list), **duplicate seg id `b.JOH.0.14`**, no BOM (the other three have a UTF-8 BOM), a tab-indented `</div>` upstream quirk |
| `zographensis.xml` | MAT 3 (ms begins there — lacunose) | shape B control |

## Format notes (upstream reality, do not "fix")

- CES `cesDoc` version 4; `<cesHeader>` literally contains the placeholder
  text "ANYTHING YOU LIKE ABOUT THE FILE".
- Hierarchy: `<div type="book" id="b.MAT">` → `<div type="chapter"
  id="b.MAT.01">` → `<seg type="verse" id="b.MAT.01.01">`. Book codes are
  upstream's MAT / MAR / LUK / JOH (MAR not MRK, JOH not JHN).
- Shape A (assemanianus, savvina): verse text in `<ver id="1.01.01.0.0">`
  children; the 7-digit ver id = gospel(1–4) · chapter(2) · verse(2) ·
  line-in-verse · parallel-version digit. A seg may hold several `<ver>`.
- Shape B (marianus, zographensis): verse text is the seg's own mixed
  content; chapter/verse numbers in ids are not zero-padded.
- Text is the corpus's 7-bit ASCII transliteration (case-significant):
  `&`=big jer, `$`=small jer, `@`=jat, `O`=big jus, `E`=small jus,
  `jO`/`jE`=iotated jusy, `w`=ot/omega, `x`=xer, `q`=shta, `C`=cherv,
  `S`=sha, `Z`=zhivete, `D`=dzelo, `T`=fita, `I`=i(10), `J`=broad i,
  `G`=gerv, `U`=izhica; editorial marks `*`=capital in ms, `!`=titlo,
  `'`=poerok, `~`=breve, `^`=circumflex, `(`=dasia, `[…]`=interpolated,
  `{…}`=superfluous, `=…=`=later addition, `%`=place the editors flagged
  as needing checking, `-`=missing. Stored verbatim (Cyrillic
  back-transliteration would be an enrichment, not canonical).
- The e-texts are tertiary sources keyed to the printed editions (e.g.
  Vajs–Kurc for Assemanianus) and "have not been properly checked" —
  upstream's own words; the `%` marks are part of the text.
