# th-wikisource fixtures

Real api.php captures from th.wikisource.org, retrieved 2026-10-12,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + "cone" + "indexes"
(each named Index's title/pageid/revid and stated fields, verbatim) +
"html" (`action=parse&oldid=<revid>`) and "page_quality" (the
ProofreadPage level histogram) on admitted pages):

- `pages/80299.json` — ประชุมพงศาวดาร/ภาคที่ 5/เรื่องที่ 3: the part 5
  print (ปี=2460 → 1917 CE, ผู้เผยแพร่=โบราณคดีสโมสร), Page: level 1 —
  ADMITTED. Whole.
- `pages/41644.json` — ประชุมพงศาวดาร/ภาคที่ 53 (2473): ปี=2473 → 1930
  CE, the last admitted year — ADMITTED. Whole.
- `pages/41645.json` — ประชุมพงศาวดาร/ภาคที่ 53 (2476): the same part's
  BE 2476 (1933) reprint — EDITION_TAINT_POST_1930. Whole; no rendering.
- `pages/14632.json` — ประชุมพงศาวดาร/ภาคที่ 56: BE 2475 (1932) —
  tainted. Whole; no rendering.
- `pages/40870.json` — ประมวลกฎหมายรัชกาลที่ 1 จุลศักราช 1166/เล่ม 1/ส่วน 2:
  the Three Seals Law in Lingat's BE 2482 (1939) edition — tainted.
  Whole; no rendering.

Re-cut: run the adapter's own fetch into a scratch directory (never
canonical/) and copy the envelopes — or by hand: prop=revisions
(rvslots=main), prop=revisions on each `<pages index>` Index
(redirects=1), action=parse with oldid=<revid> for admitted pages,
prop=templates (tlnamespace=250) + prop=proofread for the levels.
