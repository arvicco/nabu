---
title: Quickstart
permalink: /quickstart/
description: >-
  From a fresh clone to the first aligned verse in about a quarter hour: prerequisites,
  the starter shelf, the first three commands, and how to grow the library.
---

## 1. Clone

```
git clone https://github.com/arvicco/nabu
cd nabu
```

## 2. Install

```
bundle install
```
The whole step fits the ten-minute budget above, per-source index builds
included; the `lexica` download dominates, while `sblgnt` takes seconds,
so a slow connection stretches the fetches and little else. The command is
idempotent — re-running it is an ordinary re-sync — and one source's
failure never stops the rest: failures are reported at the end.
`bin/nabu quickstart --dry-run` prints the set without syncing anything.

**Search by dictionary form.** `bin/nabu search --lemma λέγω` finds every
inflected attestation over the gold treebank annotations — λέγουσι,
λέγοιεν, and the suppletive εἶπας/εἰπεῖν that no surface-string query can
reach. Diacritics are optional on the query.

**Open the dictionary.** `bin/nabu define λόγος` prints the whole LSJ
entry, with its citations resolved to passages in your own catalog where
the corpus holds them (`nabu show <urn>` opens the cited line); `bin/nabu
define virtus` does the same in Lewis &amp; Short.
Each further shelf is the pair:

```
bin/nabu enable perseus-greek   # add the shelf to your profile
bin/nabu sync perseus-greek     # fetch, load, index
```

`enable` is additive and takes an axis name too (`bin/nabu enable
celtic` enables that whole desk's public members); a handful of
grant-gated research sources are never swept in by an axis — each
must be enabled by name and shows you its terms first. After that,
`bin/nabu sync --all` re-syncs every enabled live-policy source in
one pass. The full menu is `config/sources.yml`; real on-disk sizes
for the larger shelves, measured {{ sizes.as_of }} (each row below
assumes its `enable` ran first):

| Sync | Unlocks | Canonical size |
|---|---|---|
| `bin/nabu sync vulgate` + `sync eng-web` | the Clementine Latin and English witnesses for `align`, Old Testament included | {{ src.vulgate.canonical_display }} + {{ src["eng-web"].canonical_display }} |
| `bin/nabu sync perseus-greek` | the Greek canon with aligned English translations | {{ src["perseus-greek"].canonical_display }} |
| `bin/nabu sync perseus-latin` | the Latin classics | {{ src["perseus-latin"].canonical_display }} |
| `bin/nabu sync gretil` | 780 Sanskrit editions | {{ src.gretil.canonical_display }} |
| `bin/nabu sync papyri-ddbdp` | 64k documentary papyri | {{ src["papyri-ddbdp"].canonical_display }} |
## Your desk

The starter shelf is running; the natural next move is to find the desk for
your own field. `bin/nabu list --axis` prints the shelf census grouped under
the {{ census.desks }} [research desks]({{ '/axis/' | relative_url }}) — scholarly hats
over the same sources, from the Classicist to the Assyriologist. Pick the one
that fits, enable it, and sync its members — `bin/nabu enable celtic &&
bin/nabu sync celtic`, or whichever desk is yours — then open its page: each desk carries its own
member shelves, CLI recipes, search modes, and terminal setup for its scripts.

```
bin/nabu list --axis        # the shelf census, grouped by research desk
bin/nabu axis celtic        # one desk's card: members, holdings, gold coverage
bin/nabu enable celtic      # put the desk's public members on your profile
bin/nabu sync celtic        # then sync them
```
