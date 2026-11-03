# grand-tour fixture

Retrieved 2026-11-03 from Zenodo record 23055358 ("Grand Tour TEI",
2026-09-30; concept record 23055357; creators Maximilian Görmar and
Angela Göbel, Herzog August Library), file `grand-tour-tei.zip`
(1,616,592 bytes, md5 6013b6805464fa1ec4e15e5b32cd3dea = the record's
checksum; central-directory sha256 e9b8baf3…a122, the adapter's pin), via
https://zenodo.org/api/records/23055358/files/grand-tour-tei.zip/content

The tree is the zip as ZipRangeFetch lands it (the single top directory
`grand-tour-tei/` stripped, `.git/` never fetched). This README replaces
the deposit's own README.md (same path; skipped by rule like it).

## Delivery grains (every grain the deposit serves; 199 zip entries = 126 files + 73 directories)

| grain | file(s) | taken? |
|---|---|---|
| journal | `Reiseberichte/cod_guelf_<shelfmark>.xml` (4) | TAKEN — document = journal |
| page | `<pb/>` inside each journal (540; one inside a copy's variant reading) | TAKEN — passage = page with text (515); 24 bindings/blank leaves counted as `blank_pages` |
| entity registers | `register/listPlace` / `listPerson` / `listOrg_grand_tour.xml` | READ as lookups, skipped as documents; trimmed here to the entries the fixture journals cite (+ one org) |
| itinerary | `register/itinerar_wagener.json` (149 stops) | READ into 267.1's metadata, skipped as a document; first 3 rows pinned |
| edition assembly | `Reiseberichte/index_grand_tour.xml` | READ for group labels, skipped by rule; pinned whole |
| introductions | `introduction/*.xml` (20: 4 Einleitungen, 14 Kurzbeschreibungen of untranscribed codices, project description, edition rules) | REJECTED — modern editorial apparatus, skipped by rule; `introduction_cod_guelf_127_1_extrav.xml` pinned whole |
| schema | `Schema/grand_tour_digital.rng` | REJECTED, skipped by rule; first 9 lines pinned (closed) |
| licence / readme | `LICENSE`, `README.md` | read (licence evidence), skipped by rule; LICENSE's first 3 lines pinned |
| VCS | `.git/` (94 files) | never fetched (outside the Range cone) |

## The cuts

Every journal is cut textually just before a `<pb/>`, its open elements
closed after a `<!-- fixture trim -->` comment; the kept bytes are
upstream's.

- `cod_guelf_89_blank.xml` — Ludwig Rudolf's Danish and Swedish journey,
  1689: the only journal with folio numbers (pb@n 90r…91v); pages 1–4,
  every entity resolved.
- `cod_guelf_267_1_extrav.xml` — Wagener's diary, 1652: five blank
  leaves, the mileage table, the opening entries (Meldorf, Lübeck);
  choice abbr/expan, `<w lemma>` joins.
- `cod_guelf_149_14_extrav.xml` — the Bevern dukes' journal, 1701: the
  `<app>` title page against three copies (one French), marginal
  mileages; no NER at all upstream.
- `cod_guelf_221_extrav.xml` — Christian August's diary, 1664: seven
  blank leaves, then pages whose `<rs ref="#">` are unlinked upstream
  (and one id the full register lacks too: `#homburg` — kept as an
  unresolved surface mention).

## Census of the whole deposit (through the adapter, 2026-11-03)

4 documents / 515 passages, 0 errors; 28 files skipped by rule.

| journal | passages | blank | dates | entity mentions resolved / unresolved |
|---|---|---|---|---|
| 267.1 Extrav. | 113 | 11 | 1652–1659 | 941 / 41 |
| 221 Extrav. | 210 | 6 | 1664–1670 | 74 / 2,707 |
| 89 Blank. | 23 | 0 | 1689 | 268 / 0 |
| 149.14 Extrav. | 169 | 7 | 1701–1702 | 0 / 0 |
