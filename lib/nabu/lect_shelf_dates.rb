# frozen_string_literal: true

require "yaml"
require_relative "lect_dates"

module Nabu
  # The dictionary SHELF grain of date-band staging. Dictionary lect
  # resolution otherwise runs at (shelf language, source) grain only — a
  # source-wide override names one lect for every shelf of a code — but a
  # dictionary source whose shelves carry their work's own year (LEME:
  # lexicon_year on every entry, 1477–1755) is staged per shelf by the
  # document grain's own law (Nabu::LectDates#infer, shared, so the grains
  # cannot drift):
  #
  #   1. the shelf's code resolves to a BARE anchor at source grain (an
  #      override or codemap stage is already the finer statement);
  #   2. the shelf's year values hull into a CLOSED interval ("1604" →
  #      1604..1604, "1475–1500" → 1475..1500; MIN/MAX over the distinct
  #      values its live entries carry — entries without the field are
  #      ignored, the SQL MIN/MAX stance of the document grain);
  #   3. the interval is CONTAINED IN EXACTLY ONE attested banded stage.
  #
  # Anything else — no year (:undated), a value that is not a year or
  # year range (:unparsed_year), a year no band reaches (:outside_bands),
  # a year on a shared band edge or straddling stages (:spans_bands) —
  # keeps the bare code, the reason declared in the note. Staged shelves
  # carry basis rule:date-band (the document grain's basis) and the
  # dating evidence as their note.
  #
  # Rules live in config/lect_facet_rules.yml under dictionary_date_bands:
  # (the overlay pair, same-id replacement — the LectRules stance). Each
  # names its sources, the shelf codes it may stage (a dictionary's year
  # dates its compiler's own language, never the classical headwords of a
  # Latin or Greek dictionary — so codes are opt-in, never "all"), and the
  # entry annotation field carrying the shelf's year.
  #
  # Read by Store::DictionaryStats, which stamps the verdict on the
  # dictionary_stats row (lect, lect_basis, lect_note).
  class LectShelfDates
    BASIS = LectDates::BASIS
    CONFIG_KEY = "dictionary_date_bands"
    FIELD_NAME = /\A[a-z_][a-z0-9_]*\z/
    YEAR = /\A(-?\d{1,4})\z/
    YEAR_RANGE = /\A(-?\d{1,4})\s*[–-]\s*(-?\d{1,4})\z/
    private_constant :FIELD_NAME, :YEAR, :YEAR_RANGE

    Rule = Data.define(:id, :sources, :codes, :field, :note)

    # One covered shelf's verdict: +lect_id+ when staged, else nil and the
    # +reason+ it stayed bare.
    Staging = Data.define(:dictionary_id, :rule_id, :source, :code, :field, :lect_id, :reason,
                          :not_before, :not_after) do
      def staged? = !lect_id.nil?

      def interval = [not_before, not_after]

      def basis = staged? ? BASIS : nil

      def note
        dated = not_before && not_after ? "dated #{not_before}..#{not_after} (#{field})" : nil
        return dated if staged?

        ["bare: #{reason.to_s.tr('_', ' ')}", dated].compact.join(" — ")
      end
    end

    # nil when no rules file exists (the feature-module posture); a file
    # without the section loads an empty rule set.
    def self.load(path)
      paths = Array(path).select { |p| File.file?(p) }
      return nil if paths.empty?

      merged = paths.each_with_object({}) do |file, by_id|
        raw = YAML.safe_load_file(file) || {}
        (raw[CONFIG_KEY] || []).each { |entry| by_id[entry.fetch("id")] = entry }
      end
      new(rules: merged.values.map { |entry| build_rule(entry) })
    end

    def self.load_default(config:)
      load(config.lect_facet_rules_paths)
    end

    def self.build_rule(entry)
      field = entry.fetch("field").to_s
      unless field.match?(FIELD_NAME)
        raise Nabu::Error, "dictionary date-band rule #{entry['id']}: field #{field.inspect} is not an annotation name"
      end

      Rule.new(id: entry.fetch("id"), sources: Array(entry.fetch("sources")).map(&:to_s),
               codes: Array(entry.fetch("codes")).map(&:to_s), field: field, note: entry["note"])
    end
    private_class_method :build_rule

    # "1604" → [1604, 1604]; "1475–1500" / "1475-1500" → [1475, 1500];
    # anything else nil.
    def self.parse_year(value)
      text = value.to_s.strip
      if (single = text.match(YEAR))
        year = Integer(single[1], 10)
        [year, year]
      elsif (range = text.match(YEAR_RANGE))
        [Integer(range[1], 10), Integer(range[2], 10)]
      end
    end

    def initialize(rules:)
      @rules = rules
    end

    attr_reader :rules

    # Every covered code must be a node the registry defines — the
    # never-silently-coerced rule LectRules#validate! enforces for targets.
    def validate!(registry)
      rules.each do |rule|
        rule.codes.each do |code|
          next if registry.lect(code)

          raise Nabu::Error, "dictionary date-band rule #{rule.id}: code #{code.inspect} " \
                             "is not defined in the nabu-lects registry"
        end
      end
    end

    # {dictionary_id => Staging} for every shelf a rule covers within
    # +dictionaries+ (a dataset over the dictionaries table, default all —
    # its filters qualified or join-safe: the pass joins sources).
    # The first rule covering a shelf wins (file order). No registry = no
    # staging (the feature-off posture).
    def stagings(catalog:, registry:, dictionaries: nil)
      return {} if registry.nil? || rules.empty?

      dates = LectDates.new(registry: registry)
      shelves = (dictionaries || catalog[:dictionaries])
                .join(:sources, id: :source_id)
                .select(Sequel[:dictionaries][:id].as(:id), Sequel[:dictionaries][:language].as(:language),
                        Sequel[:sources][:slug].as(:source))
                .all
      rules.each_with_object({}) do |rule, out|
        covered = shelves.select do |shelf|
          !out.key?(shelf[:id]) && rule.sources.include?(shelf[:source]) && rule.codes.include?(shelf[:language])
        end
        next if covered.empty?

        years = year_values(catalog, covered.map { |shelf| shelf[:id] }, rule.field)
        covered.each do |shelf|
          out[shelf[:id]] = stage(dates, rule, shelf, years.fetch(shelf[:id], []))
        end
      end
    end

    private

    def stage(dates, rule, shelf, values)
      base = { dictionary_id: shelf[:id], rule_id: rule.id, source: shelf[:source], code: shelf[:language],
               field: rule.field }
      return Staging.new(**base, lect_id: nil, reason: :undated, not_before: nil, not_after: nil) if values.empty?

      intervals = values.map { |value| self.class.parse_year(value) }
      if intervals.any?(&:nil?)
        return Staging.new(**base, lect_id: nil, reason: :unparsed_year, not_before: nil, not_after: nil)
      end

      not_before = intervals.map(&:first).min
      not_after = intervals.map(&:last).max
      verdict = dates.infer(code: shelf[:language], source: shelf[:source],
                            not_before: not_before, not_after: not_after)
      lect_id, reason = verdict.is_a?(Symbol) ? [nil, verdict] : [verdict, nil]
      Staging.new(**base, lect_id: lect_id, reason: reason, not_before: not_before, not_after: not_after)
    end

    # {dictionary_id => [distinct non-null year values]} over LIVE entries.
    def year_values(catalog, ids, field)
      year = Sequel.function(:json_extract, Sequel[:dictionary_entries][:annotations_json], "$.#{field}")
      catalog[:dictionary_entries]
        .where(dictionary_id: ids, withdrawn: false)
        .exclude(year => nil)
        .distinct
        .select(:dictionary_id, year.as(:year))
        .each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, acc|
          acc[row[:dictionary_id]] << row[:year].to_s
        end
    end
  end
end
