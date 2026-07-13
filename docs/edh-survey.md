# EDH survey (P17-2 Phase A, 2026-07-13)

Scouting survey for the Epigraphic Database Heidelberg (register §2.3) — Latin
inscriptions as the third documentary shelf beside the papyri and the tablets.
Per the Phase 17 deep-extraction mandate, this censuses **every** layer the
records carry and maps each to a nabu surface, ending with a fixture plan for
the owner gate.

**Evidence base (all numbers from inspected files, named throughout):** two of
the nine EpiDoc dump zips downloaded and unpacked to scratchpad —
`edhEpidocDump_HD000001-HD010000.zip` (9,928 XML) and
`edhEpidocDump_HD080001-HD082828.zip` (2,819 XML) = **12,747 records read**
(15.5% of the corpus, both ends of the HD range) — plus the **complete**
`edh_data_text.csv` (57 MB, 82,450 rows) and `edh_data_pers.csv` (8.9 MB,
93,646 rows) for corpus-wide censuses, plus HEAD probes of every dump file and
the live `/data`, `/data/download`, `/projekt/geschichte` pages
(2026-07-13). Exemplar records quoted below: HD000001, HD000082, HD000280,
HD080825.

**Bottom line up front.** EDH is a clean, frozen, CC BY-SA 4.0 corpus of
**82,450 Latin inscriptions** (81,975 with text, ~447k citable lines) whose
EpiDoc dialect is a *small subset* of the DDbDP markup the corpus already
parses — one new DdbdpParser-adjacent family, one ZipFetch source, URNs free
on stable HD numbers. It arrives carrying four metadata layers nabu can use
immediately: dating on 73.3% of records (signed years, conventions-§11
compatible — verified byte-level), findspot + 103 provinces, a **22-code
inscription-type vocabulary** (the genre facet nabu lacks — schema proposed
below), and a **93,646-row structured prosopography** (the §3.5 seed).
Upstream is archived (funding closed 2021, staff gone, the API doc page
already 404s) — the preservation argument says ingest now, `sync_policy:
frozen`.

---

## 1. Corpus shape — and the frozen-dump story

**Counts.** `edh_data_text.csv` holds **82,450 inscription records**, HD
numbers HD000001–HD082828 (gaps are unassigned numbers: the first zip's range
of 10,000 contains 9,928 files, the last's range of 2,828 contains 2,819 —
consistent with the CSV total). 81,975 records (99.4%) carry a transcription
(`atext`); the ~475 text-less rest are metadata-only stubs → skip-by-rule at
discover (the ORACC no-content precedent), never quarantine.

**Languages** (CSV `nl_text`, whole corpus): `L` 80,465 (97.6%), `G` 1,290
(1.6%), `GL` bilingual 658, `LG` 1, plus a long exotic tail totalling 31
(`PL` Punic-Latin 12, `HL` Hebrew-Latin 4, `KL` Celtic-Latin 4, `PyGL`/`PyL`
Palmyrene 6, `ItL`/`IbL`/`HIbL` Italic/Iberian 4, `N` 3, `K` 1, blank 1).
≈1,953 records (2.4%) carry Greek. **Trap verified:** the EpiDoc
`<langUsage>` is boilerplate — HD000280's edition is Greek
(`ε[---]ηθικ[`) yet its header lists only `en/de/lat`; zero of 12,747
inspected files declare `grc`. Per-document language must come from the CSV
`nl_text` column (or script-sniffing), never from the EpiDoc header.

**Dump inventory** (HEAD-verified 2026-07-13, `/data/download`):

| artifact | size | Last-Modified |
|---|---|---|
| 9 × `edhEpidocDump_HD*.zip` (EpiDoc XML, flat `HDnnnnnn.xml`) | **153.8 MB** total (5.4–19.6 MB each), ~600 MB unpacked (extrapolated from 92 MB/12,747 files) | all **2021-12-16** |
| `edh_data_text.csv` (75 columns: full metadata + `atext`/`btext`) | 57.2 MB | **2025-07-31** |
| `edh_data_pers.csv` (prosopography, 23 columns) | 8.9 MB | 2021-12-09 |
| `edh_data_geo.csv` / `edhGeographicData.json` | 15.4 / 19.2 MB | 2024-01 / 2021-12 |
| `edh_data_biblio.csv` / `edhBibliography.bib` | 3.9 MB / — | 2021-12 |
| `edh_linked_data.zip` (RDF incl. prosopography) | 13.1 MB | 2021-12-16 |
| `edhFotoXMLDump.zip` (CIDOC CRM photo metadata) | — | not taken (photos out of scope) |

