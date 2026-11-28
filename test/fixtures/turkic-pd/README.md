# turkic-pd fixtures

archive.org hOCR derivative pairs (`<stem>_hocr_searchtext.txt.gz` +
`<stem>_hocr_pageindex.json.gz`), laid out as `canonical/turkic-pd/`
holds them: `<identifier>/<upstream file name>`. Retrieved 2026-11-27 from
`https://archive.org/download/<identifier>/<file name>`. All three works
are public domain (Kuun †1905, Thomsen †1927, Vámbéry †1913; prints
1870–1896).

Delivery grains: archive.org serves an ITEM (identifier) holding one
scanned volume and its derivatives. For every census item (all four,
read from `https://archive.org/metadata/<identifier>` on 2026-11-27) the
item serves: the Text PDF (Thomsen: an Image Container PDF plus an
Additional Text PDF; Vámbéry also a Grayscale PDF), `_djvu.txt` (DjVuTXT),
the full `_hocr.html`, `_chocr.html.gz`, the hOCR derivative pair
(`_hocr_searchtext.txt.gz` + `_hocr_pageindex.json.gz`) and page images
(`_jp2.zip`; Kuun also `_orig_jp2.tar`, Vámbéry `_raw_jp2.zip`; Thomsen
none). The shelf takes the hOCR derivative PAIR as the document and its
pages as passages; every other grain is not read (the djvu.txt carries the
same OCR without page boundaries; the PDFs and images carry no text the
pair lacks). The census is a curated table, so there is no rejected grain
on disk.

All three are PREFIX TRIMS:

- `codexcumanicusbi00kuunuoft/` — Géza Kuun, *Codex Cumanicus bibliothecae
  ad templum Divi Marci Venetiarum* (Budapest 1880), University of Toronto
  (Robarts) scan, no rights field. First 14 hOCR pages (upstream: 558;
  searchtext 447,419 B, sha256
  74835e2a42ec6e0a54183f632f040cc7136937834befa47ee15bcb2bcbf504f2;
  pageindex 6,663 B, sha256
  6db7b73966b5b8580b03881cb016d7a0c7b67325d95578ac3853a14c5ddf9b6b):
  blank leaves, the library bookplate, the two title pages, the printer's
  line, the preface and the first prolegomena page — the qwm item, the
  blank-leaf case.
- `inscriptionsdel00thomgoog/` — Vilhelm Thomsen, *Inscriptions de
  l'Orkhon déchiffrées* (Helsingfors 1896), Google scan of a University of
  Michigan copy, NOT_IN_COPYRIGHT. First 11 hOCR pages (upstream: 230;
  searchtext 248,409 B, sha256
  07a8f0f66f70dae6639849153d011b5f51c3fa7a0f305c1ec73f0d7c9da93be7;
  pageindex 2,776 B, sha256
  aeb46ab7a44e9e24ae82ab9ea47e587c1d09ca87c2380dfdfd2c3ccf9a044704):
  Google's usage-guidelines pages (English and French), the title page,
  the table of contents and the opening of the decipherment — the otk
  item.
- `uigurischesprach00vmuoft/` — Hermann Vámbéry, *Uigurische
  Sprachmonumente und das Kudatku Bilik* (Innsbruck 1870), University of
  Toronto (Robarts) scan, NOT_IN_COPYRIGHT. First 12 hOCR pages (upstream:
  288; searchtext 297,162 B, sha256
  0614f57c25b9a57c400d99e485735533e1717fe3c5bd3a825a09920730569784;
  pageindex 3,417 B, sha256
  40e0e9e65427d1df60c82fdaa6930403b12cd80ef75498f724d1530b17c587ba):
  four blank leaves, a handwritten flyleaf (garbled), the half-title, the
  title page and the Vorwort — the xqa item.

Not in the fixture tree: Radloff's *Die alttürkischen Inschriften der
Mongolei* (bub_gb_sVVDAQAAMAAJ, Public Domain Mark 1.0; 1,038 hOCR pages,
searchtext 1,110,159 B, pageindex 12,821 B) — the same grain and layout as
Thomsen's Google scan.

Trim recipe (the slavistics-pd one; a prefix of whole pages needs no offset
rebasing): keep the first N rows of the page index verbatim; keep the search
text's first `rows[N-1][1]` CHARACTERS (the index counts code points);
re-gzip both (the index re-serialized as compact JSON with ", " separators,
as upstream writes it).
