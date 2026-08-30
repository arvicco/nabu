# tshet-uinh fixtures (P32-3 — the Middle Chinese rhyme-dictionary shelf)

Real upstream rows from **nk2028/tshet-uinh-data** `韻書/廣韻.csv` — the
critical edition of the 廣韻 (Kuangx Yonh, 1008; 澤存堂本 base text with
corrections from 廣韻校本, 廣韻形聲考 etc.). Every kept line is
**byte-verbatim** upstream data (header + 12 selected rows); only the row
SET was trimmed.

- **Retrieved:** 2026-07-19 from `main` (repo last pushed 2025-11-17):
  `https://raw.githubusercontent.com/nk2028/tshet-uinh-data/main/韻書/廣韻.csv`
  — 1,640,287 B, 25,337 lines (header + 25,336 rows; no embedded
  newlines — physical lines = CSV rows), 3,884 小韻 homophone groups /
  3,801 distinct 音韻地位 formulas → **header + 12 fixture rows**.
- **License (verified IN-REPO, not just the GitHub field):** `LICENSE` at
  the repo root is the full **CC0 1.0 Universal** legal code ("Creative
  Commons Legal Code / CC0 1.0 Universal …"). The GitHub license field
  agrees. → `open`.
- **Selection (小韻號.小韻字號 → what it pins):** `1.1` 東 (the long-釋義
  opening entry), `1.2` 菄 (釋義參照 上), `2.43` 𪔝〈𪔜〉 (校訛字), `133.1`
  厜 (反切 with 〘規〙 position-source mark), `157.1` 尸 (反切 with 〖脂〗
  near-substitution), `318.9` ｛𪈥｝ (應刪字 + 字頭說明 "澤存堂本衍字" +
  參照 下), `961.1` 興 + `961.1a1` ［嬹］ (應補字 with the "a1" 字號
  suffix), `1692a.1` 鷕 (suffixed 小韻號 + compound 反切 annotation
  以沼｟小｠〈水〉), `1919.1` 拯 + `1919.2` 抍 (the 反切-less 直音 小韻;
  1919.2 additionally pins the empty-釋義 → nil-gloss case), `3067.1` 豆
  (反切 with ［徒］ 脫字 restoration).

## The 校本 correction-annotation syntax (upstream README, verbatim)

The repo documents its inline apparatus — the adapter parses it HONESTLY
(corrections as annotations, never silent fixes; raw cells survive as
`key_raw`):

- 反切 annotations: 脫字 `［徒］候`, 訛字 `士〈七〉演`, 異體字正則化
  `袪狶（豨）`, 改用其他來源的音韻地位 `姊宜〘規〙`, 替換成近似等價字
  `符咸〖䒦〗`, 替換成音近字 `式之〖脂〗`, 替換成同音字 `甫｟府｠妄` /
  `呼東｟紅｠`, 複合使用 `以沼｟小｠〈水〉` — these ride VERBATIM in bodies.
- 字頭 annotations: 應補字 `［嬹］`, 應刪字 `｛𪈥｝`, 校訛字 `汦〈泜〉` —
  the adapter names the 校本 verdict as headword and keeps the transmitted
  state in an annotation line (censused on the full file: 260 annotated
  字頭 — 252 校訛字, 6 應刪字, 2 應補字; all match the three shapes;
  406 annotated 反切 cells; 3 IDS-sequence headwords ⿱𱡘正/⿰隺犬/⿱芖雨
  kept whole; 6 直音 rows; 53 suffixed 小韻號; 2 suffixed 小韻字號;
  99 empty-釋義 rows, all with a 參照 pointer; 0 non-NFC rows).

## 韻書/王三.csv — the 王三 second shelf (P88-R4, 2026-08-29)

Byte-verbatim trim of `韻書/王三.csv` — 王仁昫《刊謬補缺切韻》 (~706), the
fullest surviving Qieyun recension; upstream marks it 小韻內部待校
(in-rhyme ordering under collation) — rows parse verbatim regardless.

- **Retrieved:** with the same clone (repo last pushed 2025-11-17):
  `https://raw.githubusercontent.com/nk2028/tshet-uinh-data/main/韻書/王三.csv`
  — 1,566,059 B, 17,233 lines (header + 17,232 rows, no quoting, no
  embedded newlines) → **header + 11 fixture rows** (full-file lines
  1–6, 118, 266, 993, 2160, 3387, 5062; recipe:
  `sed -n '1p;2p;3p;4p;5p;6p;118p;266p;993p;2160p;3387p;5062p'`).
- **The column set is NOT the 廣韻 shape** (censused from bytes
  2026-08-29): 小韻號,鈴木ID,鈴木小韻號,頁號,行號,字號,韻目原貌,首字,反切,
  地位,切韻拼音,小韻內字序,字頭,釋義 — no 直音/字頭說明/釋義參照; 地位
  plays 音韻地位's role. entry_id = **小韻號.小韻內字序**, the ONLY unique
  pair (17,232 distinct; 小韻號.字號 collides at 16,126). 字頭 census:
  143 應補字 ［X］ (".1" ordinal suffix — the a1 analogue), ONE 校訛字
  箈〈𥮒〉, ZERO 應刪字, 6 empty ［］ slots (verbatim), 3 undocumented
  【X】 rows (verbatim), 5 headword-LESS rows (待校 slots → censused
  SKIP; expect 17,227 entries), 10 empty 反切, 10 empty 釋義.
- **Selection (小韻號.小韻內字序 → what it pins):** `1.1` 東 (plain head
  entry: 地位/切韻拼音/首字/locus lines; 釋義 writes 徳, not 德), `1.2` 凍
  + `2.1`–`2.3` 同/童/僮 (plain rows), `23.7.1` ［𩦺］ (應補字 with the
  ".1" suffix), line 266 (45.9 — headword-less 待校 slot, asserted
  SKIPPED), `164.6.1` ［］ (empty supplied slot, verbatim), `312.1` 絓
  (反切-less; 釋義 with ［。］ bracket), `539.3` 箈〈𥮒〉 (the one 校訛字;
  釋義 carries ［亦作］⿱竹㵶〈𥷰〉 verbatim), `804.2` 【佯】 (undocumented
  【】 shape + empty 釋義 → nil gloss).

## The file-set census (repo whole, 2026-07-19)

| file | rows | verdict |
|---|---|---|
| 韻書/廣韻.csv | 25,336 | **INGESTED** — the complete corrected shelf |
| 韻書/王三.csv | 17,232 | **INGESTED P88-R4** — the `wangsan` second shelf (section below); upstream still marks it 小韻內部待校 |
| 韻書/王一.csv | 2 | stub ("not completed" upstream) |
| 韻圖/韻鏡（古逸叢書本）.csv | 3,871 | rhyme-TABLE grid positions (字頭/轉號/上位/右位) — no definitions, different content kind |
| 韻圖/韻鏡（嘉吉本）.csv | 622 | ditto, "not completed" upstream |
| 反切音韻地位/廣韻反切音韻地位表.csv | 3,872 | per-小韻 fanqie analyses (beta) — derivable apparatus |
| 反切音韻地位/王三反切音韻地位表.csv | 3,656 | ditto (rev. Ayaka & unt) |

`src/` holds the build inputs (patches.csv, 字序表, 小韻表, the
2017-02-09 base dump) — build machinery, not shelf data.
