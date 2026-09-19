# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  module Health
    # The withdrawal-shed acceptance (P102-1 — Q74): the
    # quarantine-acceptance mold applied to TrendRules.withdrawal_creep.
    # A one-time reviewed upstream curation event (the specimen:
    # PerseusDL's 2026-09 Cicero cleanup, 104/549 shed on
    # perseus-latin) otherwise shouts forever — tombstones never leave
    # the denominator. `nabu health --accept-shed SLUG` books the
    # source's CURRENT shed count as owner-accepted.
    #
    # Config-file ONLY, unlike the quarantine sibling's ledger mirror:
    # the P70 posture already made the instance config the durable
    # record, and shed is measured live from the catalog (withdrawn +
    # retired document rows, themselves rebuild-stable), so there is no
    # baseline machinery to mirror. The file is
    # local/config/shed_acceptances.yml — owner rulings, append-only,
    # the LATEST row per source governs.
    #
    # The comparison semantics mirror QuarantineBaseline.creep_finding
    # exactly: at (or under, via growth-only re-arm) the accepted level
    # a would-be finding quiets to an info-grade note — quiet is never
    # silent; growth PAST the accepted level re-arms the full finding;
    # a recovery BELOW the accepted level (upstream restored content, a
    # parser fix) sends the acceptance dormant and the plain rule
    # resumes, so a real improvement is never masked.
    module ShedAcceptance
      module_function

      # Record the owner's acceptance of +slug+'s current +shed+ count.
      # Append-only; returns the accepted count.
      def accept!(path:, slug:, shed:, note: nil, now: Time.now)
        rows = acceptances(path) + [{ "source" => slug, "shed" => shed,
                                      "note" => note,
                                      "at" => now.strftime("%Y-%m-%d") }.compact]
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path,
                   "# local/config/shed_acceptances.yml — the owner's --accept-shed rulings\n" \
                   "# (Q74/P102: the durable record; withdrawal-creep alarms re-arm past the\n" \
                   "# accepted level and go dormant below it).\n" +
                   YAML.dump("acceptances" => rows))
        shed
      end

      # The governing (latest) acceptance for +slug+, or nil.
      def latest(path, slug)
        row = acceptances(path).select { |a| a["source"] == slug }.last
        return nil if row.nil?

        { shed: row["shed"], note: row["note"], at: row["at"] }
      end

      # The acceptance-aware wrapper over the plain withdrawal-creep
      # finding (the QuarantineBaseline.creep_finding rule shape).
      def finding(plain:, acceptance:, shed:)
        return plain if acceptance.nil? || acceptance[:shed] > shed # recovered: dormant
        return plain if shed > acceptance[:shed]                    # grown past: re-armed
        return nil if plain.nil?                                    # nothing to quiet: idle

        accepted_note(acceptance)
      end

      # Owner-editable file: tolerate an unquoted `at: 2026-09-18`
      # (YAML parses it as a Date, which safe_load rejects by default).
      def acceptances(path)
        return [] unless path && File.file?(path)

        (YAML.safe_load_file(path, permitted_classes: [Date]) || {}).fetch("acceptances", nil) || []
      end

      def accepted_note(acceptance)
        Finding.new(
          kind: :withdrawal_shed_accepted, severity: :info,
          message: "withdrawal shed accepted at #{acceptance[:shed]} (owner, #{acceptance[:at]}) — " \
                   "the alarm re-arms past that level"
        )
      end
    end
  end
end
