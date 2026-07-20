# frozen_string_literal: true

require "yaml"
require_relative "errors"
require_relative "normalize"
require_relative "deva"
require_relative "cyrl"
require_relative "hebr"

module Nabu
  # Display-time text policy (P27-0). ONE place that decides how passage text
  # is dressed for the TERMINAL: per-language mark stripping (config/display.yml)
  # and RTL isolate wrapping, selected by a named display mode (--display).
  #
  # Hard boundaries, in order of importance:
  #   - RENDER-ONLY. The canonical store, the derived db, the search fold, and
  #     MCP output never pass through this module. `--display full` is the
  #     byte-honest escape hatch and every transform is announced in a footer
  #     hint by the CLI — never silent alteration.
  #   - CENSUS-FIRST. The mark classes below are named codepoint sets backed by
  #     a census of the real fixture bytes (counts journaled in the backlog,
  #     P27-0); nothing is stripped that was not censused or owner-specified.
  #   - GRAPHEME-SAFE. Stripping removes combining marks / named punctuation by
  #     codepoint class, never a base letter. NFC languages round-trip through
  #     NFD so marks fused into precomposed characters are reachable; the
  #     NFC-exempt languages (hbo/arc — Masoretic mark order, P26-3) are
  #     stripped in place, byte-order untouched, never normalized.
  #
  # == The mode registry (the sibling-packet seam)
  #
  # A display mode is any object with #name, #description,
  # #render(text, language:, policy:) → Rendered, and #isolates?(policy).
  # P27-0 registers default/full/plain; later packets add modes (reading,
  # translit, mono) via Display.register_mode without reshaping anything —
  # the CLI resolves --display MODE through Display.mode, which names the
  # registry on a miss.
  module Display
    class Error < Nabu::Error; end
    # config/display.yml failed validation: unknown mark class, bad language
    # key, non-boolean isolates. Named errors — the message says which key.
    class ConfigError < Error; end
    # --display MODE named a mode the registry does not hold.
    class UnknownModeError < Error; end

    # The result of rendering one run of text: the display text plus the names
    # of the transforms that actually changed something (mark-class names, and
    # ISOLATES when a wrap was added). +applied+ empty ⇒ text == input.
    # +gaiji+ (P37-3) is an optional GaijiTally when the reading mode resolved
    # or placeheld `&KR\d+;` refs — nil for every other render, so the count
    # rides out to the CLI footer without touching the applied vocabulary.
    Rendered = Data.define(:text, :applied, :gaiji) do
      def initialize(text:, applied:, gaiji: nil) = super
    end

    # The gaiji outcome of one render (P37-3): how many `&KR\d+;` refs the
    # reading mode turned into a real resolved glyph vs. left as the ⬚
    # placeholder box. Summed across passages by the CLI for the honesty
    # footer; never a label in +applied+ (a Set would drop the count).
    GaijiTally = Data.define(:resolved, :unresolved)

    # A named codepoint set. +codepoints+ is an array of Integer/Range;
    # +replacement+ is what each stripped codepoint becomes — "" for combining
    # marks; maqaf becomes a space so the two words it joins never fuse.
    MarkClass = Data.define(:name, :codepoints, :replacement, :regexp) do
      def initialize(codepoints:, replacement: "", **rest)
        chars = codepoints.flat_map { |c| c.is_a?(Range) ? c.to_a : [c] }
        super(codepoints: codepoints, replacement: replacement,
              regexp: /[#{chars.map { |c| format('\u{%04X}', c) }.join}]/, **rest)
      end
    end

    # == The mark classes (named codepoint sets — the one data-driven place)
    #
    # Census (2026-07-18, real fixture bytes; full counts in backlog P27-0):
    #   cantillation  OSHB Gen/Jer/Ps/Ruth carry 25 distinct accents in
    #                 U+0591–05AF (×1,436 total). NOT the points, NOT maqaf.
    #   points        U+05B0–05BC vowels/dagesh (×5,538), shin/sin dots
    #                 U+05C1/05C2 (×304), qamats qatan U+05C7 (×0 here) —
    #                 plus METEG U+05BD (×252): Unicode names it HEBREW POINT
    #                 METEG, censused, so it folds with the points. Rafe
    #                 U+05BF is a point by name but censused ×0 → left out
    #                 ("never strip what you haven't censused"). Sof pasuq
    #                 U+05C3 / paseq U+05C0 are punctuation, unclassified,
    #                 always kept.
    #   maqaf         U+05BE (×258) — strips to a SPACE, never fusing words.
    #   vedic-accents U+0951 udatta / U+0952 anudatta, the owner-specified
    #                 set. Censused ×0 in the san shelves (DCS is IAST
    #                 romanization; the SARIT fixtures are unaccented
    #                 Devanagari) — the class is live machinery for accented
    #                 Devanagari, a measured no-op today.
    #   titla         titlo U+0483 (torot ×49, ud/orv ×51, wiktionary-cu ×39),
    #                 pokrytie U+0487 (×1), combining Cyrillic superscript
    #                 letters U+2DE0–2DFF (×2). The CCMH fixtures carry NONE —
    #                 that corpus stores the Helsinki 7-bit ASCII
    #                 transliteration verbatim, titlos encoded as `!`.
    #                 Palatalization U+0484 (torot ×22) is NOT a titlo and is
    #                 deliberately not in the set.
    #   monotonic     grc, OPTIONAL — definable in display.yml, never
    #                 defaulted. Strips breathings (U+0313/0314), perispomeni
    #                 (U+0342), koronis (U+0343), varia (U+0300), iota
    #                 subscript (U+0345); the acute survives. A strip, not a
    #                 polytonic→monotonic conversion (conversion — grave→acute
    #                 etc. — is a display MODE for a later packet).
    MARK_CLASSES = {
      "cantillation" => MarkClass.new(name: "cantillation", codepoints: [0x0591..0x05AF]),
      "points" => MarkClass.new(name: "points", codepoints: [0x05B0..0x05BD, 0x05C1, 0x05C2, 0x05C7]),
      "maqaf" => MarkClass.new(name: "maqaf", codepoints: [0x05BE], replacement: " "),
      "vedic-accents" => MarkClass.new(name: "vedic-accents", codepoints: [0x0951, 0x0952]),
      "titla" => MarkClass.new(name: "titla", codepoints: [0x0483, 0x0487, 0x2DE0..0x2DFF]),
      "monotonic" => MarkClass.new(name: "monotonic",
                                   codepoints: [0x0300, 0x0313, 0x0314, 0x0342, 0x0343, 0x0345])
    }.freeze

    # One language's display policy from config/display.yml. +strip+ applies
    # in default mode; +keep+ names classes default mode leaves alone but
    # plain mode strips too; +isolates+ wraps rendered runs in U+2067/U+2069;
    # +spacing+ (P27-2) inserts a separator between grapheme clusters — the
    # Ogham legibility knob (adjacent letters share one continuous stemline
    # and their stroke runs merge unsegmented in a terminal; between two
    # Ogham letters the separator is U+1680 OGHAM SPACE MARK, the script's
    # own stemline-continuing space, so the line stays one stem).
    Policy = Data.define(:language, :strip, :keep, :isolates, :spacing) do
      def initialize(strip: [], keep: [], isolates: false, spacing: false, **rest) = super
    end

    # == Edition-level conventions (P27-1; the `sources:` section)
    #
    # Language policies dress SCRIPTS; these dress EDITIONS: transforms keyed
    # to a source's editorial conventions, executed only by the `reading`
    # mode (the `diplomatic` mode is the byte-honest view of the same marks).
    # Census-first like the mark classes: every rule below names a marker
    # that exists in the shelves' STORED passage bytes (the parsers already
    # resolve most raw Leiden at parse time — supplements/additions/
    # expansions/underdots were censused ×0 in stored text and deliberately
    # have no rules; counts in backlog P27-1).
    #
    #   lacuna    "[…]" — the one gap rendering every Leiden parser emits
    #             (DdbdpParser/CelticLeiden GAP_MARKER; upstream's "[...]",
    #             "//" forms are normalized at parse time, censused ×0
    #             stored). ellipsis → "…"; keep → untouched.
    #   erasures  ⟦…⟧ (EDH damnatio-memoriae, CelticLeiden <del>). An
    #             erasure is content: default KEEP; unwrap drops the
    #             brackets, never the text.
    #   surplus   {…} (CelticLeiden <surplus> — letters carved in error,
    #             printed but excluded from the regularized reading).
    #             Default KEEP — unwrapping would present a misspelling as
    #             fluent text without its marker; unwrap is opt-in.
    #   sigla     SBLGNT's ⸀⸂⸃ apparatus cross-references (censused ×69/
    #             ×30/×30; ⸁ and ⸄–⸇ censused ×0 → not in the set). strip →
    #             removed; keep → untouched.
    EDITION_RULES = {
      "lacuna" => { "ellipsis" => [/\[…\]/, "…"].freeze, "keep" => nil }.freeze,
      "erasures" => { "unwrap" => [/[⟦⟧]/, ""].freeze, "keep" => nil }.freeze,
      "surplus" => { "unwrap" => [/[{}]/, ""].freeze, "keep" => nil }.freeze,
      "sigla" => { "strip" => [/[⸀⸂⸃]/, ""].freeze, "keep" => nil }.freeze
    }.freeze

    # qere_display settings (oshb): which side of a ketiv/qere apparatus
    # token the reading text shows, and the applied-label each announces.
    QERE_SETTINGS = %w[qere ketiv both].freeze
    QERE_LABELS = { "qere" => "qere", "both" => "ketiv+qere" }.freeze

    # Gaiji (P37-3; kanripo). The mandoku parser keeps not-yet-encoded
    # characters as `&KR\d+;` references verbatim in the stored text. In
    # `reading` mode, a source configured `gaiji: placeholder` swaps each such
    # ref for either its RESOLVED glyph (when the KR-Gaiji charlist gives a
    # single real Unicode codepoint — the faithful subset in
    # config/gaiji/<source>.tsv) or the ⬚ placeholder box (U+2B1A) otherwise —
    # never a fake glyph. `gaiji: refs` (and every non-reading mode) keeps the
    # refs verbatim; the diplomatic view is the byte-honest counterpart. cbeta
    # is a documented NON-entry: its `<g>` fallback text is already the stored
    # reading surface (parser resolves it at parse time), so there is nothing
    # to display-transform.
    GAIJI_REF = /&(KR\d+);/
    GAIJI_PLACEHOLDER = "\u{2B1A}" # ⬚ DOTTED SQUARE
    GAIJI_SETTINGS = %w[placeholder refs].freeze

    # The applied-labels edition transforms can emit — the footer separates
    # these ("apparatus simplified: …") from the mark-class strip vocabulary.
    EDITION_LABELS = (EDITION_RULES.keys + QERE_LABELS.values).freeze

    # One source's edition conventions from display.yml `sources:`. +reading+
    # maps rule name → setting; +qere_display+ is the ketiv/qere choice
    # (nil for sources without that apparatus); +gaiji+ is the KR-ref policy
    # (placeholder | refs | nil — P37-3).
    SourcePolicy = Data.define(:slug, :reading, :qere_display, :gaiji) do
      def initialize(slug:, reading: {}, qere_display: nil, gaiji: nil) = super
    end

    # The per-render edition context: the source's conventions plus the
    # passage's stored annotations (the qere word hashes ride there) and the
    # source's gaiji resolution map (P37-3; empty for non-gaiji sources).
    Edition = Data.define(:policy, :annotations, :gaiji_map) do
      def initialize(policy:, annotations:, gaiji_map: {}) = super
    end

    # The applied-label for isolate wrapping (footer vocabulary), and the two
    # isolate characters (RIGHT-TO-LEFT ISOLATE / POP DIRECTIONAL ISOLATE).
    ISOLATES = "rtl isolates"
    RLI = "⁧"
    PDI = "⁩"

    # Grapheme spacing (P27-2): the Ogham block and its own space mark —
    # U+1680 renders as a stemline segment, so spaced letters stay one stem.
    OGHAM_BLOCK = (0x1680..0x169F)
    OGHAM_SPACE = "\u1680"

    DEFAULT_MODE = "default"

    # == East-Asian display width (P35-7) — MEASUREMENT, not policy
    #
    # The terminal draws CJK ideographs, kana, hangul and fullwidth forms two
    # cells wide; every column-aligned surface (concord KWIC, the align label
    # column's text, the distinctive-vocabulary table) must pad by CELLS, not
    # by String#length, or Han lines drift ~2× right of the keyword column.
    # `Display.width` is the ONE seam; `ljust`/`rjust` are its padding
    # companions. There is no --display mode and no footer for it: width is a
    # rendering fact the terminal already enforces, not an editorial choice.
    #
    # Classification is by Unicode East_Asian_Width, transcribed from
    # EastAsianWidth.txt **Unicode 16.0.0** (the plane-2/3 W-default rule below
    # also absorbs the CJK Extension I additions and any Unicode 17 CJK growth):
    #   - W (Wide) and F (Fullwidth) codepoints render TWO cells.
    #   - Every other class — including A (Ambiguous) — renders ONE cell here.
    #     Ambiguous is width-1 by the Unicode narrow default; a terminal that
    #     draws it double (iTerm2's "ambiguous-width" toggle) is the operator's
    #     to switch OFF, documented in docs/display.md §2 but never modelled.
    #   - Codepoints not covered by the table below default NARROW (one cell).
    #
    # Scope is corpus-focused (the Sino wave: lzh Han, ojp kana + man'yōgana):
    # CJK Unified + Extensions A–I, kana and its extensions, hangul, bopomofo,
    # Yi, CJK radicals/strokes/symbols/punctuation, Tangut/Khitan/Nushu, and the
    # fullwidth forms. Wide pictographic emoji (also W by EAW) are out of the
    # ancient-text corpus and deliberately omitted — they would render narrow
    # here; add their ranges if a corpus ever needs them.
    EAST_ASIAN_WIDE = [
      0x1100..0x115F,     # Hangul Jamo (W)
      0x2E80..0x2E99,     # CJK Radicals Supplement (W)
      0x2E9B..0x2EF3,     # CJK Radicals Supplement (W)
      0x2F00..0x2FD5,     # Kangxi Radicals (W)
      0x2FF0..0x2FFF,     # Ideographic Description Characters (W)
      0x3000..0x303E,     # CJK Symbols and Punctuation, incl. U+3000 IDEOGRAPHIC SPACE (W)
      0x3041..0x3096,     # Hiragana (W)
      0x3099..0x30FF,     # combining kana voicing marks + Katakana (W)
      0x3105..0x312F,     # Bopomofo + extensions (W)
      0x3131..0x318E,     # Hangul Compatibility Jamo (W)
      0x3190..0x31E5,     # Kanbun, CJK Strokes (W)
      0x31EF..0x31FF,     # Ideographic symbol + Katakana Phonetic Extensions (W)
      0x3200..0x32FF,     # Enclosed CJK Letters and Months (W)
      0x3300..0x33FF,     # CJK Compatibility (W)
      0x3400..0x4DBF,     # CJK Unified Ideographs Extension A (W)
      0x4E00..0x9FFF,     # CJK Unified Ideographs (W)
      0xA000..0xA48C,     # Yi Syllables (W)
      0xA490..0xA4C6,     # Yi Radicals (W)
      0xA960..0xA97C,     # Hangul Jamo Extended-A (W)
      0xAC00..0xD7A3,     # Hangul Syllables (W)
      0xF900..0xFAFF,     # CJK Compatibility Ideographs (W)
      0xFE10..0xFE19,     # Vertical Forms (W)
      0xFE30..0xFE52,     # CJK Compatibility Forms (W)
      0xFE54..0xFE66,     # Small Form Variants (W)
      0xFE68..0xFE6B,     # Small Form Variants (W)
      0xFF01..0xFF60,     # Fullwidth ASCII variants (F)
      0xFFE0..0xFFE6,     # Fullwidth signs (F)
      0x16FE0..0x16FE4,   # Tangut/Nushu iteration & reading marks (W)
      0x17000..0x18CD5,   # Tangut, Tangut Components, Khitan Small Script (W)
      0x18D00..0x18D08,   # Tangut Supplement (W)
      0x1AFF0..0x1B2FB,   # Kana Extended-B, Kana Supplement/Extended-A, Small Kana, Nushu (W)
      0x20000..0x2FFFD,   # Plane 2 — CJK Ext B–F, I + Compat Supplement (W by Unicode default)
      0x30000..0x3FFFD    # Plane 3 — CJK Ext G, H (W by Unicode default)
    ].freeze

    # Zero-width for measurement: ANSI SGR color sequences (the token-coloring
    # RESET/paint codes) and the bidi isolates (U+2066–2069, RTL wrapping).
    ANSI_SGR = /\e\[[0-9;]*m/
    BIDI_ISOLATES = /[\u{2066}-\u{2069}]/

    class << self
      # Parse config/display.yml → { "hbo" => Policy, ... }. A missing file is
      # no policies (display becomes a pass-through); a malformed one is a
      # named ConfigError — bad display config must never silently strip.
      def load_policies(path)
        return {} unless File.exist?(path)

        data = YAML.safe_load_file(path) || {}
        languages = data.fetch("languages", nil) || {}
        raise ConfigError, "#{path}: `languages:` must be a mapping" unless languages.is_a?(Hash)

        languages.to_h { |language, spec| [validate_language!(language, path), build_policy(language, spec, path)] }
      end

      # Parse config/display.yml `sources:` → { "oshb" => SourcePolicy, … }.
      # Same contract as load_policies: missing file/section = no policies,
      # malformed = named ConfigError (bad config must never silently strip).
      def load_source_policies(path)
        return {} unless File.exist?(path)

        data = YAML.safe_load_file(path) || {}
        sources = data.fetch("sources", nil) || {}
        raise ConfigError, "#{path}: `sources:` must be a mapping" unless sources.is_a?(Hash)

        sources.to_h { |slug, spec| [validate_slug!(slug, path), build_source_policy(slug, spec, path)] }
      end

      # Parse a gaiji resolution map (P37-3): a TSV of `ref-id<TAB>glyph` lines
      # (`#` comments and blanks ignored) → { "KR0001" => "𫠦", … }. This is the
      # curated FAITHFUL subset shipped in config/gaiji/<source>.tsv (census in
      # its header). A missing file is an empty map — resolution degrades to
      # placeholder-only, never an error (the placeholder ships regardless).
      def load_gaiji_map(path)
        return {} unless File.exist?(path)

        map = {}
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          line = line.chomp
          next if line.empty? || line.start_with?("#")

          id, glyph = line.split("\t", 2)
          map[id] = glyph if id && glyph && !glyph.empty?
        end
        map.freeze
      end

      # Register a display mode (the sibling-packet seam). A duplicate name is
      # an Error — modes are added, never silently replaced.
      def register_mode(mode)
        raise Error, "display mode already registered: #{mode.name}" if modes.key?(mode.name)

        modes[mode.name] = mode
      end

      # Resolve a --display MODE name; a miss names the registry.
      def mode(name)
        modes.fetch(name) do
          raise UnknownModeError, "unknown display mode: #{name} (modes: #{mode_names.join(', ')})"
        end
      end

      def mode_names
        modes.keys
      end

      # Render one run of +text+ for the terminal: look up the language's
      # policy (primary subtag, like the fold tables), let the mode transform,
      # then wrap in RTL isolates when both mode and policy say so. No policy,
      # or nothing changed ⇒ applied is empty and the text passes through.
      #
      # +source+/+annotations+/+source_policies+ (P27-1) are the OPTIONAL
      # edition context: when the mode is edition-aware (#render_edition) and
      # the source has conventions configured, the mode receives them; every
      # P27-0 mode and caller is untouched by their absence. Grapheme spacing
      # (P27-2) applies after the mode render when policy and mode allow.
      def render(text, language:, mode:, policies:, source: nil, annotations: nil, source_policies: {},
                 gaiji_map: {})
        policy = policies[Normalize.primary_subtag(language)]
        edition = edition_context(mode, source, annotations, source_policies, gaiji_map)
        return Rendered.new(text: text, applied: []) if text.empty? || (policy.nil? && edition.nil?)

        policy ||= Policy.new(language: language)
        rendered = if edition
                     mode.render_edition(text, language: language, policy: policy, edition: edition)
                   else
                     mode.render(text, language: language, policy: policy)
                   end
        rendered = space_graphemes(rendered) if policy.spacing && mode_allows_spacing?(mode)
        return rendered unless mode.isolates?(policy)

        Rendered.new(text: RLI + rendered.text + PDI, applied: rendered.applied + [ISOLATES],
                     gaiji: rendered.gaiji)
      end

      # Insert a separator between adjacent grapheme clusters (never next to
      # an existing separator): U+1680 between two Ogham-block chars, plain
      # space otherwise. Announced as "spacing" only when something changed.
      def space_graphemes(rendered)
        clusters = rendered.text.grapheme_clusters
        spaced = +""
        clusters.each_with_index do |cluster, i|
          spaced << cluster
          follower = clusters[i + 1]
          next if follower.nil? || separator?(cluster) || separator?(follower)

          spaced << (ogham?(cluster) && ogham?(follower) ? OGHAM_SPACE : " ")
        end
        return rendered if spaced == rendered.text

        Rendered.new(text: spaced, applied: rendered.applied + ["spacing"], gaiji: rendered.gaiji)
      end

      # NO_COLOR (any non-empty value) always wins; NABU_COLOR forces color
      # for captured/piped output (tests, pagers that render ANSI); otherwise
      # color only on a TTY, so piped output stays clean.
      def color?(tty:)
        no_color = ENV.fetch("NO_COLOR", "")
        return false unless no_color.empty?
        return true unless ENV.fetch("NABU_COLOR", "").empty?

        tty
      end

      # Strip the named +classes+ from +text+, grapheme-safe, returning
      # [stripped, applied] where +applied+ names only the classes that
      # actually removed something. NFC-exempt languages (hbo/arc) are edited
      # in place — never normalized (Masoretic mark order, P26-3); everything
      # else round-trips NFD → strip → NFC so precomposed marks are reachable.
      def strip_classes(text, classes, language:)
        exempt = Normalize.nfc_exempt?(language)
        working = exempt ? text : text.unicode_normalize(:nfd)
        applied = []
        classes.each do |name|
          mark_class = MARK_CLASSES.fetch(name)
          stripped = working.gsub(mark_class.regexp, mark_class.replacement)
          applied << name unless stripped == working
          working = stripped
        end
        [exempt ? working : working.unicode_normalize(:nfc), applied]
      end

      # The number of terminal CELLS +text+ draws (P35-7): grapheme clusters
      # summed by East-Asian width, wide (W/F) = 2 and everything else = 1,
      # with ANSI SGR sequences and bidi isolates measured as 0. Column math
      # over displayed text MUST use this, never String#length — a Han cluster
      # is one character but two cells, so char-count padding drifts the column.
      # A cluster is classified by its FIRST codepoint (its base), so combining
      # marks fused onto a base add nothing and never split a grapheme.
      def width(text)
        measurable(text).grapheme_clusters.sum { |cluster| wide_grapheme?(cluster) ? 2 : 1 }
      end

      # ljust/rjust by DISPLAY WIDTH: pad with spaces until +text+ occupies
      # +target+ cells (left- or right-justified). Already ≥ target ⇒ returned
      # untouched (like String#ljust/rjust). For narrow (grc/lat/chu) text these
      # are byte-identical to String#ljust/rjust — width == length there.
      def ljust(text, target)
        pad = target - width(text)
        pad.positive? ? text + (" " * pad) : text
      end

      def rjust(text, target)
        pad = target - width(text)
        pad.positive? ? (" " * pad) + text : text
      end

      # Apply the edition's configured convention rules to +text+, returning
      # [transformed, applied] where +applied+ names only the rules that
      # changed something. Pure codepoint substitution — never a base letter,
      # never reordering (safe on the NFC-exempt languages too).
      def apply_edition_rules(text, edition)
        applied = []
        working = text
        edition.policy.reading.each do |rule, setting|
          pattern, replacement = EDITION_RULES.fetch(rule).fetch(setting)
          next if pattern.nil?

          swapped = working.gsub(pattern, replacement)
          applied << rule unless swapped == working
          working = swapped
        end
        [working, applied]
      end

      # The ketiv/qere token substitution (oshb): the stored text carries the
      # KETIV (written) form; the qere (read) form rides the token's "qere"
      # word hashes in the passage annotations. A cursor walks the tokens in
      # document order — the text was assembled from these very forms, so a
      # sequential index scan is exact and an identical earlier word can
      # never be mis-targeted. "both" renders "ketiv [qere]". Display-time
      # only; without annotations the stored ketiv stands.
      # Resolve/placehold the `&KR\d+;` gaiji refs in +text+ (P37-3), returning
      # [rendered, GaijiTally]. Only fires when the source policy is
      # `gaiji: placeholder`; otherwise the refs stay verbatim and the tally is
      # zero. A ref whose id is in the edition's gaiji_map becomes its real
      # glyph (resolved); every other `&KR…;` ref becomes the ⬚ placeholder
      # (unresolved). Pure codepoint substitution — safe on NFC-exempt text.
      def apply_gaiji(text, edition)
        return [text, GaijiTally.new(resolved: 0, unresolved: 0)] unless edition.policy.gaiji == "placeholder"

        resolved = 0
        unresolved = 0
        out = text.gsub(GAIJI_REF) do
          glyph = edition.gaiji_map[Regexp.last_match(1)]
          if glyph
            resolved += 1
            glyph
          else
            unresolved += 1
            GAIJI_PLACEHOLDER
          end
        end
        [out, GaijiTally.new(resolved: resolved, unresolved: unresolved)]
      end

      def apply_qere(text, edition)
        setting = edition.policy.qere_display
        tokens = edition.annotations.is_a?(Hash) ? edition.annotations["tokens"] : nil
        return [text, []] if setting.nil? || setting == "ketiv" || !tokens.is_a?(Array)

        substitute_qere(text, tokens, setting)
      end

      private

      def substitute_qere(text, tokens, setting)
        out = +""
        cursor = 0
        substituted = false
        tokens.each do |token|
          form = token["form"].to_s
          index = form.empty? ? nil : text.index(form, cursor)
          next if index.nil?

          qere = qere_reading(token)
          if qere.nil?
            out << text[cursor...(index + form.length)]
          else
            out << text[cursor...index]
            out << (setting == "both" ? "#{form} [#{qere}]" : qere)
            substituted = true
          end
          cursor = index + form.length
        end
        out << text[cursor..]
        substituted ? [out.freeze, [QERE_LABELS.fetch(setting)]] : [text, []]
      end

      def qere_reading(token)
        words = token["qere"]
        return nil unless words.is_a?(Array)

        reading = words.filter_map { |word| word["form"] }.join(" ")
        reading.empty? ? nil : reading
      end

      def edition_context(mode, source, annotations, source_policies, gaiji_map = {})
        return nil unless source && mode.respond_to?(:render_edition)

        policy = source_policies[source]
        policy && Edition.new(policy: policy, annotations: annotations, gaiji_map: gaiji_map)
      end

      # Strip the zero-width noise (ANSI SGR + bidi isolates) before measuring.
      def measurable(text)
        text.gsub(ANSI_SGR, "").gsub(BIDI_ISOLATES, "")
      end

      # A grapheme cluster is wide iff its base (first) codepoint is East-Asian
      # W or F. Small frozen range table (EAST_ASIAN_WIDE); a linear scan is
      # ample for the short strings column math measures.
      def wide_grapheme?(cluster)
        codepoint = cluster.ord
        EAST_ASIAN_WIDE.any? { |range| range.cover?(codepoint) }
      end

      def modes
        @modes ||= {}
      end

      # The P27-2 mode-contract extensions default permissively for modes
      # registered before them (the P27-0 seam promises no reshaping).
      def mode_allows_spacing?(mode)
        !mode.respond_to?(:spacing?) || mode.spacing?
      end

      def separator?(cluster)
        cluster.match?(/\A[[:space:]]\z/) # [[:space:]] is Unicode-aware — covers U+1680 too
      end

      def ogham?(cluster)
        OGHAM_BLOCK.cover?(cluster.ord)
      end

      def validate_language!(language, path)
        unless language.to_s.match?(/\A[a-z]{2,3}\z/)
          raise ConfigError, "#{path}: bad language key #{language.inspect} — " \
                             "primary subtags only (e.g. hbo, chu)"
        end
        language
      end

      def build_policy(language, spec, path)
        spec = {} if spec.nil?
        raise ConfigError, "#{path}: #{language}: policy must be a mapping" unless spec.is_a?(Hash)

        unknown = spec.keys - %w[strip keep isolates spacing]
        raise ConfigError, "#{path}: #{language}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

        Policy.new(language: language,
                   strip: validate_classes!(spec["strip"], language, path),
                   keep: validate_classes!(spec["keep"], language, path),
                   isolates: validate_boolean!(spec["isolates"], "isolates", language, path),
                   spacing: validate_boolean!(spec["spacing"], "spacing", language, path))
      end

      def validate_classes!(names, language, path)
        names = Array(names)
        names.each do |name|
          next if MARK_CLASSES.key?(name)

          raise ConfigError, "#{path}: #{language}: unknown mark class #{name.inspect} " \
                             "(classes: #{MARK_CLASSES.keys.join(', ')})"
        end
        names
      end

      def validate_boolean!(value, key, language, path)
        return false if value.nil?
        return value if [true, false].include?(value)

        raise ConfigError, "#{path}: #{language}: #{key} must be true or false, " \
                           "got #{value.inspect}"
      end

      def validate_slug!(slug, path)
        unless slug.to_s.match?(/\A[a-z0-9_-]+\z/)
          raise ConfigError, "#{path}: bad source key #{slug.inspect} — " \
                             "source slugs only (e.g. oshb, papyri-ddbdp)"
        end
        slug
      end

      def build_source_policy(slug, spec, path)
        spec = {} if spec.nil?
        raise ConfigError, "#{path}: #{slug}: source policy must be a mapping" unless spec.is_a?(Hash)

        unknown = spec.keys - %w[reading qere_display gaiji]
        raise ConfigError, "#{path}: #{slug}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

        SourcePolicy.new(slug: slug,
                         reading: validate_rules!(spec["reading"], slug, path),
                         qere_display: validate_qere_display!(spec["qere_display"], slug, path),
                         gaiji: validate_gaiji!(spec["gaiji"], slug, path))
      end

      def validate_gaiji!(value, slug, path)
        return nil if value.nil?
        return value if GAIJI_SETTINGS.include?(value)

        raise ConfigError, "#{path}: #{slug}: gaiji must be one of " \
                           "#{GAIJI_SETTINGS.join(', ')}, got #{value.inspect}"
      end

      def validate_rules!(rules, slug, path)
        rules = {} if rules.nil?
        raise ConfigError, "#{path}: #{slug}: reading must be a mapping" unless rules.is_a?(Hash)

        rules.each do |rule, setting|
          settings = EDITION_RULES.fetch(rule) do
            raise ConfigError, "#{path}: #{slug}: unknown edition rule #{rule.inspect} " \
                               "(rules: #{EDITION_RULES.keys.join(', ')})"
          end
          next if settings.key?(setting)

          raise ConfigError, "#{path}: #{slug}: #{rule} must be one of " \
                             "#{settings.keys.join(', ')}, got #{setting.inspect}"
        end
        rules
      end

      def validate_qere_display!(value, slug, path)
        return nil if value.nil?
        return value if QERE_SETTINGS.include?(value)

        raise ConfigError, "#{path}: #{slug}: qere_display must be one of " \
                           "#{QERE_SETTINGS.join(', ')}, got #{value.inspect}"
      end
    end

    # The built-in mode family: pick a class list from the policy, strip.
    # +classes+ is a selector over the policy — :strip (the default lists),
    # :all (strip + keep, e.g. consonantal Hebrew), :none (the escape hatch) —
    # so no language knowledge is hard-coded here. The P27-2 contract
    # extensions: #colors? gates per-token language coloring (mono/full say
    # no), #spacing? gates grapheme spacing (full says no); modes registered
    # without these methods default permissively (the no-reshaping promise).
    class StripMode
      attr_reader :name, :description

      def initialize(name:, description:, classes:, isolates: true, colors: true, spacing: true)
        @name = name
        @description = description
        @classes = classes
        @isolates = isolates
        @colors = colors
        @spacing = spacing
      end

      def render(text, language:, policy:)
        stripped, applied = Display.strip_classes(text, class_list(policy), language: language)
        Rendered.new(text: stripped, applied: applied)
      end

      def isolates?(policy)
        @isolates && policy.isolates
      end

      def colors? = @colors

      def spacing? = @spacing

      private

      def class_list(policy)
        case @classes
        when :strip then policy.strip
        when :all then policy.strip + policy.keep
        else []
        end
      end
    end

    # `--display translit` (P27-2): render passage text through the
    # language's registered transcoder — san Devanagari→IAST (Nabu::Deva),
    # hbo/arc→SBL-style romanization (Nabu::Hebr), chu/orv/bul Cyrillic→
    # scholarly Latin (Nabu::Cyrl — the display direction of the P27-2
    # cross-script fold table; Latin-diplomatic text passes through
    # byte-identical, the render layer never rewrites the source's own
    # surface). A language with no transcoder passes through with nothing
    # applied — never a guess. Output is romanized/LTR, so no RTL isolates.
    #
    # Ogham (censused verdict): the corpus's transliteration is a parallel
    # SIBLING DOCUMENT (…-translit, line-aligned by urn suffix), not a
    # transcode — `show URN --parallel` inlines it today. Wiring that
    # catalog lookup into this render seam would cross the render-only
    # boundary (a mode sees text + language, never the store), so the
    # sibling inline is journaled as a follow-up, not hacked in here.
    class TranslitMode
      TRANSCODERS = {
        "san" => Deva.method(:to_iast),
        "hbo" => Hebr.method(:to_sbl),
        "arc" => Hebr.method(:to_sbl),
        "chu" => Cyrl.method(:to_translit),
        "orv" => Cyrl.method(:to_translit),
        "bul" => Cyrl.method(:to_translit)
      }.freeze

      def name = "translit"

      def description = "romanized rendering (san Deva→IAST, hbo/arc→SBL, chu/orv/bul→scholarly Latin)"

      def render(text, language:, policy:) # rubocop:disable Lint/UnusedMethodArgument
        transcoder = TRANSCODERS[Normalize.primary_subtag(language)]
        out = transcoder ? transcoder.call(text) : text
        Rendered.new(text: out, applied: out == text ? [] : ["translit"])
      end

      def isolates?(_policy) = false

      def colors? = true

      def spacing? = true
    end

    register_mode(StripMode.new(
                    name: DEFAULT_MODE,
                    description: "config-driven per-language stripping (display.yml strip lists)",
                    classes: :strip
                  ))
    register_mode(StripMode.new(
                    name: "full",
                    description: "no transforms — every stored byte, the escape hatch",
                    classes: :none, isolates: false, colors: false, spacing: false
                  ))
    register_mode(StripMode.new(
                    name: "plain",
                    description: "strip every class the language policy defines (e.g. consonantal Hebrew)",
                    classes: :all
                  ))

    # The edition-aware mode (P27-1): fluent reading. Composes, in order:
    # ketiv/qere substitution (on the pristine stored bytes, so the token
    # forms match exactly), the source's configured edition rules, then the
    # language policy's default strip lists — so Hebrew reading = qere +
    # cantillation stripped TOGETHER, and a shelf with no source entry
    # degrades to exactly the default mode's behavior. Without edition
    # context (callers that know no source), #render is the language path.
    class ReadingMode
      def name = "reading"

      def description = "fluent reading: default language strips + per-source edition rules (sources: in display.yml)"

      def render(text, language:, policy:)
        stripped, applied = Display.strip_classes(text, policy.strip, language: language)
        Rendered.new(text: stripped, applied: applied)
      end

      def render_edition(text, language:, policy:, edition:)
        working, gaiji = Display.apply_gaiji(text, edition)
        working, applied = Display.apply_qere(working, edition)
        working, rule_applied = Display.apply_edition_rules(working, edition)
        stripped, strip_applied = Display.strip_classes(working, policy.strip, language: language)
        Rendered.new(text: stripped, applied: applied + rule_applied + strip_applied, gaiji: gaiji)
      end

      def isolates?(policy) = policy.isolates
    end

    register_mode(ReadingMode.new)

    # `diplomatic` — the byte-honest half of the reading/diplomatic pair:
    # the edition's marks exactly as stored, no transforms, no isolates.
    # Today it renders identically to `full`; it is registered under the
    # editorial-convention name so "--display diplomatic shows the edition
    # marks" is the reading-mode footer's natural counterpart.
    register_mode(StripMode.new(
                    name: "diplomatic",
                    description: "the edition's marks as stored — byte-honest (reading's counterpart)",
                    classes: :none, isolates: false
                  ))
    register_mode(StripMode.new(
                    name: "mono",
                    description: "default stripping without per-token language coloring",
                    classes: :strip, colors: false
                  ))
    register_mode(TranslitMode.new)

    # Per-token language coloring (P27-2): in code-switching texts (corph
    # sga/lat glosses, OSHB's Aramaic verses) tokens tagged — in the stored
    # P7-5 "tokens" annotation — with a language OTHER than the passage's
    # own are wrapped in an ANSI color, one stable color per language
    # (first-seen order). Base-language and untagged tokens stay uncolored:
    # color only what is honestly tagged. Token forms are located
    # sequentially in the display text; a form that cannot be found paints
    # nothing — never a fabricated span. NO_COLOR/mono/full gate this at
    # the CLI via Display.color? and mode#colors?.
    module TokenColors
      # name → ANSI SGR code, in assignment order.
      PALETTE = [["cyan", 36], ["yellow", 33], ["magenta", 35],
                 ["green", 32], ["red", 31], ["blue", 34]].freeze
      RESET = "\e[0m"

      module_function

      # → [painted text, { language => color name } legend]. +tokens+ is the
      # stored tokens annotation (array of hashes); +language+ the passage
      # language (its primary subtag is the uncolored baseline).
      def paint(text, tokens:, language:)
        base = Normalize.primary_subtag(language)
        foreign = tokens.select { |token| token.is_a?(Hash) && token["lang"] && token["lang"] != base }
        return [text, {}] if foreign.empty?

        colors = assign_colors(foreign)
        painted = +""
        rest = text
        used = {}
        foreign.each do |token|
          form = token["form"].to_s
          index = form.empty? ? nil : rest.index(form)
          next if index.nil?

          name, code = colors.fetch(token["lang"])
          used[token["lang"]] = name
          painted << rest[0, index] << "\e[#{code}m" << form << RESET
          rest = rest[(index + form.length)..]
        end
        [painted + rest, used]
      end

      def assign_colors(foreign)
        foreign.map { |token| token["lang"] }.uniq
               .each_with_index.to_h { |lang, i| [lang, PALETTE[i % PALETTE.size]] }
      end
      private_class_method :assign_colors
    end
  end
end
