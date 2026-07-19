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

## The file-set census (repo whole, 2026-07-19)

| file | rows | verdict |
|---|---|---|
| 韻書/廣韻.csv | 25,336 | **INGESTED** — the complete corrected shelf |
| 韻書/王三.csv | 17,232 | journaled — 王仁昫刊謬補缺切韻, upstream marks it 小韻內部待校 (in progress); different column set (鈴木ID/頁號/行號/切韻拼音); a future second shelf |
| 韻書/王一.csv | 2 | stub ("not completed" upstream) |
| 韻圖/韻鏡（古逸叢書本）.csv | 3,871 | rhyme-TABLE grid positions (字頭/轉號/上位/右位) — no definitions, different content kind |
| 韻圖/韻鏡（嘉吉本）.csv | 622 | ditto, "not completed" upstream |
| 反切音韻地位/廣韻反切音韻地位表.csv | 3,872 | per-小韻 fanqie analyses (beta) — derivable apparatus |
| 反切音韻地位/王三反切音韻地位表.csv | 3,656 | ditto (rev. Ayaka & unt) |

`src/` holds the build inputs (patches.csv, 字序表, 小韻表, the
2017-02-09 base dump) — build machinery, not shelf data.
