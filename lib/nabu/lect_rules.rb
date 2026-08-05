# frozen_string_literal: true

require "yaml"

module Nabu
  # The facet→lect rules compiler (P58-2): owner-ratified declarative rules
  # (config/lect_facet_rules.yml) mapping one source-set's facet values onto
  # lects — the DOCUMENT-GROUP grain of lect assignment (a period label, a
  # corpus slice). Rules are COMPILED into per-document journal rows
  # (Store::LectJournal, basis "rule:<id>", note = the verbatim facet value
  # as evidence), never resolved live: resolve() stays pure, every
  # assignment is inspectable in one place, and a re-run supersedes exactly
  # its own basis while an existing (urn, code) row — a hand ruling, another
  # rule — is never overwritten.
  #
  # Matching: #normalize_value strips parentheticals ("Old Babylonian
  # (ca. 1900-1600 BC)" → "Old Babylonian") and a trailing cataloguer's "?"
  # then requires an EXACT map-key match. Compound datings normalize to
  # something no key matches — deliberately unmatched, reported, bare.
  class LectRules
    Rule = Data.define(:id, :sources, :code, :facet, :map, :tier, :note)
    CensusReport = Data.define(:matched, :unmatched, :assignable)
    ApplyOutcome = Data.define(:assigned, :skipped)

    # const: SQLite bound-parameter comfort for the journal bulk insert
    INSERT_BATCH = 1_000

    # nil when the rules file is absent (the feature-module posture: no
    # file, no rules, no behavior change).
    def self.load(path)
      return nil unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      rules = (raw["rules"] || []).map do |entry|
        Rule.new(id: entry.fetch("id"), sources: Array(entry["sources"]).map(&:to_s),
                 code: entry.fetch("code"), facet: entry.fetch("facet"),
                 map: entry.fetch("map"), tier: entry["tier"], note: entry["note"])
      end
      new(rules: rules)
    end

    def self.normalize_value(raw)
      raw.to_s.gsub(/\([^)]*\)/, " ").gsub(/\s+/, " ").strip.sub(/\s*\?\z/, "")
    end

    def initialize(rules:)
      @rules = rules
    end

    attr_reader :rules

    def find(id)
      rules.find { |rule| rule.id == id }
    end

    # Every map target must be a lect the registry defines — the same
    # never-silently-coerced rule the journal CLI enforces, applied to the
    # whole file before any census or write.
    def validate!(registry)
      rules.each do |rule|
        rule.map.each_value do |target|
          next if registry.lect(target)

          raise Nabu::Error, "lect rule #{rule.id}: map target #{target.inspect} " \
                             "is not defined in the nabu-lects registry"
        end
      end
    end

    # The dry-run view: {[normalized value, lect] => docs} for map hits,
    # {normalized value => docs} for misses, and the assignable total —
    # counted over DISTINCT documents (a document with a duplicated facet
    # row censuses once).
    def census(rule, catalog:)
      matched = Hash.new(0)
      unmatched = Hash.new(0)
      each_candidate(rule, catalog) do |_urn, normalized, lect_id|
        if lect_id
          matched[[normalized, lect_id]] += 1
        else
          unmatched[normalized] += 1
        end
      end
      CensusReport.new(matched: matched, unmatched: unmatched, assignable: matched.values.sum)
    end

    # Compile the rule into the journal: supersede the rule's own prior rows,
    # then insert one row per matched document — EXCEPT documents that
    # already carry a (urn, code) assignment from any other basis (hand
    # rulings and sibling rules always win; counted as skipped).
    def apply!(rule, catalog:, journal:, at: Time.now)
      Store::LectJournal.supersede_basis!(journal, basis: basis_for(rule))
      rows = []
      each_candidate(rule, catalog) do |urn, normalized, lect_id|
        if lect_id
          rows << { urn: urn, code: rule.code, lect_id: lect_id, basis: basis_for(rule),
                    note: normalized, created_at: at }
        end
      end
      taken = journal[:lect_assignments].where(code: rule.code).select_map(:urn).to_set
      fresh = rows.reject { |row| taken.include?(row[:urn]) }
      fresh.each_slice(INSERT_BATCH) { |slice| journal[:lect_assignments].multi_insert(slice) }
      ApplyOutcome.new(assigned: fresh.size, skipped: rows.size - fresh.size)
    end

    def basis_for(rule)
      "rule:#{rule.id}"
    end

    private

    # One yield per DISTINCT (document, facet-value) candidate: documents of
    # the rule's code, in the rule's sources, carrying the rule's facet.
    # NOTE the verbatim value is normalized before both map lookup and note.
    def each_candidate(rule, catalog)
      seen = Set.new
      catalog[:documents]
        .join(:sources, id: :source_id)
        .join(:document_facets, document_id: Sequel[:documents][:id])
        .where(Sequel[:sources][:slug] => rule.sources,
               Sequel[:documents][:language] => rule.code,
               Sequel[:documents][:withdrawn] => false,
               Sequel[:document_facets][:facet] => rule.facet)
        .select(Sequel[:documents][:urn], Sequel[:document_facets][:value])
        .each do |row|
          next unless seen.add?(row[:urn])

          normalized = self.class.normalize_value(row[:value])
          yield row[:urn], normalized, rule.map[normalized]
        end
    end
  end
end
