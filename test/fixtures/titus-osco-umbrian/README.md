# titus-osco-umbrian fixtures

FULL real pages (untrimmed) from the TITUS Osco-Umbrian Corpus (frame-based
HTML edition), for the P90-2 adapter — one page per lane class, so the
fixtures document every script-lane pairing the corpus serves.

- Source: TITUS — Thesaurus Indogermanischer Text- und Sprachmaterialien,
  J. W. Goethe-Universität Frankfurt (Prof. Jost Gippert). Text entry
  J. Gippert (Frankfurt 1991) and V. Slunečko (Praha 1995); synoptical
  arrangement of original scripts J. Gippert.
- URLs (retrieved 2026-08-31, polite 2s pauses):
  - `oskum.htm`    — https://titus.uni-frankfurt.de/texte/etcs/ital/oskumb/oskum.htm (frameset entry, verbatim)
  - `oskum001.htm` — …/oskum001.htm — Tabula Iguvina **Ia** (34 lines): native-Italic
    original lane (`umo16`, RTL) + unified transliteration (`weum16`) → `xum`
  - `oskum012.htm` — …/oskum012.htm — Tabula Iguvina **VIIb** (4 lines): Latin-capitals
    original (`weuml16`) + transliteration (`weum16`) → `xum`
  - `oskum014.htm` — …/oskum014.htm — Oscan **POMP-2** (4 lines): native-Italic
    original (`oso16`, RTL) + transliteration (`weos16`) → `osc`
  - `oskum150.htm` — …/oskum150.htm — Oscan **Ross-10** (1 line): Greek-alphabet
    original (`gros16`) + transliteration (`weos16`) → `osc`

First-sync census additions (retrieved with the owner's 2026-08-31 full
crawl; copied from the held canonical tree, same grant):

  - `oskum043.htm` — **SAMN-8 (& HeI)** (2 lines): the paren-protected anchor
    shape (`Inscr.OU_BaI_SAMN-8_(&_HeI)__1` — an underscore INSIDE parens is
    not a level separator) → `osc`
  - `oskum377.htm` — **MARS-1** (8 lines): the Rechtsdokumente section's
    archaic-Latin comparanda lane pair (`weal16`/`wealo16`, "in hoce
    loucarid…") → `lat`
  - `oskum069.htm` — **Ross-2 (&)**: a photo-only stub (no content lanes —
    the edition links a photograph); the discovery skip-class exemplar

All four text pages are byte-verbatim upstream pages (small enough to keep
whole), so the adapter tests assert real full-page counts that survive a
refresh unchanged unless upstream itself changes.

## Provenance / grant

Served under the owner's **personal grant** (Prof. Jost Gippert, by email
2026-08-31, extending the 2026-07-23 Avestan terms): one-time download, local
non-commercial use, no redistribution, TITUS and the editors credited
wherever displayed. The fetch right is personal to this project's author and
NOT conveyed by a public clone — hence `grant_required: true` on the
`config/sources.yml` row. These sample pages are retained here purely to
exercise the parser offline (no network in tests).
