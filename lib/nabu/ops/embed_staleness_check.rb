# frozen_string_literal: true

require "date"
require "time"

module Nabu
  module Ops
    # The embed-staleness probe (`rake boards:check`; INFORMATIONAL — it
    # prints a finding line and never fails the task). vectors.sqlite3 is
    # maintained only by owner-fired `nabu embed` runs (the cost law), so
    # it can lag the library for months with no surface saying so. The
    # probe holds the newest embed stamp (embed_meta.updated_at, any
    # model) against the newest source ADDITION — each source's first
    # succeeded run in the ledger. The ledger, not the catalog: a rebuild
    # re-mints every catalog timestamp, while the ledger keeps when a
    # source really arrived. A gap beyond THRESHOLD_DAYS is one honest
    # line naming how many sources arrived since, the newest, and how
    # many of them the embed scope (registry embed_index) even covers.
    #
    # Two cheap reads (one meta table, one grouped ledger scan), both
    # read-only. No vectors file, no stamp, or no ledger = an announced
    # skip (a public clone, a lane worktree, a box that never embedded).
    class EmbedStalenessCheck
      THRESHOLD_DAYS = 7
      META_TABLE = :embed_meta # Nabu::Embed::META_TABLE

      Report = Data.define(:skipped, :skip_reason, :finding, :stamp, :newest_slug, :newest_at) do
        def clean? = finding.nil?
      end

      def initialize(vectors_path:, ledger_path:, embed_slugs: [], threshold_days: THRESHOLD_DAYS)
        @vectors_path = vectors_path
        @ledger_path = ledger_path
        @embed_slugs = embed_slugs.to_set
        @threshold_days = threshold_days
      end

      def run
        return skip("no vectors file at #{@vectors_path}") unless File.exist?(@vectors_path)

        stamp = newest_stamp
        return skip("no embed stamp in #{File.basename(@vectors_path)} (never embedded)") if stamp.nil?
        return skip("no ledger at #{@ledger_path}") unless File.exist?(@ledger_path)

        additions = first_runs
        newest_slug, newest_at = additions.max_by { |_slug, at| at }
        since = additions.select { |_slug, at| at > stamp }
        finding = (stale_line(stamp, since, newest_slug, newest_at) if newest_at && stale?(stamp, newest_at))
        Report.new(skipped: false, skip_reason: nil, finding: finding, stamp: stamp, newest_slug: newest_slug,
                   newest_at: newest_at)
      end

      private

      def skip(reason)
        Report.new(skipped: true, skip_reason: reason, finding: nil, stamp: nil, newest_slug: nil, newest_at: nil)
      end

      def stale?(stamp, newest_at)
        (newest_at - stamp) > @threshold_days * 86_400
      end

      def stale_line(stamp, since, newest_slug, newest_at)
        days = ((newest_at - stamp) / 86_400).floor
        flagged = since.keys.count { |slug| @embed_slugs.include?(slug) }
        "newest embed stamp #{stamp.utc.to_date.iso8601} predates the library: #{since.size} source(s) " \
          "first synced since (newest: #{newest_slug} #{newest_at.utc.to_date.iso8601}, #{days} days later; " \
          "#{flagged} of them embed-flagged) — the semantic surface lags; `rake aggregates:embed_census` " \
          "reads per-source coverage, the embed run itself stays owner-fired"
      end

      def newest_stamp
        with_db(@vectors_path) do |db|
          next nil unless db.table_exists?(META_TABLE)

          stamps = db[META_TABLE].select_map(:updated_at).compact
          stamps.map { |value| value.is_a?(Time) ? value : Time.parse(value.to_s) }.max
        end
      end

      # { slug => first succeeded run's started_at } — one grouped scan.
      def first_runs
        with_db(@ledger_path) do |db|
          db[:runs].where(status: "succeeded").group(:source_slug)
                   .select_hash(:source_slug, Sequel.function(:min, :started_at).as(:first))
                   .transform_values { |value| value.is_a?(Time) ? value : Time.parse(value.to_s) }
        end
      end

      def with_db(path)
        db = Nabu::Store.connect(path, readonly: true)
        yield db
      ensure
        db&.disconnect
      end
    end
  end
end
