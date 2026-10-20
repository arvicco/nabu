# pleiades fixtures — per-place JSON + an assembled dump

Real Pleiades per-place JSON, retrieved **2026-07-24** from
`https://pleiades.stoa.org/places/<id>/json`:

- `pleiades-462492.json` — Sicilia (island); `reprPoint` `[14.05, 37.59]`
  (`[lon, lat]`), `placeTypes` `["island"]`, `locations`/`features` empty
  (time periods carried only by `names[].attestations[].timePeriod`).
- `pleiades-570685.json` — Sparta; `reprPoint` `[22.42, 37.08]`,
  four `placeTypes`, populated `locations` and `names` (time periods from
  both `names[].attestations[]` and `locations[].attestations[]`).

## `dump.json` — assembled, honestly

The Pleiades quarterly archival release (Zenodo, release 4.1, 2025-05-28)
ships one big dump whose **exact container** (GeoJSON `FeatureCollection`
vs a `@graph` array vs JSON-lines vs `.json.gz`) is not verifiable
offline. `dump.json` here is **assembled** by this project: a plain JSON
array `[<place-462492>, <place-570685>]` of the two per-place documents
above, unmodified. The per-ENTRY shape IS the dump's entry shape (each
place object is identical whether served standalone or inside the dump),
so the `Nabu::Pleiades` resolver is exercised against real entry data;
only the outer container is a stand-in. `Nabu::Pleiades.load` accepts an
array, a `{"@graph": [...]}` / `{"features": [...]}` object, a single
place object, or gzip of any of these — the real container is confirmed
at first sync (see `lib/nabu/adapters/pleiades.rb`).

License (quoted from the downloads page, 2026-07-24): "Creative Commons
Attribution 3.0 License (cc-by)" → class `attribution`.

## `tm-backlinks/pleiades-places.json` — the Trismegistos backlink sample

A TRIM of the held dump `canonical/pleiades/pleiades-places.json.gz`
(`https://atlantides.org/downloads/pleiades/json/pleiades-places-latest.json.gz`,
Last-Modified 2026-10-16, sha256
`d123ab92c10a09f9892a67a183f6145d370504e6ddd96f0941744f0b3b6c2ce6`;
cut 2026-10-20): the real `{"@context", "@graph"}` container with eight
real place entries, each trimmed to the keys `@type id uri title
description placeTypes reprPoint references` (`references` whole, values
unmodified). Chosen for their `trismegistos.org/place/<id>` references:
540639 Anthedon (TM 15743), 786123 Syene (TM 2207), 265963 Malaca
(TM 26184), 570467 Megalopolis (TM 1327), 265876 Consabura (TM 27183),
570685 Sparta (TM 2181), and 29492 + 569131178 — two places citing the
ONE TM place 5181 (the ambiguous claim the crosswalk withholds). Pairs
with `test/fixtures/edh/geography/` in `test/tm_pleiades_crosswalk_test.rb`.
Kept in its own subdir so the adapter tests' fixture-root workdir never
sees a second dump.
