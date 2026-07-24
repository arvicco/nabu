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
