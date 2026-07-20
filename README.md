# Nabu

[![CI](https://github.com/arvicco/nabu/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/arvicco/nabu/actions/workflows/ci.yml) [![DOI](https://img.shields.io/badge/DOI-10.5281%2Fzenodo.21361957-blue.svg)](https://doi.org/10.5281/zenodo.21361957)

**A personal, local, license-honest library of the ancient world — that your
AI tools can read.**

Project site: **[arvicco.github.io/nabu](https://arvicco.github.io/nabu)** —
the library, tools, and sources presented in full, without the README
compression.

Nabu pulls the world's openly licensed digital corpora of antiquity — Homer
and the Greek canon, the Latin classics, documentary papyri from Egypt, the
Sanskrit epics, cuneiform tablets, the Bible in fifteen parallel witnesses,
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

As of **2026-07-19** the shelves hold **737,299 documents / 11,357,320
passages** in nearly a hundred language codes — from proto-cuneiform
tablets of the late 4th millennium BCE to 19th-century Slovenian, with
the Ancient Near East the newest arrival: the Hittite tablet corpus, the
CDLI's 353,156-artifact cuneiform catalog, the eBL Fragmentarium,
Ugaritic, a millennium of Syriac, and the Sumerian literary canon in two
scholarly editions — plus **711,376 dictionary entries** across
thirty-nine dictionary shelves and **over 12.4 million gold lemma
annotations in 22 languages** (a further 8.0 million ride an honestly
labelled silver tier). (All numbers in this README are read from the
live catalog, never estimated.)

## Quickstart

```
git clone https://github.com/arvicco/nabu && cd nabu
bundle install                 # Ruby 3.3+; deliberately small dependency set
bin/nabu quickstart            # the starter shelf: 4 sources, ~690 MB, minutes — then:
bin/nabu align "MARK 2.3"      # one verse, seven witnesses
bin/nabu search --lemma λέγω   # dictionary-form search: λέγουσι, εἶπας, εἰπεῖν…
bin/nabu define λόγος          # the whole LSJ entry, citations resolved
```

A fresh checkout works with zero configuration. The long form —
prerequisites, honest sizes and timings, growing the library, MCP
registration — is the site's
**[Quickstart](https://arvicco.github.io/nabu/quickstart/)** page
(kept in-repo as [docs/quickstart.md](docs/quickstart.md)).

## Show me

Real commands, real output, pasted from live runs on 2026-07-11/12 (trims
marked with …).

One verse of Mark across the aligned witnesses — Greek, Latin, Gothic, Old
Church Slavonic, Old English, and more — each with its license label (this
run predates the Sahidic and Bohairic Coptic witnesses that joined
2026-07-13, making fifteen registered):

```
$ bin/nabu align "MARK 2.3"
MARK 2.3 — New Testament (parallel witnesses)
  13 of 13 witnesses attest this ref

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

… (Armenian, SBLGNT, Clementine Vulgate, and the four CCMH OCS witnesses trimmed)
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

- **Biblical scholars.** The New Testament in up to **fifteen registered
  witnesses** (`align "MARK 2.3"` → Greek ×2, Latin ×2, Gothic, Armenian,
  five OCS manuscript editions incl. Assemanianus and both Marianus
  editions side by side, Old English, English, and — live since 2026-07-13
  — Sahidic and Bohairic Coptic), the Old Testament on the Septuagint ↔
  Vulgate ↔ English axis with the Greek/Hebrew Psalm numbering mapped
  honestly (`align "PSA 22.1"` shows WEB's 23.1 labeled).
- **Slavists & textual critics.** The OCS canon complete — Marianus,
  Zographensis, Assemanianus, Savvina kniga, Suprasliensis (folio-line
  cited, hyphen-split words searchable whole) — plus Old East Slavic from
  birchbark to Ruthenian chancery texts, and the ~1000 CE Freising
  Manuscripts in three aligned transcription layers. `align REF --collate`
  turns the aligned witnesses into an apparatus: a raw-token diff per
  script family (the four Helsinki-ASCII CCMH codices collated against each
  other; the Cyrillic Marianus set beside them, honestly not collated
  because the fold cannot bridge the two transcription systems).
- **Comparativists.** The reconstruction shelf walks attested words to
  their proto-forms and cognates, with corpus attestation counts:

  ```
  $ bin/nabu etym богъ --lang chu
  богъ [chu] → *bogъ [sla-pro] — gloss: god
  ← *bʰeh₂g- [ine-pro] — gloss: to divide, distribute, allot
    reflexes: [grc] ἔφᾰγον, [sa] भक्ष (bhakṣá), …
  ```

  Pure-ASCII input works (`etym bhewgh`); `--long` expands every reflex.
  And `cognates` crosses that crosswalk with the alignment hub — verses
  where the witnesses use reflexes of the same root, found blind:

  ```
  $ bin/nabu cognates "LUKE 14.34" --langs got,chu
  LUKE 14.34  *sḗh₂l [ine-pro · attribution]
      chu  соль — attested as солъ
      got  salt
  ```

  The whole Gothic × OCS NT yields ~300 such verses across 30 roots in
  under a second (hlaifs ~ хлѣбъ, malan ~ млѣти, menoþs ~ мѣсѧць), each
  hit labeled with its meet shelf — a gem-pro meet for a Slavic word is
  flagged reading matter: likely a borrowing, not common descent.
- **Indologists.** 780 GRETIL editions, 703k passages: Rāmāyaṇa, purāṇas,
  kāvya, dharmaśāstra, the Ṛgveda with Vedic accents preserved; commentary
  layers separately citable (kārikā vs. vṛtti).
- **Papyrologists.** 61k DDbDP documents, and fragment search that reads
  like an edition: type the damaged line brackets and all, and `--fuzzy`
  matches it INSIDE words (trigram index over papyri + ORACC + EDH,
  sub-10 ms):

  ```
  $ bin/nabu search --fuzzy ']ανδρα μοι εν['
  urn:nabu:ddbdp:bgu:6:1470:ctr:6 [grc]
    μαρτυροι. [ανδρα μοι εν]νεπε μουσα πολυτρο
  1 hit (fuzzy substring; highlights are diacritic-folded)
  fuzzy index covers: oracc, papyri-ddbdp
  ```

  — BGU 6.1470, a Hellenistic writing exercise breaking off mid-word
  through the Odyssey's opening line (…Μοῦσα πολύτρο[πον). *(Live output
  of 2026-07-13; the EDH inscriptions joined the index's scope later that
  day — it now covers 1.71M passages.)*
- **Epigraphists.** 81,881 Latin inscriptions from the Epigraphic Database
  Heidelberg (CC BY-SA; a preservation snapshot of the archived upstream) —
  81,416 of them dated (2026-07-14 census), with the library's first genre
  facets: `search
  --type epitaph --province Britannia --material marble` composes with the
  date and place filters, and the stones are in the `--fuzzy` index. Since
  2026-07-17 the epigraphic shelves speak Celtic too: 428 Gaulish
  inscriptions (RIIG, with per-editor readings and French translations)
  and ~500 Irish ogham stones in real Ogham codepoints with aligned
  transliteration layers.
- **Celticists.** The CorPH corpus (ERC ChronHib) brings 7th–10th-century
  Early Irish with gold lemmatization — the Annals of Ulster, Vita
  Columbae, Blathmac, and the Milan/St Gall/Würzburg gloss corpora —
  joined by two Old Irish UD treebanks, the Gaulish and ogham epigraphy
  above, and Old/Middle Irish and Middle Welsh dictionary extracts on the
  reference shelf.
- **Assyriologists.** 21,692 ORACC documents (CC0) across 33 projects —
  12,781 tablets and inscriptions, the complete State Archives of Assyria
  among them, plus 8,911 aligned English translations — with gold
  lemmatization in
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
- **Linguists & digital humanists.** Over 2.85M gold lemma rows in 17 languages
  with morphology facets (`search --lemma cyning --morph case=gen --lang
  ang`), distinctive-vocabulary profiles (`vocab urn:nabu:proiel:cic-off` →
  officium, honestas, decorum), and `export --format jsonl` streaming the
  corpus to your own tooling with license filters.
- **AI-tooling builders.** A hand-rolled, dependency-free MCP server over
  stdio (`bin/nabu mcp`, `.mcp.json` ships in-repo) exposes ten read-only
  tools — search, show, concord, align, define, etym, parallels, cognates,
  links, status — every passage carrying its license class, so a model can quote
  *and* cite responsibly. See [docs/mcp.md](docs/mcp.md).

## What's on the shelves

Live counts as of 2026-07-14; the full shelf map with research uses per
shelf is **[docs/library.md](docs/library.md)**.

| Shelf | What's on it | Size | License |
|---|---|---|---|
| Classical Greek | Perseus: Homer, the tragedians, Herodotus, Plato, Galen… + 650 aligned English translations | 1,418 docs / 394,706 passages | CC BY-SA |
| Post-classical Greek | First1KGreek: Athenaeus, Philo, church fathers, Swete's Septuagint | 1,129 / 256,480 | CC BY-SA |
| Classical Latin | Perseus: Vergil, Ovid, Cicero, Livy, Tacitus… + 181 English translations | 534 / 391,799 | CC BY-SA |
| Documentary papyri | Papyri.info DDbDP: contracts, letters, tax receipts from a millennium of Egypt (Greek, Coptic, Latin, Arabic) | 61,414 / 921,611 | CC BY |
| Latin inscriptions | Epigraphic Database Heidelberg: epitaphs, dedications, milestones from the whole empire — 81,416 dated (2026-07-14 census), genre/province/material facets | 81,881 / 406,306 | CC BY-SA |
| Coptic | Coptic Scriptorium: the complete Sahidic + Bohairic NT, monastic and patristic prose — gold-lemmatized (233k rows) | 482 / 74,169 | CC BY per doc (source class nc) |
| Sanskrit | GRETIL: Rāmāyaṇa, purāṇas, kāvya, śāstra, Ṛgveda with Vedic accents | 780 / 703,068 | CC BY-NC-SA |
| Treebanks | PROIEL, TOROT, UD, ISWOC: gold lemma/morphology/syntax — parallel NT ×5, OCS→Middle Russian, Old English, Old Irish glosses | 80 / 178,278 | mostly CC BY-NC-SA |
| Cuneiform | ORACC ×33 projects: the complete State Archives of Assyria, royal inscriptions, lexical lists, proto-cuneiform — with 8,911 aligned English translations | 21,692 / 385,243 | CC0 |
| Biblical editions | Clementine Vulgate (73 books), SBL Greek NT, WEB English | 184 / 81,372 | PD / CC BY |
| Old English poetry | The complete ASPR: Beowulf, the Exeter Book, Dream of the Rood… | 349 / 30,550 | CC BY-SA |
| Slavic & Slovenian | CCMH OCS gospel codices, the ~1000 CE Freising Manuscripts, goo300k + IMP Early Modern Slovenian (1584–1899), the damaskini Balkan Slavic witnesses (15th–19th c., with English siblings) | 839 / 456,189 | CC BY (Freising BY-ND) |
| Celtic | CorPH Early Irish (gold-lemmatized: Annals of Ulster, the great gloss corpora), RIIG Gaulish inscriptions (with French siblings), the Ogham in 3D stones (real Ogham codepoints + transliteration layers) | 1,387 / 20,318 | CC BY / MIT (ogham `nc` pending clarification) |
| Reference shelf | LSJ + Lewis & Short + Bosworth-Toller + Monier-Williams + Wiktionary OCS + ten Wiktionary reconstruction/Celtic shelves + the IE-CoR / LIV / de Vaan etymological witnesses + the five StarLing bases (Pokorny, PIET, **Vasmer**, Germanic, Baltic) + three Slovenian historical dictionaries incl. Pleteršnik (`nabu define` / `etym`) | 633,137 entries | CC BY-SA / CC BY / CC BY-NC-SA / grant |

All 38 registered sources are enabled and synced — 34 upstream sources
plus four local shelves (the language dossiers and source dossiers live,
the owner's library shelf holding its first 20 ingested documents, the
notes shelf awaiting its first annotation). The etymology desk now hears
from three tiers of witnesses: the Wiktionary-derived chains, the
expert-curated trio synced 2026-07-14 — **IE-CoR** (4,981 cognate sets /
26,325 reflex rows, 2,308 loan-flagged), **LIV-LOD** (305 PIE verbal
etymons), **de Vaan's Etymological Dictionary of Latin** (2,860
etymons) — and, since 2026-07-17, the five **StarLing / Tower of Babel
bases** under a written grant: Pokorny's complete IEW (2,222 roots),
Nikolayev's PIE database (3,291 etymologies), **Vasmer's etymological
dictionary of Russian** (18,239 entries), and the Common Germanic and
Baltic databases. The same sync wave landed the **Slovenian historical
dictionary shelf** (Pleteršnik 1894–95, the Svetokriški Baroque lexicon,
and the complete 16th-century word inventory — 139,405 entries), the
**damaskini** Balkan Slavic corpus, and the library's **Celtic axis**:
CorPH's gold-lemmatized Early Irish, the RIIG Gaulish inscriptions, the
Ogham in 3D stones, three attested-Celtic Wiktionary extracts, and two
Old Irish UD treebanks.
A local **language-dossier shelf** holds the library's language curation
as 199 plain-Markdown files (`canonical/local-language/` — edit in any
editor, `nabu sync local-language` re-derives the `nabu language` cards),
and a **source-dossier shelf** carries a curated description of every
registered source, served on `nabu list` and gate-checked against the
shelf map by `rake site:check`.
Ranked expansion candidates live in the per-axis surveys (Old English,
Slavic, PIE, …) — private planning material under gitignored
`.docs/surveys/`; their license-checked verdicts land in
[docs/02-sources.md](docs/02-sources.md).
There is also a shelf for your own PDFs, scans and articles
(`canonical/local-library/` — manifest-catalogued, `research_private` by
default so nothing you scanned is ever served or redistributed,
page-cited where a text layer exists). `nabu ingest FILE...` is its front
door — and it takes http(s) URLs too, downloading first (redirects
followed) and recording the URL you gave in the manifest's `source_url:`
lane: it copies the file in (never moves your original), derives metadata
candidates mechanically (PDF metadata, filename, sha256), walks you
through confirming them — interactively, AI-assisted (`--assist
script/ingest-assist-claude` prefills the prompts with a model's
suggestion), or scripted (`--yes` plus flags) — then syncs the shelf and
prints the minted urn:

```
bin/nabu ingest ~/scans/vaillant-1950-manuel.pdf --collection slavistics
```

After that the manual is `show`-able by page, searchable where it carries
text, and `links`-wired to the passages its manifest entry names as
`related:`.

## Feature tour

| | |
|---|---|
| `nabu search QUERY` | FTS5 full-text search, bm25-ranked, diacritic-insensitive with per-language folding: `μηνιν` finds `μῆνιν`, `iuvenis`/`juvenis`/`iuuenis` all resolve. Filters: `--lang`, `--license`, `--source SLUG` (one shelf — it composes with every other filter, `--lemma`/`--near`/`--fuzzy` included), `--limit`. Date/place axis (163,821 dated/placed documents live — EDH inscriptions 81,416, HGV papyri, ORACC catalogue/regnal dates 21,558, TOROT chronicle annals, Slovene goo300k/IMP, Coptic manuscript dates — so `--century -7` reaches the Assyrian letters): `--from -300 --to -30` scopes by signed historical year (negative = BCE, no year 0), `--century 6` is one century's shorthand, `--place oxyrhynch%` filters provenance — `στρατηγ* --from 101 --to 300 --place oxyrhynch%` finds the Oxyrhynchite strategoi. Genre facets (256,518 rows live from EDH): `--type epitaph --province Britannia --material marble` composes with all of the above. |
| `nabu search --lemma FORM` | Dictionary-form search over 2.85M+ gold lemma rows in 17 languages (Old Irish and Bulgarian joined 2026-07-17) — inflections, suppletion and all; hits carry glosses where the reference shelf knows the lemma. Add `--morph case=dat,number=pl` (UD feature vocabulary) to keep only attestations with that morphology, decoded evidence shown per hit — one façade over UD `feats` and PROIEL positional tags. Beside gold and the labeled silver shelves, the **equivalence** tier: CEIPoM's scholar-curated Classical-Latin keys on pre-Roman Italy's Oscan/Umbrian/Faliscan passages — `search --lemma precor` reaches the Iguvine Tables' `pesnimu`, every hit tagged `[equivalence]`, never counted as attestation, `--gold-only` excludes. |
| `nabu search --loans CODE` | The language-contact facet (Coptic Scriptorium today): keep only passages carrying loanwords from a donor language — `search ⲛⲟⲩⲧⲉ --lang cop --loans grc` (131K+ Greek loan tokens tagged), composing with text, `--lemma`, `--fuzzy`, `--near` and every catalog filter. `nabu list coptic-scriptorium --loans` prints the donor-language census; `--loans grc` enumerates the most loan-saturated documents. |
| `nabu search A --near B [--window N]` | Proximity search: keep only hits where `B` is within `N` words of `A` in the same passage (FTS5 NEAR over the folded forms; default 10, `0` = adjacent, order-independent). `λόγος --near θεός` is John 1:1; composes with `--lemma` (the anchor expands to the lemma's attested surface forms first: `--lemma λέγω --near κύριος` finds `τάδε λέγει κύριος`) and `--lang`/`--license`/`--limit`. Both terms bracketed in the snippet. |
| `nabu search --fuzzy FRAGMENT` | Damaged-text fragment search: substring matching ANYWHERE in a passage, mid-word included — `']μηνιν αει['` works typed straight off the edition (editorial brackets stripped, then the same per-language folding as plain search). Character-trigram index over the DOCUMENTARY shelves only (papyri-ddbdp + oracc + edh, `fuzzy_index: true` in the registry — corpus-wide would cost 15×), candidates verified by real substring match; every render names the indexed scope. The production index is LIVE (1,713,135 passages indexed as of 2026-07-14, EDH aboard). Fragments need ≥3 characters; composes with `--lang`/`--license`/`--limit`/date-place filters; `--long` prints the whole folded passage. For literary half-memories use plain search or `parallels`. |
| `nabu show URN` | A passage, a whole document, or a citation range (`urn:…:1.1-1.10`) with license, revision, and full provenance trail. `--parallel` pairs the aligned English translation; `--random` pulls something off the shelf. |
| `nabu parallels URN` | Passage-anchored intertext: point at one passage and find where the corpus quotes or echoes it — reception discovery, not translation alignment. Query-time over the FTS index (no new schema): the anchor's 4-word grams are phrase-probed, candidates ranked by shared-gram count weighted by rarity, elision folded across editions (so Matthew 4:4 finds LXX Deuteronomy 8:3). One hit per document (duplicate witnesses grouped, loci counted), the shared phrase shown as evidence; a gold-lemmatized anchor also gets rare-lemma "echoes" (re-inflected allusion). `--long` expands the truncated evidence; `--lang`/`--license`/`--limit` scope. `--batch SCOPE` flips the engine to corpus-wide mining: every anchor of a source slug or urn prefix, hits persisted as `kind=parallel` edges in the links journal (top `--per-anchor` per anchor at `--min-score`+, both named in the summary — no silent caps); reruns supersede, interactive output never persists. |
| `nabu formulas SCOPE` | The oral-formulaic reader's mirror of `parallels`, pointed inward: mine the repeated formulas WITHIN a corpus slice (a source slug or a work/urn prefix) — the same gram machinery, counting instead of probing. Homer's `ὣς ἔφαθ' οἵ δ'` (72×), `τὸν δ' ἀπαμειβόμενος προσέφη πολύμητις Ὀδυσσεύς` (50×); the Old English `saga hwæt ic hatte` riddle refrain, `Beowulf maþelode bearn Ecgþeowes`, `awa to feore`. Ranked by count × length — no stoplist, the ranking is self-filtering (a genuine formula out-recurs any function-word run; measured). `--lang` mines one tradition where a source mixes translations; `--gram-size`, `--min-count`, `--limit`, `--long` (every locus). Zero schema, ~0.2 s per slice. `--batch SCOPE` persists the sweep as `kind=formula` edges: a STAR per formula (hub = its first locus in urn order, one edge to every other locus, the gram riding each edge's detail, the count its score — all-pairs would explode quadratically), top `--max-formulas` by rank; reruns supersede, interactive output never persists. |
| `nabu links URN` | The mined cross-reference graph, read back: every batch-produced edge touching a urn, both directions, grouped by kind (parallel, formula, cognate), counterparts resolved to title/language, each kind's evidence rendered natively (a parallel's score, a formula's `“gram” ×count` pointing at the refrain's hub, a cognate's `ref · root [shelf]` meet), provenance footer citing the producer run (scope, params, code version, date). Edges are urn-keyed in their own journal (`db/links.sqlite3`) so they survive `nabu rebuild` untouched; `show` grows a one-line `linked: N formula, M parallel` footer counting the kinds present when edges exist. `--long` lists every edge per kind. |
| `nabu align REF` | One citation across every witness of a registered work (`config/alignments.yml`) — the parallel NT and the Septuagint ↔ Vulgate OT ship as flagships. A whole-chapter or verse-range query clips at 200 refs by default; `--long` lifts that ceiling and renders every ref. `--collate` diffs the witnesses into a compact apparatus (base reading + per-witness divergences) per (language, script) group, with cross-script witnesses rendered undiffed and labelled honestly; `--base LABEL` picks the base. |
| `nabu define LEMMA` | Dictionary-shelf lookup — LSJ, Lewis & Short, Bosworth-Toller, Monier-Williams (193,890 entries live: SLP1 transcoded to IAST, so `define amsa` reaches aṃśa/aṃsa, RV./BhP. citations resolving into the GRETIL shelf at verse grain, MW's own Gk./Lat./Goth. cognate notes feeding `etym`), Wiktionary OCS — entry citations resolved to in-catalog passages/documents. The TLS Chinese shelf resolves at SENSE grain: `define 棄` lists where each sense is attested in the classics (189K sense-level attributions), the Kanripo-held texts resolving to page or document urns and coverage growing as the kanseki waves sync. A leading `*` scopes to the seven reconstruction shelves (Proto-Slavic/PIE/Proto-Germanic plus the four intermediates), whose entries list their descendant reflexes; `--long` expands the truncated "not attested here" list in full, grouped by language. |
| `nabu etym LEMMA` | The comparativist's walk: an attested lemma (богъ, guþ) → every reconstruction whose Wiktionary descendants name it → one hop up the proto-to-proto chain, each with cognates and corpus attestation counts. Multi-hop closure (PIE \*per- → PBS → \*pьrstъ → chu/orv in one walk) and per-edge "(loan)" flags are live, and so — since their 2026-07-14 first syncs — are the three independent expert-curated witnesses: IE-CoR's cognate sets ride the same walk (`etym срьдьцє` → \*k̑erd- with grc καρδία ~ lat cor ~ got hairto beside kaikki's \*ḱérd-, curated loan events labelling their edges `(loan)`), LIV supplies the PIE verbal roots, and de Vaan's EDL the lat → Proto-Italic → PIE Leiden chains. `--long` expands every truncated cognate list, grouped by language with each code named inline (`[gkm · Medieval Greek]`; compact is the default). |
| `nabu language CODE` | The code desk reference: any language code the library surfaces — corpus tags (`chu`, `san-Latn`) and the 803 Wiktionary etymology codes in `etym`'s cognate lists (`gkm`, `zle-ort`, `zlw-opl`) — explained on one card: name (from the derived names census, filled at the owner's 2026-07-14 wiktionary resyncs), family, curated historical context (file-backed since P19-1: one Markdown dossier per code under `canonical/local-language/`, 199 live — edit in any editor, `nabu sync local-language` re-derives the card), and live holdings (documents/passages, gold-lemma rows, dictionary shelves, etymology edges; zero fields suppressed). An unknown code misses honestly with a family hint. `--list` prints the held languages; `--long` adds per-source counts and the upstream-code edge split. |
| `nabu cognates TARGET` | Cognates in parallel: verses of an alignment work where witnesses in ≥2 languages use reflexes of the same reconstruction root — the hub × crosswalk join (`cognates nt --langs got,chu` → salt~соль at \*sḗh₂l, hlaifs~хлѣбъ at \*hlaibaz, ~300 verses / 30 roots in under a second). TARGET is a work id, verse, chapter, or book; every hit names its meet SHELF (a gem-pro meet for a Slavic word reads as a borrowing); corpus-common words suppressed with an honest count (`--all` lifts); `--long` lifts the 200-hit cap and expands detail. `--batch WORK` persists the whole-work map as `kind=cognate` edges between the cross-language witness passages of each meet, the meet itself (`ref · root [shelf]`) riding each edge's detail; reruns supersede, interactive output never persists. |
| `nabu concord QUERY` | Classic KWIC concordance: keyword column-aligned in pristine text, corpus order — for scanning usage, not relevance. |
| `nabu vocab URN` | Lemma-frequency profile of a document, range, or passage against the gold-lemma corpus: total tokens, distinct lemmas, the most distinctive vocabulary (log-odds vs corpus — Caesar surfaces *legio*/*proelium*, Cicero's *De officiis* surfaces *officium*/*honestas*), and the in-document hapax legomena. Gold shelves only; a document without gold lemmas says so and names the annotated languages. `--long` lists every hapax (and every gold-bearing language) in full, escaping the `--limit` display cap. `--by-century` switches to diachronic mode: the shape of the dated corpus over time, or — with a text query — a word plotted across the centuries (`vocab --by-century 'στρατηγ*' --lang grc` peaks in the 2nd c. CE), bucketed by earliest year and honest about ranges that span more than one. |
| `nabu export --format plain\|jsonl` | Stream the corpus out, with `--lang`/`--license`/`--source` filters — the longevity-hedge exit formats. |
| `nabu ingest FILE-or-URL...` | The intake front door for your own material: copies a PDF/scan/article into the local-library shelf (`research_private` by default — never served or redistributed) — or downloads an http(s) URL first, recording it in the manifest — derives metadata candidates mechanically, confirms them interactively / AI-assisted (`--assist CMD`) / scripted (`--yes`), then syncs and prints the minted urn. `--shelf language CODE` scaffolds a language dossier, `--shelf source SLUG` a source dossier. |
| `nabu note URN [TEXT]` | Owner annotations — scholia of one's own — on any urn the corpus knows (documents, passages, ranges, dictionary entries), resolution-checked before any write, stored as plain YAML on the local-notes shelf. Bare `nabu note URN` reads back what you said; `--list` enumerates; `--force` records a deliberately dangling note on planned material. Notes render on `show`/`define`/`links` and are served over MCP with their target's withholding rules. |
| `nabu sync SLUG` / `sync --all` | Fetch and load a source (git, zip, or single-file HTTP — or re-scan a local shelf); idempotent, non-destructive, every run recorded. The name resolves slug-first-then-axis: `sync celtic` (or `--axis a,b`) expands a research axis to its enabled members, grouped, and names any disabled members on one skip line (an axis is not an explicit request, so a disabled member is skipped where an explicit `sync SLUG` would sync it anyway). |
| `nabu list [SOURCE]` | The what-is-held view (`status` is the sync-state view): bare, a content census — one line per shelf with document/passage/entry counts, languages, the effective license-class mix, withdrawn/retired counts when nonzero. With a SOURCE, one shelf's card (identity, credit line, counts, per-language breakdown, dictionaries, date-axis coverage, facet and collection summaries). `--documents` / `--entries` / `--collections` enumerate (default `--limit 50`, `0` = all, honest "… N more" tail), with `--lang`/`--license`/`--withdrawn`/`--from`/`--to`/`--century` filters on documents and `--prefix` folded headword-prefix filtering on entries (`bh` finds `*bʰer-`). `--axis` groups the census under the research axes (the owner's desks) — bare, every axis in ratified order with its persona line; `--axis slavic` or `--axis a,b` selects some — a source appearing under each axis it serves. |
| `nabu status` / `health` / `verify` | Per-source counts and run history, each row carrying an `up=` upstream-drift column (`up=ok(2d)` / `up=BEHIND(2d)` / `up=stale(30d)` / `up=?(never)` / `up=?(re-probe)` when a cached verdict predates the last sync / `up=frozen`) so an update is an informed decision — `nabu status --remote` probes upstreams inline and refreshes it in one command; local trend + upstream drift checks; full bitrot/tamper re-verification of every canonical file. `health` also runs the mechanical postcondition invariants (P18-7): failed-run/partial-load surfacing, flag-vs-artifact and synced-vs-populated mismatches, pending migrations, and quarantine counts as a DELTA against an audited baseline — plus an optional `sync --review CMD` AI-review hook, off by default. |
| `nabu mcp` | The read-only MCP server — ten tools for Claude Code/Desktop and any MCP client. Recipes in [docs/mcp.md](docs/mcp.md). |

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
- Versioned releases begin at **v1.0.0** (cut at the Phase-19 gate;
  citation metadata ships in [CITATION.cff](CITATION.cff)); there is no
  gem and CLI flags may still change between releases. GitHub Actions CI
  runs the full suite plus rubocop (`rake test` + `rake lint`,
  network-blocked, fast) on every push and pull request — the badge up
  top is the contract.
- Corpus numbers above are a snapshot of one live install, dated where they
  appear.
- The enrichment layer of the original vision (embeddings/semantic search,
  machine glossing) is designed but not built — see
  [docs/01-concept.md](docs/01-concept.md) for where this is headed.
  Ad-hoc ingestion of your own material shipped as `nabu ingest`
  (Phase 19); OCR/HTR for image-only scans still waits on local inference
  hardware.
- Expect rough edges; expect the docs to be more honest than polished.

## Documentation

| Doc | One line |
|---|---|
| [docs/quickstart.md](docs/quickstart.md) | Zero to first search, copy-pasteable, honest about sizes and timings. |
| [docs/library.md](docs/library.md) | The shelf map: every corpus with contents, counts, licenses, and research uses. |
| [docs/01-concept.md](docs/01-concept.md) | The vision: what Nabu is, workflows, principles, what success looks like. |
| [docs/mcp.md](docs/mcp.md) | The MCP server: ten read-only tools, registration recipes, quoting etiquette. |
| [docs/conventions.md](docs/conventions.md) | Field notes for working with ancient-text corpora (Unicode/NFC, citations, editions, licensing) — start here if you're new to the domain. |
| [docs/architecture.md](docs/architecture.md) | The design: layer model, adapter contract, store schema, retention machinery. |
| [docs/02-sources.md](docs/02-sources.md) | The source inventory: every corpus scouted, scored, and license-checked. |
| [docs/03-unlockable-sources.md](docs/03-unlockable-sources.md) | Sources not ingestible today, with concrete unlock paths. |
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
the DCO sign-off — and the issue templates for requesting sources and
features or reporting a wrong reading are in
[CONTRIBUTING.md](CONTRIBUTING.md); if you want to add a source,
`CLAUDE.md` and
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
