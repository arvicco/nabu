# sefaria fixtures — Sefaria-Export Targum shelf (index + GCS bucket)

Real files from Sefaria's restructured export (P30-3), retrieved
**2026-07-18**. Upstream is TWO surfaces:

- the **index**: `books.json` in the `Sefaria/Sefaria-Export` git repo
  (regenerated monthly; the fetched copy pinned here is
  `"generated_at": "2026-07-02T07:03:07Z"`, 19,705 version entries /
  6,456 titles, full file sha256
  `46100984c4715ae50c7e4dac1112ad00306d2b635bede2151072903d22413eb2`,
  20,170,536 bytes);
- the **texts**: per-version JSON files in the public GCS bucket
  `gs://sefaria-export` (~26 GB total — never fetched wholesale), named
  by `json/{categories}/{title}/{language}/{versionTitle}.json` and
  served without authentication from
  `https://storage.googleapis.com/sefaria-export/...`.

Every version file below is at its bucket-relative path so `discover`
walks the real layout. WHOLE files are byte-verbatim upstream. The three
TRIMMED files keep every metadata key byte-identical and slice only the
`text` arrays (python `json.dumps(indent=4, ensure_ascii=False)`
round-trips upstream's own serialization byte-identically — verified on
an untouched file before trimming); the sha256 recorded in
`manifest.yml` notes is the ORIGINAL full file's.

## The Targum shelf census (books.json 2026-07-02, verified 2026-07-18)

