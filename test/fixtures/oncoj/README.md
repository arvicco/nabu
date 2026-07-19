# ONCOJ corpus fixtures — P32-2

Real upstream sample for the `oncoj` adapter (`Nabu::Adapters::Oncoj` /
`OncojXmlParser`). Retrieved **2026-07-19** by
`git clone --depth 1 --branch release https://github.com/ONCOJ/data`
— the **"release" tag** (commit `fd34a1b284c5dd1e8008df9d3abcb28cfaf464bf`,
2021-12-26, the project's sanctioned periodic release; the project site
<https://oncoj.ninjal.ac.jp/> continues to develop — any re-pin is an
owner decision). The four `xml/` texts are **whole, byte-verbatim**
upstream files; `lexicon.xml` is a documented trim (below); `README` is
the upstream corpus README, whole and byte-verbatim (sha256
`d16432c359500b40a7414e3e08dca67e6835468e59f80cf39de763e1ab27eef2`).

## License (verbatim, upstream `README` §D, at fixture time)

> The corpus annotation (the grammatical analysis) is licensed under
> the Creative Commons Attribution 4.0 International License. To view a copy
> of this license, visit http://creativecommons.org/licenses/by/4.0/ or send
> a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.

The texts themselves are 7th–8th-century compositions — public domain;
the annotation grant → class `attribution`. Prescribed citation (§C,
verbatim, carried in the manifest):

> National Institute for Japanese Language and Linguistics (2021)
> “Oxford-NINJAL Corpus of Old Japanese” http://oncoj.ninjal.ac.jp/
> (accessed 26 December 2021)

## THE FORMAT DECISION (probed at fixture time — why `xml/`, not `oncoj.csv`)

The release ships the same annotation in three shapes; all three were
probed on the full clone before this fixture was cut:

- **`oncoj.csv`** (11,593,214 B, sha256
  `24d7f28fec2e92d87eccfbeb776cc966a0eeacd153dac3b1b843dee8c37166b4`) —
  one flattened record per text: a romanized `=N(" … ")` spine line,
  then one row per token whose *leading columns are the token's whole
  constituency path* (with `;@k` positional disambiguators), man'yōgana
  lines interleaved as `<n>@…` cells, and the text id **trailing** the
  record as a final `"ID","MYS.1.1"` row (4,992 records censused). A
  csv parser would have to reverse-engineer tree structure, line
  pairing and record boundaries that the XML states explicitly —
  structure we would be inventing, not reading.
- **`psd/`** (26 CorpusSearch `.psd` files, 9.7 MB) — bracketed trees
  formatted for the CorpusSearch tool; a third rendering of the same
  annotation, no per-text file grain.
- **`xml/`** (4,991 per-text files, 26 MB) — "TEI compatible" per the
  upstream README: one file per text, stable id (`body/@xml:id` =
  filename stem), per-line man'yōgana (`lb/@corresp` — **33,192/33,192
  lines carry it**, censused), per-word lemma ids (`w/@lemma` —
  115,515/115,525 leaf words) resolving into `lexicon.xml`, and
  per-segment script status (`c/@type`: log 58,863 · phon 50,608 ·
  nlog 4,839 · phon-kun 1,200 · phon-on 1,110 · plog 682 · null 288 ·
  ill 10 · phonon 1 — censused corpus-wide).

**Decision: `xml/` is the parse source.** It is the richest and most
explicit shape, its per-text files are the natural document grain, and
it alone pairs each original-script line with its analysis without
positional reconstruction. `oncoj.csv` and `psd/` are upstream
derivatives of the same annotation — not ingested, excluded from the
sparse fetch cone.

## Which layer is text, which is annotation (what the data distinguishes)

The corpus's element CONTENT is the editors' romanized analysis (the
`<ab type="transliteration">` layer — upstream's own name for it); the
original man'yōgana script rides as the `lb/@corresp` ATTRIBUTE, line
by line, with no per-word alignment. The adapter follows the data:
passage text = the romanized token stream of the line; man'yōgana =
the `"manyogana"` annotation. The FOUR corpus lines with man'yōgana but
no tokens at all (censused under the shipped walk: MYS.10.2033 lb3+lb4,
MYS.12.2917 lb2, MYS.20.4372 lb8 — famous cruxes upstream declines to
analyze) invert honestly: text = the man'yōgana itself,
`"unanalyzed" => true`. Two more one-off shapes were surfaced by the
first parse and are handled, censused corpus-wide as singletons: KK.6
carries the corpus's ONE line break INSIDE a word (`lb id="9"` between
the `<c>` segments of adisikwi|takapwikwone — the token rides its
starting line whole, the interior lb opens the next line after it), and
MYS.4.655 lb4 carries the corpus's only four word-less bare `<c>`
segments (minted as pos-less, lemma-less tokens — never lost).
Romanization is pure lowercase ASCII plus `*` (censused; the `<c
type="null">` null-realization mark) — nothing to strip, so **no
`config/display.yml` row**.

