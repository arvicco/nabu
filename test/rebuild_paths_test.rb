# frozen_string_literal: true

require "test_helper"

# Replay-path stage parity. Three paths re-derive the corpus-wide lanes:
# the full rebuild (Rebuild#run — the reference), the incremental rebuild
# (IncrementalRebuild), and the in-phase builder pass (builders:refresh,
# Ops::BuilderRefresh). Anchor: a derived lane wired into the full rebuild
# but absent from the other two — the timeline rebuild in those paths
# dropped the artifact-script axis rows and nothing restored them until
# the next full rebuild; served queries silently lost the lane.
#
# Every stage the full rebuild runs must appear in the incremental path
# AND in builders:refresh, or carry a declared exemption with its reason.
# A new lane added to Rebuild#run alone fails here until every path is
# wired (or the exemption is argued in writing).
#
# The stage list is read from the SOURCE: Rebuild#run announces each
# corpus stage (`progress&.stage("<name>")`) and calls each post-load
# replay (`replay_<lane>(db`). Reading the source rather than extracting
# the list into a constant keeps rebuild.rb untouched — it sits in the
# derivation fingerprint's shared core, where any edit dirties every
# source stamp.
class RebuildPathsTest < Minitest::Test
  LIB = File.expand_path("../lib/nabu", __dir__)
  FULL = File.join(LIB, "rebuild.rb")
  PATHS = {
    incremental: File.join(LIB, "incremental_rebuild.rb"),
    refresh: File.join(LIB, "ops", "builder_refresh.rb")
  }.freeze

  ANNOUNCED = /progress&\.stage\("([^"#]+)"/
  REPLAY_CALL = /^\s+(replay_\w+)\(db\b/

  # A stage a path runs without announcing it, recognized by its call.
  EVIDENCE = {
    "analyze" => /Store\.analyze!/
  }.freeze

  # Stages a path deliberately does not run (stage => reason).
  EXEMPT = {
    incremental: {},
    refresh: {
      "hiero postings" => "f(canonical/aed) alone — no builder-side input; the aed post-sync " \
                          "hook (SyncRunner) re-derives it whenever its only input changes",
      "lect journal" => "written through the lect CLIs in-phase (apply-rules, assign, withdraw) " \
                        "and re-minted wholesale by both rebuild flavors; refresh projects the " \
                        "lect facet FROM it and never re-mints it",
      "source stats" => "maintained by the loader hooks at every sync; a builder pass changes " \
                        "no document or passage row",
      "fulltext index" => "maintained per source at sync time; index-core drift is the " \
                          "incremental rebuild's covering mechanism, never a builder pass",
      "links" => "the sync-time reference lane plus the batch link CLIs write it live; only " \
                 "a rebuild re-mines it wholesale",
      "analyze" => "planner statistics, not derived content",
      "replay_enrichments" => "each enrichment producer re-runs post-sync (SyncRunner)",
      "replay_place_index" => "each place-index producer re-runs post-sync (SyncRunner)",
      "replay_person_index" => "each person-index producer re-runs post-sync (SyncRunner)"
    }
  }.freeze

  # LIVE DEFECTS this guard found on arrival — NOT exemptions. Each entry
  # names a lane a path drops; the test asserts the gap still exists, so
  # the fix that closes it must also strike its entry here.
  KNOWN_GAPS = {
    incremental: {}
  }.freeze

  def full_stages
    @full_stages ||= begin
      source = File.read(FULL)
      body = source[/^    def run\(.*?^    private$/m] or flunk "Rebuild#run not found in #{FULL}"
      announced = body.scan(ANNOUNCED).flatten.map { |name| name.split(" — ").first }
      (announced + body.scan(REPLAY_CALL).flatten).uniq
    end
  end

  def covers?(source, stage)
    source.include?("stage(\"#{stage}") || source.include?("#{stage}(") ||
      EVIDENCE.fetch(stage, nil)&.match?(source)
  end

  def uncovered(path)
    source = File.read(PATHS.fetch(path))
    full_stages.reject { |stage| covers?(source, stage) }
  end

  def test_the_full_rebuild_stage_list_reads_whole
    assert_operator full_stages.size, :>=, 20, "the stage scan lost Rebuild#run: #{full_stages.inspect}"
    ["timeline", "facets", "lect facets", "fulltext index", "analyze", "replay_person_index"].each do |stage|
      assert_includes full_stages, stage
    end
  end

  def test_incremental_and_refresh_cover_every_full_rebuild_stage
    PATHS.each_key do |path|
      declared = EXEMPT.fetch(path).keys + KNOWN_GAPS.fetch(path, {}).keys
      missing = uncovered(path) - declared
      assert_empty missing,
                   "#{path} path never runs full-rebuild stage(s) #{missing.inspect} — wire them " \
                   "into #{File.basename(PATHS[path])} (or declare an exemption with its reason)"
    end
  end

  def test_exemptions_and_known_gaps_stay_honest
    PATHS.each_key do |path|
      gaps = uncovered(path)
      (EXEMPT.fetch(path).keys + KNOWN_GAPS.fetch(path, {}).keys).each do |stage|
        assert_includes full_stages, stage, "#{path}: #{stage.inspect} is no full-rebuild stage"
        assert_includes gaps, stage,
                        "#{path} now runs #{stage.inspect} — strike its exemption / known-gap entry"
      end
    end
    EXEMPT.each_value { |stages| stages.each_value { |reason| refute_empty reason.strip } }
  end
end
