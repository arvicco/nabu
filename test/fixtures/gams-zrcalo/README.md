# gams-zrcalo fixture (GAMS Graz, CC BY 4.0)

Retrieved 2026-10-11 from the TEI_SOURCE datastream of GAMS object
`o:speculum.01` — https://gams.uni-graz.at/o:speculum.01/TEI_SOURCE
(509,016 bytes; no Last-Modified/ETag served). The edition: *Digital
edition of Zrcalo člověčaskogo spasenja* (Martina Kramarić, Gerlinde
Schneider; ZIM-ACDH Graz 2022), licence in the TEI's own availability:
"Creative Commons BY 4.0".

`speculum.01.xml` — the real file, re-serialized after a trim:

- the teiHeader WHOLE (msDesc with the five msItems, the Glagolitic
  scriptDesc, origDate 1445, origPlace "place of origin unknown", the
  custody provenance, bibliographies);
- the body cut to the outer title div + the foreword and chapters 1, 8
  (the lost-title note, two sic/corr choices), 14 (choice, del, add,
  surplus, label), 24 (the between-paragraph lacuna note) and "35."
  (a div@n without "Chapter"). Every REMOVED chapter leaves its last
  `<pb/>` and `<cb/>` in place, so the folio/column state of each kept
  passage is exactly what the whole file yields (verified passage by
  passage against the full file at cut time); whitespace-only lines
  dropped.

Re-cut recipe: GET the datastream, remove the other `div[@n]` chapters
keeping each one's last pb/cb as a sibling, re-serialize.
