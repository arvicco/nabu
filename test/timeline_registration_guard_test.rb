# frozen_string_literal: true

require "test_helper"
require "yaml"

# The timeline-registration guard (test/support/timeline_registration_guard.rb):
# a source whose parsed documents carry date-shaped metadata must reach the
# public dating axis — registered in MetadataDates::SHAPES, or opted out with
# its reason (its own extractor lane). The conformance suite runs the check
# per adapter over its fixtures; this file pins the detector, the ledgers'
# hygiene, and the class's live specimen (emmo).
class TimelineRegistrationGuardTest < Minitest::Test
  Guard = TimelineRegistrationGuard
  SHAPES = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES

  def sources
    @sources ||= YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "sources.yml"),
                                     aliases: true).keys
  end

  # -- the detector -----------------------------------------------------------

  def test_the_structured_date_hash_is_the_health_reading
    found = Guard.families({ "date" => { "not_before" => 1600, "not_after" => 1610, "raw" => "1600s" } })
    assert_includes found, "not_before"
    assert_includes found, "date"
  end

  def test_a_nested_not_before_anywhere_is_found_like_the_health_like_probe
    assert_includes Guard.families({ "ndl_catalog" => { "date" => { "not_before" => 1700 } } }), "not_before"
  end

  def test_the_health_census_and_the_guard_share_one_marker
    assert_equal '"not_before"', Nabu::Health::Invariants::DATE_BOUNDS_MARKER,
                 "the suite guard promotes the live timeline_lane_drift reading — one marker, two readers"
  end

  def test_sibling_shape_families_are_found
    { { "datefrom" => "12800101" } => "datefrom/dateto",
      { "date_not_before" => "1025-01-01" } => "date_not_before/date_not_after",
      { "creation_date" => "-245" } => "creation_date",
      { "end_date" => "-201" } => "start_date/end_date",
      { "birth_century" => "17" } => "birth_century/death_century",
      { "date_iso" => "1588" } => "date_iso",
      { "orig_date" => { "when" => "0337" } } => "orig_date",
      { "year" => 1501 } => "year",
      { "period" => "Ur III" } => "period",
      { "dynasty" => "後秦" } => "dynasty",
      { "dcs_time_slot" => "3" } => "dcs_time_slot",
      { "source_date" => "1904" } => "source_date",
      { "printed_date" => "1826" } => "printed_date",
      { "date_text" => "780-800?" } => "date_text",
      { "edition_year" => "1862" } => "edition_year",
      { "source_edition" => { "date" => "1880" } } => "source_edition" }.each do |metadata, family|
      assert_includes Guard.families(metadata), family, "#{metadata.inspect} is a SHAPES reader's input"
    end
  end

  def test_undated_metadata_carries_no_family
    assert_empty Guard.families({ "title" => "Liber", "facets" => { "genre" => "letter" }, "updated" => "2026" })
    assert_empty Guard.families({})
    assert_empty Guard.families(nil)
  end

  # -- the verdict ------------------------------------------------------------

  def dated = [{ "date" => { "not_before" => 1600, "not_after" => 1610 } }]

  def test_an_unregistered_dated_source_is_dark_with_a_naming_message
    message = Guard.violation("no-such-source", dated)
    refute_nil message
    assert_includes message, "no-such-source"
    assert_includes message, "not_before"
    assert_includes message, "MetadataDates::SHAPES"
    assert_includes message, "OPT_OUTS"
  end

  def test_a_registered_source_passes
    assert_nil Guard.violation("emmo", dated)
  end

  def test_an_opted_out_source_passes
    assert_nil Guard.violation("iip", dated)
  end

  def test_an_undated_source_passes_unregistered
    assert_nil Guard.violation("no-such-source", [{ "title" => "x" }])
  end

  # -- the class's specimen ---------------------------------------------------

  # emmo shipped with a date hash in every manuscript's metadata and no
  # SHAPES row: its 100 manuscripts sat dark on the timeline for a whole
  # release, found by accident. The guard exists for exactly this shape.
  def test_emmo_is_registered_the_specimen_stays_pinned
    assert_equal :structured, SHAPES["emmo"]
    refute Guard::OPT_OUTS.key?("emmo"), "emmo is a SHAPES source, never an opt-out"
    refute Guard::PENDING.key?("emmo")
  end

  # -- the ledgers' hygiene ---------------------------------------------------

  def test_every_opt_out_names_a_live_lane_and_a_reason
    Guard::OPT_OUTS.each do |slug, row|
      assert_includes sources, slug, "opt-out #{slug} is not a registered source"
      refute SHAPES.key?(slug), "#{slug} is in SHAPES AND opted out — drop the opt-out row"
      refute_empty row.fetch(:reason).to_s.strip, "opt-out #{slug} must carry its reason"
      lane = row.fetch(:lane)
      builder = Nabu::Store::TimelineBuilder
      live = lane.match?(/\A[A-Z]/) ? builder.const_defined?(lane, false) : builder.respond_to?(lane, true)
      assert live,
             "opt-out #{slug} names lane #{lane}, which TimelineBuilder no longer defines"
    end
  end

  def test_every_pending_row_is_still_unregistered_and_says_why
    Guard::PENDING.each do |slug, reason|
      assert_includes sources, slug, "pending #{slug} is not a registered source"
      refute SHAPES.key?(slug), "#{slug} is registered in SHAPES now — delete its PENDING row"
      refute Guard::OPT_OUTS.key?(slug), "#{slug} is both PENDING and opted out"
      refute_empty reason.to_s.strip
    end
  end
end
