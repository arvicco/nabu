# Quickstart — zero to first search

This walkthrough goes from a fresh checkout to searching, reading, and
aligning ancient texts. Every command below was actually executed and
the output pasted (transcripts re-run 2026-08-19; trims marked with …). The reference box
carries the full library, so search results here show more shelves than a
fresh install will — noted where it matters. The sync commands touch
the network and are *described* (with real sizes and timings) rather than
re-run. The same walkthrough is published on the project site:
[arvicco.github.io/nabu/quickstart](https://arvicco.github.io/nabu/quickstart/).

## 0. Prerequisites

- **Ruby 3.3+** and **git**. macOS (Apple Silicon) is the development
  platform; nothing in the core is known to be Mac-specific.
- Disk: a single small source is a few MB; the full library as of
  2026-08-19 is **87 GB canonical + 125 GB derived SQLite** (the Arabic
  OpenITI, ORACC, and Chinese shelves dominate). Start small — the
  starter shelf below is ~690 MB, and every shelf is an independent
  opt-in.

## 1. Install

```
git clone <this repo> && cd nabu
bundle install
```

The dependency set is deliberately small (thor, sequel, sqlite3, nokogiri,
faraday, plus test tooling). No services, no daemons — everything is files
and SQLite under the project root.

Configuration is optional: every key in `config/nabu.yml` has a working
default, so a fresh checkout runs as-is. Box-local overrides go in
`local/config/settings.yml`, which deep-merges over `config/nabu.yml` —
edit that later if you want the corpus on a bigger disk.

## 2. Sync the starter shelf

One command syncs the curated starter set and prints the first three
commands to try:

```
bin/nabu quickstart
```

The CORE group syncs first, automatically — the registry instruments the
library depends on (nabu-lects, nabu-places, cigs, pre-enabled by
nature; their `requires:` chain rides in the Pleiades gazetteer dump
(~129 MB) and the trismegistos-geo manual drop, which prints its
acquisition card until you supply the file — nothing fails, nothing is
skipped silently; `bin/nabu sync core` re-runs just that sweep).
Quickstart is not the only door: on a fresh install the FIRST real
`bin/nabu sync <anything>` also sweeps any never-synced core member
first, so the core layers are always in place before the first corpus
arrives.
Then the starter set (sizes measured from the live canonical tree,
2026-07-13): the SBL
Greek New Testament (`sblgnt`, 11 MB, CC BY), the PROIEL treebank
(`proiel`, 173 MB — the NT in Greek, Latin, Gothic, Armenian, and Old
Church Slavonic, with gold lemmas; nc), the ISWOC Old English treebank
(`iswoc`, 30 MB; nc), and the LSJ + Lewis & Short dictionaries (`lexica`,
479 MB, CC BY-SA) — about **690 MB** all told. On the reference box the
four first syncs took roughly three minutes of fetch-and-load combined
(lexica dominates); allow up to ten minutes on an ordinary connection.
`bin/nabu quickstart --list` previews the set without syncing; a re-run is
an ordinary re-sync, and one source's failure never stops the rest.

Prefer the smallest possible start? A single source works too:

```
bin/nabu sync sblgnt
```

This fetches the upstream snapshot into `canonical/sblgnt/` (~11 MB on
disk) and loads it into the catalog. On the reference box the entire first
run — fetch, parse, load — took **about 3 seconds** and ended with 27
books / 7,939 verses loaded, plus a `discovery:` accounting line (selected
· skipped-by-rule · unrecognized) so nothing is silently dropped.

Check the shelf:

```
$ bin/nabu status
…
vulgate             m           ?REPROBE     73/36K  08-14 08:12 +73
eng-web             m           ?REPROBE     84/38K  08-14 08:12 +84
sblgnt              m                       27/7.9K  08-14 08:12 +27
…
```

One dense row per source: a fused kind/enablement/cadence column (`m` =
a wired source on manual cadence; `a` = auto, `f` = frozen; modules and
shelves say so by name), a liveness cell that stays silent unless
something needs attention (`?REPROBE` above flags upstreams due a fresh
probe), compact docs/passages holdings, and the last run's `MM-DD HH:MM`
stamp with its zero-suppressed delta. (Those lines are from the
reference box after its 2026-08-14 full re-sync, hence every row's `+`
delta; your first run shows the same `+27`. `nabu status sblgnt` gives
the labeled long form.)

## 3. First search

```
$ bin/nabu search "λογος" --limit 3
urn:nabu:ddbdp:o.krok:2:228:b2:3 [grc]
  […] [λόγος] μοι λόγος ἐστὶν
urn:nabu:ddbdp:p.oxy:8:1151:16 [grc]
  ὁ [λόγος] καὶ ὁ λόγος
urn:nabu:glaux:2042-005:1090034 [grc]
  εἰ γὰρ" [λόγος]" μὲν ἀναγέγραπτο" λόγος δὲ θεοῦ" μὴ εἴρ…
3 hits (snippet shows the text as stored; matching is fold-aware)
```

Search is diacritic-insensitive (type `λογος` bare and still hit the
polytonic editions), FTS5 under the hood, bm25-ranked; the snippet shows
the text as stored — pristine accents, the match in [brackets] — while
the matching stays fold-aware. With only sblgnt synced your top hits
land in John's prologue instead: the papyri and the Origen line above
come from this box's fuller library.

## 4. Read a passage

Every hit is a URN; `show` renders a passage, a whole document, or a
citation range:

```
$ bin/nabu show urn:nabu:sblgnt:john:1.1-1.3
urn:nabu:sblgnt:john — ΚΑΤΑ ΙΩΑΝΝΗΝ [grc]
  source: sblgnt   license: attribution   revision: 1
  range: urn:nabu:sblgnt:john:1.1 … urn:nabu:sblgnt:john:1.3  [3 of 878 passages]
    :1.1  Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος.
    :1.2  οὗτος ἦν ἐν ἀρχῇ πρὸς τὸν θεόν.
    :1.3  πάντα διʼ αὐτοῦ ἐγένετο, καὶ χωρὶς αὐτοῦ ἐγένετο οὐδὲ ἕν. ὃ γέγονεν
```

Every query command documents itself with worked examples: `bin/nabu help
search`, `help show`, `help align`, `help export`.

## 5. Grow the library

Each shelf is one `sync` command. Real on-disk sizes from the reference
box, so you know what you're signing up for:

| Sync | Unlocks | Canonical size |
|---|---|---|
| `bin/nabu sync vulgate` + `sync eng-web` | Latin + English witnesses for `align`, OT included | 357 MB each |
| `bin/nabu sync perseus-greek` | the Greek canon + English translations | 910 MB |
| `bin/nabu sync perseus-latin` | the Latin classics | 220 MB |
| `bin/nabu sync gretil` | 780 Sanskrit editions | 303 MB |
| `bin/nabu sync papyri-ddbdp` | 61k documentary papyri (the big one — a multi-minute load) | 2.3 GB |

(`lexica` and `proiel` — the dictionary shelf and the 5-way parallel NT
with lemma search — are already on board from the starter shelf.)

The full menu is `config/sources.yml`; the full shelf map with research
uses is [library.md](library.md). Each further shelf is one
`bin/nabu enable <source>` (or `enable <axis>` for a whole desk)
followed by its `sync`. (`bin/nabu sync --all` is deliberately narrow —
it sweeps only the enabled `sync_policy: auto` sources, three rows on
the reference box today, the rolling upstream clones; it is not the
library-wide updater.)

With the dictionaries on board:

```
$ bin/nabu define ἀγάπη
ἀγάπ-η [grc] — A Greek-English Lexicon (Liddell-Scott-Jones) [attribution]  urn:nabu:dict:lsj:n347
  gloss: love,

ἀγάπ-η, ἡ,
A. love, LXX Je. 2.2 , Ca. 2.7 , al.; … of the love of husband and wife, …
2. esp. love of God for man and of man for God, … cf. Ep.Rom. 5.8 ,
2 Ep.Cor. 5.14 , Ev.Luc. 11.42 , al.:—also brotherly love, charity,
1 Ep.Cor. 13.1 , al.
…
```

With PROIEL (or any treebank shelf) on board, search by dictionary form
instead of surface string:

```
$ bin/nabu search --lemma ἀγαπάω --lang grc --limit 3
urn:nabu:proiel:chron:121109 [grc]  ἀγαπάω → ἠγάπα
  εἶτα ἔφερεν ὁ καιρὸς καὶ οἰκείωσιν ἐμοῦ εἰς τὸν μακαρίτην καὶ ἀοίδιμον πατέρα αὐτοῦ καὶ τὰ ἔχρηζεν ἀ…
urn:nabu:proiel:chron:224686 [grc]  ἀγαπάω → ἀγαπῶ
  καὶ ἀγαπῶ νὰ ἠμπορῇ νά σε εἶχον μετ’ ἐμοῦ”.
urn:nabu:proiel:chron:89299 [grc]  ἀγαπάω → ἠγάπα
  Ὃ καὶ βασιλεὺς ἔστεργε μὲν ἀκουσίως, ἐπεὶ τὸν κὺρ Κωνσταντῖνον τὸν αὐθέντην μου, - πολλάκις με ἐπληρ…
3 hits (exact lemma match; text is pristine)
```

And with multiple witnesses of one work synced, `align` renders a citation
across all of them at once. With the shelves above you get Septuagint
(Swete, from `first1k-greek`), Clementine Vulgate, and the WEB English —
`3 of 3 witnesses`; the reference box, with the Hebrew, Aramaic, and
Syriac shelves also on board, attests seven:

```
$ bin/nabu align "JON 2.1"
JON 2.1 — Old Testament (Septuagint / Vulgate)
  7 of 7 witnesses attest this ref

LXX (Swete, First1K) — Jonas [grc]   license: attribution
  urn:cts:greekLit:tlg0527.tlg041.1st1K-grc1:2.1
    Καὶ προσέταξεν Κύριος κήτει μεγάλῳ καταπιεῖν τὸν Ἰωνᾶν· καὶ ἦν Ἰωνᾶς ἐν τῇ κοιλίᾳ τοῦ κήτους τρεῖς ἡμέρας καὶ τρεῖς νύκτας.

vulgate (Clementine) — Jonas [lat]   license: open
  urn:nabu:vulgate:jon:2.1
    Et præparavit Dominus piscem grandem ut deglutiret Jonam : et erat Jonas in ventre piscis tribus diebus et tribus noctibus.

…

WEB (English) — Jonah [eng]   license: open
  urn:nabu:eng-web:jon:2.1
    Then Jonah prayed to Yahweh, his God, out of the fish’s belly.
```

(The trimmed middle: the Masoretic Hebrew twice — OSHB and BHSA — the
Targum, and the Peshitta, each in its own script with a display footer
naming the transforms applied.)

(A textual-criticism bonus hiding in plain sight: the Greek and Latin count
this verse as 2.1 while the English tradition numbers it 1.17 — witnesses
are rendered by their own citation schemes, honestly.)

## 6. Talk to your library

The repo ships `.mcp.json`, so opening this directory in Claude Code
registers the read-only MCP server automatically — your assistant can
search, read, align, and define against everything you've synced, with a
license label on every passage. Registration recipes for Claude Desktop
and other clients: [mcp.md](mcp.md).

## Where next

- [library.md](library.md) — what's on every shelf and what it's good for.
- The README's feature tour — concordance, parallel display, export,
  protection story.
- [ops.md](ops.md) — when you're ready to put maintenance on a schedule.
