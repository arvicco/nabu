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
    yield Nabu::LectSuggest.new(catalog: catalog, registry: registry), catalog
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

  # --- P61-2: the layer sections (dating / places / script) --------------

  def test_dating_layer_reports_bounds_coverage_and_the_candidate_sniff
    with_catalog do |suggest, catalog|
      undated = catalog[:documents].where(urn: "urn:t:n:akk0").get(:id)
      catalog[:documents].where(id: undated)
                         .update(metadata_json: '{"reign":"Sargon II","genre":"letter"}')
      report = suggest.run("newsource")
      assert_equal 1, report.dating_layer.dated
      assert_equal 5, report.dating_layer.total
      assert_equal [["reign", 1]], report.dating_layer.candidates,
                   "date-shaped metadata keys on UNDATED docs are the pending sniff; " \
                   "'genre' never matches"
    end
  end

  def test_places_layer_reports_the_ref_name_split_and_latent_refs
    with_catalog do |suggest, catalog|
      doc_ids = catalog[:documents].where(source_id: catalog[:sources].where(slug: "newsource")
                                                                      .get(:id)).select_map(:id)
      catalog[:document_axes].insert(document_id: doc_ids[0], place_name: "Nineveh",
                                     place_ref: "https://pleiades.stoa.org/places/874621",
                                     axis_source: "t")
      catalog[:document_axes].insert(document_id: doc_ids[1], place_name: "Assur", axis_source: "t")
      catalog[:documents].where(id: doc_ids[2])
                         .update(metadata_json: '{"findspot_url":"https://www.trismegistos.org/place/1628"}')
      report = suggest.run("newsource")
      assert_equal 2, report.places_layer.named
      assert_equal 1, report.places_layer.linked
      assert_equal 1, report.places_layer.latent,
                   "a gazetteer URL in raw metadata on a doc WITHOUT place_ref is the latent-ref sniff"
    end
  end

  def test_script_layer_censuses_suffixed_codes_and_byte_checks_the_surface
    with_catalog do |suggest, catalog|
      src = catalog[:sources].where(slug: "newsource").get(:id)
      doc = catalog[:documents].insert(source_id: src, urn: "urn:t:n:sgao1", language: "sga-Ogam",
                                       content_sha256: "x")
      catalog[:passages].insert(document_id: doc, urn: "urn:t:n:sgao1:1", sequence: 0,
                                language: "sga-Ogam", text: "ᚉᚑᚏᚁᚔ ᚋᚐᚊᚔ", text_normalized: "x",
                                content_sha256: "x")
      report = suggest.run("newsource")
      row = report.script_layer.find { |r| r.code == "sga-Ogam" }
      assert_equal 1, row.docs
      assert_equal "ogam", row.surface, "the byte-check classifies the held text's actual script"
      assert report.script_layer.none? { |r| r.code == "akk" },
             "unsuffixed codes are script-implied — not census rows"
    end
  end
end
