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
- `12868.json` — 万葉集/第三巻: TRIMMED to the front matter + the
  03/0235 / 03/0235S variant pair (the 或本歌 whose letter-suffixed
  歌番号 collided URNs at the live first sync when stripped).
- `46951.json` — 北条五代記/巻第二: a dispatcher shell
  (`{{:北条五代記/巻第一|巻=二|…}}` — the text renders from another
  page's template machinery). Shell wikitext whole; since P111-2 it
  carries the real `action=expandtemplates` payload under "expanded"
  (fetched 2026-09-30), TRIMMED 216,075 → 8,795 chars at a sentence
  boundary inside section 一 — nav divs, TOC self-links, volume list,
  inputbox and HTML ruby all inside the trim, so the furniture strip
  is tested against reality.
- `8082.json` — 方丈記 (國文大觀): a `<pages index>` ProofreadPage
  scan-transclusion shell with a real 底本 line. Shell wikitext
  whole; since P111-2 it carries 2 of its 14 Page:-namespace
  wikitexts under "pages" (Page:Kokubun taikan 09 part2.djvu/43-44,
  each whole, fetched 2026-09-30 — page 44 starts mid-sentence, the
  cross-page join case; page 43 carries a `{{*|やけイ}}` marginal
  apparatus note).
- `48325.json` — 東照宮御実紀附録/巻十九 (whole, from the box's own
  canonical envelope): a dispatcher shell with deliberately NO
  expansion payload — the payload-less skip-by-rule class (stale
  trees, empty expansions).
- `7285.json` — 徒然草 (校註日本文學大系): direct prose with 底本,
  ruby {{r|...}}, iteration-mark and {{smaller|〔…〕}} templates, dan
  numbers. TRIMMED to the header + the first two dan (101,091 → 3,456
  bytes, cut at a paragraph boundary).

Re-cut: fetch each title's current revision via api.php and re-apply
the stated trims; "eras" comes from the era-category walk (平安時代
for 土佐日記, 奈良時代 for 万葉集, 鎌倉時代 for 方丈記,
鎌倉時代+南北朝時代 for 徒然草).
