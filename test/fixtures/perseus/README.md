# Perseus fixtures

Real upstream samples from the PerseusDL canonical repos (CLAUDE.md fixture
rules). All files are byte-identical upstream copies except the Iliad edition
(P6-1), a documented trim of a 2 MB file — see its table row and manifest.yml.

- **Retrieved:** 2026-07-03, from `master` of
  [PerseusDL/canonical-greekLit](https://github.com/PerseusDL/canonical-greekLit) and
  [PerseusDL/canonical-latinLit](https://github.com/PerseusDL/canonical-latinLit)
  via raw.githubusercontent.com, exact paths below mirrored under
  `greekLit/data/` and `latinLit/data/`.
- **License:** CC BY-SA 4.0 (both repos, `license.md` at repo root; verified
  at retrieval). Attribution: Perseus Digital Library / Trustees of Tufts
  University.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P2-1).

## Editions (5) — chosen to cover the parser's hard cases

| File | Work | Lang | Why this one |
|---|---|---|---|
| `greekLit/data/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml` | Homer, Iliad (**trimmed**, P6-1) | grc | Structural-retry exemplar: refsDecl units `book`/`line` vs body `div[@subtype="Book"]` — a case mismatch the CapiTainS subtype convention cannot see; recovered from the replacementPattern xpath. Trimmed 2026-07-04 from the local canonical snapshot (synced 2026-07-03): teiHeader whole, book 1 lines 1–10 + 607–611, book 2 lines 1–19 (book boundary and a `<q>`-wrapped line run kept), books 3–24 removed |
| `greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-grc2.xml` | Homeric Hymn 13 (Demeter) | grc | Minimal case: flat single-level `line` citation (`<l n>` under `div[@type=edition]`), 3 lines total |
| `greekLit/data/tlg0013/tlg014/tlg0013.tlg014.perseus-grc2.xml` | Homeric Hymn 14 (Mother of the Gods) | grc | Second document of the same scheme → multi-document corpus for conformance |
| `greekLit/data/tlg0031/tlg024/tlg0031.tlg024.perseus-grc2.xml` | New Testament, 2 John | grc | Two-level `chapter`/`verse` citation via nested `div[@subtype]`; multiple `<ti:title>` aliases in work metadata |
| `latinLit/data/stoa0045/stoa013/stoa0045.stoa013.perseus-lat2.xml` | Ausonius, Genethliacon | lat | `line` citation nested under a structural, NON-citeable `div[@subtype=section]`; older EpiDoc schema declaration (8.19 + schematron PI) |

Each edition is accompanied by its work-level `__cts__.xml` and the
textgroup-level `__cts__.xml` (9 metadata files total) — the adapter resolves
titles, URNs, and edition-vs-translation from these. The tlg0012 metadata
files were copied whole from the local canonical snapshot (P6-1).

## Upstream structure notes (verified at retrieval)

- Path pattern `data/<textgroup>/<work>/<tg>.<work>.<edition>.xml`; the CTS
  namespace (greekLit/latinLit) is the repo, not a path segment.
- `div[@type="edition"]/@n` carries the full CTS edition URN.
- Trust the `refsDecl` `cRefPattern`s for citation levels, not div nesting —
  structural divs exist that are not citation levels (see Ausonius).
- Edition slugs encode language + version (`perseus-grc2`, `perseus-lat2`);
  translations (`perseus-eng*`) sit as sibling files in the same work dir,
  distinguished in `__cts__.xml` as `<ti:translation>` vs `<ti:edition>`.
- Mixed content inside citation units: editorial `<milestone unit="card|Para">`
  markers appear inside `<l>` elements.
- Some upstream works lack `__cts__.xml` entirely (e.g. phi0692) — these
  candidates were verified complete; the adapter must tolerate the gap.
