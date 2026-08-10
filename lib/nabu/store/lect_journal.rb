# frozen_string_literal: true

require "fileutils"

module Nabu
  module Store
    # The lect-assignment journal: db/lects.sqlite3 (P58-1). Persists the
    # per-document overlay tier of Nabu::Lects#resolve — one CURRENT
    # (urn, code) → lect-id assignment per row, `basis` "owner" for hand
    # rulings vs "rule:<id>" for compiled batches (P58-2 apply-rules,
    # P58-3 infer-dates), which a rule re-run supersedes wholesale without
    # ever touching a hand ruling.
    #
    # LinksJournal mechanics throughout (see that module's host argument):
    # own forward-only migration track (db/lects_migrate), urn keying
    # because rebuilds re-mint catalog ids, absent file = empty state,
    # `nabu rebuild` never touches it. Unlike links, losing this file loses
    # RULINGS, not re-minable derivations — backups should include it
    # (`nabu lect list --format tsv` is the flat export).
    #
    # The read side is the lazy Overlay: Lects#resolve only ever asks
    # +@overlay[urn]+, so a DB-backed object with `[]` (point lookup on the
    # unique (urn, code) index, memoized) slots into the P57-3 seam
    # unchanged — no eager hash of a 6-figure-row journal at CLI start.
    module LectJournal
      MIGRATIONS_DIR = File.expand_path("../../../db/lects_migrate", __dir__)

      module_function

      def connect(url, readonly: false) = Store.connect(url, readonly: readonly)

      # Apply pending journal migrations (db/lects_migrate) to +db+.
      def migrate!(db)
        require "sequel/extensions/migration"
        Sequel::Migrator.run(db, MIGRATIONS_DIR)
        db
      end

      # The write-path opener: create the file if absent, migrate forward.
      def open!(path)
        FileUtils.mkdir_p(File.dirname(path))
        migrate!(connect(path))
      end

      # The read-path opener: nil when the file is absent (nothing has ever
      # been assigned — readers treat that as "no overlay", never an error).
      def open_readonly(path)
        return nil unless File.exist?(path)

        connect(path, readonly: true)
      end

      # Upsert the CURRENT assignment for (urn, code). Returns :inserted or
      # :updated. Grammar is checked here (an unparseable lect id never
      # enters the journal); registry EXISTENCE is the CLI's duty — the
      # journal must stay readable even while the registry evolves ahead of
      # it (the pre-1.0 instability window).
      def assign!(db, urn:, code:, lect_id:, basis:, note: nil, at: Time.now)
        urn = urn.to_s.strip
        code = code.to_s.strip
        raise ArgumentError, "urn and code must be non-empty" if urn.empty? || code.empty?
        raise ArgumentError, "not a lect id: #{lect_id.inspect} (anchor[:stage][/variety][@ortho])" unless
          Nabu::Lects.parse_id(lect_id)

        fresh = { lect_id: lect_id.to_s, basis: basis.to_s, note: note, created_at: at }
        return :updated if db[:lect_assignments].where(urn: urn, code: code).update(fresh) == 1

        db[:lect_assignments].insert(urn: urn, code: code, **fresh)
        :inserted
      end

      # Remove assignments for +urn+ — all codes, or just +code+. Returns the
      # count removed.
      def withdraw!(db, urn:, code: nil)
        scope = db[:lect_assignments].where(urn: urn)
        scope = scope.where(code: code) if code
        scope.delete
      end

      # Delete every row a given rule minted — the re-run discipline
      # (LinksJournal#supersede!): a rule's next apply states the CURRENT
      # compilation of that rule, and hand rulings ("owner") are untouchable
      # by construction. Returns the count removed.
      # P70 (the derivability contract): re-mint the WHOLE journal from
      # the two-folder truth — config/lect_rulings.yml (owner rows), the
      # compiled rules (config/lect_facet_rules.yml over the catalog), and
      # infer-dates (catalog dates × the registry's stage bands). The
      # journal is thereby formally DERIVED: `nabu rebuild` calls this
      # before facet materialization, and losing db/lects.sqlite3 loses
      # nothing the backup cannot restore. Returns {owner:, rules:,
      # dates:} counts.
      def rederive!(db, catalog:, config:)
        db[:lect_assignments].delete
        owner = Nabu::LectRulings.apply!(config.lect_rulings_path, journal: db)
        rules_applied = 0
        if (rules = Nabu::LectRules.load(config.lect_facet_rules_path))
          rules.rules.each do |rule|
            outcome = rules.apply!(rule, catalog: catalog, journal: db)
            rules_applied += outcome.assigned
          end
        end
        registry = Nabu::Lects.load_default(config: config)
        dates = registry ? Nabu::LectDates.new(registry: registry).apply!(catalog: catalog, journal: db).assigned : 0
        { owner: owner, rules: rules_applied, dates: dates }
      end

      def supersede_basis!(db, basis:)
        db[:lect_assignments].where(basis: basis).delete
      end

      # {code => lect_id} for one urn ({} when unassigned) — the eager
      # single-document read (show/inspect surfaces).
      def overlay_for(db, urn)
        db[:lect_assignments].where(urn: urn).select_hash(:code, :lect_id)
      end

      # Journal census by basis — the `nabu lect list` footer and the
      # dry-run reports' "already assigned" arithmetic.
      def counts_by_basis(db)
        db[:lect_assignments].group_and_count(:basis).as_hash(:basis, :count)
      end

      # The lazy per-document overlay for Nabu::Lects#resolve: +[](urn)+ →
      # {code => lect_id}, or nil for a miss (the resolve contract). Point
      # lookups ride the unique (urn, code) index; results memoize because
      # display paths re-resolve the same page of urns repeatedly.
      class Overlay
        # const: memo bound — a page of results touches tens of urns; the cap
        # only guards a pathological full-corpus sweep from unbounded growth
        MAX_MEMO = 10_000

        def initialize(db)
          @db = db
          @memo = {}
        end

        def [](urn)
          @memo.clear if @memo.size >= MAX_MEMO
          return @memo[urn] if @memo.key?(urn)

          map = LectJournal.overlay_for(@db, urn)
          @memo[urn] = map.empty? ? nil : map
        end
      end
    end
  end
end
