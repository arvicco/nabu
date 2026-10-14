# DDbDP (Papyri.info) fixtures — quarantine-class exemplars (P5-1, P6-2)

Real EpiDoc documents for the P5-1 restart-aware minting fix and the P6-2
cancelled-document class. First copied 2026-07-04 from the locally synced
canonical snapshot; **re-cut 2026-10-14** in upstream's post-switchover
layout, byte-identical to the blobs of upstream commit
`8f7ed7085c4ed9055c239800286d3a6c3bc2a79f` (master, 2026-10-13; original
upstream: [papyri/idp.data](https://github.com/papyri/idp.data)), extracted
from the git objects already fetched into `canonical/papyri-ddbdp/.git`.
All files are small and kept **whole** (CLAUDE.md fixture rules: real
upstream samples, structurally intact, never hand-written). Each re-cut file
parses to exactly the urn, passages and outcome its pre-switchover
predecessor did.

The clean-parse fixtures and the conformance workdir live in
`test/fixtures/ddbdp/`; this directory holds the quarantine-class exemplars.

- **Layout:** mirrors upstream under `DDbDP/<HGV-thousand>/<HGV>.xml` and
  `Historical/<collection>/(<volume>/)?<number>.xml`.

## Files (whole)

| Path | ddb-hybrid | Class it exemplifies |
|---|---|---|
| `DDbDP/25/25457.xml` | `aegyptus;89;240` | **Line-number restart** (12,288 docs at the 2026-07-04 sync): one flat `<ab>`, NO textpart divs, `<lb n="1"/>` twice (lost-line marker block, then main text 1–11) and `<lb n="11"/>` twice → duplicate passage urns before P5-1. Now mints implicit blocks `:1`, `:b2:1`…`:b2:11`, `:b3:11`. |
| `Historical/aegyptus/89/240.xml` | `aegyptus;89;240` | The same edition's **historical copy**, also text-bearing: pins the discover precedence (the curated `DDbDP/` copy wins; one urn, one ref). |
| `Historical/chrest.wilck/101.xml` | `chrest.wilck;;101` | **Text-less stub** (9,351 docs at the 2026-07-04 sync): literally empty `<ab/>`; the body `<ref type="reprint-in">` points at the republication (P.Enteux. 13). The parser must KEEP refusing it ("no citable lines"); the adapter now skips such stubs at discover. Upstream no longer carries this hybrid in `DDbDP/` at all. |
| `DDbDP/73/73640.xml` | `o.claud;3;457` | **Cancelled-but-legible document** (P6-2, ~40 docs): every line sits inside `<del rend="erasure">` — an ancient cancellation, fully legible and fully edited; renders in Leiden double brackets `⟦…⟧` with a `"cancelled"` annotation. |

## License (recorded exactly)

Per-document `<availability>` (identical in all four):
> © Duke Databank of Documentary Papyri. This work is licensed under a
> Creative Commons Attribution 3.0 License.

license_class `attribution`.
