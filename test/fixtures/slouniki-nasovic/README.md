# slouniki-nasovic fixtures — Насовіч, Словарь бѣлорусскаго нарѣчія (1870) (P117)

Four WHOLE, byte-identical article files snapshotted **2026-10-11** from
`github.com/Belarus/Slouniki-Nasovic` (branch `master`, commit
`0970671c7a64cb2c5a31ee9d62eacd5873defc24`, 2026-02-16). Upstream ships one
SlounikPlus XML article per file under `data/` (35,159 files, ids
00007–35252) against `data/article.xsd`; the fixture tree mirrors that
layout. Repo description (the license statement): "Іван Насовіч. Слоўнік
беларускай мовы. Public domain."

- `data/00007.xml` — «А, союзъ.»: two senses (`<tlum>`), several examples
  (`<ex>`), proverb marker "(Посл.)".
- `data/00873.xml` — «БЕЗГОЛО´ВИЦА, -ы, с. ж.»: three senses, one with a
  `<gram>` label ("общ. р."); the print's stress mark as U+00B4 "´".
- `data/00014.xml` — «АБАКУ´ЛИЦЬ, см. {Абаку´ливаць}.»: a pure
  cross-reference — no `<tlum>`, the `{…}` editor markup verbatim.
- `data/01256.xml` — «БЛАЖЕ´Й, -я, с. м.»: carries an editor's `<comment>`.

Every file carries the `<rtf>` base64 rich-text blob of the editor's source
(not ingested — formatting only).
