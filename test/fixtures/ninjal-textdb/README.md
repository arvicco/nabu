# ninjal-textdb fixtures

NINJAL — *Text Data Sets for Research on the History of Japanese*
(日本語史研究用テキストデータ集), <https://www2.ninjal.ac.jp/textdb_dataset/en/>.
Retrieved 2026-11-04 (paced ~1 req/s; only the index, the 23 dataset pages,
3 layer views and the files below were requested).

## License (verbatim, per work page, read 2026-11-04)

- amhk, amis: "The transcribed text (txt) on this site is licensed under a
  Creative Commons Attribution 4.0 International License" (link
  `creativecommons.org/licenses/by/4.0/deed.en`).
- cmhab: "Transcription (txt) on this site is licensed under a Creative
  Commons 4.0 International license" — the word *Attribution* is missing
  from the sentence, but its link is `creativecommons.org/licenses/by/4.0/deed.en`
  and the badge is the BY 4.0 badge: CC BY 4.0.
- nipp: "Entry Words Data of Nippojisho Ver.202510 on this site is licensed
  under a Creative Commons Attribution 4.0 International License"; the
  zip's readme: クリエイティブ・コモンズ・ライセンス 表示 4.0 国際（CC BY 4.0）.

→ `license_class: attribution`. Facsimile images (British Library, HAB,
Gallica) are linked by the pages but never taken.

## Census — the index's dataset directories (2026-11-04)

The index links 24 directories (23 datasets + the news archive) plus one
external site (the Library of Congress Genji transcription on
`mmsrv.ninjal.ac.jp`, not a dataset dir). File counts are from each
dataset page's own link list.

| dir | dataset | section | serves | verdict |
|---|---|---|---|---|
| sksh | Saidaiji-bon konkōmyō saishōō-kyō heian shoki-ten (vol. 1) | Kunten Shiryō | 1 txt + 1 xml + himawari zip + manuals | skip by rule — kunten layer model; future widen |
| **amhk** | Feiqe no monogatari [Amakusa ed.], 1592 (BL Or.59.aa.1) | Kirishitan | 3 txt layers (r, k, rk) | **TAKEN** (r + k) |
| **amis** | Esopo no fabulas [Amakusa ed.], 1593 (same volume) | Kirishitan | 3 txt layers (r, k, rk) | **TAKEN** (r + k) |
| **cmhab** | Contemptus Mundi [HAB copy], 1596 (HAB 57.13 Eth.) | Kirishitan | 2 txt layers (r, r-normalized) | **TAKEN** (both) |
| kwrs | Wamyō ruijushō, 20-volume text [early movable type, 1617] | Dictionary | 20 txt | skip by rule — future widen |
| **nipp** | Nippojisho (Vocabulario da Lingoa de Iapam), 1603 | Dictionary | 1 zip (TSV + xlsx + readme) | **TAKEN** — dictionary lane |
| brsk | Shokoku hōgen butsurui shōko, 1775 | Dictionary | 5 txt | skip by rule |
| tgzi | Tetsugaku jii, 1881 | Dictionary | 1 txt | skip by rule |
| genk | Genkai (entry words Ver.202510) | Dictionary | 1 zip | skip by rule |
| ywyj | Yoshiwara yōji, 1788 | Share-bon/Ninjō-bon | 1 txt | skip by rule (Edo fiction) |
| agnm | Urazato tokijirō akegarasu nochi no masayume, 1821 | Share-bon/Ninjō-bon | 15 txt | skip by rule |
| mssy | Kosan kingorō kanamajiri musume setsuyō, 1831 | Share-bon/Ninjō-bon | 9 txt | skip by rule |
| umgy | Shunshoku umegoyomi, 1832 | Share-bon/Ninjō-bon | 12 txt | skip by rule |
| tmsn | Umegoyomi yokyō shunshoku tatsumi no sono, 1833 | Share-bon/Ninjō-bon | 12 txt | skip by rule |
| knhz | Ukiyo shingata koi no hanazome, 1833 | Share-bon/Ninjō-bon | 9 txt | skip by rule |
| hnsd | Hiyoku renri hana no shimadai, 1836 | Share-bon/Ninjō-bon | 12 txt | skip by rule |
| ssru | Shunshoku renri no ume, 1850 | Share-bon/Ninjō-bon | 15 txt | skip by rule |
| edms | Okumi sōjirō shunshoku edomurasaki, 1864 | Share-bon/Ninjō-bon | 9 txt | skip by rule |
| hn17 | Nihongo tokuhon, jinjōkayō [Hawai Kyōikukai, 1917 ed.] | JLS Textbooks | 6 txt | skip by rule (modern) |
| hn29 | Nihongo tokuhon [Hawai Kyōikukai, 1929 ed.] | JLS Textbooks | 6 txt | skip by rule (modern) |
| hn36 | Nihongo tokuhon [Hawai Kyōikukai, 1936 ed.] | JLS Textbooks | 12 txt | skip by rule (modern) |
| pi25 | Nihongo shoho [Dept. of Public Instruction, Territory of Hawaii] | JLS Textbooks | 2 txt | skip by rule (modern) |
| mjeh | Pre-war Hawaii Japanese textbooks (Akutagawa Collection) | JLS Textbooks | 78 PDF facsimiles, no txt | skip by rule — images only |
| newshistory | News Archive | site | release notes | skip by rule — no data |

