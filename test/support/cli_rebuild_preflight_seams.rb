# frozen_string_literal: true

# The CLI-level rebuild tests run the full rebuild's preflight
# (Nabu::Ops::RebuildPreflight) through `Nabu::CLI.start`. Un-stubbed, its
# writer check reads the box's REAL process table (`ps`) and its pinned-file
# probe the real `lsof`, so a sync running on the box blocked rebuilds
# inside the suite. Every CLI rebuild in the suite instead sees a fixed,
# empty process table and no holders; test/ops/rebuild_preflight_test.rb
# pins the writer logic itself with its own seams. The same +ps_output:+
# seam feeds the sync's mid-rebuild admission (CLI#running_rebuild), so a
# real rebuild running on the box never refuses the suite's CLI syncs.
Nabu::CLI.rebuild_preflight_seams = { ps_output: -> { "" }, holders: ->(_paths) { [] } }.freeze
