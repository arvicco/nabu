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
- `reading` — the language default strips **plus** the per-source edition
  rules of §1a below: apparatus simplified for fluent reading.
- `diplomatic` — the edition's marks exactly as stored (byte-honest, no
  isolates; `reading`'s counterpart — today it renders identically to
  `full`, named so the reading/diplomatic pair speaks the editorial
  vocabulary).

The mode set is a registry — `translit` and `mono` modes are planned on the
same seam, and this table will grow with them.

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
| `gaiji` | not-yet-encoded-character sentinels — kanripo `&KR\d+;` (P38-2), aozora `※［＃…］` (P39-5) | `ladder` \| `placeholder` \| `refs` | kanripo → `ladder` (faithful glyph → IDS → marked `⌈substitute⌉` → ⬚); aozora → `ladder` (IDS-only lane → ⬚); refs kept verbatim under diplomatic |

**Gaiji (kanripo, P38-2) — the display ladder.** The mandoku parser keeps
kanripo's not-yet-encoded characters as `&KR\d+;` references verbatim in the
stored text. In `reading` mode `gaiji: ladder` resolves each ref *per
character*, down four rungs of descending fidelity — the first rung that holds
the ref wins:

| Rung | Source table | Rendering | Example (`&KR…;` →) |
|---|---|---|---|
| 1. **Faithful** | `config/gaiji/kanripo.tsv` | the real codepoint, **unmarked** — it *is* the character | `&KR0001;` → `𫠦` |
| 2. **IDS** | `config/gaiji/kanripo-ids.tsv` | the Ideographic Description Sequence, inline | `&KR…;` → `⿰氵丐` |
| 3. **Substitute** | `config/gaiji/kanripo-substitutes.tsv` | a lossy read-through, **visibly marked** `⌈…⌉` | `&KR4710;` → `⌈脊⌉` |
| 4. **⬚ placeholder** | — | the honest box (U+2B1A) — never a fake glyph | `&KR0809;` → `⬚` |

The **substitute mark `⌈…⌉`** (U+2308 LEFT CEILING / U+2309 RIGHT CEILING) is a
deliberately *unclaimed* pair — it collides with none of the editorial brackets
already in use (erasures `⟦…⟧`, lacuna `[…]`, surplus `{…}`, sigla `⸀⸂⸃`, the
`⬚` placeholder, the IDS operators `⿰`–`⿻`) — so a lossy stand-in glyph can
**never be quoted unaware** as if it were the faithful character. It is BMP and
present in monospace/Noto Sans Mono, so it renders in a terminal.

The **IDS rung is empty for kanripo today** (its one charlist composition,
KR0198 `[沔-丏+丐]`, resolved to an *encoded* glyph 沔 and so lands on the
faithful rung); the rung is live machinery for the Aozora source (P38-3), whose
gaiji are largely IDS compositions. The census stays honest and partial: of
KR-Gaiji's refs, 427 carry a faithful codepoint and 562 more a single-glyph
substitute (cumulatively **81.8%** of the 1,751,360 gaiji *occurrences*); the
rest stay the ⬚ box.

The **honesty footer never goes silent** on a lossy or failed resolution, but
the faithful rung needs no announcement (it *is* the text). It aggregates the
lower rungs — substitutes shown, IDS compositions, and placeholders remaining:

```
$ bin/nabu show urn:nabu:kanripo:KR1h0004:001:1a --display reading
子曰𫠦學而⬚時習之
display: 1 unresolved gaiji (--display diplomatic shows the gaiji refs)

# a passage that also hits the substitute rung:
子⌈脊⌉曰⬚
display: 1 substituted, 1 unresolved gaiji (--display diplomatic shows the gaiji refs)
```

`gaiji: placeholder` (the P37-3 behavior, preserved as config) is **rungs 1 + 4
only** — faithful glyph or the ⬚ box, with the IDS and substitute lanes never
consulted; its footer keeps the older `N unresolved gaiji (M resolved)` shape.

