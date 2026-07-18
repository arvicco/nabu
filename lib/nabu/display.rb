# frozen_string_literal: true

require "yaml"
require_relative "errors"
require_relative "normalize"

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
    Rendered = Data.define(:text, :applied)

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
    # plain mode strips too; +isolates+ wraps rendered runs in U+2067/U+2069.
    Policy = Data.define(:language, :strip, :keep, :isolates) do
      def initialize(strip: [], keep: [], isolates: false, **rest) = super
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

    # The applied-labels edition transforms can emit — the footer separates
    # these ("apparatus simplified: …") from the mark-class strip vocabulary.
    EDITION_LABELS = (EDITION_RULES.keys + QERE_LABELS.values).freeze

    # One source's edition conventions from display.yml `sources:`. +reading+
    # maps rule name → setting; +qere_display+ is the ketiv/qere choice
    # (nil for sources without that apparatus).
    SourcePolicy = Data.define(:slug, :reading, :qere_display) do
      def initialize(slug:, reading: {}, qere_display: nil) = super
    end

    # The per-render edition context: the source's conventions plus the
    # passage's stored annotations (the qere word hashes ride there).
    Edition = Data.define(:policy, :annotations)

    # The applied-label for isolate wrapping (footer vocabulary), and the two
    # isolate characters (RIGHT-TO-LEFT ISOLATE / POP DIRECTIONAL ISOLATE).
    ISOLATES = "rtl isolates"
    RLI = "⁧"
    PDI = "⁩"

    DEFAULT_MODE = "default"

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
      # P27-0 mode and caller is untouched by their absence.
      def render(text, language:, mode:, policies:, source: nil, annotations: nil, source_policies: {})
        policy = policies[Normalize.primary_subtag(language)]
        edition = edition_context(mode, source, annotations, source_policies)
        return Rendered.new(text: text, applied: []) if text.empty? || (policy.nil? && edition.nil?)

        policy ||= Policy.new(language: language)
        rendered = if edition
                     mode.render_edition(text, language: language, policy: policy, edition: edition)
                   else
                     mode.render(text, language: language, policy: policy)
                   end
        return rendered unless mode.isolates?(policy)

        Rendered.new(text: RLI + rendered.text + PDI, applied: rendered.applied + [ISOLATES])
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

      # Character count minus the isolate characters — the width the terminal
      # actually draws. Column math over displayed text must use this, never
      # String#length, so isolate wrapping cannot shift a padded column.
      def visible_length(text)
        text.length - text.count(RLI + PDI)
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

      def edition_context(mode, source, annotations, source_policies)
        return nil unless source && mode.respond_to?(:render_edition)

        policy = source_policies[source]
        policy && Edition.new(policy: policy, annotations: annotations)
      end

      def modes
        @modes ||= {}
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

        unknown = spec.keys - %w[strip keep isolates]
        raise ConfigError, "#{path}: #{language}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

        Policy.new(language: language,
                   strip: validate_classes!(spec["strip"], language, path),
                   keep: validate_classes!(spec["keep"], language, path),
                   isolates: validate_isolates!(spec["isolates"], language, path))
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

      def validate_isolates!(value, language, path)
        return false if value.nil?
        return value if [true, false].include?(value)

        raise ConfigError, "#{path}: #{language}: isolates must be true or false, " \
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

        unknown = spec.keys - %w[reading qere_display]
        raise ConfigError, "#{path}: #{slug}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

        SourcePolicy.new(slug: slug,
                         reading: validate_rules!(spec["reading"], slug, path),
                         qere_display: validate_qere_display!(spec["qere_display"], slug, path))
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
    # so no language knowledge is hard-coded here.
    class StripMode
      attr_reader :name, :description

      def initialize(name:, description:, classes:, isolates: true)
        @name = name
        @description = description
        @classes = classes
        @isolates = isolates
      end

      def render(text, language:, policy:)
        stripped, applied = Display.strip_classes(text, class_list(policy), language: language)
        Rendered.new(text: stripped, applied: applied)
      end

      def isolates?(policy)
        @isolates && policy.isolates
      end

      private

      def class_list(policy)
        case @classes
        when :strip then policy.strip
        when :all then policy.strip + policy.keep
        else []
        end
      end
    end

    register_mode(StripMode.new(
                    name: DEFAULT_MODE,
                    description: "config-driven per-language stripping (display.yml strip lists)",
                    classes: :strip
                  ))
    register_mode(StripMode.new(
                    name: "full",
                    description: "no transforms — every stored byte, the escape hatch",
                    classes: :none, isolates: false
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
        working, applied = Display.apply_qere(text, edition)
        working, rule_applied = Display.apply_edition_rules(working, edition)
        stripped, strip_applied = Display.strip_classes(working, policy.strip, language: language)
        Rendered.new(text: stripped, applied: applied + rule_applied + strip_applied)
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
  end
end
