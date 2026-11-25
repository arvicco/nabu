---
title: "A humanists' journal, Middle English verse in waiting, and a release that checks its own door"
date: 2026-11-25 00:00:00 +0000
description: >-
  The first window after v1.9.0: Colloquia Maruliana joins the Croatian
  shelf with its Latin and Croatian text editions, an adapter for the
  Parsed Corpus of Middle English Poetry is ready for its delivery, and
  the release rail now proves the public can pull the image before it
  says so.
---

One development window since v1.9.0 — the library stands at
**{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources (as of
{{ site.data.census.as_of }}).

**Colloquia Maruliana.** The annual journal of Marulić studies, published
by the Split Literary Circle's Marulianum since 1992, is now read in full
text from the Croatian journal portal Hrčak: 644 articles, some 9,800
pages. Beside the scholarship on Marko Marulić and the Dalmatian and
Dubrovnik humanists it carries what a library of sources wants most — the
text editions printed in its pages, Latin works of Marulić and his circle
among them. The journal publishes under CC BY 4.0, but the licence is read
record by record: articles that state their own non-commercial terms are
marked so, and the thirty-seven that are marked in copyright are left out
and counted. Many of the older volumes were typeset in a font whose
Croatian letters come out of the PDF as other characters; the text layer
is repaired where the damage is unambiguous and left alone where it is
not.

**Middle English verse, in waiting.** The adapter for the Parsed Corpus of
Middle English Poetry — fifty-seven poems from The Grave to the Siege of
Jerusalem, every clause hand-parsed — is built and tested on real samples;
the corpus itself, kindly sent by its maintainer for research use, is
loaded once its release file is in place.

**A release that checks its own door.** v1.9.0 moved the demo image to its
settled name, and a container registry creates a package under a new name
as private: for some hours the published install command could not be
pulled by anyone but the publisher. The publish step now proves an
anonymous pull before it reports success, and the release waits for that
proof.

**Counting what is searchable.** The standing check that everything held
is also searchable now counts live passages only, with withdrawn rows
shown beside them; after the rebuild it reads no gap at all.

**Semantic neighbours.** The embedding store was brought up to date over
its core sources.
