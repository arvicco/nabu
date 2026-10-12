# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # th-wikisource (P120-3): the ประชุมพงศาวดาร cone. Fixture envelopes are
  # real api.php captures (2026-10-12): part 5 story 3 (BE 2460 → 1917,
  # admitted), part 53 printed BE 2473 (→ 1930, the last admitted year)
  # beside its BE 2476 reprint (→ 1933, tainted), part 56 (BE 2475 → 1932,
  # tainted) and a Three Seals Law section from Lingat's BE 2482 (→ 1939)
  # edition (tainted — the whole law code is post-1930 on the wiki).
  class ThWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("th-wikisource")

    def conformance_adapter = Nabu::Adapters::ThWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "th-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:th-wikisource:41644 urn:nabu:th-wikisource:80299],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("3 page(s) excluded by EDITION_TAINT_POST_1930") })
    end

    def test_buddhist_era_years_convert_to_ce
      adapter = conformance_adapter
      assert_equal [1930], adapter.years_in("2473")
      assert_equal [1918], adapter.years_in("ประชุมพงศาวดาร (ภาค ๑๐) - ๒๔๖๑.pdf"), "Thai digits read"
      assert_equal [1166], adapter.years_in("จุลศักราช 1166"), "a CE-band number stays as stated"
    end

    def test_the_be_2473_boundary_admits_and_its_2476_reprint_taints
      assert_equal :text, conformance_adapter.page_class(envelope(41_644))
      assert_equal [1930], conformance_adapter.envelope_edition_years(envelope(41_644))
      assert_equal :edition_taint, conformance_adapter.page_class(envelope(41_645))
      assert_includes conformance_adapter.envelope_edition_years(envelope(41_645)), 1933
      assert_equal :edition_taint, conformance_adapter.page_class(envelope(14_632)), "part 56, BE 2475 → 1932"
    end

    def test_the_three_seals_law_edition_is_after_the_cutoff
      law = envelope(40_870)
      assert_equal :edition_taint, conformance_adapter.page_class(law)
      assert_includes conformance_adapter.envelope_edition_years(law), 1939
    end

    def test_publisher_and_year_ride_verbatim
      chronicle = doc(80_299)
      assert_equal "tha", chronicle.language
      edition = chronicle.metadata["index_editions"].first
      assert_equal %w[โบราณคดีสโมสร 2460 พระนคร], edition.values_at("publisher", "year", "place")
      assert_includes chronicle.metadata["base_edition"], "ผู้เผยแพร่: โบราณคดีสโมสร"
      refute_includes chronicle.metadata["base_edition"], "หมายเหตุ", "the scan's contents list stays out"
      assert_equal({ "levels" => { "1" => 4 }, "lowest_text_level" => 1 }, chronicle.metadata["proofread"])
    end

    def test_the_print_year_dates_the_edition_in_ce
      assert_equal :edition_year_text, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["th-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(80_299).metadata)
      assert_equal [1917, 1917], years.first(2)
      assert_equal "edition", years.last
    end

    def test_apparatus_segments
      adapter = conformance_adapter
      %w[คำนำ คำอธิบาย ผู้วายชนม์ อธิบายประกอบ].each do |segment|
        assert_equal :apparatus, adapter.wikitext_class("ประชุมพงศาวดาร/ภาคที่ 28/#{segment}", "{{header}}")
      end
      assert_nil adapter.wikitext_class("ประชุมพงศาวดาร/ภาคที่ 10/ภาคผนวก", "{{header}}"),
                 "a print's appendix stays text"
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "th-wikisource", name: "Thai Wikisource",
                                          adapter_class: "Nabu::Adapters::ThWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 2, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end