**Gaiji (aozora, P39-5) — the ladder's second CJK source, the IDS rung live.**
The aozora-ruby parser resolves standard gaiji at parse time (JIS kuten, `U+…`)
but keeps *component-description-only* gaiji (survey §4c class-(c)) as a loud
verbatim sentinel `※［＃…］` in the stored text — the aozora analogue of
kanripo's `&KR\d+;`. `aozora: { gaiji: ladder }` runs the **same four-rung
ladder**, keyed per-source through `Nabu::Display::GAIJI_SENTINELS`: the source
slug selects (a) the sentinel pattern and (b) the lane KEY. For aozora the key
is the **component formula** — the leading `「…」` group, exactly the parser's
stored gaiji `desc` — so the per-book page/line locator trailing the notation
(`、8-11`) never fragments the lane.

aozora ships **only the IDS lane** (`config/gaiji/aozora-ids.tsv`); with no
faithful or substitute lane file its refs land on **rung 2** (a derived
`⿰`/`⿱`) or **rung 4** (the ⬚ box) — the generic ladder skips the empty lanes.
The lane is **generated** by `rake gaiji:aozora_ids` from a held, checked-in
census of the corpus's composition descriptions
(`config/gaiji/aozora-descriptions.tsv`, snapshotted read-only from the
parse-time annotations) via a **conservative mechanical grammar**
(`Nabu::Ops::AozoraIdsBuilder`): a single `＋` between two literal CJK
ideographs → `⿰`, a single `／` → `⿱`; **everything else refuses** and stays
the loud sentinel (kana radical-names `にんべん＋巨`, subtraction `旗－其＋冉`,
parenthesised/nested `（禾＋尤）／上／日`, multi-operator `筮／八／口`). Of 582
distinct composition descriptions the grammar derives **244** (46.2% of their
occurrences); the honest majority stays refused.

**A derived `⿰AB` is a STRUCTURAL claim, not an identity claim.** It says "this
glyph is A-left, B-right" and renders on the IDS rung — which is honest about
being a *description*, never a real codepoint. That is why the bar is
mechanical-only and *when in doubt, refuse*: kana radical-name → component-glyph
resolution (`にんべん` → `亻`) and arithmetic on components would be guesses, so
they are journaled leaves, not derivations.

```
$ bin/nabu show <an aozora passage> --display reading
水⿰口斗流と⬚人
display: 1 composed, 1 unresolved gaiji (--display diplomatic shows the gaiji refs)
```

Three shelves deliberately have **no** entry:

- **ogham** — its stored fixtures carry zero edition marks (the glyph and
  choice machinery resolves everything at parse time).
- **oracc** — the braces are *determinatives* (`{d}amar-{d}suen`): silent
  classifiers that keep-text-drop-marker would fuse into the word as a
  misreading; the standalone `x` marks are illegible-sign placeholders and
  the rare parentheses are metrological notation (`2(BARIG)`). All content
  — all kept, journaled in the backlog.
