# frozen_string_literal: true

require "date"

module Nabu
  module Ops
    # `rake boards:check` — the GitHub watch-list staleness guard. Replies
    # on a GitHub thread we posted to reach no other inbound channel, so
    # the local boards keep a "## GH watch list" section whose rows are
    # re-checked at every gate:
    #
    #   - <id> · <owner/repo>#<num> · checked <YYYY-MM-DD> · <state>
    #
    # A row whose checked date is more than MAX_AGE_DAYS old means the
    # sweep lapsed and a reply may be sitting unseen — the check trips and
    # names the rows. Only rows still being watched count: a state that
    # OPENS with CLOSED or DORMANT is retired (a state that merely mentions
    # dormancy further on is still live), and anything else — OPEN or a
    # prose state — is watched. A row-shaped line (a bullet naming an
    # owner/repo#num) with no readable checked date trips too: an
    # undatable row can never be judged fresh.
    #
    # Like BoardCheck this is a LOCAL instrument over gitignored files: no
    # boards dir, or no board carrying the section (any public clone, a
    # lane worktree), is an announced skip. Date arithmetic only — never
    # the network.
    class WatchListCheck
      MAX_AGE_DAYS = 7
      SECTION = /^##\s+GH watch list\b/
      SECTION_END = /^\#{1,2}\s/
      ROW = %r{^\s*[-*]\s+(?<id>[^·]+?)\s*·\s*(?<thread>[\w.-]+/[\w.-]+#\d+[^·]*?)\s*(?:·\s*(?<rest>.*))?$}
      CHECKED = /\bchecked\s+(?<date>\d{4}-\d{2}-\d{2})\b\s*(?:·\s*)?(?<state>.*)$/
      RETIRED = /\A(?:CLOSED|DORMANT)\b/i

      Report = Data.define(:skipped, :rows, :findings) do
        def clean? = findings.empty?
      end

      def initialize(boards_dir:, today: Date.today, max_age_days: MAX_AGE_DAYS)
        @dir = boards_dir
        @today = today
        @max_age = max_age_days
      end

      def run
        sections = File.directory?(@dir) ? watch_sections : []
        return Report.new(skipped: true, rows: 0, findings: []) if sections.empty?

        rows = sections.flat_map { |rel, lines| lines.filter_map { |line| parse(rel, line) } }
        Report.new(skipped: false, rows: rows.size, findings: rows.filter_map { |row| judge(row) })
      end

      Row = Data.define(:file, :id, :thread, :checked, :state)
      private_constant :Row

      private

      # [[rel path, section lines]] for every top-level board file that
      # carries the section header.
      def watch_sections
        Dir[File.join(@dir, "*.md")].filter_map do |path|
          lines = section_lines(File.readlines(path, encoding: Encoding::UTF_8, chomp: true))
          [path.delete_prefix("#{@dir}/"), lines] if lines
        end
      end

      def section_lines(lines)
        start = lines.index { |line| line.match?(SECTION) }
        return nil unless start

        body = lines[(start + 1)..]
        stop = body.index { |line| line.match?(SECTION_END) } || body.size
        body[0...stop]
      end

      def parse(file, line)
        match = line.match(ROW)
        return nil unless match

        checked = match[:rest].to_s.match(CHECKED)
        Row.new(file: file, id: match[:id], thread: match[:thread],
                checked: checked && safe_date(checked[:date]), state: checked ? checked[:state].strip : "")
      end

      def safe_date(text)
        Date.iso8601(text)
      rescue Date::Error
        nil
      end

      def judge(row)
        label = "#{row.file}: #{row.id} · #{row.thread}"
        return "#{label} — no readable checked date" unless row.checked
        return nil if row.state.match?(RETIRED)

        age = (@today - row.checked).to_i
        return nil if age <= @max_age

        "#{label} — checked #{row.checked.iso8601}, #{age} days ago (limit #{@max_age}); re-sweep the thread"
      end
    end
  end
end
