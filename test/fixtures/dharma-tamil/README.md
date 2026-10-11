# dharma-tamil fixtures

Four whole real edition files from four of the DHARMA Task Force A
repos (github.com/erc-dharma/tfa-*-epigraphy, branch master), retrieved
2026-10-11 from the repo archives
(`https://codeload.github.com/erc-dharma/<repo>/tar.gz/master`),
unmodified. Each sits under its repo's directory name, mirroring the
canonical layout `canonical/dharma-tamil/<repo>/`.

| file | upstream HEAD at retrieval | what it pins |
|---|---|---|
| `tfa-sii-epigraphy/DHARMA_INStfaSIIv06p0i0012.xml` | `dfa95be6729f162c0e7b70eea15c51da94520ff4` | Centalai, Sundareśvara temple (SII 6, no. 12): **no `<licence>`** (the repo-level CC BY 4.0 fallback) and the edition tagged bare **`tam`** over romanized text (the alias); prose at line grain, a `<p>` without its own `<lb>` continuing the line |
| `tfa-tamil-outside-TN-epigraphy/DHARMA_INSTamilOutsideTN90002.xml` | `b2f53ec25e405c27a194b2887d238db20799924e` | Saint-Paul de la Réunion, temple of Subrahmaṇya: **CC BY-SA 4.0** in-file, **multilingual** — a French slab (`fra-Latn`, 1888) beside a Tamil one, textparts A/B with no lang on the edition div |
| `tfa-tiruvavatuturai-epigraphy/DHARMA_INSTiruvavatuturai00018.xml` | `5bb2e9f1bb19d59e817c4797d5ab3e7dea0141ee` | Peruṅkāṭṭu grant, Śaka year 1589: **verse** (one anuṣṭubh `lg`/`l` in Sanskrit inside a Tamil prose plate, `met` riding annotations), Telugu lines (`tel-Latn`), pb/lb folio-line numbering |
| `tfa-tamilnadu-epigraphy/DHARMA_INSTamilNadu01015.xml` | `ab94f9e525e2ce21938e63ac93fd80aa78a4e423` | Tirukkaḷar plate, time of Rājādhirāja, year 31: **no `xml:lang` anywhere** in the edition — the honest quarantine (one of two such files in the corpus) |

License: the first file carries no in-file grant; it is covered by its
repo's `LICENCE.txt` (Creative Commons Attribution 4.0 International).
The other three carry `<licence
target="https://creativecommons.org/licenses/by-sa/4.0/">CC BY-SA
4.0</licence>`. Redistributable here under those terms; credit DHARMA
(ERC grant no. 809994) and the editors named in each file's respStmt.

Recipe (re-cut): fetch each repo archive as above (or copy from
`canonical/dharma-tamil/<repo>/` once synced) and copy the four files
whole into `test/fixtures/dharma-tamil/<repo>/`.
