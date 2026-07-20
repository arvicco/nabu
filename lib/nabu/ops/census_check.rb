# frozen_string_literal: true

module Nabu
  module Ops
    # The P35-6 gate-check rider (`rake census:check`, dev-loop §6b rule 3):
    # every era-bound literal in query/render/fetch code carries its
    # justification — a `# census: <number>, <YYYY-MM-DD>[, <basis>]` line
    # recording what was measured against the live corpus and when, or a
    # `# const: <reason>` line naming why the value is a true constant that
    # no corpus growth can falsify. Future invalidation is then a greppable
    # review question (re-diff the recorded numbers at each phase gate),
    # not an archaeology dig.
    #
    # == The tolerance rule (the honest boundary)
    #
    # PRESENCE only, in the comment block immediately above the assignment.
    # The scan never judges values, dates, or wording — staleness is the
    # gate reviewer's question; absence is the machine's. Two shapes encode
    # a census claim and are scanned: a bare numeric literal and a
    # hand-enumerated %w list. Strings, expressions, and derived constants
    # are not census claims; DEFAULT_* knobs are exempt (conventions §10 —
    # a user-visible default is a UX choice, not a corpus measurement).
    class CensusCheck
      Finding = Data.define(:path, :line, :constant, :message)

      # The region where era-bound literals live: query surfaces, the MCP
      # boundary, and the fetch pipeline.
      DEFAULT_GLOBS = ["lib/nabu/query/*.rb", "lib/nabu/mcp/*.rb", "lib/nabu/*_fetch.rb"].freeze

      MARKER = /#\s*(census|const):/
      # A constant-assignment line (any RHS) — recognized so one marker can
      # stamp a contiguous sibling run (e.g. the four JSON-RPC codes).
      CONSTANT_LINE = /\A\s*[A-Z][A-Z0-9_]*\s*=/
      # A SCREAMING_CASE assignment whose RHS is a bare numeric literal
      # (optionally with a trailing comment) or opens a %w enumeration.
      ASSIGNMENT = /\A\s*([A-Z][A-Z0-9_]*)\s*=\s*(?:-?\d[\d_]*(?:\.\d+)?\s*(?:#.*)?\z|%w\[)/

      def initialize(root:, globs: DEFAULT_GLOBS)
        @root = root
        @globs = globs
      end

      # Every unstamped era-bound literal, path order. Empty = green.
      def findings
        @globs.flat_map { |glob| Dir.glob(File.join(@root, glob)).sort }
              .flat_map { |file| scan(file) }
      end

      private

      def scan(file)
        lines = File.readlines(file)
        relative = file.delete_prefix("#{@root}/")
        lines.each_with_index.filter_map do |line, index|
          match = ASSIGNMENT.match(line) or next
          constant = match[1]
          next if constant.start_with?("DEFAULT_")
          next if stamped?(lines, index)

          Finding.new(path: relative, line: index + 1, constant: constant,
                      message: "era-bound literal without a # census:/# const: marker " \
                               "in the comment block above")
        end
      end

      # The contiguous run of comment/assignment lines immediately above
      # +index+ holds a marker. A blank (or any other) line ends the run, so
      # a marker can cover a tight group of siblings but never leaks across
      # a gap to an unrelated constant.
      def stamped?(lines, index)
        (index - 1).downto(0) do |cursor|
          line = lines[cursor]
          comment = line.match?(/\A\s*#/)
          return true if comment && MARKER.match?(line)
          return false unless comment || CONSTANT_LINE.match?(line)
        end
        false
      end
    end
  end
end
