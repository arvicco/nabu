# frozen_string_literal: true

require_relative "board_check"

module Nabu
  module Ops
    # `rake boards:check` — the decision-register hygiene probe. The
    # register's own format rule (owner, 2026-08-10): RULED items are
    # REMOVED — history lives in git, the plan docs, and the rulings they
    # produced; the file holds ONLY items still waiting on the owner. The
    # habitual failure mode (corrected eight times by 2026-11-23) is a
    # ruled row left parked with a resolution banner annotated into its
    # header. This probe fails any `## <sigil>R-n ·` header carrying an
    # unambiguous resolution banner (whole uppercase words): RULED,
    # RESOLVED, EXECUTED, or ROW CLOSED. DELAYED / DEFERRED / TAKEN
    # (partial, re-opening) rows are open waits and pass.
    #
    # A LOCAL instrument over a gitignored file: no register (public
    # clones, lane worktrees) is an announced skip; an empty register —
    # zero rows — is a legitimate state here (every decision ruled and
    # removed), unlike the incident log.
    class DecisionRegisterCheck
      FILE = "decision-register.md"
      BANNERS = ["ROW CLOSED", "RULED", "RESOLVED", "EXECUTED"].freeze
      SIGIL = BoardCheck::SIGIL
      ROW = /^##\s+#{SIGIL}R-(\d+)\s+·(.*)$/
      BANNER = /(?<![\w-])(?:#{BANNERS.map { |b| Regexp.escape(b) }.join('|')})(?![\w-])/

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
        findings = rows.filter_map do |number, rest|
          next unless rest.match?(BANNER)

          "#{name}: #{SIGIL}R-#{number} header carries a resolution banner — " \
            "ruled items are REMOVED (carrier first, then delete the row)"
        end
        Report.new(skipped: false, rows: rows.size, findings: findings)
      end
    end
  end
end
