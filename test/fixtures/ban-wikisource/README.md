# ban-wikisource fixtures

Real api.php captures from ban.wikisource.org and commons.wikimedia.org,
retrieved 2026-10-12, written through the adapter's OWN envelope methods
(`index_envelope` / `fill_manuscript!` / `attach_scans!` driven against the
live API for the picked Index names) — `pages/<index pageid>.json`: the
Index page (title/pageid/ns/revid/timestamp/categories/wikitext verbatim),
`page_count` (Page-namespace pages upstream lists for it), `works` (the
main-namespace pages that transclude it, with their categories), and for
admitted manuscripts the Page-namespace `pages` (wikitext byte-verbatim,
Balinese script intact) and the Commons `scan` File page. Transcriptions
CC BY-SA 4.0 (site rightsinfo); scans as their Commons licence templates
state. One envelope per censused class:

- `568.json` — Bali-Lontar-Sukawati-Dharma Usada-36.jpg: single-image
  lontar, work category Lontar Basa Kawi (→ kaw), Gedong Kirtya class
  Agama, Lontar Sukawati; Commons campaign photograph {{self|cc-by-sa-4.0}}
  (whole).
- `24142.json` — Bali-lontar-paparikan-uwug-rusak-dwarawati-300ppi.pdf:
  Internet Archive scan ({{IA|paparikan-uwug-rusak-dwarawati}},
  {{PD-IDNoCopyright}}), Palmleaf Bot import; TRIMMED to Page-ns pages 1,
  56, 57 of 58 (page_count keeps the upstream 58).
- `1985.json` — Bali-lontar-Tojan-Geguritan Rajapala.jpg: the work carries
  BOTH Lontar Basa Bali and Lontar Basa Kawi (the conflict class → the
  Index Language= governs), Year=2020 campaign year, validated (level 4)
  (whole).
- `28568.json` — Kidung Panji Sumirang Or. 19.586.pdf: Leiden University
  Libraries, romanized (Latin-script) copy → ban-Latn; TRIMMED to page 10
  of 101.
- `28212.json` — Gaguritan Panji Semirang Or. 20.297.pdf: Leiden, pages at
  quality 0 with empty bodies → skip by rule (no text); TRIMMED to pages
  1–2 of 4.
- `32600.json` — Geguritan Mladprana.pdf: Year=1992 printed edition → the
  year rule (Index only; the rule never fetches its pages).
- `37583.json` — PEPARIKAN MAHABHARATA.pdf: Balai Bahasa printing outside
  the manuscript families, no Year= → printed (Index only).
- `37558.json` — Wikisource Loves Manuscripts - WM ID 001 0001 - Klungkung,
  Bali.pdf: a redirect Index → skip by rule (Index only).

Re-cut: run the adapter's envelope methods against the live API for these
Index names (Page-ns listing via generator=allpages gapprefix=<name>,
prop=info; works via the full main-namespace stage), keeping the stated
page subsets.
