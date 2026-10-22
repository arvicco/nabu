# jv-wikisource fixtures

Real api.php captures from jv.wikisource.org, retrieved 2026-10-21, in
the adapter's own envelope shape (`pages/<pageid>.json`: verbatim
revision + "cone" + "indexes" (each named Indhèks page's stated fields)
+ "html" and "page_quality" on admitted pages only).

Delivery grains upstream serves: the ns-0 text page (on this wiki most
often a WHOLE BOOK on one page — a `<pages index>` over the full scan
range; the Gericke New Testament is split per book), the Indhèks (scan
Index) page, the Kaca (scan page). The adapter takes the ns-0 page.
Most of the wiki's 839 Indexes are OCR-only (no ns-0 page) and never
reach the adapter.

- `pages/21545.json` — Sakathahipun serat Prajangjéyan Énggal/Yudas:
  Jude from Gericke's 1848 New Testament, aksara Jawa — ADMITTED
  (measured jav-Java).
- `pages/676.json` — Kakawin Wṛttasañcaya (Hendrik Kern): Kern's 1875
  edition (the Indhèks states no Year; its file name "Wretansacaya (Kern
  1875).pdf" does) — ADMITTED, pinned to kaw.
- `pages/383.json` — Javaansch Nederduitsch Woordenboek (1847): the
  dictionary's Dutch front matter — measured foreign_language (rendered,
  then skipped).
- `pages/476.json` — Kajawen 041: a 1927 issue of the Balai Pustaka
  magazine — after_cone (outside the ≤ 1900 band). No rendering.

All whole. Re-cut: the adapter's own fetch into a scratch directory
(never canonical/) with its cone narrowed to these titles — or by hand
(prop=revisions; the Indhèks pages; action=parse oldid=<revid>;
prop=templates tlnamespace=250 + prop=proofread).
