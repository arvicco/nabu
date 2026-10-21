# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::SiiClean (P122-3; widened 2026-10-21): the DHARMA
# conversions of the printed South Indian Inscriptions volumes
# (github.com/erc-dharma/south-indian-inscriptions). Two layers, one
# inscription one document: every SII_B_clean DHARMA_ edition (the
# repository-wide CC BY-SA 4.0 statement of 2026-10-21 covers the files
# without their own <licence>), and the SII_A_raw/3out per-inscription
# conversions for the inscriptions no clean edition holds (a raw file whose
# number range a clean edition covers is superseded, skipped by rule). The
# held dharma-epidoc family does the text; this adapter adds the layer rule
# and mines the SII editors' printed headings (findspot, A.R. number,
# A.D./Śaka dating).
#
# Fixtures: whole real files (see the fixture README) — the grant-bearing
# set of 2026-10-12 plus, at HEAD 76608102 (2026-10-21), a grant-less clean
# edition, a range edition (Nos. 290-293), a bare-"tam" and a Dutch edition,
# a Marathi edition (unheld code: quarantined), the raw layer's Telugu /
# Kannada / Persian conversions and its two quarantine shapes, and the three
# rejected grains: a raw file superseded by an exact clean stem, one
# superseded by a clean range, and a clean ~DHARMA_ in-progress file.
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
  GRANTLESS = "#{PREFIX}INSSIIv17p0i0380".freeze
  RANGE = "#{PREFIX}INSSIIv04p0i0290-0293".freeze
  BARE_TAM = "#{PREFIX}INSSIIv06p0i0004".freeze
  DUTCH = "#{PREFIX}INSSIIv38p0i0029".freeze
  MARATHI = "#{PREFIX}INSSIIv17p0i0559".freeze
  RAW_TELUGU = "#{PREFIX}INSSIIv04p0i0294".freeze
  RAW_SAKA_ABBR = "#{PREFIX}INSSIIv10p0i0697".freeze
  RAW_KANNADA = "#{PREFIX}INSSIIv35p0i0231".freeze
  RAW_SAKA = "#{PREFIX}INSSIIv39p0i0273".freeze
  RAW_PERSIAN = "#{PREFIX}INSSIIv41p0i0058".freeze
  RAW_TEXTLESS = "#{PREFIX}INSSIIv25p0i0241".freeze
  RAW_UND = "#{PREFIX}INSSIIv42p0i0226".freeze
  CLEAN = [SAKA, AD, TELUGU, VILLAGE_FIRST, SUMMARY, AT_SHAPE, SAME,
           GRANTLESS, RANGE, BARE_TAM, DUTCH].freeze
  RAW = [RAW_TELUGU, RAW_SAKA_ABBR, RAW_KANNADA, RAW_SAKA, RAW_PERSIAN].freeze
  QUARANTINED = [STUB, MARATHI, RAW_TEXTLESS, RAW_UND].freeze

  BY_SA = "https://creativecommons.org/licenses/by-sa/4.0/"

  # The quarantine shapes fail by design; the conformance sweep runs over
  # the parseable fixtures of both layers (the dharma-tamil pattern).
  def conformance_adapter
    adapter = Nabu::Adapters::SiiClean.new
    original = adapter.method(:discover)
    adapter.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      original.call(workdir) { |ref| block.call(ref) unless QUARANTINED.include?(ref.id) }
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
    assert_match(/repository-wide CC BY-SA 4\.0/, manifest.license)
  end

  # -- discover: two layers, one inscription one document ----------------------

  def test_discover_yields_every_clean_edition_and_the_unsuperseded_raw_conversions
    refs = adapter.discover(workdir).to_a
    assert_equal (CLEAN + RAW + QUARANTINED).sort, refs.map(&:id).sort,
                 "urn:nabu:sii-clean:<stem sans DHARMA_/~DHARMA_>, one per inscription"
    assert(refs.all? { |ref| ref.source_id == "sii-clean" })
    assert_equal "SII22", refs.find { |ref| ref.id == SAKA }.metadata["volume"]
    assert_equal "SII04", refs.find { |ref| ref.id == RAW_TELUGU }.metadata["volume"],
                 "the raw tree's bare volume dir (04) reads as the clean slice's SII04"
    assert_equal "edition", refs.find { |ref| ref.id == GRANTLESS }.metadata["layer"]
    assert_equal "raw", refs.find { |ref| ref.id == RAW_TELUGU }.metadata["layer"]
  end

  def test_a_raw_conversion_held_by_a_clean_edition_is_superseded_and_censused
    ids = adapter.discover(workdir).map(&:id)
    refute_includes ids, "#{PREFIX}INSSIIv04p0i0290", "inside the clean edition's Nos. 290-293 range"
    assert_includes ids, RAW_TELUGU, "No. 294 lies outside every clean range: the raw text stands in"
    skips = adapter.discovery_skips(workdir)
    assert_equal 3, skips.skipped_by_rule, "raw 22.252 (exact stem) + raw 4.290 (range) + one ~DHARMA_"
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(/SII04: 1 raw conversion\(s\) superseded by a SII_B_clean edition/, notes)
    assert_match(/SII22: 1 raw conversion\(s\) superseded by a SII_B_clean edition/, notes)
    assert_match(/~DHARMA_INSSIIv22p0i0584\.xml: in-progress clean file/, notes)
  end

  def test_inscription_keys_read_ranges_and_letter_suffixes
    key = ->(stem) { Nabu::Adapters::SiiClean.inscription_key(stem) }
    assert_equal ["v04p0", 290..293], key.call("INSSIIv04p0i0290-0293")
    assert_equal ["v13p0", 17..17], key.call("INSSIIv13p0i0017A"), "a lettered number claims its base"
    assert_equal ["v05p1", 2..2], key.call("INSSIIv05p1i0002")
    assert_equal ["INSSIIodd", nil], key.call("INSSIIodd"), "an unparsed stem keys on itself"
  end

  def test_a_clean_edition_without_its_own_grant_is_in_the_cone
    Dir.mktmpdir do |dir|
      volume = File.join(dir, "SII_B_clean", "SII22")
      FileUtils.mkdir_p(volume)
      source = File.read(File.join(workdir, "SII_B_clean", "SII22", "DHARMA_INSSIIv22p0i0252.xml"))
      File.write(File.join(volume, "DHARMA_INSSIIv22p0i0252.xml"),
                 source.sub(%r{<licence target="[^"]+">CC BY-SA 4.0</licence>}, ""))

      assert_equal ["#{PREFIX}INSSIIv22p0i0252"], adapter.discover(dir).map(&:id)
      assert_equal 0, adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  # -- parse: the family text + the licence ------------------------------------

  def test_the_in_file_grant_rides_metadata_verbatim
    document = adapter.parse(ref_for(SAKA))
    assert_equal BY_SA, document.metadata["license"]
    assert_equal "in-file <licence>", document.metadata["license_basis"]
    assert_equal "edition", document.metadata["layer"]
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

  def test_a_grantless_clean_edition_rides_the_repository_statement
    document = adapter.parse(ref_for(GRANTLESS))
    assert_equal BY_SA, document.metadata["license"]
    assert_match(%r{SII_B_clean/README\.txt.*2026-10-21}, document.metadata["license_basis"])
    assert_equal "tam-Latn", document.language
    assert_equal 12, document.passages.size
  end

  def test_a_range_edition_is_one_document
    document = adapter.parse(ref_for(RANGE))
    assert_equal "SII 4.290-293: original edition by H. Krishna Sastri", document.title
    assert_equal "290-293", document.metadata["sii_number"]
    assert_equal "tam-Latn", document.language
  end

  def test_upstream_code_dirt_is_aliased_onto_held_codes
    assert_equal "tam-Latn", adapter.parse(ref_for(BARE_TAM)).language,
                 "bare 'tam' over romanized text (68 clean editions) is tam-Latn"
    persian = adapter.parse(ref_for(RAW_PERSIAN))
    assert_equal "fas-Latn", persian.language, "ISO 639-2/B 'per' is 639-3 'fas'"
    assert_equal "Khāni Zīshān Sa'ādu'l-lāh Khān", persian.passages.first.text
  end

  def test_the_dutch_epitaph_is_held_as_nld_latn
    document = adapter.parse(ref_for(DUTCH))
    assert_equal "nld-Latn", document.language
    assert_match(/\ADes Menschen Leven/, document.passages.first.text)
  end

  def test_an_unheld_language_code_quarantines_loudly
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref_for(MARATHI)) }
    assert_match(/mar-Latn/, error.message, "no Marathi node in the registry: classify first")
  end

  # -- the raw layer ------------------------------------------------------------

  def test_a_raw_conversion_parses_with_its_layer_and_grant
    document = adapter.parse(ref_for(RAW_TELUGU))
    assert_equal "raw", document.metadata["layer"]
    assert_equal BY_SA, document.metadata["license"]
    assert_equal "in-file <licence>", document.metadata["license_basis"]
    assert_equal "tel-Latn", document.language
    assert_equal 4, document.passages.size
    assert_equal "#{RAW_TELUGU}:1", document.passages.first.urn
    assert_equal 4, document.metadata["sii_volume"]
    assert_equal "294", document.metadata["sii_number"]
    assert_equal "SII04", document.metadata["volume"]
  end

  def test_the_raw_layer_carries_kannada
    document = adapter.parse(ref_for(RAW_KANNADA))
    assert_equal "kan-Latn", document.language
    meta = document.metadata
    assert_equal "BYĀHAṬṬI", meta["place"]
    assert_equal "HUBLI", meta["taluk"]
    assert_equal "DHARWAR", meta["district"]
  end

  def test_raw_quarantine_shapes
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref_for(RAW_TEXTLESS)) }
    assert_match(/no citable text|und/, error.message)
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref_for(RAW_UND)) }
    assert_match(/und/, error.message)
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

  def test_the_raw_layer_headings_date_through_the_same_lane
    assert_equal({ "not_before" => 1582, "not_after" => 1582, "raw" => "ŚAKA 1504", "era" => "saka",
                   "era_year" => 1504, "basis" => "title" }, metadata(RAW_SAKA)["date"])
    abbr = metadata(RAW_SAKA_ABBR)
    assert_equal ["Ś. 1066"], abbr["title_dating"]
    assert_equal({ "not_before" => 1144, "not_after" => 1144, "raw" => "Ś. 1066", "era" => "saka",
                   "era_year" => 1066, "basis" => "title" }, abbr["date"],
                 "SII 10's 'Ś. NNNN' is the editors' Śaka abbreviation (513 raw headings)")
  end

  def test_the_saka_abbreviation_never_reads_a_hedged_year
    facts = ->(title) { Nabu::Adapters::SiiClean.title_facts(title) }
    assert_nil facts.call("No. 316. (A.R. No. 175 of 1917.) ON A STONE LYING NEAR A HILLOCK TO THE WEST " \
                          "OF TĀḌIKOṆḌA, GUNTUR TALUK, GUNTUR DISTRICT. Ś. 1169. (?) (Kīlaka)")["date"]
    assert_equal 1147, facts.call("No. 119. (A.R. No. 144 of 1913.) ON A SLAB SET UP IN THE COURTYARD. " \
                                  "Ś. 1069. (Prabhava.)").dig("date", "not_before")
  end

  # Real raw-layer headings (SII 4/6/7/9/10/22) whose findspot sentence
  # opens with a monument description or wraps the name in a gloss.
  def test_place_mining_reads_past_descriptions_and_glosses
    place = ->(title) { Nabu::Adapters::SiiClean.title_facts(title)["place"] }
    assert_equal "MALKĀPURAM", place.call("No. 744. (A.R. No. 152 of 1913.) ON A PILLAR LYING NEAR THE " \
                                          "MUSSALMAN CHĀVAḌI, MALKĀPURAM, GUNTUR TALUK, GUNTUR DISTRICT. Ś. 1452."),
                 "a leading 'ON …' monument segment is description, never the village"
    assert_equal "MAMALLAPURAM", place.call("No. 1. (Annual Report No. 1. of 1887). SHORE TEMPLE AT " \
                                            "MAMALLAPURAM (SEVEN PAGODAS), CHINGLEPUT TALUK, CHINGLEPUT DISTRICT."),
                 "a trailing parenthetical gloss is dropped from the name (it stays in findspot)"
    assert_equal "TIRUMALAI", place.call("No. 282. (A.R. No. 53 of 1889). ON THE SOUTH WALL OF THE SECOND " \
                                         "PRAKARA OF THE SRINIVASAPERUMAL TEMPLE AT TIRUMALAI (NEAR TIRUPATI), " \
                                         "CHANDRAGIRI TALUK, CHITTOOR DISTRICT.")
    assert_nil place.call("No. 74-78. (A.R. Nos. 120 to 124 of 1897). IN A CAVE NEAR SULTANS BATTERY, " \
                          "WYNAAD TALUK, MALABAR DISTRICT."), "a description alone names no village"
    assert_nil place.call("No. 389. (A.R. No. 181-C of 1901). ON A SLAB SET UP IN A LANE AT HOSAKERI IN " \
                          "BARAKUR, SAME TALUK AND DISTRICT."), "'X IN Y' is two places: no claim"
    assert_nil place.call("No. 533. (A.R. No. 533 of 1906) CHITTOOR DISTRICT, MADANAPALLE TALUK, " \
                          "PEDDATIPPASAMUDRAM On a slab set up near the ruined Śiva temple in the " \
                          "Yēnugarāti-maḍi field at the above place."), "'the above place' is inheritance"
    assert_equal "PEDA KOṆḌŪRU", place.call("No. 174. (A.R. No. 695 of 1920.) ON A PILLAR BUILT INTO THE WALL " \
                                            "OF THE TEMPLE OF RĀJĒŚVARA, AT PEDA KOṆḌŪRU, TENALI TALUK, GUNTUR " \
                                            "DISTRICT. Ś. 1092."), "a segment opening with AT names the place"
    assert_equal "SAṄKARĀPURA", place.call("No. 464. (A.R. No. 86 of 1944-45.) SAṄKARĀPURA ALIAS GAṆḌI-BASĀPŪR, " \
                                           "SANDUR TALUK, BELLARY DISTRICT."), "the first of 'X ALIAS Y'"
    assert_nil place.call("No. 617. (A.R. No. 169 of 1892). INSCRIPTIONS FROM WHITEFIELD, BANGALORE DISTRICT " \
                          "(MYSORE)."), "a collection label names no village"
    assert_nil place.call("No. 673. (A.R. No. 223 of 1899). ON A PILLAR IN THE PHATTAR MASJID AT PITHAPURAM; " \
                          "PITHAPURAM DIVISION, GODAVARI DISTRICT."), "semicolon dirt: no claim"
    assert_nil place.call("No. 537. (A.R. No. 537 of 1906) CHITTOOR DISTRICT, MADANAPALLE TALUK, " \
                          "PEDDATIPPASAMUDRAM In a maṇḍapa situated near a field at Pullagaṇṭivāripalle " \
                          "Adhirājēndradēva-3rd Year (A.D. 1070)"), "digits/brackets are never a village"
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

  def test_fetch_sparse_clones_the_clean_editions_and_the_raw_per_inscription_files
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
      assert File.file?(File.join(work, "SII_A_raw", "README.txt"))
      assert File.file?(File.join(work, "SII_A_raw", "3out", "04", "~DHARMA_INSSIIv04p0i0294.xml"))
      refute File.exist?(File.join(work, "SII_B_clean", "SII22", "~DHARMA_INSSIIv22p0i0254.xml")),
             "clean in-progress ~DHARMA_ files stay outside the cone"
      refute File.exist?(File.join(work, "SII_B_clean", "SII17", "SII_to_update.html")), "worklists stay out"
      refute File.exist?(File.join(work, "SII_A_raw", "1orig")), "the contractor's whole-corpus dumps stay out"
      refute File.exist?(File.join(work, "SII_A_raw", "2mastercopy")), "the per-volume master copies stay out"
      assert_equal ["#{PREFIX}INSSIIv04p0i0294", "#{PREFIX}INSSIIv22p0i0252"], sii.discover(work).map(&:id).sort,
                   "the raw 22.252 is superseded by its clean edition"
      assert_equal report.sha, sii.fetch(work).sha, "second call: the pull path"
    end
  end

  private

  def build_upstream(root)
    upstream = File.join(root, "upstream")
    volume = File.join(upstream, "SII_B_clean", "SII22")
    raw = File.join(upstream, "SII_A_raw")
    FileUtils.mkdir_p([volume, File.join(upstream, "SII_B_clean", "SII17"), File.join(raw, "1orig"),
                       File.join(raw, "2mastercopy", "volumes"), File.join(raw, "3out", "04"),
                       File.join(raw, "3out", "22")])
    Nabu::Shell.run("git", "init", "-q", upstream)
    source = File.read(File.join(workdir, "SII_B_clean", "SII22", "DHARMA_INSSIIv22p0i0252.xml"))
    File.write(File.join(volume, "DHARMA_INSSIIv22p0i0252.xml"), source)
    File.write(File.join(volume, "~DHARMA_INSSIIv22p0i0254.xml"), source)
    File.write(File.join(upstream, "SII_B_clean", "README.txt"), "SII_B_clean")
    File.write(File.join(upstream, "SII_B_clean", "SII17", "SII_to_update.html"), "<html/>")
    File.write(File.join(raw, "README.txt"), "SII_A_raw")
    File.write(File.join(raw, "1orig", "sii-all.xml"), "<doc/>")
    File.write(File.join(raw, "2mastercopy", "volumes", "22-1.xml"), "<doc/>")
    %w[04/~DHARMA_INSSIIv04p0i0294.xml 22/~DHARMA_INSSIIv22p0i0252.xml].each do |rel|
      FileUtils.cp(File.join(workdir, "SII_A_raw", "3out", rel), File.join(raw, "3out", rel))
    end
    git(upstream, "add", ".")
    git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
    upstream
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