**Source of record: the EpiDoc dump**, supplemented by two CSVs. The EpiDoc
carries the structured text (line milestones, Leiden markup, textparts) that
the CSV flattens; the CSV carries three things the EpiDoc *lacks* — the
per-record language code, the diplomatic majuscule text (`btext`), and the
Trismegistos number — plus findspot coordinates. The 2025-07-31 CSV timestamp
is a regeneration, not new content: same 82,450 records, same max HD082828 as
the 2021 zips. The pers CSV is strictly richer than the EpiDoc's person
encoding (§4.5) and is the prosopography source of record.

**Update model → `sync_policy: frozen`, and the preservation argument.** The
history page (`/projekt/geschichte`) records 2021 as the "Closing year
(phase-out funding)", the physical inscription indexes transferred to Vienna
and Rome in 2021, all staff end-dates ≤2021, page footer "Last update:
February 2021". Decay is already visible at the edges: the `/data/api`
documentation page linked from `/data` now serves "CDIV – Page not found",
and every one of the 2,819 lastzip files' `<idno type="URI">` points at a
staging host (`edh-www.adw.uni-heidelberg.de/test/edh/…`) — the adapter must
mint its own resolver URLs from HD numbers and trust nothing but the HD id.
An archived corpus on university hosting with no staff is exactly the
ingest-now case; the dumps are small, the license is clean, and a frozen
one-shot snapshot costs one owner-fired sync.

## 2. License

**CC BY-SA 4.0 → `license_class: attribution`, MCP-safe.** Verified in two
independent places: (a) the `/data` page, verbatim: "All data of the Open
Data Repository by the Epigraphic Database Heidelberg can be reused under the
CC BY-SA 4.0 licence"; (b) **embedded per-file** in every inspected EpiDoc
record — `<licence target="http://creativecommons.org/licenses/by-sa/4.0/">
This file is licensed under the Creative Commons Attribution-ShareAlike 4.0
license.</licence>` (HD080825 quoted; present in all 12,747). The grant
covers the dumps as such; photo *files* live in HeidIcon with their own
rights and are **not taken** (facsimile URLs dropped; the CIDOC photo dump
not fetched — text + metadata only, per the packet). `license_watch`
candidate: `https://edh.ub.uni-heidelberg.de/data` (serves the terms
directly, no redirect — owner verifies before flipping, P16-5 discipline).

## 3. Text layers

**The EpiDoc dialect is a small, well-behaved subset of DDbDP's.** Markup
census over all 12,747 inspected files (element opens):

| element | count | | element | count |
|---|---|---|---|---|
| `<expan>`/`<abbr>`/`<ex>` | 68,989 | | `<del rend="erasure">` | 515 |
| `<supplied reason="lost">` | 23,942 | | `<surplus>` | 244 |
| `<gap>` (lost/character/line) | 19,280 | | `<note>` | 108 |
| `<unclear>` | **0** | | `<choice>/<reg>/<orig>/<corr>/<sic>` | **0** |
| `<hi>`/`<foreign>`/`<handShift>`/`<space>` | **0** | | | |

So: abbreviation expansions, restorations, lacunae, erasures — and *nothing
else*. No regularization apparatus, no unclear-letter encoding (EDH's data
model never carried underdots), no hand shifts. The DDbDP keep/drop policy
(conventions §5) applies almost verbatim; the print-edition rule gives:
`text` = expansions read expanded (`v(otum)` → "votum"), supplied read
through, every `<gap>` → the single `[…]` marker.

**One deliberate policy divergence: `<del>` is KEPT, wrapped `⟦…⟧`.** EDH's
`<del rend="erasure">` is the damnatio-memoriae/erasure case — legible,
edited text (HD000082: `<del rend="erasure">…Crassu</del>` — Crassus'
titles erased in antiquity), and EDH's own `atext` prints it inside `[[…]]`
(verified against the CSV row). Blanket-dropping del (the DDbDP default)
would erase reading text that the source itself publishes. This is
per-source policy, exactly the direction conventions §5's recorded
future-work note points; density 515 in 12,747 files (~4% of records), each
kept line carrying `"leiden": {"cancelled": true}` per the P6-2 precedent.

