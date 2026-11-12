# CLLG Sources Chrétiennes fixtures

Real upstream samples from the Inria CLLG Sources Chrétiennes corpus (the
Greek — and a few Latin — texts of the Cerf *Sources chrétiennes* series
as TEI; CLAUDE.md fixture rules), trimmed but structurally intact.

- **Retrieved:** 2026-11-10 (the CLLG survey probe — an anonymous depth-1
  clone of <https://gitlab.inria.fr/almanach/cllg/sources-chretiennes> at
  commit `219176d8d9b9a2dae51fe3e3aeb7fca76afc0977`, 2026-11-05, HEAD on
  2026-11-10); cut 2026-11-12.
- **License:** the repository README: "The corpus is distributed under an
  open license (CC-BY)", and "Texts are distributed under French law, which
  holds that the texts of critical editions are not subject to copyright
  protection, as they do not constitute an expression of the editor's
  personality (CA Paris, Pôle 5, 2ème Ch., 9 June 2017, no. 16/00005)."
  The per-file headers (kept verbatim) carry the CLLG respStmt, funder and
  publicationStmt; no per-file licence element. Attribution: Corpus
  Liberatum Linguae Graecae (dir. Thibault Clérice, Inria); the printed
  Sources chrétiennes editions (Éditions du Cerf) each header names.
- **Layout:** mirrors upstream: flat `data/<author>/<work-slug>.xml`
  edition files beside the per-author `data/<author>/metadata.xml`
  catalog records, under the root `cllg-sc.xml` collection.
- **Trim rule:** every teiHeader is kept verbatim; inside the body only
  the first citation units are kept, closing tags restored. Small files
  are kept whole.

## Delivery grains (upstream serves)

| Grain | Upstream count (2026-11-05) | Adapter |
|---|---|---|
| edition file `data/<author>/<slug>.xml` claimed by a `metadata.xml` resource | 368 (362 grc + 6 Latin) | **the document** |
| — of which: declared tree opens no citable unit | 2 | skipped by rule (zero-match tree) |
| edition file no `metadata.xml` resource claims | 3 | skipped by rule (uncatalogued; their in-file edition urns collide with catalogued works) |
| per-author `metadata.xml` collection | 103 | catalog record — read for urns/titles, structure, never a document |
| root `cllg-sc.xml` | 1 | the catalog root listing every `metadata.xml` |
| `sc_catalog.csv`, `sc_tlg.csv`, `sc_tlg_authors.csv` | 3 | not walked (the SC↔TLG alignment tables; future edition-pairing material) |

## Files

The catalog: `cllg-sc.xml` (trimmed to the four fixture authors; upstream's
root carries `identifier="cllg-freed"`, a copy-paste from the sibling
corpus — kept verbatim) and `data/<author>/metadata.xml` for each fixture
author (trimmed to the fixture works; `cllg0010` whole).

| Path (under `data/`) | Why it is here |
|---|---|
| `tlg2042/contra_celsum.xml` | Origen, *Contra Celsum* (SC 132–150, Borret) — `div[@type='edition']` with `textpart` subtypes: volume (structural) > book/proem > section; lb-heavy with `lb break="no"` word joins; `surplus` over running text; 4-volume sourceDesc; proem sections 1–2 + book 1 section 1 |
| `stoa0104a/ad_demetrianum.xml` | Cyprian, *Ad Demetrianum* — a LATIN edition (`langUsage` la); `div[@type='chapter']` > `.//milestone[@unit='section']`; chapters 1–2 |
| `tlg4110/commentaire_proverbes_numeriques.xml` | Evagrius (whole file) — chunk > item, with Latin chunk heads outside the items |
| `tlg4110/lettre_sur_la_foi.xml` | Evagrius, *Letter on Faith* — an edition file NO metadata.xml resource claims (the uncatalogued grain); section 1 |
| `cllg0010/homilia_in_resurrectionem_salvatoris.xml` | John of Berytus, homily (whole file) — its tree cites `div[@type='edition']/p` by @n but no `p` carries @n: the zero-match grain |
