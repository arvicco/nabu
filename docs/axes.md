# Research axes — the library's desks

The library is one flat list of corpora (the shelf map is
[docs/library.md](library.md); the code-per-language table is
[languages.md](languages.md)). This page is the other view of the same
sources: the **research axes** — the owner's scholarly desks, each a hat a
reader puts on to work one tradition, and the sources that serve it.

An axis is not a folder. It is a **tag** over the source list, and a source
wears every tag it serves — the Vulgate sits at the Classicist's desk for
its Latin and at the Biblical scholar's for its scripture; the UD treebanks
answer to nine desks at once. Multi-membership is the point, not an
accident to be tidied away.

Everything below documents **shipped behaviour** — the eighteen desks
defined in `config/axes.yml`, their memberships declared per source in
`config/sources.yml`, and the three command surfaces that read them. The
desk listing on this page is not hand-maintained: it is a projection of the
live registry, and a gate test (`test/docs/axes_page_test.rb`) fails the
build if the page and the registry ever disagree.

## What an axis is

- **Tags, not folders.** A source belongs to an axis by declaring it in the
  list-valued `axes:` key on its `sources.yml` row — one source, many axes.
  No axis owns a source; each merely serves it. A source appears under
  every axis it serves, and the surfaces say so once rather than pretending
  a shelf lives in a single place.

- **Dual-membership is deliberate.** Where a shelf answers two traditions,
  it is **tagged twice, never folded** — the honest choice over inventing a
  parent category. TLHdig's Hittite tablets ride both `cuneiform` and
  `hittite` (owner ruling D35-d — the lines are cuneiform script and they
  are Hittite language, so both desks are true). The reconstruction shelves
  sit on `etym` while their per-language lanes ride their own language
  desks. Every source declares at least one axis; an axis name may never
  equal a source slug, which is what lets `nabu sync <name>` resolve a bare
  name to a desk without ambiguity.

- **Whole-source membership, honest partial-fit notes.** Membership is at
  the grain of the whole source — there are no per-document axes in v1. When
  only part of a shelf truly belongs, the fit is stated in the desk's
  description rather than faked with a partition: GRETIL rides `buddhist`
  although only part of its Sanskrit shelf is Buddhist, and the
  reconstruction and treebank shelves ride several desks whole. The note is
  the honesty; the partition would be the lie.

## The desks

Eighteen desks, in the ratified order of `config/axes.yml` (which is also
the order the command surfaces render). Each leads with its **persona** —
the hat's one-line self-description, printed verbatim by `nabu list --axis`
and `nabu sync` — then the membership rationale, then the member slugs the
registry currently tags to it.

### classical

> The Classicist — Greek and Latin letters read whole, Homer to the late grammarians.

The Greco-Roman literary lane: the Perseus canons and First1KGreek, Diorisis, LSJ and Lewis & Short, the grc/lat treebanks, and the Vulgate wearing its Latin-literature hat beside its scripture one.

**Members** (8): `perseus-greek`, `perseus-latin`, `first1k-greek`, `ud`, `proiel`, `lexica`, `vulgate`, `diorisis`

### epigraphy

> The Papyrologist-Epigraphist — reads what survives on stone, sherd, papyrus and tablet, lacunae and all.

Documentary corpora at the artifact grain: papyri, the Latin/Greek and Levantine and Sicilian inscription databases, the Continental Celtic, Italic and Tyrsenian editions, ogham stones, Hittite tablets — the shelves where fragment search and findspots earn their keep.

**Members** (13): `papyri-ddbdp`, `edh`, `riig`, `ogham`, `isicily`, `itant`, `tlhdig`, `ceipom`, `open-etruscan`, `lexlep`, `lexlep-words`, `tir`, `iip`

### slavic

> The Slavicist — Cyril and Methodius to the damaskini, canon to vernacular.

Old Church Slavonic and its daughters: the OCS/Old Russian treebanks, the gospel and monument corpora, Freising, the Slovenian historical lane, Balkan damaskini, and the Church Slavonic dictionary shelves.

**Members** (10): `ud`, `proiel`, `torot`, `ccmh`, `goo300k`, `imp`, `damaskini`, `wiktionary-cu`, `freising`, `sl-lexica`

### germanic

