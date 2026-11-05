# leme fixture

REAL samples of LEME — Lexicons of Early Modern English (ed. Ian
Lancashire, University of Toronto) — as served by TSpace, the University
of Toronto's DSpace 7 repository, collection **1807/99021** (uuid
`10df91bc-8c9e-4ce1-b291-f02ad5715538`). Retrieved 2026-11-05 through the
REST API at https://utoronto.scholaris.ca/server/api:

- `rest/listing-<n>.json` — the discovery listing,
  `/discover/search/objects?scope=<collection uuid>&dsoType=ITEM&sort=dc.date.accessioned,ASC&page=<n>&size=100`,
  pages 0–3, each TRIMMED to this fixture's items (page 2 holds none of
  them and keeps no object) and re-serialized; the `page` block is
  verbatim (`totalElements` 314, `totalPages` 4).
- `items/<handle suffix>.json` — `/core/items/<uuid>?embed=bundles/bitstreams`,
  whole and byte-verbatim (Dublin Core metadata + the bundle/bitstream
  inventory).
- `xml/<handle suffix>.xml` — the item's named XML bitstream,
  `/core/bitstreams/<uuid>/content`.

| File | Item | Bytes | sha256 | Cut |
|---|---|---|---|---|
| xml/102611.xml | 1807/102611 — Baldwin, *The Canticles or Balades of Salomon* (1549), "The interpretacion of the Hebrue wurdes" | 10,309 | aeb5c87c2211add31691b59c3ceeba7c2ff0bf1ba406f9676d454a02b0876b19 | whole |
| xml/124555.xml | 1807/124555 — Aubrey, *Natural History and Antiquities of Surrey* (1719), "Some peculiar Words used by the Vulgar in SURREY" | 7,768 | acd303ff447a2cfa215610f542d74f58c3f872ace1b5bf7d0749728421770a43 | whole |
| xml/131265.xml | 1807/131265 — Martinez / Udall, *The Key of the Holy Tongue* (1593), the Hebrew–English dictionary | 6,356 (of 589,415) | 243b9daeaf06b55ecca1fa45a11c6dceb3b381863eb8c79d2604679bb4c3b4ea | trimmed |
| xml/102105.xml | 1807/102105 — Cotton, "Of the Antiquity of Motts and Words" (1600) | 12,540 | 8beaec2f80ee63fb68864c7faf521ce071274b9c6006d5f116e983df2d8fac8e | whole |

`xml/131265.xml` keeps upstream lines 1–17 (BOM, `<leme no="207">`, the
head note), 79–107 (page 3, the section, the A word-group, its first two
entries), 632–670 (the entry using the undeclared `&AElig;`, a `</page>`
/ `<page no="10">` boundary and the next entry), 716–733 (the entry the
`</page>` closes INSIDE of — the file's real malformation), 1124–1165
(the B word-group, the entry with the typo entity `&syh;`) and
13523–13534 (the closing word-group, section, colophon and `</leme>`),
CRLF line ends kept. Its listed MD5 is the whole file's, so the fetch
test sees the trimmed body fail its checksum — that is the MD5 guard's
test.

License: LEME's Terms of Use (https://leme.library.utoronto.ca/help/termsofuse,
read 2026-11-05), verbatim: "The following materials in LEME are
licensed under a Creative Commons Attribution 4.0 International license:
All files provided on the LEME website (http://leme.library.utoronto.ca),
and the XML encoded texts of lexical works, made available through the
TSpace institutional repository." Each fixture item's `dc.rights` reads
"Attribution 4.0 International", `dc.rights.uri`
http://creativecommons.org/licenses/by/4.0/.

## Delivery grains (census 2026-11-05 over all 314 items)

- **Item** — the archived DSpace item; the collection advertises 314
  (`archivedItemsCount` and the listing's `totalElements` agree; the
  sorted listing yields 314 unique uuids). Each item's record (Dublin
  Core + bundles) is held beside its XML.
- **The named XML bitstream** in the ORIGINAL bundle — exactly one per
  item (314 of 314) — **ACCEPTED**: one dictionary shelf per item.
- **Unnamed ORIGINAL bitstreams** — 26 on 20 items, earlier or duplicate
  uploads of the same XML (sizes within bytes of the named file, some
  MD5-identical); every one answers **HTTP 500** at `/content` —
  **REJECTED** by rule, never fetched; counted from the held record
  (specimen: `items/102611.json`, bitstream
  `118aa7b8-230e-4499-b665-a1fd71cf3573`, 10,158 bytes).
- **CC-LICENSE** (`license_rdf`, 312 items) and **LICENSE**
  (`license.txt`, 314) bundles — DSpace deposit furniture, not data.
- **An XML without a headworded word-entry** (no `<form>`) — two:
  1807/102105, Cotton's Society of Antiquaries discourse as running
  prose (specimen: `xml/102105.xml`, whole), and 1807/111075, Manlove's
  lead-mine terms (1653), one `<wordentry>` wrapping a verse word list
  — **REJECTED** by rule at discovery.

Reconciliation (every XML through the adapter): 312 discovered + 2
rule-skipped XMLs = the 314 advertised items. 311 parse to 943,211
entries; 1807/131265 (Martinez, whole file) quarantines on its line 925,
`<subform lang="he"><אַצׅיל/subform>` — a broken end tag upstream (this
fixture's trim keeps the parsable parts of that file).

## Upstream quirks the samples pin

- `102611` — the standard shape: the 260-entity internal DTD subset,
  `<root><leme no>`, word-groups by letter; headwords in LEME's `het`
  (transliterated Hebrew) code.
- `124555` — one of the four files whose DOCTYPE declares every entity
  with its value lost (`<!ENTITY AElig ">`); `<pb no>` page breaks;
  `<lemenote>` OED findings; post-1700 English.
- `131265` — no DOCTYPE and no `<root>`, a UTF-8 BOM, `&AElig;` /
  `&aelig;` used undeclared, the typo entities `&syh;` / `&sahy;`,
  `<page>` written as a container that closes inside open entries,
  `<subform>`/`<subxpln>` sub-entries, `xpln/@lexeme` OED headwords.
- `102105` — an item XML with no `<wordentry>` at all.

## Refresh

Re-GET the listing pages and the four items' records and content URLs
above; re-cut `131265` by the same line ranges.
