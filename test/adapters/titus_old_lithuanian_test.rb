# frozen_string_literal: true

require "test_helper"

# TITUS Old Lithuanian adapter tests: the multi-edition titus_levels
# family (one TitusFetch walk per edition, one document per page, units
# at the printed line / verse / paragraph). Fixtures are FULL real pages —
# Mažvydas's Catechism (XLevel lines), the Wolfenbüttel Postil (Level
# lines, quotation-class lanes, Bible references), Donelaitis's Metai
# (verses) — plus the skip class (Vilentas's notes page), every accepted
# edition's frameset + index frames (the page census), and the two
# REJECTED Szyrwid editions' index frames (Polish text, Latin notes).
#
# The bytes are gated (no redistribution), so they live under the
# gitignored local/fixtures/titus-old-lithuanian/ (its README carries the
# re-cut recipe + sha256); every data-bearing case SKIPs when absent — on
# the owner's box StrictSkips makes a skip fail.
class TitusOldLithuanianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-old-lithuanian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  URN = "urn:nabu:titus-old-lithuanian"
  ADAPTER = Nabu::Adapters::TitusOldLithuanian

  def conformance_adapter = ADAPTER.new

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id = SLUG

  def setup
    @adapter = ADAPTER.new
  end

  def documents
    require_fixtures!
    @documents ||= @adapter.discover(FIXTURES).to_h { |ref| [ref.id.split(":").last, @adapter.parse(ref)] }
  end

  def passage(urn)
    documents.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_carries_the_credit_duty_for_every_edition
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_levels", manifest.parser_family
    assert_equal "nc", manifest.license_class
    %w[TITUS Gelumbeckaitė Dini Ardoino Thies Young Ritter Keydana].each do |name|
      assert_includes manifest.credit, name
    end
    assert_match(/contact TITUS for a license grant/, manifest.license)
  end

  # --- the census -----------------------------------------------------------

  def test_the_index_frames_census_188_pages_in_the_accepted_editions
    require_fixtures!
    census = ADAPTER::EDITIONS.to_h do |id, edition|
      [id, Nabu::TestSupport::TitusIndexCensus.pages(File.join(FIXTURES, id), edition.prefix)]
    end
    assert_equal({ "dzuk" => 3, "mazvga" => 5, "forma" => 13, "mazvkat" => 10, "wp" => 75, "spslt" => 25,
                   "dauksakt" => 5, "vilentas" => 16, "lysius" => 13, "engels" => 19, "donmetai" => 4 }, census)
    assert_equal 188, census.values.sum
  end

  def test_szyrwids_polish_text_and_latin_notes_are_rejected_editions
    require_fixtures!
    refute ADAPTER::EDITIONS.key?("spspl"), "the Polish text is not Lithuanian"
    refute ADAPTER::EDITIONS.key?("spsnt"), "the Latin notes are the editor's apparatus"
    assert_equal 25, Nabu::TestSupport::TitusIndexCensus.pages(File.join(FIXTURES, "spspl"), "spspl")
    assert_equal 2, Nabu::TestSupport::TitusIndexCensus.pages(File.join(FIXTURES, "spsnt"), "spsnt")
    refute(@adapter.discover(FIXTURES).any? { |ref| ref.path.include?("/spsp") })
  end

  def test_the_siglum_years_are_upstreams_own_text_sigla
    # Daukša, Vilentas and Lysius: the index frame names the text with its
    # print year ("Kat.1595"); the edition date transcribes exactly that.
    require_fixtures!
    { "dauksakt" => "dauksx.htm", "vilentas" => "vilenx.htm", "lysius" => "lysiux.htm" }.each do |id, frame|
      siglum = File.read(File.join(FIXTURES, id, frame))[/NAME="TT2" VALUE="([^"]+)"/, 1]
      date = ADAPTER::EDITIONS.fetch(id).date
      assert_equal siglum, date["raw"]
      assert_equal Integer(siglum[/\d{4}/], 10), date["not_before"]
      assert_equal "edition", date["class"]
    end
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_yields_one_document_per_lithuanian_page
    require_fixtures!
    assert_equal %w[donmetai.donme001 engels.engel001 mazvga.mazvg005 mazvkat.mazvk004 mazvkat.mazvk010
                    spslt.spslt015 wp.wp002 wp.wp075],
                 @adapter.discover(FIXTURES).map { |ref| ref.id.split(":").last }.sort
  end

  def test_the_notes_page_skips_by_rule_with_accounting
    require_fixtures!
    refute(@adapter.discover(FIXTURES).any? { |ref| ref.path.end_with?("vilen016.htm") })
    skips = @adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule, "Vilentas's N. page: footnote lanes only"
    assert_equal 0, skips.unrecognized
    assert_match(/notes pages/, skips.notes.join)
  end

  # --- Mažvydas: the printed line as an XLevel ------------------------------

  def test_mazvydas_lines_are_the_xlevel_lines
    document = documents.fetch("mazvkat.mazvk004")
    assert_equal "lit", document.language
    assert_equal "Old Lithuanian — Martynas Mažvydas, Katekizmas (mazvk004)", document.title
    assert_equal 39, document.passages.size
    line = passage("#{URN}:mazvkat.mazvk004:Mazv._Cat._I._Decal._18/22_12")
    assert_equal "Ne tureki kytu Diewu preg manes.", line.text
    assert_equal({ "unit" => "Line" }, line.annotations)
    broken = passage("#{URN}:mazvkat.mazvk004:Mazv._Cat._I._Decal._18/22_14")
    assert_equal "Negimki warda pana, Diewa tawa na-", broken.text,
                 "the hyphen-broken fragment lane is text, the break kept as printed"
    assert_equal "praſnai.", passage("#{URN}:mazvkat.mazvk004:Mazv._Cat._I._Decal._18/22_15").text
  end

  def test_a_page_header_mid_page_locates_the_following_lines
    line = passage("#{URN}:mazvkat.mazvk004:Mazv._Cat._I._Decal._19/23_2")
    assert_equal "19/23", line.annotations["page"]
  end

  # --- the Wolfenbüttel Postil ----------------------------------------------

  def test_the_postil_lines_carry_folio_and_their_bible_references
    document = documents.fetch("wp.wp002")
    assert_equal 317, document.passages.size
    first = passage("#{URN}:wp.wp002:WP_Dom._1_Adv._1r_1")
    assert_equal "NEDEELIAN PIRMAN ADVEN=", first.text
    assert_equal({ "unit" => "Line", "page" => "1r" }, first.annotations)
    referenced = document.passages.select { |p| p.annotations.key?("reference") }
    refute_empty referenced
    assert_equal "Mt._21_1", passage("#{URN}:wp.wp002:WP_Dom._1_Adv._1r_5").annotations["reference"]
  end

  def test_the_postils_latin_rides_its_annotation
    latin = documents.fetch("wp.wp002").passages.select { |p| p.annotations.key?("latin") }
    assert_equal 13, latin.size
    refute(latin.any? { |p| p.text.include?("CAPITVLVM") })
  end

  # --- the first retrieval's quarantine classes (2026-11-12: 27 pages) -----

  # Mažvydas's German source lines (oend*, the Old Prussian family's German
  # lane) ride the german annotation, never the text. The German-only
  # heading unit ("Nu bittenn wir…" with no Lithuanian beside it) mints no
  # passage at all — the no-text drop — so its words appear nowhere.
  def test_mazvydas_german_source_lines_ride_the_german_annotation
    document = documents.fetch("mazvkat.mazvk010")
    german = document.passages.select { |p| p.annotations.key?("german") }
    refute_empty german
    assert(german.any? { |p| p.annotations["german"].include?("Vater vn") })
    refute(document.passages.any? do |p|
      p.text.include?("bittenn") || p.annotations.values.any? { |v| v.to_s.include?("bittenn") }
    end)
  end

  # The bali* lane is the editors' MODERN Lithuanian layer (normalized
  # renderings and editorial headings beside the baal old text) — it rides
  # the interpretation annotation, never the text.
  def test_the_editors_modern_lithuanian_rides_the_interpretation_annotation
    document = documents.fetch("mazvga.mazvg005")
    assert(document.passages.any? { |p| p.annotations.key?("interpretation") })
    refute(document.passages.any? { |p| p.text.include?("Apie Mažvydo") })
    assert(document.passages.any? { |p| p.text.include?("Chriſtus") }, "the baal old text is the text")
  end

  # The bpla* lane is the LATIN parallel (the -la stem): Szyrwid's "&c."
  # rubric runs and Engel's "Dicat" route to the latin annotation.
  def test_the_latin_la_lane_rides_the_latin_annotation
    spslt = documents.fetch("spslt.spslt015")
    assert(spslt.passages.any? { |p| p.annotations.key?("latin") })
    assert documents.key?("engels.engel001"), "the drop-cap title page parses"
  end

  # The Wolfenbüttel apparatus's quire-signature furniture (oec) is
  # excluded; the page parses instead of quarantining.
  def test_the_postil_apparatus_quire_signature_is_excluded
    assert documents.key?("wp.wp075")
    refute(documents.fetch("wp.wp075").passages.any? { |p| p.text.strip == "B" })
  end

  # --- Donelaitis -----------------------------------------------------------

  def test_donelaitis_verses_and_the_season_title
    document = documents.fetch("donmetai.donme001")
    assert_equal 662, document.passages.size, "the season's title + 661 verses"
    assert_equal "Pawasario Linksmybės", passage("#{URN}:donmetai.donme001:Donelait._Met._1").text
    verse = passage("#{URN}:donmetai.donme001:Donelait._Met._1_1")
    assert_equal "Iau Sauléle wėl atkópdămă buddı̆nŏ Swieta", verse.text
    assert_equal({ "unit" => "Verse" }, verse.annotations)
    assert_equal "Kristijonas Donelaitis", document.metadata["page_title"]
    assert_match(/Keydana/, document.metadata["data_entry"])
    refute document.metadata.key?("date"), "the header names only the 1977 edition — no claim"
  end

  def test_document_metadata_names_the_edition_and_its_kind_key
    metadata = documents.fetch("wp.wp002").metadata
    assert_equal "wp", metadata["edition"]
    assert_equal "wp", metadata["work"]
    assert_equal "J. Gelumbeckaite (Frankfurt)", metadata["editors"]
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (no redistribution — bytes live in local/fixtures/, never in git)"
  end
end
