# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::Runesdb: the RuneS-DB TEI deposit (Zenodo 21788307,
# CC BY-SA 4.0) — one TEI file per runic find, passage = sequence, text =
# the glyphs' main transliterations verbatim — plus the per-find LIDO
# layer (runesdb.de/lido/<id>, P160): dating, find place + coordinates,
# object classification and the English translation (-en siblings).
# Fixtures: five real finds (one trimmed) + the rejected-grain specimen
# (an untransliterated find); three real LIDO records under lido/ (finds 1,
# 629, 200143 — 720 and 9982 stay unharvested, the TEI-only path). No
# network: fetch runs against WebMock stubs of the zip and LIDO URLs.
class RunesdbTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("runesdb")
  ZIP_URL = "https://zenodo.org/records/21788307/files/runes_tei.zip"
  LIDO_URL = "https://www.runesdb.de/lido/%s"

  HIMLINGOJE = "urn:nabu:runesdb:1"      # Sj 73 brooch — LIDO with a translation
  MANUSCRIPT = "urn:nabu:runesdb:200143" # AM 623 4to, 12r — one manuscript rune
  HACKNESS = "urn:nabu:runesdb:629"      # OE-GB-30, two sequences
  HOGEBEINTUM = "urn:nabu:runesdb:720"   # bind-rune read through its components
  RUNE_ROW = "urn:nabu:runesdb:9982"     # AM 748 I b 4to — repeated sequence ids
  DOC_URNS = [HIMLINGOJE, MANUSCRIPT, HACKNESS, HOGEBEINTUM, RUNE_ROW].sort.freeze
  HARVESTED = %w[1 629 200143].freeze

  # The conformance suite runs the opted-in adapter so the -en sibling's
  # urns join the uniqueness/stability checks.
  def conformance_adapter = Nabu::Adapters::Runesdb.new(translations: true)

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "runesdb"

  def adapter = Nabu::Adapters::Runesdb.new

  def parse(urn, with: adapter) = with.parse(with.discover(FIXTURES).find { |ref| ref.id == urn })

  # -- manifest -----------------------------------------------------------------

  def test_manifest_records_the_by_sa_deposit
    manifest = Nabu::Adapters::Runesdb.manifest
    assert_equal "runesdb", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/zenodo\.21788307/, manifest.license, "the citation names the DOI")
    assert_equal "runesdb-tei", manifest.parser_family
  end

  def test_the_lido_harvest_is_a_declared_materialization
    assert_equal ["lido"], Nabu::Adapters::Runesdb.materialized_paths
  end

  # -- discover + the rejected grain ---------------------------------------------

  def test_discover_yields_the_transliterated_finds_sorted_by_urn
    refs = adapter.discover(FIXTURES).to_a
    assert_equal DOC_URNS, refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "runesdb" })
  end

  def test_an_untransliterated_find_is_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal ["runes_find-166.tei.xml: untransliterated find (signs recorded geometrically only, " \
                  "no glyph transliteration)"], skips.notes
    refute_includes adapter.discover(FIXTURES).map(&:id), "urn:nabu:runesdb:166"
  end

  def test_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # -- text + identity ---------------------------------------------------------------

  def test_passage_text_is_the_transliteration_verbatim_with_runological_sigla
    document = parse(HACKNESS)
    assert_equal "gem", document.language
    assert_equal "Stein von Hackness (OE-GB-30)", document.title, "the constant Inschrift: label dropped"
    assert_equal([["#{HACKNESS}:A-1", "?rmcd"], ["#{HACKNESS}:A-2", "[...]œn[...]g"]],
                 document.map { |passage| [passage.urn, passage.text] })
  end

  def test_glyph_records_ride_the_annotations
    passage = parse(HACKNESS).first
    first, second = passage.annotations["glyphs"]
    assert_equal({ "id" => "g-3773", "translit" => "?", "separator" => true }, first)
    assert_equal "r", second["translit"]
    assert_equal "raidō, rād, rāt, ræið/ reið", second["rune_name"]
    assert second["uncertain"], "upstream's graphTypeUncertain flag"
    assert_equal "A", passage.annotations["side"]
    assert_equal "cut", passage.annotations["technique"]
    assert_match %r{\Ahttps://www\.runesdb\.de/image-service/}, passage.annotations["facs"]
  end

  def test_a_bind_rune_without_its_own_transliteration_reads_through_its_components
    passage = parse(HOGEBEINTUM).first
    assert_equal "d^*^d", passage.text, "upstream's own bind-rune notation (a^r)"
    glyph = passage.annotations["glyphs"].first
    assert_equal %w[d * d], glyph["ligature"]
    assert glyph["composed"]
    assert_equal 1, passage.annotations["glyphs"].size, "ligature components never become reading glyphs"
  end

  def test_repeated_upstream_sequence_ids_take_the_positional_disambiguator
    document = parse(RUNE_ROW)
    assert_equal ["#{RUNE_ROW}:recto-1", "#{RUNE_ROW}:verso-1", "#{RUNE_ROW}:recto-1:b2"],
                 document.map(&:urn)
    assert_equal %w[u f o], document.map(&:text), "the rune row in document order"
  end

  def test_the_lido_layer_never_moves_a_find_or_passage_urn
    Dir.mktmpdir do |dir|
      Dir.glob(File.join(FIXTURES, "*.xml")).each { |path| FileUtils.cp(path, dir) }
      bare = adapter.discover(dir).map { |ref| [ref.id, adapter.parse(ref).map(&:urn)] }
      layered = adapter.discover(FIXTURES).map { |ref| [ref.id, adapter.parse(ref).map(&:urn)] }
      assert_equal bare, layered, "URNs are f(TEI) alone — the harvest adds metadata, never identity"
    end
  end

  # -- metadata + facets ---------------------------------------------------------------

  def test_find_metadata_carries_the_siglum_family_facet_and_the_lido_pointer
    metadata = parse(HOGEBEINTUM).metadata
    assert_equal "720", metadata["find_id"]
    assert_equal({ "siglum_family" => { "value" => "PreOFris/EROFris-NL" } }, metadata["facets"])
    assert_equal "https://www.runesdb.de/lido/720", metadata["lido_url"]
    hackness = parse(HACKNESS).metadata
    assert_equal "OE-GB-30", hackness["siglum"]
    assert_equal "OE-GB", hackness["siglum_family"]
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", hackness["license_url"]
    assert_equal "AM", parse(MANUSCRIPT).metadata["siglum_family"]
  end

  def test_an_unharvested_find_parses_exactly_as_the_tei_alone
    metadata = parse(HOGEBEINTUM).metadata
    assert_equal %w[facets find_id license license_url lido_url sides siglum siglum_family summary],
                 metadata.keys.sort, "no LIDO record on disk — no axis claim invented"
  end

  def test_the_siglum_family_strips_the_running_number
    family = ->(siglum) { Nabu::Adapters::Runesdb.siglum_family(siglum) }
    assert_equal "OE-GB", family.call("OE-GB-30")
    assert_equal "N KJ", family.call("N KJ38")
    assert_equal "MJy", family.call("MJy 74")
    assert_equal "Holm B", family.call("Holm B 59 4to, 25v")
    assert_equal "PreOFris/EROFris-NL", family.call("PreOFris/EROFris-NL-19")
    assert_nil family.call("123")
    assert_nil family.call(nil)
  end

  def test_the_per_file_licence_gate
    assert_nil Nabu::Adapters::Runesdb.license_override_for("CC BY-SA 4.0 - Attribution-ShareAlike 4.0 International")
    assert_equal "restricted", Nabu::Adapters::Runesdb.license_override_for("All rights reserved")
    assert_equal "restricted", Nabu::Adapters::Runesdb.license_override_for(nil)
    assert(adapter.discover(FIXTURES).all? { |ref| adapter.parse(ref).license_override.nil? })
  end

  def test_a_find_without_any_transliteration_quarantines_if_reached
    ref = Nabu::DocumentRef.new(source_id: "runesdb", id: "urn:nabu:runesdb:166",
                                path: File.join(FIXTURES, "runes_find-166.tei.xml"), metadata: {})
    assert_raises(Nabu::ParseError) { adapter.parse(ref) }
  end

  # -- the LIDO layer -----------------------------------------------------------------

  def test_the_production_event_dates_the_find_and_the_finding_event_places_it
    metadata = parse(HACKNESS).metadata
    assert_equal({ "not_before" => 700, "not_after" => 900, "raw" => "700–900" }, metadata["date"])
    assert_equal({ "ancient" => "Hackness", "geo" => "54.321533, -0.538513" }, metadata["place"],
                 "the GML point is lat lon — re-spelled in the house \"lat, lon\" form")
    assert_equal "1848>F", metadata["find_date"], "the discovery date rides verbatim, never as dating"
    assert_equal({ "geo" => "54.3018, -0.5111" }, metadata["repository"], "\"None\" names no holder")
    assert_equal ["OE-GB-30"], metadata["sigla"]
  end

  def test_the_lido_object_fields_ride_metadata_and_facets
    metadata = parse(HACKNESS).metadata
    assert_equal "stone", metadata["object_type"]
    assert_equal "settlement", metadata["classification"]
    assert_equal ["limestone"], metadata["material"]
    assert_equal ["cut"], metadata["technique"]
    assert_equal "?[.]mc(d)[.](œ)|[.](g/œ)(n)[...](œ)", metadata["transcription"]
    assert_equal({ "type" => "height", "value" => "146,5", "unit" => "centimetre" }, metadata["measurements"].first)
    assert_equal({ "siglum_family" => { "value" => "OE-GB" }, "object_type" => { "value" => "stone" },
                   "classification" => { "value" => "settlement" }, "material" => { "value" => "limestone" } },
                 metadata["facets"])
    assert_equal "CC BY-SA 4.0 - Attribution-ShareAlike 4.0 International", metadata["lido_license"]
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", metadata["lido_license_url"]
    refute metadata.key?("translation_en"), "upstream's \"-\" is no translation"
  end

  def test_the_translations_and_the_concordance_sigla_ride_verbatim
    metadata = parse(HIMLINGOJE).metadata
    assert_equal "Harisō.", metadata["translation_en"]
    assert_equal "Harisō.", metadata["translation_de"]
    assert_equal ["Sj 73", "DR232", "KJ9", "DR 232"], metadata["sigla"], "the rundata crosswalk keys"
    assert_equal({ "not_before" => 210, "not_after" => 310, "raw" => "210–310" }, metadata["date"])
    assert_equal "Himlingøje", metadata.dig("place", "ancient")
    assert_equal "1835", metadata["find_date"]
    assert_equal({ "name" => "Nationalmuseet", "geo" => "55.67469249083635, 12.574840614304549" },
                 metadata["repository"])
    assert_match(/\AExternal dating: probably C1b/, metadata["description"].first)
  end

  def test_a_manuscripts_finding_event_names_its_holding_library_never_a_findspot
    metadata = parse(MANUSCRIPT).metadata
    assert_equal "manuscript", metadata["object_type"]
    assert_equal({ "not_before" => 1325, "not_after" => 1325, "raw" => "1325" }, metadata["date"])
    refute metadata.key?("place"), "the holding library is a present location"
    assert_equal "Nordisk Forskningsinstitut, Københavns Universitet",
                 metadata.dig("repository", "find_event_place", "ancient")
    refute metadata.key?("find_date"), "the finding event carries no date"
  end

  # -- translations (registry `translations: true`) ---------------------------------------

  def test_a_real_english_translation_mints_the_en_sibling_when_opted_in
    opted = Nabu::Adapters::Runesdb.new(translations: true)
    assert_equal (DOC_URNS + ["#{HIMLINGOJE}-en"]).sort, opted.discover(FIXTURES).map(&:id),
                 "629's \"-\" and 200143's restated rune \"m\" mint nothing; 720/9982 are unharvested"
    sibling = parse("#{HIMLINGOJE}-en", with: opted)
    assert_equal "eng", sibling.language
    assert_equal "Bügelfibel von Himlingøje (Sj 73) — English translation", sibling.title
    assert_equal([["#{HIMLINGOJE}-en:1", "Harisō."]], sibling.map { |passage| [passage.urn, passage.text] })
    assert_equal({ "kind" => "translation", "translation_of" => HIMLINGOJE,
                   "license" => "CC BY-SA 4.0 - Attribution-ShareAlike 4.0 International" }, sibling.metadata)
  end

  def test_a_restatement_of_the_reading_is_no_translation
    ref = adapter.discover(FIXTURES).find { |r| r.id == MANUSCRIPT }
    assert_equal "m", parse(MANUSCRIPT).metadata["translation_en"], "kept verbatim in metadata"
    assert_nil adapter.translation_for(ref), "the TEI reading is \"m\" — a restatement"
  end

  def test_a_broken_lido_record_quarantines_its_find_without_breaking_discover
    Dir.mktmpdir do |dir|
      FileUtils.cp(File.join(FIXTURES, "runes_find-1.tei.xml"), dir)
      FileUtils.mkdir_p(File.join(dir, "lido"))
      File.write(File.join(dir, "lido", "1.xml"), File.read(File.join(FIXTURES, "lido", "1.xml"))[0, 3000])
      opted = Nabu::Adapters::Runesdb.new(translations: true)
      refs = opted.discover(dir).to_a
      assert_equal [HIMLINGOJE], refs.map(&:id), "no sibling from an unreadable record"
      assert_raises(Nabu::ParseError) { opted.parse(refs.first) }
    end
  end

  def test_translations_stay_off_by_default
    refute(adapter.discover(FIXTURES).any? { |ref| ref.id.end_with?("-en") })
  end

  # -- store + timeline ------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    opted = Nabu::Adapters::Runesdb.new(translations: true)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(opted, workdir: FIXTURES)
    assert_equal 6, first.added, "five finds + the Himlingøje -en sibling"
    assert_equal 0, first.errored
    assert_equal 9, db[:passages].count, "1 + 1 + 2 + 1 + 3 + the sibling's 1"
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(opted, workdir: FIXTURES)
    assert_equal 6, second.skipped
    assert_equal 9, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
    assert_equal [1], db[:documents].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  def test_the_lido_dates_and_places_project_through_the_metadata_date_lane
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["runesdb"]
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source)
                       .load_from(Nabu::Adapters::Runesdb.new(translations: true), workdir: FIXTURES)
    assert_equal 3, Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: db, slug: "runesdb"),
                 "the three harvested finds; the sibling and the unharvested finds mint no row"
    rows = db[:document_axes].join(:documents, id: :document_id)
                             .select_hash(:urn, %i[not_before not_after place_name place_lat place_lon date_class])
    assert_equal [700, 900, "Hackness", 54.321533, -0.538513, nil], rows.fetch(HACKNESS)
    assert_equal [210, 310, "Himlingøje", 55.3735957300715, 12.2153125207149, nil], rows.fetch(HIMLINGOJE)
    assert_equal [1325, 1325, nil, nil, nil, nil], rows.fetch(MANUSCRIPT), "dated, never placed at its library"
  ensure
    db&.disconnect
  end

  # -- fetch ---------------------------------------------------------------------------

  def test_fetch_downloads_the_zip_then_harvests_one_lido_record_per_text_bearing_find
    stub_zip
    stub_lido
    Dir.mktmpdir do |workdir|
      report = fetch_adapter.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal DOC_URNS, adapter.discover(workdir).map(&:id)
      HARVESTED.each do |id|
        assert_equal File.binread(File.join(FIXTURES, "lido", "#{id}.xml")),
                     File.binread(File.join(workdir, "lido", "#{id}.xml")), "upstream's bytes verbatim"
      end
      refute_path_exists File.join(workdir, "lido", "720.xml"), "a redirect is no record"
      refute_path_exists File.join(workdir, "lido", "166.xml"), "the skipped find is never requested"
      assert_not_requested :get, format(LIDO_URL, 166)
      state = JSON.parse(File.read(File.join(workdir, "lido", ".lido-fetch.json")))
      assert_equal 5, state["records"]
      assert_equal 3, state["held"]
      assert_equal %w[720 9982], state["missing"]
      assert_match(/lido=\h{12} \(5 finds: 3 fetched, 0 on disk, 2 without a record\)/, report.notes)
      assert_equal parse(HACKNESS).metadata, parse_in(workdir, HACKNESS).metadata
    end
  end

  def test_a_resync_resumes_never_refetches_and_never_attics_the_harvest
    stub_zip
    stub_lido
    Dir.mktmpdir do |workdir|
      fetch_adapter.fetch(workdir)
      before = tree_bytes(workdir)
      report = fetch_adapter.fetch(workdir)
      HARVESTED.each { |id| assert_requested :get, format(LIDO_URL, id), times: 1 }
      assert_requested :get, format(LIDO_URL, 720), times: 2 # a missing record is retried on resume
      refute_path_exists File.join(workdir, ".attic", "lido"), "the zip's attic never takes the harvest"
      assert_equal before.except(".zip-fetch.json"), tree_bytes(workdir).except(".zip-fetch.json"),
                   "the deterministic ledger leaves the harvest byte-identical"
      assert_match(/0 fetched, 3 on disk/, report.notes)
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { fetch_adapter.fetch(workdir) }
    end
  end

  def test_a_persistent_lido_outage_is_a_fetch_error
    stub_zip
    stub_request(:get, %r{\Ahttps://www\.runesdb\.de/lido/\d+\z}).to_return(status: 503)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { fetch_adapter.fetch(workdir) }
      assert_match(/HTTP 503 .* \(after 3 attempts\)/, error.message)
    end
  end

  private

  def fetch_adapter = Nabu::Adapters::Runesdb.new(lido_delay: 0)

  def parse_in(workdir, urn)
    ref = adapter.discover(workdir).find { |r| r.id == urn }
    adapter.parse(ref)
  end

  def tree_bytes(dir)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: dir).select { |rel| File.file?(File.join(dir, rel)) }
                                                   .to_h do |rel|
      [
        rel, File.binread(File.join(dir, rel))
      ]
    end
  end

  def create_source(_db)
    Nabu::Store::Source.create(slug: "runesdb", name: "RuneS-DB", adapter_class: "Nabu::Adapters::Runesdb",
                               license_class: "attribution")
  end

  def stub_lido
    HARVESTED.each do |id|
      stub_request(:get, format(LIDO_URL, id))
        .to_return(status: 200, body: File.binread(File.join(FIXTURES, "lido", "#{id}.xml")),
                   headers: { "Content-Type" => "application/xml" })
    end
    %w[720 9982].each do |id|
      stub_request(:get, format(LIDO_URL, id)).to_return(status: 302, headers: { "Location" => "/" })
    end
  end

  def stub_zip
    Dir.mktmpdir do |dir|
      zip_path = File.join(dir, "runes_tei.zip")
      files = Dir.glob(File.join(FIXTURES, "*.xml")).map { |path| File.basename(path) }
      Nabu::Shell.run("zip", "-q", zip_path, *files, chdir: FIXTURES)
      stub_request(:get, ZIP_URL).to_return(
        status: 200, body: File.binread(zip_path),
        headers: { "Content-Type" => "application/octet-stream", "Last-Modified" => "Sat, 01 Aug 2026 00:00:00 GMT" }
      )
    end
  end
end
