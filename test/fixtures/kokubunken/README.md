# kokubunken fixtures

Retrieved 2026-09-29 from github.com/kokubunken (NIJL's TEI lane;
both repo READMEs verbatim: 「…CC BY 4.0…のもとで公開しております」).

- `Kokinwakashu_200003050_20240922.xml` — 嘉禄二年本古今和歌集:
  REAL header + the full 仮名序 (phr-grain prose with app/lem/rdg
  apparatus and ruby) + the first two 和歌 divs (poems n1/n2 with
  詞書 + 作者名 notes and five-seg ku), then balanced closing tags.
- `manyo_hirose_v06_0001-0234,3348-3577_202603.xml` — 廣瀬本万葉集
  巻一: REAL header + front matter + poem 1 (長歌 as `ab` with
  傍訓 gloss segs and ミセケチ subst corrections) through poem 4's
  短歌 `lg` (man'yōgana l + corresp kun l), balanced closing tags.

Both trims re-cut with the tag-balance recipe in the phase notes;
Nokogiri-verified well-formed.
