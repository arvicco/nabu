# DDbDP (Papyri.info) fixtures — P5-1 quarantine classes

Real EpiDoc documents for the P5-1 restart-aware minting fix, copied
2026-07-04 from the **locally synced canonical snapshot**
(`canonical/papyri-ddbdp/`, first real sync of 2026-07-04; original
upstream: [papyri/idp.data](https://github.com/papyri/idp.data)). Both
files are small and kept **whole** — no trimming was needed; they are
byte-identical to the snapshot (CLAUDE.md fixture rules: real upstream
samples, structurally intact, never hand-written).

The pre-P5-1 fixtures (bgu.1.100, bgu.1.102, c.epist.lat.10 — the clean
parse cases and the conformance-suite workdir) live in
`test/fixtures/ddbdp/`; this directory holds the two 2026-07-04 sync
quarantine exemplars.

- **Layout:** mirrors upstream under `DDB_EpiDoc_XML/<collection>/(<volume>/)?`.

## Files (whole; copied from `canonical/papyri-ddbdp/DDB_EpiDoc_XML/`)

| Path (under `DDB_EpiDoc_XML/`) | ddb-hybrid | Quarantine class it exemplifies |
|---|---|---|
| `aegyptus/aegyptus.89/aegyptus.89.240.xml` | `aegyptus;89;240` | **Line-number restart** (12,288 docs): one flat `<ab>`, NO textpart divs, `<lb n="1"/>` twice (lost-line marker block, then main text 1–11) and `<lb n="11"/>` twice (line 11, then trailing lost-line marker) → duplicate passage urns before P5-1. Now mints implicit blocks `:1`, `:b2:1`…`:b2:11`, `:b3:11`. |
| `chrest.wilck/chrest.wilck.101.xml` | `chrest.wilck;;101` | **Text-less stub** (9,351 docs): literally empty `<ab/>`; the header `<ref type="reprint-in">` points at the republication (P.Enteux. 13). Must KEEP quarantining ("no citable lines"). |

## License (recorded exactly)

Per-document `<availability>` (identical in both):
> © Duke Databank of Documentary Papyri. This work is licensed under a
> Creative Commons Attribution 3.0 License.

license_class `attribution`.
