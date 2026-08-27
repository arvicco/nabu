# Trismegistos Geo — manual acquisition

The papyrological world's places database (trismegistos.org/geo),
ingested as a gazetteer feature module. TM's dump service fails the
automation bar (measured 2026-08-08): the Geo table dump is a browser
POST form that answered a scripted POST with 0 bytes, and the site
serves a captcha "Security Check" interstitial. A human acquires the
dump in a browser; `nabu sync trismegistos-geo` then ingests the drop.

This document is the human companion of the adapter's in-code
instruction card (`Nabu::Adapters::TrismegistosGeo.manual_acquisition`);
the two must agree, and the suite pins it.

## Steps

Get it from: <https://www.trismegistos.org/dataservices/>

1. Open the URL in a browser and solve the captcha ("Security Check")
   if served
2. Find the Geo table dump form (dump.php?serve=geo) and tick EVERY
   offered field
3. Download as CSV, and as JSON too if offered (it carries the nested
   name variants)
4. Save the files as TM_geo.csv / TM_geo.json and drop them as listed
   below

Route re-verified 2026-08-27: the dataservices page links a "table
dump" page (`/dataservices/tabledump/`) that still carries the
`dump.php?serve=geo` form with per-field checkboxes.

Why "tick EVERY offered field" matters: a partial tick silently loses
columns for a whole acquisition cycle — the dump is the canonical
asset until the next re-acquire.

## License capture

The dataservices page states the grant — verbatim as of 2026-08-07,
re-seen 2026-08-27: *"We offer you open access to our data on a
CC BY-SA 4.0 license."* Confirm that sentence (or whatever has
replaced it) at acquisition time and note the date; the manifest
records it verbatim (`license_class: attribution`).

Also re-check the form itself: the `pleiades_id`/`geonames` checkboxes
were commented out upstream (verified in page source 2026-08-08). If
they have returned, tick them too — they would upgrade this shelf to
crosswalk-bearing (crosswalks currently come from CIGS columns + the
Wikidata harvest, never from this dump).

## Expected files

Drop into `incoming/trismegistos-geo/` (top-level, beside
`canonical/`, gitignored):

| File | Required | Shape |
|---|---|---|
| `TM_geo.csv` | yes | the Geo table dump, CSV — the canonical asset; header starts `"id","country"`; ~10 MB, 64,857 rows at the 2026-08-08 acquisition |
| `TM_geo.json` | optional | the same dump as GeoJSON (a `FeatureCollection`; carries the nested name variants); ~40 MB |

A saved captcha page or truncated download is refused by the sync's
sniff (the CSV must start with the `"id","country"` header; the JSON
must be a `FeatureCollection`) — the refused drop is never consumed.

## Ingest

Run `bin/nabu sync trismegistos-geo`. The drop is validated, any
previous holding is atticked (`canonical/trismegistos-geo/.attic/`),
the files are MOVED into `canonical/trismegistos-geo/`, and
`.manual-fetch.json` provenance is stamped (per-file sha256,
acquisition mtime, ingest time, upstream URL). Byte-identical re-drops
are no-ops; your copy in `incoming/` is never deleted.

## Refresh

The gazetteer changes slowly — re-acquire on demand; check whether the
form's disabled pleiades_id/geonames checkboxes have returned (they
would upgrade this shelf to crosswalk-bearing).
