# kanjidic2 fixture (P38-r1)

`kanjidic2-sample.xml` — a trimmed, structurally intact slice of EDRDG's
KANJIDIC2, hand-selected to exercise every branch of `Nabu::Ops::JpnFoldBuilder`'s
lane-2 (jōyō-filtered variant) derivation. Every `<character>` block is
BYTE-VERBATIM from the held `canonical/edrdg/kanjidic2/kanjidic2.xml.gz`
(database_version 2026-202, date_of_creation 2026-07-21); only unrelated
entries were dropped and the DTD internal subset removed so the file parses
standalone.

Retrieved: 2026-07-21 from the held EDRDG shelf (upstream:
http://www.edrdg.org/kanjidic/kanjidic2.xml.gz, CC BY-SA 4.0).

The 17 selected kanji and what they pin:

- 国 / 國 — a jinmeiyō 1:1 pair (kJinmeiyoKanji 國→国); the kanjidic variant
  link is *absorbed* onto the jinmeiyō canonical, never fighting it.
- 医 / 醫 — a clean kanjidic single (醫 has no grade; 医 is grade 3 jōyō) →
  the 1:1 lane-2 pair 醫→医.
- 弁 / 辨 / 瓣 / 辯 — the flagship polygraphic MERGE (three distinct classical
  words collapsed into one shinjitai); all three olds fold onto 弁's skeleton.
- 崎 / 埼 / 碕 — 碕 is variant-linked to two jōyō forms (崎 AND 埼) → refused as
  one-to-many ambiguity (never pick arbitrarily).
- 缶 / 罐 — 罐 (kan, a boiler/can) folds onto jōyō 缶 (grade 8).
- 學 / 学 / 斈 / 斅 — the itaiji cluster: 學 (kyūjitai), 斈, 斅 all fold onto
  学's skeleton; 學's `<variant var_type="jis212">` is IGNORED (JIS X 0212 is a
  different standard the JIS X 0213 resolver does not cover — decoding it
  through the 0213 plane-1 table would misread 1-33-55 as 宋).
