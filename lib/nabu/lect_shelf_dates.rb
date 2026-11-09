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
  # The PARENT-ANCHOR FALLBACK (2026-11-09, opt-in per rule —
  # parent_anchor_fallback: true; default off). A shelf dated below every
  # stage of its own anchor (:outside_bands AND the hull ends before the
  # anchor's lowest band floor — never a straddle, never a shelf above the
  # ladder, never an undated or already-refined shelf) climbs the
  # registry's descent edges (Nabu::Lects#parent_of) to the NEAREST
  # ancestor whose band contains the hull: LEME's 1477–1499 English lexicons fall below en:early and
  # land on enm [1100, 1500]; its pre-1600 French ones on frm [1400, 1600].
  # An ancestor's candidates are its attested banded stages when it has
  # any, else its own anchor-level band (enm/frm/fro/ang carry theirs
  # bare). Tie-break: parent: is a single edge, so the walk is a chain and
  # nearest-first decides a shared edge year (1400 is in both frm and fro
  # → frm); an ancestor none of whose bands contains the hull is passed
  # over (an ancestor with SEVERAL containing bands ends the walk bare —
  # the ambiguity is not ours to resolve). The walk STOPS at the
  # first ancestor carrying no attested band — the end of the dated
  # succession (fro → roa, enm → ang → gmw:pro): past it the chain crosses
  # into another language's ladder (roa's parent is lat, whose open
  # lat:new band would swallow any late hull). SHELF GRAIN ONLY — the
  # document grain (LectDates#infer) never climbs. The staged shelf keeps
  # basis rule:date-band; its note names the anchor it fell back from.
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

    Rule = Data.define(:id, :sources, :codes, :field, :note, :parent_anchor_fallback) do
      def initialize(parent_anchor_fallback: false, **) = super
    end

    # One covered shelf's verdict: +lect_id+ when staged, else nil and the
    # +reason+ it stayed bare.
    # +fallback_from+ names the code's own anchor when the parent-anchor
    # fallback staged the shelf, else nil.
    Staging = Data.define(:dictionary_id, :rule_id, :source, :code, :field, :lect_id, :reason,
                          :not_before, :not_after, :fallback_from) do
      def initialize(fallback_from: nil, **) = super

      def staged? = !lect_id.nil?

      def interval = [not_before, not_after]

      def basis = staged? ? BASIS : nil

      def note
        dated = not_before && not_after ? "dated #{not_before}..#{not_after} (#{field})" : nil
        return [dated, fallback_from && "parent-anchor fallback from #{fallback_from}"].compact.join(" — ") if staged?

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

      fallback = entry.fetch("parent_anchor_fallback", false)
      unless [true, false].include?(fallback)
        raise Nabu::Error, "dictionary date-band rule #{entry['id']}: parent_anchor_fallback must be true or false"
      end

      Rule.new(id: entry.fetch("id"), sources: Array(entry.fetch("sources")).map(&:to_s),
               codes: Array(entry.fetch("codes")).map(&:to_s), field: field, note: entry["note"],
               parent_anchor_fallback: fallback)
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
    # A shelf code is a LANGUAGE code, so a codemapped one (fra → fr)
    # qualifies when it resolves onto a node for every covered source.
    def validate!(registry)
      rules.each do |rule|
        rule.codes.each do |code|
          next if registry.lect(code)
          next if rule.sources.all? { |source| registry.lect(registry.resolve(code, source: source)) }

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
          out[shelf[:id]] = stage(dates, registry, rule, shelf, years.fetch(shelf[:id], []))
        end
      end
    end

    private

    def stage(dates, registry, rule, shelf, values)
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
      if reason == :outside_bands && rule.parent_anchor_fallback
        fallback = parent_anchor_stage(registry, shelf, not_before, not_after)
        if fallback
          return Staging.new(**base, lect_id: fallback.last, reason: nil, not_before: not_before,
                                     not_after: not_after, fallback_from: fallback.first)
        end
      end
      Staging.new(**base, lect_id: lect_id, reason: reason, not_before: not_before, not_after: not_after)
    end

    # The parent-anchor fallback walk (class doc): [own anchor, staged id]
    # for the nearest ancestor holding exactly one attested band that
    # contains the hull, or nil. The resolution's script surface rides on
    # (en~latn → enm~latn), the LectDates#infer stance.
    def parent_anchor_stage(registry, shelf, not_before, not_after)
      match = Nabu::Lects.parse_id(registry.resolve(shelf[:language], source: shelf[:source]))
      return nil unless match && below_floor?(registry, match[:anchor], not_after)

      seen = Set[match[:anchor]]
      ancestor = registry.parent_of(match[:anchor])
      while ancestor && seen.add?(ancestor)
        bands = ancestor_bands(registry, ancestor)
        return nil if bands.empty?

        containing = bands.select do |record|
          (record.band[0].nil? || record.band[0] <= not_before) && (record.band[1].nil? || not_after <= record.band[1])
        end
        return nil if containing.size > 1
        return [match[:anchor], "#{containing.first.id}#{"~#{match[:script]}" if match[:script]}"] if containing.one?

        ancestor = registry.parent_of(ancestor)
      end
      nil
    end

    # Does the hull end before every band of the own anchor's attested
    # stages? (An open floor admits nothing below it.)
    def below_floor?(registry, anchor, not_after)
      floors = registry.stages_of(anchor).select { |lect| lect.mode == :attested && lect.band }
                                         .map { |lect| lect.band[0] }
      !floors.empty? && floors.none?(&:nil?) && not_after < floors.min
    end

    # An ancestor's candidate bands: its attested banded stages when it has
    # any, else its own record (an anchor-level band, or a stage id's band
    # — a reconstructed stage never qualifies).
    def ancestor_bands(registry, id)
      record = registry.lect(id)
      return [] unless record

      stages = record.stage ? [] : registry.stages_of(record.anchor)
      candidates = stages.empty? ? [record] : stages
      candidates.select { |lect| lect.mode == :attested && lect.band && (lect.band[0] || lect.band[1]) }
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
