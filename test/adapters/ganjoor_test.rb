# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"

# Ganjoor adapter tests: the classical cone of the Ganjoor Persian poetry
# library (ganjoor.net), read from the desktop release database through the
# ganjoor-sqlite family, with the site's poets endpoint as the dating /
# placing / publication sidecar. Fixture: an eleven-poem real slice (eight
# accepted, three rejected-by-rule specimens) + seven endpoint records.
class GanjoorTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ganjoor")
  GHAZAL1 = "urn:nabu:ganjoor:hafez:2130"
  RUBAI = "urn:nabu:ganjoor:hafez:2051"
  SHAMS = "urn:nabu:ganjoor:moulavi:2996"
  GOLESTAN = "urn:nabu:ganjoor:saadi:41334"
  ARABIC = "urn:nabu:ganjoor:saadi:10680"
  RUDAKI = "urn:nabu:ganjoor:roodaki:25300"
  ACCEPTED = [RUBAI, GHAZAL1, "urn:nabu:ganjoor:hafez:2131", SHAMS, ARABIC, RUDAKI,
              "urn:nabu:ganjoor:hafez:33169", GOLESTAN].freeze

  def conformance_adapter = Nabu::Adapters::Ganjoor.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "ganjoor"

  def adapter = Nabu::Adapters::Ganjoor.new

  def document(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  # --- manifest + identity ------------------------------------------------------

  def test_manifest_records_the_operator_grant
    manifest = adapter.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Redistribution of ganjoor contents is permitted and ganjoor data is " \
                                      "free to reuse"
    assert_includes manifest.license, "by email, 2026-11-02"
    assert_match(/Ganjoor/, manifest.credit)
    assert_equal "ganjoor-sqlite", manifest.parser_family
  end

  def test_discover_yields_the_classical_poems_in_ganjoor_id_order
    assert_equal ACCEPTED, adapter.discover(FIXTURES).map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  def test_the_premodern_cut_is_the_constitutional_revolution
    rule = Nabu::Adapters::Ganjoor.method(:modern?)
    assert_equal 1324, Nabu::Adapters::Ganjoor::MODERN_FROM_AH
    refute rule.call({ "deathYearInLHijri" => 1323 }), "Ṣafā-ye Eṣfahāni's generation (d. 1322) is classical"
    assert rule.call({ "deathYearInLHijri" => 1324 })
    assert rule.call({ "deathYearInLHijri" => 1409 }), "Shahriār is the modern tail"
    assert rule.call({ "deathYearInLHijri" => nil }), "an undated poet never enters the cone by default"
  end

  # --- discovery census: the rejected grains ------------------------------------

  def test_rejected_poems_skip_by_rule_with_their_reasons
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(/unpublished.*نیما یوشیج \(501\): 1 poem/, notes)
    assert_match(/modern tail.*شهریار \(35\).*1409 AH: 1 poem/, notes)
    assert_match(/no text.*1 poem.*59493/, notes)
  end

  def test_a_missing_poets_snapshot_yields_nothing_and_a_malformed_one_is_loud
    Dir.mktmpdir do |work|
      FileUtils.cp(File.join(FIXTURES, "ganjoor.s3db"), work)
      assert_empty adapter.discover(work).to_a, "the poets snapshot is the publication rule's input"
      skips = adapter.discovery_skips(work)
      assert_equal 11, skips.unrecognized, "every poem is unaccounted without the snapshot"
      FileUtils.mkdir_p(File.join(work, "api"))
      File.write(File.join(work, "api", "poets.json"), "{\"not\": \"a list\"}")
      assert_raises(Nabu::ParseError) { adapter.discover(work).to_a }
    end
  end

  # --- passages ------------------------------------------------------------------

  def test_passage_censuses_and_citations
    counts = adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref).size] }
    assert_equal({ RUBAI => 2, GHAZAL1 => 7, "urn:nabu:ganjoor:hafez:2131" => 8, SHAMS => 15, ARABIC => 2,
                   RUDAKI => 2, "urn:nabu:ganjoor:hafez:33169" => 9, GOLESTAN => 2 }, counts)
    ghazal = document(GHAZAL1)
    first = ghazal.first
    assert_equal "#{GHAZAL1}:1", first.urn
    assert_equal "fas", ghazal.language
    assert first.text.unicode_normalized?(:nfc), "NFC at the adapter boundary (upstream's mark order is not)"
    hemistichs = first.annotations.fetch("hemistichs")
    assert_equal 2, hemistichs.size
    assert_equal hemistichs.join(" "), first.text, "hemistichs join by one space (the openiti verse precedent)"
    assert_equal({ "kind" => "verse", "form" => "couplet", "vorder" => 1 },
                 first.annotations.slice("kind", "form", "vorder"))
  end

  def test_band_couplets_and_prose_paragraphs
    shams = document(SHAMS)
    assert_equal(%w[couplet band], shams.first(2).map { |p| p.annotations["form"] })
    golestan = document(GOLESTAN)
    prose = golestan.first
    assert_equal "prose", prose.annotations["kind"]
    refute prose.annotations.key?("hemistichs")
    assert_equal "mixed", golestan.metadata["text_form"]
    assert_equal "verse", document(GHAZAL1).metadata["text_form"]
  end

  def test_editorial_comments_ride_the_document_never_the_text
    rudaki = document(RUDAKI)
    assert_equal 2, rudaki.size
    assert_equal 3, rudaki.metadata.fetch("comments").size
    assert_match(/سعید نفیسی/, rudaki.metadata["comments"].first)
    refute(rudaki.any? { |p| p.text.include?("سعید نفیسی") })
  end

  def test_an_arabic_section_is_tagged_arabic
    assert_equal "ara", document(ARABIC).language, "قصاید و قطعات عربی — the section label names the language"
    assert_equal "ara", document(ARABIC).first.language
  end

  # --- the mined axes: work path / form / poet era / place -------------------------

  def test_the_work_path_title_and_form_ride_the_document
    ghazal = document(GHAZAL1)
    assert_equal "حافظ » غزلیات » غزل شمارهٔ ۱", ghazal.title
    meta = ghazal.metadata
    assert_equal %w[غزلیات], meta["section_path"]
    assert_equal "غزلیات", meta["form"], "the poem's own section label — kind_map folds it"
    assert_equal "https://ganjoor.net/hafez/ghazal/sh1", meta["url"]
    assert_equal 2130, meta["poem_id"]
    assert_equal "حافظ", meta["poet"]
    assert_equal "حافظ شیرازی", meta["poet_full_name"]
    assert_equal "hafez", meta["poet_slug"]
    assert_equal ["گلستان", "باب اول در سیرت پادشاهان"], document(GOLESTAN).metadata["section_path"]
    assert_equal "گلستان", document(GOLESTAN).metadata["work"]
  end

  def test_the_poet_life_dates_the_document_as_composition
    date = document(GHAZAL1).metadata.fetch("date")
    assert_equal "composition", date["class"]
    assert_equal Nabu::Store::TimelineBuilder::OpenitiDates.ce_year(792), date["not_after"]
    assert_equal Nabu::Store::TimelineBuilder::OpenitiDates.ce_year(726), date["not_before"]
    assert_match(/\Apoet b\. 726 AH – d\. 792 AH/, date["raw"])
    assert_match(/\Apoet b\. c\. 615 AH – d\. c\. 694 AH/, document(GOLESTAN).metadata["date"]["raw"],
                 "upstream flags Saʿdi's years approximate (validBirthDate/validDeathDate false)")
    meta = document(GHAZAL1).metadata
    assert_equal 792, meta["poet_death_ah"]
    assert_equal 726, meta["poet_birth_ah"]
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ganjoor"]
  end

  def test_a_reversed_life_keeps_only_the_death_bound
    date = Nabu::Adapters::Ganjoor.life_date({ "birthYearInLHijri" => 1105, "validBirthDate" => false,
                                               "deathYearInLHijri" => 1077, "validDeathDate" => false })
    assert_nil date["not_before"], "Saʿidā's endpoint record (b. 1105, d. 1077) is inconsistent upstream"
    assert_equal Nabu::Store::TimelineBuilder::OpenitiDates.ce_year(1077), date["not_after"]
  end

  def test_the_death_place_is_the_place_claim
    meta = document(GHAZAL1).metadata
    place = meta.fetch("place")
    assert_equal 1, place.size
    assert_equal "شیراز", place.first["name"]
    assert place.first["latitude"].is_a?(Numeric)
    assert_equal "شیراز", meta["poet_birth_place"]
    rudaki = document(RUDAKI).metadata
    assert_nil rudaki["place"], "an empty death place mints no claim (and 0/0 is no coordinate)"
    assert_equal "بنج", rudaki["poet_birth_place"], "birth places stay biography, never the work's place"
  end

  # --- store: idempotent double-load ------------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "ganjoor", name: "Ganjoor", adapter_class: "Nabu::Adapters::Ganjoor",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 8, first.added
    assert_equal 0, first.errored
    assert_equal 47, catalog[:passages].count
    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 8, second.skipped, "a byte-identical reload skips every document"
    assert_equal 47, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- registry + fetch --------------------------------------------------------

  def test_registry_resolves_ganjoor_with_the_manifest
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ganjoor"]
    refute_nil entry, "ganjoor must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ganjoor, entry.adapter_class
    assert_equal Nabu::Adapters::Ganjoor.manifest, entry.manifest
    assert_equal "manual", entry.sync_policy
  end

  def test_fetch_downloads_the_pinned_release_and_the_poets_snapshot
    zip_body = fixture_zip
    poets = File.read(File.join(FIXTURES, "api", "poets.json"))
    stub_request(:get, Nabu::Adapters::Ganjoor::RELEASE_URL).to_return(status: 200, body: zip_body)
    stub_request(:get, Nabu::Adapters::Ganjoor::POETS_URL).to_return(status: 200, body: poets)
    Dir.mktmpdir do |workdir|
      ganjoor = Nabu::Adapters::Ganjoor.new(release_sha256: Digest::SHA256.hexdigest(zip_body))
      report = ganjoor.fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(zip_body), report.sha
      assert File.file?(File.join(workdir, "ganjoor.s3db"))
      assert File.file?(File.join(workdir, "api", "poets.json")), "the snapshot lands under api/"
      assert_equal ACCEPTED, ganjoor.discover(workdir).map(&:id)
    end
  end

  def test_fetch_refuses_a_release_that_misses_the_pin
    stub_request(:get, Nabu::Adapters::Ganjoor::RELEASE_URL).to_return(status: 200, body: fixture_zip)
    stub_request(:get, Nabu::Adapters::Ganjoor::POETS_URL).to_return(status: 200, body: "[]")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, Nabu::Adapters::Ganjoor::RELEASE_URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  private

  # A zip of the fixture database (the release zip's one-member layout).
  def fixture_zip
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "ganjoor.s3db"), dir)
      Nabu::Shell.run("zip", "-q", "-j", File.join(dir, "release.zip"), File.join(dir, "ganjoor.s3db"))
      File.binread(File.join(dir, "release.zip"))
    end
  end
end
