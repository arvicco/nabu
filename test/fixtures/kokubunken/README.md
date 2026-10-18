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

Personography (added 2026-10-18, from the owner's live canonical copy of
the same files): each trim now closes with a `<back>` holding only its
file's `<listPerson>`, cut to real `<person>` records copied verbatim —
Kokin: 藤原定家 (aliases + VIAF), 安倍清行 (type="よみ" reading, ナシ
idnos, zero-padded @when), 在原元方 and 紀貫之 (the fixture poems'
poets), 伊勢 (sex 2, 不明 death); 廣瀬本: 雄略天皇, 舒明天皇, 中皇命
(the fixture poems' divisions) and 持統天皇 (two names). The real
`<back>`s also carry 奥書 (Kokin) and listBibl (廣瀬本), not kept.
