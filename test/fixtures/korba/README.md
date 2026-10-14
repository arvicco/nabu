# korba fixtures

Six real text directories from the KorBa manually annotated subcorpus,
edition 2.0 (`korba_xml.zip`, the project's download page link
https://korba.edu.pl/download_corpus; upstream Last-Modified Mon, 02 Sep
2024 15:13:47 GMT, the corpus header "Final version, edition 2.0").
Re-cut 2026-10-14 from the fetched tree.

License (the download page, verbatim): "Pliki źródłowe podkorpusu
anotowanego ręcznie (wersja 2.0) można pobrać tutaj (licencja: Creative
Commons Attribution Share Alike)" — CC BY-SA 4.0; these trims are
redistributed under it. Credit: Elektroniczny Korpus Tekstów Polskich
z XVII i XVIII w. (do 1772 r.) — KorBa, Instytut Języka Polskiego PAN.

## Layout (mirrors the fetched tree)

    KorBa_manual_header.xml        the corpus-level header, whole
    TEI_korba1/<text>/             project stage 1 (850 texts upstream)
    TEI_korba2/<text>/             project stage 2 (1,241 texts upstream)

The 2021 edition-1.2 archive held the 850 stage-1 texts flat under one
top directory; edition 2.0 nests them by stage. Text directory names are
unique across both stage folders.

Each text directory keeps the NKJP package's four layers. `header.xml`
is verbatim; the other three are TRIMMED to the text's first N `<ab>`
blocks, consistently across layers: text.xml keeps those blocks;
ann_segmentation.xml keeps the segs whose string-range targets an id
inside a kept block (plus range-less placeholder segs in kept
sentences, and the `<choice>` wrappers of kept segs); ann_morphosyntax.xml
keeps the morph segs pointing at kept segmentation segs. Emptied
div/p/s wrappers are dropped; the files are re-serialized (content
verbatim, inter-element whitespace may differ).

- `TEI_korba1/AkZbrojGęb/` (3 blocks) — an inventory (1690–1693,
  Żółkiew, Ziemie Ruskie; genre kanc / kind inwentarze / subject
  wojskowość) keyed from a MODERNIZED edition (Gębarowicz 1973) — the
  nested bibl type="modernized"; a Latin `<foreign>` span; two rejected
  segmentation alternatives.
- `TEI_korba1/AkDziec/` (1 block) — a 1761 Wilno print (`date @when`,
  publisher): the transcribed spelling (Ieżeli) vs the modernized orth
  (Jeżeli); `<choice>` with nkjp:rejected alternatives (uczyni|ć vs
  uczynić).
- `TEI_korba1/AndPiekBoh/` (1 block) — a Latin `<foreign>` span holding
  an `<uncertain reason="unreadable">` span whose xml:id does NOT follow
  the block's id numbering; foreign segs carry no interpretation.
- `TEI_korba1/HumListRzecz/` (1 block) — letters (1734): pubPlace place
  AND region "nieznane" (the unknown sentinel); a multi-code catRef
  (subject "#historia #wojskowość").
- `TEI_korba1/LubJMan/` (1 block) — two range-less `<seg type="g"/>`
  join placeholders in the segmentation layer.
- `TEI_korba2/AugustKopia/` (2 blocks) — a stage-2 royal letter (1704,
  August II): pubPlace place "nieznane" but region "nieznany" — the
  stage-2 headers' masculine spelling of the region sentinel (168 of
  1,241 stage-2 headers); a Latin `<foreign>` "etc.".

Re-cut: from canonical/korba/, trim each directory to its first N
blocks by the rule above into the same stage folder (the recipe script
is not part of the repo; any re-implementation of the rule reproduces
the files up to whitespace).
