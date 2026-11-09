# dbnl fixtures

Retrieved 2026-11-08 from the DBNL public-domain download page
(https://www.dbnl.org/letterkunde/pd/index.php):

- `https://www.dbnl.org/letterkunde/pd/xml_pd.zip` — 692,154,667 B,
  Last-Modified 2026-11-04, sha256
  `d8c73f0ff1f6123979e73d3fe553b9934fac06cb7aea3f03193d48447e815747`
  (one GET; the members below are copied out of it);
- `https://www.dbnl.org/extern/titels_pd.php` — the title register
  `titels_pd.csv` (9,105 rows, 7,440 titles), sha256
  `9c9a8f203a107467c1256612c1ca6a9490c23f625f947d8bbbcb760956397e93`.

No per-title URL was fetched: dbnl.org's robots.txt is `User-Agent: * /
Disallow: /` and the terms forbid downloading large numbers of works; the
zip is the KB's own offered download.

## Delivery grains

| grain | taken? | where |
|---|---|---|
| `xml_pd.zip` — 3,654 flat members `<ti_id>_01.xml`, TEI.2 (DBNL DTD, teixlite) | **taken** — document = member file | the six `.xml` files here |
| `titels_pd.csv` — pipe-separated register, `sep=\|` first line; one row per title × person × genre | **taken** as the register (dating, printing, genre, persons) | `metadata/titels_pd.csv` |
| `txt_pd.zip` — the same titles as plain text (631 MB) | rejected, never fetched (the TEI carries the same text with its pages) | — |
| per-title pages `/tekst/<id>/`, `/nieuws/xml.php`, `/nieuws/text.php` (the register's url/text_url columns) | rejected, never fetched (robots + terms) | — |

The zip holds NO non-title member (no DTD, no images, no index), so there is
no rejected in-tree grain to pin; the fetchers' own state pins and the
register account for every other file of the landed tree (asserted in
`test/adapters/dbnl_test.rb` on a landed copy). The register lists 7,440
titles; 3,654 have a file in the zip (the register-only titles are DBNL
catalogue entries whose text is not in the dump — reported in the
register's discovery note, never skipped).

## The six titles

| file | what | why it is here |
|---|---|---|
| `_rub001rubb01_01.xml` | *Rubben*, sotternie from the Hulthem manuscript (Brussels KBR 15589-623), ca. 1400–1420; text of the INL Cd-rom Middelnederlands after Leendertz 1897 | **medieval**: folio-cited pages (`pb ed="fol."`), `sp/speaker/l` drama, the CD-rom provenance header, no langUsage → Middle Dutch by date, a text-level `interpGrp` |
| `_cor008cort01_01.xml` | *Corte verhalinghe van de beeldtstormerye*, Antwerp 1566 (first print) | **early modern**: print pages with a blank page, chapter-level `interpGrp` place/date links |
| `dous003adia01_01.xml` | Janus Dousa Filius, *Ad Ianvm Havtenvm* (1607) with De Stoppelaar's 1801 translation | the **pb-less** div fallback; langUsage `la`+`nl` |
| `_ges002gesc01_01.xml` | *De geschiedenis van een goed en van een kwaad kind*, 4th printing, Dordrecht 1840 | a **later printing** (edition class) whose header states the first print's year (1838); figures; an editorial-intervention list; two genres |
| `vaen001embl01_01.xml` | Otto Vaenius, *Emblemata aliquot selectiora amatoria*, Amsterdam 1618 — **trimmed** | signature pages (`A2r`…), the `<c type="shy">` line-end break; lines 1–95 + 264–305 of the member, closed with `</div></body></text></TEI.2>` |
| `will028lala01_01.xml` | J.F. Willems, *De la langue belgique*, Brussels 1829 — **trimmed** | langUsage `fr`, foot notes, the `<hy>` page-end break with its deferred page; lines 1–213 + 246–283 of the member, closed with `</div></div></body></text></TEI.2>` |

`metadata/titels_pd.csv` is a trim of the register: its two header lines
plus every row of the six titles and of one register-only title
(`hade002jvan01`, Hadewijch's *Visioenen* — listed, not in the zip).

Re-cut recipe: download the zip once (never per title), `unzip -p xml_pd.zip
<member>` for the whole files, and the line ranges above for the trims;
`head -2` + `grep '^"<ti_id>"'` on the register.
