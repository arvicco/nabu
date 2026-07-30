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
