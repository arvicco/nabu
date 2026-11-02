# LexLep Word-page fixtures (`lexlep-words`) — P29-3

Real Word pages for the `lexlep-words` dictionary adapter
(`Nabu::Adapters::LexlepWords`). Retrieved **2026-07-18** from
`https://lexlep.univie.ac.at/api.php` in the fetcher's own batch shape —
see `test/fixtures/lexlep/README.md` for the family, the envelope note
and ALL license layers verbatim (one wiki, one `nc` posture, confirmed by
the maintainer's reply by email, C. Salomon, 2026-07-20).

- Layout: `pages/Word/<percent-encoded title>.json` + `map/Word.json`
  (trimmed to the checked-in pages).
- Pages chosen for shape coverage:
  - `aes` — Celtic (→ `cel` entry lane), gloss with inner quotes kept
    ("abbreviation of a name \"Aes...\""), `{{p|a}}{{p|e}}{{p|s}}`
    phonemic analysis (the nested-template-at-value-end regression), the
    etymology Commentary (*"\*ai̯ > ae … (Lejeune 1971: 126)"*).
  - `acisius` — Cisalpine Gaulish (→ `xcg`), `language_adaptation=Latin`,
    `{{m|akis-}}{{m|-i̯us|i̯us}}` morphemic analysis.
  - `a?` — marker-bearing title kept verbatim (`?` → `%3F` filename),
    language=unknown → `und`, `sortform` param present.
- Added **2026-11-02** (copied byte-verbatim from the box's own
  `canonical/lexlep-words/` fetch, same envelope) for the Holder
  "AcS <vol>: <col>" citation mining — the Commentary spellings upstream
  actually uses:
  - `kasios` — a locus list under one volume ("AcS I: 282, 832 f.").
  - `tekialui` — a range plus a volume switch inside the list
    ("AcS I: 1247–1250, II: 1779 f., 1788 f.").
  - `aesia` — the colon-less "AcS I 53" and a bold-wrapped second locus
    ("'''III 516'''").
  - `tati` — a lower-case volume ("AcS ii: 1751") beside "AcS II: 1723".
  - `esopnos` — the one volume-less citation ("AcS: 1489 f.").