The census is pinned in `Adapters::NinjalTextdb::DATASETS`; the 20
out-of-slice rows are counted in `discovery_skips` with their reasons and
are never fetched.

## Delivery grains (the Kirishitan sets)

Each work page lists its transcription files; each file is also rendered as
an HTML view (`en/<set>/<stem>.html`, the same txt in a page — rejected,
never fetched). The txt files live at `textdb_dataset/<set>/txt/<stem>.txt`;
"001" is the volume.

| file | layer | size | verdict |
|---|---|---|---|
| amhk-r-001.txt | original romanization (Latin script) | 501,988 B | document text |
| amhk-k-001.txt | kanji-kana transliteration | 559,485 B | annotation `kanji_kana` |
| amhk-rk-001.txt | r and k side by side, per line | 1,024,830 B | rejected — skip by rule |
| amis-r-001.txt | original romanization | 114,945 B | document text |
| amis-k-001.txt | kanji-kana transliteration | 134,026 B | annotation `kanji_kana` |
| amis-rk-001.txt | r and k side by side | 234,525 B | rejected (not pinned: amhk's specimen covers the rule) |
| cmhab-r-001.txt | original romanization | 542,217 B | document text |
| cmhab-r-normalized-001.txt | normalized romanization | 527,470 B | annotation `normalized` |
| nipp/data/ew-nippo-202510.zip | entry words: TSV + xlsx + readme | 3,378,215 B | TSV → dictionary entries |

Grain inside the files: the text numbers lines within pages — passage = one
printed line, cited **page.line**. Two body shapes:

- **paged** (amhk, amis): a `（page）` header line, then `n<TAB>text`. Page
  labels are the print's numbers plus 扉 (title page) and 序/序1–3 (preface).
  amhk-r-001 uses bare-CR line endings and a BOM; the others CRLF.
- **cited** (cmhab): `PPP.LL<TAB>text`, page labels `001`, `205[=206]`
  (misnumbered, corrected), `[434]` (supplied), `[*001]` (unpaginated title
  page), with column suffixes `[445]a`/`b`; `///` lines mark page breaks.

Full-file census through the adapter (2026-11-04): amhk-001 9,681 lines /
410 pages; amis-001 2,251 / 96; cmhab-001 10,173 / 476; total **22,105
passages**, 0 errors. The -k- layers share every page.line key with -r-
(9,681 / 2,251 aligned, 0 unmatched); the -rk- files are byte-for-byte the
-r- and -k- columns (0 mismatches over 11,932 lines). cmhab-normalized
aligns 8,943 of 10,173 lines — the 1,230 unmatched are the 目録 [434]–[444]
and 言葉の和らげ [445]–[459], which the normalized version omits (its rule 9).
Upstream mis-keys four amhk line numbers (8.15, 119.13, 310.11, 403.3 print
as repeats of their neighbour, in both layers): the number stays verbatim
and the repeat is cited `-b` (`8.1-b`).

Nippo Jisho: 32,878 rows, 32,878 unique 見出し語ID, 12 columns each, 6,887
in the Supplemento (folios 332–402), 5,582 verb rows, 325 with upstream
notes. The xlsx is the same content (the readme: 内容は同じです) — rejected,
not pinned (2.6 MB binary); the readme is pinned as the rejected
documentation grain.

## Files here (all trimmed except the readme)

- `amhk/amhk-r-001/amhk-r-001.txt`, `amhk/amhk-k-001/amhk-k-001.txt` — the
  rules header, pages 扉, 序1–3, 3 (the opening dialogue: "VManojô.
  Qẽgueônobŏ,Feiqe no yurai ga qi…") and 8 (the first mis-keyed "1"), the
  colophon. Bytes otherwise as served (BOM, line endings).
- `amhk/amhk-rk-001/amhk-rk-001.txt` — the rejected juxtaposition, pages
  扉 and 3.
- `amis/amis-r-001/amis-r-001.txt`, `amis/amis-k-001/amis-k-001.txt` — pages
  扉, 序, 409 (the Life of Esopo opens).
- `cmhab/cmhab-r-001/cmhab-r-001.txt`, `cmhab/cmhab-r-normalized-001/…` —
  pages [*001], 001, 205[=206], [445]a, [445]b (the glossary columns; absent
  from the normalized file by its own rule).
- `nipp/ew-nippo-202510.txt` — the header + 9 rows (A., Aa., the vel entry
  Aara.|,ara., the verb Abaqi,u,aita., two noted rows, a related-id-only row,
  the first Supplemento row, the last row); `nipp/readme_ew-nippo-202510.txt`
  whole. Both are members of the zip (no per-file URL).

The tree mirrors the adapter's canonical layout: one directory per fetched
txt (FileFetch keeps one file per dir), the Nippo zip unpacked into `nipp/`.
