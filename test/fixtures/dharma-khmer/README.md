# dharma-khmer fixtures

Whole real edition files from the DHARMA Corpus des inscriptions
khmères (github.com/erc-dharma/tfc-khmer-epigraphy, master), retrieved
2026-09-01 from raw.githubusercontent.com, unmodified:

- `texts/xml/DHARMA_INSCIK00001.xml` — K. 1, the stela of Vat Thleng:
  pre-Angkorian Old Khmer prose (`okz-Latn`), 26 physical lines, the
  add/unclear/`break="no"` repertoire, maturity 83211.
- `texts/xml/DHARMA_INSCIK00046.xml` — K. 46 (first-sync regression,
  copied from the 2026-09-01 canonical fetch): multi-face verse whose
  numbering restarts per face, the faces marked by
  `<milestone type="pagelike" unit="face">` INSIDE the verse lines —
  the section-prefix mechanism's pin.
- `texts/xml/DHARMA_INSCIK00002.xml` — K. 2, the fragmentary doorjamb
  from Phnom Svam: Sanskrit verse (`san-Latn`), 11 stanzas at lg/l pada
  grain, gap-heavy opening (the marker-only-pada skip case), maturity
  83213.
- `texts/xml/DHARMA_INSCIK00814-2.xml` — K. 814-2 (P120-R1 regression,
  copied whole and unmodified from the hub's canonical fetch at upstream
  commit 3428a54c26bc): six lines of Old Khmer prose whose edition div
  NESTS a French `<div type="translation">` and a
  `<div type="bibliography">` (a commented-out apparatus/commentary
  too). Before the shared parser pruned nested editorial divs, both
  divs' prose glued onto line 6 as if it were Old Khmer — the pin that
  editorial text never mints while the six edition lines stay
  byte-identical.
- `texts/xml/DHARMA_INSCIK00452.xml` — K. 452 (P120-R1 regression, same
  provenance): six Sanskrit stanzas (`san-Latn`) whose edition div nests
  apparatus, a French (`fra`) translation, commentary and bibliography.
  The translation's paragraphs minted as `fra` and quarantined the whole
  edition; with nested editorial divs pruned it mints its 24 pādas.

License: each file's own `<licence
target="https://creativecommons.org/licenses/by-sa/4.0/">` (the repo
badge says CC BY 4.0; the in-file grant governs and rides document
metadata verbatim). Redistributable here under either.
