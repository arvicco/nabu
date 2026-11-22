# frozen_string_literal: true

require_relative "board_check"

module Nabu
  module Ops
    # `rake boards:check` — the incident-register status probe. The local
    # boards keep an incident register: a LOG of `## <sigil>I-<n> · <title>`
    # rows (the register sigil U+2116, never carried literally in tracked
    # files) whose bracketed suffix (`[<date> · <STATUS …>]`) records where
    # the incident stands. Slates census it for open incidents, so a row
    # whose suffix carries no recognizable status token is unreadable to
    # that census — an open incident could hide behind a bare date. Every
    # row must name one of STATUSES (whole uppercase words) in the LAST
    # bracketed group on its header line; a status word in the title does
    # not count. A row without one fails, named by its number.
    #
    # Like the other board probes this is a LOCAL instrument over a
    # gitignored file: no register (any public clone, a lane worktree) is
    # an announced skip. A present register with no rows at all fails.
    class IncidentRegisterCheck
      FILE = "incident-register.md"
      STATUSES = %w[OPEN CLOSED FIX-STAGED MITIGATED].freeze
      SIGIL = BoardCheck::SIGIL
      ROW = /^##\s+#{SIGIL}I-(\d+)\s+·(.*)$/
      SUFFIX = /\[([^\[\]]*)\]\s*\z/
      TOKEN = /(?<![\w-])(?:#{STATUSES.map { |s| Regexp.escape(s) }.join('|')})(?![\w-])/

      Report = Data.define(:skipped, :rows, :findings) do
        def clean? = findings.empty?
      end

      def initialize(register_path:)
        @path = register_path
      end

      def run
        return Report.new(skipped: true, rows: 0, findings: []) unless File.file?(@path)

        rows = File.read(@path, encoding: Encoding::UTF_8).scan(ROW)
        name = File.basename(@path)
        empty = ["#{name}: no `## #{SIGIL}I-n ·` row found"]
        return Report.new(skipped: false, rows: 0, findings: empty) if rows.empty?

        findings = rows.filter_map { |number, rest| judge(name, number, rest.rstrip) }
        Report.new(skipped: false, rows: rows.size, findings: findings)
      end

      private

      def judge(name, number, rest)
        suffix = rest[SUFFIX, 1]
        return "#{name}: #{SIGIL}I-#{number} has no bracketed status suffix — #{wanted}" unless suffix
        return if suffix.match?(TOKEN)

        "#{name}: #{SIGIL}I-#{number} suffix [#{suffix}] carries no status token — #{wanted}"
      end

      def wanted = "add one of #{STATUSES.join(', ')}"
    end
  end
end
