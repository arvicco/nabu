# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# BaleyManuscripts adapter tests: Julien Baley's excavated-manuscript
# alignment deposits (Zenodo, CC BY 4.0 project-authored data). Fixture
# (test/fixtures/baley-manuscripts/README.md): two deposits exactly as
# ZipRangeFetch lands their text members — Jinteng 金縢 (the Tsinghua
# manuscript + the received Shangshu chapter, the rejected-grain specimen)
# and Āisòng 哀誦 (the Anda manuscript + Chen Qi's edited reading) — with
# their real alignment and source-mapping files whole.
class BaleyManuscriptsTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("baley-manuscripts")
  PREFIX = "urn:nabu:baley-manuscripts"
  AISONG_ANDA = "#{PREFIX}:aisong:anda".freeze
  AISONG_CHENQI = "#{PREFIX}:aisong:chenqi".freeze
  JINTENG = "#{PREFIX}:jinteng:tsinghua".freeze

  def conformance_adapter = Nabu::Adapters::BaleyManuscripts.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "baley-manuscripts"

  def adapter = Nabu::Adapters::BaleyManuscripts.new

  def document(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  def test_manifest_records_the_cc_by_project_license
    manifest = adapter.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY 4.0"
    assert_includes manifest.license, "witness-images/RIGHTS.md"
    assert_match(/Baley/, manifest.credit)
  end

  def test_discover_takes_manuscript_and_edition_witnesses_in_manifest_order
    assert_equal [AISONG_CHENQI, AISONG_ANDA, JINTENG], adapter.discover(FIXTURES).map(&:id)
  end

  def test_received_text_witnesses_are_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 1, skips.skipped_by_rule
    assert(skips.notes.any? { |note| note.include?("jinteng:shangshu") && note.include?("received") })
  end

  def test_an_unknown_witness_is_unrecognized_not_silently_taken
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "jinteng"), dir)
      path = File.join(dir, "jinteng", "dataset", "manifest.json")
      manifest = JSON.parse(File.read(path))
      manifest["witnesses"] << { "id" => "newfind", "label" => "new" }
      File.write(path, JSON.generate(manifest))
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      refute(adapter.discover(dir).any? { |ref| ref.id.end_with?(":newfind") })
    end
  end

  def test_one_passage_per_manuscript_line
    doc = document(JINTENG)
    assert_equal 30, doc.size
    first = doc.first
    assert_equal "#{JINTENG}:1.1.1", first.urn
    assert_equal "武王既克𰻷，三年，王不𤶠，又𡰥。", first.text
    assert_equal "och", doc.language
    assert_equal "清華大學藏戰國竹簡（壹）《金縢》", doc.title
  end

  def test_ids_transcriptions_ride_verbatim_and_graphs_count_as_upstream_does
    doc = document(JINTENG)
    line = doc.find { |p| p.urn == "#{JINTENG}:1.1.4" }
    before = doc.find { |p| p.urn == "#{JINTENG}:1.1.3" }
    assert_includes line.text, "{⿱尔坦}", "braced IDS graphs stay as transcribed"
    # 周公乃爲三坦，同{⿱尔坦}，爲一坦於南方，周公立𱙁，秉璧{⿱㞢首}珪。 — 22 graphs:
    # each braced expression is one, punctuation none.
    assert_equal 22, line.annotations["graphs"]
    assert_equal 1, doc.first.annotations["graph_start"]
    assert_equal before.annotations["graph_start"] + before.annotations["graphs"], line.annotations["graph_start"],
                 "graph numbering continues across a paragraph's lines"
    assert_equal 411, doc.sum { |p| p.annotations["graphs"] }, "= the deposit's data dictionary (411 graphs)"
  end

  def test_lines_carry_their_slips_and_their_alignment_to_every_other_witness
    first = document(JINTENG).first
    assert_equal ["1"], first.annotations["strips"]
    aligned = first.annotations["aligned"]
    assert_equal ["shangshu"], aligned.keys, "the received partner is named even though it is not held"
    assert_equal ["1.1:1-2", "1.2:1-10"], aligned["shangshu"],
                 "武王 aligns into the Shangshu's preface line, the rest into its first paragraph"
    assert_equal %w[1 2], document(JINTENG).to_a[2].annotations["strips"], "a line running across two slips"
    edition = document(AISONG_CHENQI).first
    assert edition.annotations["aligned"].key?("anda")
    refute edition.annotations.key?("strips"), "an edited reading has no physical slips"
  end

  def test_document_metadata_mines_role_era_and_findspot
    meta = document(JINTENG).metadata
    assert_equal "excavated", meta["witness_role"]
    assert_equal "tsinghua", meta["collection"]
    assert_equal "li_xueqin_2010_QinghuaDaxueCang", meta["reference_transcription"]
    assert_equal "jinteng", meta["dataset_id"]
    assert_equal "10.5281/zenodo.23870159", meta["doi"]
    assert_equal({ "not_before" => -335, "not_after" => -275, "raw" => meta.dig("date", "raw") }, meta["date"])
    assert_nil meta["place"], "the Tsinghua slips are unprovenanced (acquired 2008)"
    assert_equal %w[shangshu], meta["partners"]
    assert_equal "jinteng", meta["work"], "the kind fold's key (kind_map.yml)"
  end

  def test_an_edition_inherits_its_manuscripts_era
    meta = document(AISONG_CHENQI).metadata
    assert_equal "edition", meta["witness_role"]
    assert_equal document(AISONG_ANDA).metadata["date"], meta["date"]
    assert_equal "aisong", meta["work"]
  end

  def test_fetch_ranges_each_deposit_into_its_own_subdir
    calls = []
    fake = lambda do |**kwargs|
      calls << kwargs
      Nabu::ZipRangeFetch::Result.new(sha: "s", size: 1, kept: 1, skipped: 9, atticked: [], not_modified: false)
    end
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::BaleyManuscripts.new(range_fetch: fake).fetch(dir)
      assert_equal 9, calls.size
      assert_equal File.join(dir, "jinteng"), calls.find { |c| c[:url].include?("23870159") }[:dir]
      keep = calls.first[:select]
      assert keep.call("dataset/tsinghua/transcription.json")
      assert keep.call("dataset/alignment.json")
      assert keep.call("LICENSE.md")
      refute keep.call("witness-images/tsinghua/characters/10v.1.2.png"), "never an image"
      refute keep.call("dataset/tsinghua/expected_media.json"), "image geometry is not text"
      refute keep.call("dataset/fuyang/transcription_previous.json"), "a superseded transcription"
      refute keep.call("fonts/odes-ids-glyphs.ttf")
      assert_match(/9 deposits/, report.notes)
    end
  end
end
