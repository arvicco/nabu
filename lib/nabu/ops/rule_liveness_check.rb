# frozen_string_literal: true

# The full entrypoint (the AcquisitionCheck note): Store and LectRules only
# load in nabu.rb's order.
require_relative "../../nabu"

module Nabu
  module Ops
    # The declared-rule liveness probe (`rake boards:check`): a facet rule
    # in config/lect_facet_rules.yml is inert until `nabu lect apply-rules`
    # compiles it into the lect journal, so a rule can ship in config and
    # never stage a single document (a P178 era rule sat uncompiled through
    # a gate — 41 documents unstaged until a verification pass caught it).
    # The probe fails BY NAME on any declared rule one of whose sources
    # holds live (non-withdrawn) documents of the rule's code while the
    # journal carries zero rows of its making. Evidence of making: a map
    # rule's rows bear basis "rule:<id>"; a compose rule keeps its base
    # rule's basis and leaves "(rule:<id>)" in the refined row's note
    # (LectRules#compose_apply). Read-only; a box without the catalog, the
    # journal or the rules file gets an announced skip, never a failure.
    class RuleLivenessCheck
      Report = Data.define(:skipped, :findings, :rules) do
        def clean? = findings.empty?
      end

      def initialize(rules_paths:, catalog_path:, journal_path:)
        @rules_paths = rules_paths
        @catalog_path = catalog_path
        @journal_path = journal_path
      end

      def run
        rules = LectRules.load(@rules_paths)
        return Report.new(skipped: true, findings: [], rules: 0) unless
          rules && File.exist?(@catalog_path) && File.exist?(@journal_path)

        findings = with_stores do |catalog, journal|
          rules.rules.filter_map do |rule|
            live = live_sources(catalog, rule)
            next if live.empty? || staged?(journal, rule)

            "declared rule #{rule.id} (#{live.join(', ')}) has never produced a staging — " \
              "run `nabu lect apply-rules --rule #{rule.id}`"
          end
        end
        Report.new(skipped: false, findings: findings, rules: rules.rules.size)
      end

      private

      def with_stores
        catalog = Nabu::Store.connect(@catalog_path, readonly: true)
        journal = Nabu::Store.connect(@journal_path, readonly: true)
        yield catalog, journal
      ensure
        catalog&.disconnect
        journal&.disconnect
      end

      def live_sources(catalog, rule)
        rule.sources.select do |slug|
          source = catalog[:sources].first(slug: slug) or next false
          !catalog[:documents].where(source_id: source[:id], language: rule.code, withdrawn: false).empty?
        end
      end

      def staged?(journal, rule)
        rows = journal[:lect_assignments]
        evidence =
          if rule.compose?
            rows.where(Sequel.like(:note, "%(rule:#{rule.id})%"))
          else
            rows.where(basis: "rule:#{rule.id}")
          end
        !evidence.empty?
      end
    end
  end
end