Entries whose `categories` include `"Targum"`: **200 files / 45 titles**
(the packet spec's "46" is not reproducible against this monthly index) —
79 `merged` + **121 named versions, 15.6 MB** (sizes summed via ranged
GETs). Subshelves: Onkelos/Torah 41 · Targum Jonathan/Prophets 67 ·
Targum Jonathan/Torah 31 · Aramaic Targum/Writings 41 · Targum
Jerusalem 11 · Targum Neofiti 4 · Tafsir Rasag 5. **Tafsir Rasag is
excluded by rule** (Saadia Gaon's Judeo-Arabic translation — in the
category, but not an Aramaic targum; blanket `he`→`arc` would mislabel
it).

## The license gate (per-version, machine-readable — censused over all 121 named versions)

`"license"` field values: **Public Domain ×53 · CC0 ×26 · CC-BY ×9 ·
CC-BY-SA ×5 · CC-BY-NC ×12 · CC-BY-NC-SA ×1 · "unknown" ×14 · field
ABSENT ×1** (Targum Jonathan on Judges / Sefaria Community Translation —
a named version with no license field, exercised below). Classes:
PD/CC0 → `open` (the source class); CC-BY/CC-BY-SA → `attribution`
(per-document `license_override`, P10-4); CC-BY-NC/CC-BY-NC-SA → `nc`
(override); `"unknown"` or ABSENT → **skipped by rule, censused, never
ingested**; any other string → loud stop (owner decision before sync).
**`merged.json` files carry NO license field and are NEVER ingested**
(they are also never fetched: the fetch selector takes named versions
only — the on-disk merged fixture pins the ingest-side rule
belt-and-braces).

## Files

| fixture | whole? | exercises |
|---|---|---|
| `books.json` | SLICE | index header verbatim (`generated_at`/`bucket`/`base_url`/`total_texts`), `special_files` cut to its first entry, `books` cut to the 13 entries matching the fixtures below plus one merged sibling and one non-Targum entry (Berkovits — the selector's negative case); entry blocks byte-identical (`indent=1` round-trip verified) |
| `…/Targum Jonathan on Obadiah/Hebrew/Mikraot Gedolot.json` | whole | PD Aramaic prophets targum; `sectionNames ["Chapter","Verse"]`, single-chapter book (21 verses); `status: locked`; `actualLanguage` is upstream's `"he"` even though the text is Aramaic (the shelf-level `arc` ruling) |
| `…/Targum Jonathan on Obadiah/English/Targum Obadiah, translated by Thomas Lenihan.json` | whole | `"license": "unknown"` → skipped by rule, censused |
| `…/Targum Jonathan on Jonah/English/Sefaria Community Translation.json` | whole | CC0 English; inline footnote markup (`<sup class="footnote-marker">` + `<i class="footnote">`) → apparatus extracted to annotations, running text clean |
| `…/Targum Jonathan on Jonah/Hebrew/merged.json` | whole | a real merged file — NO license field, `versions:` list instead → never a ref (the pinned gate) |
| `…/Targum Jonathan on Judges/English/Sefaria Community Translation.json` | whole | a NAMED version with NO license field at all (the one corpus-wide) → skipped by rule, censused |
| `…/Targum Sheni on Esther/English/Sefaria Community Translation.json` | whole | depth-3 `sectionNames ["Chapter","Verse","Paragraph"]`; empty `[]` verses skipped |
| `…/Aramaic Targum to Ruth/Hebrew/Mikraot Gedolot.json` | whole | PD Aramaic Writings targum (the ot-hub RUT witness document) |
| `…/Targum Neofiti/English/Sefaria Community Translation.json` | whole | tiny partial translation (Genesis 1 only) — honest sparse coverage |
| `…/Tafsir Rasag/Tafsir Rasag/English/Sefaria Community Translation.json` | whole | CC0 but EXCLUDED TITLE (Judeo-Arabic tafsir) → skipped by rule; also a schema-node dict (`Introduction` + five books) |
| `…/Targum Jerusalem/Hebrew/Targum Jerusalem on Torah.json` | TRIM | complex schema: NO `sectionNames`, `text` = dict keyed by `schema.nodes[].enTitle` (five Torah books), fragmentary (empty-string verses dominate); trimmed to each book's first 2 chapters (original sha256 `97fbb09f…`, 353,161 bytes) |
| `…/Onkelos Genesis/Hebrew/Targum Onkelos, vocalized according to the Yemenite Taj .json` | TRIM | **CC-BY-SA** → `license_override: attribution`; NB upstream's own TRAILING SPACE in the versionTitle and filename; trimmed to chapter 1 (original sha256 `687e77de…`, 359,395 bytes) |
| `…/Onkelos Numbers/Hebrew/Sifsei Chachomim Chumash, Metsudah Publications, 2009.json` | TRIM | **CC-BY-NC** → `license_override: nc` (P10-4, MCP-excluded downstream); inline `<b>` markup unwrapped; trimmed to chapter 1 (original sha256 `e5d2df0e…`, 299,996 bytes) |

## Source shas (whole files, byte-verbatim as retrieved 2026-07-18)

```
ae75199ca584a37516db4f9bfa63ffd97de5e2669b08412bb3615af8f4ae5c21  Obadiah Hebrew Mikraot Gedolot
42f4075c22692195fa31a8a7433cdc2798bbe9441915c29caa25ab31e0104d55  Obadiah English Lenihan
b71861832ca322c91ebab2ca26dbc6dd45c19d39e0d3f86dc05a726bb65cec0c  Jonah English SCT
20e32dd9ba98e6ce71f709071dba98a528cebabe93fd3656b20547a784822224  Jonah Hebrew merged
c5f4eaa4bcaf7aaece9af2a2956034875aae0d4a901642dff2ad4274882e47bb  Judges English SCT
baa1491a726d43b91ce6c679cb2c9eb9bee104c0654cc27972d8b42254b6e245  Targum Sheni English SCT
04f303b283847ffdd09edc75bd8a0e7a05686da5ad3d9606254a583b4050dd83  Ruth Hebrew Mikraot Gedolot
7f0dfcccf32ce2b29401d69770552267f6573be971c91c726ca6407548da8459  Neofiti English SCT
6cce0a83dae4204e6d23fb75cac501aa13bc4e3f1e27f256101aea0b2cb493d7  Tafsir Rasag English SCT
```
