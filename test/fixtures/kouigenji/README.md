# kouigenji fixtures

Retrieved 2026-09-29 from
github.com/kouigenjimonogatari/kouigenjimonogatari.github.io (repo
license CC BY 4.0; the 校異源氏物語テキストDB — Ikeda Kikan's 1942
critical edition of Genji Monogatari, TEI-encoded by the デジタル源氏
物語 project, Nakamura/Nagasaki et al.).

- `01.xml` — 桐壺 (きりつぼ), REAL header + the first 59 line-segs
  including waka-001 (かきりとて…), then closing tags. Shape: body >
  p > seg per MANUSCRIPT LINE, `corresp` API id `NNNN-NN` = page.line
  (0005-01 → p5.l1); `<pb n= facs=>` NDL IIIF page breaks; waka ride
  as `<lg type="waka" xml:id="waka-NNN">` with five `<l n>` lines
  NESTED INSIDE their seg.
- `03.xml` — うつせみ, header + first 6 segs (multi-doc discovery +
  a second title).

Upstream: xml/master/01.xml … 54.xml (the 54 maki, one TEI each;
raw.githubusercontent URLs).
