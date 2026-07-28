# 84000 (e84000) fixtures

Real files from github.com/84000/data-tei (branch `master`, commit
`bdfc81c9aecdfaf93e084ab64a885577de773046`), retrieved 2026-07-28 via raw
GETs. The directory layout mirrors the repo's `translations/` tree exactly —
the adapter discovers `translations/kangyur/translations/*.xml` and
`translations/tengyur/publications/*.xml`, and censuses the sibling
`placeholders/` dirs as skip-by-rule.

License: CC BY-NC-ND 3.0, stated in the repo README ("These works are
provided under the protection of a Creative Commons CC BY-NC-ND ... 3.0
copyright"), restated per-file in `availability/licence` — identical
wording in all five publication fixtures (the decorative `<graphic>`
badge URL is the old CC 2.0 png asset; the operative prose names 3.0,
the digilibLT badge-fork shape). Class `nc`.
CAVEAT: the README's linked Terms_of_Use.md (84000/all-data) layers "data
partnership" registration language for bulk external use; the README grant
is the operative license (P47-s2 survey, owner-acknowledged).

## Files

- `translations/kangyur/translations/100-002_toh846a-the_threefold_ritual.xml`
  — WHOLE (21 KB). Single-Toh Kangyur publication, letter-suffixed Toh
  number (`toh846a`), plain `<div>` markup, verse `<lg>` body, front
  summary/acknowledgment/introduction, back notes/listBibl/glossary with
  bo/Bo-Ltn/Sa-Ltn glossary terms. 10 chunks: s.1 ac.1 i.1-3 1.1-5.
- `translations/kangyur/translations/088-034_toh539e,774,1074-the_dharani_for_polishing_a_gem.xml`
  — WHOLE (24 KB). MULTI-TOH publication: three `<bibl key>` entries
  (toh539e, toh774, toh1074 — the comma list is also in the filename); the
  first key mints the slug, all ride metadata. Inline `<mantra>` Sanskrit,
  per-witness folio `<ref>`s. 10 chunks: s.1 ac.1-2 i.1-4 1.1-3.
- `translations/kangyur/translations/096-010_toh761-the_dharani_of_the_iron_beak.xml`
  — TRIMMED (13 KB of 61 KB): teiHeader whole, front cut to the summary
  div, body cut to the first two chunks of the translation section, back
  dropped; closing tags re-added. Edition v 1.0.2 — the WINNER of the
  upstream duplicate pair below.
- `translations/kangyur/translations/096-010_toh761-the_incantation_of_lohatunda.xml`
  — TRIMMED (13 KB of 61 KB), same procedure (this copy closes with
  `</tei:div>` — it uses namespace-PREFIXED `<tei:div>` elements, a real
  upstream variant the parser must treat as `<div>`). Edition v 1.0.1 —
  the duplicate LOSER: the repo keeps BOTH an old and a renamed copy of the
  same publication (same UT id UT22084-096-010, same volume-position
  096-010); discovery keeps the highest edition version and censuses the
  loser as a skip. 11 such pairs exist upstream (census 2026-07-28).
- `translations/tengyur/publications/075-017_toh3156-the_dharani_of_simhanada.xml`
  — WHOLE (47 KB). One of the THREE Tengyur publications; `<tei:div>`
  prefixed markup throughout, a `colophon` division (→ c.1), Sanskrit
  mainTitle with soft hyphens. 15 chunks: s.1 ac.1-2 i.1-7 1.1-4 c.1.
- `translations/kangyur/placeholders/096-016_toh767-tantra_of_the_supreme_dancer_of_the_yaksas.xml`
  — WHOLE (1.7 KB). A placeholder stub (560 exist for the Kangyur, 3,366
  for the Tengyur): header-only TEI, `<text><front/></text>`, no body, no
  publication status. Never discovered (placeholders/ is outside the
  discovery cones); counts in the skip census.

## Trim procedure (the toh761 pair)

Keep lines through `</teiHeader>`; emit `<text><front>`; copy the
`type="summary"` div whole; emit `</front><body>`; copy from the
`type="translation"` div opening up to (not including) the third body
`<milestone>`; close the two open divs, `</body></text></TEI>`.
