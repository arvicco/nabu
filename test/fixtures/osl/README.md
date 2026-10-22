# OSL — Oracc Sign List fixture

Source: **github.com/oracc/osl** (the Oracc Sign List, ex-OGSL; Veldhuis &
Tinney; rolling master, no tags). The machine artifact is `00lib/osl.asl`
(~979 KB, the line-oriented ASL grammar). Do NOT build on the repo's
`sl.json` — it serves a zero-byte 200 (the known Oracc failure class).

License: **CC0**, stated verbatim in the file header line kept in this
fixture: `@inote	CC0: osl.asl and its associated files are placed in the
public domain under a CC0 licence.` → house class `open`.

Retrieved: 2026-07-29 from
https://raw.githubusercontent.com/oracc/osl/master/00lib/osl.asl
at upstream commit `7749a4bd8589491b987ab3da31660ef4abca5012`
(master, 2026-07-28, "a few values for epsd2/royal").

## What this is

`osl.asl` is a TRIMMED excerpt of the real 979 KB file: whole blocks copied
**byte-verbatim** (never edited inside a block), joined in upstream order
with the upstream single-blank-line separator. The selection covers the ASL
taxonomy:

- the file header (`@project`/`@signlist`/`@domain`) + the **CC0 line** +
  two `@listdef` blocks (ABZL with wrapped continuation lines, MZL) + the
  five `@scriptdef` lines
- `ŠEŠ` — a simple encoded sign: 14 `@list` concordances, `@uname`,
  single codepoint as `@list U+122C0`, `@ucun 𒋀`, 23 values including the
  ₓ-values `sasₓ`/`zaₓ`, with `@ref`/`@inote`/`@link` noise interleaved
- `|ŠEŠ.AB|` — the compound: `@useq x122C0.x1200A` → 𒋀𒀊 (pins the `uri₅`
  story) + `@form |AB.ŠEŠ|` with its own reversed `@useq`
- `|ŠEŠ.KI|` — `@form |ŠEŠ.NA|` carrying its own value (`nannaₓ`) and its
  own `@list BAU012`
- `MIN` — a numeric sign (`@uname CUNEIFORM NUMERIC SIGN MIN`, value
  `2(diš)`, the query-marked value `šin₂?`)
- `|MIN.MIN|` — a `@fake 1` sign, plus the top-level
  `@compoundonly |MIN×IGI|` line
- `|A×AN|` — a codepoint-less compound (no `@ucun`/`@useq`/`@list U+`
  at all: the honestly-unencoded case)
- `|A×GAN₂@t|` — a **`@sign-` deprecation** that still carries a codepoint
- `AK` — the deprecated value `@v- aŋ` among 15 values
- `|AN.SAG@g|` — the language-qualified value `@v %akk ṣillu`
- `|A.BARA₂|` — an `@aka |A.BARAG|` alias
- `|IGI.DIB|` — the `@form+` variant marker (`@form+ |IGI.LU|`, nine
  occurrences upstream) plus a form with NO encoding at all (`@form
  LAK433`, only its concordance line)
- `|UD.ŠEŠ.KI|` — carries `idₓ`, which `|A.BARA₂|` above ALSO carries: the
  real ambiguous-value case (upstream `idₓ` lives on six signs; these two
  suffice to pin that lookup returns ALL candidates, never one silently)
- `|NU×U@c|` — three real quirks in one block: `@upua U+F009B` (private
  use), SPACE-separated directives (`@upua U+F009B`, `@ucun`, the form's
  `@oid o0048857` — most of the file uses tabs), and the ONE form in the
  whole upstream file whose block is closed by `@end sign` directly with
  no `@@` terminator
- the `@pcun 1(N01@f)` block (an ACN proposal, closed by `@end pcun`) —
  pins that sign-shaped directives inside non-sign blocks must NOT leak
  into sign records (they are censused as ignored)

## Refresh

Re-fetch the raw URL above and re-cut the same blocks (grep the sign names);
update the commit sha and date here.

## 00etc/cdli_sign_readings.tsv (P65-1)

Header + the complete E2 / |NUN.ME| / SZESZ row sets, copied byte-verbatim
2026-08-09 from the held canonical/osl/00etc/cdli_sign_readings.tsv (CC0
with the repo). Covers: ASCII sign-name folding (SZESZ→ŠEŠ), a compound
name, the 'a3 apostrophe fold, glossed ("n. brother", "n. sage") and
gloss-less rows. Refresh = re-sync osl, re-cut the same sign_name rows.

## 00etc concordance assets (Store::SignConcordances)

Whole lines copied byte-verbatim 2026-10-22 from the held
canonical/osl/00etc (CC0 with the repo; upstream commit
`7749a4bd8589491b987ab3da31660ef4abca5012`, the same as osl.asl above),
in upstream order. Each file keeps rows that JOIN onto this fixture's
signs (ŠEŠ o0002834, AK o0000093, MIN o0000456, |IGI.DIB| o0001487,
|ŠEŠ.KI| o0002740, …) beside real rows that must be CENSUSED as skips:

- `wikidata-script.csv` — header + lines 2, 3 (unencoded items with no
  oid mapping: no-join), 716 (Q87555001, whose Q-to-oid oid is not in
  this fixture: oid-not-held), 742/1038/1266/1414 (AK, |IGI.DIB|, MIN,
  ŠEŠ) and 1530 (URI3 — a multi-oid Q-to-oid row naming ŠEŠ too). Pins
  the quoted-comma cell ("138,VI") and the nbsp-padded "Char image" column.
- `wikidata/Q-to-oid.tab` — the six rows for those items.
- `wikidata.tsv` — lines 1 (U+12000, a sign not held here), 4, 30, 326,
  554, 702.
- `wikidata/oid-aks-lref-name.tsv` — lines 1, 79, 197, 198, 232, 249,
  283, 332, 345: two vacat/listref rows (oid o0000000) and two oids not
  held here.
- `aks-add.tsv` — lines 1, 79, 197, 198, 249 (a name-less row), 283, 332.
- `mzl-kwu.tsv` — lines 1, 24 (trailing tab), 91 and 103 (comment lines,
  one a commented-out row), 101 (a comma KWU list), 109 (no sign name),
  146, 580, 783 and 877 (bare "KWU" = KWU unnumbered).
- `pgsl.tab` — lines 1, 7, 9, 13 (the "=" section separator), 32 (a
  comment-only row: no sign name), 49, 204.
- `ebl-sign-names.json` — the 8 objects for 1(BAN₂) (not held) and the
  seven fixture signs, upstream's CRLF formatting kept (no final newline).
- `attinger.tab` lines 1, 188; `add-attinger.tab` lines 1, 24 (the
  duplicate of attinger.tab's appended copy); `csf.tab` lines 19 (idₓ —
  ambiguous), 73, 76, 1350, 1351, 1359; `eng.tab` lines 1, 156 (no ŋ value
  is held by this fixture: both rows censused value-not-held).

Refresh = re-sync osl, re-cut the same line numbers (re-grep the sign names
if upstream renumbers).
