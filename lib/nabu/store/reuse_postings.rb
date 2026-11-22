# frozen_string_literal: true

require "fileutils"
require "json"
require "zlib"
require_relative "../errors"

module Nabu
  module Store
    # The gram-postings store: local/reuse/<build>/ (the reuse-batch
    # redesign; architecture §15, the cost law). For one SCOPE's anchor
    # grams it records every passage a quoted FTS phrase probe of that gram
    # would return — so the postings engine (Query::ParallelsPostings) can
    # score an anchor from a B-tree lookup instead of one FTS round-trip per
    # gram, the measured 92% of the old engine's time.
    #
    # == Why local/, and why its own command
    #
    # Hours to build at CJK scale (the spike measured ≈1.3 h with 8 workers
    # for the kanripo leg) — a heavy derivation product, so by the cost law
    # it is ENRICHMENT-class instance data: never built, dropped or touched
    # by `nabu rebuild` or a sync, produced only by `nabu reuse build`,
    # stamped with the identities it was built from (Nabu::ReuseCensus
    # computes the stamp and its staleness reading; `nabu reuse status`
    # shows it). Losing it costs a re-build, never data.
    #
    # == The layout (gram-hash partitioned, one SQLite file per shard)
    #
    #   local/reuse/<build>/manifest.sqlite3   provenance: one JSON row
    #   local/reuse/<build>/shard-NN.sqlite3   grams(gram, df)
    #                                          postings(gram, passage_id, lanes)
    #
    # +gram+ is the probe KEY: the gram's tokens as the FTS tokenizer folds
    # them, space-joined (Query::ParallelsPostings#keys_for). A key lives in
    # shard crc32(key) % shards — crc32, not String#hash, which is seeded
    # per process. grams holds EVERY wanted key the corpus attests, with its
    # document frequency (distinct passages over both lanes); postings holds
    # the passages of the keys whose df is under the build's +cap+ (the
    # common-gram cutoff the build was made for) — a key at or over it can
    # never score (the engine skips df ≥ cutoff), so its postings are not
    # kept, but its df IS, because the engine must still see it as common
    # rather than absent. +lanes+ is a bitmask — LANE_MAIN the passage
    # matched on the main fulltext lane, LANE_CJK on the CJK bigram lane —
    # so a probe can rebuild the FTS engine's exact (lane ∪ main) row order.
    #
    # == The gateway (the shelf write-gateway discipline)
    #
    # This class is the ONLY write path into local/reuse/: #build! (a
    # census's whole build — staged in a sibling directory, swapped in
    # whole only when stamped, so a killed build leaves the previous one
    # serving) and the Build it yields (per-worker raw writers, the
    # per-shard finalize, the stamp). Readers get #open (a Reader) and
    # #builds. derivability_writers_test pins that no other lib file names
    # the directory.
    class ReusePostings
      class Error < Nabu::Error; end

      DIRNAME = "reuse"
      MANIFEST = "manifest.sqlite3"
      LANE_MAIN = 1
      LANE_CJK = 2
      # IN-list slice for key lookups (well under SQLite's variable limit).
      LOOKUP_SLICE = 500
      # Rows buffered per raw writer file before one bulk import.
      FLUSH_ROWS = 20_000

      # One stamped build: its directory and decoded provenance.
      Manifest = Data.define(:name, :dir, :provenance) do
        def shards = provenance.fetch("shards")
        def cap = provenance.fetch("cap")
      end

      class << self
        # The store root under the instance folder.
        def root(config) = File.join(config.local_dir, DIRNAME)

        # The build directory name for a (scope, lang, gram size): the scope
        # made filesystem-safe (a urn prefix carries colons). The scope is
        # also stamped in the provenance, and readers check it there.
        def build_name(scope:, gram_size:, lang: nil)
          base = scope.to_s.gsub(/[^A-Za-z0-9._-]/, "_")
          [base, lang&.to_s&.gsub(/[^A-Za-z0-9_-]/, "_"), "g#{gram_size}"].compact.join(".")
        end

        def shard_of(key, shards) = Zlib.crc32(key) % shards

        # Build one store: yields a Build over a fresh staging directory;
        # the block must end with Build#stamp!. On success the staging
        # directory replaces <root>/<name> whole; on any failure it is
        # removed and the previous build (if any) keeps serving.
        #
        # A Build#discard!-ed build (a timing run) installs nothing and
        # returns nil. Staging left by a KILLED build of the same name is
        # removed first; one whose process is still alive refuses (two
        # censuses of one store never interleave).
        def build!(root:, name:, shards:)
          final = File.join(root, name)
          clear_dead_staging!(final)
          staging = "#{final}.building-#{Process.pid}"
          FileUtils.mkdir_p(staging)
          build = Build.new(dir: staging, shards: shards)
          yield build
          return nil if build.discarded?
          raise Error, "reuse build #{name}: never stamped — refusing to install it" unless build.stamped?

          install!(staging, final)
          manifest(final)
        ensure
          FileUtils.rm_rf(staging) if staging && File.exist?(staging)
        end

        # Every stamped build under +root+, by name.
        def builds(root)
          Dir[File.join(root, "*", MANIFEST)].filter_map { |path| manifest(File.dirname(path)) }
        end

        # Staging directories a killed build left behind (status names them).
        def unfinished(root) = Dir[File.join(root, "*.building-*")]

        def manifest(dir)
          path = File.join(dir, MANIFEST)
          return nil unless File.file?(path)

          db = Store.connect(path, readonly: true)
          row = db[:provenance].first
          Manifest.new(name: File.basename(dir), dir: dir, provenance: JSON.parse(row.fetch(:json)))
        ensure
          db&.disconnect
        end

        # A Reader over the stamped build +name+, or nil when absent.
        def open(root, name)
          found = manifest(File.join(root, name))
          found && Reader.new(found)
        end

        private

        def clear_dead_staging!(final)
          Dir["#{final}.building-*"].each do |dir|
            pid = dir[/\.building-(\d+)\z/, 1].to_i
            if pid != Process.pid && alive?(pid)
              raise Error, "reuse build #{File.basename(final)}: another census is building it (pid #{pid})"
            end

            FileUtils.rm_rf(dir)
          end
        end

        def alive?(pid)
          return false unless pid.positive?

          Process.kill(0, pid)
          true
        rescue Errno::ESRCH
          false
        rescue Errno::EPERM
          true
        end

        def install!(staging, final)
          retired = "#{final}.retired-#{Process.pid}"
          File.rename(final, retired) if File.exist?(final)
          File.rename(staging, final)
          FileUtils.rm_rf(retired)
        end
      end

      # A build in progress. Raw writers run in the census workers (each
      # owns its own files — no two processes ever write one SQLite file);
      # finalize_shard! runs once per shard after every writer closed.
      class Build
        attr_reader :dir, :shards

        def initialize(dir:, shards:)
          @dir = dir
          @shards = shards
          @stamped = false
        end

        def stamped? = @stamped

        # A timing run's end: nothing of this build is installed.
        def discard!
          @discarded = true
        end

        def discarded? = @discarded == true

        def shard_path(shard) = File.join(@dir, format("shard-%02d.sqlite3", shard))

        # Pass 1's writer: the scope's anchor keys (worker-local files).
        def wanted_writer(worker) = RawWriter.new(build: self, worker: worker, kind: :wanted)

        # Pass 2's writer: (key, passage, lane) emissions (worker-local).
        def raw_writer(worker) = RawWriter.new(build: self, worker: worker, kind: :raw)

        def raw_files(kind, shard)
          Dir[File.join(@dir, format("w*-s%<shard>02d.%<kind>s.sqlite3", shard: shard, kind: kind))]
        end

        # Merge one shard's worker files into its final tables: the wanted
        # key set, every wanted key's df (partials summed — the census
        # partitions passages across workers, so per-worker distinct counts
        # add exactly), and the postings of the keys under +cap+. The raw
        # files are deleted as they are consumed. Returns the shard's counts.
        def finalize_shard!(shard, cap:)
          db = Store.connect(shard_path(shard), rebuild: true)
          create_final_tables(db)
          scratch = File.join(@dir, format("scratch-%02d.sqlite3", shard))
          db.synchronize do |conn|
            attach(conn, scratch, "scratch")
            create_scratch_tables(db)
            raw_files(:wanted, shard).each { |path| with_attached(conn, path) { merge_wanted(db) } }
            raw = raw_files(:raw, shard)
            raw.each { |path| with_attached(conn, path) { merge_partials(db) } }
            db[:grams].import(%i[gram df], db[Sequel[:scratch][:partials]].group(:gram)
                                              .select(:gram, Sequel.function(:sum, :df)))
            raw.each { |path| with_attached(conn, path) { merge_postings(db, cap) } }
            counts = shard_counts(db, cap)
            conn.execute("DETACH DATABASE scratch")
            counts
          end
        ensure
          db&.disconnect
          (raw_files(:wanted, shard) + raw_files(:raw, shard) + [scratch].compact).each do |path|
            FileUtils.rm_f([path, "#{path}-wal", "#{path}-shm"])
          end
        end

        # Record the provenance (the census's stamp hash) — the act that
        # makes the build installable.
        def stamp!(provenance)
          db = Store.connect(File.join(@dir, MANIFEST))
          db.create_table?(:provenance) do
            String :json, text: true, null: false
          end
          db[:provenance].delete
          db[:provenance].insert(json: JSON.generate(provenance))
          @stamped = true
        ensure
          db&.disconnect
        end

        private

        def create_final_tables(db)
          db.create_table?(:grams, without_rowid: true) do
            column :gram, :text, primary_key: true
            Integer :df, null: false
          end
          db.create_table?(:postings, without_rowid: true) do
            column :gram, :text, null: false
            Integer :passage_id, null: false
            Integer :lanes, null: false
            primary_key %i[gram passage_id]
          end
        end

        def create_scratch_tables(db)
          db.create_table(Sequel[:scratch][:wanted], without_rowid: true) do
            column :gram, :text, primary_key: true
          end
          db.create_table(Sequel[:scratch][:partials]) do
            column :gram, :text, null: false
            Integer :df, null: false
          end
        end

        def merge_wanted(db)
          db[Sequel[:scratch][:wanted]].insert_ignore.import([:gram], db[Sequel[:w][:wanted]].select(:gram))
        end

        def merge_partials(db)
          wanted = db[Sequel[:scratch][:wanted]].select(:gram)
          db[Sequel[:scratch][:partials]].import(
            %i[gram df],
            db[Sequel[:w][:raw]].where(gram: wanted).group(:gram)
                                .select(:gram, Sequel.function(:count, :passage_id).distinct)
          )
        end

        # sum(DISTINCT lane) over a (key, passage) group is the lane
        # bitmask: LANE_MAIN 1, LANE_CJK 2, both 3.
        def merge_postings(db, cap)
          rare = db[:grams].where { df < cap }.select(:gram)
          db[:postings].import(
            %i[gram passage_id lanes],
            db[Sequel[:w][:raw]].where(gram: rare).group(:gram, :passage_id)
                                .select(:gram, :passage_id, Sequel.function(:sum, :lane).distinct)
          )
        end

        def shard_counts(db, cap)
          { "grams" => db[:grams].count, "rare_grams" => db[:grams].where { df < cap }.count,
            "postings" => db[:postings].count }
        end

        # ATTACH/DETACH have no Sequel API (the Store::Lanes precedent: raw
        # execute on the held connection, outside any transaction).
        def attach(conn, path, schema)
          conn.execute("ATTACH DATABASE ? AS #{schema}", [path])
        end

        def with_attached(conn, path)
          attach(conn, path, "w")
          yield
        ensure
          conn.execute("DETACH DATABASE w")
        end
      end

      # One worker's emissions for one pass, one file per shard (opened on
      # first use), bulk-imported every FLUSH_ROWS rows. Never shared
      # across processes.
      class RawWriter
        attr_reader :rows

        def initialize(build:, worker:, kind:)
          @build = build
          @worker = worker
          @kind = kind
          @dbs = {}
          @buffers = Hash.new { |hash, key| hash[key] = [] }
          @rows = 0
        end

        def add_wanted(key)
          push(key, [key])
        end

        def add(key, passage_id, lane)
          push(key, [key, passage_id, lane])
        end

        def flush
          @buffers.each do |shard, rows|
            next if rows.empty?

            db = shard_db(shard)
            db.transaction { db[@kind].import(columns, rows) }
            rows.clear
          end
        end

        def close
          flush
          @dbs.each_value(&:disconnect)
          @dbs.clear
        end

        private

        def push(key, row)
          shard = ReusePostings.shard_of(key, @build.shards)
          buffer = @buffers[shard]
          buffer << row
          @rows += 1
          return if buffer.size < FLUSH_ROWS

          db = shard_db(shard)
          db.transaction { db[@kind].import(columns, buffer) }
          buffer.clear
        end

        def columns = @kind == :wanted ? [:gram] : %i[gram passage_id lane]

        def shard_db(shard)
          @dbs[shard] ||= begin
            path = File.join(@build.dir, format("w%<worker>02d-s%<shard>02d.%<kind>s.sqlite3",
                                                worker: @worker, shard: shard, kind: @kind))
            db = Store.connect(path, rebuild: true)
            kind = @kind
            db.create_table?(kind) do
              column :gram, :text, null: false
              if kind == :raw
                Integer :passage_id, null: false
                Integer :lane, null: false
              end
            end
            db
          end
        end
      end

      # Read side: per-shard read-only handles (opened lazily — a forked
      # scoring worker opens its own).
      class Reader
        attr_reader :manifest

        def initialize(manifest)
          @manifest = manifest
          @dbs = {}
        end

        def provenance = @manifest.provenance

        # { key => :common | [[passage_id, lanes], ...] } for the +keys+
        # the corpus attests (absent keys: absent). Postings come in
        # ascending passage id — the FTS phrase probe's own row order.
        def lookup(keys)
          out = {}
          keys.uniq.group_by { |key| ReusePostings.shard_of(key, @manifest.shards) }.each do |shard, shard_keys|
            db = shard_db(shard)
            shard_keys.each_slice(LOOKUP_SLICE) { |slice| lookup_slice(db, slice, out) }
          end
          out
        end

        def close
          @dbs.each_value(&:disconnect)
          @dbs.clear
        end

        private

        def lookup_slice(db, slice, out)
          rare = []
          db[:grams].where(gram: slice).select_map(%i[gram df]).each do |gram, df|
            df < @manifest.cap ? rare << gram : out[gram] = :common
          end
          return if rare.empty?

          db[:postings].where(gram: rare).order(:gram, :passage_id)
                       .select_map(%i[gram passage_id lanes])
                       .each { |gram, passage_id, lanes| (out[gram] ||= []) << [passage_id, lanes] }
        end

        def shard_db(shard)
          @dbs[shard] ||= Store.connect(File.join(@manifest.dir, format("shard-%02d.sqlite3", shard)),
                                        readonly: true)
        end
      end
    end
  end
end
