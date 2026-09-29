# ja-wikisource fixtures

Real api.php captures from ja.wikisource.org, retrieved 2026-09-29
(action=query prop=revisions rvslots=main), stored in the adapter's
own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext + the fetch's "eras" provenance). One envelope per
censused page class:

- `17016.json` — 土佐日記: a `{{versions}}` edition-disambiguation
  shell (whole). The skip-by-rule class (29 in the live cone).
- `11940.json` — 万葉集/第一巻: the structured per-poem block grammar
  ([歌番号]/[題詞]/[原文]/[訓読]/[仮名]…). TRIMMED to the front matter
  + the first 3 poem blocks (40,627 → 2,295 bytes).
- `8082.json` — 方丈記 (國文大觀): a `<pages index>` ProofreadPage
  scan-transclusion shell (whole) with a real 底本 line. The declared
  residue class (78 in the live cone).
- `7285.json` — 徒然草 (校註日本文學大系): direct prose with 底本,
  ruby {{r|...}}, iteration-mark and {{smaller|〔…〕}} templates, dan
  numbers. TRIMMED to the header + the first two dan (101,091 → 3,456
  bytes, cut at a paragraph boundary).

Re-cut: fetch each title's current revision via api.php and re-apply
the stated trims; "eras" comes from the era-category walk (平安時代
for 土佐日記, 奈良時代 for 万葉集, 鎌倉時代 for 方丈記,
鎌倉時代+南北朝時代 for 徒然草).
