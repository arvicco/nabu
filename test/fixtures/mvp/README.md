# mvp fixtures

Trimmed real sample of the DILA Mahāvyutpatti TEI P5 digital edition
(Dharma Drum, glossaries.dila.edu.tw) for the `mvp` adapter tests.

- Retrieved: 2026-07-28
- URL: https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.tei.p5.xml.zip
  (listed on https://glossaries.dila.edu.tw/glossaries/MVP — "Download",
  602.50 KiB, dated 2017-03-20; the zip carries one member,
  `mahavyutpatti.dila.tei.p5.xml`, 6,788,944 B, plus `__MACOSX/` junk)
- Zip sha256 at retrieval:
  `571e35e4d8d109a582512b81d9a529e0366690e4446dc61079f129163130b773`
  (the adapter's frozen fetch pin)
- License statement, verbatim from the glossary page: "We believe this
  text is in the public domain."

## Trim recipe (applied to the extracted XML)

`mahavyutpatti.dila.tei.p5.xml` here is the full teiHeader plus 8 of the
308 `<div>` sections, each with its `<head>` and a selection of its
entries — 15 of the full file's 9,379 entries, every kept span
byte-verbatim. Chosen to document the upstream quirks (full-file census
2026-07-28):

- keys `1`–`3` (如来名號): the plain shape — one `san-Latn` + one
  `san-Deva` orth (every entry in the file has exactly this pair),
  `zho-Hant`/`bod-Latn`/`bod-Tibt` translation cits; key `2` carries an
  `<add resp="ddbc">` editorial addition (259 in the file).
- key `625` (菩薩通稱): the bodhisattva golden entry; its first Chinese
  quote is a `<choice><sic>菩薩</sic><corr resp="ddbc">菩提薩埵</corr></choice>`
  (2,810 sic/corr pairs in the file).
- key `731a` (菩薩名號): a letter-suffixed key (keys are NOT all numeric).
- key `1040` (聲聞): a self-closed empty `<del resp="ddbc"/>` quote AND a
  non-empty `<del resp="ddbc">喜</del>` (1,749 `<del>` quotes in the
  file — editorially deleted equivalents, dropped from lanes).
- key `1055` ×2 (聲聞) and key `2347` ×2 (世間八法): the file's only TWO
  duplicated keys — different words each time (mahāpanthakaḥ /
  śroṇakoṭīviṃśaḥ; praśaṃsā / sukham) → positional `:2` entry ids.
- keys `3824`/`3825` (人次第): duplicated `bod-Tibt` quotes (the file's
  only two entries with two Tibetan-script cits).
- keys `7752a ` / `7752b ` (佛華嚴經・數): TRAILING SPACES inside the
  `@key` attribute (the file's only two) — ids are whitespace-stripped,
  `key_raw` stays verbatim.
- key `8418` (九十墮): an empty `<quote/>`-shaped `bod-Tibt` cit — the
  Tibetan lane degrades to Wylie only.

The adapter's zip-shape tests build a zip from this file at test time
(the mw pattern); no zip is checked in.
