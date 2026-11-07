# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::EvansTcp: Evans-TCP — the Text Creation Partnership's
# keyed Early American Imprints (Evans, 1639–1800), on the eebo-tcp shape
# (the TcpCollection base over the tcp-xml family; TcpBoxFetch over the
# TCP's own Evans Box folder, both P4 classes).
#
# Fixtures (test/fixtures/evans-tcp/, retrieved 2026-11-03 — see its
# README): three REAL P4 texts — Jupiter Hammon's broadside "An evening
# thought" (N31062, released, "1760?]"), the Frederick treason sentence
# (N33557, released, a conjectural imprint), John Phillips's acrostic
# "Paraphrastical exposition" (N00552, unedited, "in the year 1693.") —
# plus the P5 and SGML copies of N31062, the rejected grains, pinned
# beside its P4 file.
class EvansTcpTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  PHILLIPS = "urn:nabu:evans-tcp:N00552"
  HAMMON = "urn:nabu:evans-tcp:N31062"
  TREASON = "urn:nabu:evans-tcp:N33557"

  SHARED = "https://app.box.com/s/zj7pzfokxde4glrhebxsavbbxzyr3ogz"
  P4_FOLDER_ID = 230_593_108_391
  FILE_BODIES = {
    "1333765453347" => "fetch/N3.zip",
    "1333730319881" => "fetch/unedited.zip",
    "1333783953046" => "fetch/eebo2prf.xml.dtd",
    "1333753679284" => "fetch/evans_pub_dates.txt"
  }.freeze

  def conformance_adapter = Nabu::Adapters::EvansTcp.new

  def conformance_workdir = Nabu::TestSupport.fixtures("evans-tcp")

  def conformance_expected_source_id = "evans-tcp"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_p4_text_sorted_with_its_class
    refs = adapter.discover(workdir).to_a
    assert_equal [PHILLIPS, HAMMON, TREASON], refs.map(&:id), "urn = the TCP id (filename stem), sorted"
    assert_equal(%w[unedited released released], refs.map { |ref| ref.metadata["tcp_class"] })
  end

  def test_the_p5_and_sgml_copies_skip_by_rule_and_are_counted
    skips = adapter.discovery_skips(workdir)
    assert_equal 2, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal ["Oxford P5 XML copy, not the P4 text: texts/released/N3/N31062.p5.xml",
                  "P3 SGML copy, not the P4 text: texts/released/N3/N31062.sgm"], skips.notes
    refute(adapter.discover(workdir).any? { |ref| ref.path.end_with?(".p5.xml", ".sgm") })
  end

  def test_a_stray_file_under_texts_is_unrecognized_never_silent
    Dir.mktmpdir do |dir|
      unit = File.join(dir, "texts", "released", "N3")
      FileUtils.mkdir_p(unit)
      FileUtils.cp(fixture("texts", "released", "N3", "N31062.p4.xml"), unit)
      File.write(File.join(unit, "notes.txt"), "x")
      File.write(File.join(unit, Nabu::ZipFetch::STATE_FILE), "{}")
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized, "the dotfile ledger is never a stray"
      assert_equal [HAMMON], adapter.discover(dir).map(&:id)
    end
  end

  def test_the_class_scope_narrows_discovery
    assert_equal [HAMMON, TREASON], Nabu::Adapters::EvansTcp.new(classes: %w[released]).discover(workdir).map(&:id)
    assert_equal [PHILLIPS], Nabu::Adapters::EvansTcp.new(classes: %w[unedited]).discover(workdir).map(&:id)
  end

  def test_unknown_classes_are_a_configuration_error
    error = assert_raises(Nabu::ValidationError) { Nabu::Adapters::EvansTcp.new(classes: %w[phase1]) }
    assert_match(%r{released/unedited}, error.message)
    assert_raises(Nabu::ValidationError) { Nabu::Adapters::EvansTcp.new(classes: []) }
  end

  # -- parse --------------------------------------------------------------------

  def test_the_idg_id_equals_the_filename_stem
    adapter.discover(workdir).each do |ref|
      assert_equal ref.id.delete_prefix("urn:nabu:evans-tcp:"), adapter.parse(ref).metadata["idg_id"]
    end
  end

  def test_hammons_evening_thought_reads_verbatim
    document = adapter.parse(ref_for(HAMMON))
    assert_equal "en", document.language, "LANGUSAGE eng → en"
    assert_equal 91, document.count
    passages = document.to_a
    assert_equal "#{HAMMON}:d1.h1", passages[0].urn
    assert_equal "AN Evening THOUGHT. SALVATION BY CHRIST, WITH PENETENTIAL CRIES:", passages[0].text
    assert_equal "#{HAMMON}:d1.l1", passages[2].urn
    assert_equal "SALVATION comes by Jesus Christ alone,", passages[2].text
  end

  # Runtime-edited real N31062 bytes (never a checked-in fake): the one
  # censused LANGUSAGE slip (N14218 declares "pau" over an English novel)
  # reads as its erratum; any other foreign code rides verbatim.
  def test_the_censused_langusage_slip_reads_as_its_erratum
    body = File.read(fixture("texts", "released", "N3", "N31062.p4.xml"))
    edited = body.sub('<LANGUSAGE ID="eng"><LANGUAGE>eng', '<LANGUSAGE ID="pau"><LANGUAGE>pau')
    refute_equal body, edited
    Dir.mktmpdir do |dir|
      unit = File.join(dir, "texts", "released", "N1")
      FileUtils.mkdir_p(unit)
      File.write(File.join(unit, "N14218.p4.xml"), edited)
      File.write(File.join(unit, "N10000.p4.xml"), edited)
      slip, other = adapter.discover(dir).to_a.partition { |ref| ref.id.end_with?("N14218") }
      assert_equal "en", adapter.parse(slip.first).language
      assert_equal "pau", adapter.parse(other.first).language, "no erratum — upstream's code verbatim"
    end
  end

  def test_fixture_passage_counts_pin_the_grain
    assert_equal 137, adapter.parse(ref_for(PHILLIPS)).count
    assert_equal 10, adapter.parse(ref_for(TREASON)).count
  end

  def test_the_class_rides_metadata
    assert_equal "unedited", adapter.parse(ref_for(PHILLIPS)).metadata["tcp_class"]
    assert_equal "released", adapter.parse(ref_for(HAMMON)).metadata["tcp_class"]
  end

  def test_the_bibliography_numbers_ride_in_order
    assert_equal ["Shipton 41129", "Shipton 49079"], adapter.parse(ref_for(HAMMON)).metadata["bibliography_refs"]
    assert_equal ["Evans 680"], adapter.parse(ref_for(PHILLIPS)).metadata["bibliography_refs"]
  end

  def test_the_lcsh_subjects_ride_verbatim_and_fold_onto_the_kind_axis
    subjects = adapter.parse(ref_for(HAMMON)).metadata["subjects"]
    assert_equal ["Christian poetry.", "Salvation -- Poetry.", "Broadsides.", "Poems -- 1760."], subjects
    kinds = load_kinds
    assert kinds.open?("evans-tcp")
    assert_equal "subject", kinds.facet_for("evans-tcp")
    assert_equal ["literary/poetry"], subjects.flat_map { |heading| kinds.normalize("evans-tcp", heading) }.uniq
    treason = adapter.parse(ref_for(TREASON)).metadata["subjects"]
    assert_includes treason.flat_map { |heading| kinds.normalize("evans-tcp", heading) }, "legal/court",
                    "Trials (Treason) -- … is LCSH's trial-proceedings form heading"
    fold = kinds.fold("evans-tcp", "Broadsides.")
    assert_empty fold.paths, "a format heading mints no kind"
    assert_equal ["Broadsides."], fold.uncovered
  end

  # The 2026-11-07 heads: the fixture's three texts carry none of these
  # headings (verse, a trial), so the pins read live census headings.
  def test_orations_catechisms_and_doctrinal_works_fold_onto_the_new_heads
    kinds = load_kinds
    { "Fourth of July orations -- 1798." => ["oratory"],
      "Catechisms." => ["catechesis"],
      "Congregational churches -- Catechisms" => ["catechesis"],
      "Society of Friends -- Catechisms and creeds." => ["catechesis"],
      "Congregational churches -- Creeds" => ["catechesis"],
      "Society of Friends -- Doctrinal and controversial works." => ["theology"],
      "Apologetics -- 18th century." => ["theology/apologetics"] }.each do |heading, want|
      assert_equal want, kinds.normalize("evans-tcp", heading), heading
    end
    fold = kinds.fold("evans-tcp", "Slavery -- United States -- Controversial literature -- 1773.")
    assert_empty fold.paths, "Evans's controversial literature is mostly the slavery debate — no theology claim"
  end

  def test_the_subjects_project_as_the_subject_facet
    fields = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
                           .fields_for("evans-tcp")
    assert_equal "subject", fields["subjects"]
    assert_equal "author", fields["author"]
  end

  # -- dating -------------------------------------------------------------------

  def test_dating_registers_in_the_metadata_dates_lane
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["evans-tcp"]
    assert_equal %w[imprint_place imprint_place_conjecture source_pub_place],
                 Nabu::Store::TimelineBuilder::MetadataDates::PLACE_KEYS["evans-tcp"]
  end

  def test_the_american_imprint_statement_dates_through_the_later_print_mold
    assert_equal({ "not_before" => 1693, "not_after" => 1693, "raw" => "in the year 1693." },
                 adapter.parse(ref_for(PHILLIPS)).metadata["date"])
    assert_equal({ "not_before" => 1781, "not_after" => 1781, "raw" => "1781]" },
                 adapter.parse(ref_for(TREASON)).metadata["date"])
  end

  def test_an_uncertain_imprint_stays_raw_only
    assert_equal({ "raw" => "1760?]" }, adapter.parse(ref_for(HAMMON)).metadata["date"])
  end

  def test_the_later_print_molds_cover_the_censused_shapes
    envelope = Nabu::Adapters::TcpCollection.method(:imprint_envelope)
    # the census 2026-11-03 shapes EEBO's molds left raw-only
    { "in the year 1790." => [1790, 1790], "Printed in the year 1736." => [1736, 1736],
      "1792. Price 8d." => [1792, 1792], "May 6, 1798." => [1798, 1798], "--1794--" => [1794, 1794],
      "in the year, 1682." => [1682, 1682], "Nov. 1796." => [1796, 1796],
      "1777 - 1801." => [1777, 1801], "1785 - 1807]" => [1785, 1807] }.each do |raw, (low, high)|
      assert_equal({ "not_before" => low, "not_after" => high, "raw" => raw }, envelope.call(raw), raw)
    end
    # EEBO's own molds still answer first
    assert_equal({ "not_before" => 1681, "not_after" => 1682, "raw" => "1681/2." }, envelope.call("1681/2."))
    # never invented: uncertainty marks, two competing numbers, nothing at all
    assert_equal({ "raw" => "[1798?]" }, envelope.call("[1798?]"))
    assert_equal({ "raw" => "[ca. 1800]" }, envelope.call("[ca. 1800]"))
    assert_equal({ "raw" => "1765-71 [1765-80]" }, envelope.call("1765-71 [1765-80]"))
    assert_equal({ "raw" => "1705 [1704?]" }, envelope.call("1705 [1704?]"))
    assert_nil envelope.call(nil)
  end

  # -- places -------------------------------------------------------------------

  def test_the_imprint_place_rides_as_the_bare_town
    assert_equal "Philadelphia", adapter.parse(ref_for(PHILLIPS)).metadata["imprint_place"]
    treason = adapter.parse(ref_for(TREASON)).metadata
    assert_equal "[Frederick, Md.? :", treason["source_pub_place"]
    assert_equal "Frederick", treason["imprint_place_conjecture"], "the ?-marked imprint is a conjecture"
    refute treason.key?("imprint_place")
  end

  # -- license ------------------------------------------------------------------

  def test_the_cc0_waiver_maps_every_fixture_open
    adapter.discover(workdir).each do |ref|
      document = adapter.parse(ref)
      assert_equal "open", document.license_override, ref.id
      assert_includes document.metadata["availability"], "CC0 1.0 Public Domain Dedication"
    end
  end

  def test_a_stranger_availability_maps_restricted
    Dir.mktmpdir do |dir|
      unit = File.join(dir, "texts", "released", "N3")
      FileUtils.mkdir_p(unit)
      body = File.read(fixture("texts", "released", "N3", "N31062.p4.xml"))
      edited = body.sub(/the terms of the CC0 1\.0 Public Domain Dedication[^<]*/, "all rights reserved")
      refute_equal body, edited
      File.write(File.join(unit, "N31062.p4.xml"), edited)
      ref = adapter.discover(dir).first
      assert_equal "restricted", adapter.parse(ref).license_override
    end
  end

  # -- manifest + probe ---------------------------------------------------------

  def test_manifest_records_the_cc0_terms
    manifest = adapter.manifest
    assert_equal "evans-tcp", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "tcp-xml", manifest.parser_family
    assert_includes manifest.license, "CC0 1.0 Public Domain Dedication"
    assert_includes manifest.credit, "Text Creation Partnership"
    assert_equal SHARED, manifest.upstream_url
  end

  def test_remote_probe_is_a_liveness_only_head_of_the_box_folder
    assert_equal :http_zip, Nabu::Adapters::EvansTcp.remote_probe_strategy
    target = Nabu::Adapters::EvansTcp.http_probe_targets.first
    assert target.liveness_only
    assert_equal SHARED, target.zip_url
    assert_equal ".evans-tcp-fetch.json", target.state_file
  end

  # -- fetch --------------------------------------------------------------------

  def test_fetch_walks_the_box_folder_unpacks_both_classes_and_lands_sidecars
    stub_box!
    Dir.mktmpdir do |dir|
      report = fetch_adapter.fetch(dir)
      assert_match(/2 zips listed, 2 fetched, 0 unchanged; 3 texts on disk; classes: released\+unedited/,
                   report.notes)
      assert File.file?(File.join(dir, "texts", "released", "N3", "N31062.p4.xml"))
      assert File.file?(File.join(dir, "texts", "released", "N3", "N33557.p4.xml"))
      assert File.file?(File.join(dir, "texts", "unedited", "unedited", "N00552.p4.xml"))
      %w[eebo2prf.xml.dtd evans_pub_dates.txt].each { |name| assert File.file?(File.join(dir, name)), name }
      state = JSON.parse(File.read(File.join(dir, ".evans-tcp-fetch.json")))
      assert_equal({ "released" => { "zips" => 1, "texts" => 2 }, "unedited" => { "zips" => 1, "texts" => 1 } },
                   state["census"])
      assert_equal report.sha, state["sha256"]
      assert_equal [PHILLIPS, HAMMON, TREASON], fetch_adapter.discover(dir).map(&:id)
    end
  end

  def test_the_rejected_grains_are_never_requested
    stub_box!
    Dir.mktmpdir do |dir|
      fetch_adapter.fetch(dir)
      # the root listing names the P3/P5 folders and the catalogue sidecars
      # (real ids) — none is ever walked or downloaded
      assert_not_requested :get, "#{SHARED}/folder/230590735011" # P5_XML_OXF
      assert_not_requested :get, "#{SHARED}/folder/230593849542" # P3_SGML_TCP
      assert_not_requested :get, download_url("1333778619791")   # evnsdat_unfinished.sgm
      assert_not_requested :get, download_url("1333782599030")   # Evans_select.stage19.mtxt
    end
  end

  def test_a_resync_skips_unchanged_zips
    stub_box!
    Dir.mktmpdir do |dir|
      fetch_adapter.fetch(dir)
      report = fetch_adapter.fetch(dir)
      assert_match(/0 fetched, 2 unchanged/, report.notes)
      assert_requested :get, download_url("1333765453347"), times: 1
    end
  end

  def test_the_class_scope_never_downloads_the_other_class
    stub_box!
    Dir.mktmpdir do |dir|
      Nabu::Adapters::EvansTcp.new(classes: %w[released], delay: 0).fetch(dir)
      assert_not_requested :get, download_url("1333730319881")
      refute Dir.exist?(File.join(dir, "texts", "unedited"))
    end
  end

  def test_a_listing_without_a_scoped_class_aborts_before_any_write
    stub_box!
    stub_request(:get, "#{SHARED}/folder/#{P4_FOLDER_ID}")
      .to_return(status: 200, body: listing_without(fixture("fetch", "p4.html"), "unedited.zip"))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { fetch_adapter.fetch(dir) }
      assert_match(/lists no unedited zip/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  def test_an_outage_page_aborts_before_any_write
    stub_request(:get, SHARED).to_return(status: 200, body: "<html>maintenance</html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { fetch_adapter.fetch(dir) }
      assert_match(/postStreamData/, error.message)
      assert_empty Dir.children(dir)
    end
  end

  # -- store --------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "evans-tcp", name: "Evans-TCP",
                                        adapter_class: "Nabu::Adapters::EvansTcp", license_class: "open")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 238, db[:passages].count, "137 + 91 + 10 across the three fixture texts"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 3, second.skipped
    assert_equal 238, db[:passages].count
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

  def load_kinds
    Nabu::Kinds.load(classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
                     map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml"))
  end

  def fetch_adapter(classes = %w[released unedited])
    Nabu::Adapters::EvansTcp.new(classes: classes, delay: 0)
  end

  def download_url(file_id)
    "https://app.box.com/index.php?rm=box_v2_download_shared_file&" \
      "shared_name=zj7pzfokxde4glrhebxsavbbxzyr3ogz&file_id=f_#{file_id}"
  end

  # The fixture listing page with one named item removed (edited as JSON).
  def listing_without(page_path, name)
    body = File.read(page_path)
    match = body.match(%r{Box\.postStreamData\s*=\s*(\{.*?\});?\s*</script>}m) || flunk("no listing blob")
    data = JSON.parse(match[1])
    folder = data.fetch("/app-api/enduserapp/shared-folder")
    folder["items"] = folder["items"].reject { |item| item["name"] == name }
    body.sub(match[1], JSON.generate(data))
  end

  def stub_box!
    stub_request(:get, SHARED).to_return(status: 200, body: File.read(fixture("fetch", "root.html")))
    stub_request(:get, "#{SHARED}/folder/#{P4_FOLDER_ID}")
      .to_return(status: 200, body: File.read(fixture("fetch", "p4.html")))
    FILE_BODIES.each do |file_id, relpath|
      stub_request(:get, download_url(file_id))
        .to_return(status: 200, body: File.binread(fixture(*relpath.split("/"))))
    end
  end
end
