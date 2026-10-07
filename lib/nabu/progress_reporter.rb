# frozen_string_literal: true

module Nabu
  # A print-free progress sink threaded from the CLI into SyncRunner / Rebuild
  # (owner feedback: the first real sync ran ~4 minutes with zero output). It
  # carries two callables the CLI supplies; the runners only ever call
  # #fetch_line and #load_tick, so ALL formatting and tty decisions stay in the
  # CLI and the runners keep doing no IO of their own.
  #
  # - +on_fetch_line+: called with each raw fetch/git progress line.
  # - +on_load_tick+: called with (processed_count, errored_count) after every
  #   loaded or quarantined document.
  # - +on_stage+: called with (label, eta) when a new unit of work begins
  #   (owner feedback 2026-07-18: a long rebuild must say which source it is
  #   on) — Rebuild announces each replayed slug and the trailing
  #   timeline/facet/index phases; the CLI adds the timing. +eta+ (P78-r2,
  #   Q34) is a Nabu::Eta estimate (Estimate or Eta::NONE) when the caller
  #   consulted the stage_timings history, nil when it didn't — the CLI
  #   renders an estimate line only for a non-nil eta.
  # - +on_note+: called with one finished line to print DURABLY (owner UX
  #   rule 2026-10-07) — a header or tally that is not a unit of work and
  #   so must not open a stage (a stage would close with a bogus elapsed
  #   tail). The incremental rebuild's verdict-sweep header and closing
  #   tally ride it; the CLI closes any open stage first.
  #
  # All fields are nil-safe: a reporter with nil callables is a no-op, so
  # callers can hand one down unconditionally.
  ProgressReporter = Data.define(:on_fetch_line, :on_load_tick, :on_stage, :on_note) do
    def initialize(on_fetch_line: nil, on_load_tick: nil, on_stage: nil, on_note: nil)
      super
    end

    def fetch_line(line) = on_fetch_line&.call(line)

    def load_tick(processed, errored) = on_load_tick&.call(processed, errored)

    def stage(label, eta: nil) = on_stage&.call(label, eta)

    def note(line) = on_note&.call(line)
  end
end
