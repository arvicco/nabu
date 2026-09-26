# DDbDP + DCLP (Papyri.info) fixtures

Real, untrimmed EpiDoc documents from the Duke Databank of Documentary Papyri —
and, since P104-3, the Digital Corpus of Literary Papyri — via the Papyri.info
`idp.data` repo (CLAUDE.md fixture rules). All files are small and kept
**whole** — no trimming.

- **Retrieved:** 2026-07-03, from `master` of
  [papyri/idp.data](https://github.com/papyri/idp.data) via
  `raw.githubusercontent.com`, base
  `https://raw.githubusercontent.com/papyri/idp.data/master/DDB_EpiDoc_XML/`.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P3-1).
- **Layout:** mirrors upstream under `DDB_EpiDoc_XML/<collection>/<volume>/`.

## Files (whole; sizes as fetched)

| Path (under `DDB_EpiDoc_XML/`) | Bytes | ddb-hybrid | HGV / TM |
|---|---|---|---|
| `bgu/bgu.1/bgu.1.102.xml` | 7,576 | `bgu;1;102` | 8877 / 8877 |
| `bgu/bgu.1/bgu.1.100.xml` | 5,509 | `bgu;1;100` | 8875 / 8875 |
| `c.epist.lat/c.epist.lat.10.xml` | 8,279 | `c.epist.lat;;10` | 78573 / 78573 |

## License (recorded exactly)

- **Repo:** CC BY 3.0.
- **Per-document `<availability>`** (identical in all three):
  > © Duke Databank of Documentary Papyri. This work is licensed under a
  > Creative Commons Attribution 3.0 License.
- license_class `attribution`.

## Structure notes (for the DDbDP parser, P3-6)

- **NOT CapiTainS:** no `__cts__.xml`, no `refsDecl`, no CTS URNs. This is a new
  parser family, not `EpidocParser` reuse.
- **Identity** via `<idno>` elements — types seen here: `filename`,
  `ddb-perseus-style`, `ddb-hybrid`, `HGV`, `TM`. URN minting uses the
  `ddb-hybrid` value → `urn:nabu:ddbdp:<ddb-hybrid>` (frozen once used).
  Note `c.epist.lat` has an **empty volume segment** (`c.epist.lat;;10`).
- **Citation** via `<lb n="…"/>` line-begin markers inside `<ab>` (the text body).
- Heavy documentary/Leiden markup to expect: `app`/`lem`/`rdg`,
  `choice`/`reg`/`orig`, `subst`/`add`/`del`, `gap` (+quantity), `supplied`,
  `unclear`, `expan`/`ex`, `handShift`. The parser implements the deferred Leiden
  text-extraction policy (keep lem+reg+supplied, drop rdg/orig/del, mark gaps).
- All three parse strict (Nokogiri) as fetched.

## P104-3 addition — the DCLP lane (cut 2026-09-26)

Four whole files copied byte-verbatim from the box's own canonical clone
(`canonical/papyri-ddbdp/DCLP/<TM-thousand>/<TM>.xml`; same upstream repo,
raw base `https://raw.githubusercontent.com/papyri/idp.data/master/DCLP/`),
preserving the upstream TM-sharded layout under `DCLP/`:

| Path (under `DCLP/`) | dclp idno → urn | Language | What it pins |
|---|---|---|---|
| `63/62952.xml` | `62952` → `urn:nabu:dclp:62952` | `la` → `lat` | Vergil, Aeneid I.1–3 on an ostracon (O.Claud. 1 190); duplicate `<lb n="1"/>` engages the P5-1 implicit restart block (`:b2:3`) |
| `65/64388.xml` | `64388` → `urn:nabu:dclp:64388` | `grc` | P.Harris 1 98 medical recipe; two textpart divs with per-part line restarts; expan/ex + num |
| `806/805566.xml` | `805566` → `urn:nabu:dclp:805566` | `grc` | Praxidicae curse text; the `tm;;`-hybrid file shape; `break="no"` line wraps |
| `317/316777.xml` | (skipped) | `cop` | A metadata-only catalog stub — SELF-CLOSED edition div, no transcription: pins the discover-side skip (12,571 of 14,842 upstream files have this shape) |

- **Identity**: `<idno type="dclp">` (numeric; = TM = filename =
  papyri.info/dclp/<n>) mints `urn:nabu:dclp:<n>`. NOT the `dclp-hybrid`:
  the hybrid is non-unique upstream — TM 60467 and TM 61136 both carry
  `<idno type="dclp-hybrid">p.hal;;5</idno>` (Odyssey 6 vs Odyssey 12,
  a live cataloguing defect, census 2026-09-26) — while the dclp number
  is unique across all 14,842 files (one non-numeric `hgvTEMP`
  placeholder skips defensively).
- **License** (per-document `<availability>`, identical shape to DDbDP):
  "© Digital Corpus of Literary Papyri. This work is licensed under a
  Creative Commons Attribution 3.0 License." — same CC BY 3.0 /
  `attribution` class as the DDbDP half.
- The same DdbdpParser family parses both corpora (Leiden policy shared
  verbatim); only the identity idno and urn namespace differ.
