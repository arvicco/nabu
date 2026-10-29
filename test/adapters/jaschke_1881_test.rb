# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"
require "support/adapter_conformance"

module Adapters
  # jaschke-1881 — Jäschke's Tibetan-English Dictionary (London 1881) as the
  # public-domain archive.org scan, one metadata-only document per printed
  # leaf (text_layer none: the scan is the asset, a transcription is a future
  # enrichment). Fixture: the real page map trimmed to one specimen per
  # grain, beside a two-page cut of the real PDF (print pp. 1–2).
  class Jaschke1881Test < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("jaschke-1881")
    KLASS = Nabu::Adapters::Jaschke1881
    ITEM = KLASS::IDENTIFIER
    URN = "urn:nabu:jaschke-1881"

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "jaschke-1881"

    # Every document is a declared scan page: metadata-only by its own marker.
    def conformance_metadata_only?(document) = document.metadata["text_layer"] == "none"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_discovers_one_document_per_printed_leaf_in_leaf_order
      assert_equal %W[#{URN}:leaf3 #{URN}:p1 #{URN}:p2 #{URN}:p611 #{URN}:p669 #{URN}:p672],
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_binding_leaves_skip_by_rule_with_their_notes
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("leaf 1") && note.include?("binding") })
      assert(skips.notes.any? { |note| note.include?("leaf 702") && note.include?("binding") })
    end

    def test_print_page_n_sits_on_leaf_n_plus_twenty_six
      page = doc("p1")
      assert_equal 27, page.metadata["leaf"]
      assert_equal 1, page.metadata["print_page"]
      assert_equal "dictionary", page.metadata["section"]
      assert_equal "https://archive.org/details/#{ITEM}/page/n26", page.metadata["ia_url"]
      assert_equal 28, doc("p2").metadata["leaf"]
    end

    def test_sections_follow_the_curated_leaf_map
      assert_equal "front_matter", doc("leaf3").metadata["section"]
      assert_nil doc("leaf3").metadata["print_page"]
      assert_equal "vocabulary", doc("p611").metadata["section"]
      assert_equal "corrections", doc("p669").metadata["section"]
      assert_equal "colophon", doc("p672").metadata["section"]
    end

    def test_pages_are_metadata_only_scans_in_english_about_tibetan
      page = doc("p2")
      assert_empty page.passages
      assert_equal "none", page.metadata["text_layer"]
      assert_equal "eng", page.language
      assert_equal "xct", page.metadata["object_language"]
      assert_equal({ "not_before" => 1881, "not_after" => 1881, "raw" => "1881" }, page.metadata["date"])
      assert_equal "H. A. Jäschke", page.metadata["author"]
      assert_equal "H. A. Jäschke, A Tibetan-English Dictionary (1881), p. 2", page.title
      assert page.canonical_path.end_with?("#{ITEM}/#{ITEM}.pdf")
    end

    def test_front_matter_title_names_the_leaf
      assert_equal "H. A. Jäschke, A Tibetan-English Dictionary (1881), front matter, leaf 3",
                   doc("leaf3").title
    end

    def test_the_page_maps_own_number_rides_when_it_has_one
      assert_equal "611", doc("p611").metadata["ia_page_number"]
      refute doc("p1").metadata.key?("ia_page_number") # upstream leaves pp. 1–9 unnumbered
    end

    def test_a_page_map_entry_contradicting_the_leaf_rule_quarantines
      Dir.mktmpdir do |workdir|
        copy_fixture_item(workdir)
        map = File.join(workdir, ITEM, "#{ITEM}_page_numbers.json")
        data = JSON.parse(File.read(map))
        data["pages"].find { |entry| entry["leafNum"] == 637 }["pageNumber"] = "612"
        File.write(map, JSON.generate(data))
        adapter = KLASS.new(delay: 0)
        ref = adapter.discover(workdir).find { |candidate| candidate.id == "#{URN}:p611" }
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_includes error.message, "612"
      end
    end

    def test_nothing_discovered_until_both_pinned_files_are_held
      Dir.mktmpdir do |workdir|
        FileUtils.mkdir_p(File.join(workdir, ITEM))
        FileUtils.cp(File.join(FIXTURES, ITEM, "#{ITEM}_page_numbers.json"), File.join(workdir, ITEM))
        assert_empty KLASS.new(delay: 0).discover(workdir).to_a
      end
    end

    def test_license_is_open_public_domain
      assert_equal "open", KLASS.manifest.license_class
      assert_includes KLASS.manifest.license, "NOT_IN_COPYRIGHT"
    end

    # --- fetch (WebMock only) ------------------------------------------------

    def fixture_bytes(name) = File.binread(File.join(FIXTURES, ITEM, name))

    def fixture_pins
      KLASS::FILES.to_h { |name| [name, Digest::SHA1.hexdigest(fixture_bytes(name))] }
    end

    def stub_files
      KLASS::FILES.each do |name|
        stub_request(:get, "https://archive.org/download/#{ITEM}/#{name}")
          .to_return(status: 200, body: fixture_bytes(name))
      end
    end

    def copy_fixture_item(workdir)
      FileUtils.mkdir_p(File.join(workdir, ITEM))
      KLASS::FILES.each { |name| FileUtils.cp(File.join(FIXTURES, ITEM, name), File.join(workdir, ITEM)) }
    end

    def test_fetch_lands_the_pinned_pair_under_upstream_file_names
      stub_files
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0, pins: fixture_pins).fetch(workdir)
        KLASS::FILES.each { |name| assert File.file?(File.join(workdir, ITEM, name)), name }
        assert_includes report.notes, "+2 this sync"
        assert_match(/\A\h{64}\z/, report.sha)
      end
    end

    def test_fetch_never_rerequests_a_held_file_whose_pin_verifies
      Dir.mktmpdir do |workdir|
        copy_fixture_item(workdir)
        report = KLASS.new(delay: 0, pins: fixture_pins).fetch(workdir)
        assert_includes report.notes, "+0 this sync"
        assert_not_requested :get, /archive\.org/
      end
    end

    def test_fetch_refuses_bytes_that_miss_the_pin_and_writes_nothing
      stub_files
      pins = fixture_pins.merge("#{ITEM}.pdf" => "0" * 40)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { KLASS.new(delay: 0, pins: pins).fetch(workdir) }
        assert_includes error.message, "pinned"
        refute File.exist?(File.join(workdir, ITEM, "#{ITEM}.pdf"))
      end
    end

    def test_the_real_pins_are_the_files_xml_sha1s
      assert_equal "146fad4ff870fcf8efc3affb278d6928db8019f4", KLASS::PINS.fetch("#{ITEM}.pdf")
      assert_equal "d4cea0cdec1ef012e36a5479a3c651bb71bd41fa", KLASS::PINS.fetch("#{ITEM}_page_numbers.json")
    end
  end
end
