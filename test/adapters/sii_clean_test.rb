# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::SiiClean (P122-3): the DHARMA conversions of the printed
# South Indian Inscriptions volumes (github.com/erc-dharma/south-indian-
# inscriptions, SII_B_clean/), ingested ONLY where a file carries its own
# <licence> grant — the repo has none. The held dharma-epidoc family does
# the text; this adapter adds the grant cone and mines the SII editors'
# printed headings (findspot, A.R. number, A.D./Śaka dating).
#
# Fixtures: eight whole real grant-bearing files (retrieved 2026-10-12, see
# the fixture README) — the Śaka heading, the A.D.-range heading, the
# village-first and "AT" findspot shapes, the comma-dirt heading with the
# summary's reign line, a SAME-TEMPLE heading, a Telugu edition, and an
# edition-less stub (the honest quarantine).
class SiiCleanTest < Minitest::Test
  include AdapterConformance

  PREFIX = "urn:nabu:sii-clean:"
  SAKA = "#{PREFIX}INSSIIv22p0i0252".freeze
  AD = "#{PREFIX}INSSIIv22p0i0391".freeze
  TELUGU = "#{PREFIX}INSSIIv22p0i0349".freeze
  STUB = "#{PREFIX}INSSIIv22p0i0408".freeze
  VILLAGE_FIRST = "#{PREFIX}INSSIIv17p0i0656".freeze
  SUMMARY = "#{PREFIX}INSSIIv17p0i0582".freeze
  AT_SHAPE = "#{PREFIX}INSSIIv08p0i0503".freeze
  SAME = "#{PREFIX}INSSIIv08p0i0391".freeze
  CLEAN = [SAKA, AD, TELUGU, VILLAGE_FIRST, SUMMARY, AT_SHAPE, SAME].freeze

  BY_SA = "https://creativecommons.org/licenses/by-sa/4.0/"

  # The edition-less stub quarantines by design; the conformance sweep runs
  # over the seven clean fixtures (the dharma-tamil pattern).
  def conformance_adapter
    adapter = Nabu::Adapters::SiiClean.new
    original = adapter.method(:discover)
    adapter.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      original.call(workdir) { |ref| block.call(ref) if CLEAN.include?(ref.id) }
    end
    adapter
  end

  def conformance_workdir = Nabu::TestSupport.fixtures("sii-clean")

  def conformance_expected_source_id = "sii-clean"

  def adapter = Nabu::Adapters::SiiClean.new

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def metadata(urn) = adapter.parse(ref_for(urn)).metadata

  # -- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_in_the_dharma_family
    manifest = Nabu::Adapters::SiiClean.manifest
    assert_equal "sii-clean", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "dharma-epidoc", manifest.parser_family
    assert_equal "https://github.com/erc-dharma/south-indian-inscriptions", manifest.upstream_url
    assert_match(/DHARMA/, manifest.credit)
    assert_match(/only files bearing their own grant/, manifest.license)
  end

  # -- discover: the grant cone -------------------------------------------------

  def test_discover_yields_every_grant_bearing_edition_across_volumes
    refs = adapter.discover(workdir).to_a
    assert_equal (CLEAN + [STUB]).sort, refs.map(&:id).sort,
                 "urn:nabu:sii-clean:<stem sans DHARMA_>, one per grant-bearing edition"
    assert(refs.all? { |ref| ref.source_id == "sii-clean" })
    assert_equal "SII22", refs.find { |ref| ref.id == SAKA }.metadata["volume"]
  end

  def test_a_file_without_its_own_grant_stays_outside_the_cone_and_is_censused
    Dir.mktmpdir do |dir|
      volume = File.join(dir, "SII_B_clean", "SII22")
      FileUtils.mkdir_p(volume)
      source = File.read(File.join(workdir, "SII_B_clean", "SII22", "DHARMA_INSSIIv22p0i0252.xml"))
      File.write(File.join(volume, "DHARMA_INSSIIv22p0i0252.xml"), source)
      File.write(File.join(volume, "DHARMA_INSSIIv22p0i0253.xml"),
                 source.sub(%r{<licence target="[^"]+">CC BY-SA 4.0</licence>}, ""))
      File.write(File.join(volume, "~DHARMA_INSSIIv22p0i0254.xml"), source)

      assert_equal ["#{PREFIX}INSSIIv22p0i0252"], adapter.discover(dir).map(&:id),
                   "no in-file grant, no ingest; the ~DHARMA_ in-progress file is never a ref"
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      notes = skips.notes.join("\n")
      assert_match(/SII22: 1 edition\(s\) without an in-file <licence> grant/, notes,
                   "grant-less editions are censused per volume")
      assert_match(/~DHARMA_INSSIIv22p0i0254\.xml: not a DHARMA_ edition file/, notes)
    end
  end

  # -- parse: the family text + the grant -------------------------------------

  def test_the_in_file_grant_rides_metadata_verbatim
    document = adapter.parse(ref_for(SAKA))
    assert_equal BY_SA, document.metadata["license"]
    assert_equal "tam-Latn", document.language
    assert_equal "SII 22.252: original edition by G.V. Srinivasa Rao", document.title
    assert_equal 16, document.passages.size
    assert_equal "#{SAKA}:1", document.passages.first.urn
    assert_equal "śvasti śrīmaN makāmaṇṭaleśvara Irācāti Irāca Irācaparameśvara",
                 document.passages.first.text
  end

  def test_a_telugu_edition_mints_tel_latn
    document = adapter.parse(ref_for(TELUGU))
    assert_equal "tel-Latn", document.language
    assert(document.passages.all? { |passage| passage.language == "tel-Latn" })
    assert_equal "class:telugu maturity:undetermined", document.metadata["script_rendition"]
  end

  def test_an_edition_less_stub_quarantines_loudly
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref_for(STUB)) }
    assert_match(/no edition div/, error.message)
  end

  # -- header mining ----------------------------------------------------------

  def test_header_mining_volume_number_editors_summary
    meta = metadata(SAKA)
    assert_equal 22, meta["sii_volume"]
    assert_equal "252", meta["sii_number"]
    assert_equal "G.V. Srinivasa Rao", meta["original_editor"]
    assert_equal ["Emmanuel Francis"], meta["editors"]
    assert_equal "A.R. No. 252 of 1906", meta["annual_report"],
                 "the Annual Report copy number + year, verbatim (never the inscription's date)"
    assert_equal "draft", meta["revision_status"]
    assert_match(/\AThe details of the date are given as Viḷambi/, meta["summary"])
    assert_match(/\ANo\. 252\. \(A\.R\. No\. 252 of 1906\) NORTH ARCOT DISTRICT/, meta["alt_title"])
  end

  def test_district_first_findspot_mints_the_village
    meta = metadata(SAKA)
    assert_equal "NORTH ARCOT DISTRICT, CHEYYAR TALUK, TIRUPPANAṄGĀḌU", meta["findspot"]
    assert_equal "NORTH ARCOT", meta["district"]
    assert_equal "CHEYYAR", meta["taluk"]
    assert_equal "TIRUPPANAṄGĀḌU", meta["place"]
  end

  def test_village_first_findspot_mints_the_village
    meta = metadata(VILLAGE_FIRST)
    assert_equal "ŚRĪNIVĀSANALLŪR", meta["place"]
    assert_equal "MUSIRI", meta["taluk"]
    assert_equal "TIRUCHIRAPPALLI", meta["district"]
  end

  def test_the_at_shape_reads_the_name_after_the_last_at
    meta = metadata(AT_SHAPE)
    assert_equal "GUDIMALLAM", meta["place"]
    assert_equal "GUDIYATTAM", meta["taluk"]
    assert_equal "NORTH ARCOT", meta["district"]
  end

  def test_a_state_unit_is_findspot_text_only
    meta = metadata(AD)
    assert_equal "TIRUCHIRAPALLI DISTRICT, PUDUKKOTTAI STATE, TIRUMAYYAM", meta["findspot"]
    assert_equal "TIRUMAYYAM", meta["place"]
    refute meta.key?("taluk")
  end

  def test_ambiguous_or_inherited_headings_claim_no_place
    comma_dirt = metadata(SUMMARY)
    assert_equal "TIRUVĀRŪR, NAGAPATTINAM, TALUK, TANJORE DISTRICT", comma_dirt["findspot"]
    refute comma_dirt.key?("place"), "two candidate names: no claim"
    same = metadata(SAME)
    refute same.key?("findspot"), "'…OF THE SAME TEMPLE' names no unit"
    refute same.key?("place"), "the preceding entry's place is never inherited"
  end

  # -- the date lane ------------------------------------------------------------

  def test_a_saka_heading_converts_through_the_era_table
    meta = metadata(SAKA)
    assert_equal ["Śaka 1460"], meta["title_dating"]
    assert_equal({ "not_before" => 1538, "not_after" => 1538, "raw" => "Śaka 1460",
                   "era" => "saka", "era_year" => 1460, "basis" => "title" }, meta["date"])
  end

  def test_the_editors_ad_range_wins_and_expands
    meta = metadata(AD)
    assert_equal ["A.D. 1003-04"], meta["title_dating"]
    assert_equal({ "not_before" => 1003, "not_after" => 1004, "raw" => "A.D. 1003-04",
                   "basis" => "title A.D." }, meta["date"])
  end

  def test_the_summary_reign_line_dates_a_heading_without_one
    meta = metadata(SUMMARY)
    refute meta.key?("title_dating")
    assert_equal({ "not_before" => 1184, "not_after" => 1185, "raw" => "Year 8: 1184-85 A.D.",
                   "basis" => "summary A.D." }, meta["date"])
  end

  def test_title_facts_cover_the_censused_shapes
    facts = ->(title) { Nabu::Adapters::SiiClean.title_facts(title) }
    assert_equal 1395, facts.call("No. 1. (A.R. No. 1 of 1906) X DISTRICT, Y TALUK, Z. VIRŪPĀKSHA (II)—" \
                                  "ŚAKA 1317, PAṄGUṈI, 2. (A.D. 1395)")["date"]["not_before"],
                 "both printed: the editor's A.D. wins"
    assert_equal 1369, facts.call("No. 2. (A.R. No. 2 of 1906) SAUMYA (= Śaka 1291—A.D. 1369-70)")
                            .dig("date", "not_before")
    assert_equal 1338, facts.call("No. 3. (A.R. No. 3 of 1906) BALLĀḶA—ŚAKA 1260, PRAMĀTHI.")
                            .dig("date", "not_before"), "the upper-case spelling resolves"
    assert_equal 1000, Nabu::Adapters::SiiClean.expand_year("999", "1000")
    assert_equal 1534, Nabu::Adapters::SiiClean.expand_year("1533", "34")
    assert_empty facts.call("")
  end

  def test_hedged_summary_readings_are_never_dated
    date = ->(summary) { Nabu::Adapters::SiiClean.summary_date(summary) }
    assert_nil date.call("Rājādhirāja II. Year 5: 1167 A.D. (?).")
    assert_nil date.call("Rājēndra III. Year 13: 1259 A.D. Year 20: 1265-66 A.D."),
               "more than one reign line: no single claim"
    assert_nil date.call("might probably correspond to Śaka 1271")
  end

  def test_the_source_registers_in_the_metadata_dates_lane
    dates = Nabu::Store::TimelineBuilder::MetadataDates
    assert_equal :structured, dates::SHAPES["sii-clean"]
    refute_includes dates::COMPOSITION, "sii-clean", "an inscription's own year dates the object"
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_sparse_clones_only_the_edition_cone
    Dir.mktmpdir("nabu-sii-clean-fetch") do |root|
      upstream = build_upstream(root)
      work = File.join(root, "canonical")
      sii = Nabu::Adapters::SiiClean.new
      sii.define_singleton_method(:repo_url) { upstream }

      report = sii.fetch(work)

      assert_instance_of Nabu::FetchReport, report
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      assert File.file?(File.join(work, "SII_B_clean", "SII22", "DHARMA_INSSIIv22p0i0252.xml"))
      assert File.file?(File.join(work, "SII_B_clean", "README.txt"))
      refute File.exist?(File.join(work, "SII_B_clean", "SII22", "~DHARMA_INSSIIv22p0i0254.xml")),
             "in-progress ~DHARMA_ files stay outside the cone"
      refute File.exist?(File.join(work, "SII_A_raw")), "the raw conversion stages stay out"
      assert_equal ["#{PREFIX}INSSIIv22p0i0252"], sii.discover(work).map(&:id)
      assert_equal report.sha, sii.fetch(work).sha, "second call: the pull path"
    end
  end

  private

  def build_upstream(root)
    upstream = File.join(root, "upstream")
    volume = File.join(upstream, "SII_B_clean", "SII22")
    FileUtils.mkdir_p([volume, File.join(upstream, "SII_A_raw", "3out")])
    Nabu::Shell.run("git", "init", "-q", upstream)
    source = File.read(File.join(workdir, "SII_B_clean", "SII22", "DHARMA_INSSIIv22p0i0252.xml"))
    File.write(File.join(volume, "DHARMA_INSSIIv22p0i0252.xml"), source)
    File.write(File.join(volume, "~DHARMA_INSSIIv22p0i0254.xml"), source)
    File.write(File.join(upstream, "SII_B_clean", "README.txt"), "SII_B_clean")
    File.write(File.join(upstream, "SII_A_raw", "3out", "raw.xml"), "<doc/>")
    git(upstream, "add", ".")
    git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
    upstream
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
