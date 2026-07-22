# frozen_string_literal: true

module Nabu
  module Ops
    # `rake stamps:rebless` (P39-1) — the owner-only escape hatch after a
    # fingerprint FORMULA change (a new digest scheme, not new derivation
    # semantics): recompute every source's DerivationFingerprint against
    # current code and REWRITE its stored stamp, deriving nothing. Without
    # it, a formula change reads every stamp dirty and the next
    # `rebuild --incremental` degenerates into a full multi-hour rebuild
    # that reproduces byte-identical rows (the P38→P39-1 situation).
    #
    # DANGEROUS BY NATURE. A stamp is a promise that a replay of current
    # canonical through current code produced the catalog's rows; rebless
    # mints that promise WITHOUT the replay. It is valid ONLY immediately
    # after a verified full rebuild on an unchanged canonical tree + code
    # that differs solely in fingerprint bookkeeping. Misused — canonical
    # or derivation code changed since the last full rebuild — it blesses
    # rows the code would no longer produce, and every future incremental
    # silently skips the drift: under-derivation with no error anywhere.
    # Hence the attestation gate: the caller must pass ATTESTATION verbatim,
    # and the refusal message re-explains the blast radius every time.
    #
    # Lives in ops/ deliberately: ops/ is excluded from the fingerprint's
    # shared core, so shipping this tool does not itself dirty any stamp.
    class StampRebless
      ATTESTATION = "i-verified-current-full-rebuild"

      def initialize(config:, registry:)
        @config = config
        @registry = registry
      end

      # Rewrite every replayable source's stamp; print each rewrite to +out+.
      # Raises Nabu::Error on a missing/refused attestation, a missing
      # catalog, or catalog/code schema drift (a landed migration means the
      # derived shapes may differ — nothing to rebless; full rebuild).
      def run(attestation:, out: $stdout)
        refuse_attestation!(attestation)
        refuse_catalog!
        db = Store.connect(@config.catalog_path)
        rebless_all(db, out)
      ensure
        db&.disconnect
      end

      private

      def refuse_attestation!(attestation)
        return if attestation == ATTESTATION

        raise Nabu::Error,
              "stamps:rebless REFUSED. This rewrites every derivation stamp against current " \
              "code WITHOUT re-deriving anything — valid ONLY immediately after a verified " \
              "full rebuild on unchanged canonical. Misuse blesses rows current code would " \
              "not produce, and every future incremental silently skips the drift " \
              "(under-derivation, no error anywhere); when in doubt run a full rebuild. " \
              "If — and only if — the last full rebuild is verified current, run: " \
              "rake \"stamps:rebless[#{ATTESTATION}]\""
      end

      def refuse_catalog!
        return if File.exist?(@config.catalog_path)

        raise Nabu::Error,
              "no catalog at #{@config.catalog_path} — nothing to rebless; full rebuild required"
      end

      def rebless_all(db, out)
        refuse_schema_drift!(db)
        fingerprints = DerivationFingerprint.new(config: @config)
        @registry.each_source do |entry|
          next out.puts("  skip    #{entry.slug} (no canonical data)") unless replayable?(entry)

          rebless_source(db, fingerprints, entry, out)
        end
        report_orphans(db, out)
      end

      def rebless_source(db, fingerprints, entry, out)
        old_stamp = Store::DerivationStamp.fetch(db, entry.slug)
        languages = Store::DerivationStamp.derived_languages(db, entry.slug)
        fingerprint = fingerprints.for_source(entry, languages: languages)
        Store::DerivationStamp.stamp!(db, slug: entry.slug, fingerprint: fingerprint)
        old_short = old_stamp ? old_stamp[:fingerprint][0, 12] : "(unstamped)"
        if fingerprint.weak?
          out.puts "  cleared #{entry.slug} #{old_short} -> (weak identity — never skipped)"
        else
          out.puts "  rebless #{entry.slug} #{old_short} -> #{fingerprint.short}"
        end
      end

      def refuse_schema_drift!(db)
        applied = db.table_exists?(:schema_info) ? db[:schema_info].get(:version).to_i : 0
        latest = DerivationFingerprint.migration_level
        return if applied == latest

        raise Nabu::Error,
              "catalog schema v#{applied} != code v#{latest} — a migration landed; " \
              "there is nothing to rebless: full rebuild required"
      end

      # Stamps for slugs with no replayable canonical tree are left alone and
      # reported: incremental refuses on them anyway, and deleting evidence
      # is not this tool's job.
      def report_orphans(db, out)
        replayable = @registry.each_source.select { |entry| replayable?(entry) }.map(&:slug)
        orphans = Store::DerivationStamp.slugs(db) - replayable
        orphans.each do |slug|
          out.puts "  orphan  #{slug} (stamp with no replayable canonical — left untouched; " \
                   "incremental will refuse until resolved)"
        end
      end

      # Same rule as Rebuild#replayable?: local canonical data exists.
      def replayable?(entry)
        dir = File.join(@config.canonical_dir, entry.slug)
        Dir.exist?(dir) && !Dir.empty?(dir)
      end
    end
  end
end
