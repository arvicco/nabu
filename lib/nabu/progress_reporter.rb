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
  #
  # Both fields are nil-safe: a reporter with nil callables is a no-op, so
  # callers can hand one down unconditionally.
  ProgressReporter = Data.define(:on_fetch_line, :on_load_tick) do
    def initialize(on_fetch_line: nil, on_load_tick: nil)
      super
    end

    def fetch_line(line) = on_fetch_line&.call(line)

    def load_tick(processed, errored) = on_load_tick&.call(processed, errored)
  end
end
