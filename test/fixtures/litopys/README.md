# litopys fixtures — Izbornyk (litopys.org.ua), the PD-edition subset (P117)

Real pages of the Izbornyk site, retrieved **2026-10-11** over plain HTTP
from `http://litopys.org.ua/<path>` (the site's HTTPS certificate does not
name the host; `http://izbornyk.org.ua/<path>` is the site's own mirror).
Bytes are the site's verbatim **windows-1251**; the adapter decodes at the
boundary. Paths mirror the site's directory layout, exactly as the fetch
lays them out under `canonical/litopys/`.

## The Ipatiev chronicle — ПСРЛ т. 2 (СПб., 1908)

Each page carries its edition statement as `<p class=Vary_cent>[ПСРЛ. — Т. 2.
Ипатьевская летопись. — СПб., 1908. — Стлб. N-M.]</p>`.

- `ipatlet/ipat01.htm` — TRIMMED: columns 3–18 cut at the apparatus-div
  boundaries (source lines 219–1109), keeping cols 1–2 (the print's heading
  «ЛѢТОПИСЬ ПО ИПАТЬЕВСКОМУ СПИСКУ.», the first folio mark `<small
  id="lyst2">//</small>`, variants + notes) and cols 19–21 (the first
  annal-year keys `[6413 (904)]`…).
- `ipatlet/ipat05.htm` — TRIMMED: columns 95–112 cut (source lines
  422–1372), keeping cols 89–94: the `<p class=Mberid="st91">` quirk (no
  space before `id=`), the MISLABELED `<p class=Mber id="st58">58</p>`
  anchor standing where column 92 begins, and a `<p class=KF>` paragraph.
- `ipatlet/ipat36.htm` — TRIMMED: columns 813–840 cut (source lines
  310–1898), keeping cols 810–812 and the page-opening continuation anchor
  `<p class=Mber id="st809_1">809п<br><br><br>810</p>`.
- `ipatlet/ipat40.htm` — WHOLE (cols 895–903, annals 6792–6795 / 1284–1287):
  the bracketed `[II, 214]` site reference, the `<small>Ђ</small>` font hack.

## The «Лексикони» glossaries (the dictionary lane)

- `zyzlex/zyz100.htm` — TRIMMED: letters Б–Щ cut (source lines 307–2904),
  keeping the page head with its statement `[Амфілохієва публікація: «Чтения
  в Обществе истории и древностей российских…», … М., 1884.]`, the print's
  column header «по слове(н)ску, просто.», letter А (48 entries) and Ю (2).
- `zyzlex/zyz101.htm` — WHOLE: «Рѣчь жидовьскаго языка…» (174 entries), the
  editor's pre-reform footnote.
- `zyzlex/zyz102.htm` — WHOLE: «Тлъкованїє неудобь познаваемомъ…» (61
  entries), `<small>Ђ</small>` / `<small>Ж</small>` inside headwords.

Re-cut recipe: GET the page, then drop the stated source-line ranges
(line numbers of the raw page; the trims cut at a `<div class="dop4">`
apparatus block so the page structure stays intact).
