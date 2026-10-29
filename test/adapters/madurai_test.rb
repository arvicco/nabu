# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Madurai (P122-3): Project Madurai's classical-Tamil cone
# — the works list's genre rule picks the pre-modern e-texts, the
# madurai-html family reads them at physical-line grain, the header page
# (the distribution condition) rides every document.
#
# The fixture bytes live under the gitignored local/fixtures/madurai/: the
# project permits free distribution of each file only with its header page
# intact, and asks to be contacted before online redistribution — a public
# git repository is online redistribution, so the public repo carries no
# Project Madurai bytes (that dir's README records the re-cut recipe).
# Every data-bearing case SKIPS when the dir is absent; on the owner's box
# StrictSkips turns a skip into a failure.
class MaduraiTest < Minitest::Test
  include AdapterConformance

  SLUG = "madurai"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  AUVAIYAR = "urn:nabu:madurai:pmuni0002"
  NANMANI = "urn:nabu:madurai:pmuni0047"

  def require_fixtures!
    skip "local/fixtures/madurai absent (Project Madurai bytes stay out of the public repo)" unless
      Nabu::TestSupport.local_fixtures?(SLUG)
  end

  def conformance_adapter = Nabu::Adapters::Madurai.new

  def conformance_expected_source_id = SLUG

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def adapter = Nabu::Adapters::Madurai.new

  def ref_for(urn)
    adapter.discover(conformance_workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  # -- manifest + the rule ------------------------------------------------------

  def test_manifest_is_attribution_with_the_header_condition
    manifest = Nabu::Adapters::Madurai.manifest
    assert_equal SLUG, manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "madurai-html", manifest.parser_family
    assert_match(/provided this header page is kept intact/, manifest.license)
    assert_match(/Project Madurai/, manifest.credit)
  end

  def test_the_classical_genre_rule
    classical = ->(genre) { Nabu::Adapters::Madurai.classical_genre?(genre) }
    ["சங்ககாலம் - பத்துப்பாட்டு", "சங்ககாலம் – எட்டுத்தொகை", "நீதிநெறி – பதினெண்கீழ்க்கணக்கு",
     "சமயம் - சைவம்", "சமயம் - வைணவம்", "சைவ சித்தாந்தம்", "பிரபந்தம் - பிள்ளைத்தமிழ்",
     "புராணம்", "காப்பியம்", "இதிகாசம்", "இலக்கணம்", "இலக்கண நூல்", "நிகண்டு",
     "சிற்‌றிலக்கியம் /பிரபந்தம்", "இலக்கியம் - கலிவெண்பா"].each do |genre|
      assert classical.call(genre), "#{genre} is pre-modern"
    end
    ["நாவல் - புதினம்", "சிறுகதைகள் தொகுப்பு", "கட்டுரைகள்", "சமயம் – கிருத்துவம்",
     "கவிதைகள்", "நாடகம்", "வரலாறு / சரித்திரம்", "பிரபந்தம் - சதகம், ஆங்கில மொழிபெயர்ப்பு",
     "காப்பியம் - ஆராய்ச்சி", "சமயம் - சைவம், ஆராய்ச்சிக் கட்டுரைகள்", "புராணச் சுருக்கம்",
     ""].each do |genre|
      refute classical.call(genre), "#{genre.inspect} stays out"
    end
  end

  # -- discover: the cone ---------------------------------------------------------

  def test_discover_yields_the_in_scope_files_on_disk_with_their_catalog_rows
    refs = adapter.discover(conformance_workdir).to_a
    assert_equal [AUVAIYAR, NANMANI], refs.map(&:id)
    meta = refs.first.metadata
    assert_equal ["ஆத்திசூடி", "கொன்றை வேந்தன்", "நல்வழி", "மூதுரை"], meta["titles"]
    assert_equal ["ஒளவையார்"], meta["authors"]
    assert_equal ["நீதிநெறி நூல்கள்"], meta["genres"]
    assert_equal %w[2], meta["work_numbers"]
  end

  def test_discovery_skips_census_the_outside_and_the_missing
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(conformance_workdir, "pmworks.html"), dir)
      etexts = File.join(dir, "pm_etexts", "utf8")
      FileUtils.mkdir_p(etexts)
      source = File.join(conformance_workdir, "pm_etexts", "utf8", "pmuni0047.html")
      FileUtils.cp(source, File.join(etexts, "pmuni0047.html"))
      FileUtils.cp(source, File.join(etexts, "pmuni0223_01.html")) # a novel's slot
      FileUtils.cp(source, File.join(etexts, "pmuni0660.html")) # the mixed-genre file

      assert_equal [NANMANI], adapter.discover(dir).map(&:id),
                   "a modern genre and a mixed classical/modern file both stay out"
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule
      missing = skips.notes.grep(/not on disk/)
      assert_equal 3, skips.unrecognized, "pmuni0002 + the two Tiruvācakam parts are in the cone"
      assert_equal 3, missing.size
      assert_match(/2 e-text file\(s\) outside the classical cone/, skips.notes.join("\n"))
    end
  end

  def test_no_works_list_no_cone
    Dir.mktmpdir do |dir|
      assert_empty adapter.discover(dir).to_a
      assert_match(/pmworks\.html missing/, adapter.discovery_skips(dir).notes.join)
    end
  end

  # -- parse ------------------------------------------------------------------------

  def test_parse_mints_tamil_lines_with_the_header_riding
    document = adapter.parse(ref_for(NANMANI))
    assert_equal "tam", document.language
    assert_equal "நான்மணிக்கடிகை", document.title
    assert_equal 431, document.passages.size
    first = document.passages.first
    assert_equal "#{NANMANI}:1", first.urn
    assert_equal({ "heading" => true }, first.annotations)
    assert_equal "மதிமன்னு மாயவன் வாள்முகம் ஒக்கும்", document.passages[2].text
    assert(document.passages.all? { |passage| passage.language == "tam" })
    meta = document.metadata
    assert_match(/provided this header page is kept intact/, meta["pm_header"])
    assert_match(/last revised on 3 August 2021/, meta["pm_footer"])
    assert_equal 0, meta["non_tamil_lines"]
    assert_equal ["விளம்பிநாகனார்"], meta["authors"]
  end

  # -- the OCR label (text_nature) ----------------------------------------------------

  # Verbatim header sentences from canonical/madurai (pmuni0743 and the
  # census variants): every OCR-mentioning header also states the correction.
  OCR_PROOFREAD = "The e-text has been generated using Google OCR online tool and subsequent proof-reading."

  def test_an_ocr_header_with_a_correction_claim_is_corrected_ocr
    nature = ->(header) { Nabu::Adapters::Madurai.text_nature(header) }
    assert_equal "corrected-ocr", nature.call(OCR_PROOFREAD)
    assert_equal "corrected-ocr", nature.call("The raw text file was generated using Google OCR and the text was " \
                                              "subsequently corrected for any OCR errors.")
    assert_equal "corrected-ocr", nature.call("This e-text has been generated using Google OCR and subsequently " \
                                              "edited by K.Kalyanasundaram.")
    assert_nil nature.call("Etext Preparation (input, proof-reading): Ms. Sarala Sandirasegarane"),
               "hand-keyed input is not OCR"
    assert_equal "ocr-origin", nature.call("The e-text has been generated using Google OCR online tool."),
                 "pmuni0752: OCR without a stated correction is not claimed corrected"
  end

  def test_hand_keyed_fixtures_carry_no_text_nature
    refute adapter.parse(ref_for(NANMANI)).metadata.key?("text_nature")
  end

  def test_an_ocr_proofread_header_stamps_the_document
    require_fixtures!
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      path = File.join(dir, "pm_etexts", "utf8", "pmuni0047.html")
      html = File.read(path)
      File.write(path, html.sub("Our Sincere thanks go to", "#{OCR_PROOFREAD}<br>\nOur Sincere thanks go to"))
      ref = adapter.discover(dir).find { |r| r.id == NANMANI }
      assert_equal "corrected-ocr", adapter.parse(ref).metadata["text_nature"]
    end
  end

  def test_a_multi_title_file_joins_its_catalog_titles
    document = adapter.parse(ref_for(AUVAIYAR))
    assert_equal "ஆத்திசூடி / கொன்றை வேந்தன் / நல்வழி / மூதுரை", document.title
    assert_equal 519, document.passages.size
    assert_equal "ஆத்தி சூடி அமர்ந்த தேவனை", document.passages[3].text
  end

  # -- fetch (WebMock, no network) ------------------------------------------------

  def test_fetch_gets_the_works_list_then_only_the_cone
    catalog = File.binread(File.join(conformance_workdir, "pmworks.html"))
    stub_request(:get, "https://www.projectmadurai.org/pmworks.html").to_return(status: 200, body: catalog)
    stub_request(:get, %r{\Ahttps://www\.projectmadurai\.org/pm_etexts/utf8/})
      .to_return(status: 200, body: "etext")
    Dir.mktmpdir do |dir|
      madurai = adapter.tap { |instance| instance.define_singleton_method(:fetch_delay) { 0 } }
      report = madurai.fetch(dir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{64}\z/, report.sha)
      %w[pmuni0002.html pmuni0003_01.html pmuni0003_02.html pmuni0047.html].each do |file|
        assert File.file?(File.join(dir, "pm_etexts", "utf8", file)), "#{file} is in the cone"
      end
      refute File.exist?(File.join(dir, "pm_etexts", "utf8", "pmuni0223_01.html")), "a novel is never fetched"
      refute File.exist?(File.join(dir, "pm_etexts", "utf8", "pmuni0019_01.html")), "nor mission literature"
      refute File.exist?(File.join(dir, "pm_etexts", "utf8", "pmuni0660.html")), "nor a mixed file"
      assert File.file?(File.join(dir, "pmworks.html")), "the works list is fetched beside the cone"
      assert_requested :get, %r{/pm_etexts/utf8/}, times: 4
    end
  end

  def test_a_dead_catalog_link_is_skipped_and_named_and_a_delisted_page_atticked
    catalog = File.binread(File.join(conformance_workdir, "pmworks.html"))
    stub_request(:get, "https://www.projectmadurai.org/pmworks.html").to_return(status: 200, body: catalog)
    stub_request(:get, %r{\Ahttps://www\.projectmadurai\.org/pm_etexts/utf8/})
      .to_return(status: 200, body: "etext")
    stub_request(:get, "https://www.projectmadurai.org/pm_etexts/utf8/pmuni0003_02.html").to_return(status: 404)
    Dir.mktmpdir do |dir|
      stale = File.join(dir, "pm_etexts", "utf8", "pmuni0999.html")
      FileUtils.mkdir_p(File.dirname(stale))
      File.write(stale, "a page the works list no longer names")
      madurai = adapter.tap { |instance| instance.define_singleton_method(:fetch_delay) { 0 } }
      report = madurai.fetch(dir, force: true)
      assert_match(%r{404 on the works list's own links: pm_etexts/utf8/pmuni0003_02\.html}, report.notes)
      refute File.exist?(File.join(dir, "pm_etexts", "utf8", "pmuni0003_02.html"))
      assert File.file?(File.join(dir, "pm_etexts", "utf8", "pmuni0003_01.html")), "the rest of the cone lands"
      refute File.exist?(stale), "the delisted page leaves the live tree"
      assert File.file?(File.join(dir, ".attic", "pm_etexts", "utf8", "pmuni0999.html")), "…into the attic"
    end
  end

  def test_fetch_failure_is_a_fetch_error
    stub_request(:get, "https://www.projectmadurai.org/pmworks.html").to_return(status: 503)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
    end
  end
end
