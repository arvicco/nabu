# frozen_string_literal: true

module Nabu
  module Ops
    # The extraction half of `rake docs:verify` (lib/nabu/ops/docs_verify.rb):
    # pulls the runnable commands and their documented output out of a
    # walkthrough page's markdown, so the verifier executes what the page
    # actually teaches rather than a remembered copy of it.
    #
    # Shapes recognised (each one present in the real pages):
    #
    # - a fenced shell block (no language, bash, sh, shell, console):
    #   - TRANSCRIPT form when any line starts with "$ " — each "$ " line
    #     is a command and the lines after it, up to the next "$ " line,
    #     are its documented output;
    #   - PLAIN form otherwise — every non-blank, non-"#" line is a
    #     command, a trailing backslash joins the next line, and an
    #     unquoted " # " starts the line's explanatory comment;
    # - any other fenced block (json, python…) is CONTENT: it carries a
    #   body and no commands;
    # - inline backtick spans in prose that begin with "bin/nabu " are
    #   commands too (spans broken across source lines are joined).
    #
    # Extraction can be scoped to named headings (`sections:`): a section
    # runs from its heading to the next heading of the same or higher
    # level, so ### subsections ride inside their ## parent.
    class DocCommands
      SHELL_LANGS = ["", "bash", "sh", "shell", "console"].freeze
      FENCE = /\A\s*```\s*([\w-]*)\s*\z/
      HEADING = /\A(#+)\s+(.*?)\s*\z/
      INLINE = /`([^`]+)`/m
      INLINE_PREFIX = "bin/nabu "

      Command = Data.define(:text, :line, :comment, :output, :fenced)
      Block = Data.define(:line, :lang, :body, :commands)

      # One parsed page: its fenced blocks, its inline bin/nabu spans, and a
      # whitespace-squeezed copy of the full text for claim-quote lookups.
      Page = Data.define(:path, :blocks, :inline_commands, :normalized) do
        def fenced_commands = blocks.flat_map(&:commands)
        def commands = fenced_commands + inline_commands

        # True when +quote+ (whitespace-insensitive) appears in the page.
        def quotes?(quote) = normalized.include?(DocCommands.key(quote))
      end

      def self.key(text) = text.to_s.gsub(/\s+/, " ").strip

      def self.parse(text, path:, sections: nil)
        new(text, path: path, sections: sections).page
      end

      def initialize(text, path:, sections: nil)
        @lines = text.lines.map(&:chomp)
        @path = path
        @sections = sections
        @text = text
      end

      def page
        scoped = scope_mask
        blocks = []
        prose = []
        index = 0
        while index < @lines.size
          match = FENCE.match(@lines[index])
          if match && scoped[index]
            close = ((index + 1)...@lines.size).find { |i| @lines[i].strip == "```" } || @lines.size
            blocks << block(index, match[1], close)
            (index..close).each { |i| prose[i] = "" }
            index = close + 1
          else
            prose[index] = scoped[index] ? @lines[index] : ""
            index += 1
          end
        end
        Page.new(path: @path, blocks: blocks, inline_commands: inline(prose), normalized: self.class.key(@text))
      end

      private

      # Per-line flag: inside a requested section (everything when unscoped).
      def scope_mask
        return Array.new(@lines.size, true) if @sections.nil?

        wanted = @sections.map { |s| self.class.key(s) }
        level = nil
        in_fence = false
        @lines.map do |line|
          in_fence = !in_fence if FENCE.match?(line)
          heading = !in_fence && HEADING.match(line)
          if heading
            depth = heading[1].size
            if wanted.include?(self.class.key(heading[2]))
              level = depth
            elsif level && depth <= level
              level = nil
            end
          end
          !level.nil?
        end
      end

      def block(open, lang, close)
        body_lines = @lines[(open + 1)...close]
        first = open + 2 # 1-based line of the first body line
        commands = SHELL_LANGS.include?(lang) ? shell_commands(body_lines, first) : []
        Block.new(line: open + 1, lang: lang, body: body_lines.join("\n"), commands: commands)
      end

      def shell_commands(body, first)
        if body.any? { |l| l.start_with?("$ ") }
          transcript(body, first)
        else
          plain(body, first)
        end
      end

      def transcript(body, first)
        commands = []
        body.each_with_index do |line, offset|
          if line.start_with?("$ ")
            commands << { text: line.delete_prefix("$ ").strip, line: first + offset, output: [] }
          elsif commands.any?
            commands.last[:output] << line
          end
        end
        commands.map do |c|
          Command.new(text: c[:text], line: c[:line], comment: nil, output: trim(c[:output]), fenced: true)
        end
      end

      def trim(output)
        output = output.dup
        output.pop while output.any? && output.last.strip.empty?
        output
      end

      def plain(body, first)
        commands = []
        pending = nil
        body.each_with_index do |raw, offset|
          line = raw.rstrip
          next if pending.nil? && (line.strip.empty? || line.lstrip.start_with?("#"))

          pending ||= { text: +"", line: first + offset }
          if line.end_with?("\\")
            pending[:text] << line.delete_suffix("\\") << " "
            next
          end
          pending[:text] << line
          commands << finish(pending)
          pending = nil
        end
        commands << finish(pending) if pending
        commands
      end

      def finish(pending)
        text, comment = split_comment(pending[:text])
        Command.new(text: self.class.key(text), line: pending[:line], comment: comment, output: [], fenced: true)
      end

      # An unquoted '#' preceded by whitespace starts the explanatory comment.
      def split_comment(line)
        quote = nil
        line.each_char.with_index do |char, i|
          if quote
            quote = nil if char == quote
          elsif ["'", '"'].include?(char)
            quote = char
          elsif char == "#" && i.positive? && line[i - 1].match?(/\s/)
            return [line[0...i], line[(i + 1)..].strip]
          end
        end
        [line, nil]
      end

      def inline(prose)
        joined = prose.join("\n")
        joined.to_enum(:scan, INLINE).filter_map do
          match = Regexp.last_match
          text = self.class.key(match[1])
          next unless text.start_with?(INLINE_PREFIX)

          line = joined[0...match.begin(0)].count("\n") + 1
          Command.new(text: text, line: line, comment: nil, output: [], fenced: false)
        end
      end
    end
  end
end
