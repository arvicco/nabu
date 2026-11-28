# EDCS fixtures

Thirteen WHOLE real records, each cut byte-for-byte from the SDAM project's
cleaned dump of the Epigraphik-Datenbank Clauss-Slaby and re-joined into a
small valid JSON array under the upstream filename:

- Record: <https://zenodo.org/records/7072337> — "EDCS", version 2.0,
  published 2022-09-12, DOI 10.5281/zenodo.7072337 (creator: Petra
  Heřmánková, Aarhus University — the SDAM project, Social Dynamics and
  complexity in the Ancient Mediterranean).
- Artifact: `EDCS_text_cleaned_2022-09-12.json`, 465,523,658 B, md5
  `7ee22c65f442d54ba3537955603cc0ba` (Zenodo-published; verified on the
  download), sha256
  `5ecdb22311eb48c4d522212896cc828905f959c766ae57c89f49e069b5899d2a`
  (the adapter's `SHA256` pin).
- Retrieved: 2026-11-28 via
  `https://zenodo.org/records/7072337/files/EDCS_text_cleaned_2022-09-12.json?download=1`.
- Licence (the record's license field, verbatim): `cc-by-4.0`. The texts
  and their metadata come from the Epigraphik-Datenbank Clauss-Slaby
  (db.edcs.eu; Manfred Clauss et al.); the scrape and its cleaned layers
  are SDAM's. Both are credited.

## Delivery grains

Upstream serves exactly one grain: the record (one inscription) inside a
single JSON array on ONE line. There is no volume, page, index or
manifest grain in the deposit; SDAM's ETL scripts and attribute
descriptions live on GitHub (sdam-au/EDCS_ETL), outside the deposit, and
are not fetched. The adapter takes the record as the document and
rejects three record classes by rule, each pinned below.

## Census (the whole file, 2026-11-28)

- 537,262 records — exactly the count upstream's record description
  advertises ("537,262 cleaned and streamlined Latin inscriptions").
- 533,307 distinct `EDCS-ID`s, all `EDCS-<digits>` (537,259 with 8
  digits, 3 with 7); 3,955 ids occur twice, every pair identical as
  parsed.
- 513,781 documents = 537,262 − 6,997 without an `inscription` key
  − 12,549 whose inscription carries no letter (12,382 are EDCS's `?`,
  "text not given"; the rest bare lacuna brackets) − 3,935 later copies
  of a text-bearing duplicate pair. One passage each: 513,781 passages.
- Keys and fill: `EDCS-ID`, `publication`, `province`, `place`,
  `inscr_type`, `status_notation`, `inscr_process` on all records (the
  last three often `{}`, pandas' empty); `inscription` 530,265;
  `clean_text_conservative` / `clean_text_interpretive_word` 530,265;
  `inscription_conservative_cleaning` 517,362;
  `inscription_interpretive_cleaning` 517,683; `status` 425,404;
  `latitude`/`longitude` ~523,135; `partner_link` 274,338; `material`
  259,601; `dating_from`/`dating_to`/`date_not_before`/`date_not_after`
  ~203,245; `raw_dating` 203,262; `photo` 141,036; `comment` 12,412;
  `language` 8,327; `extra_text`/`extra_html` 2.
- Over the 513,781 documents: dated 196,743 (signed years, negative =
  BCE, no year 0; 12 reversed pairs in the whole file); placed 504,391
  (504,102 by name, 500,229 by coordinates); genre 391,232; material
  249,445; an EDH partner id 76,035; language by script lat 495,304 ·
  grc 18,477.
- 66 provinces (Roma 121,470 … Armenia 5, incl. "Provincia incerta" and
  joint values like "Belgica | Germania superior"); 16 `inscr_type`
  values; 20 materials; 4 `inscr_process` values; 16 `status_notation`
  values. 15,546 inscriptions are not NFC (Greek with oxia accents).
- A whole-file dry parse through the adapter takes ~48 s on this box
  (5 s for the skip census, 43 s discover + parse, one process).

## The records

| EDCS-ID | why this one |
| --- | --- |
| EDCS-24700151 | A Greek // Latin bilingual with more Latin letters → `lat`; the cleanings differ (`(Ζ)εῦξις` restored only in the interpretive layer); an EDH partner id; place named, no coordinates, undated. |
| EDCS-24900077 | Dated `-68 to -68` (68 BCE), coordinates, a six-witness concordance, `status_notation` as a list. |
| EDCS-77400214 | REJECTED: no `inscription` key at all (`language` "GR" — EDCS lists the stone, never transcribes it). |
| EDCS-28000525 | REJECTED: inscription `?` — no letter, EDCS's "text not given". |
| EDCS-09700347 | A three-part `raw_dating` (`a: … b: … c: …`) and its envelope; `//` part breaks; `inscr_type` `{}`. |
| EDCS-65000225 | Greek-script → `grc`; not NFC (iota with oxia, U+1F77); dated, placed. |
| EDCS-34700317 | Two genres in a list (tituli fabricationis + tituli operum), `sigilla impressa`, `opus figlinae`, a consular date. |
| EDCS-69800124 | A brick stamp that occurs twice in the dump — the first copy is the document. |
| EDCS-82200035 | `inscriptiones christianae` beside `tituli sepulcrales` (the cult label folds deliberate, the genre folds). |
| EDCS-13001449 | `language` "PU": the Punic half untranscribed, the Latin text present → `lat`, the marker kept verbatim. |
| EDCS-31200870 | Place `?` with coordinates: no name, the coordinate pair still places. |
| EDCS-09001312 | Reversed bounds `171 to 138`, verbatim (the timeline builder reorders); a photo link; two partner ids. |
| EDCS-69800124 | REJECTED: the second, identical copy. |

## Recipe

Records are located with `Nabu::JsonArraySplitter` over the real dump
and their byte slices joined with `,` inside `[` … `]` — no record is
re-serialized, so key order, `{}` empties and non-NFC bytes are
upstream's own. To re-cut: download the artifact above, verify the md5,
walk it with the splitter, pick the ids in the table (the repeated one
twice) and join their slices in table order.
