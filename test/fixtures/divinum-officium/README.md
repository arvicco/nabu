# divinum-officium fixtures — the Tridentine Latin Office and Mass

Real files from `github.com/DivinumOfficium/divinum-officium`, retrieved
**2026-11-04** at master `85183a9b1161f4242c9199177b5d6c9dd16be620`
(2026-11-04). The fixture mirrors upstream's own tree (`web/www/...`), so
the adapter's discovery walks it exactly as it walks a sparse checkout.
Raw URL of any file = `https://raw.githubusercontent.com/DivinumOfficium/divinum-officium/<sha>/<path>`.

## License (verbatim, first-hand)

`LICENSE` (repo root, fixture copy whole):

> MIT License
>
> Copyright (c) 2026 Divinum Officium

`web/www/horas/Help/credits.html` (fixture copy whole), the Disclaimer
paragraph:

> The code and data are freely available to anyone at the Divinum Officium
> GitHub repository, and licensed under the MIT License. All liturgical
> texts within this site are, to the best of our knowledge, from the public
> domain. No special permission is needed to utilize any of our content.

→ class **open** for the Latin trees. The same page's Vernaculars credits
document the translations as taken with permission from modern editions
and sites (the Martyrology "adapted with the permission of the owner";
Polski-Newer "used by permission of the copyright holder"), with sources
undocumented ("Laszlo left behind no documentation of his sources of the
Sancta Missa English translation"), and, of the Bute English breviary scans,
"The same collection also has a set of the same books without the quoted
permission and apparently copyrighted." → the vernacular trees are
excluded (LATIN ONLY).

## Upstream's delivery grains (census of the whole tree at 85183a9b)

The repo holds 40,432 files; the data live under `web/www/horas/` (the
Office) and `web/www/missa/` (the Mass), one directory per language.

| grain | files | verdict |
|---|---|---|
| `web/www/horas/Latin/**` | 3,962 (3,961 `.txt` + 1 extensionless) | **ACCEPTED** — one document per `.txt` with own text |
| `web/www/missa/Latin/**` | 1,063 `.txt` | **ACCEPTED** — likewise |
| … of which inclusion stubs (no own text: a whole-file `@…` inheritance, or every section an @-reference / Rank / Rule / Name data) | 1,021 | **skipped by rule** (specimens `horas/Latin/CommuneCist/C10c.txt`, `horas/Latin/SanctiM/08-18bmv.txt`) |
| `horas/Latin/Sancti/aliquibus locis/09-04-BMVDivPastMatr` | 1 (1 byte, a newline — the stray twin of its `.txt`) | **skipped by rule** (specimen pinned whole) |
| vernacular trees — horas: Bohemice 1,657 · Cesky-Schaller 33 · Dansk 219 · Deutsch 1,055 · English 2,010 · Espanol 1,804 · Francais 1,651 · Hebrew 220 · Italiano 1,832 · Magyar 1,252 · Magyar-Kaldi 196 · Nederlands 847 · Polski 2,063 · Polski-Newer 152 · Portugues 1,095 · Ukrainian 26 · Vietnamice 225; missa: Bohemice 247 · Cesky-Schaller 218 · Dansk 22 · Deutsch 557 · English 951 · Espanol 1,057 · Francais 957 · Italiano 943 · Magyar 901 · Nederlands 979 · Polski 707 · Portugues 567 · Ukrainian 112 · Vietnamice 7 | 24,562 (16,337 + 8,225) | **REJECTED** (LATIN ONLY — see License); outside the sparse cone; specimen `horas/English/Sancti/01-21.txt` |
| `horas/Latin-gabc/**` — Gregorian chant scores in gabc notation | 4,809 | **REJECTED** (a notation grain); outside the cone; specimen `horas/Latin-gabc/Sancti/01-21.txt` |
| `horas/Latin-Bea/**` — the Pius XII (Bea, 1945) psalter | 170 | **REJECTED** (a modern authored Latin translation; held for a ruling); outside the cone; specimen `horas/Latin-Bea/Psalterium/Psalmorum/Psalm123.txt` |
| `horas/Ordinarium/*.txt` — the hour-assembly templates | 6 | **REJECTED** (program scripts: `#Psalmi`, `$Pater noster`, conditionals); outside the cone; specimen `horas/Ordinarium/Prima.txt` |
| `horas/Help/**` — the site's help/credits pages | 108 | **REJECTED**; only `credits.html` rides the cone (the license evidence) and counts as skipped by rule |
| top-level site files of `horas/` (14) and `missa/` (13) — `.setup`/`.dialog`, `ruler.txt`, `sundaytable.txt`, `Linguae.txt`, images | 27 | **REJECTED**; outside the cone; specimen `missa/Linguae.txt` |
| everything else (`web/cgi-bin` Perl, `standalone/`, `t/`, docker, css/js) | — | code, never fetched |

**Reconciliation.** Upstream advertises no count; the tree is the claim.
5,025 Latin-tree files = **4,003 accepted + 1,021 stubs + 1 stray**. A full
parse of the two Latin trees at 85183a9b with the shipped adapter: **4,003
documents / 26,381 passages / 0 errored**. A live sparse checkout therefore
reports 1,023 skipped by rule (+ credits.html), 0 unrecognized.

## Files

| fixture | whole? | exercises |
|---|---|---|
| `web/www/horas/Latin/Sancti/01-21.txt` | whole | St Agnes, the Office: 21 passages; [Officium] title; [Rank] variants with `(sed rubrica …)` lines; [Rule]; reference-only sections (`@:Ant Laudes`, `@Commune/C6::s/N\./Agnes/`); `$Per Dominum`, `&Gloria`, `&teDeum` calls; `!Liber 1, post initium` rubric |
| `web/www/missa/Latin/Sancti/01-21.txt` | whole | St Agnes, the Mass: 4 passages; seven sections pure `@Commune` references; `!Ps 44:3` citations |
| `web/www/horas/Latin/SanctiM/09-17M.txt` | whole | the Monastic use; a conditional inside [Officium]; the header condition `[Ant 2] (nisi rubrica cisterciensis)` |
| `web/www/horas/Latin/Sancti/Bavaria/Passaviensis/05-04-Florianus.txt` | whole | a Passau diocesan proper → place; the [Name] section (machine data) |
| `web/www/horas/Latin/Sancti/Brasilia/06-13.txt` | whole | a Brazilian proper; one of upstream's four CRLF files |
| `web/www/horas/Latin/Commune/C10a.txt` | whole | the whole-file inheritance `@Commune/C10`; a repeated `[Oratio] (ad missam)` |
| `web/www/horas/Latin/Psalterium/Psalmorum/Psalm1.txt` | whole | the psalter's verse layout (`1:3a` …) |
| `web/www/horas/Latin/Necrologium/Januarius.txt` | TRIM — upstream lines 1–32 of 370 (days 1–2), byte-verbatim | the necrology's day layout and its `Anno 1746` entry years |
| `web/www/missa/Latin/Ordo/Ordo.txt` | TRIM — upstream lines 1–73 of 415 (the `&Vidiaquam` preamble, `# Incipit`, `# Incensatio`, `# Introitus`), byte-verbatim | the header-less `#Heading` layout; `!*D` display directives; a capitalized `(Osculatur Altare in medio)` that is text |
| `web/www/horas/Latin/CommuneCist/C10c.txt` | whole | an inclusion stub (one line, `@CommuneCist/C10`) → skipped by rule |
| `web/www/horas/Latin/SanctiM/08-18bmv.txt` | whole | a stub whose sections are @-references between bare `;;` antiphon slots → skipped by rule |
| `web/www/horas/Latin/Sancti/aliquibus locis/09-04-BMVDivPastMatr` | whole (1 byte) | the extensionless stray → skipped by rule |
| `web/www/horas/English/Sancti/01-21.txt` | TRIM — lines 1–10 of 114 ([Officium], [Ant 1], [Oratio]) | the rejected vernacular grain |
| `web/www/horas/Latin-gabc/Sancti/01-21.txt` | TRIM — lines 1–7 of 94 ([Ant 1], [Oratio]) | the rejected chant-notation grain |
| `web/www/horas/Latin-Bea/Psalterium/Psalmorum/Psalm123.txt` | whole | the rejected Bea-psalter grain |
| `web/www/horas/Ordinarium/Prima.txt` | whole | the rejected template grain |
| `web/www/horas/Help/credits.html` | whole | the license evidence; skipped by rule as a help page |
| `web/www/missa/Linguae.txt` | whole | a rejected top-level site file |
| `LICENSE` | whole | the repo's MIT notice (upstream's root `README.md` rides the live cone too — "The files are UTF-8-encoded text files … arranged into sections, with each section beginning with its name enclosed in square brackets" — but is not pinned here: this file holds its place) |

