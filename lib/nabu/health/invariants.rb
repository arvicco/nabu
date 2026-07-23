# frozen_string_literal: true

require "digest"
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
    # - Synced-vs-populated: a source whose LATEST run succeeded but which
    #   holds zero rows in its grain (documents, dictionary entries, language
    #   records) — the half-loaded-catalog signature a crashed rebuild leaves
    #   for the sources it never reached (their ledger says ok, the fresh
    #   catalog is empty). Enablement is deliberately NOT a gate (P23-3a): the
    #   liv case (2026-07-14) was a DISABLED source synced anyway to zero
    #   entries, silent because the original enabled-vs-populated check
    #   watched enabled sources only. A succeeded run promises rows whatever
    #   the flag says. No exemption mechanism ships: the 2026-07-15 census of
    #   the live catalog found every source populated in its own grain
    #   (local-language holds language_records — the grain routing below), so
    #   an honestly-empty-by-design source does not exist to exempt.
    # - Flag-vs-artifact: fuzzy_index flagged but the trigram index absent /
    #   empty / scope-less for the source (the flag was ON a full day with no
    #   trigram table); a timeline extractor family shipping for the source but
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
    # synced-vs-populated zero check plus the quarantine/withdrawal deltas
    # already cover the regression classes a projection diff would catch.
    #
    # Everything reads through raw datasets on the injected handles (the
    # Verify precedent) and degrades honestly: nil catalog/fulltext/ledger or
    # a table that predates the relevant migration produces no finding here
    # (the pending-migrations line covers the why).
    class Invariants
      # slug => the axis_source value its extractor family writes
      # (Store::TimelineBuilder and timeline_builder/*).
      AXIS_FAMILIES = {
        "papyri-ddbdp" => "hgv",
        "goo300k" => "goo300k",
        "imp" => "imp",
        "oracc" => "oracc",
        "torot" => "torot",
        "coptic-scriptorium" => "coptic-scriptorium",
        "edh" => "edh"
      }.freeze

      # +canonical_dir+ (P19-1) roots the local-shelf checks (dossier files
      # vs derived records; pinned files vs the tree); nil (callers that
      # cannot name the corpus root) skips them honestly. +now+ picks the
      # D42-a rotation slot (injected so the probe is testable).
      def initialize(registry:, catalog:, fulltext:, ledger:, canonical_dir: nil, now: Time.now)
        @registry = registry
        @catalog = catalog
        @fulltext = fulltext
        @ledger = ledger
        @canonical_dir = canonical_dir
        @now = now
      end

      # All invariant findings for one registry entry, in a stable order.
      def for_source(entry)
        [
          last_run_honesty(entry),
          partial_load(entry),
          synced_unpopulated(entry),
          fuzzy_vs_trigram(entry),
          timeline_vs_rows(entry),
          reflex_vs_rows(entry),
          language_names_vs_reflexes(entry),
          dossiers_vs_records(entry),
          *local_shelf_integrity(entry),
          QuarantineBaseline.creep_finding(@ledger, entry.slug)
        ].compact
      end

      # Library-wide findings (not tied to one source).
      def global
        [
          pending_migrations(@catalog, Store::MIGRATIONS_DIR, "catalog", "run nabu sync or nabu rebuild"),
          pending_migrations(@ledger, Store::Ledger::MIGRATIONS_DIR, "ledger", "any write path (sync) applies them"),
          stats_drift
        ].compact
      end

      # Dossier-shelf content kind => its derived catalog table (P19-1 the
      # language shelf, P24-0 the source shelf).
      DOSSIER_TABLES = { language: :language_records, source: :source_records,
                         notes: :urn_notes }.freeze

      # D42-a: above this many stats-claimed live passages the drift probe
      # stays at the document grain for the day's source — the passage truth
      # is a real count over the passages join, cheap for small/mid shelves,
      # seconds-scale for the giants; the doc grain (indexed counts) still
      # watches every source.
      # census: 2000000, 2026-07-23, ~3% of the 62.8M-passage live corpus
      # (the P41 scale review's census) — an indexed live-on-live join count
      # at this size stays low-seconds, health's budget for one probe
      STATS_PASSAGE_PROBE_CAP = 2_000_000

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

      # -- synced-vs-populated ------------------------------------------------

      # Gates on the LATEST run having succeeded (a failed latest run is
      # last_run_honesty's one loud line, not two), and NEVER on `enabled` —
      # class note (the liv case).
      def synced_unpopulated(entry)
        return nil unless @catalog && latest_run(entry.slug)&.fetch(:status) == "succeeded"
        return nil if populated?(entry)

        Finding.new(
          kind: :synced_unpopulated, severity: :loud,
          message: "latest run succeeded but zero documents/entries/records held " \
                   "(enabled or not — a succeeded run promises rows) — " \
                   "half-loaded catalog or synced-to-nothing? re-sync or rebuild"
        )
      end

      # What "populated" means is content-kind-shaped (P19-1/P24-0): a
      # dossier-class shelf's artifact is its derived records rows (it owns them —
      # the shelf is their only writer), everything else documents/entries.
      def populated?(entry)
        kind = content_kind(entry)
        return derived_records(kind).positive? if DOSSIER_TABLES.key?(kind)

        live_documents(entry.slug).positive? || dictionary_entries(entry.slug).positive?
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

      def timeline_vs_rows(entry)
        family = AXIS_FAMILIES[entry.slug]
        return nil unless family && @catalog && table?(@catalog, :document_axes)
        return nil unless live_documents(entry.slug).positive?
        return nil if @catalog[:document_axes].where(axis_source: family).any?

        Finding.new(
          kind: :timeline_missing, severity: :loud,
          message: "timeline extractor (#{family}) ships for this source but document_axes has 0 rows — " \
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

      # -- local shelves (P19-1) -------------------------------------------------

      # Flag-vs-artifact, the dossier family: dossier FILES on disk with a
      # successful run on record but ZERO derived language records — the
      # local-shelf variant of the half-loaded-catalog signature (the files
      # are the flag, the records the artifact).
      def dossiers_vs_records(entry)
        kind = content_kind(entry)
        return nil unless DOSSIER_TABLES.key?(kind) && @canonical_dir && @catalog
        return nil unless table?(@catalog, DOSSIER_TABLES.fetch(kind)) && any_ok_run?(entry.slug)
        return nil if dossier_files(entry.slug).zero? || derived_records(kind).positive?

        Finding.new(
          kind: :dossiers_unindexed, severity: :loud,
          message: "dossier files on disk but zero derived #{kind} records — " \
                   "re-sync (bin/nabu sync #{entry.slug}) or rebuild"
        )
      end

      # The per-file integrity check the LocalFetch pins exist for: every
      # "local:<relpath>" → sha256 ledger pin (a kind: shelf memory shelf, or a
      # vendored no-git source like sabellic-loans — P39-0) is held against the
      # canonical tree. A source with no such pins yields nothing. A pinned file
      # that is
      # neither live nor in the attic VANISHED (loud — restore from backup,
      # or move to .attic/ to retire deliberately); a live file whose bytes
      # changed since the last scan is STALE derivation, not corruption —
      # owner edits are the shelf's whole point — so it reads soft, naming
      # the re-scan that re-derives and re-pins.
      def local_shelf_integrity(entry)
        return [] unless @canonical_dir && table?(@ledger, :pins)

        vanished, changed = partition_local_pins(entry.slug)
        findings = []
        unless vanished.empty?
          findings << Finding.new(
            kind: :dossiers_vanished, severity: :loud,
            message: "#{vanished.size} pinned file(s) missing from canonical/#{entry.slug} " \
                     "(no attic copy): #{vanished.join(', ')} — restore from backup, " \
                     "or move to .attic/ to retire"
          )
        end
        unless changed.empty?
          findings << Finding.new(
            kind: :dossiers_stale, severity: :soft,
            message: "#{changed.size} file(s) edited since the last scan (#{changed.join(', ')}) — " \
                     "bin/nabu sync #{entry.slug} re-derives and re-pins"
          )
        end
        findings
      end

      def partition_local_pins(slug)
        vanished = []
        changed = []
        workdir = File.join(@canonical_dir, slug)
        local_pins(slug).each do |rel, sha|
          live = File.join(workdir, rel)
          if File.file?(live)
            changed << rel unless Digest::SHA256.file(live).hexdigest == sha
          elsif !File.file?(File.join(workdir, Nabu::Adapter::ATTIC_DIRNAME, rel))
            vanished << rel
          end
        end
        [vanished.sort, changed.sort]
      end

      # { relpath => sha } from the source's "local:" ledger pins.
      def local_pins(slug)
        @ledger[:pins]
          .where(source_slug: slug)
          .where(Sequel.like(:repo_url, "local:%"))
          .to_h { |row| [row[:repo_url].delete_prefix("local:"), row[:last_sync_sha]] }
      end

      # -- source_stats drift (D42-a, global) ----------------------------------

      # The D42-a contract: source_stats is DERIVED and the LOADER is its
      # only writer (rebuild re-derives wholesale). This probe holds ONE
      # rotating source per run against its true counts — O(one source),
      # never the corpus, so `nabu health` stays cheap while any write path
      # that bypassed the loader (or a stats bug) surfaces loudly within a
      # rotation. A catalog predating migration 019 has no table and
      # produces nothing here (pending_migrations already says why).
      def stats_drift
        return nil unless table?(@catalog, :source_stats) && table?(@catalog, :sources)

        sources = @catalog[:sources].order(:id).select_map(%i[id slug])
        return nil if sources.empty?

        id, slug = sources[@now.yday % sources.size]
        drift = stats_drift_pairs(id)
        return nil if drift.empty?

        detail = drift.map { |field, (stated, actual)| "#{field} stats=#{stated} actual=#{actual}" }.join(", ")
        Finding.new(
          kind: :stats_drift, severity: :loud,
          message: "source_stats drift on #{slug}: #{detail} — stats are derived and " \
                   "loader-maintained; a write path bypassed the loader (a bug — report it). " \
                   "nabu rebuild (or rebuild --incremental) re-derives"
        )
      end

      # {field => [stated, actual]} for the day's source: the document grain
      # always, the passage grain only under the cap and only when the doc
      # grain is already clean (one loud line at a time).
      def stats_drift_pairs(source_id)
        stats = Store::SourceStats.fetch(@catalog, source_id)
        drift = Store::SourceStats.document_truth(@catalog, source_id).filter_map do |field, actual|
          [field, [stats.fetch(field), actual]] if stats.fetch(field) != actual
        end.to_h
        if drift.empty? && stats.fetch(:live_passages) <= STATS_PASSAGE_PROBE_CAP
          actual = Store::SourceStats.passage_truth(@catalog, source_id)
          drift[:live_passages] = [stats.fetch(:live_passages), actual] if stats.fetch(:live_passages) != actual
        end
        drift
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

      # Same tolerance for the content kind: an unloadable adapter class
      # reads as the plain passage default.
      def content_kind(entry)
        entry.adapter_class.content_kind
      rescue Nabu::ValidationError
        :passages
      end

      def derived_records(kind)
        table = DOSSIER_TABLES.fetch(kind)
        return 0 unless table?(@catalog, table)

        @catalog[table].count
      end

      def urn_notes
        return 0 unless table?(@catalog, :urn_notes)

        @catalog[:urn_notes].count
      end

      def dossier_files(slug)
        Dir.glob(File.join(@canonical_dir, slug, "*.md")).size
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
