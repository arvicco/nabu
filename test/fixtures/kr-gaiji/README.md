# KR-Gaiji fixture (P37-3)

Trimmed real slice of `charlist.org.txt` from **github.com/kanripo/KR-Gaiji**
at commit `662fd61d3f564e26c62810329aff3b9bae9fff99` (2019-11-30), retrieved
2026-07-20. Licensed CC BY-SA 4.0 (the kanripo org grant).

KR-Gaiji is the Kanseki Repository's list of **not-yet-encoded characters**:
one row per `&KR\d+;` gaiji reference that appears in KR texts. Each line is

```
KR{id}  {freq}  {unicode-or-IDS repr}  {normalized version}  {image link}
```

The nine rows here are hand-picked to cover every mapping class the census
found (full numbers in the P37-3 worklog paragraph and `config/gaiji/kanripo.tsv`
header). They are the load-test and honesty evidence, not fabricated:

| id | class | what it exercises |
|---|---|---|
| `KR0001` | faithful codepoint | col3 = 𫠦 (U+2B826) → resolves to the real glyph |
| `KR0005` | faithful codepoint | col3 = 將 (BMP) → resolves |
| `KR0007` | faithful codepoint | col3 = 𤣥 (U+248E5) → resolves |
| `KR0002` | normalized-only | col3 empty, col4 = 若 (lossy substitute) → **placeholder** |
| `KR0008` | image-only | col3 + col4 both empty → **placeholder** |
| `KR0809` | image-only | the parser's own `&KR0809;` example → **placeholder** |
| `KR0132` | dubious multi-cp | col3 = "𦒿 " (codepoint + stray space) → excluded, placeholder |
| `KR0198` | dubious multi-cp | col3 = "[沔-丏+丐]" (bracket composition) → excluded, placeholder |
| `KR0359` | dubious multi-cp | col3 = "㴱?" (uncertainty mark) → excluded, placeholder |

Only the three faithful-codepoint rows land in the shipped resolution map;
everything else stays a placeholder box (⬚), never a fake glyph. The census
verdict: of 5,254 refs / 1,751,360 occurrences, only 36.4% of occurrences
resolve to a real codepoint, so the resolution lane is a genuine but partial
win layered over the placeholder that ships regardless.
