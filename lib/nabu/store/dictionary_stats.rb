# frozen_string_literal: true

module Nabu
  module Store
    # The dictionary-group census (P106-1 — owner ruling, generalization 2): one
    # precompiled row per dictionary in dictionary_stats (migration 036) —
    # shipped language code, resolved lect node, live entry count — so
    # every dictionary-shaped surface (`define`'s header, the language
    # cards, the site desks) answers from the GROUP without scanning the
    # entries (the desk-commands law: cards touch only precompiled data).
    #
    # Resolution runs the registry's own ladder (per-source override >
    # codemap > identity) and then requires the resolved id to be a node
    # the registry actually defines: a code the registry cannot place
    # (oracc's akk-x-* periods before their mint) stays NULL — the
    # censused-UNRESOLVED posture, honest and never silently invented.
    # No registry at all (a clone without the nabu-lects module) writes
    # every lect NULL — the feature-off posture, never an error.
    #
    # Derived by construction: f(dictionaries + dictionary_entries +
    # registry) — drop-and-reproject wholesale in both rebuild flavors,
    # per source after any dictionary-bearing sync (the P47-r3 lesson:
    # no lane may lag a sync). Recorded v1 limit (owner ruling): a dictionary
    # carries ONE language code; mixed dictionaries group under their
    # primary — entry-grain language is a recorded future step.
    module DictionaryStats
      module_function

      # Wholesale recompute. Returns the row count; a pre-036 catalog is
      # a clean no-op (the KindBuilder table-guard stance).
      def rebuild!(catalog:, lects:, shelf_dates: nil)
        return 0 unless catalog.table_exists?(:dictionary_stats)

        catalog[:dictionary_stats].delete
        insert_rows(catalog, lects, catalog[:dictionaries], shelf_dates)
      end

      # Drop and re-derive ONE source's rows (SyncRunner's post-load
      # seam). Unknown slug just reports zero.
      def refresh_source!(catalog:, lects:, slug:, shelf_dates: nil)
        return 0 unless catalog.table_exists?(:dictionary_stats)

        source_id = catalog[:sources].where(slug: slug).get(:id)
        return 0 if source_id.nil?

        catalog[:dictionary_stats].where(source_id: source_id).delete
        insert_rows(catalog, lects, catalog[:dictionaries].where(source_id: source_id), shelf_dates)
      end

      def insert_rows(catalog, lects, dictionaries, shelf_dates)
        counts = catalog[:dictionary_entries]
                 .where(withdrawn: false)
                 .group_and_count(:dictionary_id)
                 .as_hash(:dictionary_id, :count)
        rows = dictionaries
               .join(:sources, id: :source_id)
               .select(Sequel[:dictionaries][:id].as(:dictionary_id),
                       Sequel[:dictionaries][:slug],
                       Sequel[:dictionaries][:source_id],
                       Sequel[:dictionaries][:language],
                       Sequel[:sources][:slug].as(:source_slug))
               .map do |dict|
                 { dictionary_id: dict[:dictionary_id], slug: dict[:slug],
                   source_id: dict[:source_id], language: dict[:language],
                   lect: resolved_node(lects, dict[:language], dict[:source_slug]),
                   entries: counts.fetch(dict[:dictionary_id], 0) }
               end
        stamp_shelf_stages!(catalog, rows, lects, dictionaries, shelf_dates)
        catalog[:dictionary_stats].multi_insert(rows)
        rows.size
      end

      # The resolved id only counts when the registry DEFINES it (an
      # identity resolution of an unregistered code is not a node).
      def resolved_node(lects, language, source_slug)
        return nil unless lects

        id = lects.resolve(language, source: source_slug)
        lects.lect(id) ? id : nil
      end

      # Fold the shelf-grain verdicts into the rows. A pre-053 catalog (no
      # stamp columns — builders:refresh connects without migrating) keeps
      # the ladder-only rows rather than failing the insert.
      def stamp_shelf_stages!(catalog, rows, lects, dictionaries, shelf_dates)
        return if shelf_dates.nil? || lects.nil?

        columns = catalog.schema(:dictionary_stats, reload: true).map(&:first)
        return unless columns.include?(:lect_basis) && columns.include?(:lect_note)

        stagings = shelf_dates.stagings(catalog: catalog, registry: lects, dictionaries: dictionaries)
        rows.each do |row|
          # Every row carries both keys: multi_insert takes its column
          # list from the FIRST row, so a stamp set only on later rows
          # would be silently dropped.
          staging = stagings[row[:dictionary_id]]
          row[:lect] = staging.lect_id if staging&.staged? && lects.lect(staging.lect_id)
          row[:lect_basis] = staging&.basis
          row[:lect_note] = staging&.note
        end
      end

      private_class_method :insert_rows, :resolved_node, :stamp_shelf_stages!
    end
  end
end
