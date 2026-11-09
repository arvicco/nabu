---
title: "v1.8.0 — four library waves, three new search surfaces, and a demo that earns its keep"
date: 2026-11-09 00:00:00 +0000
description: >-
  Twenty days of development in one release: early-modern Europe,
  the Latin liturgy sung, the early-medieval charters, the opening of
  the mass-digitization rail — plus annotation and gloss search
  surfaces, a widened public demo with a cuneiform sign desk, and a
  crash fix the demo image was waiting for.
---

Version 1.8.0 gathers twenty days of waves since v1.7.0 — the library
now stands at **{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources, every number on this
site regenerated from the live catalog (as of
{{ site.data.census.as_of }}).

**The library grew by four waves.** Early-modern Europe arrived first
— the Stationers' Register, the Statutes of the Realm, the Evans-TCP
and ECCO-TCP transcriptions, 3,067 mazarinades, the Socinian
correspondence network, Korpus 16, Noscemus's neo-Latin science, and
LEME's 311 period dictionaries. The Latin liturgy followed, sung: six
chant and liturgy sources led by the Cantus Database's 449,132 chants,
with a chant-identity layer tying the same chant across witnesses.
Then the early Middle Ages, charter by charter: the 5,164 charters and
diplomas of the Formulae–Litterae–Chartae editions beside the Late
Latin Charter Treebank's hand-annotated Tuscan charters, with a
three-source Mongolic shelf beside them. And the mass-digitization
rail opened: the British Library's digitised books at their pre-1800
cone, DBNL's hand-corrected Dutch literature, and the opening cones of
the National Library of Norway and the Wellcome Collection — each with
a resumable ledger, each honest about what OCR is.

**Three new search surfaces.** The annotation layers — standardized
spellings, margin notes, editors' notes across 31 sources — answer
`search --annotations`; scholars' token glosses became searchable
content (`search --gloss-lines`); and upstream morphology across five
more tagsets decodes to readable features, with a word-grain
`--gloss` filter. The works taxonomy grew to 28 ruled heads.

**The demo server earns its keep.** This release ships the fix for a
crash the public demo image carried (a dictionary miss could bring
down the whole MCP server — fixed, with a regression eval). The
in-repo eval pack grew from 36 to 42 tasks over all 14 tools, and the
demo slice now carries a cuneiform sign desk (the Oracc Sign List,
CC0) and a live reference-links journal (Achemenet's Babylonian
documents, CC BY), so the sign, character, and links tools answer
with substance instead of honest absence. Reference clarification now
folds the æ/œ ligatures — "Matthaeus 1.23" finds the Vulgate's
Matthæus. From this release on, the demo image's version line is the
release's own.

**Staging honesty.** A printed edition's year is now excluded from
language-stage inference everywhere — a 1510 Paris printing of
Plutarch must not stage as Renaissance Latin — and dictionary shelves
dated below their language's stage floor reach the parent stage by an
opt-in fallback: LEME's incunable-era English lexicons now sit under
Middle English, its early French ones under Middle French, while
Latin dictionaries deliberately stay unstaged by their compilers'
years.

As always, the census figures above are generated from the live
catalog, not hand-kept.
