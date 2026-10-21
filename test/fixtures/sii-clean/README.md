# sii-clean fixtures

Whole real files from github.com/erc-dharma/south-indian-inscriptions
(branch master), unmodified, each under its volume directory, mirroring the
canonical layout `canonical/sii-clean/SII_B_clean/SII<NN>/` and
`canonical/sii-clean/SII_A_raw/3out/<NN>/`. Two retrievals, both from a
blobless sparse clone:

- 2026-10-12, HEAD `3ea671b6c9b2b60e1834535ee16614ebdadf3195` — the eight
  grant-bearing clean editions of the first cut (SII08, SII17 0582/0656,
  SII22 0252/0349/0391/0408);
- 2026-10-21, HEAD `7660810200c43d60b8d711e710e3b3a05a0e6ddf` — everything
  else (the widening to the whole clean slice and the raw layer), plus both
  READMEs (`SII_B_clean/README.txt` carries the repository-wide licence
  statement of 2026-10-21).

## Upstream's grains (census at 76608102)

| grain | count | taken? |
|---|---|---|
| `SII_B_clean/SII<NN>/DHARMA_*.xml` — one DHARMA edition per inscription (or per printed range, `…i0290-0293`) | 4,796 | **yes** — the document |
| `SII_B_clean/SII<NN>/~DHARMA_*.xml` — an in-progress edition | 179 | no — outside the sparse cone, arrives by promotion; skipped by rule when present (pinned: `SII22/~DHARMA_INSSIIv22p0i0584.xml`) |
| `SII_A_raw/3out/<NN>/~DHARMA_*.xml` — one per-inscription conversion | 20,554 | **yes** where no clean edition covers the inscription (15,753); **superseded** (skipped by rule, censused per volume) where one does (4,801 — pinned: `3out/22/~DHARMA_INSSIIv22p0i0252.xml`, exact stem; `3out/04/~DHARMA_INSSIIv04p0i0290.xml`, inside the clean range 290-293) |
| `SII_A_raw/2mastercopy/volumes/NN.xml` — one master copy per printed volume (53) | 53 | no — the same text as 3out at volume grain; outside the sparse cone (multi-MB files, not pinned; the fetch test asserts the cone keeps them out) |
| `SII_A_raw/1orig/*` — the contractor's whole-corpus dumps | 3 | no — the same text at corpus grain (~110 MB); outside the cone, likewise asserted by the fetch test |
| READMEs, `SII_B_clean/SII17/SII_to_update.html`, `3out/*.tsv`, `2mastercopy` tooling | — | not documents |

## The files

