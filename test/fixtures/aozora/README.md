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

## P38-i1 incident regressions (added 2026-07-21, copied from the owner's
## live canonical — the encoding-fix rule: offending bytes ride as fixtures)

- `cards/000608/files/51135_ruby_65180.zip` — 検疫と荷物検査 (Sugimura
  Sojinkan). PD, 新字旧仮名, ruby-dense (332 readings over 9 paragraphs).
  REAL, WHOLE. Its single zip member is named
  `ken\xFCfekito_nimotsu_kensa.txt` — byte 0xFC is invalid in UTF-8 AND
  CP932. This crashed the owner's first live sync (ArgumentError from an
  encoding-aware split over the `unzip -Z1` listing, aborting the whole
  run at ~9,471 of ~17.5k docs). Member names are junk-bytes-in-the-wild:
  the parser handles listings as BINARY and never decodes names; this
  work must PARSE successfully. Its index row (051135, PD) is appended to
  the fixture CSV verbatim from the live index (quoted-CSV form; the CRLF
  terminator normalized to the trim's LF).
- `cards/001562/files/56151_ruby_60063.zip` — the first 4,096 bytes of
  upstream's genuinely corrupt 549 KB zip ("End-of-central-directory
  signature not found" — the FULL file is corrupt too; the trim keeps the
  fixture small while staying not-a-zip, which is the point). Must
  QUARANTINE with ParseError, never abort the sync. NO index row: the
  live index has moved to 56151_ruby_70005.zip (upstream re-proof), so
  this zip doubles as the real stranded-zip exemplar for the unrecognized
  discovery census.