**text vs text_normalized verdict:** `text` = the edition reading as above
(the "diplomatic-ish" layer nabu stores everywhere); `text_normalized` =
the standard house search fold minted by `Passage.new` — nothing
EDH-specific needed (Latin fold already exists; Greek lines fold as Greek).
The TRUE diplomatic layer (majuscule `btext`: `SEVERV[ ]` beside
`Severu[s]`) exists **only in the CSV**, not the EpiDoc — 81,964 records
have it. Not a second document (it is mechanically derivable lettering, not
an independent edition); carry it as a per-document annotation from the CSV
join in v2, lose nothing (the CSV is canonical).

**Citation grain: the LINE, non-negotiable.** Epigraphy cites "CIL XIII
5708, line 3". Corpus-wide: 446,690 lines, mean 5.45 lines/inscription,
**23.8 chars/line** — even shorter than DDbDP's 34. `<lb n="…"/>` milestones
inside `<ab>`, textpart divs (`<div n="1" type="textpart">`) in 975/9,928
firstzip files (9.8%) — bilinguals and multi-sided stones — and line numbers
RESTART per textpart (HD000082 has two `lb n="1"`), so the textpart path is
mandatory in the urn when present (the DdbdpParser urn shape handles this
already). `lb n="0"` exists (lost-line-before-text, HD080825); it usually
extracts only a gap marker and skips as empty. `break="no"` hyphenated line
breaks: 865 occurrences in the 2,819 lastzip files — same accepted property
as DDbDP (line-grain passages split the word; the ccmh-txt rejoined-form
precedent is available if a whole-text layer is ever wanted, not v1).

