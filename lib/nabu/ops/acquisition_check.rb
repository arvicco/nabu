# frozen_string_literal: true

# The full entrypoint, not a partial tree: the rail-freshness probe reads
# the ledger through Store, whose require graph (indexer, timeline
# builders, adapters) only loads in nabu.rb's order.
require_relative "../../nabu"

module Nabu
  module Ops
    # The acquisition segment's half of `rake boards:check` (the P169–P171
    # rail-slice omission class: three slates running forgot the rail
    # because nothing machine-checked the duty). Two probes, both LOCAL
    # (boards and the ledger are instance state — a public clone or a lane
    # worktree skips cleanly):
    #
    # 1. SEGMENT PRESENCE — the CURRENT phase plan doc (the highest
    #    .docs/p<N>-plan.md outside old-phases) must carry its alternating
    #    segment (odd N = acquisition, even N = outreach) as a named
    #    section/mention, or an explicit carries-none justification
    #    ("carries no acquisition …" / "carries no outreach …"). A
    #    justified empty is honest; a silent empty flags.
    #
    # 2. RAIL FRESHNESS — every paced-crawl source declaring a per-phase
    #    schedule (found by its `cadence: :per_phase` declaration in
    #    lib/nabu/adapters — the declarations are the roster, never a
    #    remembered list) must have a sync run in the ledger NEWER than
    #    the previous phase's merge date (the second-newest "merged
    #    YYYY-MM-DD" in the phase register): a source quiet across a whole
    #    phase cycle owes slices and flags.
    class AcquisitionCheck
      PLAN = /\Ap(\d+)-plan\.md\z/
      MERGED = /merged (\d{4}-\d{2}-\d{2})/
      PER_PHASE = /cadence:\s*:per_phase/
      JUSTIFIED = { odd: /carries no acquisition/i, even: /carries no outreach/i }.freeze
      SEGMENT = { odd: /acquisition segment/i, even: /outreach segment/i }.freeze

      Report = Data.define(:skipped, :findings) do
        def clean? = findings.empty?
      end

      def initialize(boards_dir:, adapters_dir:, ledger_path:)
        @boards_dir = boards_dir
        @adapters_dir = adapters_dir
        @ledger_path = ledger_path
      end

      def run
        return Report.new(skipped: true, findings: []) unless File.directory?(@boards_dir)

        Report.new(skipped: false, findings: segment_findings + rail_findings)
      end

      private

      def segment_findings
        name, number = current_plan
        return [] unless name

        parity = number.odd? ? :odd : :even
        text = File.read(File.join(@boards_dir, name), encoding: Encoding::UTF_8)
        return [] if text.match?(SEGMENT[parity]) || text.match?(JUSTIFIED[parity])

        kind = parity == :odd ? "acquisition" : "outreach"
        ["#{name}: P#{number} is #{parity} but the plan doc names no #{kind} segment " \
         "and no carries-none justification (the segment duties, private-agreements)"]
      end

      def current_plan
        plans = Dir.children(@boards_dir).sort.filter_map do |entry|
          match = entry.match(PLAN)
          [entry, match[1].to_i] if match
        end
        plans.max_by { |(_, number)| number }
      end

      # The previous phase's merge date: the SECOND-newest merged stamp in
      # the register (the newest may be the phase just closed). Fewer than
      # two dated rows: too young a register to judge, skip.
      def previous_merge_date
        path = File.join(@boards_dir, "phase-register.md")
        return nil unless File.file?(path)

        dates = File.read(path, encoding: Encoding::UTF_8).scan(MERGED).flatten
                    .map { |d| Date.parse(d) }.sort.reverse
        dates[1]
      end

      def rail_slugs
        Dir.glob(File.join(@adapters_dir, "*.rb")).filter_map do |path|
          File.basename(path, ".rb").tr("_", "-") if File.read(path, encoding: Encoding::UTF_8).match?(PER_PHASE)
        end.sort
      end

      def rail_findings
        cutoff = previous_merge_date
        return [] unless cutoff && File.file?(@ledger_path)

        db = Nabu::Store.connect(@ledger_path, readonly: true)
        begin
          return [] unless db.table_exists?(:runs)

          rail_slugs.filter_map do |slug|
            last = db[:runs].where(source_slug: slug).max(:started_at)
            last_day = last && Date.parse(last.to_s)
            next if last_day && last_day >= cutoff

            seen = last_day ? "last ran #{last_day}" : "has never run"
            "rail source #{slug} #{seen} — before the previous phase's merge (#{cutoff}); " \
              "it owes slices (the per-phase schedule it declares in code)"
          end
        ensure
          db.disconnect
        end
      end
    end
  end
end
