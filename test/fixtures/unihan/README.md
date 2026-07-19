# Unihan fixtures (P32-4 — the Sinoxenic character bridge)

Real upstream sample of the **Unicode Han Database** (CLAUDE.md fixture
rules; docs/backlog.md P32-4). Every kept line is **byte-verbatim** upstream
data; only the codepoint SET was trimmed.

- **Upstream:** `https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip`
  (8,518,517 bytes, sha256
  `f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e`,
  Last-Modified `Mon, 18 Aug 2025 15:51:14 GMT` = **Unicode 17.0.0**,
  in-file date stamp `2025-07-24`). NB `/latest/` moves with each annual
  Unicode release — re-check the version headers at any refresh.
- **Retrieved:** 2026-07-19 (whole zip; the two member files below unpacked
  and trimmed).
- **License (verbatim, unicode.org/license.txt, read 2026-07-19):**
  "UNICODE LICENSE V3 … Permission is hereby granted, free of charge, to
  any person obtaining a copy of data files and any associated
  documentation (the "Data Files") … to deal in the Data Files or Software
  without restriction, including without limitation the rights to use,
  copy, modify, merge, publish, distribute, and/or sell copies …, provided
  that either (a) this copyright and permission notice appear with all
  copies of the Data Files or Software, or (b) this copyright and
  permission notice appear in associated Documentation." → `open`.

## Upstream format reality (what this fixture preserves)

- One line per (codepoint, field): `U+4E00<TAB>kJapaneseOn<TAB>ICHI ITSU`;
  `#` comment header naming the fields each file carries; files sorted by
  the ASCII of the `U+…` key, so **plane-2 codepoints (`U+2000B`) sort
  BEFORE the BMP CJK blocks** — the parser re-sorts numerically.
- Unicode 17.0 field census over the full files (the carried-field verdict
  lives on `Nabu::Adapters::UnihanTxtParser`): kJapanese 51,583 ·
  kMandarin 44,348 · kHanyuPinyin 34,130 · kCantonese 29,936 ·
  kDefinition 23,285 · kFanqie 20,222 · kJapaneseOn 13,177 ·
  kJapaneseKun 11,296 · kXHC1983 11,072 · kKorean 9,050 · kHangul 8,525 ·
  kVietnamese 8,306 · kSMSZD2003Readings 8,110 · kTGHZ2013 8,105 ·
  kTang 3,811 · kHanyuPinlu 3,799 · kZhuang 2,472; variants:
  kSimplifiedVariant 6,929 · kTraditionalVariant 6,475 · kSemanticVariant
  3,538 · kSpecializedSemanticVariant 525 · kSpoofingVariant 349 ·
  kZVariant 149. 65,092 of 102,999 codepoints carry ≥1 carried field.
- `kJapanese` (added in Unicode 15.1) is DENSER than the legacy
  kJapaneseOn/kJapaneseKun pair it supersedes — all three are carried.

## These files — 16 codepoints, all their Readings + Variants lines

`Unihan_Readings.txt` (145 lines) + `Unihan_Variants.txt` (19 lines),
full comment headers kept verbatim. The set:

| Codepoints | Why |
|---|---|
| U+4E00 一, U+5929 天, U+4EBA 人 | full-strata rows (definition, fanqie, Tang readings, all three Japanese layers, Korean/Vietnamese); 天/人 tie to the HDIC fixtures (TSJ s0104a601, KRM F00001) |
| U+4E9C 亜 / U+4E9E 亞 / U+4E9A 亚 | the Japanese-shinjitai / traditional / simplified variant triangle (kSimplifiedVariant, kTraditionalVariant) |
| U+611B 愛 / U+7231 爱, U+9AD4 體 / U+4F53 体 | more variant pairs incl. the JMdict fixture headword 愛 |
| U+9B75 鬵 | ties to the TSJ wakun fixture row (sj_w00001 カナヘ) |
| U+340A / U+340B | the kSpoofingVariant pair — U+340A mints from the Variants file alone |
| U+349A | kSpecializedSemanticVariant with source tag (`U+6587<kFenn`) verbatim |
| U+3403 | **negative case:** carries ONLY kCantonese (censused out) — must mint NO entry |
| U+2000B 𠀋 | plane-2: sorts early in the raw file, last numerically |

## Extraction recipe (one-shot, run 2026-07-19)

```ruby
KEEP = %w[U+3403 U+340A U+340B U+349A U+4E00 U+4E9A U+4E9C U+4E9E U+4EBA
          U+4F53 U+5929 U+611B U+7231 U+9AD4 U+9B75 U+2000B]
# for each of the two member files: keep every `#`/blank line verbatim,
# keep a data line iff its first tab field is in KEEP
```
