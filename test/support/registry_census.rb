# frozen_string_literal: true

module Nabu
  module TestSupport
    # The nabu-lects registry census, as pinned by the CURRENT fixture cut
    # (test/fixtures/nabu-lects/ — see its README for the cut's commit and
    # hashes). These are era-bound census claims, not invariants: every
    # registry fixture re-cut moves them, and every test that asserts a
    # census figure MUST read it from here, so a re-cut is a one-line
    # advance instead of a hunt across assertion literals (the P152
    # consolidation; the 2026-10-30 third cut broke nine assertions in
    # four files by moving 272 → 284; the 2026-11-02 fourth cut moved it to
    # 312; the 2026-11-04 fifth cut to 317; the 2026-11-12 sixth cut to 323).
    module RegistryCensus
      ANCHORS = 323
      STAGES = 172
      VARIETIES = 33
      CODEMAP_ROWS = 238

      # The one-line census rendering shared by status/list surfaces.
      LINE = [
        "#{ANCHORS} anchors", "#{STAGES} stages",
        "#{VARIETIES} varieties", "#{CODEMAP_ROWS} codemap rows"
      ].join(" · ").freeze
    end
  end
end
