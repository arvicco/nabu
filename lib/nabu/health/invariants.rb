# frozen_string_literal: true

require_relative "trend_rules"
require_relative "quarantine_baseline"

module Nabu
  module Health
    # The mechanical postcondition invariants (P18-7): always-on checks folded
    # into `nabu health`'s per-source findings. Where TrendRules judges NUMBERS
    # against history, these judge STATE against PROMISES — every one is a
    # "the code/config says X, so the database must show Y" pairing, each
    # motivated by a real silent failure:
    #
    # - Last-run honesty: a source whose most recent ledger run FAILED is loud
    #   (the failed Coptic sync sat invisible — health showed old trends, run
    #   history only surfaced successes); a failed run that also left catalog
    #   rows behind is named a PARTIAL LOAD.
    # - Enabled-vs-populated: an enabled source with a successful run on record
    #   and zero documents AND zero dictionary entries — the half-loaded-
    #   catalog signature a crashed rebuild leaves for the sources it never
    #   reached (their ledger says ok, the fresh catalog is empty).
    # - Flag-vs-artifact: fuzzy_index flagged but the trigram index absent /
    #   empty / scope-less for the source (the flag was ON a full day with no
    #   trigram table); an axis extractor family shipping for the source but
    #   zero document_axes rows; reflex extraction shipping but zero
    #   dictionary_reflexes rows (cu shipped reflex code with 0 rows pending
    #   resync); reflex rows present but the language_names census empty.
    # - Quarantine creep: cumulative baseline-above-anchor drift (see
    #   QuarantineBaseline — the delta warning auto-advances; this is the
    #   backstop that keeps slow creep visible).
    # - Pending migrations (global): catalog / ledger schema_info behind the
    #   migration dir — read surfaces guard-degrade silently, so say it once.
    #
    # Projection diffs (registry-declared expected counts) were considered and
    # SKIPPED: nothing machine-readable states an expected count today (the
    # sources.yml counts live in sign-off comments, which rot by design), and
    # an `expected_docs:` key would be stale after every ordinary sync. The
    # enabled-vs-populated zero check plus the quarantine/withdrawal deltas
    # already cover the regression classes a projection diff would catch.
    #
    # Everything reads through raw datasets on the injected handles (the
    # Verify precedent) and degrades honestly: nil catalog/fulltext/ledger or
    # a table that predates the relevant migration produces no finding here
    # (the pending-migrations line covers the why).
    class Invariants
      # slug => the axis_source value its extractor family writes
      # (Store::AxisBuilder and axis_builder/*).
      AXIS_FAMILIES = {
        "papyri-ddbdp" => "hgv",
        "goo300k" => "goo300k",
        "imp" => "imp",
        "oracc" => "oracc",
        "torot" => "torot",
        "coptic-scriptorium" => "coptic-scriptorium",
        "edh" => "edh"
      }.freeze

      def initialize(registry:, catalog:, fulltext:, ledger:)
        @registry = registry
        @catalog = catalog
        @fulltext = fulltext
        @ledger = ledger
      end

      # All invariant findings for one registry entry, in a stable order.
      def for_source(entry)
        [
          last_run_honesty(entry),
          partial_load(entry),
          enabled_unpopulated(entry),
          fuzzy_vs_trigram(entry),
          axis_vs_rows(entry),
          reflex_vs_rows(entry),
          language_names_vs_reflexes(entry),
          QuarantineBaseline.creep_finding(@ledger, entry.slug)
        ].compact
      end

      # Library-wide findings (not tied to one source).
      def global
        [
          pending_migrations(@catalog, Store::MIGRATIONS_DIR, "catalog", "run nabu sync or nabu rebuild"),
          pending_migrations(@ledger, Store::Ledger::MIGRATIONS_DIR, "ledger", "any write path (sync) applies them")
        ].compact
      end

      private

      # -- last-run honesty ---------------------------------------------------

      def last_run_honesty(entry)
        run = latest_run(entry.slug)
        return nil unless run && run[:status] == "failed"

        detail = run[:notes].to_s.empty? ? "no error detail recorded" : run[:notes]
        Finding.new(
          kind: :failed_run, severity: :loud,
          message: "last #{run[:kind]} run FAILED (#{stamp(run[:finished_at] || run[:started_at])}): " \
                   "#{detail} — re-run"
        )
      end

      # A failed run that nonetheless journaled document/entry activity left a
      # PARTIAL load in the catalog (the 152 partial Coptic docs no one saw).
      # Provenance is the honest witness: the loaders journal every loaded/
      # revised/withdrawn/restored/retired row with a timestamp, so activity at
      # or after the failed run's start is exactly what that run wrote.
      def partial_load(entry)
        run = latest_run(entry.slug)
        return nil unless run && run[:status] == "failed" && @catalog

        touched = provenance_since(entry.slug, run[:started_at])
        return nil unless touched.positive?

        Finding.new(
          kind: :partial_load, severity: :loud,
          message: "partial load: #{touched} catalog row(s) written during the failed run — " \
                   "re-run the sync (idempotent) or rebuild"
        )
      end

      def provenance_since(slug, since)
        return 0 unless table?(@catalog, :provenance)

        source = source_row(slug)
        return 0 if source.nil?

        docs = document_provenance_since(source, since)
        docs + dictionary_provenance_since(source, since)
      end

      def document_provenance_since(source, since)
        @catalog[:provenance]
          .where { at >= since }
          .where(document_id: @catalog[:documents].where(source_id: source[:id]).select(:id))
          .count
      end

      def dictionary_provenance_since(source, since)
        return 0 unless table?(@catalog, :dictionary_entries) &&
                        @catalog[:provenance].columns.include?(:dictionary_entry_id)

        entry_ids = @catalog[:dictionary_entries]
                    .where(dictionary_id: dictionary_ids(source))
                    .select(:id)
        @catalog[:provenance].where { at >= since }.where(dictionary_entry_id: entry_ids).count
      end

      # -- enabled-vs-populated -----------------------------------------------

      def enabled_unpopulated(entry)
        return nil unless entry.enabled && @catalog && any_ok_run?(entry.slug)
        return nil if live_documents(entry.slug).positive? || dictionary_entries(entry.slug).positive?

        Finding.new(
          kind: :enabled_unpopulated, severity: :loud,
          message: "enabled with a successful run on record but zero documents/entries — " \
                   "half-loaded catalog? re-sync or rebuild"
        )
      end

      # -- flag-vs-artifact ---------------------------------------------------

      def fuzzy_vs_trigram(entry)
        return nil unless entry.fuzzy_index && @fulltext && live_documents(entry.slug).positive?

        problem = trigram_problem(entry.slug)
        return nil if problem.nil?

        Finding.new(
          kind: :fuzzy_unindexed, severity: :loud,
          message: "fuzzy_index flagged but #{problem} — reindex (any sync, or nabu rebuild)"
        )
      end

      def trigram_problem(slug)
        return "the trigram index is absent" unless @fulltext.table_exists?(Store::Indexer::TRIGRAM_TABLE)
        unless @fulltext.table_exists?(Store::Indexer::TRIGRAM_SCOPE_TABLE) &&
               @fulltext[Store::Indexer::TRIGRAM_SCOPE_TABLE].where(slug: slug).any?
          return "the source is not in the trigram scope (flag flipped since the last reindex?)"
        end
        return "the trigram index is empty" if @fulltext[Store::Indexer::TRIGRAM_TABLE].none?

        nil
      end

      def axis_vs_rows(entry)
        family = AXIS_FAMILIES[entry.slug]
        return nil unless family && @catalog && table?(@catalog, :document_axes)
        return nil unless live_documents(entry.slug).positive?
        return nil if @catalog[:document_axes].where(axis_source: family).any?

        Finding.new(
          kind: :axis_missing, severity: :loud,
          message: "axis extractor (#{family}) ships for this source but document_axes has 0 rows — " \
                   "run nabu rebuild (axes regenerate at rebuild)"
        )
      end

      def reflex_vs_rows(entry)
        return nil unless reflex_bearing?(entry) && @catalog && table?(@catalog, :dictionary_reflexes)
        return nil unless dictionary_entries(entry.slug).positive?
        return nil if reflex_rows(entry.slug).positive?

        Finding.new(
          kind: :reflexes_missing, severity: :loud,
          message: "reflex extraction ships for this adapter but dictionary_reflexes has 0 rows — " \
                   "parse-only resync (bin/nabu sync #{entry.slug} --parse-only)"
        )
      end

      def language_names_vs_reflexes(entry)
        return nil unless reflex_bearing?(entry) && @catalog && table?(@catalog, :language_names)
        return nil unless reflex_rows(entry.slug).positive?

        source = source_row(entry.slug)
        return nil if @catalog[:language_names].where(dictionary_id: dictionary_ids(source)).any?

        Finding.new(
          kind: :language_census_missing, severity: :loud,
          message: "reflex rows present but the language_names census is empty — " \
                   "parse-only resync (bin/nabu sync #{entry.slug} --parse-only)"
        )
      end

      # -- pending migrations (global) -----------------------------------------

      def pending_migrations(db, dir, label, remedy)
        return nil if db.nil? || !table?(db, :schema_info)

        applied = db[:schema_info].get(:version).to_i
        latest = Dir[File.join(dir, "*.rb")].map { |path| File.basename(path).to_i }.max.to_i
        return nil if applied >= latest

        Finding.new(
          kind: :pending_migrations, severity: :soft,
          message: "#{label} migrations pending: schema at #{applied}, latest is #{latest} — #{remedy}"
        )
      end

      # -- shared lookups -------------------------------------------------------

      def latest_run(slug)
        return nil unless table?(@ledger, :runs)

        @ledger[:runs].where(source_slug: slug).order(Sequel.desc(:id)).first
      end

      def any_ok_run?(slug)
        return false unless table?(@ledger, :runs)

        @ledger[:runs].where(source_slug: slug, status: "succeeded").any?
      end

      def source_row(slug)
        return nil unless table?(@catalog, :sources)

        @catalog[:sources].where(slug: slug).select(:id).first
      end

      def live_documents(slug)
        source = source_row(slug)
        return 0 if source.nil? || !table?(@catalog, :documents)

        @catalog[:documents].where(source_id: source[:id], withdrawn: false).count
      end

      def dictionary_entries(slug)
        source = source_row(slug)
        return 0 if source.nil? || !table?(@catalog, :dictionary_entries)

        @catalog[:dictionary_entries].where(dictionary_id: dictionary_ids(source), withdrawn: false).count
      end

      def reflex_rows(slug)
        source = source_row(slug)
        return 0 if source.nil? || !table?(@catalog, :dictionary_reflexes)

        entry_ids = @catalog[:dictionary_entries].where(dictionary_id: dictionary_ids(source)).select(:id)
        @catalog[:dictionary_reflexes].where(dictionary_entry_id: entry_ids).count
      end

      def dictionary_ids(source)
        @catalog[:dictionaries].where(source_id: source[:id]).select(:id)
      end

      # The adapter's declaration that its parser extracts reflexes. Resolution
      # can fail for an unloadable adapter class — health must report on, not
      # crash over, a misconfigured registry line, so that reads as "no".
      def reflex_bearing?(entry)
        klass = entry.adapter_class
        klass.respond_to?(:reflex_bearing?) && klass.reflex_bearing?
      rescue Nabu::ValidationError
        false
      end

      def table?(db, name)
        !db.nil? && db.table_exists?(name)
      end

      def stamp(time)
        time.respond_to?(:strftime) ? time.strftime("%Y-%m-%d %H:%M") : time.to_s
      end
    end
  end
end
