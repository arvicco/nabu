# frozen_string_literal: true

require_relative "source_class"
require_relative "../../eta"

module Nabu
  module Ops
    module Reconstruction
      # `nabu reconstruct backupset`: the COMBINED restore path (owner
      # ruling 2026-11-17) — between carrying a full backup across and the
      # bare-clone rebuild sits the practical strategy: back up only what
      # is expensive or impossible to re-acquire, and re-sync the rest from
      # upstream. This card computes that backup set from the box's own
      # records, never a hand list:
      #
      #   * local/ whole — the instance (rulings, grants, shelves, the
      #     ledger, the mined layers): non-derivable, no upstream;
      #   * db/vectors.sqlite3 — the one time-heavy enrichment living in
      #     db/ (the cost law's documented exception);
      #   * every paced-rail source's canonical tree — months-class to
      #     re-crawl politely;
      #   * every manual-class source's canonical tree — upstream serves it
      #     only to a human, so re-acquisition costs human hours whatever
      #     the tree's size;
      #   * every EXTRA-HUGE source's canonical tree — wired, re-syncable,
      #     but measured at or past the threshold on its last sync
      #     (HUGE_SYNC_SECONDS; --threshold overrides): re-syncing is
      #     possible, planning around it is better;
      #   * every other attic-flagged source's canonical/<slug>/.attic/ —
      #     upstream-deleted bytes no re-fetch restores.
      #
      # Everything else re-syncs from upstream (the Book's three-grain
      # command path), and the card prints that remainder's summed measured
      # compute so the trade is visible. Read-only; sizes come from one
      # `du` per entry and can be skipped.
      class BackupSet
        # The line between "re-sync casually" and "plan around it": a last
        # sync at/past 30 minutes puts the tree in the backup set.
        HUGE_SYNC_SECONDS = 30 * 60

        Entry = Data.define(:path, :reason, :bytes)
        Result = Data.define(:entries, :threshold, :resync_count, :resync_seconds, :resync_unmeasured) do
          def total_bytes = entries.sum { |entry| entry.bytes.to_i }
        end

        def initialize(registry:, verdicts:, ledger:, canonical_dir:, local_dir:, vectors_path:,
                       threshold: HUGE_SYNC_SECONDS, sizes: true)
          @registry = registry
          @verdicts = verdicts
          @ledger = ledger
          @canonical_dir = canonical_dir
          @local_dir = local_dir
          @vectors_path = vectors_path
          @threshold = threshold
          @sizes = sizes
        end

        def build
          entries = instance_entries + rail_entries + manual_entries + huge_entries + attic_entries
          count, seconds, unmeasured = resync_remainder(entries)
          Result.new(entries: entries, threshold: @threshold, resync_count: count,
                     resync_seconds: seconds, resync_unmeasured: unmeasured)
        end

        def self.render(result)
          lines = ["reconstruct backupset — the combined path: back up these, re-sync the rest", ""]
          result.entries.each do |entry|
            size = (entry.bytes ? human(entry.bytes) : "-").rjust(8)
            lines << "  #{size}  #{entry.path}  — #{entry.reason}"
          end
          lines << ""
          total = result.total_bytes
          sized = total.positive? ? " · #{human(total)}" : nil
          lines << "backup set: #{result.entries.size} paths#{sized}"
          remainder = "re-sync remainder: #{result.resync_count} wired sources · " \
                      "#{Eta.format_seconds(result.resync_seconds)} summed measured compute"
          remainder += " · #{result.resync_unmeasured} unmeasured" if result.resync_unmeasured.positive?
          lines << remainder
          lines << "threshold: a last sync at/past #{result.threshold / 60} min puts a tree in the set"
          lines << ""
          lines << "restore order: 1. restore the set  2. clone + bundle install + rake tools:*  " \
                   "3. enable + sync the remainder (the Book's command path)  4. the rebuild  " \
                   "5. reconstruct verify"
          "#{lines.join("\n")}\n"
        end

        def self.human(bytes)
          return "#{bytes} B" if bytes < 1024

          units = %w[KiB MiB GiB TiB]
          value = bytes.to_f
          unit = units[0]
          units.each do |u|
            value /= 1024
            unit = u
            break if value < 1024
          end
          format("%<value>.1f %<unit>s", value: value, unit: unit)
        end

        private

        def instance_entries
          entries = []
          if Dir.exist?(@local_dir)
            entries << entry(@local_dir, "the instance: rulings, grants, shelves, ledger, mined layers " \
                                         "(non-derivable)")
          end
          if File.exist?(@vectors_path)
            entries << entry(@vectors_path, "semantic vectors — time-heavy enrichment (the cost-law " \
                                            "exception in db/)")
          end
          entries
        end

        def rail_entries
          by_class(:rail_paced).filter_map do |slug|
            tree = File.join(@canonical_dir, slug)
            next unless Dir.exist?(tree)

            entry(tree, "paced rail — months-class to re-crawl politely")
          end
        end

        # Manual-class trees ride the set whatever their size (owner ruling
        # 2026-11-17): "the rest re-synced from source" cannot cover a
        # source upstream serves only to a human — re-acquisition costs
        # human hours, not compute, so the tree is carried by class.
        def manual_entries
          by_class(:manual).filter_map do |slug|
            tree = File.join(@canonical_dir, slug)
            next unless Dir.exist?(tree)

            entry(tree, "manual acquisition — human-hours to re-acquire, no unattended route")
          end
        end

        def huge_entries
          wired_slugs = @registry.each_source.select(&:wired).map(&:slug)
          (wired_slugs - by_class(:rail_paced) - by_class(:manual)).sort.filter_map do |slug|
            seconds = Eta.last_sync(@ledger, slug: slug)&.seconds
            next unless seconds && seconds >= @threshold

            tree = File.join(@canonical_dir, slug)
            next unless Dir.exist?(tree)

            entry(tree, "extra-huge: last re-sync measured #{Eta.format_seconds(seconds)}")
          end
        end

        # Attic subtrees of sources whose whole tree is not already in the
        # set: the only strictly backup-only bytes a re-syncable source has.
        def attic_entries
          covered = by_class(:rail_paced) + manual_entries.map { |e| File.basename(e.path) } + huge_slugs
          @verdicts.select(&:attic).map(&:slug).sort.filter_map do |slug|
            next if covered.include?(slug)

            attic = File.join(@canonical_dir, slug, ".attic")
            next unless Dir.exist?(attic)

            entry(attic, "upstream-deleted bytes — no re-fetch restores these")
          end
        end

        def resync_remainder(entries)
          backed = entries.map(&:path)
          slugs = @registry.each_source.select(&:wired).map(&:slug)
                           .reject { |slug| backed.include?(File.join(@canonical_dir, slug)) }
          seconds = 0
          unmeasured = 0
          slugs.each do |slug|
            measured = Eta.last_sync(@ledger, slug: slug)&.seconds
            measured ? seconds += measured : unmeasured += 1
          end
          [slugs.size, seconds, unmeasured]
        end

        def huge_slugs
          @huge_slugs ||= huge_entries.map { |e| File.basename(e.path) }
        end

        def by_class(klass)
          @by_class ||= @verdicts.group_by(&:klass).transform_values { |list| list.map(&:slug) }
          @by_class.fetch(klass, [])
        end

        def entry(path, reason)
          Entry.new(path: path, reason: reason, bytes: @sizes ? size_of(path) : nil)
        end

        def size_of(path)
          Nabu::Shell.run("du", "-sk", path).to_i * 1024
        rescue Nabu::Error
          nil
        end
      end
    end
  end
end
