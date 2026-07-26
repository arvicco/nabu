# Dillmann fixtures — Lexicon linguae aethiopicae TEI entries (P46-2)

Three whole, real TEI entry files, snapshotted **2026-07-26** from
`github.com/BetaMasaheft/DillmannData` (branch `master`, commit
`b7a3d8875dec0a561c99aef212420c16655ef512`). Each upstream file is ONE
dictionary `<entry>` (13,727 entry files under numbered directories `1/` …
`11/` plus `new/` and `new1/`); the fixture tree mirrors that layout.
NB: the data repo is `DillmannData` — the sibling `Dillmann` repo is only
the eXist-db display application.

- `1/L3c8821a46d56420283fc3bdedc1c341a.xml` — ዐፅም (ʿaḍm, "os/bone",
  Dillmann `n="7417"`): the rich shape — nested lettered senses (a–g),
  `<cit type="translation">` Latin glosses, biblical `<ref cRef=…>`
  citations, comparative Semitic `<foreign>` forms (Hebrew, Arabic).
- `1/L2d417be91261494990015aae6b9b5d81.xml` — ሞተ (mota, "mori/die",
  `n="1472"`): the entry the TraCES fixture's lemma links point at
  (`lex` value `L2d417be91261494990015aae6b9b5d81--ሞተ` in
  test/fixtures/traces/RIE232TEILing.xml) — the cross-source crosswalk
  anchor. Licence target with `http://` scheme.
- `new1/L844cd3b8849f4c16b5f3390e611a4f7b.xml` — ደረባ (darabā, a
  TraCES-project ADDITION, `n="12860"`): English sense
  (`source="#traces"`), a prefixed-namespace `<t:quote>` transcription,
  `<nd/>` empty element, and the licence target with `https://` scheme.

License (D46-b context; row 124): EVERY entry file carries the MALFORMED
licence target `http(s)://creativecommons.org/licenses/by-sa-nc/4.0/` —
"by-sa-nc" is not a URL Creative Commons serves; the prose beside it reads
"licensed under the Creative Commons Attribution-ShareAlike Non Commercial
4.0", i.e. **CC BY-NC-SA 4.0** → class `nc`. Both URL-scheme variants are
pinned here (12,453 `http://` + 1,274 `https://` censused 2026-07-26).
