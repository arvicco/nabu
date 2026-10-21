# br-wikisource fixtures

Real api.php captures from br.wikisource.org, retrieved 2026-10-21, in
the adapter's own envelope shape (`pages/<pageid>.json`: verbatim
revision + "cone" + "indexes" (each named Meneger page's stated fields)
+ "html" and "page_quality" on admitted pages only).

Delivery grains upstream serves: the ns-0 text page (a song, a saint's
life, a chapter — or an "/a-bezh" page carrying the whole book again),
the Meneger (scan Index) page, the Pajenn (scan page). The adapter
takes the ns-0 page; "/a-bezh" is a rejected grain (aggregate), pinned
below.

- `pages/24543.json` — Buhez ar Sent/1837/Odilon: Marigo's Buez ar
  Saent (Kemper 1837) — ADMITTED.
- `pages/16516.json` — Barzhaz Breizh/1846/Ann eostik: the 1846 Barzaz
  Breiz, the song spanning the two volume scans — ADMITTED.
- `pages/123.json` — Santes Henori: Luzel's Gwerziou Breiz-Izel (An
  Oriant 1868) — ADMITTED.
- `pages/32386.json` — Barzhaz Breizh/1846/a-bezh: the whole-book page
  (aggregate). No rendering.
- `pages/60077.json` — Ar Baro Bleun: Jezegou's 1906 Ar Vro story —
  after_cone. No rendering.
- `pages/27457.json` — Chansons et danses des Bretons (Quellien 1889):
  the book's root page, French prose — measured foreign_language.
  TRIMMED: its rendering (143,292 characters) is cut at the first
  `</p>` after 12,000 characters and the two wrapper divs re-closed
  (48,371 characters kept); the page class is unchanged.

Re-cut: the adapter's own fetch into a scratch directory (never
canonical/) with its cone narrowed to these titles — or by hand
(prop=revisions; the Meneger pages; action=parse oldid=<revid>;
prop=templates tlnamespace=102 + prop=proofread).
