# shiratori-shm fixtures

`books/1184344.json` — the NDL Lab Bulk Download API (JSON) answer for
PID 1184344 (白鳥庫吉, 音訳蒙文元朝秘史, 東洋文庫叢刊 第8, Tokyo:
東洋文庫 1943), from
https://lab.ndl.go.jp/dl/api/book/fulltext-json/1184344, retrieved
2026-11-08 (whole answer: 16,009,267 B, sha256
90224d059d37da96d41a0043edcbe1245bb9fded89e500e80dff5c68be481695; 636
koma). Public domain (Shiratori †1942).

Delivery grains upstream serves, and which this adapter takes:

- the BOOK (one JSON per PID: `list`, `hit`, `from`) — the document;
- the KOMA (one `list` entry per scan frame: `page`, `contents`, frame
  geometry) — the passage;
- the LINE (`coordjson`: one `contenttext` + bbox per OCR line inside a
  koma) — NOT taken: layout, the same text as the koma's `contents`.
  Every kept koma below carries its `coordjson` verbatim as the specimen.

Rejected koma, pinned here and asserted skipped by rule: koma 1 (the
Kodak colour/grey-scale calibration frame) and koma 2 (a letterless
koma — a bare page number). Reconciliation over the whole answer
(through the adapter, 2026-11-08): 636 koma = 632 passages + 2 skipped
by rule + 2 with empty contents.

TRIMMED to nine koma, each entry verbatim, the `hit`/`from` envelope
kept, re-serialized as compact JSON: 1 (calibration), 2 (letterless), 3
(the title leaf, jpn), 4 (the Japanese preface, jpn), 11 (Ye Dehui's
preface, lzh), 17–18 (the first interlinear openings, xng), 153 (a Ming
總譯 opening inside the body, zho), 636 (the English title leaf, eng).

Re-cut: fetch the URL above and keep the `list` entries whose `page` is
in [1, 2, 3, 4, 11, 17, 18, 153, 636].
