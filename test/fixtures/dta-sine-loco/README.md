# DTA sine-loco fixture (Deutsches Textarchiv, BBAW)

One real DTA-Basisformat (TEI/P5) text, copied byte-verbatim from the
held komplett archive (`canonical/dta/`, the per-book file
`kippenheim_dieberey_1660.TEI-P5.xml`, fetched 2026-09-03 from
`https://www.deutschestextarchiv.de/`; license CC BY-SA 4.0), untrimmed
(9.9 KB):

- `kippenheim_dieberey_1660.TEI-P5.xml` — a 1660 Strasbourg council
  ordinance against servants' theft. Its sourceDesc pubPlace is the
  catalogue's sine loco `s. l.` (the print names no place; 116 DTA texts
  carry it, census 2026-10-22).

Kept beside the `dta/` trio rather than inside it so the trio's
discovery set stays unchanged; `test/adapters/dta_test.rb` loads this
directory on its own to pin that the sine loco rides the metadata
verbatim but mints no place on the timeline axis.
