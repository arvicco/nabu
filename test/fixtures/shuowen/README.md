# Shuowen Jiezi fixtures

Real records from the shuowen.org data repo
(<https://github.com/shuowenjiezi/shuowen>), master at commit
`6553a350763ce4feca2c5d1cc2cad7e594dc2975` (2025-09-05), retrieved
2026-10-21 as the codeload tarball. License: Apache License 2.0 (README
"## License": "Copyright [2019] [Shuowen.org] / Licensed under the Apache
License, Version 2.0").

## Delivery grains

Upstream serves two grains:

1. `data/<id>.json` — ONE RECORD PER HEAD CHARACTER (9,833 files, ids
   1..9,833 contiguous, one uniform key set). **Accepted**: each file is
   one dictionary document (a head entry plus its encoded 重文 entries).
2. `doc/` — the format guide (`FORMAT.md`), the contribution guide
   (`CONTRIBUTING.md`) and screenshots (`img/`). **Rejected**:
   documentation, not dictionary data. `doc/FORMAT.md` is pinned here
   (whole) and rides the adapter's sparse cone as the format's own
   provenance; the adapter counts it in `discovery_skips`.

## Records (`data/`, all WHOLE, byte-identical upstream copies)

- `1.json` 一 — the radical 一 with one encoded 重文 (弌).
- `7.json` 帝 — FORMAT.md's own worked example: fanqie, components, one
  encoded 重文 (𢂇), four Duan commentary pairs.
- `530.json` 蔇 — a Duan note writing 穊 as the CJK compatibility
  ideograph U+2F95A (one of the 42 non-NFC records).
- `1000.json` 䞪 — a plain record (no variants, no Xu notes).
- `1082.json` 此 — `volume` empty upstream (one of 3).
- `1214.json` 遐 — carries a 徐鉉 (`xuan_note`) note.
- `4354.json` 秀 — carries a 徐鍇 (`kai_note`) note and NO Duan pairs.
- `6558.json` 浾 — `pronunciation` (fanqie) empty upstream (one of 14);
  one encoded 重文 (泟).
- `7538.json` 雲 — two 重文: 云 (encoded) and one whose glyph upstream
  never encoded (empty `wordhead`, explanation only); duplicate and empty
  `indexes` keys.
