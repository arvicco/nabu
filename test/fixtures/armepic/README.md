# armepic fixtures — ArmEpiC / ArtsakhEpiC (Zenodo 23501516)

Retrieved 2026-11-04 from the Zenodo record API
(`https://zenodo.org/api/records/23501516`, the record's `versions/latest`
resolves to the same id): **ArmEpiC – Armenian Epigraphic Corpus
(ArtsakhEpiC Sub-Corpus)**, version 7 ("Seventh digital edition
(2026-10-19)" in every file's editionStmt), published 2026-10-20,
DOI 10.5281/zenodo.23501516 (concept DOI 10.5281/zenodo.18198117).
Editors Hamest Tamrazyan, Gayane Hovhannisyan, Arsen Harutyunyan, Narine
Sarvazyan; data curators Emanuela Boros, Narek Meloyan; EPFL Digital
Humanities Laboratory (DHLAB).

License: the deposit's LICENSE.txt (pinned here as `LICENSE/LICENSE.txt`,
byte-identical): "The texts and data of this work (all TEI/EpiDoc XML files
and authority files in this deposit) are licensed under the Creative
Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)";
the record's license field `cc-by-nc-4.0`; every inscription's
`<licence target="https://creativecommons.org/licenses/by-nc/4.0/">`.
The photographs and drawings are "not covered by this licence" (rights stay
with the photographers and publications) — never fetched.

## The files (whole, untrimmed — each is 13–21 KB)

Laid out as the adapter's fetch lays out `canonical/armepic/`: one
FileFetch subdirectory per deposit file, named by the file's stem.

| path | what | why it is here |
|---|---|---|
| `ART0001/ART0001.xml` | donative inscription of Ter Hovhannes, abbot of Gandzasar, 1271 (9 lines) | the first-vintage markup (ART0001–ART0010): no `xml:lang` on the edition div, pretty-printed with whitespace inside `<w>`, the `<choice><orig>`/`<reg>` numeral pair, `<space>`, `<join>`, ligature `<hi>` |
| `ART0013/ART0013.xml` | khachkar of Ter Grigor at Vaghuhas, 1196 | nested textparts (section 1 › column 1 / column 2, section 2) whose `<lb n>` restart in every textpart; `<supplied>`; an origPlace with WGS84 `<geo>` |
| `ART0026/ART0026.xml` | building inscription of Catholicos Petros at Herher, 2nd half of the 17th c. | three monogram textparts with no `<lb>` (`<expan><abbr><am><g type="monogram"/></am></abbr><ex>…</ex></expan>`); a `notBefore-custom`/`notAfter-custom` century date |
| `ArmEpiC_ListInscriptionType_crm/ArmEpiC_ListInscriptionType_crm.xml` | the inscription-type authority list | the REJECTED grain's pinned specimen (below) |
| `LICENSE/LICENSE.txt` | the deposit license | provenance |

## Delivery grains (enumerated at fixture time, the whole record)

The record serves **66 files**:

- **50 inscription files `ART0001.xml`–`ART0050.xml`** — each one
  standalone TEI/EpiDoc record of one inscription: diplomatic edition with
  word-level lemma + UPOS, Armenian and English translations, commentary,
  physical description, dating, find-place with coordinates, bibliography.
  **ACCEPTED: one file = one document** (`urn:nabu:armepic:art0001`).
  The record description: "Fifty inscription files (ART0001.xml –
  ART0050.xml)"; ART0051–ART0079 exist in the collection but "are not
  part of this deposit".
- **12 authority files** (`ArmEpiC_List*.xml`: abbreviation types,
  bibliography, chronology, editors, inscription types, materials,
  monuments, object types, places, preservation, scripts, techniques) —
  controlled vocabularies, not inscriptions. **REJECTED, skipped by rule**
  (counted in `discovery_skips`); specimen pinned above. The inscription
  files already carry each term's English/Armenian label inline beside its
  `urn:armepic:` ref, so nothing the documents need lives only here.
- **README.md, CHANGES_v7.md, LICENSE.txt** — deposit documentation;
  fetched for provenance, never `.xml`, never a candidate document.
- **ArtsakhEpiC_v7_images.zip** (255,920,643 bytes) — photographs and
  drawings, outside the license; **never fetched**.

## Census of the full deposit (2026-11-04, every file read)

- 50/50 inscription files parse; each has exactly one
  `div[@type="edition"]`. 40 carry `xml:lang="hy"` on it, ART0001–ART0010
  none (the root is `xml:lang="en"` everywhere — the record's language,
  not the text's).
- 371 `<lb n>`; 7 records divide into textparts (section / column /
  monogram), `<lb n>` restarting per textpart; 1,873 `<w lemma pos>`.
- Dates: 50/50 carry `origin/origDate` — 41 `when-custom` (an Armenian-era
  year converted, `evidence="internal-date"`), 9 `notBefore-custom` /
  `notAfter-custom` palaeographic centuries; range 1183–1998 (8 records
  after 1700: 1725, 1728, 1738, 1763, 1858, 1868–1888, 1918, 1998).
- Places: 49/50 name an origPlace settlement (`urn:armepic:artsakh:PLC…`),
  41 with decimal coordinates; ART0043 names only its found-provenance
  ("Kashatagh, Cross stone").
- Through the adapter: 50 documents / 374 passages (371 lb-keyed lines +
  3 lb-less monogram textparts) / 1,872 word tokens, 12 authority lists
  skipped by rule, 0 errored.
- Inscription-type keyword terms (English; a record may carry two):
  construction 22, donation 15,
  commemorative 13, khachkar erection 5, construction / building 2,
  commemoration 1, dedication 1, donation / dedication 1, epitaph 1,
  religious-ethical 1, canonical-legal 1.
