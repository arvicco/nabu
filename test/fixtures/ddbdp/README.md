# DDbDP (Papyri.info) fixtures

Real, untrimmed EpiDoc documents from the Duke Databank of Documentary Papyri via
the Papyri.info `idp.data` repo (CLAUDE.md fixture rules). All files are small and
kept **whole** — no trimming.

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