- **cbeta** — its gaiji `<g>` fallback *text* is resolved at parse time and
  is already the stored reading surface (P33-2), so there is no `&KR;`-style
  ref to display-transform. A documented non-entry, exactly the ogham logic.

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
  font-noto-sans-gothic font-noto-sans-runic font-noto-sans-old-italic`.
  Old Italic (U+10300–1032F) is the Sabellic axis's block (P29-2): the
  sabellic-loans etymon headwords are real Old Italic codepoints
  (𐌓𐌖𐌚𐌓𐌉𐌉𐌔), while the ItAnt/CEIPoM inscription text itself is stored
  in the editions' Latin transliteration — the language tags
  (`osc-Ital-x-oscetr`) and script facets name the alphabet the stones
  carry.

### CJK fonts (Han ideographs, kana) — the coverage problem

The Sinitic/Japonic axes (lzh/och/ojp, and the `nabu char` card) render Han
ideographs and kana. For the BMP CJK the terminal needs a CJK font in the
non-ASCII slot or the fallback cascade:

- `brew install --cask font-noto-sans-cjk-sc` (Simplified) covers the
  common ideographs; add `font-noto-sans-cjk-tc` (Traditional) and
  `font-noto-sans-cjk-jp` (Japanese glyph forms) as the regional forms you
  read call for. These join the macOS fallback cascade once installed, the
  same mechanism as the script Notos above.

- **The real gap is rare characters.** kanripo/cbeta and the decomposition
  shelves reach CJK Extension B and beyond (plane 2+, U+20000 up), where Noto
  CJK stops. This is exactly the tail the gaiji ladder (§1a) resolves to a real
  codepoint — the faithful and substitute rungs both put *encoded but unfonted*
  characters on screen, so the font, not nabu, is what decides whether you see
  the glyph or a ⬚ box. The census IS the justification: a scan of this repo's
  Sinitic fixtures (BabelStone IDS + KRADFILE + Unihan) finds **6 distinct
  Ext-B+ codepoints already present** — the IDS component stubs 𠃊 (U+200CA),
  𠃋 (U+200CB), 𠄏 (U+2010F), 𠆢 (U+201A2) that build common characters
  (棄's 木 = ⿻十𠆢), plus 𢖩 (U+225A9) and the Ext-F 𬻌 (U+2CECC). Every one
  of these renders as ⬚/□ (missing glyph) under Noto CJK alone. At corpus
  scale the count is far larger — the rare-char tail is where a second font
  install earns its keep. Three cover it, in the macOS font-fallback cascade
  (download the `.ttf`/`.otf` and double-click, or drop it in `~/Library/Fonts`;
  none is a Homebrew cask):

  - **Jigmo** (the Hanazono/HanaMin successor) — one family covering *every*
    encoded Han character across all extensions; the broadest single install,
    ships as `Jigmo.ttf` / `Jigmo2.ttf` / `Jigmo3.ttf` (install all three).
  - **Plangothic** (Plangothic P1/P2) — a modern gothic-style face with very
    deep Ext-B through Ext-I coverage; the most legible of the three at
    terminal sizes, and actively maintained.
  - **BabelStone Han** — Andrew West's font, strong on the rare CJK blocks and
    the CJK-symbol/IDS ranges; a good third fallback for anything the other two
    miss.

  Once installed they join the fallback cascade automatically; the terminal
  picks whichever family has the glyph, so having all three maximises coverage
  of the plane-2+ tail.

- **Ambiguous-width toggle OFF** (the East-Asian width section below): nabu
  measures the ambiguous class narrow, so leave iTerm2's "treat
  ambiguous-width as double-width" off to match. Vertical CJK layout is a
  deliberate non-goal — terminals are horizontal.

### East-Asian width (CJK) — what nabu models, what the terminal owns

Chinese/Japanese/Korean ideographs, kana, hangul and fullwidth forms occupy
**two terminal cells** each. nabu *does* model this: `Nabu::Display.width`
(P35-7) measures every column-aligned surface — concord KWIC, the
distinctive-vocabulary table, aligned columns — in display **cells**, not
`String#length`, classifying each grapheme by its Unicode East-Asian-Width
class (transcribed from **EastAsianWidth.txt, Unicode 16.0.0**; W/F = 2, all
else = 1). So a lzh (Literary Chinese) or ojp (Old Japanese) KWIC line lines
its keyword column up exactly where a Greek line does. This is measurement,
not policy: there is no `--display` mode and no footer for it — cell width is
a rendering fact the terminal already enforces.

The one thing nabu leaves to the terminal is the **Ambiguous (A)** width
class. Unicode assigns a handful of codepoints (Greek/Cyrillic letters, some
punctuation, geometric shapes, the □ missing-glyph box) an *ambiguous* width:
narrow in a Latin context, wide in a legacy CJK context. nabu measures them
**narrow (one cell)** — the Unicode default — because the corpus text is
ancient scholarship read in a modern UTF-8 terminal, not a legacy
double-byte one. A **fixture-scale census** of the held lzh/ojp passages
(kanripo + cbeta + oncoj; tls is a lexicon, no passage text) found **10
ambiguous codepoints out of 48,673** (0.02%) — every one of them U+25A1 □
WHITE SQUARE, kanripo's placeholder for an unmappable glyph. ojp's
man'yōgana original rides the passage *annotations*, not the rendered
(romanized) KWIC text, so the corpus's actual wide-text exposure is the lzh
Han. At that scale the ambiguous class is a rounding error, and the narrow
default is right.

