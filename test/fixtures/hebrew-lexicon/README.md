# hebrew-lexicon fixtures

Trimmed, byte-verbatim slices of the **OSHB Hebrew Lexicon**
(github.com/openscriptures/HebrewLexicon): retrieved 2026-07-18 from
https://github.com/openscriptures/HebrewLexicon at commit
`21c9add13bc727d3a951361778e97e3ff7afd1ce` (master, 2019-09-02 — the
content files' last change; the repo's later pushes touch site files
only). All four content files ship in the OSHB project's own XML
namespace `http://openscriptures.github.com/morphhb/namespace`.

Full-file sha256 at retrieval (the fixtures are slices of these bytes):

- `AugIndex.xml` (9,299 `<w>` rows upstream)
  `e7217ca8ff8ff3f21f9cf1bbe87411adf55f6aa88bcf5ed9ddc886cc6b160c5d`
- `LexicalIndex.xml` (10,221 entries: heb part 9,432 + arc part 789)
  `8f7a605c58899d2f44430149c143c00903976e1e91232476677972a69e5bc85f`
- `HebrewStrong.xml` (8,674 entries)
  `a628f4f89f8bdaf2483fd3faf1abc8653cc6717758dfc9f24beb7571d9bdd0c4`
- `BrownDriverBriggs.xml` (11,845 entries, 46 parts: 23 heb + 23 arc)
  `2b52658a4323d91674cda4090ab8b3ebddfff640f4f18143c28300e80b2c38f8`
- `readme.md` (the license grant)
  `9a129c25674387c494571c3828aa3a8eb78459c165e275c313ae26994ce8ff22`

## License

Verbatim from the repo's `readme.md` (the governing grant; the markdown
link resolves to http://creativecommons.org/licenses/by/4.0/):

> These files are released under the
> [Creative Commons Attribution 4.0 International](http://creativecommons.org/licenses/by/4.0/)
> license. The actual text of Brown, Driver, Briggs and Strong’s Hebrew
> dictionary remain in the public domain. For attribution purposes,
> credit the Open Scriptures Hebrew Bible Project.

→ `license_class` `attribution` (project annotations) over the
public-domain underlying dictionaries.

## Trim procedure

Each fixture is the real file header (XML declaration + root/part open
tags, BOM included where upstream has one — `BrownDriverBriggs.xml`
starts with U+FEFF), plus upstream `<w>`/`<entry>`/`<section>` blocks
copied **byte-verbatim in file order** (original tabs, original
non-NFC Masoretic mark order — never re-normalized), plus the original
closers. Nothing rewrapped, nothing reindented.

## The normalization rule pinned here (THE JOIN CONTRACT)

OSHB `@lemma` → augmented-Strong entry id: take the final `/`-segment
(drops the `b/ c/ d/ k/ l/ m/` prefix morphemes), strip whitespace,
strip a trailing `+`. Real OSHB fixture strings this covers:
`"b/7225"` → `7225`, `"1254 a"` → `1254a`, `"c/6213 a"` → `6213a`,
`"1008+"` → `1008`, `"l"` → `l`.

- Fixture-level join, measured 2026-07-18 over ALL 1,906 lemma-bearing
  tokens of `test/fixtures/oshb/wlc/{Gen,Jer,Ps,Ruth}.xml` against the
  full upstream AugIndex: **1,906/1,906 tokens = 100.000%** (506/506
  distinct normalized types).
- Live-catalog join (hebrew survey, 2026-07-18, canonical/oshb 4 books):
  **49,946/49,946 tokens = 100.000%** (Gen 20,159 + Jer 21,580 + Dan
  5,914 + Ruth 1,249; types 3,617/3,617), Aramaic Daniel included —
  Strong's Aramaic entries live in the same H-number space.

## What the slices cover

The **43 `AugIndex.xml` rows** are the complete normalized-lemma
inventory of four OSHB fixture verses — Gen 1:1, Gen 31:13, Gen 31:47
(the Aramaic Jegar-sahadutha verse), Jer 10:11 (the Aramaic verse) —
so the adapter test can join every real token of those verses
end-to-end. Shapes covered: bare numbers (`7225`), letter-augmented
ids (`1254a`, `3026a`, `3026b`, `834a`, `4480a`, `3837a`, `6965b`),
and one of the eight non-numeric particle ids (`l`, the preposition לְ
— no `HebrewStrong` entry exists for it, pinning the LexicalIndex-only
fallback).

- `LexicalIndex.xml`: the 43 target entries (28 heb + 15 arc parts),
  incl. entries without `<def>`/`<pos>` (`gau`), an `xref` with the
  `aug` letter attribute (`bxy`), and non-NFC headwords (`bxy` בָּרָא is
  dagesh-before-qamats upstream).
- `HebrewStrong.xml`: the 41 base entries `H7`…`H8460`, incl. Aramaic
  entries (`H7`, `H426`, `H560`, `H1768`, `H1836`, … `xml:lang="arc"`),
  proper nouns (`xml:lang="x-pn"`, e.g. `H1008` Beth-el), inline
  `<w src="H…">` cross-references, and `H1254`'s two-sense meaning.
- `BrownDriverBriggs.xml`: sections `a.aa`+`a.ab`+`a.ac` (part a, heb),
  `b.cw` (part b — `b.cw.aa` ברא, print page 135, the survey's
  exemplar), `xa.ab`+`xa.an` (part xa, **arc**) = 19 entries covering
  the sense trees (nested `<sense n>`), `<stem>`/`<asp>`/`<ref>`/
  `<foreign>` inline markup, all five `<status>` workflow values with
  numeric `@p` print pages (1, 2, 135, 1078, 1080), and the corpus's
  rare mid-entry `<page p="2"/>` second page anchor (`a.ac.aa`, one of
  two upstream).
