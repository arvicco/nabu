# Perseus fixtures

Real upstream samples from the PerseusDL canonical repos (CLAUDE.md fixture
rules). All files are byte-identical upstream copies except the two Iliad
files — the grc2 edition (P6-1) and the eng4 Butler translation (P8-1b), each a
documented trim of a multi-MB file — see their table rows and manifest.yml.

- **Retrieved:** 2026-07-03, from `master` of
  [PerseusDL/canonical-greekLit](https://github.com/PerseusDL/canonical-greekLit) and
  [PerseusDL/canonical-latinLit](https://github.com/PerseusDL/canonical-latinLit)
  via raw.githubusercontent.com, exact paths below mirrored under
  `greekLit/data/` and `latinLit/data/`.
- **License:** CC BY-SA 4.0 (both repos, `license.md` at repo root; verified
  at retrieval). Attribution: Perseus Digital Library / Trustees of Tufts
  University.
- **Acquisition plan** approved by owner 2026-07-03 (dev-loop §8; packet P2-1).

## Editions (8) — chosen to cover the parser's hard cases

| File | Work | Lang | Why this one |
|---|---|---|---|
| `greekLit/data/tlg0012/tlg001/tlg0012.tlg001.perseus-grc2.xml` | Homer, Iliad (**trimmed**, P6-1) | grc | Structural-retry exemplar: refsDecl units `book`/`line` vs body `div[@subtype="Book"]` — a case mismatch the CapiTainS subtype convention cannot see; recovered from the replacementPattern xpath. Trimmed 2026-07-04 from the local canonical snapshot (synced 2026-07-03): teiHeader whole, book 1 lines 1–10 + 607–611, book 2 lines 1–19 (book boundary and a `<q>`-wrapped line run kept), books 3–24 removed |
| `greekLit/data/tlg0012/tlg001/tlg0012.tlg001.perseus-eng4.xml` | Homer, Iliad, Butler translation (**trimmed**, P8-1b) | eng | Span-grouped parallel-display fixture (P8-1b): CARD-cited prose (`div[@subtype="card"]` under `div[@subtype="book"]`, citation `book.card`) against the line-cited grc sibling — one prose block anchored at each card's first line owns the whole run of Greek lines up to the next card (the "frankly, not that parallel" case the coarse renderer exists for). Trimmed 2026-07-07 from the local canonical snapshot (synced 2026-07-03): teiHeader + translation div kept, book 1 reduced to its first two cards (1.1, 1.40), later cards and books 2–24 removed |
| `greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-grc2.xml` | Homeric Hymn 13 (Demeter) | grc | Minimal case: flat single-level `line` citation (`<l n>` under `div[@type=edition]`), 3 lines total |
| `greekLit/data/tlg0013/tlg014/tlg0013.tlg014.perseus-grc2.xml` | Homeric Hymn 14 (Mother of the Gods) | grc | Second document of the same scheme → multi-document corpus for conformance |
| `greekLit/data/tlg0031/tlg024/tlg0031.tlg024.perseus-grc2.xml` | New Testament, 2 John | grc | Two-level `chapter`/`verse` citation via nested `div[@subtype]`; multiple `<ti:title>` aliases in work metadata |
| `latinLit/data/stoa0045/stoa013/stoa0045.stoa013.perseus-lat2.xml` | Ausonius, Genethliacon | lat | `line` citation nested under a structural, NON-citeable `div[@subtype=section]`; older EpiDoc schema declaration (8.19 + schematron PI) |
| `greekLit/data/tlg0013/tlg013/tlg0013.tlg013.perseus-eng2.xml` | Homeric Hymn 13, Evelyn-White translation | eng | Parallel-translations fixture (P7-4): `div[@type="translation"]`, ONE merged `<l n="1">` covering the grc edition's three lines — the honest one-sided alignment case. Copied whole from the local canonical snapshot 2026-07-07 |
| `greekLit/data/tlg0031/tlg024/tlg0031.tlg024.perseus-eng2.xml` | 2 John, World English Bible translation | eng | Parallel-translations fixture (P7-4): `div[@type="translation"]` with the same two-level `chapter`/`verse` citation as the grc edition, 13 verses each — full citation-suffix pairing. Copied whole from the local canonical snapshot 2026-07-07 |

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
- Translation bodies use `div[@type="translation"]` where original-language
  editions use `div[@type="edition"]` (785 of 786 `perseus-eng*` files in the
  canonical snapshot; the lone exception, tlg0057.tlg010.perseus-eng2, uses
  `edition`). Version tokens on `perseus-eng<n>` are pure digits upstream
  (eng1–eng6; no letter suffixes as of the 2026-07-03 snapshot).
- English translations may merge the original's citation units: Hymn 13's
  translation is a single `<l n="1">` covering the Greek's three lines; the
  Iliad Butler translation (eng4, now fixtured) cites by `book`/`card` where
  the Greek cites by `book`/`line`, so only card-initial suffixes coincide and
  each card owns the run of Greek lines up to the next (P8-1b span grouping).
- Mixed content inside citation units: editorial `<milestone unit="card|Para">`
  markers appear inside `<l>` elements.
- Some upstream works lack `__cts__.xml` entirely (e.g. phi0692) — these
  candidates were verified complete; the adapter must tolerate the gap.
