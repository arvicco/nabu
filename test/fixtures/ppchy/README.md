# ppchy fixtures — the Penn Parsed Corpus of Historical Yiddish

Real files from `github.com/beatrice57/penn-parsed-corpus-of-historical-yiddish`
(Beatrice Santorini, v1.0 2021), retrieved **2026-11-02** at main
`404082bfd935958878a687be990c6254ce01d149` (2026-10-29, "corrected an idom;
added a definition" — upstream corrects annotation weekly).

## License (verbatim, in-repo `LICENSE.rst`)

> The files in this repository are distributed under Creative
> Commons License Attribution-NonCommercial-ShareAlike 4.0 International
> CC BY-NC-SA 4.0 (https://creativecommons.org/licenses/by-nc-sa/4.0/).

The README repeats it and names the citation: "Santorini, Beatrice. 2021.
Penn Parsed Corpus of Historical Yiddish, v1.0." GitHub's license field
reads "Other" (NOASSERTION) — the in-file grant governs → class **nc**.

## Upstream's delivery grains (census of the whole repo at 404082bf)

| grain | what | verdict |
|---|---|---|
| `data/*.psd` | **63 parsed-text files** — 19,560 top-level forms = 17,861 sentence trees + 1,699 ID-less CODE marker blocks (`<BEGIN_…>`, `<P_n>`) | **ACCEPTED — the document grain** (one document per file, one passage per sentence tree) |
| `doc/sources/yiddish-sources-contents.html` | the per-text source record: Filename / Date / Dialect / Genre / Source / Notes / Catalog entries / Number of words + a `<!--PDF: …-->` page-image flag; 61 records naming exactly the 63 file stems (two records name a preface + main-text pair) | **MINED** (fetched, never a document) |
| `doc/sources/yiddish-sources-{list,frames}.html` | the frameset navigation over the same records | fetched with the cone, never read |
| `doc/pdf-images/*.pdf` | 44 page-image PDFs of the source prints (~400 MB; several shared between texts) | **REJECTED** (a scan grain — the text is the psd); outside the sparse cone; specimen `doc/pdf-images/1819e-khasid.pdf` (whole, 32 KB) |
| `doc/annotation-yiddish/*.html` | the annotation manual (guidelines, tag tables, the transliteration note) | **REJECTED** (documentation); outside the cone; specimen `doc/annotation-yiddish/index.html` (whole — upstream's frameset still titled "Syntactic annotation manual for Swiss German corpus", verbatim) |
| `other/` | Santorini 1989 and 1995, the Olsvanger 1947 glossary, Zaretski's transliterated grammar excerpts | **REJECTED** (scholarship about the corpus); outside the cone |
| `data/.DS_Store` | Finder litter inside `data/` | **skipped by rule** (not a parsed text; gitignored here, so the test writes a stand-in) |

Reconciliation: 63 accepted + 1 skipped by rule = the 64 entries under
`data/`; the sources page lists the same 63 stems (no residue either way).
The README advertises "roughly 200,000 words"; the page's per-text counts
sum to 206,392. A full parse of the 63 files at 404082bf: **63 documents /
17,861 passages, 0 errored**, every text dated, 17 placed.

## Files

| fixture | whole? | exercises |
|---|---|---|
| `data/1478w-letter-regensburg.psd` | whole (1,885 B) | the oldest dated Yiddish letter; 12 forms → 10 passages; `(CODE {TEXT:di})`; `*2s*`/`*arb*` empties; Hebrew `h^the` / `yomem^UNKNOWN` glosses; the underscore join (`fer_makhen`); ID `1478W-LETTER-REGENSBURG,156.3` → `:156.3` |
| `data/1620e-lev-tov-1-preface.psd` | TRIM — first 12 forms | the shared record's `Genre: Prose (preface), verse (main text)` resolving to Prose for the preface; `(N 0)` ellipsis; `IP-MAT=1` gapping indices |
| `data/1910e-grine-felder.psd` | TRIM — first 14 forms | `META` stage directions + speaker labels; `oyf@ @n` / `bay@ @m` split words; hyphenated names (`dovid-noyekhn`) that must NOT lemma-split; `Approx. 1910`; Genre Vernacular |
| `data/1xxxx-court-testimony.psd` | TRIM — upstream lines 1–70, 945–973, 1387–1428 | Rubashov's court-testimony items with their own date + dialect in the ID (`1_c1413_w`, `27_c1460_w?`, `37_1463_x`); a `<P_3_no_yiddish>` marker-only item; `vos shreybs@ @tu` with a `*T*-1` trace; 16 passages |
| `doc/sources/yiddish-sources-contents.html` | TRIM — head + catalogs table + the four texts' records | the mined record (entities `&uuml;`, `<ul><li>` notes, `<!--PDF: NO, BIRNBAUM-->`) |
| `doc/pdf-images/1819e-khasid.pdf` | whole | the rejected page-image grain → skipped by rule |
| `doc/annotation-yiddish/index.html` | whole | the rejected annotation-manual grain → skipped by rule |
| `LICENSE.rst`, `README.rst` | whole | the in-file grant + the citation / corpus description |

Source shas (whole upstream files, before any trim):

```
b40b9fc83556c641c4f2639b3eed21b28313b4c99421ba40b949c6ba90f32c6a  data/1478w-letter-regensburg.psd
19eadfaaec42218bcfb38ab4c821a9efbf0bf8b8c4f3a2bb342bfd5162932fee  data/1620e-lev-tov-1-preface.psd
81a4d522bc655d2ae62e664c0ba913706da4a186f0e0fcadff8b0c7876cad067  data/1910e-grine-felder.psd
9d31528112352b501d31587c761b62756cf3df5ae540eadec1a3f02e917d12b8  data/1xxxx-court-testimony.psd
7802384e2f545107e7aebbb772ea2f2db136a696639bd7f4cff0111e530ed882  doc/sources/yiddish-sources-contents.html
0c3cd678866d418245b3e9664fc283156b2d03882bdc464d82f546d44d34b38d  doc/pdf-images/1819e-khasid.pdf
efb57d64e9d8714ae9d5b86b2faf52bcbad2a335773740486f6623db208dba32  doc/annotation-yiddish/index.html
ab6d27f34e949abecf251276c29f0d8c4775b23c369ea5ec0e1c3e8b09a9db39  LICENSE.rst
607c53cf61651fe3897b6f3ba35694cfa81b05d53c0a8a33d613386c476af854  README.rst
```
