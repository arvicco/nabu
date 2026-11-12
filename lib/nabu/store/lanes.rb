# frozen_string_literal: true

module Nabu
  module Store
    # The fulltext LANE files (the incrementality review's lane split): the
    # cjk bigram lane and the trigram fragment lane each live in their OWN
    # SQLite file beside fulltext.sqlite3 — db/fulltext-cjk.sqlite3 and
    # db/fulltext-trigram.sqlite3 — while the search core (passages_fts +
    # passage_lemmas) and every aggregate stay in the main file.
    #
    # == Why split, and why exactly these two
    #
    # One 57 GB file was carrying every tenant: one WAL, one page cache,
    # one merge space. A lane's fts5 merge debt ground against the whole
    # file's b-tree; a checkpoint refusal pinned everyone's WAL; dropping a
    # lane meant a tombstone flood instead of deleting a file. The lanes
    # are the separable tenants by construction — no statement anywhere
    # joins a lane to another table (verified by grep at the split: every
    # lane is MATCHed alone and bridged to the catalog by id lists in app
    # code), so moving them changes no query. The review's "heavy
    # aggregates" stay put deliberately: char_postings, passage_chars and
    # the sign twins are written INSIDE refresh_source!'s slice transaction
    # beside passages_fts, and several (char postings, the rarity ranks)
    # are read back by the very pass that writes them — splitting them
    # would trade one file's atomic swap for a cross-file one with no
    # measured pain to pay for it.
    #
    # == How: ATTACH, so no reader changes
    #
    # Every connect_fulltext installs an after_connect hook that ATTACHes
    # each lane file that EXISTS under a fixed schema name (lane_cjk,
    # lane_trigram). SQLite resolves an unqualified table name main-first,
    # then through the attached schemas, so `fulltext[:passages_cjk]`, the
    # `passages_cjk MATCH ?` literal, fts5's special-command INSERTs and
    # the structure-record read of passages_cjk_data all keep working
    # untouched — the Store::LinkLayers precedent (one handle, two files,
    # readers none the wiser). An attached file inherits the main
    # connection's open flags, so a read-only fulltext handle is a
    # read-only lane handle.
    #
    # Absence is an honest state: a connect NEVER mints a lane file (no
    # file = lane not built = the old missing-table degrade, exactly).
    # Only a lane BUILD creates one (ensure_attached!). An in-memory main
    # (the suite's sqlite::memory: fulltexts) gets a per-connection
    # in-memory lane at its first build — the memory pool is one
    # connection, so the lane lives exactly as long as the main does.
    #
    # Shape arrival: a pre-split fulltext still carries the lane tables in
    # its MAIN schema. They keep serving (main-first resolution) and keep
    # taking the trigram lane's sync writes until the lane is next built,
    # which drops them from main first (drop_legacy!) — otherwise the
    # legacy copy would shadow the fresh file forever.
    #
    # == The connection profile, per attached schema
    #
    # cache_size, mmap_size, page_size, journal_mode and synchronous are
    # all PER-SCHEMA pragmas, so the riders the main fulltext gets on
    # connect (Store.connect_fulltext) are applied to each lane schema in
    # the hook: the live cache + mmap on every connect; on read-write
    # connects page_size 8192 (fresh files only — the main file's
    # one-way-door rule), WAL, and synchronous NORMAL (OFF under the
    # rebuild profile, the same disposable-derived argument).
    #
    # == Crash-honest builds (the Nov 2026 crash-loss incident)
    #
    # The rebuild that died mid-reindex on 2026-11-10 left the cjk lane
    # EMPTY with an empty scope: the lane build dropped its tables BEFORE
    # rebuilding, so the death took the old lane with it, and fourteen
    # flagged sources silently lost substring search. Now that a lane is
    # a file, its build (Lanes.build!) never touches the serving file:
    #
    #   1. clear any orphan a previous KILLED build left (<lane>.building);
    #   2. DETACH the serving lane on the builder's connection and ATTACH
    #      the fresh <lane>.building file under the SAME schema name — so
    #      the build's unqualified writes, the merge governor's structure
    #      reads and the fts5 commands all land in the new file, untouched;
    #   3. the build runs; the new file is then SEALED (checkpointed, the
    #      journal back to rollback mode — no -wal/-shm left beside it);
    #   4. the swap: the serving file's sidecars go, and one rename(2)
    #      puts the new file at the serving path — atomic on one volume;
    #   5. the serving path is re-ATTACHed on the builder's connection.
    #
    # A build that RAISES anywhere before the swap detaches and deletes
    # its file and re-attaches the old one (the ensure arm); a build that
    # is KILLED runs no ensure at all — the old file was never opened for
    # writing, so it simply keeps serving, and the orphan is step 1's job
    # next time. Readers in other processes holding the old inode keep
    # reading it until they reconnect (unlinked, never corrupted).
    #
    # The building file takes the rebuild profile (synchronous OFF): it is
    # disposable until the swap by construction. The seal raises it back
    # to NORMAL before the checkpoint, so the bytes the rename publishes
    # were synced.
    #
    # Two honest gaps, both shape-arrival one-offs: an in-memory main has
    # no file to swap (the suite's fulltexts — build in place), and the
    # FIRST split build over a pre-split fulltext drops the main-schema
    # copy before building (it would shadow the new file's schema for the
    # build's own unqualified writes) — that one arrival is not
    # crash-honest; every lane build after it is.
    module Lanes
      Lane = Data.define(:name, :schema, :suffix, :tables)

      CJK = Lane.new(name: :cjk, schema: "lane_cjk", suffix: "-cjk",
                     tables: %i[passages_cjk passages_cjk_scope].freeze)
      TRIGRAM = Lane.new(name: :trigram, schema: "lane_trigram", suffix: "-trigram",
                         tables: %i[passages_trigram passages_trigram_scope].freeze)
      ALL = [CJK, TRIGRAM].freeze

      # The in-progress build's file: <lane path><BUILDING_SUFFIX>. Never
      # attached by a connect (attach_existing! names only the lane path).
      BUILDING_SUFFIX = ".building"

      module_function

      # The lane's file beside +main_path+: fulltext.sqlite3 →
      # fulltext-cjk.sqlite3 (the stem keeps the family sorted together in
      # db/ and in every backup listing).
      def path_for(main_path, lane)
        ext = File.extname(main_path)
        "#{main_path.to_s.delete_suffix(ext)}#{lane.suffix}#{ext}"
      end

      def paths_for(main_path) = ALL.map { |lane| path_for(main_path, lane) }

      # The main database FILE behind a connect_fulltext url (a bare path
      # or a sqlite:// url), or nil for an in-memory or non-sqlite url.
      def main_file(url)
        url = url.to_s
        return nil if url.include?(":memory:")
        return url.delete_prefix("sqlite://") if url.start_with?("sqlite://")
        return nil if url.match?(/\A[a-z][a-z0-9+.-]*:/i)

        url
      end

      # The after_connect hook body (+conn+ is the raw SQLite3::Database):
      # attach every lane file that exists beside +main_path+.
      def attach_existing!(conn, main_path, readonly:, rebuild: false)
        return if main_path.nil?

        ALL.each do |lane|
          path = path_for(main_path, lane)
          attach_raw!(conn, lane, path, readonly: readonly, rebuild: rebuild) if File.file?(path)
        end
      end

      def attach_raw!(conn, lane, path, readonly:, rebuild: false)
        conn.execute("ATTACH DATABASE ? AS #{lane.schema}", [path])
        profile!(conn, lane, readonly: readonly, rebuild: rebuild)
      end

      # The per-schema riders (class note).
      def profile!(conn, lane, readonly:, rebuild: false)
        schema = lane.schema
        conn.execute("PRAGMA #{schema}.cache_size = #{rebuild ? REBUILD_CACHE_KIB : LIVE_CACHE_KIB}")
        conn.execute("PRAGMA #{schema}.mmap_size = #{LIVE_MMAP_BYTES}")
        return if readonly

        conn.execute("PRAGMA #{schema}.page_size = #{PAGE_SIZE}")
        conn.execute("PRAGMA #{schema}.journal_mode = wal")
        conn.execute("PRAGMA #{schema}.synchronous = #{rebuild ? 'OFF' : 'NORMAL'}")
      end

      # -- the writer side (Sequel handles) -----------------------------------

      # The main file behind a live Sequel handle (PRAGMA database_list —
      # works whatever opened it), nil for an in-memory main.
      def main_path(db)
        row = schemas(db).find { |entry| entry[:name] == "main" }
        file = row && row[:file].to_s
        file.nil? || file.empty? ? nil : file
      end

      def attached?(db, lane) = schemas(db).any? { |entry| entry[:name] == lane.schema }

      def schemas(db) = db.fetch("PRAGMA database_list").all

      # A lane BUILD's attach: the lane file beside a file-backed main
      # (created here — the one place a lane file is born), or a fresh
      # in-memory schema beside an in-memory main. Idempotent.
      def ensure_attached!(db, lane)
        return if attached?(db, lane)

        main = main_path(db)
        target = main ? path_for(main, lane) : ":memory:"
        db.synchronize { |conn| attach_raw!(conn, lane, target, readonly: false) }
      end

      # A pre-split file's main-schema copies of the lane tables (class
      # note: they would shadow the lane file). No-op once gone.
      def drop_legacy!(db, lane)
        lane.tables.each { |table| db.run("DROP TABLE IF EXISTS main.#{table}") }
      end

      # Ready +lane+ for a from-scratch build on +db+: legacy copies out of
      # main, the lane schema attached, its tables dropped. Returns the
      # schema name the build's DDL qualifies with.
      def prepare_build!(db, lane)
        drop_legacy!(db, lane)
        ensure_attached!(db, lane)
        lane.tables.each { |table| db.run("DROP TABLE IF EXISTS #{lane.schema}.#{table}") }
        lane.schema
      end

      # Build +lane+ from scratch through the crash-honest swap (class
      # note); yields the schema name the build's DDL qualifies with and
      # returns the block's value. Must run OUTSIDE a transaction (ATTACH
      # and DETACH refuse inside one) — every lane build is a top-level
      # rebuild stage. An in-memory main builds in place.
      def build!(db, lane)
        main = main_path(db)
        return yield(prepare_build!(db, lane)) if main.nil?

        final = path_for(main, lane)
        building = "#{final}#{BUILDING_SUFFIX}"
        drop_legacy!(db, lane)
        Store.drop_database_files!(building) # a killed build's orphan
        db.synchronize do |conn|
          swapped = false
          begin
            detach_raw!(conn, lane)
            attach_raw!(conn, lane, building, readonly: false, rebuild: true)
            result = yield lane.schema
            seal_raw!(conn, lane)
            detach_raw!(conn, lane)
            swap_in!(building, final)
            swapped = true
            result
          ensure
            unless swapped
              detach_raw!(conn, lane)
              Store.drop_database_files!(building)
            end
            attach_raw!(conn, lane, final, readonly: false) if File.file?(final) && !attached_raw?(conn, lane)
          end
        end
      end

      # The swap (class note, step 4): the serving file's sidecars first —
      # a -wal left beside the new file would replay the OLD file's frames
      # over it (the drop_database_files! incident class) — then one rename.
      def swap_in!(building, final)
        FileUtils.rm_f(["#{final}-wal", "#{final}-shm"])
        File.rename(building, final)
      end

      # Fold the WAL in and leave no sidecars (Store.seal_rollback_journal!,
      # per schema): the file is renamed as one self-contained file.
      def seal_raw!(conn, lane)
        conn.execute("PRAGMA #{lane.schema}.synchronous = NORMAL")
        conn.execute("PRAGMA #{lane.schema}.wal_checkpoint(TRUNCATE)")
        conn.execute("PRAGMA #{lane.schema}.journal_mode = delete")
      end

      def detach_raw!(conn, lane)
        conn.execute("DETACH DATABASE #{lane.schema}") if attached_raw?(conn, lane)
      end

      def attached_raw?(conn, lane)
        conn.execute("PRAGMA database_list").any? { |row| row[1] == lane.schema }
      end

      # A lane table as a schema-qualified identifier (create_table).
      def qualified(lane, table) = Sequel[lane.schema.to_sym][table]
    end
  end
end
