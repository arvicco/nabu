# Places of the library

The third dimension, after language and time. As of **2026-08-09**:
**585,682 documents carry a machine place reference** (708,905 name a
place; ~977,000 documents total as of the P77 census) — 151,157 before the places program.
The public summary of this page is site/places.md; this is the
maintained original, in the docs/languages.md mold.

## The system, in five rules

1. **Gazetteers are held, never queried live.** Each is a canonical
   asset with provenance (Pleiades — quarterly/daily dump, CC BY 3.0;
   Trismegistos Geo — a Manual Adapter acquisition, CC BY-SA 4.0; CIGS —
   one Zenodo-pinned CSV, CC BY 4.0), derived wholesale into the
   namespaced place index (`place_index`, keyed `(gazetteer, place_id)`;
   migration 025). Deriving one gazetteer's slice never touches
   another's.
2. **Namespaces are parallel; crosswalks are data.** `tm:2788` and
   `pleiades:579885` are independent claims about Pompeii. Equivalences
   live in `place_crosswalk` with per-row provenance — CIGS's own
   columns (source `cigs`) and a Wikidata P1958⇄P1584 harvest (source
   `wikidata`, in the registry's crosswalks.csv) — never inferred.
3. **Matching decisions are registry rows, not heuristics.** The
   [nabu-places](https://github.com/arvicco/nabu-places) sibling maps
   each source's VERBATIM name strings to refs (`names.yml`), with
   `unlocatable` / `region` / `ghost` / `rejected` as first-class
   answers and `alias_of` for upstream `?`-variants. An unlisted name
   is honestly unmatched (identity-default). No fuzzy matching exists
   anywhere in the pipeline.
4. **Adapter-asserted refs always win.** `nabu place apply` projects
   matched decisions into `document_axes.place_ref` on NULL rows only;
   upstream-captured references (edh, papyri, isicily…) are never
   overwritten, and canonical bytes are never rewritten (defective
   upstream ids — 12 known, digit-mangled or superseded — stay flagged
   by the `unresolvable_place_refs` invariant rather than silently
   repaired). Apply is idempotent, censused, probe-guarded, and re-run
   by `nabu rebuild` after the timeline lanes — db/ stays a pure
   function of canonical/, registry included.
5. **The registry can mint places of its own.** Where text-analysis
   scholarship establishes a place no gazetteer registers, `places.yml`
   records it under the `np:` namespace with a REQUIRED evidence trail;
   minted records derive into the index like any gazetteer's rows.

A sixth rule joined with the uncertainty doctrine (P76): a decision's
`certainty: low` and the cataloguer's trailing `?` are **rendered, never
dropped** — the three-tier vocabulary and the render axiom live in
[conventions §12](conventions.md#12-uncertainty--three-tiers-rendered-never-stored-p76-r-6),
`Nabu::Certainty` owns the mapping.

## The namespaces held

| Namespace | Rows | Asset |
|---|---:|---|
| `pleiades:` | 42,284 | canonical/pleiades (dump refreshed 2026-08-09) |
| `tm:` | 64,857 | canonical/trismegistos-geo (owner-acquired 2026-08-08) |
| `cigs:` | 598 | canonical/cigs (Zenodo v1.7) |
| `np:` | 0 | the native minting lane (new) |
| crosswalk | 3,438 | cigs 1,330 + wikidata 2,108 |

## Coverage after the P63/P64 waves

registry 550 decision rows / 7 sources. Axis rows with refs: cdli
250,484/337,572 (from zero) · oracc 101,983/117,419 · edr
99,249/115,590 (144 unique matches + 28 homonym rulings; Atina, Forum
Novum and Potentia honestly rejected — multiple Italian homonyms inside
corpus scope) · edh 73,507 (upstream) · papyri-ddbdp 49,030 (upstream +
German-exonym aliases) · elephantine 3,690/7,973 · iip 1,828/5,499 ·
ceipom 1,036 (float-mangled TM GeoIDs restored to `tm:` at the axis).

Postures (config/postures.yml, places layer): linked with measured
notes for the applied sources; named where only strings exist; region
bins (aes) recorded as registry `region` rows.

## Surfaces

`nabu place NAME|ID` (the desk card: gazetteer facts + per-source
holdings + unlinked-mention tail) · `nabu place apply` (the projection)
· MCP `nabu_place` · the timeline/axis filters read findspot and date
off the same `document_axes` row. The health invariants hold the layer:
`unresolvable_place_refs` (per-namespace, both URL and mint spellings)
and `registry_orphan_names` (era-bound census discipline on the
registry itself).
