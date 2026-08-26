# EEBO-TCP fixtures

Real upstream samples from the Text Creation Partnership's Box folder
(`https://app.box.com/s/jjzmnrx98dkvanipopz3nxkvymnjccht` — the TCP's
public distribution point, uniformly CC0), retrieved 2026-08-26 via the
per-file `box_v2_download_shared_file` endpoint (Phase-1 `A9.zip`/
`A5.zip`/`B3.zip`, Phase-2 `A2.zip`/`B3.zip`/`B4.zip` inspected; the
P83-0 scout's 3,325-file sample pool backs every census claim below).

## texts/ — four real corpus files (the fixture tree mirrors the fetch layout)

| path | what | why |
|---|---|---|
| `texts/phase1/A9/A90004.P4.xml` | *A new petition to the Kings most Excellent Majestie* (1642), whole file, 8.5 KB | the broadside shape: one DIV1, heads + opener/closer/trailer, BACK license div |
| `texts/phase1/A5/A57617.P4.xml` | *To day a man, to morrow none: Sir Walter Rawleighs farewell to his lady* (1644), whole file, 10 KB | the quarto shape; carries the canonical farewell poem ("EVen such is time…") as a `<Q><L>` block — the pinned snippet |
| `texts/phase2/A2/A29180.P4.xml` | Bragge, *The passion of our Saviour, a pindarick ode* (imprint "[1694?]"), whole file, 18 KB | Phase-2 verse (LG/L), GAP display glyphs, the corpus's ONE censused `<FW>` instance (wrapping a FIGURE — 1 FW-bearing file in 5,782 sampled P4 files), and the `?`-uncertain imprint (raw-only dating) |
| `texts/phase2/A2/A20018.P4.xml` | Dedekind, *The schoole of slovenrie* (Grobianus, 1605), TRIMMED | the folio shape. Trim: full HEADER + FRONT's first two DIV1s (title page, translator-to-the-reader) + BODY's Book 1, closers intact — front DIV1s 3–5 and Books 2–3 removed, well-formedness verified |

Every file: `<ETS>` P4 schema (`eebo2prf.xml.dtd`), `<IDG ID>` equal to
the filename stem (0 mismatches on the 3,325-file census), one LANGUSAGE
entry (`eng`), AVAILABILITY carrying the CC0 1.0 Public Domain
Dedication.

## fetch/ — the acquisition fixtures

- `root.html`, `phase1.html`, `phase1_p4.html`, `phase2.html`,
  `phase2_p4.html` — the Box shared-folder listing pages, TRIMMED real:
  the server-side `Box.postStreamData` JSON is the real payload
  (retrieved 2026-08-26) with the item arrays pruned to the fixture
  subset and zip `itemSize` values updated to the fixture zips' sizes;
  page chrome reduced to a minimal shell. Folder/file ids are upstream's
  real ids.
- `A9.zip`, `A5.zip`, `ph2_A2.zip` — subset re-zips of the REAL member
  files above, preserving each zip's real internal layout (one top-level
  `<stem>/` directory). `ph2_A2.zip` is Phase 2's `A2.zip` (both phases
  ship an `A2.zip`; the fixture name disambiguates on disk only).
- `IDnos_in_phase1.txt`, `eebo_phase1_IDs_and_dates.txt`,
  `IDnos_in_phase2.txt`, `EEBO_Phase2_IDs_and_dates.txt` — the per-phase
  ID lists, trimmed real: first 6 rows + the fixture texts' own rows.
- `eebo2prf.xml.dtd` — the P4 schema, WHOLE real file (45 KB; its
  2011-05 changelog line documents the `<FW>` element the family drops).
