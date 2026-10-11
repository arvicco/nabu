# Places of the library

The third dimension, after language and time. As of **2026-10-11**:
**585,928 documents carry a machine place reference** (781,900 name a
place; over 2.3 million documents in the library) — 151,157 before the
places program. The referenced set is concentrated where the upstream
or a registry decision supplies a findspot (the cuneiform, epigraphic,
and papyrological shelves); for metadata-less corpora the place lane
is the text-mining loop below, which writes review candidates, never
refs.

The public summary of this page is site/places.md; this is the
maintained original, in the docs/languages.md mold.

## The system, in five rules

1. **Gazetteers are held, never queried live.** Each is a canonical
   asset with provenance (Pleiades — quarterly/daily dump, CC BY 3.0;
   Trismegistos Geo — a Manual Adapter acquisition, CC BY-SA 4.0; CIGS —
   one Zenodo-pinned CSV, CC BY 4.0; CHGIS — the Harvard–Fudan
   temporal gazetteer dump, CC0; NRCT — one pinned CSV cut, CC BY 4.0;
   al-Ṯurayyā — a repository clone, data CC BY 4.0), derived wholesale into the
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

Row counts as of 2026-10-11:

| Namespace | Rows | Asset |
|---|---:|---|
| `pleiades:` | 42,379 | canonical/pleiades (the held dump) |
| `tm:` | 64,857 | canonical/trismegistos-geo (owner-acquired 2026-08-08) |
| `cigs:` | 598 | canonical/cigs (Zenodo v1.7) |
| `chgis:` | 81,292 | canonical/chgis — the China Historical GIS, the Han lane's gazetteer |
| `nrct:` | 80,502 | canonical/nrct — Heibonsha's historical gazetteer of Japan (via ROIS-DS/NII) |
| `thurayya:` | 2,331 | canonical/althurayya — the al-Ṯurayyā gazetteer of the early Islamic world |
| `np:` | 0 | the native minting lane (no minted places yet) |
| crosswalk | 3,438 | cigs 1,330 + wikidata 2,108 |

## Coverage

As of 2026-10-11 the registry holds 560 decision rows across 8 source
sections. Documents with refs, per source: cdli 250,484 (from zero) ·
oracc 101,983 · edr 99,249 (144 unique matches + 28 homonym rulings;
Atina, Forum Novum and Potentia honestly rejected — multiple Italian
homonyms inside corpus scope) · edh 73,507 (upstream) · papyri-ddbdp
47,947 (upstream + German-exonym aliases) · isicily 5,040 (upstream) ·
elephantine 3,690 · iip 1,828 · ceipom 1,036 (float-mangled TM GeoIDs
restored to `tm:` at the axis) · itant 502 · riig 421 · ogham 241.

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

## The mining loop (P96–P97) — the documented script

Text-mined place candidates for metadata-less corpora, the Han lane
first (kanripo × chgis is the flagship). Candidates are **review
fuel**: they live as `kind=place-candidate` edges in the links
journal, they never touch `place_ref` directly, and a re-run
supersedes cleanly — so the whole loop below is safely repeatable.
The precision rules (all censused, never silent): names under 2
characters never match; a name resolving to more than 3 places is
dropped as ambiguous; a name hitting more than 0.2% of scanned
passages is derived-stopped as a common word wearing a place's
clothes; `config/place_stop_names.yml` is the standing hand list.

The script, in order:

```
# 0 · Prerequisite: the gazetteer slice must be derived.
bin/nabu sync chgis                       # (or any place_index gazetteer)

# 1 · CENSUS (writes nothing) — read the derived stop list before
#     any real run. ~46 min per 4.5M-passage source; announced + ticked.
bin/nabu place mine kanripo chgis --dry-run

# 2 · MINE — census + write in one command (two full scans; ~92 min
#     at kanripo scale; the summary reports both counts and elapsed).
bin/nabu place mine kanripo chgis

# 3 · REVIEW — the aggregate report: candidates grouped by place,
#     ranked by document spread, ~1 min over 3.8M edges.
bin/nabu place mine report kanripo chgis --limit 30
#     Expect the HEAD to be common-compound false positives first
#     (和平, 空中, 雨露…) — each row prints its ready-to-paste
#     stop-list line and its place-card ref.

# 4 · RULE — paste the stop lines the head hands you (owner ruling):
#     config/place_stop_names.yml, under stop_names:.
#     A real place instead earns its np: decision through the
#     nabu-places registry (see rule 5 above), then `nabu place apply`.

# 5 · RE-MINE — the rerun supersedes the whole scope; stopped names
#     vanish, the report re-ranks, repeat 3–5 until the head is
#     places, not particles.
bin/nabu place mine kanripo chgis
bin/nabu place mine report kanripo chgis

# Spot-reads at any point:
bin/nabu links <passage-urn>        # the candidates on one passage
bin/nabu place chgis:hvd_<n>        # the place behind a candidate
```

Grain honesty: the report's exact document spread is computed over
the top 5×limit places by passage count (announced in its header) —
review works the head of the distribution, and the head is exactly
where the rulings are.
