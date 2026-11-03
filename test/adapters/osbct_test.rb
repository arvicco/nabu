# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Osbct: the Sixth Buddhist Council Tipiṭaka Unicode corpus
# (IEBH / BTHAR, Zenodo record 23541744, v2.11.0) — the Chaṭṭha Saṅgāyana
# recension of the Pāḷi canon with its Aṭṭhakathā and Ṭīkā, converted from
# the Ministry of Religious Affairs, Yangon romanised edition (2008, from the
# Myanmar edition of 2001). NOT the VRI / Igatpuri CST digital edition.
#
# Document = upstream VOLUME (site/<VOL>.json, 118 in the release); passage
# = upstream paragraph, cited by the paragraph's own key ("<VOL>#<k>" →
# :<k>). The printed apparatus (site/reader/apparatus/<VOL>.appk.json,
# keyed by paragraph ordinal) rides each paragraph's annotations verbatim;
# the edition's inline note markers (a 1–2 digit run glued to a letter —
# upstream's own reader rule) leave the text and ride as offsets.
#
# License: the text by the edition's own notice (free, non-commercial
# distribution — the deposit's LICENSE.md, verbatim in the manifest); the
# deposit's CC BY 4.0 covers only IEBH/BTHAR's derived data → class nc.
class OsbctTest < Minitest::Test
  include AdapterConformance

  DN = "urn:nabu:osbct:08Di03"
  CNDA = "urn:nabu:osbct:44KhuA25"
  PPT = "urn:nabu:osbct:24AbhiT03"

  def conformance_adapter = Nabu::Adapters::Osbct.new

  def conformance_workdir = Nabu::TestSupport.fixtures("osbct")

  def conformance_expected_source_id = "osbct"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def document(urn)
    ref = adapter.discover(workdir).find { |r| r.id == urn } || flunk("no ref #{urn}")
    adapter.parse(ref)
  end

  def passage(urn, citation) = document(urn).find { |p| p.urn == "#{urn}:#{citation}" } || flunk("no #{citation}")

  # -- manifest ---------------------------------------------------------------

  def test_manifest_classes_the_text_by_the_editions_own_notice
    manifest = adapter.manifest
    assert_equal "osbct", manifest.id
    assert_equal "nc", manifest.license_class, "the text: free, non-commercial distribution (the edition's notice)"
    assert_includes manifest.license, "free, non-commercial distribution"
    assert_includes manifest.license, "CC BY 4.0", "the deposit's grant over the derived data is recorded too"
    assert_includes manifest.license, "Ministry of Religious Affairs, Yangon"
    assert_equal "https://zenodo.org/records/23541744", manifest.upstream_url
  end

  # -- discover / skips ---------------------------------------------------------

  def test_discover_yields_one_document_per_volume_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [DN, PPT, CNDA], refs.map(&:id)
    assert_equal(%w[canon subcommentary commentary], refs.map { |ref| ref.metadata["layer"] })
  end

  def test_site_metadata_files_are_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(workdir)
    assert_equal 3, skips.skipped_by_rule, "build.json, concordance.json, downloads.data.json"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("downloads.data.json") })
  end

  def test_a_volume_shaped_file_the_concordance_does_not_place_is_unrecognized
    Dir.mktmpdir("nabu-osbct-stray") do |root|
      FileUtils.cp_r(Dir.glob(File.join(workdir, "*"), File::FNM_DOTMATCH).reject { |p| p.end_with?("/.", "/..") },
                     root)
      FileUtils.cp(File.join(root, "site", "08Di03.json"), File.join(root, "site", "99Xyz01.json"))
      skips = adapter.discovery_skips(root)
      assert_equal 1, skips.unrecognized
      assert_match(/99Xyz01/, skips.notes.join)
      refute(adapter.discover(root).any? { |ref| ref.id.end_with?("99Xyz01") })
    end
  end

  def test_the_id_keyed_apparatus_twin_is_never_read
    # site/reader/apparatus/<VOL>.app.json (keyed by the NON-unique
    # hierarchical id) is outside the fetch cone; the pinned specimen
    # proves discovery and parse never reach it.
    assert File.file?(File.join(workdir, "site/reader/apparatus/44KhuA25.app.json"))
    refute Nabu::Adapters::Osbct.keep?("site/reader/apparatus/44KhuA25.app.json")
    refute(adapter.discover(workdir).any? { |ref| ref.path.include?("/reader/") })
  end

  def test_discover_yields_nothing_before_the_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  # -- documents ---------------------------------------------------------------

  def test_volume_metadata_comes_from_upstreams_own_tables
    doc = document(DN)
    assert_equal "pli", doc.language
    assert_equal "Pāthikavaggapāḷi (08Di03)", doc.title
    meta = doc.metadata
    assert_equal "08Di03", meta["volume"]
    assert_equal "canon", meta["layer"]
    assert_equal "dn-pathika", meta["group"]
    assert_equal "Dīgha Pāthikavagga", meta["group_work"]
    assert_equal({ "layer" => { "value" => "canon", "raw" => "canon" } }, meta["facets"])
    assert_match(/Ministry of Religious Affairs, Yangon/, meta["edition"])
    assert_equal "pali-unicode/08Di03.pdf", meta["source_pdf"]
  end

  def test_a_volume_without_the_vol_and_source_keys_still_parses
    doc = document(PPT)
    assert_equal "Pañcapakaraṇamūlaṭīkā (24AbhiT03)", doc.title
    assert_equal "subcommentary", doc.metadata["layer"]
    assert_equal "tika-unicode/24AbhiT03.pdf", doc.metadata["source_pdf"], "from downloads.data.json"
    assert_equal 5, doc.size
  end

  def test_one_passage_per_paragraph_cited_by_the_paragraph_key
    doc = document(DN)
    assert_equal 6, doc.size
    assert_equal (0..5).map { |k| "#{DN}:#{k}" }, doc.map(&:urn)
  end

  # -- passages ---------------------------------------------------------------

  def test_note_markers_leave_the_text_and_ride_as_offsets
    p = passage(DN, 0)
    assert p.text.start_with?("1. Evaṁ me sutaṁ–ekaṁ samayaṁ Bhagavā Mallesu viharati Anupiyaṁ nāma Mallānaṁ nigamo.")
    assert_includes p.text, "“atippago kho tāva Anupiyāyaṁ piṇḍāya carituṁ"
    refute_match(/\p{L}\d/, p.text)
    markers = p.annotations["note_markers"]
    assert_equal([1, 2], markers.map(&:last))
    offset = markers.first.first
    assert_equal "nāma", p.text[offset - 4, 4], "the offset points just after the annotated word"
  end

  def test_the_printed_apparatus_rides_the_paragraph_verbatim
    notes = passage(DN, 0).annotations["apparatus"]
    assert_equal 2, notes.size
    assert_equal({ "n" => 1, "text" => "Anuppiyaṁ nāma (Syā)",
                   "variants" => [{ "reading" => "Anuppiyaṁ nāma", "sigla" => ["Syā"] }], "xrefs" => [] },
                 notes.first)
    xref = passage(PPT, 3).annotations["apparatus"].first
    assert_equal [{ "work" => "Abhi-Ṭṭha", "vol" => 1, "page" => 8, "also" => false }], xref["xrefs"]
    assert_nil passage(DN, 1).annotations["apparatus"], "no notes, no key"
  end

  def test_paragraph_structure_rides_annotations
    p = passage(DN, 2)
    notes = p.annotations
    assert_equal 2, notes["printed_page"]
    assert_equal 3, notes["paragraph"]
    assert_equal "Pāthikasutta", notes["sutta"]
    assert_equal "Pāthikavaggapāḷi", notes["vagga"]
    assert_equal "X/Pāthikavaggapāḷi/Pāthikasutta/3", notes["path"]
    assert_equal "Pāthikavaggapāḷi", passage(DN, 0).annotations["vagga"]
    title = passage(CNDA, 0)
    assert_equal "Cūḷaniddesaṭṭhakathā", title.text
    assert_equal true, title.annotations["unnumbered"]
    assert_nil title.annotations["paragraph"]
  end

  def test_commentary_markers_and_apparatus_align_by_ordinal
    p = passage(CNDA, 5)
    assert_equal [1], p.annotations["note_markers"].map(&:last)
    assert_equal(["Nirantakaragāmino hutvā savanti (Syā)", "Yadetaṁ (Syā)"],
                 p.annotations["apparatus"].map { |note| note["text"] })
  end

  # -- fetch --------------------------------------------------------------------

  def test_the_fetch_cone_is_text_and_its_tables_only
    keep = ->(rel) { Nabu::Adapters::Osbct.keep?(rel) }
    %w[LICENSE.md README.md CITATION.cff .zenodo.json data/concordance.json site/08Di03.json
       site/downloads.data.json site/reader/apparatus/08Di03.appk.json].each { |rel| assert keep.call(rel), rel }
    %w[site/index/08Di03.idx.json site/reader/verse/08Di03.json stores/lookup/freq/a.json
       pipeline/extract.py data/links_all.json site/t/dn/1.html].each { |rel| refute keep.call(rel), rel }
  end

  def test_fetch_pins_the_v2_11_0_directory
    assert_match %r{\Ahttps://zenodo\.org/api/records/23541744/files/}, Nabu::Adapters::Osbct::ZIP_URL
    assert_equal "3d1c2b1bcc436c3b5f2a8e8d5ae8a9035bb9b54d90afb98cd455def7a44a5f77",
                 Nabu::Adapters::Osbct::DIRECTORY_SHA256
  end

  FakeRange = Struct.new(:sha, :completed, keyword_init: true) do
    def prepare! = nil
    def not_modified? = false
    def doomed_paths = []
    def complete! = (self.completed = true)

    def result
      Nabu::ZipRangeFetch::Result.new(sha: sha, size: 1, kept: 245, skipped: 1, atticked: [],
                                      not_modified: false)
    end
  end

  def test_a_directory_pin_miss_aborts_before_any_tree_change
    fake = FakeRange.new(sha: "0" * 64, completed: false)
    osbct = Nabu::Adapters::Osbct.new(range_fetch: ->(**) { fake })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { osbct.fetch(dir) }
      assert_match(/pin/, error.message)
    end
    refute fake.completed, "complete! never runs on a pin miss"
  end

  def test_a_pinned_directory_lands
    fake = FakeRange.new(sha: Nabu::Adapters::Osbct::DIRECTORY_SHA256, completed: false)
    report = Dir.mktmpdir { |dir| Nabu::Adapters::Osbct.new(range_fetch: ->(**) { fake }).fetch(dir) }
    assert fake.completed
    assert_equal Nabu::Adapters::Osbct::DIRECTORY_SHA256, report.sha
  end
end
