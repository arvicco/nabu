# frozen_string_literal: true

module Nabu
  # The date model for the date/place axis (P15-2, design doc §3), in one small
  # module so the BCE arithmetic lives in exactly one place. Fable-reviewed
  # 2026-07-12 (backlog P15-2): the core arithmetic is verified correct at every
  # era boundary; the guards below are the reviewer's five mandatory fixes.
  #
  # == Signed HISTORICAL years, no year 0
  #
  # A year is a signed integer: negative = BCE, positive = CE, and there is NO
  # year 0 (1 BCE = -1, 1 CE = +1). This matches HGV's own encoding (`when=
  # "-0113"` is labelled "113 v.Chr." = 113 BCE — historical, not ISO
  # astronomical, which would read -0113 as 114 BCE) AND the CLI user's
  # intuition (`--from -300` = 300 BCE). Ingest = source = query = display, so
  # the entire BCE off-by-one class is eliminated. SQLite integer sort is
  # chronological across the boundary (-300 < -30 < 14 < 501); the absent year 0
  # is a harmless gap (no document occupies it, interval queries don't care).
  module DateAxis
    # Year 0 is not a valid historical year (1 BCE = -1, 1 CE = +1). It is also
    # the Ruby floor-division tripwire: for year 0 the BCE branch would compute
    # a = 0, (a - 1) / 100 = -1 (Ruby floors negatives), yielding a phantom
    # "0th century" idx 0. Rejected loudly so a malformed source (or a future
    # astronomical-numbered adapter, whose year 0 = 1 BCE) can never slip a bad
    # year through silently.
    class InvalidYear < Nabu::Error; end

    module_function

    # Parse a signed year out of an HGV date attribute ("-0113-08-26", "0501",
    # "-0088"). Base-10 via a sign+digits regex — NEVER Ruby's Integer(), which
    # reads "0700" as OCTAL (448) and raises on "0090"; and the leading '-' is
    # taken as the sign, not a naive split delimiter. Returns the signed integer
    # year, or nil when there is no parseable year (empty/"unbekannt"). Raises
    # InvalidYear on a literal year 0.
    def parse_year(raw)
      return nil if raw.nil?

      m = raw.to_s.strip.match(/\A(-?)(\d+)/)
      return nil unless m

      year = m[2].to_i # base-10, so "0700" → 700, "0090" → 90
      year = -year unless m[1].empty?
      raise InvalidYear, "year 0 is not a valid historical year (no year 0): #{raw.inspect}" if year.zero?

      year
    end

    # The signed century INDEX of a year: 1st c. CE = 1, 2nd c. CE = 2, 1st c.
    # BCE = -1, 2nd c. BCE = -2 (idx 0 is unreachable, like year 0). Ascending
    # index is chronological order (-2 < -1 < 1 < 2 = 2c BCE, 1c BCE, 1c CE,
    # 2c CE) — so it is both the bucket key and the sort key. Division is always
    # on a positive magnitude (via abs) so Ruby's negative floor-division never
    # bites. Raises InvalidYear on year 0.
    def century_index(year)
      raise InvalidYear, "year 0 has no century (no year 0)" if year.zero?

      magnitude = ((year.abs - 1) / 100) + 1
      year.positive? ? magnitude : -magnitude
    end

    # A human century label from a signed index: -2 → "2nd c. BCE", 6 → "6th
    # c. CE".
    def century_label(index)
      era = index.negative? ? "BCE" : "CE"
      "#{ordinal(index.abs)} c. #{era}"
    end

    # The inclusive [from, to] year bounds of a signed century index (the
    # --century N convenience the fable review recommended, so users never
    # hand-compute BCE century bounds): 6 → [501, 600]; -2 → [-200, -101].
    def century_bounds(index)
      raise InvalidYear, "century 0 does not exist" if index.zero?

      magnitude = index.abs
      if index.positive?
        [((magnitude - 1) * 100) + 1, magnitude * 100] # 1c CE → 1..100
      else
        [-(magnitude * 100), -(((magnitude - 1) * 100) + 1)] # 1c BCE → -100..-1
      end
    end

    # A single year for display: -113 → "113 BCE", 501 → "501 CE".
    def format_year(year)
      "#{year.abs} #{year.negative? ? 'BCE' : 'CE'}"
    end

    # A date span for display, honest about open ends: a point → "113 BCE"; a
    # same-era range collapses the era → "200–101 BCE", "501–700 CE"; a range
    # straddling the boundary keeps both → "30 BCE – 14 CE"; an open-ended
    # interval → "≤ 257 BCE" / "≥ 501 CE". Returns nil when both bounds are nil.
    def format_span(not_before, not_after)
      return nil if not_before.nil? && not_after.nil?
      return "≥ #{format_year(not_before)}" if not_after.nil?
      return "≤ #{format_year(not_after)}" if not_before.nil?
      return format_year(not_before) if not_before == not_after

      if not_before.negative? == not_after.negative?
        era = not_before.negative? ? "BCE" : "CE"
        "#{not_before.abs}–#{not_after.abs} #{era}"
      else
        "#{format_year(not_before)} – #{format_year(not_after)}"
      end
    end

    # English ordinal for a positive integer (1 → "1st", 2 → "2nd", 21 → "21st").
    def ordinal(number)
      teens = (11..13).include?(number % 100)
      suffix = if teens
                 "th"
               else
                 { 1 => "st", 2 => "nd", 3 => "rd" }.fetch(number % 10, "th")
               end
      "#{number}#{suffix}"
    end
  end
end
