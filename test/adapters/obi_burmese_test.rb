# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::ObiBurmese (P92-3): the Structured Corpus of Old Burmese
# Stone Inscriptions (Zenodo 4321314, CC BY 4.0) — per-face structured
# text files, Myanmar-script Unicode + paired transliteration. Fixtures:
# three whole real volume-7 files (see the fixture README) covering the
# faced, face-less and lettered-number filename shapes.
class ObiBurmeseTest < Minitest::Test
  include AdapterConformance

  NO3A = "urn:nabu:obi-burmese:vol7:3a:ob"
  NO36 = "urn:nabu:obi-burmese:vol7:36"
  NO19B = "urn:nabu:obi-burmese:vol7:19b:re"

  def conformance_adapter = Nabu::Adapters::ObiBurmese.new

  def conformance_workdir = Nabu::TestSupport.fixtures("obi-burmese")

  def conformance_expected_source_id = "obi-burmese"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn }
  end

  def test_manifest
    manifest = Nabu::Adapters::ObiBurmese.manifest
    assert_equal "obi-burmese", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "obi-txt", manifest.parser_family
  end

  def test_discover_mints_face_grain_urns_from_the_three_filename_shapes
    assert_equal [NO19B, NO36, NO3A], adapter.discover(workdir).map(&:id),
                 "vol:number[:face] — the face-less three-underscore shape included"
  end

  def test_no3a_parses_lines_with_transliteration_annotations
    document = adapter.parse(ref_for(NO3A))
    assert_equal "obr", document.language
    assert_match(/သရပိုလ်/, document.title, "the Myanmar half of the bilingual TITLE")
    assert_match(/sarapuil/, document.metadata["title_translit"])
    assert_equal "obverse", document.metadata["face"]
    line1 = document.passages.first
    assert_equal "#{NO3A}:1", line1.urn
    assert_match(/သကရစ် ၅၃၅ ခု/, line1.text, "Myanmar-script Unicode is the passage text")
    assert_match(/sakarac\Sʻ?\s*535/, line1.annotations["translit"],
                 "the ¤ lane rides annotations, the aozora ruby shape")
  end

  def test_ftn_markers_are_stripped_from_both_lanes
    document = adapter.parse(ref_for(NO3A))
    document.passages.each do |passage|
      refute_match(/ftn|<|>/, passage.text)
      refute_match(/ftn/, passage.annotations["translit"].to_s)
    end
  end

  def test_footnote_section_lines_are_not_passages
    document = adapter.parse(ref_for(NO36))
    numbers = document.passages.map { |p| p.urn.split(":").last.to_i }
    assert_equal numbers.sort, numbers
    assert_equal 1, numbers.first, "footnote entries before INSCRIPTION never mint"
  end

  # The page-based files sometimes carry the START of the next
  # inscription (No36's page runs into No37's heading, line numbers
  # restarting at ၁): the heading opens a section and its lines mint
  # "<section>.<n>" keys — no duplicate urns, nothing dropped.
  def test_an_intra_file_next_inscription_opens_a_section
    document = adapter.parse(ref_for(NO36))
    urns = document.passages.map { |p| p.urn.split(":").last }
    assert_includes urns, "1", "the file's own inscription keeps bare line keys"
    assert_includes urns, "37.1", "inscription 37's restart mints section keys"
    assert_equal ["37"], document.metadata["sections"]
    refute_includes document.passages.map(&:text).join, "<pg>",
                    "page markers are milestones, dropped"
  end

  def test_a_file_with_no_inscription_lines_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vol1"))
      File.write(File.join(dir, "vol1", "OBI_Vol1_No9__ob_p1.txt"),
                 "OBI CORPUS REF: OBI vol1 n°9 ob p1\nTITLE: x\n INSCRIPTION: \n")
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_an_off_shape_filename_is_censused
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vol1"))
      File.write(File.join(dir, "vol1", "notes.txt"), "scratch")
      assert_empty adapter.discover(dir).to_a
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(/notes\.txt/, skips.notes.join(" "))
    end
  end
end
