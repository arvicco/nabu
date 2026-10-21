# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # te-wikisource (P140): the classical Telugu cone. Fixture envelopes are
  # real api.php captures (2026-10-21): two chapters of Baddena's Nītisāra
  # (బద్ది నీతులు, the 1917 Pithapuram print — admitted), a Krīḍābhirāmamu
  # part whose header and scan state no year (edition_unstated),
  # Jagannātha's Bhāminīvilāsa (Sanskrit in Telugu script — the censused
  # overlap exclusion), the Harivaṃśamu publisher's notice (apparatus) and
  # C. P. Brown's 1911 Vemana (translation — Brown's English layer).
  class TeWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("te-wikisource")

    def conformance_adapter = Nabu::Adapters::TeWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "te-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:te-wikisource:188381 urn:nabu:te-wikisource:188382],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      ["1 Sanskrit-in-Telugu-script page(s)", "1 editorial apparatus page(s)", "1 translation page(s)",
       "1 page(s) whose edition states no year"].each do |prefix|
        assert(notes.any? { |note| note.start_with?(prefix) }, "missing skip note: #{prefix}")
      end
    end

    def test_the_sanskrit_overlap_is_excluded_by_rule
      adapter = conformance_adapter
      assert_equal :sanskrit_overlap, adapter.page_class(envelope(173_790))
      rigveda = envelope(188_381).merge("title" => "ఋగ్వేదము/మండలము 1",
                                        "wikitext" => "{{తలకట్టు|శీర్షిక=ఋగ్వేదము}}\n[[వర్గం:ఋగ్వేదము]]")
      assert_equal :sanskrit_overlap, adapter.page_class(rigveda), "the category guard holds for any page"
      sanskrit_index = envelope(188_381)
      sanskrit_index["indexes"].first["fields"]["భాష"] = "sa"
      assert_equal :sanskrit_overlap, adapter.page_class(sanskrit_index), "an Index declaring sa"
    end

    def test_a_pre_print_year_is_never_edition_evidence
      adapter = conformance_adapter
      assert_equal [1917], adapter.years_in("1917")
      assert_empty adapter.years_in("1600"), "no Telugu print predates 1800 — a composition year"
      assert_equal :edition_unstated, adapter.page_class(envelope(11_230))
    end

    def test_the_index_edition_rides_verbatim
      niti = doc(188_381)
      assert_equal "tel", niti.language
      assert niti.passages.first.text.start_with?("అవిఘ్నమస్తు. శుభమస్తు.")
      edition = niti.metadata["index_editions"].first
      assert_equal ["1917", "చెలికాని లచ్చారావు", "పిఠాపురము"], edition.values_at("year", "editor", "place")
      assert_equal({ "author" => "బద్ది భూపాలుడు", "section" => "సేవకనీతిప్రకరణము", "year" => "1917" },
                   niti.metadata["header"])
      assert_match(/\Aసంవత్సరం: 1917 · index: బద్ది నీతులు/, niti.metadata["base_edition"])
    end

    def test_the_print_year_feeds_the_edition_date_lane
      shapes = Nabu::Store::TimelineBuilder::MetadataDates::SHAPES
      assert_equal :edition_year_text, shapes["te-wikisource"]
      years = Nabu::Store::TimelineBuilder::MetadataDates.edition_year_text(doc(188_382).metadata)
      assert_equal [1917, 1917, "edition"], years.values_at(0, 1, 4)
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "te-wikisource", name: "Telugu Wikisource",
                                          adapter_class: "Nabu::Adapters::TeWikisource", license_class: "attribution")
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
