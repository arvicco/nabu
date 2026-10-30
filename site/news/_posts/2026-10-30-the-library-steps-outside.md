---
title: "The library steps outside — a public demo image, and the languages of ancient Italy"
date: 2026-10-30 13:50:00 +0000
description: >-
  Four development windows: a runnable public demo of the library as
  one Docker image, eleven ancient languages of Italy minted into the
  lect registry, French classical drama and a scan-anchored Tibetan
  dictionary on the shelves, the Neo-Assyrian prosopography in the
  person index, and a parallels-engine experiment reported honestly:
  it didn't help.
---

Four development windows since the last note, and the first one that
points outward: the library now has a **public, runnable demo**.

**One command, a working research library.** The demo image at
`ghcr.io/arvicco/nabu-demo` bakes a fully open slice of the library —
223 documents, 104,585 passages, 168,142 dictionary entries, every
source openly licensed and attributed — behind the same MCP server
the full library runs. `docker run -i --rm ghcr.io/arvicco/nabu-demo`
gives any MCP client (Claude, Cursor, VS Code and friends) fourteen
working tools over real corpus data: search ἀγάπη and land in
1 Corinthians 13 with the concordance, definitions and alignment
witnesses beside it. The server also speaks streamable HTTP for
hosted setups. The listing is live on Glama, with more directories to
follow; the full library remains a local build from the open adapters
in the repo. Details on the [MCP page]({{ "/mcp/" | relative_url }}).

**Eleven languages of ancient Italy entered the registry.** The
Lexicon ItAnt — 809 dictionary entries across sixteen languages of
pre-Roman Italy, from Oscan to Venetic — joined the dictionary
shelves, and the lect registry grew the anchors its languages needed:
Faliscan, Venetic, South Picene, Paelignian, Marrucinian, Marsian,
Vestinian, Volscian, Hernican, and local-use codes for Pre-Samnite
and Capenate, whose tags ISO 639-3 never assigned. Each anchor
carries researched classification notes and an epigraphic attestation
band; Venetic's disputed place inside Italic is recorded as disputed
rather than silently decided. The registry now holds 284 anchors.

**New on the shelves.** Théâtre Classique brought French classical
drama — Corneille, Molière, Racine and their contemporaries — as
structured play texts. A Literary Chinese collection widened the
largest shelf. Jäschke's 1881 Tibetan–English dictionary arrived as a
scan-anchored reference: page-exact lookups from the dictionary desk
into the original plates, with a converter verified against the scans
themselves. Sefaria's curated cross-reference graph now rides the
Tanakh shelf, linking verses to the passages that cite them. And the
reference-scan shelf gained its Celtic wing: Zeuss and Ebel's
*Grammatica Celtica* (1871) and the held volume of Holder's
*Alt-celtischer Sprachschatz*.

**The person index learned Assyriology.** The Prosopography of the
Neo-Assyrian Empire joined the person authorities, with its persons
linked to the texts that attest them — the index that already serves
Greek and Latin epigraphy now answers for Nineveh too.

**An experiment, reported honestly.** The parallels engine gained a
contiguity bonus last window (adjacent shared phrases now outrank
scattered ones, measured as a recall gain). This window tested a
fourth idea — demoting phrases a document repeats internally, the
"framing formula" discount — on all five gold sets. It never helped:
on the Pali suttas it was built for, the framing formulas turn out to
*carry* the curated-parallel signal. The switch stays in the bench
harness, off, with the measurements in the repo; negative results are
results.

The shelves stand at **{{ site.data.census.documents_display }}
documents / {{ site.data.census.passages_display }} passages** across
{{ site.data.census.live_sources }} live sources (as of
{{ site.data.census.as_of }}).
