# RSTI fixtures — Ras Shamra Tablet Inventory (U. Chicago OCHRE/CORPUS)

Trimmed real API responses, retrieved **2026-07-31** during the P55-2 scout
(20 bounded probes against the granted resolver; grant by email, Miller Prosser,
U. Chicago CORPUS/OCHRE, 2026-07-27). Resolver URL shape — note the literal
`&format=json` with NO `?`, the granted, working form:

    https://pi.lib.uchicago.edu/1001/org/ochre/<uuid>&format=json

Layout mirrors `canonical/rsti/` exactly (menu + per-set + per-text files,
uuid-named), so `discover` walks this directory unchanged.

- `menu.json` — the "New TEO Menu of Sets" (entry uuid
  `4a7c67a2-6814-4e88-b24c-04db5ab2ad2a`), `items.set` trimmed from the full
  35 season/collection sets to 4 (Season 01, Season 19, Seasons 35-48,
  Ras Ibn Hani). Carries the menu-level `availability.license` credit line
  (Bordreuil & Pardee 1989) verbatim.
- `sets/2a414954-e077-496b-8b06-a9d0cd417eba.json` — Season 01, trimmed from
  106 `spatialUnit` inventory records to 4: **RS 1.001** (the one witnessed
  full edition), **RS 1.003+** (join label; text detail is the `{"result":[]}`
  tombstone), **RS 1.004** (shell: text item resolves but `sections` is `{}`),
  **RS 1.009 [A]** (bracket variant label; no text detail on disk — the
  "unfetched" path), plus — added 2026-07-31 after the first real sync —
  **RS 17.009** (verbatim from the live Season 17 set,
  `063495df-dbbd-4c9e-9b71-1c22302ed75b`): `associated_uuid`,
  `associated_desc` and `associated_alias` all arrive as `{}` (the XML
  self-closing form — no associated text exists), the shape that crashed
  stage-2 uuid collection live and now pins `uuid_of` + the "no-text"
  status.
- `sets/a7a3a86e-8cdb-4ea9-92fe-6dc31d07dcbc.json` — Ras Ibn Hani, trimmed
  from 238 records to 2: **RIH 77/01** (slash label, `description` is the
  empty-dict quirk `{}`), **RIH 84/ [31,10]** (slash + space + bracketed
  comma pair — the gnarliest witnessed label shape).
- `texts/de32293f-9b4b-435e-bf02-c4894863035b.json` — RS 1.001 text item,
  **whole** (the only witnessed full edition): four parallel renderings
  (transliteration / phonemic / graphemic with `&#x103xx;` HTML-entity
  Ugaritic cuneiform / empty translation), concordance aliases, Zotero
  bibliography, CC BY-NC-SA `availability.license`.
- `texts/3e80daf3-a394-4a0e-9f00-dd76392b3834.json` — RS 1.004 text item,
  whole: the SHELL shape (resolves, language Hurrian, `sections: {}`).
- `texts/223fa8f2-a5a6-47b0-9f82-80b159c1e23c.json` — the 13-byte
  `{"result":[]}` tombstone (HTTP 200): the API's well-defined "not
  published", byte-verbatim. ~8 of 10 scouted text probes returned exactly
  this — the inventory-first verdict.

## The line-model specimens (cut 2026-11-13 from the local canonical sync)

Real records + text items pinning the shapes the live corpus carries beyond
RS 1.001 (set records appended verbatim; text items byte-verbatim):

- Season 01 set + `RS 1.017` (`texts/bda5afe1…`): a counted lacuna
  (`region`, `missingLines: 8`) — line numbering resumes at Verso 22.
- Season 01 set + `RS 1.022` (`texts/120210e5…`): unlabeled lacuna regions
  (`missingLines: -1`, no label) and typographic-prime line labels (`1’`).
- Ras Ibn Hani set + `RIH 77/01` (`texts/e8e93bf6…`, the record already
  pinned above now resolves): `separator` rulings and "broken" regions
  between lines — before the line model these minted duplicate-urn and
  empty passages.
- Ras Ibn Hani set + `RIH 77/25+` (`texts/d9c1af5f…`): each surface holds
  one nested `section` per joined fragment (RIH 78/21, RIH 77/25).
- Ras Ibn Hani set + `RIH 83/02` (`texts/2ef071ab…`): the 38-byte bare XML
  declaration the resolver answered a `&format=json` request with — the
  empty answer.
- `sets/7e5dbd07…` (Season 15, trimmed to `RS 15.125`, `texts/8731a20f…`):
  transliteration lines at the rendering ROOT, no surface node.
- `sets/83bb804c…` (Season 08, trimmed to `RS 8.220`, tombstone
  `texts/dfcebd3b…`): Language property `<unassigned>` — OCHRE's explicit
  empty.
- `sets/b7ea3e39…` (Season 11, trimmed to `RS 11.850`, `texts/458102d8…`):
  an unlabeled trailing ruling on the Lower edge, and phonemic line 10 as
  mixed markup (`{"i" => "napḫaru šābū", "content" => 16}`).
- `quarantine/` (Season 17 trimmed to `RS 17.238`, `texts/39ba4c2f…`): every
  transliteration line is mixed markup flattened into `{i, content, sup}`
  lists — the quarantine specimen, outside the conformance workdir by
  design (`discover` walks only `sets/` at the workdir root).

Trimming was structural only (list members removed, remaining objects
untouched); the trimmed containers are re-serialized compact JSON, matching
the wire format. Raw scout snapshots (full seasons 01/19/24/35-48 + Ras Ibn
Hani, ~1.4 MB) stayed outside the repo.

License: CC BY-NC-SA 4.0 (the API's own `availability.license` on season
sets and text items), fetched under that grant (by email, 2026-07-27) with attribution.
