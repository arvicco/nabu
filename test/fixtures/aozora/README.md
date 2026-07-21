# Aozora Bunko fixtures

Real upstream samples, retrieved 2026-07-21 from the aozorabunko
GitHub mirror (raw.githubusercontent.com/aozorabunko/aozorabunko/master/)
and www.aozora.gr.jp. Layout mirrors the upstream sparse-checkout shape
(cards/<authorID>/files/ + index_pages/).

- `cards/001257/files/56078_ruby_51155.zip` — 驛傳馬車 (Irving,
  "The Stage Coach", trans. Takagaki Matsuo). PD, 旧字旧仮名
  (old kanji / historical kana), 13.5 KB text inside; carries 4 gaiji
  notations. Zip kept whole (upstream stores text as single-txt zips;
  the adapter unzips on read — fixtures exercise that path).
- `cards/001257/files/59898_ruby_70679.zip` — ウェストミンスター寺院
  (Irving, "Westminster Abbey", trans. Yoshida Kōji). PD, 新字新仮名,
  ruby-dense.
- `index_pages/list_person_all_extended_utf8.csv` — the 55-column
  index trimmed to the header + all person-work rows for three works:
  056078 and 059898 (作品著作権フラグ=なし, PD → discovered) and
  054333 (=あり, in-copyright → must be SKIPPED by discovery; its zip
  is deliberately NOT in fixtures — in-copyright text is not
  redistributable, and discovery must exclude it before ever touching
  the file).

Upstream stores the index zipped (list_person_all_extended_utf8.zip);
the fixture keeps the inner CSV directly — the adapter reads the CSV
(unzip-on-read applies to work zips; index handling per adapter).
