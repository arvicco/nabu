---
title: "Lane's Lexicon, Byzantine book epigrams and the Wolfenbüttel editions"
date: 2026-11-27 00:00:00 +0000
description: >-
  Two windows of work: Lane's Arabic–English Lexicon and the Middle
  English Dictionary's headword list join the reference shelf; the Ghent
  database of Byzantine book epigrams, three volumes of Die Deutschen
  Inschriften and the Herzog August Bibliothek's hand-keyed editions
  join the library; and title lookup forgives swapped letters.
---

Two development windows since the last note — the library stands at
**{{ site.data.census.documents_display }} documents /
{{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources (as of
{{ site.data.census.as_of }}).

**Lane's Arabic–English Lexicon.** Edward William Lane's lexicon
(London, 1863–93) is the library's first classical Arabic dictionary:
48,795 entries under their roots, each with its printed page, from the
Perseus Digital Library edition. It stands beside the classical Arabic
prose the library already holds, so a word met in a text can be looked
up where Lane gathered the medieval lexicographers.

**Byzantine book epigrams.** The Database of Byzantine Book Epigrams
(Ghent University) collects the verses that scribes, patrons and
readers wrote into Greek manuscripts: colophons asking for the reader's
prayers, dedications, title poems, lines in praise of the author
copied. Each epigram is held as it stands in one manuscript, in the
scribe's own spelling — 12,928 occurrences from some 4,500 manuscripts
of the sixth to the nineteenth century — and as the normalized text the
editors establish for each family of copies (5,226 types), with about
2,500 translations beside them. The copies carry their manuscript's
date, and genre, metre and poet where known.

**The Wolfenbüttel editions.** The Herzog August Bibliothek publishes
hand-keyed transcriptions of early modern prints and manuscripts from
its collections; 472 of them are now read page by page — Hans Sachs's
*Wittenbergisch Nachtigall* (1523), Kaempfer's *Amoenitates exoticae*
(1712), Lipsius on the libraries of antiquity, Sebald Heyden's school
colloquies in fifteen printings, Sibylla Schwarz's poems (1650), and
more than four hundred letters of the nuns of Kloster Lüne, in Latin and
Middle Low German. The library has no single list of its editions and
no single licence: each edition's manifest is read, the licence is taken
per transcript, and editions that publish no transcript file are
skipped and counted.

**German inscriptions.** Three volumes of *Die Deutschen Inschriften* —
Braunschweig (Riddagshausen), Greifswald and Stralsund — are published
by the Mainz academy as structured EpiDoc: 978 catalogue numbers
carrying 2,699 inscriptions from 1145 to the seventeenth century, the
grave slabs of the Hanseatic churches above all. Each is cited by its
printed number and carries its date, its place and, for most Latin
texts, the edition's German translation.

**Middle English, by headword and by period.** The Middle English
Dictionary's headword list — 57,094 entries — is searchable as a
reference shelf; at the editors' request it is used here and not passed
on. The language-stage registry now divides Middle English into the
four Helsinki periods, ready for the Parsed Corpus of Middle English
Poetry, whose adapter waits for its release file.

**Four historical treebanks.** Universal Dependencies 2.19 brought the
Ashokan edicts in Prakrit, a Manchu sample, the Swedish New Testament
of 1526 and Ukrainian prints in the Zhelekhivka spelling of 1892–1921.
Treebanks that print a translation or an original reading beside each
sentence now keep it: the Manchu sentences are searchable by their
English, and the edicts keep the reading of the stone.

**Finding a title despite the typing.** `nabu clarify` finds the Iliad
when asked for the "Illiad", and now the Aeneid when asked for the
"Aenied": a swapped pair of letters counts as one slip, not two.

**Under the floor.** The semantic-vector build no longer re-sorts its
whole scope for every page it reads — the fault that made the last
catch-up run take five times its estimate. The dictionary loader stops
and says so when too many entries of a file newly fail to parse; a sync
started while a rebuild is running refuses at once; and the check that
tells whether a source must be re-read names every reason, not only
the first.
