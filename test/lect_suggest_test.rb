# frozen_string_literal: true

require "test_helper"

# Nabu::LectSuggest (P59-4): the front-door census — one source's held
# metadata inspected against the lect registry, REPORT-ONLY (adapters
# never write the journal). Exercised against an in-memory catalog and
# the fixture registry.
class LectSuggestTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")

  def registry
    @registry ||= Nabu::Lects.load(FIXTURES)
  end

  def with_catalog
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    source = catalog[:sources].insert(slug: "newsource", name: "New", adapter_class: "X",
                                      license_class: "open")
    seed = lambda do |urn, language, facets: {}, dates: nil|
      doc = catalog[:documents].insert(source_id: source, urn: urn, language: language,
                                       content_sha256: "x")
      facets.each { |facet, value| catalog[:document_facets].insert(document_id: doc, facet: facet, value: value) }
      if dates
        catalog[:document_axes].insert(document_id: doc, not_before: dates[0], not_after: dates[1],
                                       axis_source: "newsource")
      end
    end
    3.times { |i| seed.call("urn:t:n:akk#{i}", "akk", facets: { "period" => "Neo-Assyrian" }) }
    seed.call("urn:t:n:akk9", "akk", facets: { "period" => "Old Babylonian" }, dates: [-1900, -1700])
    seed.call("urn:t:n:ett1", "ett", facets: { "genre" => "funerary" })
    yield Nabu::LectSuggest.new(catalog: catalog, registry: registry)
  ensure
    catalog&.disconnect
  end

  def test_reports_codes_with_resolution_and_refinability
    with_catalog do |suggest|
      report = suggest.run("newsource")
      akk = report.codes.find { |row| row.code == "akk" }
      assert_equal 4, akk.docs
      assert_equal "akk", akk.resolution, "no override/codemap — identity, the honest baseline"
      assert_includes akk.stages, "na", "the anchor HAS stages — refinement is possible"
      ett = report.codes.find { |row| row.code == "ett" }
      assert_empty ett.stages, "no minted stages — nothing to refine into (identity posture)"
    end
  end

  def test_reports_the_facet_vocabulary_as_rule_material
    with_catalog do |suggest|
      report = suggest.run("newsource")
      period = report.facets.find { |row| row.facet == "period" }
      assert_equal 2, period.distinct
      assert_equal [["Neo-Assyrian", 3], ["Old Babylonian", 1]], period.top
      refute report.facets.any? { |row| row.facet == "lect" },
             "the derived lect facet never censuses as its own rule material"
    end
  end

  def test_reports_the_dating_lane_and_unknown_sources_are_nil
    with_catalog do |suggest|
      report = suggest.run("newsource")
      assert_kind_of Nabu::LectDates::CensusReport, report.dating
      assert_equal({ ["newsource", "akk", "akk:ob"] => 1 }, report.dating.assignable,
                   "the dated OB doc sits in exactly one band — date-band material")
      assert_nil suggest.run("ghost")
    end
  end
end
