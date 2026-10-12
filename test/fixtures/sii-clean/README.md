# sii-clean fixtures

Eight whole real edition files from `SII_B_clean/` of
github.com/erc-dharma/south-indian-inscriptions (branch master, HEAD
`3ea671b6c9b2b60e1834535ee16614ebdadf3195`), retrieved 2026-10-12 from a
blobless sparse clone of the repo, unmodified. Each sits under its volume
directory, mirroring the canonical layout
`canonical/sii-clean/SII_B_clean/SII<NN>/`.

| file | what it pins |
|---|---|
| `SII22/DHARMA_INSSIIv22p0i0252.xml` | Tiruppanaṅgāḍu, Achyutadēva-Mahārāya: a district-first findspot heading and a **Śaka-only** dating ("Śaka 1460" → 1538 through config/eras.yml) |
| `SII22/DHARMA_INSSIIv22p0i0391.xml` | Tirumayyam, Rājarāja I year 19: the editor's **"A.D. 1003-04"** conversion (the abbreviated range → [1003, 1004]) and a "PUDUKKOTTAI STATE" unit |
| `SII22/DHARMA_INSSIIv22p0i0349.xml` | Ūttukkāḍu: a **Telugu** edition (`tel-Latn`) in a Tamil-majority volume |
| `SII22/DHARMA_INSSIIv22p0i0408.xml` | a grant-bearing **stub with no edition div** (commentary + bibliography only) — the honest quarantine (40 such in the cone) |
| `SII17/DHARMA_INSSIIv17p0i0656.xml` | Śrīnivāsanallūr: the **village-first** heading shape of SII 17 ("VILLAGE, X TALUK, Y DISTRICT") |
| `SII17/DHARMA_INSSIIv17p0i0582.xml` | Tiruvārūr, Kulōttuṅga III: upstream's comma dirt in the heading ("TIRUVĀRŪR, NAGAPATTINAM, TALUK" — two candidate names, so no place is claimed) and the summary's reign line **"Year 8: 1184-85 A.D."** (the summary dating lane) |
| `SII08/DHARMA_INSSIIv08p0i0503.xml` | Guḍimallam: SII 8's "…TEMPLE **AT** GUDIMALLAM, GUDIYATTAM TALUK, NORTH ARCOT DISTRICT" shape |
| `SII08/DHARMA_INSSIIv08p0i0391.xml` | SII 8's "…OF THE SAME TEMPLE" heading — no findspot, no place (the inherited-place inference is never made) |

License: every file carries `<licence
target="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA
4.0</licence>` in its publicationStmt — the grant that admits it into the
source. Redistributable here under those terms; credit DHARMA (ERC grant
no. 809994), the SII volume's original editor and the digital editors named
in each file's respStmt.

Recipe (re-cut): `git clone --filter=blob:none --sparse
https://github.com/erc-dharma/south-indian-inscriptions`, `git
sparse-checkout set SII_B_clean`, and copy the eight files whole into
`test/fixtures/sii-clean/SII_B_clean/<volume>/` (or copy them from
`canonical/sii-clean/SII_B_clean/` once synced).
