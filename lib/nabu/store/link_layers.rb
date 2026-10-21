# frozen_string_literal: true

require_relative "links_journal"
require_relative "mined_links"

module Nabu
  module Store
    # The READ side of the links split (architecture §15): one read-only
    # handle over BOTH link stores — db/links.sqlite3 (the cheap rebuild
    # lanes) and local/mined-links.sqlite3 (the heavy mined layers,
    # Store::MinedLinks) — so every reader (Query::Links, the `show`
    # footer, `nabu export links`, MCP nabu_links) sees one edge set
    # without knowing there are two files.
    #
    # == How (per connection, in the temp schema)
    #
    # The mined store is ATTACHed as "mined" (read-only: an attached file
    # inherits the main connection's open flags) and two TEMP views named
    # links and link_runs shadow the main tables — SQLite resolves an
    # unqualified name temp-first, so `db[:links]` reads the union.
    # UNION ALL views take the reader's WHERE into each arm, so the
    # per-urn probes stay two indexed searches per store.
    #
    # Mined rows carry NEGATED ids (edge id and run id alike): the two
    # files mint ids independently, and negation keeps every id unique
    # and every run_id → link_runs join exact across the union. Both
    # views add a mined_at column — the layer's mine date (its run's
    # finish time) on mined rows, NULL on rebuild-lane rows.
    #
    # Absent files are honest states: neither file → nil (no links);
    # only the journal → a plain read-only journal handle (no mined_at
    # column — readers treat a missing key as nil); only the mined store →
    # the views over it alone.
    module LinkLayers
      EDGE_TABLES = %i[links link_runs].freeze

      module_function

      # Paths from a Nabu::Config (the usual call) — see #open_paths.
      def open_readonly(config)
        open_paths(links_path: config.links_path, mined_path: config.mined_links_path)
      end

      def open_paths(links_path:, mined_path:)
        links = links_path && File.exist?(links_path)
        mined = mined_path && File.exist?(mined_path)
        return nil unless links || mined
        return LinksJournal.open_readonly(links_path) unless mined

        main = links ? links_path : mined_path
        install = ->(conn) { install_views!(conn, attach: links ? mined_path : nil) }
        Store.connect(main, readonly: true, after_connect: install)
      end

      # The per-connection install: ATTACH (when the journal is main) and
      # the two temp views. +conn+ is the raw SQLite3::Database.
      def install_views!(conn, attach:)
        conn.execute("ATTACH DATABASE ? AS mined", [attach]) if attach
        mined_schema = attach ? "mined" : "main"
        EDGE_TABLES.each do |table|
          columns = columns(conn, mined_schema, table)
          columns &= columns(conn, "main", table) if attach
          arms = []
          arms << journal_arm(table, columns) if attach
          arms << mined_arm(table, columns, mined_schema)
          conn.execute("CREATE TEMP VIEW #{table} AS #{arms.join(' UNION ALL ')}")
        end
      end

      def columns(conn, schema, table)
        conn.execute("PRAGMA #{schema}.table_info(#{table})").map { |row| row[1] }
      end

      def journal_arm(table, columns)
        "SELECT #{columns.join(', ')}, NULL AS mined_at FROM main.#{table}"
      end

      # Ids negated (see the class note); mined_at from the owning run.
      def mined_arm(table, columns, schema)
        if table == :links
          picked = columns.map { |name| %w[id run_id].include?(name) ? "-l.#{name} AS #{name}" : "l.#{name}" }
          "SELECT #{picked.join(', ')}, COALESCE(r.finished_at, r.created_at) AS mined_at " \
            "FROM #{schema}.links l JOIN #{schema}.link_runs r ON r.id = l.run_id"
        else
          picked = columns.map { |name| name == "id" ? "-id AS id" : name }
          "SELECT #{picked.join(', ')}, COALESCE(finished_at, created_at) AS mined_at FROM #{schema}.link_runs"
        end
      end

      # A view's mined_at arrives as the stored string (a computed view
      # column carries no declared type for the adapter to convert by);
      # readers pass it through here for a Time. nil stays nil.
      def mined_time(value)
        value.is_a?(String) ? Sequel.string_to_datetime(value) : value
      end

      private_class_method :install_views!, :columns, :journal_arm, :mined_arm
    end
  end
end