Source shas (sha256 of the whole upstream files, before any trim):

```
8072920c22d6fccbe3dd825192732434f40fb78e4f9f6bbe2f224fac5ce0cfae  LICENSE
eeb5667a0e79b1d846f4332258d7ccb3a8fdcf58bf3f5310a14980e6390c5216  web/www/horas/English/Sancti/01-21.txt
aa42c457f390f68941ac3ba6c449bae4f29b324003de3234127ff6b53339c6ea  web/www/horas/Help/credits.html
b7e646bfcc60e7787d81dd1bd1ff9d31f8ac2ad2b2fe1ea6bae80a31b54c7fd0  web/www/horas/Latin-Bea/Psalterium/Psalmorum/Psalm123.txt
8b02efcdd240ac0a38996bff26065b1b5e2e9fdd4b1a8c11b4741530615b7b67  web/www/horas/Latin-gabc/Sancti/01-21.txt
df13f105a1f5a6be6a56885a6013d41577c4eda8e21970e92a4b75726336af2c  web/www/horas/Latin/Commune/C10a.txt
7d631882ec7287f1f145fd25e15b7639077e6348feaf64742421a79e54fe981b  web/www/horas/Latin/CommuneCist/C10c.txt
5054507e324807c157d48594513b548caea303cce333f32b50f70b5b4ed3f765  web/www/horas/Latin/Necrologium/Januarius.txt
9f59ff9e4a5c39e8e8d9b8b24a8ffff6fba69f203115fd05fa236ec206cc3613  web/www/horas/Latin/Psalterium/Psalmorum/Psalm1.txt
d6ea0543a7463ad3a8b42af9f3e1b6dd45ed7d83ea6768475aefe1208f2715bf  web/www/horas/Latin/Sancti/01-21.txt
8226504493e9fc2d9926076a72fc2a6b9d9262480d6a642445fb6344d8acda3a  web/www/horas/Latin/Sancti/Bavaria/Passaviensis/05-04-Florianus.txt
c855b3f37ff7473dc836782f06cb328c262d870958cb2a42311755ffd7c72fa1  web/www/horas/Latin/Sancti/Brasilia/06-13.txt
01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b  web/www/horas/Latin/Sancti/aliquibus locis/09-04-BMVDivPastMatr
890e893f23ff91d9aecf0bc19a9e1ab9bad895fc27192902e499d542d073b8f9  web/www/horas/Latin/SanctiM/08-18bmv.txt
9783445161f60cc5568a8e81c8027ebe38b48c228ccc3e01d00596a1eeef71cc  web/www/horas/Latin/SanctiM/09-17M.txt
5ea2c8d743d6b15b5a97a73607e56c57df5e38a1c80469c82945084df1e79931  web/www/horas/Ordinarium/Prima.txt
9260da0d4017301f802d36d4185c1bef7b72c138ef5f2e05a4d6100c538bd15a  web/www/missa/Latin/Ordo/Ordo.txt
4d6ad8e1947b9fb4e25887f21b8c5b23e0cf21d0cdfac2daa9a27075740ae93e  web/www/missa/Latin/Sancti/01-21.txt
3d4105206a4cc90cd6edbaaa5fe3cb1d53999c535c0bbefee927d63dd824f2aa  web/www/missa/Linguae.txt
```
