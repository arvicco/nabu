# Displaying ancient text in a terminal

Nabu's shelves carry pointed Masoretic Hebrew, polytonic Greek, titlo-bearing
Old Church Slavonic, IAST and Devanagari Sanskrit, Ogham, Gothic, Coptic and
runes — and render them in a terminal. Two different layers decide what you
actually see, and only one of them is nabu's:

1. **What nabu does** (this repo, `--display`, `config/display.yml`): decide
   *which characters* of the stored text to draw, per language — display-time
   only, announced, reversible.
2. **What the terminal must do** (iTerm2/Terminal.app settings, fonts): draw
   those characters in the right *direction* and with the right *glyphs*.
   A CLI cannot fix a terminal that lays RTL text out backwards or lacks a
   Hebrew font — this page says exactly which knobs do.

---

## 1. What nabu's display layer does

The stored text is canonical: byte-verbatim from the source (Hebrew/Aramaic
are never even NFC-normalized — Masoretic mark order is preserved,
architecture §3). But the *stored* form is not always the *readable* form on
a terminal: cantillation accents stack illegibly in most monospace Hebrew
rendering, and Old Church Slavonic titla clutter a reading pass. So the
render layer — and only the render layer — can strip named mark classes.

**Where it applies.** The commands that print passage text: `show`, `align`
(including `--collate`), `search` (all modes), `concord`, `parallels`,
`cognates`. **It never applies to** `export`, the MCP server (AI clients
always get pristine bytes), matching, folding, or anything stored — a
test-pinned invariant: every `--display` mode returns identical search hits,
and `show --display full` is byte-identical to the database text.

**Config: `config/display.yml`** — per-language policies over named mark
classes:

```yaml
languages:
  hbo: { strip: [cantillation], keep: [points, maqaf], isolates: true }
  arc: { strip: [cantillation], isolates: true }
  san: { strip: [vedic-accents] }   # Devanagari-script text; IAST untouched
  chu: { strip: [titla] }
```

The mark classes are named codepoint sets defined in one place
(`Nabu::Display::MARK_CLASSES`), each backed by a census of the real corpus
bytes:

| Class | Codepoints | Notes |
|---|---|---|
| `cantillation` | U+0591–05AF | Hebrew accents only — never the vowel points, never maqaf |
| `points` | U+05B0–05BD, 05C1, 05C2, 05C7 | vowels, dagesh, shin/sin dots, meteg; kept by default, stripped by `plain` |
| `maqaf` | U+05BE | strips to a space, never fusing the words it joins |
| `vedic-accents` | U+0951, U+0952 | udatta/anudatta on Devanagari text; the IAST shelves (DCS) carry none |
| `titla` | U+0483, U+0487, U+2DE0–2DFF | titlo, pokrytie, combining superscript letters; palatalization U+0484 is *not* a titlo and stays |
| `monotonic` | U+0300, 0313, 0314, 0342, 0343, 0345 | Greek, **definable but not defaulted** — opt in via display.yml |

**Modes: `--display MODE`** on the render commands:

- `default` — the config-driven policy above.
- `full` — **no transforms at all**: every stored byte, no isolates, no
  spacing, no colors. The escape hatch; what you see is what the database
  holds.
- `plain` — strip every class the language policy defines (`strip` + `keep`):
  consonantal Hebrew, for instance.
- `translit` (P27-2) — romanized rendering through the language's registered
  transcoder; see §1a below.
- `mono` (P27-2) — exactly `default`, minus per-token language coloring;
  see §1b below.

The mode set is a registry — the `reading` mode is a future sibling on the
same seam.

**Grapheme spacing (`spacing:`, P27-2).** A per-language boolean in
`display.yml`; when true, the render inserts a separator between grapheme
clusters. Shipped default: `pgl: { spacing: true }` — Primitive Irish is
attested only in Ogham script, whose letters are stroke clusters on one
shared stemline and merge into unsegmented runs in a terminal font. Between
two Ogham letters the separator is U+1680 OGHAM SPACE MARK — the script's
own stemline-continuing space — so the line stays one stem while letter
boundaries become visible; `--display full` restores the exact stored run.
(The corpus's sga-Ogam and und layers can't be keyed per-language without
hitting Latin-script sga — corph — so they stay unspaced; journaled.)

