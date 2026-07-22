# Rundata fixtures (Scandinavian runic inscriptions) + SCHEMA CENSUS

Real samples from the **Scandinavian Runic-text Database** (SRDB /
*Samnordisk runtextdatabas* / Rundata) — the Uppsala catalogue of ~6,800 runic
inscriptions (CLAUDE.md fixture rules). Four whole inscription records as served
by the **rundata.info JSON API**, chosen for geographic and chronological
spread.

- **Retrieved:** 2026-07-22, live from `https://rundata.info` (Rundata-net, the
  open web edition of SRDB). The P39-s1 scout was Cloudflare-blocked; **plain
  `curl` succeeded** — no block hit on `rundata.info`.

## Where the machine-readable data actually is (established live, P40-g)

Two real machine-readable surfaces exist on rundata.info; **there is no plain
flat-file corpus download** (the desktop "Rundata 3.1" text files at
`nordiska.uu.se` are a separate legacy distribution not fetched here):

1. **The per-inscription JSON API** — `https://rundata.info/api/inscription/<signum>`
   (e.g. `.../api/inscription/U%20344`) → one inscription as JSON. Stable GET,
   no session. **This is what the four fixtures are.** There is also
   `https://rundata.info/api/openapi.json` (the OpenAPI schema) and a
   server-rendered detail page at `/inscription/<signum>/`.
2. **The bulk dump — a client-side SQLite database.** Rundata-net is a single-
   page app that "expose[s] the database to the client side completely" (README):
   it downloads **the entire SRDB as one SQLite file**,
   `https://rundata.info/static/runes/runes.<hash>.sqlite3` (at retrieval:
   `runes.234feed5f77e.sqlite3`, **47,448,064 B**, `application/octet-stream`,
   Last-Modified 2026-07-12). All searching then happens in-browser via `sql.js`.
   **This 47 MB SQLite file is the real bulk dump P40-6 should ingest** (too big
   to commit; the JSON fixtures below are the honest small sample).
   The Rundata-net source (Django) is at `github.com/Snorresk/rundata-net`;
   `rundatanet/runes/models.py` is the authoritative schema, `docs/db/data.rst`
   documents the field semantics.

## Files (whole API records)

| File | Signum | Bytes | What it exemplifies |
|---|---|---|---|
| `U_344.json` | U 344 | 2,010 | Uppland, Viking Age; Åsmund-carved; the compact canonical shape (all 5 text lanes, both coordinate pairs, a `[l]`/`(a)`/`----` damaged transliteration) |
| `DR_42.json` | DR 42 | 2,491 | Denmark — the large Jelling stone (Harald Bluetooth); `§A`/`§B` sections |
| `N_KJ101.json` | N KJ101 | 3,835 | Norway — the Eggja stone; **Older Futhark**, Migration/Merovingian dating |
| `Og_136.json` | Ög 136 | 9,267 | Östergötland — the Rök stone; `kortkvist` runes, the longest/most famous inscription, `§A`–`§E` |

Retrieved 2026-07-22. Each is the **complete API response** for that signum,
kept whole. They are marked `whole: false` in the manifest because the endpoint
is a JSON *rendering* of a live (actively maintained) database row, so it is
fetched for URL-liveness, not byte-identity.

---

## SCHEMA CENSUS (authoritative input for the P40-6 parser)

Field layout combines `models.py` (the DB tables) with the flattened JSON the
API returns. A record has a **signum**, a `meta` block, and a `runic_texts`
list (the five text lanes).

### Signum / identity

- `signature` — the primary signum, e.g. `"U 344"`, `"Ög 136"`, `"DR 42"`,
  `"N KJ101"`. Format is `<land/region-prefix> <number>[suffix]`: `U` Uppland,
  `Sö` Södermanland, `Ög` Östergötland, `DR` Denmark, `N` Norway, etc. **This
  is the natural id / URN key.**
- `canonical_slug` — a URL-safe form, `"u-344"`, `"og-136"`.
- `aliases` — alternative signa (list), e.g. Ög 136 → `["B 913", "L 2028"]`
  (Bautil, Liljegren numbers); N KJ101 → `["KJ 101"]` (Krause-Jankuhn). Empty
  for many (U 344 → `[]`).

### The five text lanes (`meta.runic_texts`: list of `{value, language_code}`)

One entry per lane, in this order, identified by `language_code`:

