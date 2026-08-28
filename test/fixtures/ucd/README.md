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

Redistributable: Unicode License v3 (MIT-style, `license_class: open`).
