# GPC — acquiring the open subset (manual drop)

Where from: supplied by the GPC editors by email (gpc@geiriadur.ac.uk);
a site publication of the subset is upstream's announced future channel.

GPC's open-access subset comes from the Centre for Advanced Welsh &
Celtic Studies under **CC BY 4.0** and, as of the 2020 vintage,
travels **by email attachment** — there is no download URL yet. Two conditions ride the grant and are honored by the
adapter: no scraping/republication of the GPC website's HTML, and
users are pointed at GPC Online (every ingested entry carries its
permanent `gpc.html?gpcNNNNNN` URL).

## The drop, step by step

1. Request (or receive) the open-access subset xlsx from the GPC editors
   — a note to gpc@geiriadur.ac.uk is sufficient; the reply carries the
   workbook and its format specification.
2. Save the xlsx (and the format-spec PDF if supplied) as downloaded — no
   re-saving in Excel; the sha pin records the bytes as supplied:
   - `2020-09-03_GPC_Agored_UTF8.xlsx` (required — the subset)
   - `Welsh_ELEXIS_GPC_Open_Description.pdf` (optional — the spec)
3. Place them under `incoming/gpc/` in the library root.
4. Run `bin/nabu sync gpc`. The drop is validated (zip/PDF magic
   bytes), moved into `canonical/gpc/`, and sha-stamped in
   `.manual-fetch.json`; the parse then loads ~89,386 dictionary
   entries (a handful of id-less rows skip by rule).

## Refresh

A newer vintage — emailed or site-published — drops the same way; an
identical re-drop is a sha-verified no-op. If the announced site
publication appears, the adapter can grow an ordinary FileFetch and
this document retires.
