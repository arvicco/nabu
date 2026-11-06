# statutes-realm fixtures

Trimmed real pages from British History Online's **Statutes of the Realm**
(ed. John Raithby, Great Britain Record Commission, vols 5–6 1819, vol 7
1820), retrieved **2026-11-05** by direct HTTP GET, paced ~1 request/s, from
`https://www.british-history.ac.uk/statutes-realm/…`. Every page states
"This free content was digitised by double rekeying. Public Domain."

The tree mirrors the fetch layout (`Nabu::StatutesRealmFetch`):

| file | upstream URL | grain |
|---|---|---|
| `toc/vol5-page-0.html` | `/statutes-realm/vol5?page=0` | TOC page — rows kept: `p1` (engraving), `iii-iv` (preface), `v-xix` (chronological table), `p1a`, `pp255-259`, `pp421-422` (acts; the last row rides here from the live vol5 TOC's page 1) |
| `toc/vol5-page-3.html` | `/statutes-realm/vol5?page=3` | TOC page (the volume's last) — row kept: `pp24-25` (Index: F) |
| `toc/vol7-page-1.html` | `/statutes-realm/vol7?page=1` | TOC page — row kept: `p641a` (act) |
| `toc/vol7-page-2.html` | `/statutes-realm/vol7?page=2` | TOC page (the volume's last) — rows kept: `p750` (The Private Acts), `pp3-5` (Index: A) |
| `vol5/p1a.html` | `/statutes-realm/vol5/p1a` | act — Charles I, 1625, the Lord's Day Act (one section, a footnote) |
| `vol5/pp255-259.html` | `/statutes-realm/vol5/pp255-259` | act — Charles II, 1660, the beer-and-ale excise grant; **trimmed to sections s1–s3** (s1 carries the rate table) and the three footnotes they anchor |
| `vol5/pp421-422.html` | `/statutes-realm/vol5/pp421-422` | act — Charles II, 1662, the Butter Act; its heads anchor **page-wise** (`h2-p1`, `h3-p2`, …) instead of `hN-sK` — retrieved 2026-11-06 after the live sync quarantined it; **trimmed to sections p1–p3** and the two footnotes they anchor |
| `vol7/p641a.html` | `/statutes-realm/vol7/p641a` | act — William III, 1700 & 1701, with the rekeyed citation "Rot. Parl. 12 § 13 Gul. III" |
| `vol7/p750.html` | `/statutes-realm/vol7/p750` | private-acts schedule — the roll's Latin formula + two private-act titles |
| `vol5/p1.html` | `/statutes-realm/vol5/p1` | engraving plate page — a REJECTED grain's own page, on disk but never minted |

Trimming: each file keeps the page's `<main>` element verbatim (scripts
dropped) inside a minimal document shell; TOC pages keep only the listed
`<tr>` rows, their pagers intact; `pp255-259` drops sections s4–s29 and the
footnotes only those anchored. Nothing is rewritten.

## Delivery grains (every grain upstream serves, enumerated 2026-11-05)

Census over all three live volume TOCs (vol5 4 pages, vol6 2, vol7 3; 100
rows a page): **723 rows** — vol5 311 · vol6 192 · vol7 220.

| grain | rows | taken? | specimen here |
|---|---:|---|---|
| act page ("<Reign>, <session>: <title>") | 656 (291 · 172 · 193) | **the document** | `vol5/p1a`, `vol5/pp255-259`, `vol7/p641a` |
| private-acts schedule ("<Reign>, <session>: The Private Acts", vol 7 only) | 5 | **document** (roll text) | `vol7/p750` |
| index letter ("Index: A" …) | 53 (16 · 19 · 18) | rejected by rule | rows `pp24-25`, `pp3-5` |
| front matter (Preface; Chronological table) | 5 (2 · 1 · 2) | rejected by rule | rows `iii-iv`, `v-xix` |
| engraving plate ("Engraving: …") | 4 (2 · 0 · 2) | rejected by rule | row + page `p1` |
| TOC page itself | 9 | the manifest; sidecar skipped by rule | `toc/*.html` |
| volumes 1–4 | — | not served: `/statutes-realm/vol1` … `vol4` → 404 (also `vol8`) | — |
| images (plates, `/sites/default/files/…`) | — | never fetched | — |

656 + 5 accepted + 62 rejected = 723 = upstream's own rows; residue 0.

## Upstream quirks these files document

- **Rekeying losses**: the contraction marks of the record type were
  dropped — "enaed" (enacted), "Cmons" (Commons), "coon Playes" (common) in
  `p1a`; kept verbatim (canonical means canonical).
- **Footnote markers** `(fn. N)` inline, the same note anchored repeatedly
  (`p641a`: fn. 1 three times); MS sigla in the notes ("Constable *O*.").
- **Rekeyed citation slips** in vol 7 titles: "12 § 13 Gul. III" (`p641a`),
  elsewhere "12 £ 13", "7&7", "8c9" for "8 & 9".
- **A misheaded session**: BHO labels the 11 Will. III session (Nov 1699 –
  Apr 1700) "1698-9" while 20 of its 25 rows cite "Rot. Parl. 11 Gul. III".
- The only `lang` attribute is the page shell's `lang="en"`; the Latin roll
  formula in `p750` is unmarked.
- Robots: `/robots.txt` (read 2026-11-05) disallows only the Drupal shell
  paths (`/admin/`, `/search/`, `/user/…`, `/core/`, `/profiles/`); no
  crawl-delay.

Re-cut: GET the URLs above (paced), keep `<main>`, trim rows/sections as
listed.
