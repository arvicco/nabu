# ptg fixtures

Trimmed real sample of the DILA Pentaglot TEI P5 digital edition
(Dharma Drum, glossaries.dila.edu.tw) for the `ptg` adapter tests.

- Retrieved: 2026-11-04
- URL: https://glossaries.dila.edu.tw/data/pentaglot.dila.tei.p5.xml.zip
  (listed on https://glossaries.dila.edu.tw/glossaries/PTG as
  "XML-source", 42.09 KiB, dated 2017-03-20; 43,101 B, Last-Modified
  Mon, 20 Mar 2017 06:37:38 GMT; the zip carries one member,
  `pentaglot.dila.tei.p5.xml`, 465,625 B, UTF-8 with BOM, plus
  `__MACOSX/` junk)
- Zip sha256 at retrieval:
  `ed0519c108873a4d5f2ba500218fdbf5d771519a913feea3ee84398a88550393`
  (the adapter's frozen fetch pin)
- License, verbatim from the glossary page: "We believe this text is in
  the public domain." and "This digital version is licensed by DILA
  under a Creative Commons Attribution-Share Alike 3.0 Taiwan License."
  (The 2011 TEI header inside the member still reads "This TEI version
  is licensed by DDBC under a Creative Commons Attribution-Share Alike
  2.5 Taiwan License" — the predecessor statement; the live page
  governs.)
- Upstream description, verbatim: "This is a digital version of the
  Wuyi hebi jiyao 五譯合璧集要, as reprinted with indices by Raghu Vira
  under the title "Pentaglot Dictionary of Buddhist Terms", Delhi: 1961.
  The Pentaglot contains 1071 terms in Manchu, Chinese, Sanskrit
  (written in Tibetan script), Mongolian and Tibetan … We have not
  digitized the Tibetan terms as yet."

## Delivery grains

The glossary page serves six renderings of the one dictionary: HTML
zip, EPUB, **XML-source (TEI P5 zip — the grain taken)**, Stardict zip,
Babylon GLS zip, PDF. All but the TEI are derived renderings and are
never fetched (no specimen pinned: they are not files inside the
fetched asset, so there is nothing to skip). Inside the TEI the grain
is the `<entry>`; the document is the whole file, read once per
headword-language shelf.

## Full-file census (2026-11-04)

- 1,071 `<entry>` (matches the page's "1071 terms") = 1,070 real
  entries + 1 placeholder, `p341A.1`, which holds only an XML comment
  (Bawden's Manchu index cites "buyarame gargan" on a page DILA could
  not trace) — skipped by rule.
- Every real entry: five `<sense xml:lang>` in order `san-Latn`,
  `bod-Tibt` (empty ×1,070), `mnc-Latn`, `mon-Latn`, `zho-Hant`.
  Empty columns: Manchu ×2, Mongolian ×1, Chinese ×1, Sanskrit ×0 →
  shelves san 1,070 / mnc 1,068 / cmg 1,069 / lzh 1,069 (4,276 rows).
- Body: two volume `<div xml:id="han1|han2">` (472 / 599 entries), 73
  `<div type="topic">` (one nested level in the bodhipakṣika block);
  71 bracketed Sanskrit rubric rows head topics
  (`[buddha paryāya - nāmāni]`).
- ids: `pNNN.n` page.item of the 1961 reprint, all unique; irregular
  shapes `p192A.`, `p209`, `p340A.n`, `p340B.n`, `p341A.1`.
- Mongolian column is NOT NFC upstream: 415 combining U+0308 (ö/ü as
  base + diaeresis beside precomposed ü ×721); `ï` ×2; `"X"` placeholder
  quotes ×38.
- Manchu column: Möllendorff (ū ×237, š ×75), `’` ×12 in the
  Sanskrit-transcription syllables (`budg’ali`), hyphens ×31
  (`colgo-roko`, kept verbatim), inline editorial parentheses ×12
  (`(sic)`, `(for fusihūn)`, `(BN …)` variant notes, one full-width
  `？`).

## Trim recipe (applied to the extracted XML)

`pentaglot.dila.tei.p5.xml` here is the full teiHeader (BOM included)
plus 17 of the 1,071 entries inside their own volume/topic divs, every
kept line byte-verbatim (topic divs without a kept entry dropped, the
nested bodhipakṣika level kept):

- `p005.1`–`p006.1`: the opening topic — rubric row (`p005.1`), the
  golden `p005.2` buddhaḥ / fucihi / burkhan / 佛, `p005.3` bhagavān
  (Mongolian `nögchigsen` with a decomposed ö; Manchu hyphen).
- `p015.2`: Manchu `’` + Mongolian `ï`.
- `p031.2`: empty Mongolian column; `p166.2`: empty Chinese;
  `p336.4` and `p340B.1`: the two empty Manchu columns.
- `p071.1`, `p086.1`, `p155.1`, `p338.1`: Manchu editorial parentheses
  (`(sic)`, `(BN …)`, the full-width `？`); `p155.1` also carries
  upstream's long run of spaces and sits in the nested topic level.
- `p192A.`, `p209`: irregular ids; `p341A.1`: the placeholder;
  `p374.4`: the file's last entry.

The adapter's zip-shape tests build a zip from this file at test time
(the mvp pattern); no zip is checked in.
