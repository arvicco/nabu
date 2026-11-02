# Patristic Text Archive (PTA) fixtures

Real upstream samples from the Patristic Text Archive's data repository
(CLAUDE.md fixture rules), trimmed but structurally intact.

- **Retrieved:** 2026-11-02, a clone of
  [PatristicTextArchive/pta_data](https://github.com/PatristicTextArchive/pta_data)
  at commit `524eb9763b1181bc9f14edf52943bfe2f7a43aed` (2026-06-18).
- **Layout:** mirrors upstream's `data/<textgroup>/<work>/` CapiTainS tree.
- **Trim rule:** every teiHeader is kept verbatim; inside the body only the
  first citation units are kept (the deeper levels likewise).

| Path (under `data/`) | Licence (own header) | Why it is here |
|---|---|---|
| `pta0001/pta002/pta0001.pta002.pta-grc1.xml` | CC BY-SA 4.0 | Severian, *De paenitentia et compunctione* — the CTS refsDecl beside the biblical/pta/perseus resolver refsDecls (sections 1–2 of 7) |
