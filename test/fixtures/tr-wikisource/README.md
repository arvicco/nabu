# tr-wikisource fixtures

Four real Turkish Wikisource pages (https://tr.wikisource.org), retrieved
2026-11-27 through api.php (`prop=revisions|categories&rvprop=content|ids|
timestamp&rvslots=main`, paced ≥ 1 s) and written as the adapter's fetch
writes them: `pages/<pageid>.json` = {title, pageid, ns, revid, timestamp,
categories, wikitext}, the wikitext byte-verbatim except where TRIMMED
below (whole lines cut, never edited; every kept table still opens with its
caption and header row and closes with `|}`). The texts are 8th-century
inscriptions, public domain; the wiki layer is CC BY-SA (tr.wikisource.org
footer).

## Delivery grains

Upstream serves, for this corpus: the category member page (Kategori:Orhun
Abideleri — 3 members, all main namespace, one inscription each), the
landing/disambiguation page "Orhun Yazıtları" (fetched by title — not a
member), and redirects ("Orhun Abideleri (Kül Tigin)" etc. → the member
pages; never members, never fetched). The adapter takes ONE member page as
a document and ONE table row (one inscribed line) as a passage; the landing
page is rejected by rule and pinned here.

| pageid | title | revid | live bytes | kept | class |
|---|---|---|---|---|---|
| 5093 | Orhun Yazıtları (Kül Tigin) | 174981 | 99,515 | header; south face rows G1–G2 of 13; the whole north-east face (KD1, the date line); the Dış bağlantılar heading with the Ata 2011 and Tekin 1995 {{Kaynak}} entries; the category line | admitted |
| 5095 | Orhun Yazıtları (Bilge Kağan) | 174979 | 108,320 | header; west face rows B7–B9 of 9 (B8/B9 lost in every column — the lacuna fallback); the whole south-west face (GB1); the apparatus link; the category line | admitted |
| 5096 | Orhun Yazıtları (Tonyukuk) | 175665 | 53,720 | header; stone 1 west face rows 1-B1–1-B2 of 7; stone 2 west face row 2-B1 of 9; the apparatus link; the category line | admitted |
| 5338 | Orhun Yazıtları | 102344 | 153 | whole | landing (disambiguation) |

Reconciliation (the whole census, 2026-11-27): 3 category members = 3
admitted; 1 landing page skipped by rule; every face's row count equals
the line count its caption declares ("13 dizi") — 70 + 82 + 62 = 214
lines. The census table is `TrWikisource::WORKS` / `REJECTED`.

Real runiform bytes pinned by the tests: Kül Tigin G1 opens
U+10C45 U+10C2D U+10C3C U+10C03 (𐱅𐰭𐰼𐰃, "teŋri").

Re-cut: `action=query&prop=revisions|categories&rvprop=content|ids|timestamp&rvslots=main&titles=<title>`
on https://tr.wikisource.org/w/api.php (User-Agent identifying the
client), enveloped as above, then the line cuts listed in the table.
