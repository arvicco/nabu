# frozen_string_literal: true

module Nabu
  module Adapters
    # The CorA-XML header dating lane shared by the ReM and ReN sibling
    # zips — the ReF P81-1 grammar (Ref#date_envelope) generalized over the
    # two upstream grid spellings: ReM writes the century-half grid with a
    # comma ("13,1", "12,2-13,1", bare-century "12"), ReN with a slash
    # ("14/1", "15/1-15/2").
    #
    # The result is the MetadataDates :structured envelope: a clean date
    # lane ("1329", "1452-1500", "1464/65") sets the bounds; prose datings
    # ("[um 1300]", "um 1140/50 (?)", century claims like "11") are never
    # number-scraped and fall back to the grid, the raw naming both claims;
    # neither lane clean → the raw string rides alone, minting nothing.
    module CoraDateLane
      module_function

      DATE_EXACT = /\A(\d{4})\z/
      # A 2-digit tail expands with the head's century ("1464/65" → 1465).
      DATE_SPAN = %r{\A(\d{4})\s*[-–/]\s*(\d{2}|\d{4})\z}

      # +date+/+time+ the verbatim header values (nil when absent);
      # +separator+ the grid's century/half separator ("," or "/").
      def envelope(date, time, separator:)
        clean = date_bounds(date)
        bounds = clean || grid_bounds(time, separator: separator)
        raw = [date, ("(time #{time})" if clean.nil? && time)].compact.join(" ")
        return nil if raw.empty?
        return { "raw" => raw } if bounds.nil?

        { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => raw }
      end

      def date_bounds(date)
        text = date.to_s.strip
        if (match = DATE_EXACT.match(text))
          year = Integer(match[1], 10)
          [year, year]
        elsif (match = DATE_SPAN.match(text))
          from = Integer(match[1], 10)
          to = match[2].length == 2 ? Integer("#{match[1][0, 2]}#{match[2]}", 10) : Integer(match[2], 10)
          from <= to ? [from, to] : nil # a descending pair is not a clean claim
        end
      end

      # "C" = the whole century, "C<sep>H" = its half; "A-B" spans A's
      # start to B's end.
      def grid_bounds(time, separator:)
        sep = Regexp.escape(separator)
        grid = /\A(\d{2})(?:#{sep}([12]))?(?:-(\d{2})(?:#{sep}([12]))?)?\z/
        match = grid.match(time.to_s.strip) or return nil

        first = century_bounds(match[1], match[2])
        last = match[3] ? century_bounds(match[3], match[4]) : first
        first[0] <= last[1] ? [first[0], last[1]] : nil
      end

      def century_bounds(century, half)
        start = (Integer(century, 10) - 1) * 100
        return [start, start + 100] if half.nil?

        start += (Integer(half, 10) - 1) * 50
        [start, start + 50]
      end
    end
  end
end
