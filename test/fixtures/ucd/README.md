# UCD fixture — UnicodeData.txt (trimmed)

A structurally-intact slice of the real `UnicodeData.txt`, retrieved from
<https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt> on 2026-08-28
(`nabu sync ucd`, Unicode 17.0.0).

Twenty real lines, chosen to exercise every shape the read seam
(`Nabu::Ucd`) must parse — nothing hand-written:

- **plain letters** across scripts — Latin (`0041`/`0061`), Greek
  (`0391`/`03B1`), Hebrew (`05D0`), Old Italic (`10300`), Egyptian
  Hieroglyph (`13000`) — with their case mappings.
- **a control** (`0000`) whose `name` field is `<control>` and whose real
  label lives in the Unicode-1.0 name column (`NULL`).
- **decomposition** — canonical (`00C0` À → `0041 0300`) and tagged
  (`00BD` ½ → `<fraction> 0031 2044 0032`, `2160` Ⅰ → `<compat> 0049`).
- **numeric values** — a digit (`0664` → 4), Roman numerals (`2160` → 1,
  `2185` → 6), a Gothic numeral (`10341` → 90), a fraction (`00BD` → 1/2).
- **a combining mark** (`0300`, combining class 230).
- **range pairs** — `<CJK Ideograph, First>`/`<…, Last>` (`4E00`/`9FFF`)
  and `<Hangul Syllable, First>`/`<…, Last>` (`AC00`/`D7A3`): interior
  code points have algorithmically-DERIVED names, never listed lines.
- P86 appended real lines at the file tail (the parser indexes by code
  point, order-independent): `16A0` (ᚠ, the member-context anchor),
  `30A2` (ア, the ambiguity-panel anchor), and the jamo/letter cast
  `110B`/`1175`/`11B8`/`3147` (the hangul reading-line tests).

## Member files (P86-1, №R-49a — the useful-context tier)

All retrieved 2026-08-28 from the real `UCD.zip`
(<https://www.unicode.org/Public/17.0.0/ucd/UCD.zip>, Unicode 17.0.0),
except `confusables.txt`, which comes from the security tree's own
version line (<https://www.unicode.org/Public/security/16.0.0/>, UTS #39
— no 17.0.0 existed there at retrieval). Every file keeps its real
header block; trims select real lines covering the identity fixture's
code-point cast (Latin a, Greek α, Hebrew א, runic ᚠ, Old Italic 𐌀,
hiragana と, CJK 木-radical row, Hangul, Cuneiform, Egyptian, Tangut):

- `Blocks.txt` — 18 real block rows of ~400.
- `Scripts.txt` / `ScriptExtensions.txt` — the rows covering the cast
  (incl. `30FC ; Hira Kana`, the extensions shape).
- `NameAliases.txt` — the `0000` control/abbreviation rows and the
  `FE18` "BRAKCET" correction, among real others.
- `DerivedAge.txt` — rows covering the cast (`0020..007E ; 1.1`,
  `16A0..16F0 ; 3.0`, …).
- `Jamo.txt`, `CJKRadicals.txt` — WHOLE (3.3K / 5.4K, structurally
  their own document).
- `EquivalentUnifiedIdeograph.txt` — the `2F4A` (⽊ → 木) rows.
- `PropertyValueAliases.txt` — the full `gc` and `sc` sections (the
  short↔long vocabulary the script line renders through).
- `NamesList.txt` — the chart entries for the cast (`05D0` carries
  `= aleph` + the `x (alef symbol - 2135)` crossref shape).
- `NamedSequences.txt`, `StandardizedVariants.txt`, `DoNotEmit.txt`,
  `TangutSources.txt` (`U+17000` rows), `NushuSources.txt` — header +
  a handful of real rows each (parsers for the later P86 slices).
- `confusables.txt` — the Latin-a cluster rows (`FF41`, `237A`,
  mathematical alphabets → `0061`), the "looks like" panel's shape.

Redistributable: Unicode License v3 (MIT-style, `license_class: open`).
