# mnc-wikisource fixtures

Thirteen real Multilingual Wikisource pages (https://wikisource.org),
retrieved 2026-11-08 through api.php (`prop=revisions&rvprop=content|ids|
timestamp&rvslots=main`, paced 1.5 s) and written as the adapter's fetch
writes them: `pages/<pageid>.json` = {title, pageid, ns, revid, timestamp,
categories, wikitext}, the wikitext byte-verbatim and WHOLE (no trims).
The texts are public domain; the transcription layer is CC BY-SA
(wikisource.org footer).

Delivery grains: the category member (any namespace) is the unit upstream
serves; the adapter takes ONE main-namespace page as a document and
rejects the rest by rule. Every rejected class is pinned:

| pageid | title | revid | class |
|---|---|---|---|
| 168826 | ᠨᡳᠪᠴᡠ ᠊ᡳ ᠪᠣᠵᡳ ᠪᡳᡨ᠌ᡥᡝ (Treaty of Nerchinsk) | 1338622 | admitted — script + romanization, External link section |
| 84446 | ᠯᡳᠩ ᡷᡳ ᡳ ᠵᡠᡤᡡᠨ᠈ ᡨᡠᡤᡳ ᡳ ᡩᠠᠯᠠᠨ (a Kangxi poem) | 793701 | admitted — header + <poem> |
| 64127 | Manchu/The Analects/lunyu1 | 238375 | admitted — table, Manchu/Chinese cells (lzh) |
| 152894 | ᠴᡳᠩ ᠸᡝᠨ ᡴᡳ ᠮᡝᠩ ᠪᡳᡨ᠌ᡥᡝ/ᡠᠵᡠᡳ ᡩᡝᠪᡨᡝᠯᡳᠨ (清文啓蒙 juan 1) | 494236 | admitted — zho glosses |
| 153207 | Sun Dzi i Coohai Doro | 495036 | admitted — editorial lines before "(263)" drop |
| 64132 | 清語老乞大卷一 | 771518 | admitted — modern Chinese "Translation" section drops |
| 260168 | ᠮᠠᠨᠵᡠ ᡳ ᠶᠠᡵᡤᡳᠶᠠᠨ ᡴᠣᠣᠯᡳ/ᠵᠠᡳ ᡩᡝᠪᡨᡝᠯᡳᠨ (MYK juan 2) | 845089 | admitted — one 30k-character paragraph, sentence split |
| 64129 | Usiha be toloro jui | 238377 | modern |
| 152815 | ᠮᠠᠨᠵᡠ ᡳ ᠶᠠᡵᡤᡳᠶᠠᠨ ᡴᠣᠣᠯᡳ (MYK main page) | 520485 | landing |
| 64134 | Sanzijing | 238383 | unattested |
| 159228 | ᡞᠯᠠᠨ ᡤᡠᠷᡠᠨ ᡞ ᡪᡠᠯᡝᠨ/1 | 788532 | out-of-lect (lang=sjo) |
| 325868 | Page:Chrestomathie mandchou … (IA chrestomathieman00klap).pdf/261 | 977143 | other-namespace (ns 104) |
| 64120 | Wikisource:Main Page/Manchu | 1353858 | other-namespace (ns 4), in two categories |

Reconciliation (the whole census, 2026-11-08): 34 main-namespace member
pages = 21 admitted + 13 rejected by rule (6 landing, 4 modern, 2
unattested, 1 out-of-lect); plus the non-main-namespace members, skipped
by rule. The census tables are `MncWikisource::WORKS` / `REJECTED`.

Re-cut: `action=query&prop=revisions&rvprop=content|ids|timestamp&rvslots=main&titles=<title>`
on https://wikisource.org/w/api.php, enveloped as above.