| `language_code` | Lane | Script | Example (U 344) |
|---|---|---|---|
| `run` | **Transliteration** (the runrad) | Latin transliteration, lower-case | `in ulfr hafiR o\| \|onklati ' þru kialt\| \|takat þit uas fursta þis tusti ka-t ' þ(a) ---- (þ)urktil ' þa kalt knutr` |
| `fvn` | Normalisation → Old West Norse (*fornvästnordiska*) | Latin, normalised | `En "Ulfr hefir á "Englandi þrjú gjald tekit. …` |
| `rsv` | Normalisation → runic Swedish / Old East Norse (*runsvenska*) | Latin, normalised | `En "UlfR hafiR a "Ænglandi þry giald takit. …` |
| `eng` | **English translation** | English | `And Ulfr has taken three payments in England. …` |
| `swe` | Swedish translation | Swedish | `Men Ulv har i England tagit tre gälder. …` |

In the DB (`models.py`) these are five separate one-to-one tables:
`TransliteratedText`, `NormalisationNorse` (fvn), `NormalisationScandinavian`
(rsv), `TranslationEnglish`, `TranslationSwedish` — each a `TextModel` with a
`value` (display) and a `search_value` (stripped, for search). Not every lane is
present for every inscription (short/undeciphered ones may lack normalisation or
translation).

**Transliteration notation to expect in the `run` lane** (real, from the
fixtures):
- `R` = the *yr*/ʀ rune (not Latin R); `þ` = thorn; `o` = the nasal ą rune.
- `|` word/rune-boundary or rune shared between words (`o| |onklati`).
- `'`, `+`, `¶`, `×`, `:` = punctuation / cross / section dividers on the stone
  (`baþ : kaurua ¶ kubl` on DR 42).
- `§A §B …` = inscription-side / section markers (DR 42, Ög 136, N KJ101).
- `(i)` = uncertain rune; `-` = one illegible rune (`ka-t`); `----` = a run of
  lost runes; `[l]`/`[minni]` = editorial restoration; `"` before a word marks a
  **proper name** (`"Ulfr`, `"Englandi`, `"Tosti`).

### Whether REAL runic codepoints appear — **NO.**

Checked live across all four records (and the source is transliteration by
design): **zero** Unicode Runic-block codepoints (U+16A0–U+16FF). The database
stores **transliteration and normalisation in the Latin script only** (with the
conventions above); it does **not** carry the runes themselves as
`ᚱᚢᚾᛁ` characters. P40-6 must not expect runic Unicode; the `run` lane is the
canonical "runic text". (If P40-6 ever wants rendered runes it would have to
transliterate → Unicode itself.)

### `meta` — inscription metadata

Geography & find-spot: `found_location` (*Plats* — `"Yttergärde"`), `parish`
(*Socken* — `"Orkesta sn"`), `district` (*Härad* — `"Seminghundra hd"`),
`municipality` (*Kommun* — `"Vallentuna"`), `current_location` (*Placering*),
`original_site` (*Urspr. plats?* — `"nej"`/`"ja"`), `parish_code`
(*Sockenkod/Fornlämningsnr.* — `"0065 (Orkesta), 29:2 (nuv. plats) [objektid=…]"`).

**Coordinates** — TWO pairs, WGS84 decimal degrees (`DecimalField`, 6 dp;
default `0`/`"0.000000"` when unknown):
- `latitude`, `longitude` — the find/original coordinates (U 344:
  `59.604644, 18.109098`).
- `present_latitude`, `present_longitude` — the stone's present location if
  moved (U 344: `59.604637, 18.109983`; Ög 136 present pair is `0.000000` = n/a).

**Dating** — a free-text lane plus a parsed range:
- `dating` (*Period/Datering*) — verbatim scholarly string, e.g. `"V"` (Viking
  Age), `"V 800-t"` (Ög 136, 800s), `"V Jelling"` (DR 42, Jelling group),
  `"U 650-700 (Grønvik)"` (N KJ101 — `U` = *urnordisk*/Proto-Norse, with the
  authority in parentheses).
- `year_from`, `year_to` — integer bounds (nullable): U 344 `725–1100`,
  Ög 136 `800–899`, N KJ101 `650–700`.

Typology & production: `style` (Gräslund's Viking-Age ornament chronology —
`"Pr 3"`, `"Rak"`, `"Fp"`, `"KB"`), `carver` (*Ristare*, with a signature code:
`"Åsmund (A)"` — `(S)` signed / `(A)` attributed / `(P)` paired / `(L)` like),
`rune_type` (*Runtyper* — `"kortkvist"` on Ög 136, often `""`), `material`
(*Material* — `"granit"`, Swedish vocab), `materialType` (`"stone"`),
`objectInfo` (*Föremål* — `"runsten"`), `additional` (*Övrigt*).

