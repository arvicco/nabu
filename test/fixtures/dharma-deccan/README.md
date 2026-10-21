# dharma-deccan fixtures

Real files from the DHARMA Task Force B repos on github.com/erc-dharma
(branch `master`), retrieved 2026-10-11 by shallow clone and copied
unmodified unless marked TRIMMED. Each file sits under its repo's own
name and path, mirroring `canonical/dharma-deccan/<repo>/<path>`:

- `tfb-eiad-epigraphy/texts/xml/DHARMA_INSEIAD00001.xml` — EIAD 1, the
  octagonal pillar from Nagarjunakonda: Prakrit prose (`pra-Latn`) at
  line grain; two grants (the DHARMA file's CC BY-SA 4.0 and the 2017
  EIAD edition's CC BY 3.0 in sourceDesc).
- `tfb-satavahana-epigraphy/satavahana-inscriptions-data_Ollett/Am499.xml`
  — Ollett's Amarāvatī 499: NO in-file `<licence>` (the repo-licence
  fallback case), origDate 100–200 CE, origPlace findspot.
- `tfb-satavahana-epigraphy/satavahana-inscriptions-data_Ollett/N10.xml`
  — Nasik 10 (Uṣavadāta): in-file CC BY 3.0, dated 60–84 CE, and a
  `<div type="commentary">` nested INSIDE the edition (the prune pin).
- `tfb-satavahana-epigraphy/satavahana-inscriptions-data_Ollett/My1.xml`
  — Myākadoni, year 8 of Vāsiṣṭhīputra Śrī Puḷumāvi (added 2026-10-21,
  copied whole from the synced canonical tree at upstream HEAD
  `4ec16f19efbe549e5e3256e60c10b02375a52be2`): licence-less, the
  edition's `<date datingMethod="cal:regnal">` (the regnal-year pin)
  beside Ollett's own origDate ca. 90 CE; the translation restates the
  regnal date.
- `tfb-satavahana-epigraphy/LICENCE.txt` — the repo's CC BY 4.0 grant
  (the fallback reads its first line).
- `tfb-telugu-epigraphy/texts/DHARMA_INSTelugu00048.xml` — a Telugu
  (`tel-Latn`) label inscription; its `<title>` holds only a template
  comment (title falls back on the stem).
- `tfb-kalyanacalukya-epigraphy/xml-provisional/DHARMA_INSKalyanaCalukya01004.xml`
  — Ālūr, 1124 CE: Kannada (`kan-Latn`) prose opened by a Sanskrit
  anuṣṭubh stanza (the verse case, `met` annotation), maturity 83215.
- `tfb-vengicalukya-epigraphy/xml/DHARMA_INSVengiCalukya00099.xml` —
  Pithapuram plates (set 2) of Jayasiṁha I: multi-face plates (seal face
  A, plate faces 1v/2r… sections).
- `tfb-vengicalukya-epigraphy/DHARMA_mdt_VengiCalukya_v01 - Text.tsv` —
  TRIMMED: the repo's metadata table cut to its four header rows plus
  the data rows for INSVengiCalukya00001 and 00099 (the date join).

Recipe: `git clone --depth 1 https://github.com/erc-dharma/<repo>`, copy
the paths above; the TSV trim keeps lines 1–4 and the rows whose column
14 ("Identifier of the text") is INSVengiCalukya00001 / 00099.

Licences: as recorded per file above (CC BY-SA 4.0, CC BY 3.0, or the
repo's CC BY 4.0) — redistributable here with attribution to DHARMA
(ERC no. 809994) and, for the Sātavāhana files, Andrew Ollett.
