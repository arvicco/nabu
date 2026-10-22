# etruscan-loans fixture

Trimmed REAL English Wiktionary MediaWiki API responses, retrieved
2026-10-22 from https://en.wiktionary.org/w/api.php — the inputs the
curation of `config/etruscan_loans.yml` read (the config itself is the
adapter's data, as config/sabellic_loans.yml is for sabellic-loans).

Requests (formatversion=2, format=json):

- `api/members-borrowed.json` — `action=query&list=categorymembers&
  cmtitle=Category:Latin terms borrowed from Etruscan&cmlimit=500&
  cmtype=page|subcat` (69 members at retrieval, all ns 0);
- `api/members-derived.json` — the same for `Category:Latin terms
  derived from Etruscan` (204 members: 199 ns-0 pages, 1 Reconstruction
  page, 4 subcategories — one of them the borrowed category itself);
- `api/revisions.json` — `action=query&prop=revisions&rvprop=
  content|ids|timestamp&rvslots=main&titles=…`, fetched in batches of
  50 titles; the kept page records merged into one response.

## Delivery grains

The API serves category member records (page / subcategory /
Reconstruction page) and page revisions. The curation takes the
main-namespace member as the row and its Latin etymology as the etymon
source; Reconstruction pages and subcategories are REJECTED (named in
the config header), specimens pinned here: `Reconstruction:Latin/piltrum`
and the borrowed category's own subcategory record.

## Cut

Member lists: the records of the ten kept pages (Ahala, Annaeus,
Aprilis, Aulus, autumnus, Caere, capus, Maso, Roma, titulo) plus the two
rejected-grain specimens, verbatim records in upstream order. Revisions:
the ten kept page records verbatim (whole wikitext), sorted by title.
The JSON is re-serialized compactly; record contents are unchanged.
They cover {{bor}}/{{der}}/{{bor+}} (with a leading named parameter)
and tr=, the {{ety|la|…}} template with and without <tr:…>, an earlier
"-" followed by a stated form, a form hidden in an HTML comment, an
"ett:-" unstated etymon, and a member whose Latin etymology carries no
Etruscan template (titulo, via titulus).

## Refresh

Re-run the three requests above and re-select the same titles.