| file | what it pins |
|---|---|
| `SII_B_clean/SII22/DHARMA_INSSIIv22p0i0252.xml` | Tiruppanaṅgāḍu, Achyutadēva-Mahārāya: a district-first findspot heading and a **Śaka-only** dating ("Śaka 1460" → 1538 through config/eras.yml) |
| `SII_B_clean/SII22/DHARMA_INSSIIv22p0i0391.xml` | Tirumayyam, Rājarāja I year 19: the editor's **"A.D. 1003-04"** conversion (the abbreviated range → [1003, 1004]) and a "PUDUKKOTTAI STATE" unit |
| `SII_B_clean/SII22/DHARMA_INSSIIv22p0i0349.xml` | Ūttukkāḍu: a **Telugu** edition (`tel-Latn`) in a Tamil-majority volume |
| `SII_B_clean/SII22/DHARMA_INSSIIv22p0i0408.xml` | a **stub with no edition div** (commentary + bibliography only) — the honest quarantine (798 such in the clean slice) |
| `SII_B_clean/SII17/DHARMA_INSSIIv17p0i0656.xml` | Śrīnivāsanallūr: the **village-first** heading shape of SII 17 ("VILLAGE, X TALUK, Y DISTRICT") |
| `SII_B_clean/SII17/DHARMA_INSSIIv17p0i0582.xml` | Tiruvārūr, Kulōttuṅga III: upstream's comma dirt in the heading (two candidate names, so no place is claimed) and the summary's reign line **"Year 8: 1184-85 A.D."** |
| `SII_B_clean/SII08/DHARMA_INSSIIv08p0i0503.xml` | Guḍimallam: SII 8's "…TEMPLE **AT** GUDIMALLAM, GUDIYATTAM TALUK, NORTH ARCOT DISTRICT" shape |
| `SII_B_clean/SII08/DHARMA_INSSIIv08p0i0391.xml` | SII 8's "…OF THE SAME TEMPLE" heading — no findspot, no place (the inherited-place inference is never made) |
| `SII_B_clean/SII17/DHARMA_INSSIIv17p0i0380.xml` | Kuḍumiyāmalai: a clean edition **without an in-file `<licence>`** — admitted on the repository statement (`license_basis`) |
| `SII_B_clean/SII04/DHARMA_INSSIIv04p0i0290-0293.xml` | a **range edition** (Nos. 290 to 293 as one document) — supersedes the raw 290…293 |
| `SII_B_clean/SII06/DHARMA_INSSIIv06p0i0004.xml` | upstream's **bare `tam`** over romanized Tamil (68 such) — aliased to `tam-Latn` |
| `SII_B_clean/SII38/DHARMA_INSSIIv38p0i0029.xml` | Chingleput: a **Dutch** epitaph (`nld-Latn`) |
| `SII_B_clean/SII17/DHARMA_INSSIIv17p0i0559.xml` | Kīvaḷūr: a **`mar-Latn`** (Marathi) record — no registry node, the loud quarantine |
| `SII_B_clean/SII22/~DHARMA_INSSIIv22p0i0584.xml` | rejected grain: an **in-progress** clean file |
| `SII_A_raw/3out/04/~DHARMA_INSSIIv04p0i0294.xml` | a **raw-only Telugu** conversion (No. 294 lies outside the clean range 290-293 — the raw text stands in) |
| `SII_A_raw/3out/04/~DHARMA_INSSIIv04p0i0290.xml` | rejected grain: a raw conversion **inside a clean range** — superseded |
| `SII_A_raw/3out/22/~DHARMA_INSSIIv22p0i0252.xml` | rejected grain: a raw conversion with an **exact clean stem** — superseded |
| `SII_A_raw/3out/10/~DHARMA_INSSIIv10p0i0697.xml` | SII 10's **"Ś. 1066"** heading abbreviation → Śaka 1066 = 1144 |
| `SII_A_raw/3out/35/~DHARMA_INSSIIv35p0i0231.xml` | Byāhaṭṭi: a raw **Kannada** conversion with a village-first heading |
| `SII_A_raw/3out/39/~DHARMA_INSSIIv39p0i0273.xml` | Srimushnam: a raw Telugu record dated **"ŚAKA 1504"** |
| `SII_A_raw/3out/41/~DHARMA_INSSIIv41p0i0058.xml` | Gingee: a **Persian** record tagged `per-Latn` (ISO 639-2/B) — aliased to `fas-Latn`; a mixed-case heading |
| `SII_A_raw/3out/25/~DHARMA_INSSIIv25p0i0241.xml` | a raw conversion **without text** (heading only) — the quarantine shape of 831 raw files |
| `SII_A_raw/3out/42/~DHARMA_INSSIIv42p0i0226.xml` | a raw conversion tagged **`und`** — the family's loud quarantine (400 raw files) |

License: the repository-wide statement in `SII_B_clean/README.txt` (added
by the DHARMA maintainer 2026-10-21: "All files in this repository are
under CC BY-SA 4.0 license"); the first-cut files and every raw file also
carry `<licence target="https://creativecommons.org/licenses/by-sa/4.0/">CC
BY-SA 4.0</licence>` in their publicationStmt. Redistributable here under
those terms; credit DHARMA (ERC grant no. 809994), the SII volume's
original editor and the digital editors named in each file's respStmt.

Recipe (re-cut): `git clone --filter=blob:none --sparse --no-checkout
https://github.com/erc-dharma/south-indian-inscriptions`, `git
sparse-checkout set --no-cone '/SII_B_clean/*/DHARMA_*.xml'
'/SII_B_clean/README.txt' '/SII_A_raw/3out/*/~DHARMA_*.xml'
'/SII_A_raw/README.txt'`, `git checkout`, and copy the files above whole
into place (or copy them from `canonical/sii-clean/` once synced; the
in-progress `~DHARMA_INSSIIv22p0i0584.xml` lies outside that cone — fetch it
by its raw URL).
