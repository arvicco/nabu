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
- `full` — **no transforms at all**: every stored byte, no isolates. The
  escape hatch; what you see is what the database holds.
- `plain` — strip every class the language policy defines (`strip` + `keep`):
  consonantal Hebrew, for instance.
- `reading` — the language default strips **plus** the per-source edition
  rules of §1a below: apparatus simplified for fluent reading.
- `diplomatic` — the edition's marks exactly as stored (byte-honest, no
  isolates; `reading`'s counterpart — today it renders identically to
  `full`, named so the reading/diplomatic pair speaks the editorial
  vocabulary).

The mode set is a registry — `translit` and `mono` modes are planned on the
same seam, and this table will grow with them.

**The honesty footer.** Whenever a transform actually changed something, the
command ends with one hint line — never silent alteration, and no line when
nothing happened:

```
display: cantillation stripped (--display full shows all marks)
display: apparatus simplified: sigla (--display diplomatic shows the edition marks)
```

**RTL isolates.** With `isolates: true` (hbo/arc), rendered runs are wrapped
in U+2067/U+2069 (RTL isolate / pop). In a bidi-capable terminal this keeps
Hebrew runs coherent inside left-to-right layout lines; where bidi is absent
the characters are invisible and harmless. Width math (KWIC columns) excludes
them, so alignment never shifts.

---

## 1a. Edition-level transforms — `--display reading` (P27-1)

Language policies dress *scripts*; the `sources:` section of
`config/display.yml` dresses *editions* — transforms keyed to a source's
editorial conventions, executed only by the `reading` mode
(`--display diplomatic` shows the same marks byte-honest, as stored).

The rules are census-first over the **stored** passage bytes, and the stored
surface is much leaner than raw Leiden: the parsers already read through
supplements `[abc]`, editorial additions `<abc>`, expansions `(abc)` and
unclear-underdots at parse time (all censused ×0 in stored text — no rules
exist for them; per-shelf counts in the backlog, P27-1). What the shelves
actually carry, and what `reading` does about it:

| Rule | Marks | Settings | Shipped |
|---|---|---|---|
| `lacuna` | `[…]` — the one gap marker every Leiden parser emits | `ellipsis` \| `keep` | papyri-ddbdp, edh, riig → `ellipsis` (`[…]` reads `…`) |
| `erasures` | `⟦abc⟧` — EDH damnatio memoriae, RIIG/Ogham `<del>` | `keep` \| `unwrap` | `keep` — an erasure is content; unwrap drops only the brackets, never the text |
| `surplus` | `{abc}` — letters carved in error (RIIG) | `keep` \| `unwrap` | `keep` — unwrapping would present a misspelling as fluent text without its marker |
| `sigla` | `⸀ ⸂ ⸃` — SBLGNT's apparatus cross-references | `strip` \| `keep` | sblgnt → `strip` (⸁ and ⸄–⸇ censused ×0, not in the set) |

Two shelves deliberately have **no** entry:

- **ogham** — its stored fixtures carry zero edition marks (the glyph and
  choice machinery resolves everything at parse time).
- **oracc** — the braces are *determinatives* (`{d}amar-{d}suen`): silent
  classifiers that keep-text-drop-marker would fuse into the word as a
  misreading; the standalone `x` marks are illegible-sign placeholders and
  the rare parentheses are metrological notation (`2(BARIG)`). All content
  — all kept, journaled in the backlog.

**Ketiv/qere (oshb).** The stored verse text carries the *ketiv* (written)
form; the *qere* (read) form rides that token's annotations. Per-source
config `qere_display: qere | ketiv | both` (shipped: `qere`) chooses which
side `reading` shows; `both` renders "ketiv [qere]". Token-level display
substitution from the stored annotations — never a re-parse, never stored.
Hebrew reading mode thus composes naturally: qere read **and** cantillation
stripped together:

```
$ bin/nabu show urn:nabu:oshb:ruth:1.8 --display reading
…
display: cantillation stripped · apparatus simplified: qere · rtl isolates (--display diplomatic shows the edition marks)
```

**RIIG orig/reg.** RIIG's parallel editorial readings are separate sibling
passages by construction (`urn …:PLT-a:1` vs `…:MLE-a:1`), and within one
passage `<choice>` already keeps the regularized branch — orig and reg never
share a passage, so there is no display-time choice to make; `reading`'s
Leiden handling suffices.

**Scope.** Edition rules apply where the command knows the passage's source:
the `show` family (passage, document listing, range). Search/concord/align
render under the language policies alone — matching is never affected either
way (the mode-independence pin covers `reading` and `diplomatic` too).

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
| Cyrillic OCS (chu) | strips titla (titlo/pokrytie/superscripts) | Noto Sans Mono covers the combining range | `bin/nabu align "MARK 2.3"` |
| Devanagari (san) | strips Vedic accents when present (IAST untouched) | conjunct-capable Devanagari fallback (system default is fine) | `bin/nabu search "dharma" --lang san` |
| Ogham | nothing | `font-noto-sans-ogham` | `bin/nabu show urn:nabu:ogham:e-dev-001` |
| Coptic | nothing | `font-noto-sans-coptic` | `bin/nabu search ⲛⲟⲩⲧⲉ --lang cop` |
| Gothic | nothing | `font-noto-sans-gothic` | `bin/nabu search guþ --lang got` |
| Runic | nothing | `font-noto-sans-runic` | `bin/nabu show urn:nabu:riig:ais-01-01` |

Every transform in column two is display-time and announced; `--display
full` always shows the stored bytes, and the MCP surface never applies any
of this.
