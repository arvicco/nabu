# dicta-bavli fixtures — Dicta's vocalized Babylonian Talmud

Retrieved 2026-11-16 from
https://github.com/Dicta-Israel-Center-for-Text-Analysis/Talmud-Bavli-with-Nikud
(branch `master`, last upstream push 2024-01-08), raw files under
`https://raw.githubusercontent.com/Dicta-Israel-Center-for-Text-Analysis/Talmud-Bavli-with-Nikud/master/`.

License (the README, verbatim; no LICENSE file, no version number):

> This vocalized text of the Babylonian Talmud is released under a CC BY-SA license.
> If you make use of the text, please attribute as follows: This text of the Babylonian
> Talmud was vocalized by Dicta: The Israel Center for Text Analysis (www.dicta.org.il)

→ `attribution` (unversioned BY-SA, admitted with the requested credit).

## Upstream's delivery grains (the whole tree, censused 2026-11-16)

1. **Tractate directory** — 38 top-level directories (English names:
   `Berakhot`, `Bava_Batra` …). `Meila` and `Meilah` are BOTH present and
   byte-identical (same sha256 for both files).
2. **Tractate file, two spellings** — per directory
   `<hebrew name>.combinedfullmaleh.txt` (ktiv male, the Vilna print's
   spelling) and `<hebrew name>.combinedfullhaser.txt` (ktiv haser, the
   defective spelling Dicta recommends for pointed text). Yevamot's Hebrew
   stem carries a trailing dot (`יבמות..combinedfull…`). 76 files; the two
   spellings are line-aligned in every tractate (identical line counts and
   blank/header skeletons).
3. **Daf/amud** — a header line ` *** דף ב. *** ` (gematria daf; `.` =
   amud a, `:` = amud b; one header in the census lacks its trailing space).
4. **Paragraph** — one line under its header; blank lines between. The
   marker lines `גמ'` / `מַתְנִי'` appear irregularly (a few dozen in the Shas).
5. **Corrections lists** — two Word files (`Berakhot/תיקונים - מסכת ברכות.docx`,
   `Shabbat/תיקוני מסכת שבת.docx`).
6. The repo `README.md` (license + project note; not a text grain).

The adapter takes the **tractate** as the document and the **paragraph
line** as the passage, cited `<daf><a|b>.<n>`. The **male** file is the
passage text; the line-aligned **haser** line rides the passage's
`ktiv_haser` annotation wherever it differs. Rejected grains, each pinned
here and skipped by rule (`discovery_skips`):

| file | grain | rule |
|---|---|---|
| `Meila/מעילה.combinedfull{maleh,haser}.txt` | duplicate tractate directory | `DictaBavli::DUPLICATE_DIRS` (Meila duplicates Meilah) |
| `Berakhot/תיקונים - מסכת ברכות.docx` | corrections list (Word) | every `.docx` |

## The trim

Each text file keeps its LEADING lines, byte-identical (both spellings cut
at the same line, so the alignment holds):

| tractate | lines kept | content | why it is here |
|---|---|---|---|
| `Berakhot` | 28 | 2a (5 paragraphs), 2b (6), 3a (7) | the Shas opening; the `גמ'` marker line |
| `Tamid` | 20 | 25a (3), 26a (10) | a tractate that does not start at 2a; upstream's own amud gap |
| `Meilah` | 18 | 2a (14) | the kept copy of the duplicated pair |
| `Meila` | 18 | 2a (14) | the rejected duplicate (identical bytes) |

The docx is whole (30,984 B).

## Census (all 76 files, 2026-11-16)

37 tractates (Meila excluded) → 78,782 paragraph lines (= expected
passages), 61,896 of which differ between the spellings; haser total
28.2 MB. Reconciliation: 38 directories = 37 documents + 1 duplicate
skipped by rule; 78 files = 74 texts + 2 duplicate texts + 2 .docx.
