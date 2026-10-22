# su-wikisource fixtures

Real api.php captures from su.wikisource.org, retrieved 2026-10-21, in
the adapter's own envelope shape (`pages/<pageid>.json`: verbatim
revision + "cone" + "indexes" (each named Indéks page's stated fields)
+ "html" and "page_quality" on admitted pages only).

Delivery grains upstream serves: the ns-0 text page (a book, a chapter
subpage, a Cacarakan-script twin subpage, or one text extracted from a
journal volume — TBG, Verhandelingen, Bijdragen), the Indéks (scan
Index) page, the Kaca (scan page). The adapter takes the ns-0 page.

- `pages/12457.json` — Wawatjan Katrangan Miara Laoek Tjai/Bab Bibit
  (Moehamad Oemar, 1866) — ADMITTED, Latin script.
- `pages/12797.json` — Kitab Dongéng-Dongéng nu Aranéh/X (Muhamad Musa,
  1866) — ADMITTED, Sundanese in Javanese script (measured sun-Java).
- `pages/98.json` — Tijdschrift voor Indische Taal- Land- en
  Volkenkunde, LXVI/De Tjarita Parahijangan: the 1926 TBG text (the
  censused EXTRA_INDEXES print) — ADMITTED, pinned to osn.
- `pages/16.json` — Badoejsche Pantoenverhalen/Inleiding: Meijer's 1891
  Dutch introduction — measured foreign_language (rendered, then
  skipped).
- `pages/47.json` — Poesaka Soenda 1922-07-1(01): a 1922 issue —
  after_cone. No rendering.

All whole. Re-cut: the adapter's own fetch into a scratch directory
(never canonical/) with its cone narrowed to these titles — or by hand
(prop=revisions; the Indéks pages; action=parse oldid=<revid>;
prop=templates tlnamespace=250 + prop=proofread).
