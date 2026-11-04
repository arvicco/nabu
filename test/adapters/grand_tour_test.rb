# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # grand-tour — the HAB's Grand Tour digital travel journals (Zenodo
  # 23055358): document = journal, passage = page; entities resolved
  # through the deposit's registers. Fixture: four trimmed journals, the
  # registers trimmed to their citations, and one specimen of each
  # rejected grain (README.md).
  class GrandTourTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("grand-tour")
    URN = "urn:nabu:grand-tour"
    STEMS = %w[cod_guelf_149_14_extrav cod_guelf_221_extrav cod_guelf_267_1_extrav cod_guelf_89_blank].freeze

    def conformance_adapter = Nabu::Adapters::GrandTour.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "grand-tour"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    # The fixture tree minus its own manifest — the tree as it lands.
    def landed_tree
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "."), dir)
        FileUtils.rm_f(File.join(dir, "manifest.yml"))
        yield dir
      end
    end

    def test_discovers_the_four_journals_never_the_index
      assert_equal STEMS.map { |s| "#{URN}:#{s}" }, conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_introductions_registers_index_schema_and_licence_skip_by_rule
      landed_tree do |dir|
        File.write(File.join(dir, Nabu::ZipRangeFetch::STATE_FILE), "{}")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 10, skips.skipped_by_rule, "README, LICENSE, index, schema, 1 introduction, " \
                                                "3 registers, the itinerary, the state pin"
        assert skips.clean?
        assert(skips.notes.any? { |n| n.start_with?("introduction/introduction_cod_guelf_127_1_extrav.xml:") })
        assert(skips.notes.any? { |n| n.start_with?("Reiseberichte/index_grand_tour.xml:") })
      end
    end

    def test_an_unknown_member_is_unrecognized
      landed_tree do |dir|
        File.write(File.join(dir, "Reiseberichte", "notes.txt"), "?")
        refute conformance_adapter.discovery_skips(dir).clean?
      end
    end

    def test_passages_are_pages_cited_by_folio_or_facsimile
      assert_equal %w[90r 90v 91r 91v].map { |c| "#{URN}:cod_guelf_89_blank:#{c}" },
                   doc("cod_guelf_89_blank").passages.map(&:urn)
      assert_equal %w[f7 f8 f9 f10].map { |c| "#{URN}:cod_guelf_221_extrav:#{c}" },
                   doc("cod_guelf_221_extrav").passages.map(&:urn)
      assert_equal(16, documents.sum { |d| d.passages.size })
    end

    def test_the_citation_rule
      assert_equal "90r", Nabu::Adapters::GrandTour.citation(label: "90r", facs: "#mss_89-blank_00181")
      assert_equal "f107", Nabu::Adapters::GrandTour.citation(label: nil, facs: "#mss_221-extrav_00107")
      assert_nil Nabu::Adapters::GrandTour.citation(label: nil, facs: nil)
    end

    def test_a_known_snippet_and_the_regularized_layer
      page = doc("cod_guelf_89_blank").passages.first
      assert_equal "de", page.language
      assert page.text.start_with?("Dänische und Schwedische\nreyse so von hier\ngetahn worden in dem")
      assert_includes page.annotations["regularized"], "Wir Logierten bey einem Kaufmann"
      assert_equal "mss_89-blank_00181", page.annotations["facs"]
    end

    def test_documents_are_dated_by_their_entries
      assert_equal({ "not_before" => 1689, "not_after" => 1689, "raw" => "dated entries 1689 … 1689-02-01",
                     "class" => "composition" }, doc("cod_guelf_89_blank").metadata["date"])
      assert_equal 1652, doc("cod_guelf_267_1_extrav").metadata.dig("date", "not_before")
      assert_equal 1664, doc("cod_guelf_221_extrav").metadata.dig("date", "not_after")
    end

    def test_places_are_mentions_never_a_document_place
      meta = doc("cod_guelf_89_blank").metadata
      assert_nil meta["place"], "an itinerary claims no single origin"
      assert_equal "Dänemark, Königreich", meta["places_mentioned"].first
      page = doc("cod_guelf_89_blank").passages[1]
      assert_includes page.annotations["places"], { "value" => "Rendsburg",
                                                    "ref" => "https://www.geonames.org/2848245/rendsburg.html",
                                                    "id" => "rendsburg" }
    end

    def test_uneven_upstream_ner_is_counted_honestly
      assert_equal({ "resolved" => 0, "unresolved" => 0 }, doc("cod_guelf_149_14_extrav").metadata["entity_mentions"])
      assert_equal({ "resolved" => 5, "unresolved" => 64 }, doc("cod_guelf_221_extrav").metadata["entity_mentions"])
      assert_equal %w[Braunschweig Wolfenbüttel Helmstedt Darmstadt Hamburg],
                   doc("cod_guelf_221_extrav").metadata["places_mentioned"], "only resolved names"
    end

    def test_header_and_index_ride_the_metadata
      meta = doc("cod_guelf_221_extrav").metadata
      assert_equal "Cod. Guelf. 221 Extrav.", meta["shelfmark"]
      assert_equal "Christian August von Schleswig-Holstein-Norburg", meta["author"]
      assert_equal "Christian August, 1664-1669 (in Bearbeitung)", meta["edition_group"]
      assert_equal true, meta["work_in_progress"]
      assert_equal "htr-corrected", meta["text_nature"]
      assert_nil doc("cod_guelf_89_blank").metadata["work_in_progress"]
      assert_equal "[Johannes Wagener]", doc("cod_guelf_267_1_extrav").metadata["author"]
      assert_equal 6, meta["blank_pages"]
    end

    def test_the_wagener_itinerary_rides_its_journal
      itinerary = doc("cod_guelf_267_1_extrav").metadata["itinerary"]
      assert_equal({ "date" => "24.03.1652", "place" => "Meldorf", "geonames" => "6557327",
                     "lat" => "54.083333333333336", "lon" => "9.066666666666666", "journey" => "Reise 1 (1652)" },
                   itinerary.first)
      assert_equal 3, itinerary.size
      assert_nil doc("cod_guelf_89_blank").metadata["itinerary"]
    end

    def test_the_lect_stays_bare_german
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                               overrides_path: File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal "de", lects.resolve("de", source: "grand-tour"), "1652–1702 lies past de:early's 1650"
    end

    def test_registry_row_is_wired_and_frozen
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["grand-tour"]
      refute_nil entry
      assert_equal Nabu::Adapters::GrandTour, entry.adapter_class
      assert entry.wired, "first sync verified 2026-11-03 (4 docs / 515 passages)"
      assert_equal "frozen", entry.sync_policy
    end

    # -- fetch: the Range cone + the directory pin ------------------------------

    def test_the_cone_excludes_the_shipped_git_directory
      assert Nabu::Adapters::GrandTour.keep?("Reiseberichte/cod_guelf_89_blank.xml")
      assert Nabu::Adapters::GrandTour.keep?("register/itinerar_wagener.json")
      refute Nabu::Adapters::GrandTour.keep?(".git/HEAD")
      refute Nabu::Adapters::GrandTour.keep?(".git/objects/66/abc")
    end

    def test_fetch_pins_the_record_directory
      assert_match %r{\Ahttps://zenodo\.org/api/records/23055358/files/}, Nabu::Adapters::GrandTour::ZIP_URL
      assert_equal "e9b8baf3019f7952caa783c412ce920538669cd79fb0168a9910463b4a97a122",
                   Nabu::Adapters::GrandTour::DIRECTORY_SHA256
    end

    FakeRange = Struct.new(:sha, :completed, keyword_init: true) do
      def prepare! = nil
      def not_modified? = false
      def doomed_paths = []
      def complete! = (self.completed = true)

      def result
        Nabu::ZipRangeFetch::Result.new(sha: sha, size: 1, kept: 32, skipped: 94, atticked: [], not_modified: false)
      end
    end

    def test_a_directory_pin_miss_aborts_before_any_tree_change
      fake = FakeRange.new(sha: "0" * 64, completed: false)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::GrandTour.new(range_fetch: ->(**) { fake }).fetch(dir) }
      end
      refute fake.completed
    end

    def test_a_pinned_directory_completes
      fake = FakeRange.new(sha: Nabu::Adapters::GrandTour::DIRECTORY_SHA256, completed: false)
      Dir.mktmpdir do |dir|
        report = Nabu::Adapters::GrandTour.new(range_fetch: ->(**) { fake }).fetch(dir)
        assert_match(/32 members kept by Range, 94 never read/, report.notes)
      end
      assert fake.completed
    end
  end
end
