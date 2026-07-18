# LexLep Word-page fixtures (`lexlep-words`) — P29-3

Real Word pages for the `lexlep-words` dictionary adapter
(`Nabu::Adapters::LexlepWords`). Retrieved **2026-07-18** from
`https://lexlep.univie.ac.at/api.php` in the fetcher's own batch shape —
see `test/fixtures/lexlep/README.md` for the family, the envelope note
and ALL license layers verbatim (one wiki, one `nc` posture, email №17
queued, relabel-on-reply).

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
