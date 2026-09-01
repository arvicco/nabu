# obi-burmese fixtures

Three whole real files from "A Structured Corpus of Old Burmese Stone
Inscriptions" (Zenodo record 4321314, CC BY 4.0 — verified via the
Zenodo API), volume 7 zip, retrieved 2026-09-01, unmodified, laid out
as the adapter extracts them (vol7/OBI_Corpus_Vol7/):

- `OBI_Vol7_No3a__ob_p6.txt` — inscription 3a, obverse: the full
  header + footnotes + line-paired body (Myanmar-script line ¤
  transliteration line), `<ftn>` markers inline.
- `OBI_Vol7_No36___p121.txt` — a face-less filename (the
  three-underscore shape) with empty FACE header field.
- `OBI_Vol7_No19b__re_p59.txt` — a reverse face of a lettered
  inscription number.
- `vol6/OBI_Vol6_No10__ob_p16.txt` (first-sync regression, 2026-09-01):
  vol6's parenthesized reconstructed line numbers ("(၁) ",
  space-separated, no tab) — and the volume zip extracts FLAT, without
  the vol7-style OBI_Corpus_VolN subdir, which the fixture layout
  mirrors.
