# EDRDG fixtures (P32-4 — KANJIDIC2 + JMdict)

Real upstream samples of the two EDRDG dictionary files (CLAUDE.md fixture
rules; docs/backlog.md P32-4). Both are documented TRIMS: the full XML
prolog/DTD (JMdict's internal entity definitions are load-bearing — the
parser expands them) plus a small set of verbatim elements re-wrapped in
the root tag. **Upstream builds BOTH files NIGHTLY** — the build stamps
below date exactly which night's build these bytes came from; a refresh
WILL fetch different bytes and must re-record them.

- **Retrieved:** 2026-07-19 from `http://ftp.edrdg.org/pub/Nihongo/`.
- **kanjidic2.xml.gz:** 1,488,568 B, sha256
  `158f352a27e8bd07b41492e5811188a91abff561c0715933033af07ec29c3555`,
  Last-Modified `Sun, 19 Jul 2026 03:30:36 GMT`; in-file
  `<database_version>2026-200</database_version>`,
  `<date_of_creation>2026-07-19</date_of_creation>`; 13,108 characters.
- **JMdict_e.gz:** 10,506,351 B, sha256
  `f607da95696d0f19f7d724b28034862cf9b8934c16c14e9ef4ff6a39d578b81d`,
  Last-Modified `Sun, 19 Jul 2026 03:30:23 GMT`; in-file comment
  `<!-- JMdict created: 2026-07-19 -->`; 217,951 entries.
- **License (verbatim, edrdg.org/edrdg/licence.html, read 2026-07-19):**
  "The dictionary files are made available under a Creative Commons
  Attribution-ShareAlike Licence (V4.0)." (copyright "James William BREEN
  and The Electronic Dictionary Research and Development Group"; the
  statement names JMDICT and KANJIDIC2 explicitly) → `attribution`.

## Upstream format reality (what these fixtures preserve)

- **kanjidic2.xml** — DTD + `<header>` + `<character>` elements: `literal`,
  `codepoint/cp_value` (the ucs value is the Unihan join key — verified
  quirk: **BMP values are lowercase hex (`4e9c`), plane-2 values UPPERCASE
  (`2000B`)**; the parser upcases into one key shape), `radical`, `misc`
  (grade/stroke_count/freq/jlpt), `dic_number`, `query_code`,
  `reading_meaning` with `r_type="ja_on"/"ja_kun"` readings, `nanori`, and
  `<meaning>` with non-English `m_lang` variants (skipped by the parser).
- **JMdict_e.xml** — internal DTD defines ~190 entities for pos/misc/field
  tags (`&unc;` → "unclassified"); entries carry `ent_seq` (the stable id),
  `k_ele/keb` kanji forms (absent for kana-only entries), `r_ele/reb`
  readings, `sense/pos/gloss`.

## These files

- `kanjidic2.xml` (10 characters): 一 4e00, 亜 4e9c, 亞 4e9e, 人 4eba,
  体 4f53, 天 5929, 愛 611b, 體 9ad4, 鬵 9b75 (ties to the HDIC TSJ wakun
  fixture), 𠀋 2000B (the UPPERCASE plane-2 quirk pinned in a test).
  Recipe: keep bytes up to the first `<character>`, then the 10 matching
  `<character>…</character>` blocks verbatim, then `</kanjidic2>`.
- `JMdict_e.xml` (6 entries): 1000000 ヽ (kana-only, `&unc;` entity),
  1150410 愛, 1438210 天, 1366410 人, 1318970 辞書, 1358280 食べる
  (multi-sense verb). Recipe: keep the prolog + full DOCTYPE internal
  subset verbatim, then `<JMdict>`, the upstream `<!-- JMdict created:
  2026-07-19 -->` comment (relocated from the file tail — the one
  structural liberty), the 6 `<entry>…</entry>` blocks verbatim,
  `</JMdict>`.

Both fixtures are PLAIN XML; canonical after a real fetch holds the .gz
bodies verbatim and the adapter streams them through Zlib::GzipReader —
discover accepts both shapes under the same ref ids (the mw precedent).
