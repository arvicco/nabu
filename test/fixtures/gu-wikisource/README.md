# gu-wikisource fixtures

Real api.php captures from gu.wikisource.org, retrieved 2026-10-12,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "indexes" (each named Index page's title/pageid/revid and
its stated fields, verbatim) + "html", the `action=parse&oldid=<revid>`
rendering, and "page_quality", the ProofreadPage level histogram, only
on pages the rules admit):

- `pages/8229.json` — ટળતો ટળતો હીંડીશ મારે (Narsinh Mehta): one pada
  transcluded from Bruhad Kavyadohan Granth 1 (વર્ષ=1908, સંપાદક=
  ઈચ્છારામ સૂર્યરામ દેસાઈ), Page: level 3 (proofread) — ADMITTED. Whole.
- `pages/64.json` — અખાના છપ્પા/આભડછેટનિંદા અંગ (Akho): a section-range
  transclusion from the same Index, Page: level 1 — ADMITTED. Whole.
- `pages/12209.json` — મીરાં ભક્તિ કરેરે પ્રકટકી (Mirabai): transcluded
  from the Meerabai Lekhan scan, whose Index states NO year — the
  edition_unstated case (REQUIRE_EDITION_YEAR). Whole; no rendering.
- `pages/7415.json` — મામેરૂં (Premanand): the Mameru.pdf Index's
  વર્ષ=1683 is the composition year, not a print — a censused
  EXCLUDED_INDEXES case. Whole; no rendering.

Re-cut: run the adapter's own fetch into a scratch directory (never
canonical/) and copy the four envelopes — or by hand: prop=revisions
(rvslots=main) for the page, prop=revisions on each `<pages index>`
Index (redirects=1), action=parse with oldid=<revid> for admitted
pages, prop=templates (tlnamespace=104) + prop=proofread for the levels.