- **iTerm2 users: keep "Treat ambiguous-width characters as double-width"
  OFF** (Settings → Profiles → Text). With it ON, the terminal draws those
  ambiguous codepoints two cells wide while nabu measured them as one, and a
  column padded by nabu drifts by exactly that count. OFF matches nabu's
  measurement, and — per the census — barely matters either way for this
  corpus. (macOS Terminal.app has no such toggle; it treats ambiguous as
  narrow, already matching nabu.)

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
| Old Italic (osc/xum) | nothing (inscription text is stored in Latin transliteration; the U+10300 block appears in the sabellic-loans etymon headwords) | `font-noto-sans-old-italic` | `bin/nabu etym rufus` (after the sabellic-loans sync) |
| Han (lzh, kanripo) | measures CJK cells (§2); `reading` runs the four-rung gaiji ladder (§1a) — faithful glyph → IDS → `⌈substitute⌉` → ⬚ (P38-2), refs kept under `diplomatic` | any font with CJK Ext-B+ coverage — Jigmo / Plangothic / BabelStone Han (§2); resolved glyphs reach plane 2 (𫠦 U+2B826) | `bin/nabu show urn:nabu:kanripo:KR1h0004:001:1a --display reading` |
| Kana/kanji (ojp) | oncoj romanization/original layers per its own design; man'yōgana rides the annotations, not the romanized KWIC | Noto CJK + Jigmo/Plangothic/BabelStone Han (same cascade) | `bin/nabu char 天` · an oncoj urn |

Every transform in column two is display-time and announced; `--display
full` always shows the stored bytes, and the MCP surface never applies any
of this.

---

## 4. Runic (Rundata / SRDB) — the transliteration IS the text

*Added P40-6 (2026-07-22), with the rundata adapter.*

What the corpus actually carries, so nobody goes hunting for runes that
were never there:

- **SRDB stores no runic codepoints.** The Scandinavian Runic-text
  Database records every inscription in the scholarly **Latin
  transliteration** (lower-case, `þ` thorn, `R` for the *yr*/ʀ rune, `o`
  for the nasal ą rune) — verified zero U+16A0–16FF across the artifact.
  The transliteration is the canonical text under the bare urn
  (`urn:nabu:rundata:u-344`), not a display transform of anything.
- **The notation legend is content, never stripped** (it encodes the
  stone's state and the editor's judgment): `§A §B …` inscription
  sides/sections, `|` word/rune boundaries and runes shared between words
  (`o| |onklati`), `' + ¶ × :` separators as carved, `(i)` an uncertain
  rune, `-` one illegible rune, `----` a run of lost runes, `[l]`
  editorial restoration, and a leading `"` marking a proper name
  (`"Ulfr`). `--display full` and default rendering show the same stored
  bytes; no display.yml transform applies.
- **The five lanes are sibling documents** — reach them with
  `show --parallel` (the registry `siblings:` declaration): the bare urn
  is the transliteration; `-fvn` (Old West Norse normalisation), `-rsv`
  (runic Swedish normalisation), `-eng`/`-swe` (translations) sit beside
  it, e.g. `bin/nabu show urn:nabu:rundata:u-344 --parallel`. Absent
  lanes are simply absent.
- **No display.yml entry** (the ogham/oracc no-entry logic): there is
  nothing to strip and nothing to transliterate — the stored text is
  already the romanized scholarly form, and the notation must survive
  untouched. Censused need: none.
- **Forward-looking:** if a future source ever carries real Runic-block
  codepoints (U+16A0–16FF, `ᚠᚢᚦ…`), the terminal side is one cask —
  `brew install --cask font-noto-sans-runic` joins the macOS fallback
  cascade like the other script Notos (§2). Relevant only then; nabu
  would still never transliterate Latin → runes on its own.
