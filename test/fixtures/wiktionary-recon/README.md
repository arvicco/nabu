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

Four NEW extracts (the survey .docs/surveys/recon2-survey.md §4 fixture plan, owner-
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

## P25-2 additions (attested Celtic; retrieved 2026-07-17)

Three NEW extracts — the P25 Celtic axis (survey
`.docs/surveys/celtic-survey.md`, gitignored planning material). These are
ATTESTED languages riding the recon source (the wiktionary-cu precedent:
attested entries mint reflex edges too, no display asterisk; the codes are
real ISO 639-3, adopted as themselves). All kept lines byte-verbatim (same
post-check as above); the license statement on
https://kaikki.org/dictionary/ re-verified verbatim 2026-07-17 ("This data
is made available under the same licenses as Wiktionary - both CC-BY-SA
and GFDL.").

Full-download census (extraction dated 2026-07-09, from the enwiktionary
dump dated 2026-07-06; sha256 of the full downloads):

- `.../Old%20Irish/kaikki.org-dictionary-OldIrish.jsonl` — 19,776,265 B,
  **6,564 lines** ("5828 distinct words"; 2,093 with descendants, 3,116
  with etymology_text, 1,427 naming Proto-Celtic, 1,263 naming PIE — the
  DIL-derived depth), sha256
  `6d595de9838796a819100f18809c74f8729db937278c392d888ef713f5814abb`
  → **3 fixture lines** (upstream lines 693/674/675):
  - `rí` "king" — THE crosswalk golden: cel-pro/ine-pro etymology kept
    verbatim in the body (*rīxs, *h₃rḗǵs), descendants mga rí → ga rí /
    gd rìgh / gv ree; the mga node is the mga shelf's own headword, so
    the shelf-visited ascent runs Middle Irish rí → Old Irish rí.
  - `ingen` 1 "daughter" / `ingen` 2 "nail" — the classic DIL homograph
    pair split by `etymology_number`; ingen 1's etymology carries the
    Ogham-script Primitive Irish ᚔᚅᚔᚌᚓᚅᚐ (real Ogham codepoints through
    the NFC boundary).
- `.../Middle%20Irish/kaikki.org-dictionary-MiddleIrish.jsonl` —
  1,267,269 B, **767 lines** ("710 distinct words"), sha256
  `7739a1a0b465298a74d9ec9bcc2eeca41f4992fc00cfb80246836e4650eb2952`
  → **3 fixture lines** (74/55/37):
  - `rí` — bottoms the sga golden (the ascent target) with its own
    ga/gd/gv descendants.
  - `clann` — the en `clan` node under gd clann carries raw_tags
    `["borrowed"]` (the Gaelic loan into English); its own etymology is
    the Latin planta loan chain via Old Irish cland / Old Welsh plant.
  - `data` "sire, father" — the structural edge: no etymology_text, no
    descendants.
- `.../Middle%20Welsh/kaikki.org-dictionary-MiddleWelsh.jsonl` —
  1,343,469 B, **766 lines** ("695 distinct words"), sha256
  `a3a810637fda4822f41e5f49a4896d5fc0ccecd80d0aa7992df4901985602767`
  → **3 fixture lines** (41/58/59):
  - `cant` "hundred" — cel-pro *kantom / PIE *ḱm̥tóm etymology, cy cant
    descendant.
  - `cam` 1 "step" / `cam` 2 "bent" — `etymology_number` homographs, each
    with a cy descendant.
- `.../Umbrian/kaikki.org-dictionary-Umbrian.jsonl` — 1,132,498 B,
  **500 lines** (whole-corpus census 2026-07-18: 373 with
  etymology_text, 30 romanization stubs), sha256
  `c985e245392b56c021eaa4cf5206a1a1838883d4f40f979738a4d4d0faff4d9d`,
  retrieved 2026-07-18 (the P29-1 CEIPoM rider — the only kaikki-served
  Italic corpus language) → **3 fixture lines** (2/5/220):
  - `angla` — plain attested noun form (late Iguvine), no etymology.
  - `tre` — one of the 30 romanization stubs.
  - `𐌀𐌛𐌄𐌐𐌄𐌔` "fat, fatty portions of an animal" — Old Italic-script
    headword (real U+10300-block codepoints through the NFC boundary),
    Proto-Italic etymology chain + descendants.

Selection recipe: whole JSONL lines picked by upstream line number as
listed (deterministic; the post-check asserts each emitted line is a
literal line of the raw download).

## P29-0 addition (attested Etruscan; retrieved 2026-07-18)

One NEW extract — the Etruscan axis rider on the OpenEtruscan packet.
ATTESTED language on the recon source (the wiktionary-cu/P25-2
precedent: no display asterisk; `ett` is real ISO 639-3, adopted as
itself). All kept lines byte-verbatim; the license statement on
https://kaikki.org/dictionary/ re-verified verbatim 2026-07-18 ("This
data is made available under the same licenses as Wiktionary - both
CC-BY-SA and GFDL.").

Full-download census (sha256 of the full download):

- `https://kaikki.org/dictionary/Etruscan/kaikki.org-dictionary-Etruscan.jsonl`
  — 637,430 B, **493 lines** (485 distinct words; 419 Old Italic-script
  headwords + 73 `pos: romanization` stubs; 179 with etymology_text; 10
  records carry descendants → 11 Latin edges, **8 upstream-flagged
  borrowed** — the Etruscan→Latin loan layer), sha256
  `cc9ee00245ad383f60d75a3a6dcc3594cae0b3d68e123e1b02a1507da62c2786`
  → **4 fixture lines** (upstream lines 1/18/37/266):
  - `vetus` (line 1) — the romanization-stub shape (pos "romanization",
    gloss "romanization of 𐌅𐌄𐌕𐌖𐌔").
  - `𐌀𐌅𐌉𐌋` (line 18) — Old Italic headword with etymology_text and an
    UNFLAGGED la Aulus descendant (borrowed: false, not NULL).
  - `𐌘𐌄𐌓𐌔𐌖` (line 37) — THE loan-edge golden: la persōna descendant
    raw_tags `["borrowed", "uncertain"]` under an intermediate ett node
    raw_tags `["reshaped by analogy or addition of morphemes",
    "uncertain"]` (no /borrow/i substring → false) — the per-edge
    honesty the closure ORs along the path.
  - `𐌋𐌀𐌍𐌉𐌔𐌕𐌀` (line 266) — the clean borrowed case: la lanista
    raw_tags `["borrowed"]`.

## P32-3 addition (attested Chinese; retrieved 2026-07-19)

One NEW extract — **wiktionary-zh**, the whole-macrolanguage Chinese
extract (language `zho`; the OWNER-APPROVED ~1.1 GB disk call). ATTESTED
language on the recon source (the wiktionary-cu/P25-2 precedent), and the
ONLY extract parsed with `historical_sounds: true`: the per-entry
`sounds` rows tagged `Middle-Chinese` / `Old-Chinese` (+ the school —
`Baxter-Sagart` / `Zhengzhang`) surface as body lines; nothing else in
`sounds` (modern lect romanizations, IPA) enters bodies. All kept lines
byte-verbatim (post-check as ever); the license statement on
https://kaikki.org/dictionary/ re-verified verbatim 2026-07-19 ("This
data is made available under the same licenses as Wiktionary - both
CC-BY-SA and GFDL.").

Full-download census (2026-07-19; upstream Last-Modified 2026-07-16):

- `https://kaikki.org/dictionary/Chinese/kaikki.org-dictionary-Chinese.jsonl`
  — **1,181,142,520 B (~1.1 GiB), 323,840 lines** (303,963 distinct
  words), sha256
  `e0b6c4ed6aac4d311f1cfbd3109014541889d06287065276970a24ec5b7a2fdd`.
  **MC/OC census (the reconstruction value):** 23,484 records carry a
  Middle Chinese reading; 19,382 an Old Chinese reconstruction — 8,158
  Baxter-Sagart, 19,273 Zhengzhang (**Zhengzhang arrives ONLY via
  kaikki** — ytenx is license-blocked, see docs/02-sources.md row 50).
  8,098 records carry `descendants` (the Sino-Xenic ja/ko/vi loan
  lanes); 26,184 carry etymology_text; pos landscape: soft-redirect
  123,055 · noun 90,150 · verb 34,092 · character 29,879 · name 19,314 …
  → **6 fixture lines** (upstream lines 2/3/4/9/122/18894):
  - `GDP` noun (line 2) — a modern term: full modern `sounds`, NO MC/OC
    rows — pins that no historical lines are invented.
  - `A` verb (line 3) / `A` adj (line 4) — `etymology_number` homographs
    (ids A:verb:1 / A:adj:2).
  - `犬` character (line 9) — THE golden: MC `khwenX` + OC Baxter-Sagart
    `/*[k]ʷʰˤ[e][n]ʔ/` + OC Zhengzhang `/*kʰʷeːnʔ/`, all three
    fixture-pinned as body lines.
  - `MD` soft-redirect (line 122) — the dominant record shape (123,055
    upstream): no-gloss stub, honest nil.
  - `茶` character (line 18894) — the Sino-Xenic loan pin: descendants
    carry ja 茶 (roman `cha`) / ryu / ko 차(茶) readings raw_tags
    `["borrowed"]`; the ja/ko codes pass through unmapped (display-only
    until a CJK gold shelf lands — the P32-4 bridge's future join).
