# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "links_journal"

module Nabu
  module Store
    # The mined-layers store: local/mined-links.sqlite3 (architecture §15,
    # the cost law — owner ruling 2026-10-20). HEAVY-derived link layers
    # (config/mined_layers.yml: the parallels scopes today) are
    # enrichment-class data: hours to regenerate, so they sit OUTSIDE the
    # rebuild's drop zone, are produced only by their mine command, and
    # carry their provenance and age where every reader can see them.
    # By the derivability law's cost clause that makes them INSTANCE data
    # (local/), beside the ledger — never dropped, never re-mined, never
    # stamped by `nabu rebuild`; the backup's local/ section carries them.
    #
    # == The schema (two migration tracks, one file)
    #
    # The edge tables ARE the links journal's: open! applies
    # db/links_migrate first, so links / link_runs / link_run_chunks have
    # the journal's exact shape and every LinksJournal verb (supersede!,
    # the chunked-run cursor, write_edge!, edge_digests) works here
    # unchanged — a heavy producer writes the same rows it always wrote,
    # into a different file. db/mined_migrate adds the per-layer
    # provenance table (mined_layers), versioned in its own counter table.
    # The journal's stamp/stage tables exist here too and stay empty.
    #
    # == The gateway (the shelf write-gateway discipline)
    #
    # This module is the ONLY write path into the store: #mine! (a mine
    # command's whole run — provenance dropped first, the producer's
    # writes, provenance recorded, the self-check verdict) and #migrate!
    # (the one-time move of heavy runs out of db/links.sqlite3). The
    # writable opener is private; readers get #open_readonly (or the
    # union, Store::LinkLayers). The guard test pins that no other lib
    # file opens the store for writing.
    module MinedLinks
      MIGRATIONS_DIR = File.expand_path("../../../db/mined_migrate", __dir__)
      MIGRATIONS_TABLE = :mined_schema_info

      # One layer's provenance row, decoded. +mined_at+ is when its runs
      # finished — the date every reader shows beside its edges.
      Layer = Data.define(:producer, :scope, :run_scope, :run_ids, :edges, :code_version, :stamp, :inputs,
                          :catalog, :origin, :seconds, :mined_at) do
        def label = "#{producer} #{scope}"
      end

      # What one mine did. +verdict+ is the self-check's reading of the
      # re-mine against the layer it replaced:
      #   :first      no prior layer to compare
      #   :verified   inputs unchanged (same stamp) and the edges digest equal
      #   :drift      inputs unchanged but the edges differ — the stamp lied
      #   :reproduced only producer code moved and the edges digest equal
      #   :changed    only producer code moved and the edges differ (honest)
      #   :remined    inputs beyond code moved (+blame+ names them)
      MineResult = Data.define(:layer, :verdict, :blame, :before_edges)

      # The one-time move's tally (#migrate!). +moved+ / +kept+ hold layer
      # labels (kept = the store already held an equal-or-newer mine of
      # that layer, so only the journal copy was dropped). Edge counts are
      # taken before and after on both sides.
      MigrationReport = Data.define(:moved, :kept, :runs, :journal_edges_before, :journal_edges_after,
                                    :mined_edges_before, :mined_edges_after, :dry_run)

      module_function

      # The read-path opener: nil when the store is absent (no heavy layer
      # was ever mined here — readers show fewer links, never an error).
      def open_readonly(path)
        return nil unless path && File.exist?(path)

        Store.connect(path, readonly: true)
      end

      # Every layer's provenance, label order. +db+ may be nil (absent store).
      def layers(db)
        return [] if db.nil? || !db.table_exists?(:mined_layers)

        db[:mined_layers].order(:producer, :scope).all.map { |row| decode(row) }
      end

      # #layers over the file at +path+ ([] when absent).
      def layers_at(path)
        db = open_readonly(path)
        layers(db)
      ensure
        db&.disconnect
      end

      # Up to +size+ [from_urn, to_urn] pairs spread evenly over the id span
      # of +run_ids+' edges — one indexed probe per pick, so health's
      # orphan census costs milliseconds on a 466k-edge layer.
      def sample_edges(db, run_ids, size:)
        return [] if db.nil? || run_ids.empty?

        edges = db[:links].where(run_id: run_ids)
        low, high = edges.get { [min(id).as(:low), max(id).as(:high)] }
        return [] if low.nil?

        step = [(high - low + 1) / size.to_f, 1].max
        picks = (0...size).map { |slot| low + (slot * step).floor }.select { |id| id <= high }.uniq
        picks.filter_map { |id| edges.where { |row| row.id >= id }.order(:id).get(%i[from_urn to_urn]) }.uniq
      end

      # THE mine write path. Opens (creating/migrating) the store, drops the
      # layer's provenance row FIRST (a crash mid-mine must never leave a
      # row vouching for edges that are gone), yields the store to the
      # producer — which writes through the LinksJournal verbs exactly as
      # it would into the journal (supersede, chunked resume and all) —
      # then records the layer's provenance and returns the MineResult.
      # +run_scope+ is the scope string the producer's run rows carry (the
      # recorded scope for parallels). +stamp+/+inputs+ are the
      # LinkStamps preimage; +catalog+ the members' ingest identities.
      def mine!(path, producer:, scope:, stamp:, inputs:, catalog:, run_scope: scope, at: Time.now)
        db = open!(path)
        prior = layer(db, producer, scope)
        expected = prior ? LinksJournal.edge_digests(db, prior.run_ids) : nil
        db[:mined_layers].where(producer: producer, scope: scope).delete
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield db
        run_ids = db[:link_runs].where(producer: producer, scope: run_scope).select_order_map(:id)
        if db[:link_runs].where(id: run_ids, status: "running").any?
          raise Nabu::Error, "#{producer} #{scope}: the mine left an unfinished chunked run — rerun to resume it"
        end

        seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        fresh = record_layer!(db, producer: producer, scope: scope, run_scope: run_scope, run_ids: run_ids,
                                  stamp: stamp, inputs: inputs, catalog: catalog, origin: "mine",
                                  seconds: seconds, at: at)
        verdict, blame = verdict(prior, fresh, expected, LinksJournal.edge_digests(db, run_ids))
        MineResult.new(layer: fresh, verdict: verdict, blame: blame, before_edges: prior&.edges)
      ensure
        db&.disconnect
      end

      # THE one-time move: every run of +producers+ (the heavy class) in
      # the links journal at +journal_path+ — its run row, chunk rows,
      # edges and scope stamp — copied into the store at +path+ (counts
      # verified per run), then removed from the journal. Idempotent: a
      # second call finds no heavy runs left and moves nothing; a call
      # resumed after a crash between copy and delete finds the layer
      # already in the store (equal-or-newer) and only drops the journal
      # copy. +dry_run+ reads both sides and writes nothing.
      # +catalog_for+ (optional) answers (producer, scope, journal stamp) →
      # the members' ingest identities when that stamp still describes the
      # live catalog (nil otherwise: the layer's catalog identity stays
      # unrecorded until its next mine — honest, never guessed).
      def migrate!(path, journal_path:, producers:, dry_run: false, catalog_for: nil)
        journal = if dry_run
                    LinksJournal.open_readonly(journal_path)
                  else
                    (LinksJournal.open!(journal_path) if File.exist?(journal_path))
                  end
        runs = journal ? journal[:link_runs].where(producer: producers).order(:id).all : []
        journal_before = runs.empty? ? 0 : journal[:links].where(run_id: runs.map { |run| run[:id] }).count
        db = dry_run || runs.empty? ? open_readonly(path) : open!(path)
        mined_before = db ? db[:links].count : 0
        plan = migration_plan(journal, db, runs)
        unless dry_run || runs.empty?
          plan.each { |entry| copy_layer!(db, journal_path, journal, entry, catalog_for) unless entry[:kept] }
          drop_journal_runs!(journal, runs, plan)
        end
        MigrationReport.new(
          moved: plan.reject { |entry| entry[:kept] }.map { |entry| entry[:label] },
          kept: plan.select { |entry| entry[:kept] }.map { |entry| entry[:label] },
          runs: runs.size, journal_edges_before: journal_before,
          journal_edges_after: if dry_run || runs.empty?
                                 journal_before
                               else
                                 journal[:links].where(run_id: runs.map do |run|
                                   run[:id]
                                 end).count
                               end,
          mined_edges_before: mined_before, mined_edges_after: db ? db[:links].count : 0, dry_run: dry_run
        )
      ensure
        journal&.disconnect
        db&.disconnect
      end

      # -- private ---------------------------------------------------------------

      # The writable opener: create the file if absent, apply the journal's
      # edge track, then the store's own track.
      def open!(path)
        FileUtils.mkdir_p(File.dirname(path))
        db = LinksJournal.migrate!(LinksJournal.connect(path))
        require "sequel/extensions/migration"
        Sequel::Migrator.run(db, MIGRATIONS_DIR, table: MIGRATIONS_TABLE)
        db
      end

      def layer(db, producer, scope)
        row = db[:mined_layers].where(producer: producer, scope: scope).first
        row && decode(row)
      end

      def decode(row)
        Layer.new(producer: row[:producer], scope: row[:scope], run_scope: row[:run_scope],
                  run_ids: JSON.parse(row[:run_ids_json]), edges: row[:edges], code_version: row[:code_version],
                  stamp: row[:stamp], inputs: row[:inputs_json] && JSON.parse(row[:inputs_json]),
                  catalog: row[:catalog_json] && JSON.parse(row[:catalog_json]), origin: row[:origin],
                  seconds: row[:seconds], mined_at: row[:mined_at])
      end

      # Write one layer's provenance row from the runs now holding its
      # edges: mined_at is their finish time, the engine marker theirs.
      def record_layer!(db, producer:, scope:, run_scope:, run_ids:, stamp:, inputs:, catalog:, origin:,
                        seconds:, at:)
        runs = db[:link_runs].where(id: run_ids).order(:id).all
        mined_at = runs.map { |run| run[:finished_at] || run[:created_at] }.max || at
        row = { producer: producer, scope: scope, run_scope: run_scope, run_ids_json: JSON.generate(run_ids),
                edges: db[:links].where(run_id: run_ids).count, code_version: runs.last&.dig(:code_version),
                stamp: stamp, inputs_json: inputs && JSON.generate(inputs),
                catalog_json: catalog && JSON.generate(catalog), origin: origin, seconds: seconds,
                mined_at: mined_at, recorded_at: at }
        db[:mined_layers].where(producer: producer, scope: scope).delete
        db[:mined_layers].insert(row)
        layer(db, producer, scope)
      end

      # The self-check verdict (MineResult). Digests come from
      # LinksJournal.edge_digests, keyed "producer run_scope".
      def verdict(prior, fresh, expected, actual)
        return [:first, []] if prior.nil?

        blame = blame(prior.inputs, fresh.inputs)
        if prior.stamp && prior.stamp == fresh.stamp
          [expected == actual ? :verified : :drift, []]
        elsif blame == ["producer_code"]
          [expected == actual ? :reproduced : :changed, blame]
        else
          [:remined, blame]
        end
      end

      def blame(before, after)
        return ["unstamped"] if before.nil? || after.nil?

        (before.keys | after.keys).reject { |name| before[name] == after[name] }.sort
      end

      # One entry per (producer, run scope) of the journal's heavy runs:
      # the layer scope its stamp names (falling back to the run scope),
      # the stamp row, whether the store already holds an equal-or-newer
      # mine of it (kept).
      def migration_plan(journal, db, runs)
        return [] if runs.empty?

        stamps = LinksJournal.scope_stamps(journal)
        runs.group_by { |run| [run[:producer], run[:scope]] }.map do |(producer, run_scope), group|
          ids = group.map { |run| run[:id] }
          key, stamp = stamps.find do |(stamp_producer, _scope), row|
            stamp_producer == producer && row[:run_ids].intersect?(ids)
          end
          scope = key ? key.last : run_scope
          mined_at = group.map { |run| run[:finished_at] || run[:created_at] }.max
          existing = db&.table_exists?(:mined_layers) ? layer(db, producer, scope) : nil
          { producer: producer, scope: scope, run_scope: run_scope, runs: group, stamp: stamp,
            label: "#{producer} #{scope}", kept: !existing.nil? && existing.mined_at >= mined_at }
        end
      end

      # Copy one layer's runs into the store over an ATTACHed journal (one
      # INSERT … SELECT per table — 466k edges in seconds), verify each
      # run's edge count, and record its provenance (origin "migrated",
      # the journal stamp's preimage carried over).
      def copy_layer!(db, journal_path, journal, entry, catalog_for)
        catalog = catalog_for&.call(entry[:producer], entry[:scope], entry[:stamp]&.dig(:stamp))
        db.synchronize do
          db.run(Sequel.lit("ATTACH DATABASE ? AS journal", journal_path))
          db.transaction do
            LinksJournal.supersede!(db, producer: entry[:producer], scope: entry[:run_scope])
            new_ids = entry[:runs].map { |run| copy_run!(db, journal, run) }
            stamp = entry[:stamp]
            record_layer!(db, producer: entry[:producer], scope: entry[:scope], run_scope: entry[:run_scope],
                              run_ids: new_ids, stamp: stamp&.dig(:stamp), inputs: stamp&.dig(:inputs),
                              catalog: catalog, origin: "migrated", seconds: nil, at: Time.now)
          end
        ensure
          db.run("DETACH DATABASE journal")
        end
      end

      EDGE_COLUMNS = %i[from_urn to_urn kind score detail chunk created_at].freeze
      CHUNK_COLUMNS = %i[chunk first_urn last_urn anchors candidates edges_inserted edges_refreshed seconds
                         finished_at].freeze

      def copy_run!(db, journal, run)
        new_id = db[:link_runs].insert(run.except(:id))
        attached = ->(table) { db.from(Sequel[:journal][table]).where(run_id: run[:id]) }
        db[:links].import(EDGE_COLUMNS + [:run_id],
                          attached.call(:links).select(*EDGE_COLUMNS, Sequel.as(new_id, :run_id)))
        db[:link_run_chunks].import(CHUNK_COLUMNS + [:run_id],
                                    attached.call(:link_run_chunks).select(*CHUNK_COLUMNS, Sequel.as(new_id, :run_id)))
        copied = db[:links].where(run_id: new_id).count
        held = journal[:links].where(run_id: run[:id]).count
        unless copied == held
          raise Nabu::Error, "migrate-mined: run #{run[:id]} (#{run[:producer]} #{run[:scope]}) copied " \
                             "#{copied} of #{held} edges — rolled back, the journal is untouched"
        end

        new_id
      end

      # Every copy verified: drop the moved runs (edges, chunks, run rows)
      # and their scope stamps from the journal, in one transaction.
      def drop_journal_runs!(journal, runs, plan)
        ids = runs.map { |run| run[:id] }
        journal.transaction do
          journal[:links].where(run_id: ids).delete
          journal[:link_run_chunks].where(run_id: ids).delete
          journal[:link_runs].where(id: ids).delete
          plan.each do |entry|
            journal[:link_scope_stamps].where(producer: entry[:producer], scope: entry[:scope]).delete
          end
        end
      end

      private_class_method :open!, :layer, :decode, :record_layer!, :verdict, :blame, :migration_plan,
                           :copy_layer!, :copy_run!, :drop_journal_runs!
    end
  end
end
