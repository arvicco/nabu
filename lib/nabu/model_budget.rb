# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "errors"

module Nabu
  # The monthly model-spend budget table (architecture §16 "the
  # model-output convention"): local/config/model_budget.yml, keyed
  # YYYY-MM → { spend_usd, cap_usd }. Instance state — what THIS box has
  # spent and what its owner allows — so it lives under local/config/
  # beside grants and the creep/shed acceptances, written through this
  # one gateway (tmp + rename, so a kill never leaves a half-written
  # table): the owner's cap via `nabu model-budget --cap`, the spend by
  # ModelCall from each paid call's REAL usage.
  #
  # == The check order (FIXED — verified against two live implementations)
  #
  # ModelCall consults the cache FIRST (a hit costs nothing and answers
  # even over the cap), then #check! BEFORE every paid call, then books
  # the call's real cost with #record! after it returns. FAIL-CLOSED: a
  # month with no cap row refuses every paid call — a cap is the owner's
  # explicit act, never a default.
  class ModelBudget
    MONTH = /\A\d{4}-(0[1-9]|1[0-2])\z/

    HEADER = "# local/config/model_budget.yml — the monthly model-spend table\n" \
             "# (cap_usd is the owner's `nabu model-budget --cap`; spend_usd is\n" \
             "# booked per paid call from real usage). Edit caps through the CLI.\n"

    class Error < Nabu::Error; end

    # The month has no cap row (fail-closed).
    class NoCap < Error; end

    # The month's spend has reached its cap.
    class OverCap < Error; end

    def self.month(time = Time.now) = time.utc.strftime("%Y-%m")

    def initialize(path:)
      @path = path
    end

    attr_reader :path

    # { "YYYY-MM" => { spend_usd:, cap_usd: } }, month order.
    def table
      months.sort.to_h do |month, row|
        [month, { spend_usd: Float(row.fetch("spend_usd", 0)), cap_usd: nullable_float(row["cap_usd"]) }]
      end
    end

    def row(month) = table[month]

    # The owner's cap for +month+ (spend untouched).
    def set_cap!(month:, cap_usd:)
      check_month!(month)
      unless cap_usd.is_a?(Numeric) && cap_usd >= 0
        raise Error,
              "cap_usd must be a non-negative number, got #{cap_usd.inspect}"
      end

      update! { |rows| (rows[month] ||= { "spend_usd" => 0.0 })["cap_usd"] = cap_usd.to_f }
    end

    # Refuse unless +month+ has a cap and spend + +estimate_usd+ stays
    # within it. Returns the remaining headroom.
    def check!(month:, estimate_usd: 0.0)
      check_month!(month)
      current = row(month)
      if current.nil? || current[:cap_usd].nil?
        raise NoCap, "no model budget cap for #{month} — paid calls are refused until the owner sets one " \
                     "(nabu model-budget --cap USD --month #{month})"
      end
      headroom = current[:cap_usd] - current[:spend_usd]
      if current[:spend_usd] >= current[:cap_usd] || estimate_usd > headroom
        raise OverCap, format("model budget for %<m>s is spent: $%<s>.4f of $%<c>.2f cap — paid call refused",
                              m: month, s: current[:spend_usd], c: current[:cap_usd])
      end
      headroom
    end

    # Book +usd+ (a paid call's real cost) against +month+.
    def record!(month:, usd:)
      check_month!(month)
      raise Error, "usd must be a non-negative number, got #{usd.inspect}" unless usd.is_a?(Numeric) && usd >= 0

      update! do |rows|
        entry = (rows[month] ||= {})
        entry["spend_usd"] = (Float(entry.fetch("spend_usd", 0)) + usd).round(9)
      end
    end

    private

    def months
      return {} unless File.file?(@path)

      (YAML.safe_load_file(@path) || {}).fetch("months", nil) || {}
    end

    def update!
      rows = months
      yield rows
      FileUtils.mkdir_p(File.dirname(@path))
      tmp = "#{@path}.tmp"
      File.write(tmp, HEADER + YAML.dump("months" => rows.sort.to_h))
      File.rename(tmp, @path)
      nil
    end

    def check_month!(month)
      raise Error, "month must be YYYY-MM, got #{month.inspect}" unless month.to_s.match?(MONTH)
    end

    def nullable_float(value) = value.nil? ? nil : Float(value)
  end
end
