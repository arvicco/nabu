# Wiktionary reconstruction fixtures (P14-1 — the reconstruction shelf)

Real upstream samples from the **kaikki.org machine-readable reconstruction
dictionaries** (wiktextract / Tatu Ylönen's extraction of English
Wiktionary): Proto-Slavic (`sla-pro`), Proto-Indo-European (`ine-pro`) and
Proto-Germanic (`gem-pro`). Every kept line is **byte-verbatim** upstream
data — the selection script picks whole JSONL lines and a post-check
asserts each emitted line is a literal line of the raw download; only the
record SET was trimmed.

- **Retrieved:** 2026-07-12, full downloads (extraction dated 2026-07-09
  from the enwiktionary dump dated 2026-07-06):
  - `https://kaikki.org/dictionary/Proto-Slavic/kaikki.org-dictionary-ProtoSlavic.jsonl`
    — 47,623,549 B, 5,431 lines ("5195 distinct words"), sha256
    `85b0e8ec33851faf94fcb608e90b8b508d5a5a8503fa5af0fc670b561e4c90d3`
    → **75 fixture lines**.
  - `https://kaikki.org/dictionary/Proto-Indo-European/kaikki.org-dictionary-ProtoIndoEuropean.jsonl`
    — 12,026,624 B, 1,905 lines ("1781 distinct words"), sha256
    `72a315b0b0d2357a872dd17de6aa9bac43f8d920ece196c6adb14661bb21f3d1`
    → **61 fixture lines**.
  - `https://kaikki.org/dictionary/Proto-Germanic/kaikki.org-dictionary-ProtoGermanic.jsonl`
    — 65,338,100 B, 5,717 lines ("5552 distinct words"), sha256
    `38593fbdea0831dd2ff801b41256f2aec970eb6bcffdadcf7b9bbd448fbafbec`
    → **74 fixture lines** (73 strata lines + upstream line 4539
    `hrunkwǭ` appended out of order — the ONE record in all three
    extracts whose descendants carry a malformed lang_code, `"ML."`
    Medieval Latin; it pins the nil-language posture).
- **License (verbatim, https://kaikki.org/dictionary/ "Copyright and
  license", re-verified 2026-07-12):** "This data is made available under
  the same licenses as Wiktionary - both CC-BY-SA and GFDL." Plus the
  academic citation request for wiktextract (Ylönen, LREC 2022,
  pp. 1317–1325).
- **Deprecation caveat:** like the OCS extract, the per-language
  postprocessed JSONL is labelled "DEPRECATED, will be removed in the near
  future" (wiktextract issue #1178) but serves today. Durable fallback:
  filter the full enwiktionary extract by `lang_code`.

## Upstream format reality (what these fixtures preserve)

- The OCS record shape (one JSON object per line, one record per
  WORD × POS × etymology, no top-level id, `etymology_number` homograph
  splits) **plus**:
  - `original_title` on every record — the Wiktionary page title
    (`Reconstruction:Proto-Slavic/bogъ`). The `word` field carries **no
    asterisk**.
  - **`descendants`** on ~89% of records — a recursive tree of
    `{lang, lang_code, word?, roman?, tags?, descendants?}` nodes.
    Branch-grouping nodes (`zle` "East Slavic") carry no `word`; OCS
    reflexes nest under *script* children ("Old Cyrillic script" /
    "Glagolitic script", **both** `lang_code "cu"`); `roman` carries the
    romanization that matches how the catalog's got/san/xcl gold lemmas
    are spelled (Gothic-script 𐌲𐌿𐌸 is unfindable, its roman `guþ` is a
    914-passage gold lemma). Reflexes that are themselves reconstructions
    (proto-to-proto edges, e.g. PIE → `sla-pro *bogъ`) DO carry a leading
    asterisk on `word`.
- Raw lines are **not NFC** (`bʰeh₂ǵos` ships with decomposed `ǵ`) — the
  parser's NFC boundary is load-bearing and pinned by tests.
- Wiktionary lang_codes are 639-1 where one exists (`cu`, `la`, `sa`) —
  the parser maps join-relevant codes to the catalog's 639-3
  (`chu`/`lat`/`san`), identity for everything else.

## Selection recipe (deterministic; scratch script `select_fixtures.py`)

Per extract, union of (first-match order, line order preserved, lines
byte-verbatim):

1. **demo chain**: sla-pro `bogъ` (all records) + `cěsařь`; ine-pro
   `bʰeh₂g-`, `ǵʰutós`, `gʷʰew-`, `bʰeh₂ǵos`, `swé`; gem-pro `gudą`,
   `kaisaraz` — the attested→proto→PIE walks the etym tests ride
   (cu богъ → *bogъ → *bʰeh₂g-; got guþ → *gudą → *ǵʰutós; the царь
   loan chain crosses cěsařь/kaisaraz).
2. **held-language reflexes**: first records naming a worded reflex per
   code — sla-pro: cu/orv/sl ×4; ine-pro: grc/la/sa/xcl/hit ×3 + the
   proto-to-proto edges sla-pro/gem-pro ×3; gem-pro: got/ang/non ×4.
3. **homographs**: first 3 with `etymology_number` ≥ 2.
4. **structural edges**: first 2 without `descendants`; first 2 without
   `etymology_text`; first 2 with all senses glossless; first 1 with
   grouping-only descendants (tree present, zero worded nodes).
5. **script/tag edges**: first 3 with a Glagolitic-script reflex
   (sla-pro); first 2 with a tags-bearing worded reflex.
6. **sweep**: every 100th line (sla-pro, gem-pro), every 50th (ine-pro).
7. **quirk**: gem-pro upstream line 4539 (`hrunkwǭ` — the lone `"ML."`
   malformed lang_code in all three extracts), appended after the strata.

Totals: 75 + 61 + 74 = 210 records, 1,908,607 bytes.

Re-apply this recipe after any refresh; fresh GETs return the full
extracts (fetched for URL-liveness only, never byte-compared).