**Fragment density → the fuzzy flag.** 19,280 gaps + 23,942 supplied across
12,747 files; HD000280's entire text is `]ε[---]ηθικ[`. This shelf is the
designed second… now third customer of P16-4: the sources.yml comment on
`papyri-ddbdp` says verbatim "Future documentary sources (inscriptions) join
by adding this flag, no code" — **the config join is one line**,
`fuzzy_index: true` in the `edh` registry entry. Cost: 81,975 texts × 129.4
chars ≈ 10.6M chars × 6.55 B/char (design §4's measured documentary rate) ≈
**+70 MB** trigram index — well inside documentary economics.

## 4. Metadata layers — exhaustive census, each mapped to a surface

### 4.1 Dating → `document_axes`

CSV `dat_jahr_a`/`dat_jahr_e` ↔ EpiDoc `<origDate notBefore-custom=…
notAfter-custom=…>`. **Signed historical years, no year 0 — verified, not
assumed:** HD080029 carries `notBefore-custom="-0020" notAfter-custom="-0001"`
labelled "20 BC - 1 BC", i.e. −1 = 1 BCE, exactly conventions §11 (the HGV
numbering; `DateAxis` ingests it unchanged). Coverage (whole corpus):
**56,945 records with both bounds + 3,529 notBefore-only (open-ended, NULL
not_after) = 60,474 dated (73.3%)**; 21,976 undated (an absence, never a
row). Precision distribution (range width): ≤25y 6,603 · 26–50y 8,539 ·
51–100y 18,795 · 101–200y 15,643 · >200y 7,364 · point 1 — median a
century, store honest ranges, precision derived from width. Honest tail: 330
records date past 640 CE (up to 1998 — post-antique copies/forgeries EDH
records as such); ingest verbatim, the axis does not editorialize. Floor
−530. Surface: an `AxisBuilder::EdhDates` extractor (HGV precedent — reads
canonical XML/CSV, joins on urn = f(HD)); this **nearly doubles the dated
corpus: 83,233 → ~143,700 documents (+73%)**.

### 4.2 Findspot & province → the place axis (strings + province v1)

Four-level place per record: ancient findspot (`fo_antik`), modern
(`fo_modern`, geonames-ref'd in EpiDoc), findspot detail, region + country —
80,742 records (97.9%) have at least one. **PROVINCE** is its own field:
103 values (66-odd canonical Roman provinces + the 11 Italian regiones +
`?`-variants); top: Dalmatia 7,610, Germania superior 6,830, Hispania
citerior 4,684, Britannia 4,483, Africa Proconsularis 4,444. Surface:
`document_axes.place_name` = ancient findspot (modern as fallback),
`place_ref` = the geonames URL where present; **province → the facet table
(§4.3)** — it is a categorical filter, not a point-place. Coordinates exist
on 79,488 records (96.4%) in the CSV plus a GeoJSON dump and
Pleiades-derived province polygons — **not ingested v1, not lost**: they
stay in the canonical CSV for a future geo layer.

### 4.3 Inscription TYPE → the genre facet nabu doesn't have (schema proposal)

**Census:** CSV `i_gattung`, **22 base codes**, 61,260 records typed (74.3%);
`?`-suffixed uncertain variants throughout (titsep? 1,376). Full vocabulary
with corpus counts: titsep/epitaph 28,083 · titsac/votive 14,198 ·
titpossfabr/owner-artist 5,337 · tithon/honorific 4,007 ·
titoppubpriv/building-dedicatory 3,323 · miliarium/milestone 1,742 ·
nota/identification 1,570 · titaccl/acclamation 543 · diplmil/military
diploma 501 · indexlaterc/list 360 · titdefix/defixio 311 · titreiexpl/label
301 · titiurpub/public-legal 249 · titterm/boundary 246 · elogium 143 ·
brief/letter 124 · titsedspect/seat 87 · oratio/prayer 57 ·
titiurpriv/private-legal 45 · titadsig/assignation 16 · fasti/calendar 14 ·
titadnun 3. The EpiDoc mirrors every code as an EAGLE-vocabulary term with a
LOD URI (`<term ref="…eagle-network.eu/voc/typeins/lod/92">epitaph</term>`)
— mapping empirically verified for 21/22 codes against inspected files
(titadnun's 3 records fell outside the sampled ranges; resolve at fixture
time).

**Proposal: a `document_facets` table, not columns on documents.** The
document_axes design argument replays exactly: facet values are sparse
(25.7% of EDH has no type), multi-valued in principle (a `?` certainty rider;
bilingual language pairs; future sources' genres), and new facets must not
mean new migrations. One skinny catalog-side table, rebuild-regenerated:

    document_facets(document_id, facet, value, raw)
    -- facet ∈ {genre, province, material, object_type} for EDH v1
    -- value: the normalized English term ("epitaph", "Pannonia inferior")
    -- raw:   upstream verbatim ("titsep?", "PaI") — the ? certainty survives

populated by the loader from document annotations (or a FacetBuilder pass,
whichever the implementer prices cheaper — both are f(canonical)). Queries
land through the proven CatalogJoin EXISTS pattern, composing with
everything: **`search --type epitaph --province "Pannonia inferior"
--century 2`**, `vocab --by-century` sliced by genre (epitaph formulae vs
votive formulae — D M / H S E / V S L M are *the* formula-miner targets),
`formulas SCOPE` per genre slice, MCP `nabu_search` gaining `type`/
`province` args. Cost: ~230k skinny rows for EDH (61,260 genre + 82,143
province + 37,030 material + ~50k object type), a few MB; one migration.
The alternative (a `documents.genre` column) is priced and rejected: it
handles exactly one facet, single-valued, and the very next source pays
another migration.

### 4.4 Material & object type → facet rows

Material on 37,030 records (44.9%): German vocabulary in CSV/XML text
(Kalkstein 698, Gesteine 510, Ton 504, Sandstein 240, Bronze 90 in lastzip)
**with EAGLE material LOD refs** in EpiDoc — store the EAGLE-English/URI as
`value`, German verbatim as `raw`. Object type (`denkmaltyp`, 69 distinct
incl. `?`): Tafel 12,097 · Stele 8,776 · Altar 8,774 · instrumentum
domesticum 4,576 · Statuenbasis 1,986 · Meilenstein 1,712 · Sarkophag 1,664;
EpiDoc `<objectType ref="…eagle…/objtyp/lod/29">altar</objectType>` gives
the English. Both → `document_facets` (§4.3). Also present, recorded but
NOT ingested v1: dimensions (h/w/d cm), letter heights, `erhaltung`
(preservation state), decoration flag, `ligatur` (596 records), layout
description.

### 4.5 PERSONS — the structured prosopography (§3.5 seed)

**The headline layer.** `edh_data_pers.csv`: **93,646 person rows across
46,801 inscriptions (56.8% of the corpus)**, one row per attested person,
with columns: name (display form incl. Leiden brackets), praenomen / nomen /
cognomen / supernomen (cognomen filled on 89,997, nomen 63,625, praenomen
35,099), sex 76,289 (M 61k / W 15k), **status 33,306** (freedman/slave/
senatorial etc., coded), filiation 2,528, tribus 2,882, origo 2,672,
kinship-to-other-persons (`verwandt`) 3,181, function 1,150, occupation
(`beruf`) 738, age-at-death (years 8,808 + months/days/hours), **EDH person
URIs 12,331** and **PIR references 2,091**. The EpiDoc mirrors only a
shard: `<particDesc><person xml:id="HDnnnnnn_k" sex="…">` + name parts —
verified across all 12,747 files: no status/origo/tribus/age attributes
exist in the XML. The pers CSV is the source of record.

**v1 verdict: annotations JSON now, own table deferred — argued.** Persons
ride in the document's `annotations` (`"persons": [{praenomen, nomen,
cognomen, sex, status, origo, tribus, age, uri, pir}, …]`), joined from the
pers CSV by HD number at parse time. Cost: zero schema, visible in `nabu
show`, greppable, and it IS the §3.5 prosopography seed — when the
NER/prosopography work wakes (cluster-era), 93,646 *gold* structured Latin
name records are the training/evaluation anchor the register said
Trismegistos would have to provide. A `persons` table + attestation index
("every Ζήνων in the Fayum", but for Iulii in Pannonia) is real and earns
its keep only WITH a query surface (`nabu persons NAME`?) — that is a
packet of its own, deferred v2 with the annotations as its ready feedstock.
The 12,331 EDH-person URIs + 2,091 PIR refs are future links-journal edges
(kind: attestation), also v2.

### 4.6 Everything else the records carry

- **Trismegistos numbers on 77,160 records (93.6%)** (CSV `tm_nr`; absent
  from EpiDoc) → annotation v1; the professional-crosswalk key (§3.5's named
  reference) and a future links surface.
- **Literature** on 81,937 (99.4%): AE/CIL citations, structured `#`-joined
  (`beleg` field + BibTeX dump) → future citation edges in the links
  journal (the §1.8 dictionary-citation pattern); annotation-only v1.
- **Commentary** (German) on 40,430 → stays canonical, not ingested
  (matches the DDbDP posture on editorial notes).
- **Find year** 30,956, **repository/aufbewahrung** (current museum),
  **fundstelle** detail → annotations verbatim, cheap.
- **Verse flag** (`metrik` J/J?) on 496 records — carmina epigraphica; tiny
  but a genuine intertext hook (verse epitaphs quote Vergil); rides as an
  annotation, could join the genre facet as `verse` later.
- **`people_uris` 4,377 / `godot_uris` 1,579** (GODOT calendar-date URIs —
  inscriptions dated to a named consulate/day) → annotations; GODOT is a
  finer-than-year dating layer if ever wanted.
- **Photos/facsimile URLs** (HeidIcon API, 3 per record in HD080825) →
  dropped; separately-rights'd (§2).

## 5. Ingestion design sketch

- **Adapter** `Nabu::Adapters::Edh`, fetch = `Nabu::ZipFetch` over the nine
  EpiDoc zips (the ORACC multi-artifact precedent; Last-Modified change
  detection is moot under `frozen` but comes free) **+ the two CSVs**
  (`edh_data_text.csv` 57 MB for `nl_text`/`btext`/`tm_nr`/coordinates,
  `edh_data_pers.csv` 8.9 MB for persons) — ZipFetch's sibling single-file
  path or a plain FileFetch, implementer's pick. Canonical footprint ≈
  **220 MB** (154 zips + 66 CSVs).
- **Parser family:** new `EdhEpidocParser`, DdbdpParser-adjacent — the
  keep/drop depth-stack and line-milestone machinery pattern-match, but it
  is a new family, not reuse: different header extraction (msDesc/origin/
  provenance/textClass/particDesc), the keep-del-in-⟦…⟧ policy divergence
  (§3), textpart-relative line restarts, and a CSV side-join. The Leiden
  subset is *smaller* than DDbDP's (no choice/reg/orig, no unclear) — this
  is the easy end of the family.
- **URN:** `urn:nabu:edh:hd000001[:<textpart>]:<line>` — HD numbers are the
  stable id every aggregator (EAGLE, Trismegistos, EDCS) keys on; lowercase
  zero-padded slug, textpart segment only when textpart divs exist
  (HD000082 → `…:hd000082:2:1` for Ὅμηρος). Document language from
  `nl_text` (L→lat, G→grc); GL bilinguals get per-passage language by
  textpart script (the freising Latin-tail precedent).
- **Projected size:** ~81,975 documents / **~450k passages** (446,690 CSV
  lines; textpart splits add noise) — half a DDbDP of passages; fulltext
  growth proportional; trigram +~70 MB (§3); `document_axes` +60,474 rows
  (~2 MB at the measured 175 B/row); `document_facets` ~230k rows, single-
  digit MB.
- **What each surface gains, measured:** the date/place axis grows 83,233 →
  ~143,700 dated documents (+73%, the largest single axis feed since HGV);
  `search --fuzzy` gains its third documentary shelf for one config line
  (~70 MB); the new genre facet lands with 61,260 typed documents on day
  one (`--type epitaph --province X --century N`); the §3.5 prosopography
  inherits 93,646 gold person records for zero schema.
- **Fixture plan (2–3 real records, trimmed CSV siblings, README with URLs
  + retrieval date):**
  1. **HD080825.xml** (lastzip) — votive altar, Germania inferior, dated
     151–250, `expan`+`supplied`+`gap`+`lb n="0"`, one person, EAGLE
     type/material/objectType refs, the staging-URI quirk. Exercises the
     core extraction + axis + facets.
  2. **HD000082.xml** (firstzip) — the Homer herm from Roma, 171–230:
     **bilingual** Latin/Greek textparts with per-textpart line restarts,
     `del rend="erasure"` (damnatio of Crassus) nesting an `expan` —
     exercises the ⟦…⟧ keep policy, per-passage language, textpart urns.
  3. **HD000001.xml** (firstzip) — marble tabula epitaph, 71–130 CE, THREE
     structured persons (Nonia Optata, C. Iulius Artemo, C. Iulius Optatus:
     filiation, patronage relations in the pers CSV) — exercises the
     persons annotation join + genre facet.
  Plus `edh_data_text.csv` / `edh_data_pers.csv` trimmed to the header +
  these three HD numbers' rows.
- **Registry sketch** (`config/sources.yml`):

      edh:
        adapter: Nabu::Adapters::Edh
        enabled: false
        sync_policy: frozen      # archived upstream, 2021 (survey §1)
        fuzzy_index: true        # third documentary shelf (design §4)
        # license_watch: https://edh.ub.uni-heidelberg.de/data  (owner verify)

## 6. Ranked verdict

**v1 scope (gate-ready):** the EpiDoc dump + two CSVs, frozen; line-grain
passages under the DDbDP-minus policy with the del-⟦…⟧ divergence; language
from `nl_text`; axis extractor (dates + findspot place); `document_facets`
(migration + genre/province/material/object_type + `search --type/--province`
+ MCP args); persons + tm_nr + literature + verse flag as annotations JSON;
`fuzzy_index: true`. The fixture plan above is what the owner approves.

**v2 deferrals (recorded, feedstock secured in canonical):** persons table +
attestation query + PIR/EDH-URI/Trismegistos links-journal edges; the geo
layer (79,488 coordinate pairs + GeoJSON + province polygons — waiting for
any nabu geo surface to exist); `btext` diplomatic annotation per document;
literature → citation edges; GODOT day-precision dating.

**Blocked: nothing.** Every artifact taken is CC BY-SA 4.0 with the grant
embedded per file. The only exclusions are self-imposed and rights-clean:
photo files (HeidIcon, separate rights — never fetched) and the CIDOC photo
metadata dump (out of text+meta scope). Honest unknowns: the `titadnun`
EAGLE mapping (3 records, resolve at fixture time); the semantics of the
CSV `atext` `$`/`&` sigils (line-0 / border markers — irrelevant, we parse
the XML); whether the 2025 CSV regeneration carries silent record-level
corrections against the 2021 zips (spot-checks HD000082/HD000280/HD080825
matched exactly; the adapter's CSV join will surface any real drift as
count mismatches at sync).
