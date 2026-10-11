# eltec-srp fixtures

Real upstream samples from **ELTeC-srp** (github.com/COST-ELTeC/ELTeC-srp,
master @ 355cea8f2e9f47e16b207d8fae1a6a22409231a4, retrieved 2026-10-11),
laid out as the repository lays them out (`level1/<file>.xml`).

Each file is a TRIMMED real level-1 file: the `teiHeader` and `front` are
verbatim; the body keeps its first top-level divs (groups keep their first
chapters) and each chapter its first block children (plus, for Ђурађ
Бранковић, every paragraph carrying a note anchor); back notes are kept
only when a kept `<ref>` targets them. Nothing is hand-written.

| File | Why |
|---|---|
| `SRP18520_BogobojA_DvaIdola.xml` | 1852; verse `<l>` inside `<quote>`, a 1893 print's title page (furniture), `<pb>` page tracking |
| `SRP18590_JakovI_DjuradjB.xml` | 1859; book `group` divs nesting chapters, modern editor notes ("Прим. прир.") in `back`, a 1987 Матица српска print source |
| `SRP19180_MilicaJ_PreSrece.xml` | 1918; `xml:lang="sr-Latn"` (one of the two Latin-script texts), a body-level `<head>` |
| `SRP19190_IsidoraS_Djakon.xml` | 1919; author Исидора Секулић (1877-1958) — excluded by the life+70 rule |

License: texts public domain; markup CC BY 4.0 (the repository README's
"Licence" section).