## Files kept

| file | why |
|---|---|
| `xml/BS.1.xml` | Bussokuseki-ka 1 — small clean single-sentence text; lemma-bearing compound `<w>` (titipapa, `l050402`) above its leaf parts |
| `xml/MYS.1.1.xml` | Man'yōshū 1.1, the flagship opening poem — `multi-sentence` wrapper (6 sentences), 17 lines, log/phon segment mix |
| `xml/KK.6.xml` | Kojiki kayō 6 — the corpus's ONE mid-word line break (lb9 inside the `<w>` adisikwi|takapwikwone, lines 8/9) |
| `xml/MYS.10.2033.xml` | Tanabata crux poem — lb3 `神競者` + lb4 `磨待無`, two of the four token-less (unanalyzed) lines |
| `xml/MYS.3.276b.xml` | variant text — **duplicate upstream lb ids** (`0,3,4,0,1` — two `0`s): pins the deterministic `-b` re-mint (2 such files corpus-wide: MYS.3.276b, MYS.5.903) |
| `lexicon.xml` | trimmed: the 91 `<superEntry>` blocks (112 entries) covering every lemma id the five texts reference (87 superEntries) + `l000006-main` (EOJ geo-usage variant) + `l000032-main` (def-less entry) + `l090819main`/`l090819-main` (the upstream **duplicate entry id** pair) — blocks kept **line-byte-verbatim** in file order between the original 3-line header and `</div>`; full file 3,405,964 B, sha256 `b6c06d00e61c53325217b5494e64130297ad1f30aa9c9dd1347472b8a23b6d2f` |
| `README` | upstream corpus README, whole — the license and citation source |

Per-file sha256 (whole files, = upstream bytes):

```
b1a6f3248d335e7bf713e8745dbccc8742ca23078d3beeff010da93f76729e18  xml/BS.1.xml
2212574a117ae1ba1dba31808e0509e21e317f33df602e00b3b75e58d4ac5f64  xml/MYS.1.1.xml
01d058a3c430c37c53a641b77a78c45113b94d1459f78f0d51438164846715d7  xml/KK.6.xml
69352b13cf9318a1c0a21c8fd14a9755cb5d18c1d33029932886a6c320dc478b  xml/MYS.10.2033.xml
ac2986648048420fb7c95f91b3972fa9584ed1994e6983627d99c242fefabb04  xml/MYS.3.276b.xml
d16432c359500b40a7414e3e08dca67e6835468e59f80cf39de763e1ab27eef2  README
```

## Trim recipe (lexicon.xml)

From the release clone: collect `w/@lemma` ids of the five fixture
texts (88 distinct); walk the full `lexicon.xml` LINE-wise; keep the
3-line header, every `    <superEntry …>` … `    </superEntry>` block
whose `xml:id` set intersects the wanted ids (plus the four named
extras above), and append `</div>`. Lines are copied byte-verbatim —
no re-serialization.

## Census at fixture time (full release, 2026-07-19)

- 4,991 `xml/` texts: MYS 4,693 · NSK 133 · KK 112 · BS 21 · FK 20 ·
  SNK 8 · JSHT 4. **NB the packet brief's "Senmyō" is NOT in this
  release** — the 2021-12-26 tag carries SNK (Shoku Nihongi kayō) and
  JSHT instead; Senmyō exists only on the continuing project site.
- 33,192 lines, all with man'yōgana `@corresp`; 4 token-less (above);
  1 mid-word line break (KK.6); 4 word-less bare `<c>` segments
  (MYS.4.655) — the singleton quirks, both fixture-pinned.
- 141,247 `<w>` (115,525 leaf tokens; 115,515 with `@lemma`);
  lemma-bearing `<w>` occurrences incl. compounds 125,043.
- Token→lexicon join, measured: 5,792/5,802 distinct lemma ids resolve
  to a `lexicon.xml` entry (**99.8%**); 125,020/125,043 lemma-bearing
  word occurrences resolve (**99.98%**); 5,793/5,871 lexicon entries
  are cited by the corpus (98.7%).
- Structure quirks, all censused and handled: 1 file without the
  `<s>` wrapper (MYS.10.2027 — `ab > cl` directly); 12 files with
  out-of-order/skipped lb ids (upstream ids kept verbatim as citation,
  sequence = document order); 2 files with duplicate lb ids (`-b`
  re-mint); tokens sitting directly under the `multi-sentence` wrapper
  outside any child `<s>` (e.g. MYS.14.3419) — invisible to the
  line-grain walk, nothing lost.
