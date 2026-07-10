# ISWOC treebank fixtures

Real samples from the ISWOC Treebank (Bech & Eide, University of Oslo), which
uses the **PROIEL XML** format (CLAUDE.md fixture rules). Two Old English
documents plus one Old French **exclusion probe** (the `ang` language filter is
the one behavior this adapter adds over the TOROT pattern; its exclusion branch
is tested against a real non-`ang` file, owner-approved 2026-07-10).

- **Retrieved:** 2026-07-10, from the pinned commit
  `574c81cd9dbf8124290e869bc65078c303a36911` (final commit of the archived
  repo) of [iswoc/iswoc-treebank](https://github.com/iswoc/iswoc-treebank)
  via `raw.githubusercontent.com`, base
  `https://raw.githubusercontent.com/iswoc/iswoc-treebank/574c81cd9dbf8124290e869bc65078c303a36911/`.
- **Acquisition plan** approved by owner 2026-07-10 ("Approved as is, including
  the third fixture"; docs/backlog.md P12-1 plan block).

## Files

| File | Bytes | Source (full B) | Trim |
|---|---|---|---|
| `wscp-mark.xml` | 305,320 | `wscp.xml` (2,735,960) | PROIEL surgery — leading **3 whole divs** (Matthew 7 fragment · Mark 1 · Mark 2; 150 sentences, 1,393 tokens), no div/sentence split. West-Saxon Gospels, `ang`. |
| `æls-head20.xml` | 86,069 | `æls.xml` (646,405) | PROIEL surgery + **div truncation, see below** — first **20 whole sentences** of div 1 (383 tokens). Ælfric's Lives of Saints, `ang`. |
| `eustace-head.xml` | 20,899 | `eustace.xml` (469,127) | PROIEL surgery + div truncation — first **3 whole sentences** of div 1 (63 tokens). La Vie Saint Eustace, `fro` — the exclusion probe; discover must drop it. |

Full upstream files were fetched to a scratch dir and are **not** committed.
Upstream sha256 at fetch time: `wscp.xml`
`a9b5616743005f804fd98d3850b05a057665c78abaac7b85c39c67401aec0238`, `æls.xml`
`b6d224bee95f2f4f187bc3df10e4fb09ccba11a1a9038796221db56fa9def2f4`,
`eustace.xml`
`3b73305dac5d8db8c727bb48924bcc67af321422c2e7bd28bbb9f3ccc7193ce7`.

## Trim procedure

- **`wscp-mark.xml`** — the torot-fixture PROIEL surgery verbatim: XML
  declaration + `<proiel>` root + entire `<annotation>` + `<source>` with all
  metadata children, then whole leading `<div>` elements (3 divs), then
  `</source></proiel>`. No div or sentence is split.
- **`æls-head20.xml` / `eustace-head.xml`** — same surgery, except the single
  kept `<div>` is **truncated after the Nth whole `<sentence>`** (20 / 3) and
  closed cleanly. Deviation from the approved plan text ("leading whole
  divs"), forced by upstream structure discovered at fetch time: `æls.xml` has
  only 2 divs and div 1 alone holds 197 of 198 sentences (~630 KB — keeping it
  whole would blow the owner-approved ~35–55 KB size envelope); `eustace.xml`'s
  div 1 is 24 sentences (~95 KB vs the approved ~10–15 KB). Sentences are never
  split; the result parses strict and keeps the real upstream token stream.

## Licenses (per-source `<license>` recorded exactly)

All three `<source>` headers carry, identically:
`<license>CC BY-NC-SA 3.0</license>`,
`<license-url>http://creativecommons.org/licenses/by-nc-sa/3.0/us/</license-url>`.

The repo README agrees verbatim: the treebank "is freely available under a
[Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License](http://creativecommons.org/licenses/by-nc-sa/3.0/us/)".
No LICENSE file in the repo. license_class `nc`. Cite as: "Bech, Kristin and
Kristine Eide. 2014. The ISWOC corpus. Department of Literature, Area Studies
and European Languages, University of Oslo."
