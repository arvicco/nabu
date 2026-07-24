# trismegistos fixtures — TexRelations crosswalk

Real Trismegistos dataservices responses, retrieved **2026-07-24** from

    https://www.trismegistos.org/dataservices/texrelations/<ID>

- `102617.json` — TM text 102617. Non-null partners: `PHI` (`228245`),
  `CPI` (`CPI-093`). No held-source partner (ISic/EDH/DDBDP all null) —
  exercises the Type-A-only (external crosswalk, no internal edge) path.
- `175903.json` — TM text 175903. Non-null partners: `EDH` (`HD007132`),
  `EDCS` (`09300551`). `EDH` is a HELD nabu source (`urn:nabu:edh:hd007132`),
  so this file drives the internal same-stone cross-source edge test
  (`urn:nabu:isicily:…` ↔ `urn:nabu:edh:hd007132`) when the catalog holds
  the edh witness and the links journal carries the isicily→`tm:175903`
  concordance edge.

Each response is a JSON array of one-key objects: the first is
`{"TM_ID": ["<id>"]}`, then one per partner project (80+), value
`null` / string / array. Trimmed: none — these are verbatim upstream
responses (~6 KB each).

License (quoted from the dataservices page, 2026-07-24): "open access to
our data on a CC BY-SA 4.0 license" → class `attribution` (the house
BY-SA posture — share-alike is a downstream-licensing duty, not a serving
gate; see `config/sources.yml`).