> The Germanicist — Gothic, Old English verse and prose, the northern word-hoard.

Old English poetry (ASPR) and prose (ISWOC) with Bosworth-Toller, and Gothic riding the proiel/ud treebanks.

**Members** (5): `ud`, `proiel`, `iswoc`, `aspr`, `bosworth-toller`

### celtic

> The Celticist — from Lepontic stones to the Old Irish glossators.

Continental Celtic epigraphy (RIIG, Lexicon Leponticum and its word shelf), ogham Primitive Irish, CorPH's Early Irish, the UD Old Irish treebanks, and the kaikki attested-Celtic extracts riding wiktionary-recon.

**Members** (7): `ud`, `wiktionary-recon`, `riig`, `ogham`, `corph`, `lexlep`, `lexlep-words`

### italic

> The Italicist — the languages of pre-Roman Italy, Oscan to Etruscan to Raetic.

The Sabellic, Etruscan, Venetic and Raetic epigraphic shelves (CEIPoM, ItAnt, the Etruscan editions, TIR), Lepontic at the Celtic border, I.Sicily's island mix, and the Sabellic-to-Latin loan lane.

**Members** (10): `wiktionary-recon`, `isicily`, `itant`, `sabellic-loans`, `ceipom`, `open-etruscan`, `larth-etp`, `lexlep`, `lexlep-words`, `tir`

### etym

> The Comparative Indo-Europeanist — laryngeals, reflex chains, the long descent of words.

The reconstruction shelves: the kaikki proto-extracts, IE-CoR cognacy, LIV, the Leiden Latin dictionary, StarLing's bases, and the curated loan edges. Non-IE lanes of the same shelves ride their own axes too — dual-tagging, never folding.

**Members** (6): `wiktionary-recon`, `iecor`, `liv`, `edl`, `starling`, `sabellic-loans`

### biblical

> The Biblical scholar — one text across Hebrew, Greek, Latin, Syriac, Coptic and English witnesses.

The cross-language scripture hat: the Masoretic shelves and the Scrolls, the Greek NT, Vulgate and WEB, Peshitta and the Syriac corpus, Coptic Scriptorium, the Targums, and the OSHB-BHSA bridging module. The hebrew and syriac language desks coexist with this hat by design.

**Members** (13): `vulgate`, `eng-web`, `sblgnt`, `coptic-scriptorium`, `oshb`, `sdbh`, `sefaria`, `bhsa`, `bridging`, `dss`, `hebrew-lexicon`, `peshitta`, `syriac-corpus`

### hebrew

> The Hebraist — Masoretic vowels, Qumran consonants, the Aramaic of the Targums.

The Hebrew-and-Aramaic language desk beside the cross-language biblical hat: OSHB, BHSA, DSS, SDBH and the lexicon shelf, the Sefaria Targums, the bridging crosswalk, and IIP's inscriptions of Israel/Palestine.

**Members** (8): `oshb`, `sdbh`, `sefaria`, `bhsa`, `bridging`, `dss`, `iip`, `hebrew-lexicon`

### syriac

> The Syriacist — the Peshitta and the estrangela bookshelf.

The Syriac language desk: the ETCBC Peshitta and the Digital Syriac Corpus, riding beside the biblical hat by design.

**Members** (2): `peshitta`, `syriac-corpus`

### hittite

> The Hittitologist — Anatolia in cuneiform, KBo and KUB by tablet and line.

The Hittite desk: TLHdig's tablet corpus (dual-tagged cuneiform by ruling — its lines also carry Akkadian, Sumerian, Luwian, Hattic, Hurrian) and the UD Hittite treebank.

**Members** (2): `ud`, `tlhdig`

### cuneiform

> The Assyriologist — Sumerian, Akkadian, Ugaritic, Hittite: the tablet world entire.

The cuneiform-culture shelves: Oracc and CDLI, ETCSL's Sumerian literature, eBL's fragments, the Copenhagen Ugaritic Corpus (alphabetic cuneiform), and TLHdig shared with the Hittitologist.

**Members** (6): `oracc`, `tlhdig`, `etcsl`, `cdli`, `ebl`, `cuc`

### egyptian

> The Egyptologist — hieroglyphs to Coptic, one language across four millennia of script.

