# frozen_string_literal: true

module Nabu
  # The one duration voice (Q69/P97-4): Xs under a minute, else XmYYs —
  # shared by every surface that prints a timed summary line (both Thor
  # classes and the health board view). Elapsed rides every summary
  # (owner rule 2026-09-11).
  module DurationFormat
    def format_duration(secs)
      secs < 60 ? "#{secs.round(1)}s" : "#{(secs / 60).floor}m#{format('%02d', (secs % 60).round)}s"
    end
  end
end
