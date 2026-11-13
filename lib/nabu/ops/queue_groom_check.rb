# frozen_string_literal: true

require "date"

module Nabu
  module Ops
    # The ship-time write-back probe of `rake boards:check` (the
    # 2026-11-13 incident class: two gates shipped queue items recording
    # the ships only in the plan docs — zero queue rows touched — and the
    # next slate ranked against the stale board). A ship updates its queue row in
    # the same motion; this is the machine half, the acquisition-check
    # precedent for a duty that lapsed silently.
    #
    # One cheap, one-directional probe: every Q-id the NEWEST
    # phase-register row names (the row is written at gate close, so its
    # ids are the phase's ships/adoptions) must either be absent from the
    # work queue (removed at the groom) or carry a header stamp dated at
    # or after that row's merge date. Trim judgment stays human — the
    # probe only presumes an unstamped named row stale.
    #
    # The report's summary line (queue row count + newest groom date)
    # rides the boards:check output so a slate ranking against an
    # ungroomed queue is visible in its own transcript.
    class QueueGroomCheck
      MERGED = /merged (\d{4}-\d{2}-\d{2})/
      GROOM = /^## Executed .*groom \((\d{4}-\d{2}-\d{2})\)/
      QUEUE_ROW = /^## (Q\d+) ·(.*)$/
      DATE = /\d{4}-\d{2}-\d{2}/

      Report = Data.define(:skipped, :findings, :rows, :newest_groom) do
        def clean? = findings.empty?

        def summary
          groomed = newest_groom ? newest_groom.to_s : "never"
          "work queue: #{rows} rows, newest groom #{groomed}"
        end
      end

      def initialize(boards_dir:)
        @boards_dir = boards_dir
      end

      def run
        return Report.new(skipped: true, findings: [], rows: 0, newest_groom: nil) unless queue_path && register_path

        queue = File.read(queue_path, encoding: Encoding::UTF_8)
        rows = queue.scan(QUEUE_ROW).to_h { |id, header| [id, header] }
        grooms = queue.scan(GROOM).flatten.map { |d| Date.parse(d) }
        Report.new(skipped: false, findings: findings(rows), rows: rows.size, newest_groom: grooms.max)
      end

      private

      def queue_path = existing("work-queue.md")
      def register_path = existing("phase-register.md")

      def existing(name)
        path = File.join(@boards_dir, name)
        File.file?(path) ? path : nil
      end

      # The newest register row (newest-on-top): from the first "## P"
      # heading to the next one. Without a merge stamp there is no cutoff
      # to judge against — skip the probe rather than guess.
      def newest_register_row
        text = File.read(register_path, encoding: Encoding::UTF_8)
        rows = text.split(/^## /)[1..] || []
        rows.first
      end

      def findings(queue_rows)
        row = newest_register_row
        return [] unless row

        merged = row[MERGED, 1]
        return [] unless merged

        cutoff = Date.parse(merged)
        row.scan(/Q\d+/).uniq.filter_map do |id|
          header = queue_rows[id]
          next if header.nil? # removed at the groom — the clean outcome
          next if header.scan(DATE).any? { |d| Date.parse(d) >= cutoff }

          "queue row #{id} is named by the newest phase-register row (merged #{cutoff}) but carries " \
            "no stamp at or after that date — groom it (remove when whole, trim to the remainder when partial)"
        end
      end
    end
  end
end
