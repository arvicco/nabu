# frozen_string_literal: true

require "json"
require "fileutils"
require "nabu/duration_format"

module Nabu
  module Store
    # The text_normalized diet's reclaim pass — the OWNER-FIRED
    # instrument behind `rake "diet:text_normalized"`. Never the loader's
    # job for existing rows: the loader writes the slim form for every row
    # it touches from now on (Loader#stored_normalized); this pass rewrites
    # the rows an earlier loader stored in full.
    #
    # == What it does
    #
    # Rows whose stored search form equals SQLite's own lower(text) — ASCII
    # lower, the exact expression migration 055's text_search recomputes —
    # take a sentinel in place: "" when the form is also equal to text
    # (P112's class, for rows stored before P112 or by-passing it), else the
    # one-byte "\u0001". The match runs IN SQL (`text_normalized =
    # lower(text)`), so no row round-trips through Ruby. The SERVED form is
    # bit-identical by construction (the sentinel recomputes exactly the
    # value it replaced), and content shas, revisions and the FTS index are
    # untouched — nothing a reader sees changes, so nothing journals.
    #
    # What stays STORED, deliberately: rows whose true fold differs from
    # both text and ASCII-lower(text) — the Unicode folds (Greek accents
    # and case, Cyrillic, É, ſ, the Han variant folds; ~53% of rows at the
    # November 2026 measurement). That is the fold's real content, not waste.
    #
    # == Shape
    #
    # - Batched by rowid WINDOW ((cursor, cursor + batch_rows]), each window
    #   one short transaction inside the catalog write window
    #   (CatalogWriteLock — queues with syncs, so a sync fired meanwhile
    #   interleaves between batches instead of dying on a busy catalog).
    #   One progress line per window.
    # - Resumable: the last committed window's upper id is saved to
    #   db/text_normalized_diet.cursor with the catalog file's inode; a
    #   re-run resumes after it, a cursor from another catalog generation
    #   (a rebuild recreates the file) is ignored. Re-running from scratch
    #   is also correct — dieted rows no longer match — only slower.
    # - Exclusive: one diet at a time (a fail-fast flock on
    #   db/text_normalized_diet.lock, FetchLock-style), never during a
    #   rebuild (+rebuild_check+), never on a catalog whose seam predates
    #   migration 055 (a sentinel there would SERVE the raw byte).
    # - Dry run first-class: the same windowed scan, read-only — row counts
    #   per class and the projected payload bytes, nothing written.
    #
    # == Where the space goes (said in the summary, every run)
    #
    # The freed bytes become free space INSIDE catalog.sqlite3 (emptier
    # pages, some returned to the freelist); the file does not shrink.
    # Space returns to the OS only at VACUUM, the next full rebuild, or
    # db:snapshot (VACUUM INTO writes the compact copy at once). Meanwhile
    # the working set and every snapshot shrink immediately.
    #
    # Projected bytes count the text_normalized PAYLOAD only (the record
    # header's varint shrinks too, by a byte or so per row — not counted).
    class TextNormalizedDiet
      include Nabu::DurationFormat

      LOCK_FILE = "text_normalized_diet.lock"
      CURSOR_FILE = "text_normalized_diet.cursor"
      # const: ids per window — a few seconds of work per transaction on
      # the live catalog, short enough that a queued sync waits briefly
      BATCH_ROWS = 50_000
      # The first catalog migration whose text_search serves the lower
      # sentinel.
      SEAM_MIGRATION = 55
      LOWER = Sequel.function(:lower, :text)
      MONOTONIC = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      class Refused < Nabu::Error; end

      # rows = to_empty + to_lower; bytes = stored payload bytes freed
      # (projected on a dry run).
      Result = Data.define(:rows, :to_empty, :to_lower, :bytes, :batches, :resumed_from, :seconds, :dry_run)

      def initialize(catalog:, catalog_path:, batch_rows: BATCH_ROWS, out: $stdout, rebuild_check: -> {},
                     after_batch: nil, clock: MONOTONIC)
        @catalog = catalog
        @catalog_path = catalog_path
        @db_dir = File.dirname(catalog_path)
        @batch_rows = batch_rows
        @out = out
        @rebuild_check = rebuild_check
        @after_batch = after_batch
        @clock = clock
      end

      def run!(dry_run: false)
        preflight!
        return scan(dry_run: true, from: nil) if dry_run

        with_run_lock { scan(dry_run: false, from: saved_cursor) }
      end

      # The resumable position for THIS catalog file, or nil.
      def saved_cursor
        data = JSON.parse(File.read(cursor_path))
        data.fetch("cursor") if data.fetch("ino") == File.stat(@catalog_path).ino
      rescue Errno::ENOENT, JSON::ParserError, KeyError
        nil
      end

      private

      def preflight!
        version = @catalog[:schema_info].get(:version).to_i
        if version < SEAM_MIGRATION
          raise Refused, "the catalog's text_search seam predates migration 055 (schema #{version}) — " \
                         "a sentinel there would serve the raw byte; run a sync or rebuild first"
        end
        line = @rebuild_check.call
        raise Refused, "#{line} — the diet never runs during a rebuild" if line
      end

      def scan(dry_run:, from:)
        started = @clock.call
        floor = (@catalog[:passages].min(:id) || 1) - 1
        top = @catalog[:passages].max(:id) || 0
        cursor = from && from > floor ? from : floor
        @out.puts("diet:text_normalized resuming after id #{cursor} (saved cursor)") if from && cursor == from
        total = [((top - cursor) / @batch_rows.to_f).ceil, 0].max
        tally = { rows: 0, to_empty: 0, to_lower: 0, bytes: 0 }
        batches = 0
        while cursor < top
          upper = [cursor + @batch_rows, top].min
          window = dry_run ? measure(cursor, upper) : slim!(cursor, upper)
          tally.each_key { |key| tally[key] += window.fetch(key) }
          batches += 1
          progress(batches, total, cursor, upper, window, tally, dry_run: dry_run)
          cursor = upper
          unless dry_run
            save_cursor(cursor)
            @after_batch&.call(cursor)
          end
        end
        clear_cursor unless dry_run
        seconds = @clock.call - started
        result = Result.new(**tally, batches: batches, resumed_from: from, seconds: seconds, dry_run: dry_run)
        @out.puts(summary(result))
        result
      end

      # Rows of one id window the diet would rewrite.
      def candidates(lower, upper)
        @catalog[:passages]
          .where { (id > lower) & (id <= upper) }
          .where(text_normalized: LOWER)
          .exclude(text_normalized: [Loader::EMPTY_SENTINEL, Loader::LOWER_SENTINEL])
      end

      # Class counts and payload bytes freed for one window: every byte of
      # an emptied row, all but the sentinel byte of a lower row.
      def measure(lower, upper)
        to_empty = Sequel.case({ { text_normalized: :text } => 1 }, 0)
        row = candidates(lower, upper).select do
          [count.function.*.as(:rows), sum(to_empty).as(:to_empty),
           sum(octet_length(:text_normalized)).as(:payload)]
        end.first
        rows = row[:rows].to_i
        empties = row[:to_empty].to_i
        { rows: rows, to_empty: empties, to_lower: rows - empties,
          bytes: row[:payload].to_i - ((rows - empties) * Loader::LOWER_SENTINEL.bytesize) }
      end

      def slim!(lower, upper)
        CatalogWriteLock.hold(db_dir: @db_dir, slug: "diet:text_normalized") do
          @catalog.transaction do
            window = measure(lower, upper)
            updated = candidates(lower, upper).update(
              text_normalized: Sequel.case({ { text_normalized: :text } => Loader::EMPTY_SENTINEL },
                                           Loader::LOWER_SENTINEL)
            )
            raise Nabu::Error, "diet window (#{lower}, #{upper}]: measured #{window[:rows]}, updated #{updated}" \
              unless updated == window[:rows]

            window
          end
        end
      end

      def progress(batch, total, lower, upper, window, tally, dry_run:)
        verb = dry_run ? "would slim" : "slimmed"
        @out.puts("diet:text_normalized batch #{batch}/#{total} · ids (#{lower}, #{upper}] · " \
                  "#{verb} #{window[:rows]} (#{human(window[:bytes])}) · total #{tally[:rows]} rows, " \
                  "#{human(tally[:bytes])} · cursor #{upper}")
      end

      def summary(result)
        classes = "#{result.to_empty} → \"\" (equal to text), #{result.to_lower} → the lower sentinel"
        if result.dry_run
          return "DRY RUN diet:text_normalized — #{result.rows} rows would slim (#{classes}); projected " \
                 "#{human(result.bytes)} (#{result.bytes} B) of stored text_normalized payload, " \
                 "#{result.batches} windows scanned in #{format_duration(result.seconds)}; nothing written. " \
                 "Freed space stays inside catalog.sqlite3 until VACUUM, the next full rebuild, or db:snapshot."
        end

        resumed = result.resumed_from ? " (resumed after id #{result.resumed_from})" : ""
        "SUMMARY diet:text_normalized — #{result.rows} rows slimmed (#{classes}), #{human(result.bytes)} " \
          "(#{result.bytes} B) of payload freed in #{result.batches} windows#{resumed} in " \
          "#{format_duration(result.seconds)}. Served text_search is unchanged. The file does NOT shrink " \
          "yet: the space is free pages inside catalog.sqlite3, returned to the OS only at VACUUM, the next " \
          "full rebuild, or db:snapshot (VACUUM INTO writes the compact copy now); the working set and " \
          "every snapshot shrink immediately."
      end

      def with_run_lock
        FileUtils.mkdir_p(@db_dir)
        File.open(File.join(@db_dir, LOCK_FILE), File::RDWR | File::CREAT, 0o644) do |file|
          unless file.flock(File::LOCK_EX | File::LOCK_NB)
            holder = file.read.to_s.strip
            raise Refused, "another diet:text_normalized run holds #{LOCK_FILE}" \
                           "#{" (pid #{holder})" unless holder.empty?} — wait for it or stop it"
          end
          file.truncate(0)
          file.write(Process.pid.to_s)
          file.flush
          yield
        end
      end

      def cursor_path = File.join(@db_dir, CURSOR_FILE)

      def save_cursor(cursor)
        File.write(cursor_path, JSON.generate("ino" => File.stat(@catalog_path).ino, "cursor" => cursor))
      end

      def clear_cursor = FileUtils.rm_f(cursor_path)

      def human(bytes)
        units = %w[B KB MB GB TB]
        value = bytes.to_f
        unit = units.shift
        while value >= 1024 && !units.empty?
          value /= 1024
          unit = units.shift
        end
        unit == "B" ? "#{bytes} B" : format("%<value>.1f %<unit>s", value: value, unit: unit)
      end
    end
  end
end
