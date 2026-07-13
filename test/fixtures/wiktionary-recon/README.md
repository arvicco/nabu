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

## P17-3 additions (reconstruction shelf part 2; retrieved 2026-07-13)

Four NEW extracts (the survey docs/recon2-survey.md §4 fixture plan, owner-
approved) plus five golden lines appended to the existing files. All lines
byte-verbatim (`select_fixtures_p17_3.py` in scratch, same post-check);
the three existing extracts re-downloaded 2026-07-13 hash IDENTICAL to the
2026-07-12 snapshot (sha256 above), so the appends are same-file.

New files (full-download sha256, then what each kept line preserves):

- `.../Proto-Balto-Slavic/kaikki.org-dictionary-ProtoBaltoSlavic.jsonl`
  — 1,692,429 B, 491 lines, sha256
  `5fcd528f8c316e38bf8ece3a1c87e5407358a8f556ce7c670b546ee18fc6b0f5`
  → **3 lines** (upstream lines 23/92/175):
  - `duktḗ` — borrowed-flagged Proto-Finnic/Samic/Mordvinic descendants:
    the loan flag on off-gold display-only edges.
  - `pírštan` — THE multi-hop golden: named by PIE `*per-` (root #1),
    names `sla-pro *pь̃rstъ` whose accented fold joins the sla-pro shelf
    headword `pьrstъ`; the chain bottoms at chu прьстъ + Glagolitic
    ⱂⱃⱐⱄⱅⱏ and orv пьрстъ gold.
  - `wárˀnāˀ` — the ˀ (U+02C0, MODIFIER LETTER GLOTTAL STOP) headword
    quirk, ×310 in PBS headwords; folds to `warna` under the P17-3 ine
    fold extension.
- `.../Proto-West%20Germanic/kaikki.org-dictionary-ProtoWestGermanic.jsonl`
  — 49,438,078 B, 5,551 lines, sha256
  `803bc28eebc73bd00d54ae87fff0b027149b6b93e448486c9a33b7bbc11d8bc4`
  → **3 lines** (252/253/699):
  - `faru` noun 1 and 2 — `etymology_number` homographs; faru:1's tree
    carries `sl barva` flagged borrowed (the German-loan-in-Slovene edge,
    a gold-language loan label).
  - `hlaib` — ang hlāf gold (the OE proto desk) + the sco/en-heavy modern
    tail (112 worded nodes) proving gold-scoping stays quiet; also named
    by gem-pro `*hlaibaz` (the second intermediate-shelf path).
- `.../Proto-Italic/kaikki.org-dictionary-ProtoItalic.jsonl`
  — 5,229,349 B, 745 lines, sha256
  `b16f7cb74b44dff6c1cb27d8af58975728d290a50bc2b6a596c11847e43dca29`
  → **2 lines** (124/147):
  - `gʷōs` — `la bōs` raw_tags `["borrowed"]`: a loan INTO the gold
    language from Osco-Umbrian, the meet-shelf-heuristic counterexample;
    ʷ fold quirk.
  - `kʷis` — clean inherited `la quis/quid` (Vulgate-attested) with a PIE
    parent (`*kʷís`, appended below): the unflagged Italic ascent.
- `.../Proto-Indo-Iranian/kaikki.org-dictionary-ProtoIndoIranian.jsonl`
  — 3,338,611 B, 799 lines, sha256
  `d7076cb20e41d3e80fd8e256c8d44a92d49734fce291e30601c836ac25fd9d47`
  → **3 lines** (81/156/229):
  - `bʰráHtā` — the sa reflex's roman `bhrā́tṛ` is the script bridge to
    GRETIL's romanized san gold.
  - `kšatrám` — `xcl աշխարհ` flagged borrowed (the Iranian-loan layer in
    Armenian, 81 of the live extract's 84 xcl edges).
  - `adᶻdʰáH` — the ᶻ (U+1DBB) / ˢ (U+02E2) modifier-letter fold class
    (ˢ×12 ᶻ×9 measured) + a "reshaped by analogy or addition of
    morphemes" raw_tag that must NOT parse as borrowed.

Appends to the existing files (upstream line numbers in the same-sha
downloads; appended after the strata, the `hrunkwǭ` precedent):

- ProtoSlavic + `xlěbъ` (686: chu хлѣбъ leaf, the UNFLAGGED direct half of
  the *hlaibaz borrowed-OR golden) + `pьrstъ` (1144: chu прьстъ Cyrillic +
  Glagolitic, orv пьрстъ — the multi-hop golden's bottom).
- ProtoIndoEuropean + `per-` root #1 "before, in front" (28: names
  `ine-bsl-pro *pírštan` — the golden's top; NOTE upstream has THREE per-
  root records; only #1 is kept, so its entry_id stays `per-:root`) +
  `kʷís` (111: names `itc-pro *kʷis`).
- ProtoGermanic + `hlaibaz` (320: the borrowed flag rides the
  PROTO-TO-PROTO edge — `sla-pro *xlěbъ` raw_tags `["borrowed"]` — while
  got 𐌷𐌻𐌰𐌹𐍆𐍃/ang-side edges are unflagged: the closure must OR along the
  path, pinned by the indexer tests).

Borrow-marker census over all eight live extracts (2026-07-13, scratch):
`"borrowed"` ×92,120, `"learned borrowing"` ×405, plus a free-text hedge
tail ("possibly borrowed from …") — all matched `/borrow/i`; the frequent
non-loan raw_tag "reshaped by analogy or addition of morphemes" carries no
"borrow" substring and stays false.
