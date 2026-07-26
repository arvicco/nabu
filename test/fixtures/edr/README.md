# EDR fixtures

Six WHOLE real records (byte-for-byte uncut) extracted from the EDR
project's own Zenodo EpiDoc data release:

- Record: <https://zenodo.org/records/18468635> — "EDR - Epigraphic
  Database Roma Epidoc files", version 12, concept DOI
  10.5281/zenodo.3931222.
- Artifact: `EDR.zip`, 267,683,094 B, md5
  `d679b73ce95537406b84468cac64753c` (Zenodo-published; verified on
  download), sha256
  `61be8164b35fbf7409568da095242b247dec420a56df7f5f452bb4736c55917b`
  (the adapter's `RELEASE_SHA256` pin).
- Retrieved: 2026-07-26 via
  `https://zenodo.org/api/records/18468635/files/EDR.zip/content`.
- Census at retrieval (measured over the whole zip, not estimated):
  115,591 XML files in nine range dirs at the zip root, ids
  `aEDR<nnnnnn>` all unique, zero non-XML members, 649.5 MB unpacked,
  median file 5.3 KB; exactly 1 malformed file (below); edition-div
  `xml:lang`: la 110,006 · grc 5,584; every well-formed record carries
  the identical EAGLE-era `<licence>` ("Reserved Rights - Free access
  via Epigraphic Database Roma") while the DEPOSIT is CC BY 4.0 — see
  the adapter manifest for the two-layer license story.

Layout mirrors the workdir (range dirs at the fixture root), so
`discover` scans this directory as-is.

| file | why this one |
| --- | --- |
| `000001-025000/aEDR000002.xml` | The Latin exemplar: `choice` sic/corr pair, `surplus`, `<g type="mulieris">`, expansions, TM idno, full facet/date/place header (Julian `-50` … `1`). |
| `000001-025000/aEDR006167.xml` | A gap-only edition (all lines `<lb n="0">`/gap markers, one of 234 censused) → the whole-inscription `:text` fallback, never a quarantine. |
| `100001-125000/aEDR123437.xml` | A symbol-only carving: the edition's whole content is one self-closed `<g type="fulmen"/>` (88 such records at the full parse — christogramma, phallus, palma…) → the metadata-only document (`text_layer: none`), never a quarantine. |
| `125001-150000/aEDR125195.xml` | A Greek edition (`div[@type="edition"] xml:lang="grc"` while the ROOT tag says `la` — the boilerplate-header trap): grc minting, corr-only `<choice>`, `lb break="no"`, empty `origDate`. |
| `200001-225000/aEDR200440.xml` | A textpart record (`div[@type="textpart"] n="1"`): textpart-relative line urns, supplied/unclear counts, literal `〈:columna I〉` column labels, empty TM idno. |
| `quarantine/175001-200000/aEDR188615.xml` | THE one malformed file of the release: `<supplied>` crossing `<l>` boundaries (overlapping hierarchy from upstream's auto-converter) → `Nabu::ParseError` quarantine. Kept under `quarantine/` so the one-level discover glob of the conformance suite never yields it. |

A raw GET of the recorded url returns the 267 MB ZIP, not the member
file, so all entries are `whole: false` — fetched for URL-liveness
only, never byte-compared. Re-extract the members from `EDR.zip` after
any refresh.
