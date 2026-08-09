# trismegistos-geo fixtures

Trimmed from the REAL Trismegistos Geo table dump the owner acquired
manually on 2026-08-08 (browser session — the dump service sits behind
a captcha interstitial and a POST form, which is WHY this source runs
the Manual Adapter pattern; see docs/architecture.md and the P63 plan).

- Upstream: https://www.trismegistos.org/dataservices/ →
  `dump.php?serve=geo`, all 15 live fields ticked, CSV + JSON formats.
  (The form's `pleiades_id`/`geonames` checkboxes are commented out
  upstream — the dump carries NO crosswalk ids; verified 2026-08-08.)
- License (dataservices page, verbatim): "We offer you open access to
  our data on a CC BY-SA 4.0 license."
- `TM_geo.csv`: header + 10 real rows (ids 1, 4, 5, 10, 100, 604,
  1767, 2355, 2788, 3311) preserving the full dump's structural
  quirks: every line ends `";` (semicolon AFTER the closing quote),
  multilingual name columns, empty-string absences, the "ghost name"
  status, rows with and without coordinates.
- `TM_geo.json`: the dump's GeoJSON FeatureCollection trimmed to 4
  real features (ids 1, 100, 1767, 2788) with the nested `names`
  object and per-place `uri` intact.

Full dump: 64,857 rows / 10 MB CSV + 40 MB JSON. Never hand-edit
these files; re-trim from a real dump instead.
