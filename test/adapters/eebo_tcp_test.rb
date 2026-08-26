# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::EeboTcp (P83-1): EEBO-TCP — Early English Books Online,
# Text Creation Partnership. 60,326 early-modern English texts in the P4
# <ETS> schema, riding the tcp-xml family CME proved (P82-2). Fetched from
# the TCP's own Box folder (28 P4 zips across two phases, uniformly CC0 —
# channel verified 2026-08-26); wave scope is the `classes:` phase list
# (№R-43 ruled 2026-08-26: wave 1 = Phase I whole, both phases the
# stated follow-on).
#
# Fixtures: four REAL corpus files (test/fixtures/eebo-tcp/texts/,
# retrieved 2026-08-26) spanning phases and formats — a Phase-1 broadside
# petition (A90004, 1642), a Phase-1 quarto with Raleigh's farewell poem
# (A57617, "EVen such is time"), a Phase-2 verse ode carrying the corpus's
# one censused <FW> instance (A29180), and a Phase-2 folio trimmed to its
# first book (A20018, Grobianus 1605). See the fixture README.
#
# THE LICENSE: open — every file's AVAILABILITY carries the TCP's CC0 1.0
# Public Domain Dedication (censused ×3,325, two statement variants, both
# explicit); the license_mapper maps the dedication → open per document
# and a STRANGER availability → restricted, never silently open.
class EeboTcpTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  GROBIANUS = "urn:nabu:eebo-tcp:A20018"
  ODE = "urn:nabu:eebo-tcp:A29180"
  RALEIGH = "urn:nabu:eebo-tcp:A57617"
  PETITION = "urn:nabu:eebo-tcp:A90004"

  SHARED = "https://app.box.com/s/jjzmnrx98dkvanipopz3nxkvymnjccht"

  # The fixture listing pages' own Box ids (trimmed real postStreamData —
  # see the fixture README).
  FOLDER_IDS = {
    phase1: 142_421_025_353, phase1_p4: 142_422_134_304,
    phase2: 142_422_118_399, phase2_p4: 142_422_035_597
  }.freeze
  FILE_BODIES = {
    "841160372075" => "fetch/A9.zip",                      # phase1 A9.zip
    "841160364875" => "fetch/A5.zip",                      # phase1 A5.zip
    "841165246490" => "fetch/ph2_A2.zip",                  # phase2 A2.zip
    "1333777767630" => "fetch/eebo2prf.xml.dtd",           # root DTD
    "841168372645" => "fetch/IDnos_in_phase1.txt",
    "841168371445" => "fetch/eebo_phase1_IDs_and_dates.txt",
    "841168065045" => "fetch/IDnos_in_phase2.txt",
    "841168068645" => "fetch/EEBO_Phase2_IDs_and_dates.txt"
  }.freeze

  def conformance_adapter = Nabu::Adapters::EeboTcp.new(classes: %w[phase1 phase2])

  def conformance_workdir = Nabu::TestSupport.fixtures("eebo-tcp")

  def conformance_expected_source_id = "eebo-tcp"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_sorted_by_urn_with_phase
    refs = adapter.discover(workdir).to_a
    assert_equal [GROBIANUS, ODE, RALEIGH, PETITION], refs.map(&:id),
                 "urn = the TCP id (filename stem — IDG agrees, censused ×3,325), sorted"
    assert_equal %w[phase2 phase2 phase1 phase1], refs.map { |ref| ref.metadata["phase"] },
                 "the texts/<phase>/ prefix is the phase claim"
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_the_default_wave_scope_is_phase_one_per_r43
    refs = Nabu::Adapters::EeboTcp.new.discover(workdir).to_a
    assert_equal [RALEIGH, PETITION], refs.map(&:id),
                 "№R-43 (ruled 2026-08-26): wave 1 = Phase I whole; the both-phases " \
                 "follow-on is a sources.yml classes: edit"
  end

  def test_unknown_phase_classes_are_a_configuration_error
    error = assert_raises(Nabu::ValidationError) { Nabu::Adapters::EeboTcp.new(classes: %w[phase3]) }
    assert_match(%r{phase1/phase2}, error.message)
    assert_raises(Nabu::ValidationError) { Nabu::Adapters::EeboTcp.new(classes: []) }
  end

  def test_discover_never_yields_the_ledger_sidecars_or_zip_state_files
    Dir.mktmpdir do |dir|
      unit = File.join(dir, "texts", "phase1", "A9")
      FileUtils.mkdir_p(unit)
      FileUtils.cp(File.join(workdir, "texts", "phase1", "A9", "A90004.P4.xml"), unit)
      File.write(File.join(dir, Nabu::EeboTcpFetch::STATE_FILE), "{}")
      File.write(File.join(dir, "eebo_phase1_IDs_and_dates.txt"), "A90004\t1642\n")
      File.write(File.join(unit, Nabu::ZipFetch::STATE_FILE), "{}")
      assert_equal [PETITION], adapter.discover(dir).map(&:id)
    end
  end

  # -- parse: identity, language, grain ---------------------------------------

  def test_the_idg_id_equals_the_filename_stem_the_verified_crosscheck
    adapter.discover(workdir).each do |ref|
      assert_equal ref.id.delete_prefix("urn:nabu:eebo-tcp:"), adapter.parse(ref).metadata["idg_id"],
                   "#{ref.id}: filename↔IDG agreement (0 mismatches on the 3,325-file census " \
                   "2026-08-26 — unlike CME's shared placeholder IDG)"
    end
  end

  def test_english_documents_claim_en_from_their_own_langusage
    document = adapter.parse(ref_for(PETITION))
    assert_equal "en", document.language,
                 "LANGUSAGE eng → en (the nabu-lects codemap alias); 97.6% of the corpus"
    assert(document.all? { |passage| passage.language == "en" })
  end

  def test_a_foreign_language_document_claims_its_own_upstream_code
    # A Latin book printed in England must not claim `en`. Runtime-derived
    # from the real A90004 bytes (LANGUSAGE swapped to lat — the 1.4%
    # minority shape; never a checked-in fake fixture).
    with_edited_petition(/ID="eng"><LANGUAGE>eng/, 'ID="lat"><LANGUAGE>lat') do |ref|
      assert_equal "lat", Nabu::Adapters::EeboTcp.new.parse(ref).language
    end
  end

  def test_the_broadside_parses_at_head_and_block_grain
    document = adapter.parse(ref_for(PETITION))
    assert_equal 9, document.count, "2 heads + opener + 3 P + closer + trailer + back license"
    assert_equal "#{PETITION}:d1.h1", document.first.urn
    assert_equal "A NEW PETITION To the Kings most Excellent Majestie.", document.first.text
  end

  def test_raleighs_farewell_poem_reads_verbatim
    passage = adapter.parse(ref_for(RALEIGH)).to_a[21]
    assert_equal "#{RALEIGH}:d2.p18", passage.urn
    assert passage.text.start_with?("EVen such is time, which takes in trust Our youth, our age,"),
           "the canonical farewell poem, NFC verbatim (got: #{passage.text[0, 60].inspect})"
    assert passage.text.end_with?("The Lord shall raise me up, I trust.")
  end

  def test_fixture_passage_counts_pin_the_grain
    assert_equal 41, adapter.parse(ref_for(RALEIGH)).count
    assert_equal 200, adapter.parse(ref_for(ODE)).count
    assert_equal 1508, adapter.parse(ref_for(GROBIANUS)).count, "the trimmed folio's first book"
  end

  def test_the_real_fw_forme_work_never_reaches_reading_text
    # A29180 carries the corpus's ONE censused <FW> (wrapping a FIGURE
    # whose FIGDESC reads "decorative border resembling a picture frame",
    # ×20) — the real-bytes pin for the P83-1 family drop; the leak
    # differentiator (FW with PCDATA) lives in the family suite.
    document = adapter.parse(ref_for(ODE))
    assert(document.none? { |passage| passage.text.include?("picture frame") })
  end

  # -- parse: dating (the imprint molds) --------------------------------------

  def test_dating_registers_in_the_metadata_dates_lane
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["eebo-tcp"],
                 "the imprint envelope projects through the P47-r3/P81 catalog lane"
  end

  def test_clean_imprint_years_mint_the_envelope
    assert_equal({ "not_before" => 1642, "not_after" => 1642, "raw" => "1642." },
                 adapter.parse(ref_for(PETITION)).metadata["date"])
    assert_equal({ "not_before" => 1605, "not_after" => 1605, "raw" => "1605." },
                 adapter.parse(ref_for(GROBIANUS)).metadata["date"])
  end

  def test_an_uncertain_imprint_stays_raw_only
    assert_equal({ "raw" => "[1694?]" }, adapter.parse(ref_for(ODE)).metadata["date"],
                 "?-marked years mint no bounds — never invented")
  end

  def test_the_imprint_molds_cover_the_censused_shapes
    envelope = Nabu::Adapters::EeboTcp.method(:imprint_envelope)
    # the censused clean shapes (3,325-file sample, 2026-08-26 — 85.7% dated)
    assert_equal({ "not_before" => 1642, "not_after" => 1642, "raw" => "1642." }, envelope.call("1642."))
    assert_equal({ "not_before" => 1697, "not_after" => 1697, "raw" => "[1697]" }, envelope.call("[1697]"))
    assert_equal({ "not_before" => 1697, "not_after" => 1697, "raw" => "1697]" }, envelope.call("1697]"),
                 "an unbalanced cataloguer bracket still reads")
    assert_equal 1588, envelope.call("13. Febr. Anno 1587 [i.e. 1588]")["not_before"],
                 "the cataloguer's correction outranks the misprint"
    assert_equal 1635, envelope.call("1634 [i.e., 1635]")["not_before"]
    assert_equal({ "not_before" => 1680, "not_after" => 1681, "raw" => "1680-1681." },
                 envelope.call("1680-1681."))
    assert_equal({ "not_before" => 1681, "not_after" => 1682, "raw" => "1681/2." },
                 envelope.call("1681/2."), "the OS/NS split year is an honest two-year envelope")
    assert_equal({ "not_before" => 1617, "not_after" => 1617, "raw" => "Anno Dom. 1617." },
                 envelope.call("Anno Dom. 1617."))
    assert_equal({ "not_before" => 1625, "not_after" => 1625, "raw" => "M.DC.XXV [1625]" },
                 envelope.call("M.DC.XXV [1625]"), "the bracketed Arabic year beside roman numerals")
    # uncertainty: raw-only, bounds never invented
    assert_equal({ "raw" => "[ca. 1570]" }, envelope.call("[ca. 1570]"))
    assert_equal({ "raw" => "1695?]" }, envelope.call("1695?]"))
    assert_nil envelope.call(nil), "no BIBLFULL date — no key at all"
  end

  # -- parse: license ---------------------------------------------------------

  def test_the_cc0_dedication_maps_every_fixture_open
    adapter.discover(workdir).each do |ref|
      document = adapter.parse(ref)
      assert_equal "open", document.license_override,
                   "#{ref.id}: the per-file CC0 dedication is the claim"
      assert_includes document.metadata["availability"], "CC0 1.0 Public Domain Dedication"
    end
  end

  def test_a_stranger_availability_maps_restricted_never_silently_open
    with_edited_petition(/the terms of the CC0 1\.0 Public Domain Dedication[^<]*/,
                         "all rights reserved") do |ref|
      assert_equal "restricted", Nabu::Adapters::EeboTcp.new.parse(ref).license_override
    end
  end

  # -- manifest + probe -------------------------------------------------------

  def test_manifest_records_the_cc0_terms_verbatim
    manifest = adapter.manifest
    assert_equal "eebo-tcp", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "tcp-xml", manifest.parser_family
    assert_includes manifest.license, "CC0 1.0 Public Domain Dedication"
    assert_includes manifest.license, "№77-2"
    assert_includes manifest.credit, "Text Creation Partnership"
    assert_equal SHARED, manifest.upstream_url
  end

  def test_remote_probe_is_a_liveness_only_head_of_the_box_folder
    assert_equal :http_zip, Nabu::Adapters::EeboTcp.remote_probe_strategy
    targets = Nabu::Adapters::EeboTcp.http_probe_targets
    assert_equal 1, targets.size
    assert targets.first.liveness_only
    assert_equal SHARED, targets.first.zip_url
    assert_equal Nabu::EeboTcpFetch::STATE_FILE, targets.first.state_file
  end

  # -- fetch wiring -----------------------------------------------------------

  def test_fetch_walks_the_box_folder_unpacks_zips_and_lands_sidecars
    stub_box!
    Dir.mktmpdir do |dir|
      report = fetch_adapter(%w[phase1 phase2]).fetch(dir)
      assert_kind_of Nabu::FetchReport, report
      assert_match(/3 zips listed, 3 fetched, 0 unchanged; 4 texts/, report.notes)
      assert File.file?(File.join(dir, "texts", "phase1", "A9", "A90004.P4.xml"))
      assert File.file?(File.join(dir, "texts", "phase1", "A5", "A57617.P4.xml"))
      assert File.file?(File.join(dir, "texts", "phase2", "A2", "A29180.P4.xml"))
      assert File.file?(File.join(dir, "texts", "phase2", "A2", "A20018.P4.xml"))
      %w[eebo2prf.xml.dtd IDnos_in_phase1.txt eebo_phase1_IDs_and_dates.txt
         IDnos_in_phase2.txt EEBO_Phase2_IDs_and_dates.txt].each do |sidecar|
        assert File.file?(File.join(dir, sidecar)), "sidecar #{sidecar} lands beside texts/"
      end
      state = JSON.parse(File.read(File.join(dir, Nabu::EeboTcpFetch::STATE_FILE)))
      assert_equal({ "phase1" => { "zips" => 2, "texts" => 2 },
                     "phase2" => { "zips" => 1, "texts" => 2 } }, state["census"])
      assert_equal report.sha, state["sha256"]
    end
  end

  def test_a_resync_skips_unchanged_zips_with_zero_zip_requests
    stub_box!
    Dir.mktmpdir do |dir|
      fetch_adapter(%w[phase1 phase2]).fetch(dir)
      report = fetch_adapter(%w[phase1 phase2]).fetch(dir)
      assert_match(/0 fetched, 3 unchanged/, report.notes)
      FILE_BODIES.each_key do |file_id|
        next unless FILE_BODIES[file_id].end_with?(".zip")

        assert_requested :get, download_url(file_id), times: 1 # the FIRST sync only
      end
    end
  end

  def test_the_phase_scope_never_touches_the_other_phases_listings
    stub_box!
    Dir.mktmpdir do |dir|
      fetch_adapter(%w[phase1]).fetch(dir)
      assert_not_requested :get, "#{SHARED}/folder/#{FOLDER_IDS[:phase2]}"
      assert_not_requested :get, download_url("841165246490")
      refute Dir.exist?(File.join(dir, "texts", "phase2"))
    end
  end

  def test_a_zip_vanishing_from_the_listing_trips_the_breaker_then_attics_under_force
    stub_box!
    Dir.mktmpdir do |dir|
      fetch_adapter(%w[phase1]).fetch(dir)
      # upstream drops A5.zip: 1 of 2 discovered texts would vanish (50% > 20%)
      stub_request(:get, "#{SHARED}/folder/#{FOLDER_IDS[:phase1_p4]}")
        .to_return(status: 200, body: listing_without(fixture("fetch", "phase1_p4.html"), "A5.zip"))
      assert_raises(Nabu::SyncAborted) { fetch_adapter(%w[phase1]).fetch(dir) }
      assert File.file?(File.join(dir, "texts", "phase1", "A5", "A57617.P4.xml")),
             "the breaker aborts with the tree byte-unchanged"

      fetch_adapter(%w[phase1]).fetch(dir, force: true)
      refute File.exist?(File.join(dir, "texts", "phase1", "A5", "A57617.P4.xml"))
      attic_copy = File.join(dir, ".attic", "texts", "phase1", "A5", "A57617.P4.xml")
      assert File.file?(attic_copy), "the vanished unit is retained under the attic"
      assert_equal [RALEIGH, PETITION],
                   fetch_adapter(%w[phase1]).discover_with_attic(dir).map(&:id).sort,
                   "attic rediscovery keeps the retired text in the collection"
    end
  end

  def test_an_outage_page_aborts_before_any_write
    stub_request(:get, SHARED).to_return(status: 200, body: "<html>maintenance</html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { fetch_adapter(%w[phase1]).fetch(dir) }
      assert_match(/postStreamData/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 1758, db[:passages].count, "9 + 41 + 200 + 1508 across the four fixture texts"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 1758, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def fixture(*parts)
    File.join(workdir, *parts)
  end

  # A runtime-edited copy of the real A90004 bytes under the fixture tree
  # shape — for the minority/stranger shapes no checked-in fixture should
  # fake.
  def with_edited_petition(pattern, replacement)
    Dir.mktmpdir do |dir|
      unit = File.join(dir, "texts", "phase1", "A9")
      FileUtils.mkdir_p(unit)
      body = File.read(fixture("texts", "phase1", "A9", "A90004.P4.xml"))
      edited = body.gsub(pattern, replacement)
      refute_equal body, edited, "the edit must actually hit"
      File.write(File.join(unit, "A90004.P4.xml"), edited)
      yield Nabu::Adapters::EeboTcp.new.discover(dir).first
    end
  end

  def fetch_adapter(phases)
    Nabu::Adapters::EeboTcp.new(classes: phases, delay: 0)
  end

  def download_url(file_id)
    "https://app.box.com/index.php?rm=box_v2_download_shared_file&" \
      "shared_name=jjzmnrx98dkvanipopz3nxkvymnjccht&file_id=f_#{file_id}"
  end

  # The fixture listing page with one named item removed — the JSON is
  # edited as JSON (nested braces defeat any textual excision).
  def listing_without(page_path, name)
    body = File.read(page_path)
    match = body.match(%r{Box\.postStreamData\s*=\s*(\{.*?\});?\s*</script>}m) || flunk("no listing blob")
    data = JSON.parse(match[1])
    folder = data.fetch("/app-api/enduserapp/shared-folder")
    folder["items"] = folder["items"].reject { |item| item["name"] == name }
    body.sub(match[1], JSON.generate(data))
  end

  def stub_box!
    stub_request(:get, SHARED)
      .to_return(status: 200, body: File.read(fixture("fetch", "root.html")))
    { phase1: "phase1.html", phase1_p4: "phase1_p4.html",
      phase2: "phase2.html", phase2_p4: "phase2_p4.html" }.each do |key, page|
      stub_request(:get, "#{SHARED}/folder/#{FOLDER_IDS[key]}")
        .to_return(status: 200, body: File.read(fixture("fetch", page)))
    end
    FILE_BODIES.each do |file_id, relpath|
      stub_request(:get, download_url(file_id))
        .to_return(status: 200, body: File.binread(fixture(*relpath.split("/"))))
    end
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "eebo-tcp", name: "EEBO-TCP", adapter_class: "Nabu::Adapters::EeboTcp",
      license_class: "open"
    )
  end
end