Crosses: `crosses` (textual) — Linn Lager's A–G cross-form classification
(e.g. `A1, B3, C4 …`), `""` when none; the DB models this as `Cross` /
`CrossForm` / `CrossDefinition` tables (see `data.rst`).

Booleans: `lost`, `new_reading`, `ornamental`, `recent` (*Santida* — a modern
inscription). References: `references` (list of `{text, kind, label}`; `kind` ∈
`text`/`link`) plus the legacy `reference` free-text field, and `images`
(`ImageLink`: `link_url`/`direct_url`). Personal names are separately indexed
(`PersonalName` + `NameUsage.word_index`).

### Verbatim sample record — U 344 (the compact canonical shape)

```
signature      : "U 344"
canonical_slug : "u-344"
aliases        : []
meta.found_location : "Yttergärde"    parish: "Orkesta sn"  district: "Seminghundra hd"  municipality: "Vallentuna"
meta.latitude/longitude                 : 59.604644 / 18.109098
meta.present_latitude/present_longitude : 59.604637 / 18.109983
meta.dating : "V"   year_from/year_to : 725 / 1100
meta.style  : "Pr 3"   carver : "Åsmund (A)"   material : "granit"   materialType : "stone"   objectInfo : "runsten"
meta.parish_code : "0065 (Orkesta), 29:2 (nuv. plats) [objektid=10006500290002]"
runic_texts:
  run : in ulfr hafiR o| |onklati ' þru kialt| |takat þit uas fursta þis tusti ka-t ' þ(a) ---- (þ)urktil ' þa kalt knutr
  fvn : En "Ulfr hefir á "Englandi þrjú gjald tekit. Þat var fyrsta þat's "Tosti ga[l]t. Þá [galt] "Þorketill. Þá galt "Knútr.
  rsv : En "UlfR hafiR a "Ænglandi þry giald takit. Þet vas fyrsta þet's "Tosti ga[l]t. Þa [galt] "Þorkætill. Þa galt "Knutr.
  eng : And Ulfr has taken three payments in England. That was the first that Tosti paid. Then Þorketill paid. Then Knútr paid.
  swe : Men Ulv har i England tagit tre gälder. Den var det första, som Toste gäldade. Sedan gäldade Torkel. Sedan gäldade Knut.
```

---

## License (recorded exactly)

The SRDB **data** is under the **Open Database License (ODbL) 1.0** for the
database and the **Database Contents License (DbCL) 1.0** for the contents.
Verbatim, from Uppsala runforum (`https://www.runforum.nordiska.uu.se/en/srd/`):

> The Scandinavian Runic-text Database is copyrighted, but is made available
> under the Open Database License (`http://opendatacommons.org/licenses/odbl/1.0/`).
> Any rights in individual contents of the database are licensed under the
> Database Contents License (`http://opendatacommons.org/licenses/dbcl/1.0/`).

Attribution requirement (verbatim): *"When quoting or re-using information from
the Scandinavian Runic-text Database, you are required to refer to the database
by naming it and linking to its web site."* → license_class **`attribution`**
(ODbL is a share-alike/attribution open-data licence; treat as attribution-
class, honour the naming+link requirement).

**Caveat, reported honestly:** `rundata.info` (Rundata-net) itself states only
**GPLv3 for its own source code** (`github.com/Snorresk/rundata-net`, `LICENSE`,
Vadim Frolov) and does **not** restate a data licence on its About page. The
ODbL/DbCL grant above is the authoritative SRDB (Uppsala) licence — confirmed
against the Uppsala runforum and Wikipedia's Scandinavian Runic-text Database
article. The owner should re-confirm the ODbL grant at the point of a real
sync / before flipping the adapter to `enabled: true`.

## The SQLite trim (orchestrator, 2026-07-22)

`runes-trim.sqlite3` — a schema-preserving trim of the REAL 45 MB
browser artifact (`runes.234feed5f77e.sqlite3`, the actual bulk file
P40-6 ingests as canonical): full DDL including the `all_data` view,
rows for the same four inscriptions as the JSON fixtures, small
reference tables (cross_forms, material_types, nameusage) whole.
The view machinery verified working on the trim (all_data → 4 rows).
The parser develops against this; the owner-fired real sync fetches
the full artifact.