### 1a. `--display translit` — romanized rendering

Registered transcoders, applied render-time only (footer:
`display: transliterated (--display full shows all marks)`):

| Languages | Transcoder | Notes |
|---|---|---|
| `san` | Devanagari→IAST (`Nabu::Deva`) | IAST shelves (DCS/GRETIL/MW) pass through untouched |
| `hbo`, `arc` | Hebrew→SBL-style romanization (`Nabu::Hebr`) | general-purpose SBL base with academic ʾ/ʿ/ḥ/ṭ/ś kept where general-purpose would merge distinct letters; every shewa renders ə (vocal/silent is not inferred); no dagesh-forte doubling; matres lectionis render as consonants (*bəreʾshiyt*). Output is LTR Latin — no isolates, and the most legible Masoretic view on a bidi-less terminal (Terminal.app). |
| `chu`, `orv`, `bul` | Cyrillic→scholarly Latin (`Nabu::Cyrl`) | the display direction of the P27-2 cross-script fold table (ѣ→ě, щ→št, ѫ→ǫ, оу→u); text the source already wrote in Latin (damaskini's diplomatic layer) passes through **byte-identical** — the render layer never rewrites the source's own surface. Combining marks (titla) stay on their letters: stripping is `default` mode's business, not the transcoder's. |

A language with no registered transcoder passes through unchanged — never a
guessed romanization. **Ogham** deliberately has no transcoder: the corpus
itself ships the transliteration as a line-aligned *sibling document*
(`…-translit`, same line numbers) — `nabu show <ogham-urn> --parallel`
inlines it today, which is the honest surface (a display mode sees only
text + language, never the catalog; wiring a db lookup into the render seam
would cross the render-only boundary). Journaled as a possible show-level
follow-up.

### 1b. Per-token language coloring

Code-switching texts (CorPH's Latin words inside Old Irish sentences,
OSHB's Aramaic verses inside Hebrew books) carry a per-token `lang` tag in
their stored token annotations. `nabu show` (single-passage view) colorizes
tokens whose tag **differs from the passage language** — one stable ANSI
color per language, named in the footer
(`display: token colors: lat=cyan …`). The honesty rules:

- **Color only what's honestly tagged**: untagged tokens and base-language
  tokens stay uncolored. damaskini's tokens carry no language tag (its
  chu/bul split lives at document grain) — so damaskini text renders
  uncolored, correctly.
- A token form that can't be located in the display text paints nothing —
  never a fabricated span.
- `NO_COLOR` (any non-empty value) always wins; without it, color appears
  only on a TTY (`NABU_COLOR=1` forces it for pagers that render ANSI);
  `--display mono` keeps the default stripping but never colors;
  `--display full` shows plain stored bytes.
- Coloring composes with the existing lemma-hit/snippet highlighting — the
  ANSI escapes are ASCII, untouched by mark stripping and bracket markers.

### 1c. Cross-script search folding (the search layer, not display)

Sibling to the display work, P27-2 extended the **search fold**
(conventions §9) with per-language *script neutralization*: one language
spelled in two scripts folds to ONE indexed skeleton, symmetrically at
index and query time. `search 'धर्मन्'` ≡ `search dharman` (san,
Devanagari→IAST before the virāma-eating mark strip), and `search vъsta` ≡
`search въста` ≡ the union of both scripts' hits (chu/orv/bul,
damaskini's Latin-diplomatic ↔ the Cyrillic shelves). A zero-hit query in
a script with *no* registered neutralization (Glagolitic, Gothic script)
prints one honest hint naming what to try.

**Consequence — a fold change invalidates the fulltext index.** The
neutralization changes `text_normalized` for san/chu/orv/bul passages and
lemmas, so an index built before P27-2 will miss cross-script queries until
it is re-derived: one `nabu rebuild` (or per-source `nabu sync <slug>
--parse-only` resyncs of the affected shelves) refreshes it.

**The honesty footer.** Whenever a transform actually changed something, the
command ends with one hint line — never silent alteration, and no line when
nothing happened:

```
display: cantillation stripped (--display full shows all marks)
```

**RTL isolates.** With `isolates: true` (hbo/arc), rendered runs are wrapped
in U+2067/U+2069 (RTL isolate / pop). In a bidi-capable terminal this keeps
Hebrew runs coherent inside left-to-right layout lines; where bidi is absent
the characters are invisible and harmless. Width math (KWIC columns) excludes
them, so alignment never shifts.

---

## 2. What the terminal must do (nabu cannot)

*The facts below were verified live on macOS, 2026-07-18.*

### Direction (bidi)

Most terminals draw characters in storage order, left to right — which
mangles Hebrew/Aramaic into reversed strings. This is a terminal capability,
not something escape characters from nabu can force:

- **iTerm2 ≥ 3.6.0** ships RTL support as an **experimental toggle**:
  **Settings → General → Experimental → "Right-to-left text support"**
  (note: *not* under Profiles → Text). Turn it on for Hebrew reading.
- **macOS Terminal.app has no bidi support at all.** Hebrew renders in
  storage order; there is no setting to change it.
- **Copy-paste garbling**: when display and storage disagree about
  direction, copied RTL text comes out scrambled. The bidi toggle fixes
  this; nothing nabu emits can.

### Fonts

- iTerm2's **"Use a different font for non-ASCII text"** (Profiles → Text)
  applies **per codepoint, not per script**. A size-boosted Hebrew font in
  that slot wrecks mixed-ASCII/diacritic text — IAST Pali/Sanskrit (ā/ṁ/ṭ)
  jumps fonts mid-word. Verified guidance: fill the slot with **Noto Sans
  Mono at the SAME size as the ASCII font** (`brew install --cask
  font-noto-sans-mono`) for uniform metrics across IAST, Greek, Cyrillic and
  Hebrew.
- For dedicated Masoretic sessions, use a separate **iTerm2 profile** (the
  terminal's per-task mechanism) — e.g. a "Hebrew reading" profile with
  **Ezra SIL at +4pt**.
- Recommended scholarly Hebrew fonts: **Ezra SIL** (SIL OFL, purpose-built
  for pointed + cantillated Masoretic text) and **SBL Hebrew** (equally
  excellent; personal-use license).
- Script-specific Noto casks join the macOS font-fallback cascade once
  installed, even when not the chosen slot font — one command each:
  `brew install --cask font-noto-sans-ogham font-noto-sans-coptic
  font-noto-sans-gothic font-noto-sans-runic`.

---

## 3. Per-script quick table

| Script | What nabu does (default) | What the terminal needs | Try it |
|---|---|---|---|
| Hebrew (hbo/arc) | strips cantillation, keeps points + maqaf, RTL isolates | iTerm2 RTL toggle; Ezra SIL / SBL Hebrew (profile) or Noto Sans Mono (slot) | `bin/nabu show urn:nabu:oshb:gen:1.1` |
| Greek (grc) | nothing (polytonic intact; `monotonic` opt-in) | any font with polytonic coverage | `bin/nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1` |
| Cyrillic OCS (chu) | strips titla (titlo/pokrytie/superscripts); `--display translit` romanizes | Noto Sans Mono covers the combining range | `bin/nabu align "MARK 2.3"` |
| Devanagari (san) | strips Vedic accents when present (IAST untouched); `--display translit` → IAST | conjunct-capable Devanagari fallback (system default is fine) | `bin/nabu search "dharma" --lang san` |
| Ogham (pgl) | letter spacing with U+1680 (stemline-continuing); translit via `show --parallel` | `font-noto-sans-ogham` | `bin/nabu show urn:nabu:ogham:e-dev-001` |
| Coptic | nothing | `font-noto-sans-coptic` | `bin/nabu search ⲛⲟⲩⲧⲉ --lang cop` |
| Gothic | nothing | `font-noto-sans-gothic` | `bin/nabu search guþ --lang got` |
| Runic | nothing | `font-noto-sans-runic` | `bin/nabu show urn:nabu:riig:ais-01-01` |

Every transform in column two is display-time and announced; `--display
full` always shows the stored bytes, and the MCP surface never applies any
of this.
