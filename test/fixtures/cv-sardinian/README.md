# cv-sardinian fixtures — Common Voice Sardinian sentence text

Retrieved 2026-08-19 from the Mozilla Common Voice repository (the TEXT
side only — no audio, ever):

- `sentence-collector.txt` — trimmed from
  <https://raw.githubusercontent.com/common-voice/common-voice/main/server/data/sc/sentence-collector.txt>
  (full artifact 2026-08-19: **265,677 bytes, 5,237 lines**, sha256
  `f62431087020e1c600b4940d04cc98cca04255f2d47dc20fa7325e63cf2f16ec`).
  The fixture holds byte-verbatim lines **1–10 plus the final line 5,237**
  (`Ùndighi.`), and — like the full artifact — ends WITHOUT a trailing
  newline (the documented upstream quirk; the last sentence must still
  mint a passage). Zero blank lines, no BOM/CRLF, all lines NFC upstream.

`sc` is Common Voice's locale code for Sardinian (ISO 639-1 `sc` = 639-3
`srd`). One sentence per line, no ids — passage identity is the 1-based
line number in the local canonical file (the tla-hf precedent).

## License (verified 2026-08-19)

`server/data/LICENSE` in the same directory tree
(<https://github.com/common-voice/common-voice/blob/main/server/data/LICENSE>)
is the full text of **CC0 1.0 Universal** — Common Voice accepts sentence
submissions only under CC0/public domain. → `license_class: open`.
