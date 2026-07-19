# CDLI fixtures — P31-2

Trimmed real slices for the `cdli` adapter (`Nabu::Adapters::Cdli` /
`AtfParser`, parser family `atf`). Retrieved **2026-07-19** from
`https://github.com/cdli-gh/data` at commit
`d66b12b065af39a57d640576b4c7e098db5dac7f` (master tip, committed
2023-10-11 — the snapshot vintage the adapter honestly labels; the repo
README still says "Last update was August 2022" and the daily dump is
dead; the cdli.earth API is the journaled freshness channel, not wired).

Both upstream files are **Git LFS objects** — the repo itself holds only
134-byte pointers. Payloads were downloaded through the standard LFS
Batch API (`…/data.git/info/lfs/objects/batch`, anonymous — the same
protocol `Nabu::LfsFetch` speaks) and sha256-verified against the
pointer oids before slicing:

| upstream file | size | pointer oid (sha256) |
| --- | --- | --- |
| `cdli_cat.csv` | 154,768,722 B | `2e3232f75325b61c4d1e788d4d8c074c6230a947aed422110f9f35a6e353d09c` |
| `cdliatf_unblocked.atf` | 86,897,831 B | `2896ec253767fa07fcaa5424af6fc25d6a047dc30b99c95f99d57ce75384d836` |

## License (the bespoke open grant, verbatim — cdli.earth/terms-of-use)

> Text in the pages of CDLI may be freely copied, aggregated and re-used
> according to common and fair academic practice; we request, in the
> case of re-use of considerable textual data, that mention be made of
> the source of such material, with reference to CDLI.

→ class `attribution`. Images are governed by separate fair-use language
on the same page and are ENTIRELY out of scope (never fetched).

## Corpus census (2026-07-19, full payloads at the pinned commit)

- Catalog: **353,283 rows / 64 columns**; `id_text` is a bare integer
  (P-number = `P%06d`), unique, max 532447. 59 distinct `language`
  values (Sumerian 139,961 · blank 90,177 · Akkadian 84,736 · Hittite
  14,669 · undetermined 8,493 · Eblaite 6,871 · … · junk "clay" ×9);
  81 distinct `period` values, 329,948 rows carrying the year envelope
  inside the period string itself ("Ur III (ca. 2100-2000 BC)");
  `external_id` bdtns-schemed on 96,641 rows; `composite_id` Q-numbers
  on ~29k.
- ATF: **135,255 `&P` blocks** (54 duplicate headers — same P under two
  designations — first block wins), **~2.19M numbered lines**, 2,063
  zero-line blocks, 156 blocks carrying junk lines (honest quarantine
  floor), `#atf: lang` in 12 spelling variants (sux 100,161 · akk
  22,095 · qpc 8,330 · qeb 1,359 · nlc 461 · …), `#tr.*` inline
  translations (en 94,968 · ts 9,386 · de/it/fr/fa/dk/es/ca), 119,946
  `>>` composite links (Q direct + letters via `#link: def` /
  `#atf def linktext`).

## `cdliatf_unblocked.atf` — 7 blocks, byte-verbatim, file order

| block | why |
| --- | --- |
| `P000001` | proto-cuneiform (`qpc`), multi-column obverse, direct `>>Q000002` links, `$` states |
| `P000725` | the spec exemplar: proto-cuneiform, `>>A` letter links through the OLDER `#atf def linktext A = Q000002` definition spelling |
| `P225015` | `#atf: use lexical`, `#link: def`, `\|\| A 791` parallel riders, `@obverse?` uncertain face, NO `#atf lang` line (and an empty catalog language — the double-fallback exemplar) |
| `P323717` | tablet & envelope & seal multi-object block (object segment joins the urn), lineless objects, `$` states incl. trailing |
| `P469841` | BOTH blocks of a real duplicate `&P` header ("Anonymous 469843" vs "Anonymous 0700") — first wins, second skipped by rule |
| `P480562` | `@object weight` / `@surface a` (argument-named face) + `#tr.en:` |
| `P519727` | the stray-space header `& P519727`, `#tr-en:` hyphen variant, `@object composite text`, `>>Q006486` |

## `cdli_cat.csv` — header + 12 real rows (re-serialized by Ruby CSV, content-verbatim)

The 7 ATF P-numbers above **plus 5 metadata-only artifacts** (rows with
no ATF block — the owner-approved universal-catalog shape):

| row | why |
| --- | --- |
| `P008113` | Proto-Elamite (ca. 3100-2900 BC), Susa — proto-Elamite's only home |
| `P104749` | Ur III + `bdtns:015946` concordance + `Amar-Suen.01.04.00` ruler date |
| `P274853` | `fake (modern)` period (honestly undated), language Ugaritic, "Elbonia ?" |
| `P282287` | Middle Hittite (ca. 1500-1100 BC), Assur |
| `P519993` | "Akkadian; Persian; Elamite" multi-language Achaemenid trilingual |

## Trim recipe

Blocks/rows extracted by P-number with a python csv/regex pass over the
verified payloads (whole blocks and whole rows, nothing edited inside);
re-acquiring them means re-downloading the two LFS payloads (240 MB) —
so the manifest marks both files `refetchable: false`.
