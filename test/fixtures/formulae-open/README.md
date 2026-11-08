# formulae-open fixtures

Real upstream samples from the Formulae – Litterae – Chartae project's
public repository (CLAUDE.md fixture rules).

- **Retrieved:** 2026-11-08, a shallow clone of
  [Formulae-Litterae-Chartae/formulae-open](https://github.com/Formulae-Litterae-Chartae/formulae-open)
  at commit `2ce7341634926492d5a75a44f22b850fbb142f2f` (2023-11-08; still
  HEAD on 2026-11-08). Zenodo DOI 10.5281/zenodo.10082515.
- **License:** per file — each TEI's own `<licence @target>` in the
  publicationStmt. Attribution: Formulae – Litterae – Chartae (Akademie der
  Wissenschaften in Hamburg / Universität Hamburg) and each printed
  edition's editor.
- **Layout:** mirrors upstream's CapiTainS v3 tree under `data/` —
  `data/<collection>/<work>/` and, for the cartularies, the three-level
  `data/<collection>/<sub-collection>/<work>/` (the Anjou specimen).
- **Trim rule:** every charter TEI and every work-level `__capitains__.xml`
  is copied WHOLE (the charters are small). The textgroup (and
  sub-collection) `__capitains__.xml` catalogs are cut to the member
  entries of the pinned works only; their headers (dc:title, dc:coverage)
  are verbatim.

## Delivery grains (upstream serves)

| Grain | Upstream count | Adapter |
|---|---|---|
| Latin charter edition file `<collection>.<work>.lat<nnn>.xml` | 5,207 (5,170 lat001 + 37 lat002–lat004) | **the document** — every edition of a work (lat002+ are the print's a/b/c pieces) |
| …of which carrying no `<licence>` (the 6 luzern charters) | 6 | skipped by rule (unlicensed) |
| …of which regest-only (the print gives a summary, the charta div is empty) | 37 | skipped by rule (no Latin text) |
| E-Lexicon entry `elexicon.<lemma>.deu001.xml` (German) | 259 files / 289 catalog editions (30 aliases share a file) | skipped by rule (the lexicon grain) |
| `__capitains__.xml` textgroup / sub-collection / work catalogs | one per directory | read for the collection title only, never documents |
| passage: `div[@type="textpart"][@subtype="charta"]` | 5,324 over the 5,207 charters (89 files carry 2–7) | the passage |

## Files (under `data/`)

| Path | Licence (own header) | Why it is here |
|---|---|---|
| `stgallen/wartmann0001/stgallen.wartmann0001.lat001.xml` | CC BY 4.0 | Wartmann Nr. 1 — dateline `when="0700"`, issuing place (ausstellungsort) Cannstadt, the regest |
| `freising/bitterauf1019/freising.bitterauf1019.lat001.xml` | CC BY 4.0 | Bitterauf Nr. 1019a — the manuscript rubric `<head>`, `<seg function>` formula spans, the `<choice><abbr>/<expan>` cross-referenced formula |
| `freising/bitterauf1019/freising.bitterauf1019.lat002.xml` | CC BY 4.0 | Nr. 1019b — a second edition of the same work, its own document |
| `hersfeld/weirich0037/hersfeld.weirich0037.lat001.xml` | CC BY 4.0 | four charta divs in one file (four passages); bracketed range `[880-899]` |
| `hersfeld/weirich0004/hersfeld.weirich0004.lat001.xml` | CC BY 4.0 | a regest-only record (empty charta div) — skipped by rule |
| `anjou_archives/marchegay_carbaio/marchegay_carbaio_0006/…lat001.xml` | CC BY 4.0 | the three-level tree; an empty `<date/>` dateline (undated) |
| `marmoutier_vendomois/trémault0011/…trémault0011.lat001.xml` | CC BY 4.0 | a non-ASCII path and urn; notBefore/notAfter ISO dates |
| `eudes/lex0034/eudes.lex0034.lat001.xml` | **CC BY-NC-ND 4.0** | the deviant licence class (→ nc); "Sans date" with an empty and a bounded `<date>` |
| `luzern/schiess0004/luzern.schiess0004.lat001.xml` | **none** ("To be filled in when a decision is made by the team.") | the unlicensed class — skipped by rule |
| `elexicon/riga/elexicon.riga.deu001.xml` | CC BY 4.0 | the rejected E-Lexicon grain — skipped by rule despite its licence |

Plus each pinned work's `__capitains__.xml` (whole) and each collection's
`__capitains__.xml` (trimmed). Together the licence tags cover every
target upstream ships: by-4.0, by-nc-nd-4.0, and none.
