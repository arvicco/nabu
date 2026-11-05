# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::StationersRegister — the Stationers' Register Online
  # (SRO) copy entries 1557–1640 over the sro-tei family: document = one
  # register entry (urn = its permanent SRO id), passage = one block of its
  # register text. Fixtures: real trimmed slices of the four CURRENT
  # Register files (11 entries), plus one specimen of each rejected grain
  # (an Arber rendering, a superseded OLD Register version, the stylesheet).
  class StationersRegisterTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("stationers-register")
    URN = "urn:nabu:stationers-register:"

    def conformance_adapter = Nabu::Adapters::StationersRegister.new

    def conformance_workdir = FIXTURES

    def conformance_expected_source_id = "stationers-register"

    def adapter = Nabu::Adapters::StationersRegister.new

    def refs = adapter.discover(FIXTURES).to_a

    def document(sro_id)
      a = adapter
      ref = a.discover(FIXTURES).find { |r| r.id == "#{URN}#{sro_id}" } or flunk "#{sro_id} not discovered"
      a.parse(ref)
    end

    # -- registry ------------------------------------------------------------

    def test_registered_unwired_until_the_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["stationers-register"]
      refute_nil entry, "stationers-register must be registered in config/sources.yml"
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "Nabu::Adapters::StationersRegister", entry.adapter_class_name
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "germanic"
    end

    def test_manifest_is_attribution_class_and_records_the_licence_conflict
      manifest = adapter.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY-SA"
      assert_includes manifest.license, "creativecommons.org/licenses/by/4.0/"
      assert_includes manifest.credit, "Giles Bergel and Ian Gadd"
      assert_equal ["https://github.com/gbergel/SRO_data.git"], Nabu::Adapters::StationersRegister.upstream_repo_urls
    end

    # -- discovery -----------------------------------------------------------

    def test_discovers_one_document_per_entry_of_the_current_registers_only
      ids = refs.map(&:id)
      assert_equal %w[SRO1 SRO4 SRO8 SRO218 SRO1679 SRO1688 SRO2203 SRO4539 SRO5992 SRO8024 SRO9195 SRO10453]
        .map { |id| "#{URN}#{id}" }, ids,
                   "register order A→D, file order within each; the OLD Register and Arber " \
                   "specimens carry the SAME SRO ids and must never be discovered"
      assert_equal({ "A" => 4, "B" => 3, "C" => 2, "D" => 3 }, refs.map { |r| r.metadata["liber"] }.tally)
      assert(refs.all? { |r| r.path.include?(File.join("Register ", "CURRENT Register")) })
    end

    def test_discovery_skips_count_every_rejected_grain_by_rule
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 4, skips.skipped_by_rule,
                   "the Arber rendering, the superseded OLD Register version, the stylesheet and the " \
                   "README (this fixture's README sits at the upstream README's path)"
      assert(skips.notes.any? { |n| n.start_with?("Arber/: 1 file —") })
      assert(skips.notes.any? { |n| n.start_with?("Register /OLD Register/: 1 file —") })
      assert(skips.notes.any? { |n| n.start_with?("schema/stylesheet: 1 file —") })
      assert(skips.notes.any? { |n| n.start_with?("project documents: 1 file —") })
      assert_equal 1, skips.unrecognized,
                   "the fixture rig's own manifest.yml is a stray the census counts loudly — " \
                   "exactly what it must do for any unexpected file in a real workdir"
      assert(skips.notes.any? { |n| n.include?("manifest.yml") })
    end

    def test_discovery_skips_recognize_the_upstream_support_files
      Dir.mktmpdir do |dir|
        current = File.join(dir, "Register ", "CURRENT Register")
        FileUtils.mkdir_p(current)
        FileUtils.cp(File.join(FIXTURES, "Register ", "CURRENT Register", "reg_A-updated.xml"), current)
        %w[README.md JC-changes-actually-made.pdf .DS_Store].each { |name| File.write(File.join(dir, name), "x") }
        File.write(File.join(current, "sro-transcription.rng"), "x")
        File.write(File.join(current, ".DS_Store"), "x")
        FileUtils.mkdir_p(File.join(dir, ".git"))
        File.write(File.join(dir, ".git", "HEAD"), "x")
        skips = adapter.discovery_skips(dir)
        assert_equal 5, skips.skipped_by_rule
        assert_equal 0, skips.unrecognized, skips.notes.inspect
      end
    end

    # -- parse ---------------------------------------------------------------

    def test_a_simple_entry_parses_with_its_whole_metadata_block
      doc = document("SRO1")
      assert_equal "en", doc.language
      assert_equal "a Ryse and wake", doc.title
      meta = doc.metadata
      assert_equal "SRO1", meta["sro_id"]
      assert_equal "A", meta["liber"]
      assert_equal "Register A", meta["register"]
      assert_equal "1557-07-19", meta["sort_date"]
      assert_equal 4, meta["fee_pence"]
      assert_equal "Register A, f.21v", meta["register_ref"]
      assert_equal "I. 74", meta["arber_ref"]
      assert_equal "https://stationersregister.online/entry/SRO1", meta["url"]
      assert_equal ["William pekerynge"], meta["enterers"]
      assert_equal ["William pekerynge"], meta["persons_mentioned"]
      assert_equal(%w[warden warden master], meta["officers"].map { |o| o["role"] })
      assert_equal 1, doc.passages.size
      passage = doc.passages.first
      assert_equal "#{URN}SRO1:1", passage.urn
      assert_equal "To William pekerynge a ballett Called a Ryse and wake iiijd", passage.text
      assert_equal "p", passage.annotations["block"]
    end

    def test_the_company_year_span_dates_an_undated_early_entry
      date = document("SRO1").metadata["date"]
      assert_equal 1557, date["not_before"]
      assert_equal 1558, date["not_after"]
      assert_equal "19 July 1557 - 9 July 1558", date["raw"]
      assert_equal "1557-07-19", date["start"]
      assert_equal "1558-07-09", date["end"]
      refute date.key?("class"), "the entry's own date of record — the artifact basis, no class"
    end

    def test_a_dated_entry_is_a_one_year_envelope_on_the_clerks_day
      date = document("SRO10453").metadata["date"]
      assert_equal 1640, date["not_before"]
      assert_equal 1640, date["not_after"]
      assert_equal date["start"], date["end"]
      assert_equal document("SRO10453").metadata["sort_date"], date["start"]
    end

    def test_multi_block_entries_cite_their_blocks_in_order_and_keep_apparatus_aside
      doc = document("SRO8")
      assert_equal (1..doc.passages.size).map { |n| "#{URN}SRO8:#{n}" }, doc.passages.map(&:urn)
      assert(doc.passages.none? { |p| p.text.include?("Arber:") })
      assert_equal 32, doc.metadata["works"]
      assert(doc.metadata["notes"].any? { |n| n["resp"] == "#arber" })
      assert_equal %w[entered shared annotated incomplete], doc.metadata["status"]
      assert_equal "Women [be] beste whan thay be at Reste", doc.title
      assert_operator doc.metadata["titles"].size, :>=, 30
    end

    def test_annotations_carry_deletions_corrections_foreign_and_places
      assert_equal ["ys"], document("SRO4").passages.first.annotations["deletions"]
      choice = document("SRO9195").passages.last
      assert_equal [{ "sic" => "Coods", "corr" => "Goods" }], choice.annotations["corrections"]
      foreign = document("SRO5992").passages.find { |p| p.annotations["foreign"] }
      refute_nil foreign
      assert_equal ["london"], document("SRO2203").metadata["places_mentioned"]
      refute document("SRO2203").metadata.key?("place"), "mentions are never an origin claim"
    end

    def test_a_cancelled_entry_keeps_its_struck_through_marks
      doc = document("SRO1679")
      assert_equal "A great herball called Dodoneus herball", doc.title
      assert_equal "struck-through", doc.passages.last.annotations["rend"]
      assert_includes doc.metadata["status"], "cancelled"
    end

    def test_a_foreign_licence_target_quarantines_the_file
      Dir.mktmpdir do |dir|
        current = File.join(dir, "Register ", "CURRENT Register")
        FileUtils.mkdir_p(current)
        source = File.read(File.join(FIXTURES, "Register ", "CURRENT Register", "reg_A-updated.xml"))
        File.write(File.join(current, "reg_A-updated.xml"),
                   source.sub("creativecommons.org/licenses/by/4.0/", "creativecommons.org/licenses/by-nc/4.0/"))
        a = adapter
        ref = a.discover(dir).first
        error = assert_raises(Nabu::ParseError) { a.parse(ref) }
        assert_includes error.message, "licence"
      end
    end

    def test_parse_is_memoized_per_file_but_stable_across_instances
      a = adapter
      first = a.discover(FIXTURES).map { |ref| a.parse(ref).urn }
      second = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref).urn }
      assert_equal first, second
    end
  end
end
