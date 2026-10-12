# ms-wikisource fixtures

Real api.php captures from ms.wikisource.org, retrieved 2026-10-12,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + "cone" + "indexes"
(each named Index's title/pageid/revid and stated fields, verbatim) +
"html" (`action=parse&oldid=<revid>`) and "page_quality" (the
ProofreadPage level histogram) on admitted pages):

- `pages/1928.json` — Hikayat Aceh (Leiden Or. 1954): header year
  "abad ke-17", Index Year 1700; ONE level-1 Page: page with text of the
  142 the `<pages>` range names (the rest not yet created — the
  rendering carries one red-link placeholder per missing page). Whole.
- `pages/4196.json` — Hikayat Pelanduk Jenaka (Or. 1932): Index Year
  1718, levels 0/1/3/4. Whole.
- `pages/6478.json` — Syair Perahu (MSS Malay A2): Rencong (Rejang
  block) lines interleaved with a Latin transliteration, header
  author Hamzah Fansuri, year 1700. Whole.
- `pages/6916.json` — Tafsir Yā Ayyuha an-Nâs: the WM ID 010 0014 root,
  header year=1949 — the EDITION_TAINT_POST_1930 case. Whole; no
  rendering.
- `pages/6918.json` — Tafsir Yā Ayyuha an-Nâs/10: a subpage of the same
  series stating no year — the series-wide EXCLUDED_INDEXES case.
  TRIMMED: the capture predates the exclusion, so its "html" and
  "page_quality" keys were dropped (an excluded page is never rendered).

Re-cut: run the adapter's own fetch into a scratch directory (never
canonical/) and copy the envelopes — or by hand: prop=revisions
(rvslots=main), prop=revisions on each `<pages index>` Index
(redirects=1), action=parse with oldid=<revid> for admitted pages,
prop=templates (tlnamespace=250) + prop=proofread for the levels.
