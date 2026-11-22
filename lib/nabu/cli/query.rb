# frozen_string_literal: true

# Nabu::CLI — corpus query commands: search, concord, show, note, vocab.
# Carved out of lib/nabu/cli.rb, the registry that loads it; the per-command
# partials under cli/query/ are loaded below.
module Nabu
  class CLI < Thor
    # RTL snippet highlight = SGR reverse video (P42-r4, strike 4 — the
    # matrix ruling on the owner's iTerm2). Every CHARACTER-based highlight
    # is at the mercy of the renderer's bidi treatment, and four attempts
    # measured four failure modes; a cell ATTRIBUTE rides the glyph wherever
    # reordering moves it and cannot be broken by any bidi algorithm.
    RTL_HIGHLIGHT_ON = "\e[7m"

    RTL_HIGHLIGHT_OFF = "\e[27m"

    no_commands do
      # Render a SNIPPET — StoredSnippet output with the match in [brackets] —
      # for the terminal (P42-r4, four strikes deep). Square brackets inside
      # RTL text are unrenderable-portably: they are a bidi-mirrored pair,
      # and each character-based fix failed a different way on the owner's
      # iTerm2 (mirrorless reversal showed ]word[; brackets cut OUT of the
      # isolate were swept into the reversed segment anyway; the symmetric ‖
      # detached at passage-edge matches; RLM gluing was ignored — invisible
      # bidi controls do not extend that renderer's runs, though a VISIBLE
      # strong-R paseq does, matrix line 8). The ruling fix highlights with
      # a cell ATTRIBUTE instead of characters: SGR reverse video rides the
      # glyph wherever reordering moves it and no bidi algorithm can touch
      # it (matrix line 9 on the owner's screen). Gated by color_output?
      # (mode + NO_COLOR/NABU_COLOR/tty): piped or colorless output keeps
      # the logical [brackets] — no renderer, no bidi, and the documented
      # grep/MCP contract stays byte-identical. ANSI escapes are ASCII —
      # untouched by mark strips and NFC round-trips (the painted-tokens
      # precedent). Only PAIRED brackets convert (a stored lone Leiden
      # bracket stays literal); a stored [...] lacuna pair colors like a
      # match — the same ambiguity the bracket convention always had.
      def display_snippet(text, language)
        unless Nabu::Display.isolates?(language: language.to_s, mode: display_mode,
                                       policies: display_policies) && color_output?
          return display_text(text, language)
        end

        marked = text.to_s.gsub(/\[([^\[\]]*)\]/) { "#{RTL_HIGHLIGHT_ON}#{Regexp.last_match(1)}#{RTL_HIGHLIGHT_OFF}" }
        display_text(marked, language)
      end

      # Per-token language coloring (P27-2): the single-passage show view —
      # the one render where the stored P7-5 tokens annotation is at hand —
      # colorizes tokens tagged with a language OTHER than the passage's own
      # (corph's Latin glosses in Old Irish, OSHB's Aramaic verses). Gated
      # three ways: the mode's #colors? (mono/full say no), NO_COLOR /
      # NABU_COLOR / tty (Display.color?), and the honest-tagging rule
      # (untagged and base-language tokens stay uncolored). Painting wraps
      # PRISTINE token forms before the display transform — ANSI escapes are
      # ASCII, untouched by mark-class strips and NFC round-trips.
      def painted_passage_text(passage)
        return passage.text unless color_output?

        tokens = passage.annotations["tokens"]
        return passage.text unless tokens.is_a?(Array)

        painted, legend = Nabu::Display::TokenColors.paint(passage.text, tokens: tokens,
                                                                         language: passage.language)
        return passage.text if legend.empty?

        display_applied << "token colors: #{legend.map { |lang, color| "#{lang}=#{color}" }.join(' ')}"
        painted
      end

      def color_output?
        mode = display_mode
        (!mode.respond_to?(:colors?) || mode.colors?) && Nabu::Display.color?(tty: $stdout.tty?)
      end
    end
  end
end

require_relative "query/search"
require_relative "query/concord"
require_relative "query/show"
require_relative "query/note"
require_relative "query/vocab"
