# Nabu

[![CI](https://github.com/arvicco/nabu/actions/workflows/ci.yml/badge.svg)](https://github.com/arvicco/nabu/actions/workflows/ci.yml)

**A personal, local, license-honest library of the ancient world — that your
AI tools can read.**

Nabu pulls the world's openly licensed digital corpora of antiquity — Homer
and the Greek canon, the Latin classics, documentary papyri from Egypt, the
Sanskrit epics, cuneiform tablets, the Bible in nine parallel witnesses,
Beowulf — into one library on your own disk. Everything is plain files plus
SQLite: searchable by word or by dictionary lemma, citable to the exact verse
or tablet line, honest about every text's license, and rebuildable from
scratch at any time. And because it ships a read-only [MCP
server](docs/mcp.md), the AI assistants you already use can search, quote,
and cite the whole library — while structurally unable to change a letter
of it.

Named for the Mesopotamian god of scribes, patron of the tablet house and
divine custodian of Ashurbanipal's library. It is not a website and not a
reader app: it is a pipeline plus a database, operated from the command
line, designed to outlive the services it draws from.

As of **2026-07-11** the shelves hold **72,734 documents / 3,143,750
passages** in some two dozen ancient languages — from proto-cuneiform
tablets of the late 4th millennium BCE to 17th-century Russian — plus
**168,133 dictionary entries** and **1.94 million gold lemma annotations in
13 languages**. (All numbers in this README are read from the live catalog,
never estimated.)

## Show me

Real commands, real output, pasted from live runs on 2026-07-11 (trims
marked with …).

One verse of Mark, across nine witnesses — Greek, Latin, Gothic, Old Church
Slavonic, Old English, and more — each with its license label:

```
$ bin/nabu align "MARK 2.3"
MARK 2.3 — New Testament (parallel witnesses)
  9 of 9 witnesses attest this ref

greek-nt — The Greek New Testament [grc]   license: nc
  urn:nabu:proiel:greek-nt:6563
    καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων.

latin-nt — Jerome's Vulgate [lat]   license: nc
  urn:nabu:proiel:latin-nt:10368
    et venerunt ferentes ad eum paralyticum qui a quattuor portabatur

gothic-nt — The Gothic Bible [got]   license: nc
  urn:nabu:proiel:gothic-nt:37435
    jah qemun at imma usliþan bairandans, hafanana fram fidworim.

marianus — Codex Marianus [chu]   license: nc
  urn:nabu:proiel:marianus:36421
    Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми.

wscp — West-Saxon Gospels [ang]   license: nc
  urn:nabu:proiel:wscp:102359
    & hi comon anne laman to him berende, þone feower men bæron.

WEB (English) — Mark [eng]   license: open
  urn:nabu:eng-web:mrk:2.3
    Four people came, carrying a paralytic to him.

… (Armenian, SBLGNT, and Clementine Vulgate witnesses trimmed)
```

Look up the first word of Western literature — with the dictionary's
citations resolved to live passages in your own catalog:

```
$ bin/nabu define μῆνις
μῆνις — A Greek-English Lexicon (Liddell-Scott-Jones) [attribution]  urn:nabu:dict:lsj:n67485
  gloss: wrath

μῆνις, Dor. and Aeol. μᾶν-, ἡ, gen.
A. μήνιος Pl. R. 390e , later μήνιδος Ael. Fr. 80 , … —wrath; from Hom.
downwds. freq. of the wrath of the gods, Il. 5.34 , al., A. Ag. 701 (lyr.),
… but also, generally, of the wrath of Achilles, Il. 1.1 , al. …

resolved citations (in this corpus — nabu show <urn>):
  Il. 1.1 → urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1
  Il. 5.34 → urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:5.34
  A. Ag. 701 → urn:cts:greekLit:tlg0085.tlg005.1st1K-grc1:701
  …
```

Search by dictionary form, not surface string — suppletion and all:

```
$ bin/nabu search --lemma λέγω --limit 3
urn:nabu:proiel:chron:108755 [grc]  λέγω → ῥηθέντος  (lay)
  ὅ περ ἦν καὶ αἴτιον τοῦ μὴ ἐλθεῖν τὸν γενήσαντά με εἰς τὸν Μορέαν μετὰ τοῦ αὐθεντοπούλου κὺρ Θωμᾶ εἰ…
urn:nabu:proiel:chron:121080 [grc]  λέγω → εἶπον, εἰπὲ  (lay)
  Πολλῶν οὖν λόγων δαπανηθέντων, τέλος ἐστάλησαν πρὸς τὸν ἄνθρωπον δύο τῶν κελλιωτῶν καὶ συντρόφων μου…
urn:nabu:proiel:chron:121083 [grc]  λέγω → εἴπω  (lay)
  Ἐγὼ δὲ νὰ ἀκούω παρὰ μὲν τῶν, ὅτι καλή ἐστι, παρὰ δὲ τῶν, ὅτι οὐ καλή, διὰ τὶ νὰ μηδὲν εἴπω·
3 hits (exact lemma match; text is pristine)
```

Pull a random tablet off the cuneiform shelf:

```
$ bin/nabu show --random --source oracc
urn:nabu:oracc:rinap-rinap1:Q003443:1 [akk]
  a-di {KUR}sa-u₂-e KUR-e ša ina {KUR}lab-na-na-ma it-tak-ki-pu-u₂-ni
  document: urn:nabu:oracc:rinap-rinap1:Q003443 — Tiglath-pileser III 30
  source: oracc   license: open   sequence: 0   revision: 1
  provenance:
    2026-07-10 18:36:28 +0200  loaded  nabu-loader
```

— a royal inscription of Tiglath-pileser III, "as far as Mount Saue, which
abuts Lebanon."

## Who this is for

- **Classicists.** The Perseus Greek and Latin canons plus First1KGreek —
  2,209 Greek and Latin editions with 872 aligned English translations
  (`show <urn> --parallel` pairs Vergil line by line). TLG-style proximity
  search, lemma-aware:

  ```
  $ bin/nabu search λόγος --near θεός --window 5 --lang grc
  urn:nabu:ddbdp:p.oxy:8:1151:18   [θεοσ] ην ο [λογοσ].          ← a papyrus amulet…
  urn:cts:…:tlg0031.tlg004…:1.1    …και [θεοσ] ην ο [λογοσ].     ← …quoting John 1:1
  ```

- **Biblical scholars.** The New Testament in up to **thirteen witnesses**
  (`align "MARK 2.3"` → Greek ×2, Latin ×2, Gothic, Armenian, five OCS
  manuscript editions incl. Assemanianus and both Marianus editions side by
  side, Old English, English), the Old Testament on the Septuagint ↔
  Vulgate ↔ English axis with the Greek/Hebrew Psalm numbering mapped
  honestly (`align "PSA 22.1"` shows WEB's 23.1 labeled).
- **Slavists & textual critics.** The OCS canon complete — Marianus,
  Zographensis, Assemanianus, Savvina kniga, Suprasliensis (folio-line
  cited, hyphen-split words searchable whole) — plus Old East Slavic from
  birchbark to Ruthenian chancery texts, and the ~1000 CE Freising
  Manuscripts in three aligned transcription layers.
- **Comparativists.** The reconstruction shelf walks attested words to
  their proto-forms and cognates, with corpus attestation counts:

  ```
  $ bin/nabu etym богъ --lang chu
  богъ [chu] → *bogъ [sla-pro] — gloss: god
  ← *bʰeh₂g- [ine-pro] — gloss: to divide, distribute, allot
    reflexes: [grc] ἔφᾰγον, [sa] भक्ष (bhakṣá), …
  ```

  Pure-ASCII input works (`etym bhewgh`); `--long` expands every reflex.
- **Indologists.** 780 GRETIL editions, 703k passages: Rāmāyaṇa, purāṇas,
  kāvya, dharmaśāstra, the Ṛgveda with Vedic accents preserved; commentary
  layers separately citable (kārikā vs. vṛtti).
- **Assyriologists.** 17,795 ORACC texts (CC0) across 33 projects — the
  complete State Archives of Assyria — with gold lemmatization in
  `search --lemma` and the running English translations aligned per line:

  ```
  $ bin/nabu show urn:nabu:oracc:saao-saa01:P224395:o.1-o.3 --parallel
  :o.1  akk  a-na LUGAL EN-ia
  :o.2  akk  ARAD-ka {1}10-ha-ti
  …     eng  To the king, my lord: Your servant Adda-hati. …
  ```

- **Medievalists.** The complete Anglo-Saxon Poetic Records (Beowulf cited
  by its real line numbers: `show urn:nabu:aspr:A4.1:1` → *Hwæt! We
  Gardena in geardagum*), the ISWOC treebank with West-Saxon Mark as an
  alignment-hub witness, and Bosworth-Toller on the dictionary shelf —
  `define aethele --lang ang` finds **æþele** through the æ/þ/ð folding.
- **Linguists & digital humanists.** 2.6M gold lemma rows in 14 languages
  with morphology facets (`search --lemma cyning --morph case=gen --lang
  ang`), distinctive-vocabulary profiles (`vocab urn:nabu:proiel:cic-off` →
  officium, honestas, decorum), and `export --format jsonl` streaming the
  corpus to your own tooling with license filters.
- **AI-tooling builders.** A hand-rolled, dependency-free MCP server over
  stdio (`bin/nabu mcp`, `.mcp.json` ships in-repo) exposes seven read-only
  tools — search, show, concord, align, define, etym, status — every
  passage carrying its license class, so a model can quote *and* cite
  responsibly. See [docs/mcp.md](docs/mcp.md).

## Quickstart

```
git clone <this repo> && cd nabu
bundle install          # Ruby 3.3+; deliberately small dependency set
bin/nabu sync sblgnt    # a small first shelf: the SBL Greek NT, ~11 MB, seconds
bin/nabu search "ἀγάπη" --limit 3
```

A fresh checkout works with zero configuration — every key in
`config/nabu.yml` has a working default. The full zero-to-first-search
walkthrough, with real outputs and honest sizes/timings for the bigger
shelves, is in **[docs/quickstart.md](docs/quickstart.md)**.

## What's on the shelves

Live counts as of 2026-07-11; the full shelf map with research uses per
shelf is **[docs/library.md](docs/library.md)**.

| Shelf | What's on it | Size | License |
|---|---|---|---|
| Classical Greek | Perseus: Homer, the tragedians, Herodotus, Plato, Galen… + 650 aligned English translations | 1,418 docs / 394,706 passages | CC BY-SA |
| Post-classical Greek | First1KGreek: Athenaeus, Philo, church fathers, Swete's Septuagint | 1,129 / 256,480 | CC BY-SA |
| Classical Latin | Perseus: Vergil, Ovid, Cicero, Livy, Tacitus… + 181 English translations | 534 / 391,799 | CC BY-SA |
| Documentary papyri | Papyri.info DDbDP: contracts, letters, tax receipts from a millennium of Egypt (Greek, Coptic, Latin, Arabic) | 61,389 / 921,248 | CC BY |
| Sanskrit | GRETIL: Rāmāyaṇa, purāṇas, kāvya, śāstra, Ṛgveda with Vedic accents | 780 / 703,068 | CC BY-NC-SA |
| Treebanks | PROIEL, TOROT, UD, ISWOC: gold lemma/morphology/syntax — parallel NT ×5, OCS→Middle Russian, Old English | 75 / 172,815 | mostly CC BY-NC-SA |
| Cuneiform | ORACC ×5 projects: Sumerian royal inscriptions, Sargon II letters, lexical lists, proto-cuneiform | 6,876 / 191,712 | CC0 |
| Biblical editions | Clementine Vulgate (73 books), SBL Greek NT, WEB English | 184 / 81,372 | PD / CC BY |
| Old English poetry | The complete ASPR: Beowulf, the Exeter Book, Dream of the Rood… | 349 / 30,550 | CC BY-SA |
| Reference shelf | LSJ + Lewis & Short (entries, not passages; `nabu define`) | 168,133 entries | CC BY-SA |

The newest arrivals (ISWOC, ASPR) are synced and searchable but still
marked `enabled: false` pending the routine owner sign-off; Bosworth-Toller
(Old English dictionary, CC BY 4.0) is registered and queued for its first
sync. Ranked expansion candidates live in the axis surveys:
[Old English](docs/oe-survey.md), [Slavic](docs/slavic-survey.md).

## Feature tour

| | |
|---|---|
| `nabu search QUERY` | FTS5 full-text search, bm25-ranked, diacritic-insensitive with per-language folding: `μηνιν` finds `μῆνιν`, `iuvenis`/`juvenis`/`iuuenis` all resolve. Filters: `--lang`, `--license`, `--limit`. Date/place axis (61,670 dated documents — HGV papyri + Slovene goo300k/IMP): `--from -300 --to -30` scopes by signed historical year (negative = BCE, no year 0), `--century 6` is one century's shorthand, `--place oxyrhynch%` filters provenance — `στρατηγ* --from 101 --to 300 --place oxyrhynch%` finds the Oxyrhynchite strategoi. |
| `nabu search --lemma FORM` | Dictionary-form search over 1.94M gold lemma rows in 13 languages — inflections, suppletion and all; hits carry glosses where the reference shelf knows the lemma. Add `--morph case=dat,number=pl` (UD feature vocabulary) to keep only attestations with that morphology, decoded evidence shown per hit — one façade over UD `feats` and PROIEL positional tags. |
| `nabu search A --near B [--window N]` | Proximity search: keep only hits where `B` is within `N` words of `A` in the same passage (FTS5 NEAR over the folded forms; default 10, `0` = adjacent, order-independent). `λόγος --near θεός` is John 1:1; composes with `--lemma` (the anchor expands to the lemma's attested surface forms first: `--lemma λέγω --near κύριος` finds `τάδε λέγει κύριος`) and `--lang`/`--license`/`--limit`. Both terms bracketed in the snippet. |
| `nabu show URN` | A passage, a whole document, or a citation range (`urn:…:1.1-1.10`) with license, revision, and full provenance trail. `--parallel` pairs the aligned English translation; `--random` pulls something off the shelf. |
| `nabu align REF` | One citation across every witness of a registered work (`config/alignments.yml`) — the parallel NT and the Septuagint ↔ Vulgate OT ship as flagships. |
| `nabu parallels URN` | Passage-anchored intertext: point at one passage and find where the corpus quotes or echoes it — reception discovery, not translation alignment. Query-time over the FTS index (no new schema): the anchor's 4-word grams are phrase-probed, candidates ranked by shared-gram count weighted by rarity, elision folded across editions (so Matthew 4:4 finds LXX Deuteronomy 8:3). One hit per document (duplicate witnesses grouped, loci counted), the shared phrase shown as evidence; a gold-lemmatized anchor also gets rare-lemma "echoes" (re-inflected allusion). `--long` expands the truncated evidence; `--lang`/`--license`/`--limit` scope. |
| `nabu align REF` | One citation across every witness of a registered work (`config/alignments.yml`) — the parallel NT and the Septuagint ↔ Vulgate OT ship as flagships. A whole-chapter or verse-range query clips at 200 refs by default; `--long` lifts that ceiling and renders every ref. |
| `nabu define LEMMA` | LSJ and Lewis & Short lookup, entry citations resolved to in-catalog passages. A leading `*` scopes to the Proto-Slavic/PIE/Proto-Germanic reconstruction shelves, whose entries list their descendant reflexes; `--long` expands the truncated "not attested here" list in full, grouped by language. |
| `nabu etym LEMMA` | The comparativist's walk: an attested lemma (богъ, guþ) → every reconstruction whose Wiktionary descendants name it → one hop up the proto-to-proto chain, each with cognates and corpus attestation counts. `--long` expands every truncated cognate list, grouped by language (compact is the default). |
| `nabu concord QUERY` | Classic KWIC concordance: keyword column-aligned in pristine text, corpus order — for scanning usage, not relevance. |
| `nabu vocab URN` | Lemma-frequency profile of a document, range, or passage against the gold-lemma corpus: total tokens, distinct lemmas, the most distinctive vocabulary (log-odds vs corpus — Caesar surfaces *legio*/*proelium*, Cicero's *De officiis* surfaces *officium*/*honestas*), and the in-document hapax legomena. Gold shelves only; a document without gold lemmas says so and names the annotated languages. `--long` lists every hapax (and every gold-bearing language) in full, escaping the `--limit` display cap. `--by-century` switches to diachronic mode: the shape of the dated corpus over time, or — with a text query — a word plotted across the centuries (`vocab --by-century 'στρατηγ*' --lang grc` peaks in the 2nd c. CE), bucketed by earliest year and honest about ranges that span more than one. |
| `nabu export --format plain\|jsonl` | Stream the corpus out, with `--lang`/`--license` filters — the longevity-hedge exit formats. |
| `nabu sync SLUG` / `sync --all` | Fetch and load a source (git, zip, or single-file HTTP); idempotent, non-destructive, every run recorded. |
| `nabu status` / `health` / `verify` | Per-source counts and run history, each row carrying an `up=` upstream-drift column (`up=ok(2d)` / `up=BEHIND(2d)` / `up=stale(30d)` / `up=?(never)` / `up=frozen`) so an update is an informed decision — `nabu status --remote` probes upstreams inline and refreshes it in one command; local trend + upstream drift checks; full bitrot/tamper re-verification of every canonical file. |
| `nabu mcp` | The read-only MCP server — six tools for Claude Code/Desktop and any MCP client. Recipes in [docs/mcp.md](docs/mcp.md). |

Two more tastes. Facing translation, span-grouped, honest when the English
is coarser than the Greek:

```
$ bin/nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.5 --parallel
urn:cts:greekLit:tlg0012.tlg001.perseus-grc2 — Iliad [grc]
  parallel: urn:cts:greekLit:tlg0012.tlg001.perseus-eng4 — Iliad [eng]
  aligned by citation: 0 paired, 1 block covering 5 lines, 0 grc only, 0 eng only
  :1.1
    grc  μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος
  :1.2
    grc  οὐλομένην, ἣ μυρίʼ Ἀχαιοῖς ἄλγεʼ ἔθηκε,
  …
  eng [:1.1 — covers :1.1–:1.39; range shows :1.1–:1.5]
    Sing, O goddess, the anger [mênis] of Achilles son of Peleus, that brought
    countless ills upon the Achaeans. …
```

And the concordance, here on Caesar's *virtus*:

```
$ bin/nabu concord --lemma virtus --width 30
…vetii quoque reliquos Gallos virtute praecedunt, quod fere cotidi…  urn:nabu:proiel:caes-gal:52552 [lat]
…i populi Romani et pristinae virtutis Helvetiorum.                   urn:nabu:proiel:caes-gal:52635 [lat]
…b eam rem aut suae magnopere virtuti tribueret aut ipsos despicer…  urn:nabu:proiel:caes-gal:52636 [lat]
…que suis didicisse, ut magis virtute contenderent quam dolo aut i…  urn:nabu:proiel:caes-gal:52637 [lat]
…
```

## Your collection cannot rot

Upstream projects restructure, lose funding, and disappear. Nabu is built
on the assumption that the library must outlive its sources:

- **Canonical vs. derived.** Upstream text lives as plain files in a
  git-tracked canonical layer — the permanent asset. All SQLite is derived
  and rebuildable: `nabu rebuild` regenerates the entire catalog from
  canonical data, proven byte-identical by test.
- **The attic.** Fetch is non-destructive: files an upstream deletes are
  copied to `canonical/<source>/.attic/` *before* the merge and stay live,
  searchable, and exportable — honestly labeled "retired upstream", keeping
  the license they were fetched under. A mass-deletion breaker aborts any
  sync that would withdraw more than 20% of a source.
- **The ledger.** Run history, license baselines, and revision records live
  in `db/history.sqlite3` — the one database no rebuild can wipe.
- **Backup with a drill.** `nabu backup` rsyncs everything non-derivable to
  a mounted external volume, and `rake ops:drill` proves it: backup →
  fresh-root restore → rebuild → verify → RESTORABLE, actually run against
  the full corpus.
- **Standing verification.** `nabu verify` re-parses every canonical file
  (attic included) and compares content hashes against the catalog;
  `nabu health` watches run-history trends and probes upstreams for drift.
  Every sync prints a discovery-accounting line (`selected ·
  skipped-by-rule · unrecognized`), so silent ingestion gaps are
  structurally visible.
- **Boring storage.** Files, git, SQLite. Restorable from an rsync with
  zero services.

Nothing is ever hard-deleted: withdraw, revise, journal.

## Status — honest

This is a **young, personal, early-development project** — built for one
scholar's research needs first and shared because the approach may be
useful to others.

- Developed and tested on macOS (Apple Silicon), Ruby 3.3+. Nothing is
  known to be Mac-specific except the ops templates (launchd), but no other
  platform is exercised.
- No packaged release, no gem, no versioned API; CLI flags may still
  change. GitHub Actions CI runs the full suite plus rubocop
  (`rake test` + `rake lint`, network-blocked, fast) on every push and pull
  request — the badge up top is the contract.
- Corpus numbers above are a snapshot of one live install, dated where they
  appear.
- The enrichment layer of the original vision (embeddings/semantic search,
  machine glossing, ad-hoc scan ingestion) is designed but not built — see
  [docs/01-concept.md](docs/01-concept.md) for where this is headed.
- Expect rough edges; expect the docs to be more honest than polished.

## Documentation

| Doc | One line |
|---|---|
| [docs/quickstart.md](docs/quickstart.md) | Zero to first search, copy-pasteable, honest about sizes and timings. |
| [docs/library.md](docs/library.md) | The shelf map: every corpus with contents, counts, licenses, and research uses. |
| [docs/01-concept.md](docs/01-concept.md) | The vision: what Nabu is, workflows, principles, what success looks like. |
| [docs/mcp.md](docs/mcp.md) | The MCP server: six read-only tools, registration recipes, quoting etiquette. |
| [docs/conventions.md](docs/conventions.md) | Field notes for working with ancient-text corpora (Unicode/NFC, citations, editions, licensing) — start here if you're new to the domain. |
| [docs/architecture.md](docs/architecture.md) | The design: layer model, adapter contract, store schema, retention machinery. |
| [docs/02-sources.md](docs/02-sources.md) | The source inventory: every corpus scouted, scored, and license-checked. |
| [docs/03-unlockable-sources.md](docs/03-unlockable-sources.md) | Sources not ingestible today, with concrete unlock paths. |
| [docs/oe-survey.md](docs/oe-survey.md) / [docs/slavic-survey.md](docs/slavic-survey.md) | Evidence-cited axis surveys ranking expansion candidates (and license-honest about what's blocked). |
| [docs/ops.md](docs/ops.md) | The runbook: maintenance cadence, launchd templates, what to do when a check goes red. |
| [docs/maintenance-and-extension.md](docs/maintenance-and-extension.md) | How this stays alive across years of intermittent attention. |

## How this is built

Nabu is developed by a model-tiered autonomous agent loop — work packets
executed by Claude models under TDD ground rules, with owner-approved phase
gates — documented in [docs/dev-loop.md](docs/dev-loop.md). This README is
refreshed at every gate to reflect what actually works.

```
bundle exec rake test    # full suite (network-blocked by WebMock; fast)
bundle exec rake lint    # rubocop
bin/nabu --help
```

Contributions: the project is early and personal; issues and conversation
are welcome, but expect the backlog to be driven by the owner's research
needs. The house rules for outside contributors — TDD, fixture discipline,
the DCO sign-off — are in [CONTRIBUTING.md](CONTRIBUTING.md); if you want to
add a source, `CLAUDE.md` and
[docs/maintenance-and-extension.md](docs/maintenance-and-extension.md)
describe the adapter checklist end to end.

## License

- **Code:** [MIT](LICENSE).
- **Content:** every ingested text keeps its upstream license, recorded
  per document as data (`open` / `attribution` / `nc`), and every surface —
  search hits, exports, MCP responses — carries the label. Roughly 99% of
  documents are public-domain or attribution-class; the `nc` shelves
  (GRETIL, most treebanks) are for non-commercial research use and are
  never redistributed by the tooling. Per-source terms:
  [docs/02-sources.md](docs/02-sources.md).
