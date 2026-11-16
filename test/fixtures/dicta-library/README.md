# dicta-library fixtures — the Dicta library (AI-OCR'd rabbinic books)

Retrieved 2026-11-16:

- the manifest — https://github.com/Dicta-Israel-Center-for-Text-Analysis/Dicta-Library-Download
  (`books.json`, branch `main`, last upstream push 2026-10-06; raw at
  `https://raw.githubusercontent.com/Dicta-Israel-Center-for-Text-Analysis/Dicta-Library-Download/main/books.json`);
- the book zips — `https://files.dicta.org.il/library-1-0/<fileName>/<fileName>__<kind>.zip`
  (Cloudflare in front of S3; zips Last-Modified 2026-10-06).

License: the README's closing line is the bare link
`https://creativecommons.org/licenses/by-sa/4.0/` → CC BY-SA 4.0,
`attribution`, credit Dicta. Upstream's own warning (README, Hebrew,
verbatim): "כיוון שמדובר בתהליכים אוטומטיים ייתכנו שיבושים בטקסט וכן
בניקוד" — automatic processing, so the text and vocalization may contain
errors.

## Upstream's delivery grains

1. **Manifest** — `books.json`, a JSON array of 1,205 entries: `fileName`,
   `author`/`authorEnglish`, `category`/`categoryEnglish`,
   `subcategory`/`subcategoryEnglish` (null on 5), `displayName`/
   `displayNameEnglish`, `printLocation`/`printLocationEnglish`,
   `printYear` (1,204 integers 1726–1982 + one string `"1925-1931"`),
   `source`, `ocrFeDir`, and three URLs.
2. **Book, plain text** — `textFileURL`, `<fileName>__text_files.zip`: one
   member per scanned page, `<fileName>-NNN.txt` (lines as OCR'd). 536.4 MB
   over 1,204 HEAD-censused zips (one HEAD reset, re-probed: 22 B).
   **Three are empty 22-byte archives**: amudeiohr, chidusheiharadad,
   maharamlublin.
3. **Book, vocalized** — `nikudMetegFileURL`,
   `<fileName>__nikud_meteg_files.zip`: the same pages through Dicta's
   automatic vocalizer, one line per page. 750.5 MB. Empty for
   chidusheiharadad only.
4. **Book, OCR HTML** — `OCRDataURL`, `<fileName>__ocr_data_html_files.zip`:
   per-page `<span>` markup with OCR layout/confidence classes
   (`heading`, `flagged`, `edited`). 685.0 MB.
5. **Page** — one member of a book zip.

The adapter takes the **book** as the document (its plain-text zip) and
the **page** as the passage (urn tail = the scan number as an integer).
Rejected grains, each pinned here and skipped by rule:

| file | grain | rule |
|---|---|---|
| `books/birkatcohen__nikud_meteg_files.zip` | vocalized layer of a held book | machine vocalization over the held reading — never fetched (fetch takes it only when the text zip is empty) |
| `books/birkatcohen__ocr_data_html_files.zip` | OCR layout HTML | markup over the held reading — never fetched |
| `books/chidusheiharadad__{text,nikud_meteg}_files.zip` | a book with no text in either zip | both 22-byte empty archives |
| every empty page member | blank page | mints no passage (metadata `empty_pages`) |

And the fallback, also pinned: `maharamlublin` — its text zip is empty, its
vocalized zip is the document (metadata `text_layer` says so).

## The fixture tree (the FETCHED shape, not upstream's)

`books.json` keeps six of upstream's element blocks byte-identical.
`books/<fileName>.json` are the sidecars `Nabu::DictaLibraryFetch` writes
(the manifest entry, pretty-printed). The zips:

| file | upstream | kept | why it is here |
|---|---|---|---|
| `birkatcohen__text_files.zip` | 4,473 B, 2 pages | whole | Responsa, Acharonim (West), Piotrków 1908 |
| `rishonletziontaanit__text_files.zip` | 8,682 B, 3 pages | whole | the Or HaChaim on Taanit, Jerusalem 1915 (Acharonim East) |
| `sefatemetmoed1__text_files.zip` | 1,013,751 B, 324 pages | pages 003–005, re-zipped | the one `"1925-1931"` printYear |
| `hilchotberakhotritba__text_files.zip` | 29,133 B, 14 pages | pages 200–201, re-zipped | the Ritva — a Rishonim book (the era facet → heb:med) |
| `maharamlublin__text_files.zip` | 22 B, empty | whole | the empty text zip |
| `maharamlublin__nikud_meteg_files.zip` | 695,361 B, 136 pages | pages 009–010, re-zipped | the vocalized fallback (not NFC upstream) |
| `chidusheiharadad__text_files.zip`, `__nikud_meteg_files.zip` | 22 B each | whole | both empty → skipped |
| `birkatcohen__nikud_meteg_files.zip` | 6,435 B | whole | rejected grain specimen |
| `birkatcohen__ocr_data_html_files.zip` | 6,232 B | whole | rejected grain specimen |

Trim recipe: `unzip` the leading N members, `zip -X -D` them back (member
bytes verbatim).

## Census (2026-11-16)

Manifest: 1,205 books — Responsa 415 · Talmud and Commentaries 252 ·
Halakha and Minhaggim 205 · Chassidut 64 · Miscellaneous 65 · Tanakh and
Commentaries 56 · Derashot 49 · Rambam 43 · Rabbinic Literature 21 ·
Kabbala 18 · Jewish Thought and Ethics 12 · General Topics 5; print years
by century 17xx 7 · 18xx 687 · 19xx 510 (+1 range); 567 authors; 93 print
places. Expected first sync: 1,205 entries = 1,204 documents (1,202 plain +
2 vocalized fallbacks: amudeiohr, maharamlublin) + 1 skipped by rule
(chidusheiharadad). A 12-book random download sample: 4.05 MB of zips →
1,799 pages, 12.06 MB unzipped (≈ 2,250 B of zip per page) → ≈ 238k pages /
≈ 1.6 GB of page text library-wide.
