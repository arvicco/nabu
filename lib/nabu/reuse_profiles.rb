# frozen_string_literal: true

require "yaml"
require_relative "errors"
require_relative "normalize"

module Nabu
  # config/reuse_profiles.yml — the declared per-language tuning profiles of
  # the parallels batch producer (P122-2, architecture §15). A profile names
  # the language/scope it serves, the engine knobs (gram size, score floor,
  # per-anchor and candidate caps, a function-token policy) and a free-text
  # rationale; `parallels --batch --profile NAME` loads one, explicit flags
  # override it, and the run's provenance records the profile plus every
  # effective parameter (BatchParallels::Settings).
  #
  # Strict by design: an unknown key, a missing rationale, or a mistyped
  # knob raises at load — a silently ignored `gram_sise` would mine with
  # the default and record a tuning that never happened.
  class ReuseProfiles
    class Error < Nabu::Error; end

    KNOBS = %w[gram_size min_score per_anchor candidate_pool stop_tokens].freeze
    KEYS = (%w[lang serves rationale] + KNOBS).freeze
    REQUIRED = %w[serves rationale].freeze

    # Omitted knobs are nil (the engine default applies); stop_tokens are
    # folded to the profile language's search form so they compare against
    # the engine's gram tokens.
    Profile = Data.define(:name, :lang, :serves, :gram_size, :min_score, :per_anchor,
                          :candidate_pool, :stop_tokens, :rationale)

    def self.default_path = File.join(Nabu::Config::PROJECT_ROOT, "config", "reuse_profiles.yml")

    # The project definition's table (config data, memoized per process —
    # the period-bands precedent).
    def self.default
      @default ||= load(default_path)
    end

    def self.load(path)
      return new(profiles: {}) unless File.file?(path)

      raw = YAML.safe_load_file(path) || {}
      unknown = raw.keys - ["profiles"]
      raise Error, "#{path}: unknown top-level key(s) #{unknown.join(', ')}" unless unknown.empty?

      new(profiles: (raw["profiles"] || {}).to_h { |name, entry| [name, build(path, name, entry || {})] })
    end

    def self.build(path, name, entry)
      unknown = entry.keys - KEYS
      raise Error, "#{path}: #{name}: unknown key(s) #{unknown.join(', ')}" unless unknown.empty?

      REQUIRED.each do |key|
        raise Error, "#{path}: #{name}: #{key} is required" if entry[key].to_s.strip.empty?
      end
      validate_knobs!(path, name, entry)
      Profile.new(name: name, lang: entry["lang"], serves: entry["serves"].to_s.strip,
                  gram_size: entry["gram_size"], min_score: entry["min_score"]&.to_f,
                  per_anchor: entry["per_anchor"], candidate_pool: entry["candidate_pool"],
                  stop_tokens: fold_stop_tokens(entry["stop_tokens"], entry["lang"]),
                  rationale: entry["rationale"].to_s.strip)
    end
    private_class_method :build

    def self.validate_knobs!(path, name, entry)
      checks = {
        "gram_size" => ->(v) { v.is_a?(Integer) && v.between?(2, 8) },
        "min_score" => ->(v) { v.is_a?(Numeric) && !v.negative? },
        "per_anchor" => ->(v) { v.is_a?(Integer) && v.positive? },
        "candidate_pool" => ->(v) { v.is_a?(Integer) && v.positive? },
        "stop_tokens" => ->(v) { v.is_a?(Array) && v.all?(String) },
        "lang" => ->(v) { v.is_a?(String) && !v.empty? }
      }
      checks.each do |key, valid|
        next unless entry.key?(key)
        next if valid.call(entry[key])

        raise Error, "#{path}: #{name}: #{key} #{entry[key].inspect} is invalid " \
                     "(gram_size 2–8, min_score ≥ 0, per_anchor/candidate_pool positive integers, " \
                     "stop_tokens a list of strings)"
      end
    end
    private_class_method :validate_knobs!

    def self.fold_stop_tokens(tokens, lang)
      Array(tokens).map { |token| Normalize.search_form(token.to_s, language: lang.to_s) }.uniq
    end
    private_class_method :fold_stop_tokens

    def initialize(profiles:)
      @profiles = profiles
    end

    def names = @profiles.keys

    def fetch(name)
      @profiles.fetch(name) do
        declared = names.empty? ? "none" : names.sort.join(", ")
        raise Error, "unknown reuse profile #{name.inspect} — declared: #{declared} (config/reuse_profiles.yml)"
      end
    end
  end
end
