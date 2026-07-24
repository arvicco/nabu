# CroALa fixtures — Croatiae auctores Latini (TEI P5)

Three whole, real TEI XML documents + the repo LICENSE, snapshotted
**2026-07-24** from
`github.com/nevenjovanovic/croatiae-auctores-latini-textus` (branch
`master`, raw `txts/`). Trimmed to nothing — each file is the upstream
document byte-for-byte, so the fixtures document CroALa's real encoding
quirks.

Chosen to cover the three structural shapes the parser must handle:

- `txts/albert-i-inscr.xml` — the minimal prose shape: one
  `<div type="prosa-inscriptio">` with a single `<p>` carrying an
  inline `<lb/>` (the line-break → space rule). One passage.
- `txts/adam-radauanus-traditio.xml` — a medieval charter (Donatio
  Radauani, dated `notBefore="1070-09-01"` — CroALa's 976-CE-onward
  span reaching the timeline): one prose div whose reading text lives
  in `<opener>` + two `<p>` + `<closer>`/`<signed>`. The
  opener/closer coverage is the reason CroALa gets its own parser
  (the reused SARIT family drops those subtrees). Four passages.
- `txts/andreis-f-carm-h46.xml` — verse: seven sibling
  `<div type="carmen|epigramma" met="hexameter">` of flat `<l>`
  lines, `<head>` poem titles (dropped from reading text), `<pb>`
  milestones, and the sparse every-fifth-line `@n` running marker
  (recorded as a `n` annotation, never the citation — the positional
  line ordinal coincides with it where present).

`LICENSE.md` is the repo's in-file grant, verbatim: the Creative
Commons **Attribution 4.0 International** legal text ("# Attribution
4.0 International"). The in-repo LICENSE governs (house doctrine),
resolving the recorded site-vs-GitHub fork to CC BY 4.0 → class
`attribution`. Kept here so the local-git fetch test can seed an
upstream cone with the real license bytes.