The Egyptian-Coptic continuum: the TLA corpora and word list (tla-hf, aes, aed), the Coptic lexicon with its egy-cop crosswalk, and Coptic Scriptorium.

**Members** (5): `ccl`, `coptic-scriptorium`, `tla-hf`, `aes`, `aed`

### indic

> The Indologist — Veda to sastra, the Sanskrit library and its instruments.

The Sanskrit, Prakrit and Pali lane: GRETIL and SARIT, the DCS treebank, Monier-Williams, the Vedic UD treebank, and SuttaCentral's canon.

**Members** (6): `ud`, `gretil`, `mw`, `suttacentral`, `sarit`, `dcs`

### buddhist

> The Buddhologist — the dharma across the Pali, Sanskrit and Chinese canons.

Cross-cutting by design: SuttaCentral, CBETA, SARIT, and GRETIL whole — membership is whole-source, so GRETIL rides here although only part of its shelf is Buddhist.

**Members** (4): `gretil`, `suttacentral`, `sarit`, `cbeta`

### sinitic

> The Sinologist — the classical Chinese written world and its phonological deep past.

Literary and classical Chinese with its reconstruction instruments: Kanripo and CBETA, TLS, Baxter-Sagart and the Qieyun-system database, Unihan, the Heian hanzi dictionaries, the UD lzh treebanks, SuttaCentral's Agamas, and the kaikki zh extract riding wiktionary-recon.

**Members** (11): `ud`, `wiktionary-recon`, `suttacentral`, `baxter-sagart`, `tshet-uinh`, `unihan`, `hdic`, `babelstone-ids`, `cbeta`, `kanripo`, `tls`

### japonic

> The Japanologist — Old Japanese song to the Sino-Japanese dictionary tradition.

The Japanese lane: the ONCOJ corpus and lexicon, EDRDG's dictionaries, HDIC and Unihan shared with the Sinologist, and the kaikki ojp extract riding wiktionary-recon.

**Members** (7): `wiktionary-recon`, `unihan`, `edrdg`, `hdic`, `kradfile`, `oncoj`, `oncoj-lexicon`

### local

> The Librarian — the owner's own shelves: dossiers, library, notes, and the sources' own records.

The canonical-memory shelves (architecture §16): local-language, local-library, local-notes, local-source.

**Members** (4): `local-language`, `local-library`, `local-notes`, `local-source`

## Working the axes — the commands

Three shipped surfaces read the registry. All three take an axis by name;
axis names never collide with source slugs, so a bare name resolves
unambiguously to a desk.

- **`nabu list --axis`** — the shelf census grouped under the desks. Bare
  `--axis` renders every desk in the ratified order; `--axis slavic` renders
  one; `--axis slavic,celtic` renders those, in the order named. Each desk
  leads with its persona line, then its member rows indented beneath. A
  source appears under every desk it serves (stated once). An unknown axis
  name is refused with the known set listed; the plain ungrouped census is
  unchanged.

- **`nabu status --axis`** — the same grouping over the status table
  (enablement, last sync, drift). Same bare / one / comma-list forms, same
  ratified order, same appears-under-each-desk rule.

- **`nabu sync <axis>`** and **`nabu sync --axis a,b`** — sync a desk's
  members. A bare positional name resolves **exact slug first, then axis**:
  a real slug syncs that one source, and a name that is not a slug but is a
  desk expands to that desk's members. `--axis a,b` selects several desks
  and prints one group each, in order. Expansion is pure per-source fan-out:
  each member syncs exactly as `sync <slug>` would, its report line
  byte-unchanged, under a one-line axis header.

  **The asymmetry to know:** an axis expansion is *not* an explicit
  per-source request, so **disabled members are skipped** — reported by name
  on one `skipped (disabled): …` line, never silently — whereas
  `sync <disabled-slug>` (an explicit request) syncs the disabled source
  anyway, with a note. The desk is a convenience over the enabled shelf; the
  slug is a direct order.

  ```
  nabu list --axis                      # the whole census, grouped by desk
  nabu list --axis slavic               # one desk's shelves
  nabu status --axis celtic,italic      # two desks' health
  nabu sync celtic                      # the celtic desk's enabled members
  nabu sync --axis celtic,italic --parse-only
  ```
