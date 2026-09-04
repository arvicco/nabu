# Languages of the library

**As of 2026-09-04** (the P95 gate — five phases past the EEBO
wave: ~106.9M live passages across the 181-row registry; live
inventory: every code below appears in the catalog, the lemma
index, or the reference shelf). This page explains the code system
once, then lists the significant codes with one sentence each (the
corpus now carries 167 document language codes; the long tail of
single-inscription script variants is folded into grouped rows).

**The headline pair is Arabic and English.** **`ara` (Classical
Arabic) remains the library's largest language — 33.3M passages** —
with **`en` (Early Modern English) second at 24.3M** (EEBO-TCP whole);
`lzh` (Literary Chinese, 18.7M — the hanmun written tradition beyond
China: Korea's state records and Đại Việt's annals ride it) is third,
Latin (3.49M) fourth, Japanese (3.16M) fifth, Sumerian (3.04M) sixth,
and Ancient Greek (3.02M) seventh. Below them the seven-figure floor
has widened: Korean-tradition holdings (`ko` 1.48M via OKHC),
Classical Tibetan (`xct` 1.36M — the Derge canon), Middle English
(1.36M), Persian (`fas` 1.35M), and German (`de` 1.18M — the DTA
print era whole, P94).

**The desk reference is a command (P18-4), and languages are now
file-backed (P19-1):** `nabu language CODE` explains any code this page
covers AND the **803-code** Wiktionary etymology universe the `etym`
cognate lists surface (`gkm`, `zle-ort`, `zlw-opl`…) — name, family,
curated context, live holdings, and (since 2026-07-28) the related
research axes: an `axes:` line naming the desks whose shelves hold the
code, in ~0.2 s. **The curation's home is
the `local/shelves/local-language/` dossier shelf (architecture §16)** — one
Markdown file per code, edit it in any editor, then `nabu sync
local-language` re-derives the card. The owner-fired migration is
complete: the dossiers on disk derive the catalog's `language_records`
(name, family, context, and the IE-CoR witness sections — that shelf's
first programmatic writer), and the `config/languages.yml` seed is
retired. The derived names census (`language_names`, from the held kaikki
extracts) is **filled** — 160 name records, feeding the inline
`[gkm · Medieval Greek]`-style rendering in `etym --long` (superseded,
where nabu-lects is synced, by the resolved-lect reading — "The lect
layer" below).
`nabu ingest --shelf language CODE` scaffolds a new dossier;
`nabu language --list` prints the held languages.

## The system, in five rules

1. **Codes are BCP-47-shaped**: a primary language subtag (ISO 639: `grc`,
   `lat`, `chu`…), optionally followed by a **script subtag** (`san-Latn` =
   Sanskrit in Latin transliteration) or another qualifier. Validation is
   shape-only, so a few deliberate non-ISO codes pass (rule 4).
2. **The code names the language of the passage text as stored** — not the
   manuscript's, not the modern nation's. GRETIL stores IAST romanization,
   so its Sanskrit is `san-Latn`; the UD Vedic treebank stores Devanagari-
   independent CoNLL-U, so it is plain `san`. CCMH stores the corpus's own
   7-bit transliteration but the *language* is still `chu`.
3. **Historical stages ride the nearest standard code, documented**: Old
   East Slavic, Middle Russian, and Ruthenian all live under `orv`
   (following Universal Dependencies); Early Modern Slovenian and the
   ~1000 CE Freising Manuscripts under `sl` (no better subtag exists —
   an acknowledged anachronism).
4. **Reconstruction shelves use Wiktionary's etymology codes verbatim**
   (`sla-pro`, `ine-pro`, `gem-pro`) — non-ISO, kept because they join
   directly against the upstream descendants data (conventions §4).
5. **Search folding is per-language** (conventions §9): the code picks the
   rule — `grc` final-sigma, `lat` u/v–i/j, `ang` æ→ae/þ,ð→th,
   `sl`/`gmh` ſ→s (Slovenian and the ReM Middle High German diplomatic
   text), `akk`/`sux` determinative stripping, generic diacritic folding
   elsewhere. Where a source's language differs from a tool's expectation,
   the per-document override records reality (P10-4).

## The lect layer

Everything above is the code system this library has always spoken —
ISO-639-shaped tags, one per stored passage/entry, folded and searched as
documented in the five rules. **nabu-lects** (P57-3/4;
github.com/arvicco/nabu-lects) is a SEPARATE, OPTIONAL module layered on
top: a small curated registry of *lects* — language varieties identified by
genealogical anchor × historical stage × variety × orthography
(`lat:med` = Medieval Latin; `grc:byz` = Byzantine Greek; `ine:pro` =
Proto-Indo-European) — plus a universal mapping from the codes above onto
them. It answers a question the code system alone cannot: not just "what
language is this passage tagged," but "which SPECIFIC historical stage of
that language, and is it a reconstruction or attested."

**It changes nothing about storage.** Stored codes are exactly as documented
above, forever (rule 2's promise). `Nabu::Lects` (`lib/nabu/lects.rb`) is a
pure READ resolver: `#resolve(code, source:, urn:)` maps a stored code onto
a lect id, `#lect(id)` looks up its name/band/mode, `#reconstructed?(id)`
asks whether it is a comparative-method reconstruction (a registry field,
never a guess from the code's spelling — rule 4's `-pro` convention is a
Wiktionary joining convention, not evidence of reconstruction; nabu-lects
registers the real distinction, e.g. Rundata's `gmq-pro` runic inscriptions
are ATTESTED epigraphy filed under a proto-looking tag).

**Resolution precedence, highest first**: a per-document ruling (the lect
journal, `db/lects.sqlite3` — P58-1: urn-keyed assignments that survive
`nabu rebuild` and ride backups, written by `nabu lect assign` at hand
grain and by the ratified compilers at batch grain: `lect apply-rules`
turns period/corpus facet values into stages, `lect infer-dates` stages a
document whose date interval sits inside exactly one stage band; every
row states its basis and `lect check-dates` audits the lot against the
documents' own dates) → a per-source override
(`config/lect_overrides.yml`, Nabu-authored — what one particular source's
use of a code actually means in its holdings, e.g. DÉRom's `la-vul` really
means the reconstructed `roa:pro`, not Wiktionary's attested-register
default) → the module's own universal codemap → identity (an unmapped code
resolves to itself as a bare anchor — always legal, honest coarseness).

**Feature-detected everywhere it surfaces, never required**: `Nabu::Lects
.load_default` returns `nil` when `canonical/nabu-lects` has not been
synced (`nabu sync nabu-lects`), and every consumer below degrades to its
pre-P57-4 behavior byte-for-byte in that case — the cldf-spine/nabu-data
posture, same as every other optional module this library carries (Pleiades,
the Oracc Sign List, Tibetan word segmentation).

Since P58-4 the resolved lect is also MATERIALIZED as an ordinary
document facet (`document_facets`, facet `lect`, rows only where the
resolution differs from the bare code — "no row means identity"), so the
stage is a first-class query axis: `show` prints it on the facets line,
`search --lect` filters by it at every grain including per-document
rulings, and the `language` ladder counts from it. As of 7 August 2026
the journal holds 500,985 assignments and the facet 587,317 rows
(P59-0 repaired the reversed-interval extractor cluster — 82 defective
dating rows across six sources — and the date-band re-run recovered the
affected documents' assignments with zero refusals; P61-3 added 3,424
`~script` surface claims via the byte-verified codemap suite and the
artifact-claiming overrides; P62 extended the akk/sux period rules to
ORACC's own catalogue labels — +90,383 stage assignments in one apply,
and corpus dating coverage rose 64.4% → 77.4%).

Consumers as of P57-4 (ladder counts facet-backed since P58-6):

- **`nabu language CODE`** grows a `stages:` ladder when the code is a
  registered anchor with stages: each stage ord-sorted with its band and
  live document counts (aggregated by resolving every held (language,
  source) pair through the registry); reconstructed stages carry a leading
  asterisk; codes that resolve to the bare anchor group under one honest
  `unstaged` line.
- **`search --lect LECT-ID`** (CLI) and **`nabu_search`'s `lect` parameter**
  (MCP) filter hits to passages whose (language, source) resolves to the
  given lect or a MORE SPECIFIC one under it — prefix semantics over the
  `:`/`/`/`@` axis grammar (`--lect lat` matches `lat:med`; `--lect lat:med`
  matches `lat:med` and `lat:med/xyz`, not `lat:cla`). A resolution-level
  filter: stored codes are never touched. Errors, naming the module, when
  nabu-lects is not synced.
- **`nabu etym`**'s reconstruction predicate (the display asterisk, and the
  reconstruction-shelf scope for a direct `*headword` lookup) resolves the
  dictionary's (language, source) and asks `#reconstructed?` instead of
  testing the code for a `-pro` suffix — the class of correction Rundata's
  `gmq-pro` needed. Its cognate-language brackets also prefer the resolved
  lect id + composed name (`[grc:byz · Byzantine Greek]` for `gkm`, the
  codemap default) over the older kaikki-census name where nabu-lects
  supplies one — display-only, additive.

Absent the module, every one of the above reads exactly as it did before
P57-4: no ladder section, no `--lect` flag (a clear error naming the
module if used), the old `-pro`-suffix string test, the old bracket names.

## Corpus languages (documents / passages)

| Code | Language | One sentence |
|---|---|---|
| `lzh` | Literary Chinese | The library's third-largest language (18.7M passages) — the Kanripo classical-Chinese repository and the CBETA Buddhist canon (Taishō + Xuzangjing), plus the HDIC Heian-period character-dictionary line — and now the hanmun written tradition beyond China: Korea's dynastic records (the sillok, the Royal Secretariat's daily registers, the Goryeo histories, the ITKC classics) and Đại Việt's annals, the Korean wave's first syncs landed 2026-08-18/19. Since P37-2, traditional/simplified/z-variant spellings fold to one search skeleton (conventions §9). |
| `grc` | Ancient Greek | The third *Western* language (Latin and EEBO's English ahead) — seventh overall at 3.02M passages — Homer through the papyri to Swete's Septuagint, both Greek NTs, and the EDH bilinguals, polytonic. |
| `sux` | Sumerian | The language isolate of the earliest written literature, from Ur III royal inscriptions to the great lexical lists — 3.03M passages, the largest cuneiform language. |
| `akk` | Akkadian | East Semitic language of Babylon and Assyria, held in transliteration with ORACC's gold lemmas (SAA letters, omens, royal inscriptions) — joined at scale by the CDLI and eBL fragment shelves, and since 2026-08-18 by the Achemenet archives: 2,774 Achaemenid-period legal/administrative texts and letters (Murašû, Eanna, Sippar), silver-lemmatized with English glosses. |
| `san-Latn` | Sanskrit (IAST romanization) | The GRETIL, SARIT, and DCS shelves — Vedas to early-modern śāstra — stored in the international transliteration scheme with accents preserved (0.84M passages). |
| `san` | Sanskrit (Devanagari / CoNLL-U) | The UD Vedic treebank and the gold-lemmatized Digital Corpus of Sanskrit; `san-Deva` holds the Devanagari-scripted SARIT slice separately. |
| `pli` | Pali | The SuttaCentral Tipiṭaka — the segmented Pali canon (0.44M passages), aligned to its English and the Chinese Āgamas. |
| `sl` | Slovenian (historical) | Early Modern print (Dalmatin 1584 → 1899), the IMP historical-Slovene corpus, PriLit's earliest narrative prose (1643–1866, P95 — the Cigler multi-edition collation case), and, by lineage, the ~1000 CE Freising Manuscripts (0.42M passages; 29 works staged sl:emod + 8 sl:mod by print-year inference). |
| `hit` | Hittite | The Anatolian cuneiform corpus at fragment scale — the TLHdig transliterations beside the lexical-list entries, gold- and silver-lemmatized (0.36M passages). |
| `syc` | Classical Syriac | The Digital Syriac Corpus (632 TEI documents) and the ETCBC Peshitta OT — extending the Aramaic axis by a millennium (0.17M passages). |
| `egy` | Egyptian | The Ancient Egyptian Sentences (AES/TLA) and Late-Egyptian/Demotic Hugging-Face shelves — 0.12M gold-lemmatized passages from the Pyramid Texts onward; `egy-Egyd` holds a couple of Demotic papyri separately. |
| `lat` | Latin | Republican and Imperial classics, Jerome's Vulgate, the Clementine bible, papyrus fragments, the Romance-wave shelves (BFM's medieval Latin side, CroALa, digilibLT, openMGH), Migne's Patrologia Latina (corpus-corporum, live 2026-08-21 — 5,248 patristic and medieval works / 0.9M passages, library.md §8ai) — and the EDH + EDR inscriptions, ~196,000 epigraphic documents (library.md §8g, §8aa); 3.08M passages (2026-08-21). |
| `cop` | Coptic | The last stage of Egyptian: documentary papyri plus the literary Coptic Scriptorium shelf in Sahidic and Bohairic, gold-lemmatized (233,020 rows; library.md §8f). |
| `qpc` | Proto-cuneiform | The pre-linguistic administrative tablets of the late 4th millennium BCE (dcclt archaic lists) — signs before language. |
| `hbo` | Biblical Hebrew | The Masoretic shelves — OSHB Westminster Leningrad, the BHSA/ETCBC treebank, the Dead Sea Scrolls — gold-lemmatized, NFC-exempt (0.09M passages). |
| `xeb` | Eblaite | The eBL/Ebla East-Semitic lexical material from the cuneiform fragment shelves (0.05M passages). |
| `arc` | Aramaic / Targumic | The Sefaria Targum shelf, DSS Aramaic, and cuneiform-shelf traces — now 0.05M passages, gold-lemmatized where the Targums carry it. |
| `ara` | Arabic | **The library's largest language (33,294,039 passages, loaded 2026-07-22)** — the OpenITI corpus: hadith, history and biography, law, falsafa, the dīwāns; unannotated (no gold lemmas — full-text and the AH timeline are the instruments), cross-searchable with Persian under the Arabic-script fold; beside it DiCCAS (P95), disaster accounts excerpted from ten classical sources with catastrophe terminology tagged. |
| `fas` | Persian | The Persian shelf of OpenITI (1.33M passages — Ḥāfiẓ, Niẓāmī, ʿAṭṭār, Ibn Sīnā) plus, since P95, Hafez's Divan as a proper CTS edition with its aligned English (perseus-farsilit, 17,637 seg-grain passages); folded to the same Arabic-script skeleton as ara (ی/ي, ک/ك), either keyboard finds either language. |
| `chu` | Old Church Slavonic | The OCS canon: Codex Marianus, Suprasliensis, and the four CCMH gospel manuscripts (incl. Assemanianus and Savvina kniga). |
| `orv` | Old East Slavic (incl. Middle Russian, Ruthenian) | Birchbark letters, chronicles, Avvakum, and the prosta mova chancery texts, 1025–1700. |
| `ojp` | Old Japanese | The Oxford-NINJAL Corpus of Old Japanese (ONCOJ) — gold-morphology Man'yōshū-era verse, gold-lemma language #23 (123,002 rows). |
| `ang` | Old English | Beowulf and the complete ASPR poetry plus the ISWOC prose/gospel treebank, ca. 700–1150 — and, since P95, Klaeber's 1922 Beowulf as a second edition with its aligned English translation card-for-card (perseus-anglit). |
| `sga` / `mga` | Old & Middle Irish | The CorPH Palaeohibernicum and the Ogham corpus — the Celtic axis, gold-lemmatized in CorPH. |
| `got` | Gothic | Wulfila's Bible — the oldest substantial Germanic text, gold-lemmatized in PROIEL. |
| `gmh` | Middle High German | The ReM reference corpus (1050–1350), synced live 2026-07-22: 406 manually annotated texts / 355,449 manuscript lines, diplomatic layer stored (long ſ folds to s — rule 5) — and instantly the corpus's **third-largest gold-lemma pool** (2.10M rows). |
| `gml` | Middle Low German (incl. Low Rhenish) | The ReN reference corpus (1200–1650), adapter landed P46-5 (`ren`, `wired: false` — counts land at the owner-fired first sync): 161 gold pos+msd+lemma texts + 74 transcribed-only, expected ~297,594 manuscript lines; the 28 texts upstream classes *niederrheinisch* ride `gml` with an `upstream_language` marker (no `dum` split invented). |
| `non` / `gmq-pro` | Old Norse / Proto-Norse | The North Germanic lane (synced live 2026-07-22): Menotec's seven Old Norwegian treebanks and the Poetic Edda of Codex Regius (gold PROIEL-scheme morphology), plus Rundata's runic corpus in transliteration with its Old-West-Norse normalisation lane — 39,923 passages; the urnordisk-dated inscriptions carry `gmq-pro` (the wiktionary-recon proto-code convention of rule 4 — no ISO code exists; 822 passages). |
| `isl` / `nor` / `swe` / `dan` | The Menota manuscript codes | The Medieval Nordic Text Archive (P82, live 2026-08-24, 91/91 after the P82-r1 recovery — 241,628 diplomatic manuscript-line passages): per-file modern ISO codes with manuscript dating, the Handbook's own doctrine — `isl` 53 (Laxdæla saga, the Codex Wormianus, AM homilies), `nor` 30 (Konungs skuggsjá, the Landslǫg laws, the homily book — staged `no:old` by date inference over the №R-42 nabu-lects v1.1.0 mints), `swe` 4, `dan` 2 (Codex Runicus, Mariaklagen → `da:old`); the deprecated house code `onw` (1 doc) rides a per-source override — ISO says Old Nubian. |
| `enm` | Middle English | The Corpus of Middle English (P82, live 2026-08-24): 297 texts / 1,355,279 passages — Chaucer, Sir Gawain, the mystery cycles, Piers Plowman, the MED's own quotation base over the new `tcp-xml` family; registry band 1100–1500 under parent `ang`, joining ASPR and Bosworth-Toller on the English descent ladder. |
| `en` | Early Modern English | EEBO-TCP Phase I (P83, live 2026-08-27, the million-crossing wave): 24,857 English docs of the 25,368-text corpus — everything printed in England 1473–1700 that the TCP hand-keyed, Milton to broadside petitions; 20,981 staged `en:early` (nabu-lects v1.2.0, [1500, 1700]) by imprint-date inference. The English descent ladder is now populated at every rung: ang (ASPR/ISWOC) → enm (CME) → en:early. The corpus's minority lanes ride verbatim: `lat` 381 (28 → lat:ren), `wel` 59, `sco` 27, `fre`/`dut`/`frm` tails. |
| `osx` | Old Saxon | The *Heliand* (HeliPaD, synced live 2026-07-22): 3,549 syntactically parsed tree blocks with gold form-lemma pairs — the 9th-century gospel harmony beside its Gothic and Old English gospel cousins. |
| `is` | Icelandic (diachronic) | IcePaHC via UD, live 2026-07-22 — the 12th–21st c. under the one modern tag (the `orv`/Middle-Russian precedent of rule 3): 44,029 passages whose 812,484 gold rows enter straight at #4 of the lemma pools. |
| `sv` | Old Swedish (under the modern tag) | Fornsvenska textbanken, live 2026-08-18 — the medieval law codes, prose and rhymed chronicles, 170,872 sentence passages; no ISO code exists for Old Swedish (the IcePaHC-under-`is` precedent of rule 3), so the stage rides the `sv:old` lect minted in nabu-lects (PR #4). |
| `osp` | Old Spanish | The Old Spanish Textual Archive (osta), live 2026-08-18 — 684 documents of semi-paleographic manuscript transcription (5,091 passages), with the codices' Leonese (`ast`), Navarro-Aragonese (`arg`, under the `an:old` lect) and Latin work layers coded per document from the archive's own works tables. |
| `spa` | Spanish (diachronic) | The DISCO sonnet corpus, live 2026-08-18 — 4,527 sonnet passages by 1,216 authors, 15th–20th c., under the one modern tag (the etym-desk reflex code, so cognate joins connect); per-line meter and rhyme ride as labelled machine annotations. |
| `jpn` | Japanese | The Aozora Bunko reading desk (synced live 2026-07-21): 2.99M passages of Meiji-and-later public-domain literature, ruby readings as annotations, kyūjitai works reachable through the reform fold (rule 5 / conventions §9). |
| `okm` | Middle Korean | The 용비어천가 shelf (ko-wikisource-mk, first sync 2026-08-18, wired flip pending): the 1447 hangul epic's 125 cantos of Middle Korean verse in the archaic orthography (arae-a, tone dots — hangul NFC-safe, never NFKC), beside their parallel hanmun. |
| `ko` | Korean (historical, under the modern tag) | The OKHC historical slice (okhc, P91): 1.48M passages — the Samguk sagi (the oldest Korean history), the Ilseongnok daily records, the ITKC munjip mass and the AKS/Kyujanggak old-literature shelves, each record carrying its own PD-vs-nc label; the hanmun state record itself (sillok, Goryeosa…) rides `lzh`. |
| `xct` | Classical Tibetan | The Derge canon whole — the Public-Domain Digital Kangyur and Tengyur (1.36M passages, Esukhia's exact woodblock representation, Toh numbers as the crosswalk key), OTDO's Old Tibetan documents beside it under `otb`, and the SOAS gold-annotation lane. |
| `nwc` | Classical Newar | The DACON corpus (dacon, P88): dated Nepalese manuscript colophons and documents — the Newar written tradition's first machine-readable shelf here. |
| `okz` / `ocm` / `omy` / `osn` / `kaw` / `pyx` / `obr` | The Southeast Asia family (P92) | Old Khmer (the Cœdès K-numbers), Old Mon (the first digital corpus anywhere — two inscriptions inside the Pyu corpus), Old Malay (Kedukan Bukit to the Laguna copperplate), Old Sundanese, Old Javanese (the DHARMA charters + the kakawin editions + the OJW wordnet), Pyu, and Old Burmese (the Bagan stones, Myanmar-script with a transliteration lane) — ten languages the library never held before P92, most in their only machine-readable form. |
| `de` | German (ENHG → the print era, under the modern tag) | Two shelves: the ReF reference corpus (190 diplomatically transcribed manuscripts of 1350–1650, silver-lemmatized) and — since P94 — the Deutsches Textarchiv whole (dta: 5,478 prints of 1473–1969 at page grain, 729K passages, orthography as printed with ¬-line-break joins; 562 pre-1650 prints staged de:early by print-year inference). Together 1.18M passages; upstream's own `de` tag kept (the `is`/`sv` modern-tag precedent of rule 3). |
| `cat` | Catalan | The CTILC public-domain slice (ctilc, live 2026-08-21) — 967 works / 256,685 passages of Renaixença-era-onward literary and non-literary print, with the IEC's genre, dialect variant (central, baleàric, valencià…) and publication year on every work. |
| `por` | Portuguese | BDCamões Part I (bdcamoes, live 2026-08-21) — 127 dated literary works / 69,812 passages, Gil Vicente (1517) through Camilo and Herculano into the early 20th century; medieval Galician-Portuguese stays `roa-opt` on the cantigas shelf, not here. |
| `oci` | Occitan (incl. Aranese) | Lo Congrès' six-norm dialect matrix (lo-congres, live 2026-08-21 — 5,152 French-aligned sentences in each written norm, auvernhat through vivaroaupenc) and the Spanish–Aranese parallel corpus (aranese — 419,908 Aranese passages, largely Apertium-generated, held as synthetic parallel data); one deliberately coarse `oci` tag, the dialect riding as a facet. |
| `lad` | Judeo-Spanish (Ladino) | The Şalom press corpus (salom, live 2026-08-21) — 10,685 sentences from 2022 articles in Latin-script Ladino, the Istanbul Sephardic community's newspaper: the living written register of the language. |
| `srd` | Sardinian | The Common Voice sentence collection (cv-sardinian, live 2026-08-21) — 5,237 modern everyday-prose sentences in current orthography, gathered by Mozilla's volunteer community as speech-recording prompts (text layer only). |
| `xcl` / `xhu` / `uga` / `elx` / `peo` | Classical Armenian / Hurrian / Ugaritic / Elamite / Old Persian | The 5th-century Armenian NT plus lexical-list and inscriptional traces from the cuneiform and Achaemenid shelves — small but gold-lemmatized. |
| `ett` / `osc` / `xlu` / `xtg` / `xfa` / `xve` / `scx` / `xly` / `xpu` / `xrr` | Etruscan / Oscan / Luwian / …the pre-Roman epigraphic long tail | The Italic, Anatolian, and Mediterranean inscription corpora (OpenEtruscan, CEIPoM, ItAnt, LexLep, TIR, I.Sicily) — dozens of languages, mostly script-tagged (`-Grek`/`-Latn`/`-Ital`), many at a few hundred passages each. |
| `eng` / `en` / `ger` / `deu` / `ita` / `pol` / `fra` | Modern translation tags | The facing-translation layer (Perseus/First1K, WEB/Vulgate, SuttaCentral, Freising) — never originals; `en`/`deu` are legacy strays standardizing on `eng`/`ger`. |
| `und` | Undetermined | Inscriptions (chiefly EDH and epigraphic-shelf) whose language the upstream record could not determine — coded honestly rather than guessed. |

## Reference-shelf languages (dictionaries)

| Code | Dictionary | One sentence |
|---|---|---|
| `grc` | LSJ | The Greek-English lexicon, 116,497 entries, citations resolved into the corpus. |
| `lat` | Lewis & Short | The Latin dictionary, 51,636 entries, same resolution. |
| `san` | Monier-Williams | The Sanskrit-English dictionary (1899), 193,890 entries live since 2026-07-13 — SLP1↔IAST transcoded lookup, RV./BhP. citations resolving to GRETIL urns. |
| `ang` | Bosworth-Toller | The Anglo-Saxon dictionary, 62,815 entries, æ/þ/ð-folded lookup. |
| `chu` | Wiktionary-OCS | 4,615 crowd-sourced OCS entries whose etymologies seed the reconstruction crosswalk (2,210 descendant edges live). |
| `sla-pro` | Proto-Slavic (reconstructed) | 5,431 reconstructed headwords with descendant trees naming attested reflexes. |
| `ine-pro` | Proto-Indo-European (reconstructed) | 1,905 roots — the trunk the `etym` command ascends to. |
| `gem-pro` | Proto-Germanic (reconstructed) | 5,717 reconstructions bridging PIE to Gothic and Old English. |
| `ine-bsl-pro` | Proto-Balto-Slavic (reconstructed) | 491 headwords, live since the P17-3 resync — the STRUCTURAL intermediate shelf (PIE → PBS → Proto-Slavic) the multi-hop closure walks. |
| `gmw-pro` | Proto-West Germanic (reconstructed) | 5,551 headwords — the Old English proto desk, and the second intermediate shelf (Proto-Germanic → PWG → ang). |
| `itc-pro` | Proto-Italic (reconstructed) | 745 headwords bridging PIE to Latin (best record-level crosswalk join). |
| `iir-pro` | Proto-Indo-Iranian (reconstructed) | 799 headwords: Sanskrit via romanization + the flagged Iranian-loan layer in Armenian. |
| `ine` | IE-CoR (cognate sets) | 4,981 expert-curated Indo-European cognate sets under the collective `ine` tag, live since 2026-07-14 — the third etymological witness, 26,325 reflex edges, 2,308 loan-flagged. |
| `ine-pro` | LIV-LOD | 305 PIE verbal etymons with stem types (LiLa Turtle edition), live since 2026-07-14 — 374 Latin reflex edges. |
| `ine-pro` / `itc-pro` | de Vaan EDL | De Vaan's *Etymological Dictionary of Latin* (LiLa skeleton, `nc`): 2,860 etymons across two shelves, live since 2026-07-14 — the lat → Proto-Italic → PIE Leiden chains. |
| `ine-pro` / `rus` / `gem-pro` / `bat-pro` | StarLing (Pokorny · PIET · Vasmer · Germanic · Baltic) | The classical etymological bases digitized by the Tower of Babel project — Pokorny (2,222), the PIET Indo-European base (3,291), Vasmer's Russian (18,239), plus the Germanic and Baltic subordinate bases; library.md §8j. |
| `hbo` | BDB · SDBH · OSHB lexicon | The Masoretic desk: Brown-Driver-Briggs (11,845), the UBS Dictionary of Biblical Hebrew (7,932), and the Strong's-indexed OSHB lexicon; library.md §8q. |
| `egy` | AED · CCL | The TLA Ägyptische Wortliste (35,052 entries) and the Comprehensive Coptic Lexicon (11,284) — the Egyptian→Coptic dictionary chain; library.md §8o. |
| `sl` | Pleteršnik · JSV · Besedje16 | The Slovene historical lexica (Pleteršnik 1894, 103,185 entries; Janez Svetokriški; the 16th-century word-list) — diachronic Slovene on one desk; library.md §8k. |
| `sga` / `mga` / `wlm` / `xum` / `ett` / `ojp` | Wiktionary recon shelves | Old & Middle Irish, Middle Welsh, Umbrian, Etruscan, and Old Japanese kaikki extracts — the small crosswalk shelves that carry `etym` into Celtic, Sabellic, and the Sino/Japonic axes. |
| `och` / `ltc` | Baxter-Sagart · Guangyun · TLS | Old Chinese reconstruction and Middle Chinese phonology (Baxter-Sagart 2014, the 廣韻 Guangyun rime dictionary, 25,336 entries) plus the Thesaurus Linguae Sericae concept/word nets; library.md §8s/§8t. |
| `zho` / `lzh` | Unihan · HDIC quartet | The Unicode Han Database (65,092 codepoint entries) and the HDIC Heian character dictionaries (Yuanben/Songben Yupian, Tenrei Banshō Meigi, Shinsen Jikyō) — Literary-Chinese lexicography by codepoint; library.md §8s. |
| `jpn` / `ojp` | JMdict · KANJIDIC2 · ONCOJ lexicon | The EDRDG Japanese dictionaries (JMdict 217,951 glosses; KANJIDIC2) and the Old-Japanese ONCOJ lexicon; library.md §8s. |

*(All seven proto shelves are live — `define`/`etym` walk them with
multi-hop closure and per-edge "(loan)" flags — the Phase-18 trio
(`iecor`, `liv`, `edl`) synced live 2026-07-14, and the Phase-30–33
expansion added the StarLing bases, the Hebrew/Egyptian/Slovenian
desks, and the Sino/Japanese shelves. The table above is representative:
**105 dictionary shelves** now hold **1,410,205 entries** total
(2026-08-21 census) —
library.md §8c/§8h/§8j/§8k/§8m/§8o/§8q/§8s/§8t enumerate them per phase.)*

## Gold-lemma languages (searchable via `--lemma`, 38 as of the 2026-08-21 census)

`san, sux, gmh, gml, lat, egy, akk, is, grc, ro, orv, lzh, hbo, non,
cop, sl, fro, chu, ojp, sga, got, xcl, it, gez, frm, osx, bul, ota,
ang, xur, peo, arc, hit, xhu, elx, uga, qur, hlu` — the treebanks,
ORACC, goo300k, DCS, ONCOJ, the Hebrew/Egyptian shelves, Coptic
Scriptorium, and the Germanic reference corpora feed these
**19,319,627 gold rows** (2026-08-21 census; ordered above by pool
size: `san` 5.54M and `sux` 2.98M lead, `gmh` 2.10M third — ReM —
and `gml` 1.23M fourth — ReN — with `lat` 851K, `egy` 826K, `akk`
826K and `is` 812K the next tier). A parallel **silver layer** adds
**30,999,504 machine-suggested rows in 15 codes** (2026-08-21
census), always labelled (`--gold-only` excludes it): chiefly Greek
at corpus scale (GLAUx + Diorisis, 21.5M) and Latin (digilibLT + BFM
lanes, 5.7M), now joined by ReF's Early New High German (`de`,
2.55M), with Hittite/TLHdig 462K, Old French 319K — and the P77
newcomers, OSTA's Old Spanish 249K (plus its `arg`/`ast` layers) and
Achemenet's Akkadian 121K. Everything else is
full-text-searchable but not lemma-searchable (yet — see improvements
§3.1 for the cluster plan to project lemmas onto the rest).

---

*Maintenance: this page is refreshed at phase gates alongside library.md
(§10 duty). The authoritative per-source assignments live in each
adapter's manifest; the curated per-language prose lives in the
`local/shelves/local-language/` dossiers (edit there, not here); folding
rules in conventions §9; the proto-code rationale in conventions §4.*
