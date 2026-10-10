# korba fixtures

Five real text directories from the KorBa manually annotated subcorpus
2.0 zip (`korba_xml.zip`, the project's download page link
https://korba.edu.pl/download_corpus). Retrieved 2026-10-10 — the live
host answered HTTP 502 all day, so the copy is the Internet Archive's
capture of the same URL:
https://web.archive.org/web/20240811115948id_/https://www.korba.edu.pl/download_corpus
(49,892,239 bytes; upstream Last-Modified Mon, 07 Jun 2021 14:18:27 GMT).

License (the download page, verbatim): "Pliki źródłowe podkorpusu
anotowanego ręcznie (wersja 2.0) można pobrać tutaj (licencja: Creative
Commons Attribution Share Alike)" — CC BY-SA 4.0; these trims are
redistributed under it. Credit: Elektroniczny Korpus Tekstów Polskich
z XVII i XVIII w. (do 1772 r.) — KorBa, Instytut Języka Polskiego PAN.

Each directory keeps the NKJP package's four layers. `header.xml` is
verbatim; the other three are TRIMMED to the text's first N `<ab>`
blocks, consistently across layers: text.xml keeps those blocks;
ann_segmentation.xml keeps the segs whose string-range targets an id
inside a kept block (plus range-less placeholder segs in kept
sentences, and the `<choice>` wrappers of kept segs); ann_morphosyntax.xml
keeps the morph segs pointing at kept segmentation segs. Emptied
div/p/s wrappers are dropped; the files are re-serialized (content
verbatim, inter-element whitespace may differ).

- `AkZbrojGęb/` (3 blocks) — an inventory (1690–1693, Żółkiew, Ziemie
  Ruskie; genre kanc / kind inwentarze / subject wojskowość) keyed from
  a MODERNIZED edition (Gębarowicz 1973) — the nested bibl
  type="modernized"; a Latin `<foreign>` span; two rejected
  segmentation alternatives.
- `AkDziec/` (1 block) — a 1761 Wilno print (`date @when`, publisher):
  the transcribed spelling (Ieżeli) vs the modernized orth (Jeżeli);
  `<choice>` with nkjp:rejected alternatives (uczyni|ć vs uczynić).
- `AndPiekBoh/` (1 block) — a Latin `<foreign>` span holding an
  `<uncertain reason="unreadable">` span whose xml:id does NOT follow
  the block's id numbering; foreign segs carry no interpretation.
- `HumListRzecz/` (1 block) — letters (1734): pubPlace place AND region
  "nieznane" (the unknown sentinel); a multi-code catRef
  (subject "#historia #wojskowość").
- `LubJMan/` (1 block) — two range-less `<seg type="g"/>` join
  placeholders in the segmentation layer.

Re-cut: unpack the zip, then trim each directory to its first N blocks
by the rule above (the recipe script is not part of the repo; any
re-implementation of the rule reproduces the files up to whitespace).
