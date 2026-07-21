# BabelStone IDS fixture

Trimmed slice of Andrew West's `IDS.TXT` — Ideographic Description Sequences
for CJK Unified Ideographs.

- **Source URL:** https://www.babelstone.co.uk/CJK/IDS.TXT
- **Retrieved:** 2026-07-20 (upstream File Date 2025-06-27, Unicode Version
  16.0, 97,680 total entries)
- **Encoding:** UTF-8 with BOM and CR/LF (preserved byte-verbatim)
- **License:** public-domain dedication — quoted verbatim in the file
  header §2 (kept in this slice): *"…IDS sequences in themselves are not
  eligible for copyright protection … anyone is free to make use of the IDS
  data provided in this file for personal or commercial purposes without
  asking permission or providing attribution."* → registry class `open`.

## Trim

The real header is kept verbatim (metadata + provenance §1 + the licence
dedication §2 + the format notes §4/§5), followed by 12 real data lines
chosen so the acceptance character 棄 (U+68C4) and a coherent
transitive-containment neighbourhood are present:

- 棄 (U+68C4) = `⿳亠厶⿻廿木` — contains 木 via the `⿻廿木` overlay;
- its components 亠 厶 廿 木 and the J/K-form component 丗;
- other 木-containing chars 本 林 (so `--char-component 木` transitive
  containment has real multi-hit coverage), plus 一 世 云 and the
  simplified/z-variant 弃 (U+5F03) as non-木 controls.

The component sequences contain real CJK Extension B codepoints
(𠃊 U+200CA in 世, 𠆢 U+201A2 in 木) — the honest Ext-B presence the
display.md fonts rider censuses (Jigmo fallback territory).
