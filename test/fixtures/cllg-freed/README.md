# CLLG Freed Corpus fixtures

Real upstream samples from the Inria CLLG Freed Corpus (Corpus Liberatum
Linguae Graecae — the TLG E canon as TEI; CLAUDE.md fixture rules),
trimmed but structurally intact.

- **Retrieved:** 2026-11-10 (the CLLG survey probe — an anonymous depth-1
  clone of <https://gitlab.inria.fr/almanach/cllg/freed-corpus> at commit
  `281049a3dc8c96ddd7c8ef9a9f37da0021d16764`, 2026-10-06, HEAD on
  2026-11-10); cut 2026-11-12.
- **License:** per file, both in each teiHeader's
  `publicationStmt/availability` (retained verbatim in every trimmed
  file): texts CC0 1.0 ("under French law, the text of a critical edition
  is not protected by copyright (CA Paris, Pôle 5, 2ème Ch., 9 June 2017,
  no. 16/00005)"); citation structure and metadata CC-BY 4.0. Attribution:
  Corpus Liberatum Linguae Graecae (dir. Thibault Clérice, Inria); the
  Diogenes TEI export (Peter Heslin) the texts descend from.
- **Layout:** mirrors upstream: `data/<author>/<work>/<urn>.xml` edition
  files beside the per-author `data/<author>/metadata.xml` catalog
  records, under the root `cllg-freed.xml` collection.
- **Trim rule:** every teiHeader is kept verbatim (availability blocks
  included); inside the body only the first two or three citation units
  are kept, closing tags restored. Small files are kept whole.

## Delivery grains (upstream serves)

| Grain | Upstream count (2026-10-06) | Adapter |
|---|---|---|
| edition file `data/<author>/<work>/<urn>.xml` (incl. `data/spurious-and-dubia/`) | 6,626 | **the document** |
| — of which: no `refsDecl`/`citeStructure` declared at all | 331 | skipped by rule (no citation tree) |
| per-author `metadata.xml` collection | 1,839 | catalog record — read for urns/titles, structure, never a document |
| root `cllg-freed.xml` | 1 | the catalog root listing every `metadata.xml` |

## Files

| Path (under `data/`) | Why it is here |
|---|---|
| `tlg0012/tlg001/tlg0012.tlg001.cllg-grc1.xml` | Homer, *Iliad* (Allen 1931) — verse: `div[@type='book']` > `l`; `seg rend="Marginalia"` margin signs; book 1 lines 1–3 + book 2 lines 1–2 |
| `tlg0059/tlg030/tlg0059.tlg030.cllg-grc1.xml` | Plato, *Republic* (Burnet) — prose cited by flat `milestone[@unit='section'][@ed='Burnet']` (default tree) beside a physical `pb` tree; sections 327a–327c; carries U+0387/U+037E (the non-NFC codepoints) |
| `tlg2738/tlg002/tlg2738.tlg002.cllg-grc1.xml` | Anonymous chronicle (de Boor) — the `pb[@ed='Boor']` stream alone is the citation, across `head`/`p`/`div type="subsection"`; pages 218–220 (page 220 cut after its first line) |
| `tlg1514/tlg002/tlg1514.tlg002.cllg-grc1.xml` | Mnaseas, fragments (whole file) — `div[@type='fragment']` with @n like `25 bis a`; `bibl type="fragment-source"`, inline `bibl`, `note`, and the Leiden sigla `supplied`/`surplus`/`del`/`gap`/`unclear`/`space` |
| `tlg0545/tlg005/tlg0545.tlg005.cllg-grc1.xml` | Aelian (whole file) — one of the 331 files declaring NO citation tree (the rejected grain) |
