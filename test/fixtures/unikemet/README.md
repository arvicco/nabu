# unikemet fixture

Trimmed REAL excerpt of Unicode 17.0's Unikemet.txt (the normative
Egyptian Hieroglyph data file of the UCD — the Egyptian analogue of
Unihan). Retrieved 2026-08-09 from
https://www.unicode.org/Public/17.0.0/ucd/Unikemet.txt (1,482,071 bytes,
5,067 codepoints; sha256
a7b46c19e24355257030b73be046c71b172595ec4a106867d3f988e3a4007208).

Cut: the complete header comment block (lines 1–32, license pointer and
field documentation verbatim) + every line of six complete sign blocks,
byte-verbatim in upstream order:

- U+13000 — A1 seated man: core, Classifier, full concordance row
  (kEH_JSesh/kEH_HG "A1", kEH_IFAO "1,1")
- U+1305D — legacy (kEH_Core L), kEH_AltSeq carrier, NO description —
  the sparse-field honesty case
- U+13143 — G5 falcon: Logogram (Horus), kEH_FVal ḥr — the aes
  hiero_inventar join exemplar
- U+13171 — G43 quail chick: Phonemogram, kEH_FVal w
- U+13216 — N35 water ripple: Phonemogram n — attested in the aes
  fixture's hiero_inventar (incl. beside N35A, the bounded-match trap)
- U+13460 — Extended-A block, kEH_Core absent (default N), UniK A001F

Field census at 17.0 (whole file): kEH_Cat/kEH_UniK 5,067 · kEH_Core
4,499 · kEH_Desc 4,380 · kEH_Func 4,378 · kEH_FVal 4,212 · kEH_JSesh
3,843 · kEH_HG 3,739 · kEH_IFAO 2,726 · kEH_AltSeq 97 · kEH_NoRotate 44
· kEH_NoMirror 4. Every (codepoint, field) pair is unique; kEH_JSesh
codes are globally unique.

## Refresh

Re-fetch the versioned URL above (a NEW Unicode release is a NEW pin —
owner call) and re-grep the same five codepoints.
