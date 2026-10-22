# wilkens-oui fixtures

Jens Wilkens, *Handwörterbuch des Altuigurischen. Altuigurisch – Deutsch –
Türkisch / Eski Uygurcanın El Sözlüğü* (Göttingen: Universitätsverlag
Göttingen, 2021), DOI 10.17875/gup2021-1590. Retrieved 2026-10-22 from
https://univerlag.uni-goettingen.de/bitstream/3/isbn-978-3-86395-481-9/4/Wilkens_handwoerterbuch.pdf
(946 pages, sha256 4f61ac8db2a7cd5a60f3b454b0524b1c598de6e6e9681008576f84087e383c94).
License: CC BY-SA 4.0, as stated on the publisher's handle page
(univerlag.uni-goettingen.de/handle/3/isbn-978-3-86395-481-9), read
2026-10-22.

## Delivery grains

Upstream serves ONE grain: the whole book as a single born-digital PDF
(Microsoft Word 2016 export; the cover JPEG and METS record beside it are
metadata, not text). Inside it: front matter (PDF pp. 1–16: title,
Vorbemerkungen, Hinweise zur Benutzung, Abkürzungen, Symbole), the
dictionary body (PDF pp. 17–945 = printed folios 1–929), and the back cover
(p. 946). The parser takes the dictionary ENTRY as its record grain; the
rule separating body from matter is the printed folio (an arabic folio in
the bottom band = body; the 17 matter pages carry roman folios or none).

## The fixture

`wilkens-sample.pdf` — a `mutool merge` trim of five real pages, chosen for
the layout quirks a segmenter must survive:

| fixture page | PDF page | folio | why |
|---|---|---|---|
| 1 | 17  | 1   | the letter heading "a", superscript homonyms ¹a–⁴a, a sub-entry cross-reference |
| 2 | 60  | 44  | justified lines split into word fragments, hyphen-wraps (roman and italic), a two-line italic sub-entry phrase |
| 3 | 61  | 45  | page-top continuation of p. 44's last entry (sub-entries of *amranmaklıg*) |
| 4 | 198 | 182 | a sub-entry set at a non-standard indent (*bitigü p(a)ryan*) |
| 5 | 457 | 441 | page-top orphan lines (the parent *kün* is on folio 440) and multi-line bold headwords, one crossing the column break |

`wilkens-grains.pdf` — a second `mutool merge` trim (PDF pages 3, 15, 185),
the adapter's grain specimens: the REJECTED matter grain (p. 3, the
license page — "Dieses Werk ist lizenziert unter einer Creative Commons
Namensnennung - Weitergabe unter gleichen Bedingungen 4.0 International
Lizenz."; p. 15, the Symbole page with its roman folio IX) and folio 169
(p. 185), whose Hebrew etymon of *bidilhim* wraps onto an indent line —
one of the book's two records the segmenter closes with an empty
headword, skipped by rule. `wilkens-grains.stext.xml.gz` is its recorded
stext (same command, same mutool).

`wilkens-sample.stext.xml.gz` — the RECORDED `mutool draw -F stext -o -
wilkens-sample.pdf` output (mutool 1.28.0, 2026-10-22), gzipped, checked in
so the suite never depends on mutool being installed. Re-cut it with that
command and `gzip -9` if mutool's stext shape drifts; the guarded live test
compares the SEGMENTED entries, not the bytes.

## Layout facts the parser relies on (measured on the whole body)

- Two columns; mirrored margins: even folios x≈47.1 / 250.0, odd folios
  x≈58.4 / 261.7; sub-entries indent +11.7 (a handful of lines sit at
  other small indents).
- Main headwords are Word's synthetic bold: the glyphs are FILLED+STROKED
  (stext char flags bit 32), the font itself is plain Gentium.
- Sub-entry phrases (collocations filed under the first element) are
  Gentium-Italic at the indent; Sanskrit citations are italic too.
- Entries read `headword [(labels)] [< etymon] German || Türkisch`, senses
  chained `G1 || T1; G2 || T2`; `→` cross-references, `†` rejected readings.
- Subscript digits (5.38 pt) mark word pairs ("Liebe₂") and, before a
  headword, homonym numbers; the parser renders both as `^n`.
- Chinese characters in etymologies are set in a font without a ToUnicode
  map: the text layer yields U+FFFD for them (upstream residue).
