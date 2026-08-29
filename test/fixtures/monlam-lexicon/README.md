# monlam-lexicon fixtures

Two byte-verbatim head trims from **MonlamIT/Tibetan-Lexicon** (branch
`master`, HEAD 33e2c21b 2024-02-19 "Cleanup and updated licence";
Apache-2.0 LICENSE.txt at root), retrieved **2026-08-29**:

- `monlam-lexicon-1.txt` — the REAL first 40 lines (782 bytes) of the
  3,918,954-byte Monlam Dictionary list: **UTF-16LE + BOM + CRLF** with
  the `word` header line — the trim pins all three quirks.
- `monlam-lexicon-2.txt` — the REAL first 60 lines of the 25,122,113-byte
  Monlam **Grand** Dictionary list: UTF-8, LF, headerless.

Raw URLs:
`https://raw.githubusercontent.com/MonlamIT/Tibetan-Lexicon/master/monlam-lexicon-{1,2}.txt`

Census facts the tests pin (2026-08-29, over the whole files): lex-1
107,113 entries after the header (7 duplicate headwords); lex-2 **342,716**
real entries — the README's "367,011" counts raw lines, because the file
carries ONE contiguous 24,295-line blank run (raw lines 224,165–248,459:
the late-འ…ཡ alphabetical band is absent upstream —
`.docs/upstream-reports.md`), plus 377 duplicate headwords (max ×2), 70
trailing-tab lines, and 520 NFC-unstable lines (composition-excluded
Tibetan vowels: U+0F75 decomposes to U+0F71+U+0F74 under NFC — boundary
NFC applies, bod is not exempt). The censused dirt shapes are tested via
verbatim StringIO lines (they sit deep in the full files).
