# te-wikisource fixtures

Real api.php captures from te.wikisource.org, retrieved 2026-10-21,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext verbatim + the fetch's "cone"
provenance + "indexes" (each named Index page's title/pageid/revid and
its stated fields, verbatim) + "html", the `action=parse&oldid=<revid>`
rendering, and "page_quality", the ProofreadPage level histogram, only
on pages the rules admit).

Delivery grains upstream serves: the work tree (a root page + one
subpage per āśvāsa/prakaraṇa, each a `<pages index>` transclusion of a
scan), the Index (సూచిక:) page, the Page (పుట:) scan pages. The adapter
takes the ns-0 work page as the document; the Index rides as evidence,
the Page levels as the proofread histogram.

- `pages/188381.json` — బద్ది నీతులు/సేవకనీతిప్రకరణము (Baddena's
  Nītisāra, the 1917 Pithapuram print, Index సంవత్సరం=1917) — ADMITTED.
- `pages/188382.json` — బద్ది నీతులు/లోకనీతిప్రకరణము — ADMITTED.
- `pages/11230.json` — క్రీడాభిరామము/మొదటి భాగము: neither header nor
  scan states a year — the edition_unstated case. No rendering.
- `pages/173790.json` — భామినీవిలాసమ్ (Jagannātha, 1902): Sanskrit in
  Telugu script — the censused sanskrit_overlap exclusion. No rendering.
- `pages/109900.json` — హరివంశము/విజ్ఞప్తి: the publisher's notice
  (apparatus). No rendering.
- `pages/41557.json` — వేమన పద్యములు (సి.పి.బ్రౌన్)/ప్రథమ భాగము: the
  header's అనువాదం= names C. P. Brown (translation). No rendering.

All whole. Re-cut: run the adapter's own fetch into a scratch directory
(never canonical/) with its cone narrowed to these titles and copy the
envelopes — or by hand: prop=revisions (rvslots=main) for the page,
prop=revisions on each `<pages index>` Index (redirects=1),
action=parse with oldid=<revid> for admitted pages, prop=templates
(tlnamespace=104) + prop=proofread for the levels.
