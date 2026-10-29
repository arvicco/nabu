# lzh-collection fixtures

Real upstream sample from **nk2028/lzh-collection** — nk2028's Classical
Chinese Collection (plain-text Literary Chinese; README: texts contributed
by Billy Zhou).

- **Upstream:** <https://github.com/nk2028/lzh-collection>, branch `main`,
  commit `dda274b7269234981b543b0c2b4f1df6981fa947` (2023-02-27, the last
  push).
- **Retrieved:** 2026-10-29 through the GitHub contents API.
- **License:** the in-repo `LICENSE` is the full CC0 1.0 Universal legal
  code (opening "Creative Commons Legal Code / CC0 1.0 Universal"; sha256
  `a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499`);
  the GitHub license field reads CC0-1.0 → license_class `open`. The repo
  names no print edition for any text (provenance gap, recorded).

## Upstream's delivery grains

One grain: `data/<title>.txt`, one work per file (UTF-8, LF, no BOM), 30
files. The dedupe census (titles + twelve evenly spaced six-character
content samples per file against the held kanripo / zh-wikisource / ccl /
classical-modern / cbeta trees, 2026-10-29) splits them:

| class | files | adapter |
|---|---|---|
| Ming–Qing poetry collections (別集), 19 poets | 20 (0–1 of 12 samples held) | ACCEPTED, one document each |
| the Masters 白文 texts 公孫龍子 列子 墨子 新語 法言 管子 老子 荀子 韓非子 | 9 (8–12 of 12 held, kanripo holds every one) | SKIPPED by rule, the note names the witness |
| 李夢陽詩集 | 1 (8 of 12 held — kanripo KR4e0150 空同集) | SKIPPED by rule |

20 + 10 = 30. README.md and LICENSE are not data.

## What the fixture holds

| file | trim | pins |
|---|---|---|
| `data/1_史可法詩集.txt` | whole (694 bytes, 11 lines) | the juan heading on line 1 governing every line; a parenthesised circumstance note in a title |
| `data/1_甌北集.txt` | upstream lines 1–7 | a juan heading carrying a sexagenary year range (起丙寅至戊辰); 甌北集 names no poet (the table: 趙翼) |
| `data/2_夏完淳詩集.txt` | upstream lines 1–12 + 101–103 | interlinear variant notes （一作上）; line 103 writes 裏 as the compatibility ideograph U+F9E7 (NFC folds it to U+88CF) |
| `data/老子白文.txt` | upstream lines 1–6 | rejected-grain specimen (held: kanripo KR5c0057) |
| `data/2_李夢陽詩集.txt` | upstream lines 1–5 | rejected-grain specimen (held: kanripo KR4e0150) |

Every kept line is byte-verbatim upstream.
