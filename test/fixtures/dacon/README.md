# DACON fixtures

Real files from **DACON — the Diachronic Annotated Corpus of Newar**
(O'Neill & Meelen; Zenodo record 12887386, DOI 10.5281/zenodo.12887386,
CC BY 4.0), retrieved **2026-08-29** from the record's file API
(`https://zenodo.org/api/records/12887386/files/<name>/content`).

The set deliberately carries the deposit's three FORMAT VARIANTS
(censused 2026-08-29 across all four texts):

| file | bytes | variant |
|---|---|---|
| `cnew12-Ukubahah_POS.txt` | 3,736 (WHOLE) | LF, no header, 4-space separator, zero `<utt>` lines |
| `cnew12-Ukubahah_SEG.txt` | 1,801 (WHOLE) | the SEG rendition (pins the discovery skip) |
| `cnew13_14-Gopala_POS.txt` | first 48 of 9,130 lines | UTF-8 BOM + CRLF + `form    POS` header, 4-space, `<utt>` blocks |
| `cnew17-vetala-MSB-10000_POS.txt` | first 120 of 9,999 lines | CRLF + `form\tPOS` header, TAB separator |

Both trims are byte-verbatim heads (`head -n`) of the real downloads —
never hand-edited. The cnew12 pair is whole (the 234-token Ukubāhāḥ
inscription — the deposit's smallest text).

Upstream quirks the fixtures/tests pin: the BOM, the CRLF/LF split, the
two separator conventions, `fol`-tagged foliation tokens (`[1]`,
`*fn30a`), and (via the parser test's verbatim StringIO lines — they sit
deep in the full files) the 26 censused dirty lines: tag-less forms,
one glued form+tag, separator-only lines, one three-field line.
