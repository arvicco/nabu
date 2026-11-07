# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"
require "json"

# Nabu::Adapters::Cgpg (P153; the work grain): the Calfa/GREgORI Patrologia
# Graeca deposit (Zenodo 19915273, CC BY 4.0) — 33 Migne volumes, machine
# OCR with automatic lemma/POS — carved into works by open-greek-corpus's
# carve plan (materialized under carve/). Fixtures: eight volume files
# trimmed to whole OCR lines of a few pages, the plan trimmed to those
# volumes' entries, and the raw-OCR rejected grain (see the fixture README).
class CgpgTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("cgpg")
  ZIP_URL = Nabu::Adapters::Cgpg::ZIP_URL
  PLAN_URL = Nabu::Adapters::Cgpg::CARVE_PLAN_URL
  PLAN_FIXTURE = File.join(FIXTURES, "carve", "cgpg_carve_plan.json")
  JOANNIS = "urn:nabu:cgpg:theophylactus-achridensis.enarratio-in-evangelium-joannis"

  def conformance_adapter = Nabu::Adapters::Cgpg.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "cgpg"

  def adapter = conformance_adapter

  def parse(urn, workdir: FIXTURES, with: adapter)
    with.parse(with.discover(workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}"))
  end

  def test_manifest
    manifest = Nabu::Adapters::Cgpg.manifest
    assert_equal "cgpg", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "cgpg-vert", manifest.parser_family
    assert_match(/CC BY 4\.0/, manifest.license)
  end

  def test_the_carve_plan_is_a_declared_materialization
    assert_equal ["carve"], Nabu::Adapters::Cgpg.materialized_paths
  end

  # PG order; inside a carved volume its works in page order, then its
  # residuum. PG 3 is planned but deferred and PG 8 / PG 153 are not in
  # the plan: those keep the volume grain.
  def test_discover_carves_planned_volumes_and_keeps_the_rest_whole
    assert_equal %w[urn:nabu:cgpg:pg3 urn:nabu:cgpg:pg8
                    urn:nabu:cgpg:photius.amphilochia urn:nabu:cgpg:pg101-residuum
                    urn:nabu:cgpg:theophylactus-achridensis.enarratio-in-evangelium-joannis
                    urn:nabu:cgpg:pg123-residuum
                    urn:nabu:cgpg:theophylactus-achridensis.expositio-in-epistolam-ad-romanos
                    urn:nabu:cgpg:pg124-residuum
                    urn:nabu:cgpg:joannes-zonaras.epitome-historiarum-lib-1-12
                    urn:nabu:cgpg:joannes-zonaras.epitome-historiarum-lib-12-clausula-varia-dub
                    urn:nabu:cgpg:pg134-residuum
                    urn:nabu:cgpg:isidorus-thessalonicensis.sermones-in-deiparam
                    urn:nabu:cgpg:joel.chronographia-compendiaria
                    urn:nabu:cgpg:nicetas-choniates.historia-xronikh-dih-ghsis
                    urn:nabu:cgpg:pg139-residuum
                    urn:nabu:cgpg:pg153], adapter.discover(FIXTURES).map(&:id)
  end

  def test_part_volumes_mint_their_dotted_number
    assert_equal "16.3", Nabu::Adapters::Cgpg.volume_of("PG016_3_tagged_text.vert")
    assert_equal "87.1", Nabu::Adapters::Cgpg.volume_of("PG087_1_tagged_text.vert")
    assert_equal "101", Nabu::Adapters::Cgpg.volume_of("PG101_tagged_text.vert")
    assert_nil Nabu::Adapters::Cgpg.volume_of("PG101_text.txt")
  end

  def test_the_volume_table_covers_the_whole_deposit
    assert_equal 33, Nabu::Adapters::Cgpg::VOLUMES.size
    assert_equal %w[3 5 6 8 9 16.3 21 42 67 71 73 87.1], Nabu::Adapters::Cgpg::VOLUMES.keys.first(12)
  end

  # Two grains not taken, each counted with its note: the raw-OCR text,
  # and a plan volume the box does not hold (the fixture tree holds no
  # PG 146 file — on the live box every plan volume is held).
  def test_the_raw_ocr_grain_and_an_unheld_plan_volume_are_skipped_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule
    notes = skips.notes.join("\n")
    assert_match(/PG101_text\.txt: not a tagged volume file/, notes)
    assert_match(/PG 146: in the carve plan \(1 work\) but no volume file is held/, notes)
  end

  def test_a_work_takes_its_plan_rows_as_passages
    document = parse("urn:nabu:cgpg:photius.amphilochia")
    assert_equal ["urn:nabu:cgpg:photius.amphilochia:pg101:p44"], document.passages.map(&:urn),
                 "293 sits inside 44-611 but the plan cuts it out (residual_loci)"
    assert_equal "PG 101 — Photius, Amphilochia (Migne main series: prooemium + quaestiones I-CCCXXI+, truncated)",
                 document.title
    passage = document.passages.first
    assert_equal({ "pdf_page" => 44, "pg_volume" => "101" }, passage.annotations.except("tokens"))
    assert_includes passage.text, "Τῆς σπουδῆς σου τὸ γνήσιον"
  end

  def test_work_metadata_carries_the_plan_identity_and_rank
    metadata = parse("urn:nabu:cgpg:joannes-zonaras.epitome-historiarum-lib-1-12").metadata
    assert_equal "work", metadata["carve"]
    assert_equal "joannes-zonaras.epitome-historiarum-lib-1-12", metadata["carve_slug"]
    assert_equal "Joannes Zonaras", metadata["author"]
    assert_equal "Epitome historiarum (lib. 1-12)", metadata["work_title"]
    assert_equal "tlg3135.tlg001", metadata["tlg"]
    assert_equal "secondary", metadata["carve_rank"]
    assert_match(/served from/, metadata["secondary_reason"])
    assert_equal [{ "pg_volume" => "134", "ranges" => [[31, 567]] }], metadata["carve_ranges"]
    assert_equal({ "planned" => 535, "held" => 1 }, metadata["rows"], "537 in range less the 563-564 rescan")
    assert_equal "134", metadata["pg_volume"]
    assert_equal "12th century", metadata["period"]
    assert_equal({ "not_before" => 1101, "not_after" => 1200, "raw" => "12th century", "class" => "composition" },
                 metadata["date"])
    assert_equal "uncorrected-ocr", metadata["text_nature"]
    assert_equal({ "verified" => 0, "unverifiable" => 1 }, metadata["incipit_checks"],
                 "the check sits at locus 31, a page the fixture does not hold")
  end

  def test_a_work_with_no_secondary_rank_is_primary
    metadata = parse("urn:nabu:cgpg:joannes-zonaras.epitome-historiarum-lib-12-clausula-varia-dub").metadata
    assert_equal "primary", metadata["carve_rank"]
    refute metadata.key?("secondary_reason")
    assert_equal({ "verified" => 1, "unverifiable" => 0 }, metadata["incipit_checks"],
                 "the clausula opens mid-page at 568, line 33")
  end

  def test_an_appended_work_spans_both_volumes
    document = parse(JOANNIS)
    assert_equal ["#{JOANNIS}:pg123:p569", "#{JOANNIS}:pg124:p10"], document.passages.map(&:urn)
    assert_equal [0, 1], document.passages.map(&:sequence)
    metadata = document.metadata
    assert_equal %w[123 124], metadata["pg_volumes"]
    assert_equal [{ "pg_volume" => "123", "ranges" => [[569, 679]] },
                  { "pg_volume" => "124", "ranges" => [[10, 164]] }], metadata["carve_ranges"]
    assert_match(/complete across two volumes/, document.title, "the continuation's title states the whole")
    assert document.title.start_with?("PG 123, 124 — Theophylactus Achridensis, ")
    assert_equal({ "verified" => 2, "unverifiable" => 1 }, metadata["incipit_checks"])
  end

  # Edition apparatus (the plan's residual), rescans (drop_duplicates) and
  # rows no work claims all land in the volume's residuum, each passage
  # naming its class — nothing the deposit holds is dropped.
  def test_the_residuum_keeps_every_row_no_work_claims
    document = parse("urn:nabu:cgpg:pg134-residuum")
    assert_equal ["urn:nabu:cgpg:pg134-residuum:p563"], document.passages.map(&:urn)
    assert_equal({ "pdf_page" => 563, "pg_volume" => "134", "residuum_class" => "duplicate", "duplicate_of" => 561 },
                 document.passages.first.annotations.except("tokens"))
    assert_equal({ "duplicate" => 1 }, document.metadata["residuum_rows"])
    assert_equal "residuum", document.metadata["carve"]
    assert_equal "PG 134 — residuum: edition apparatus, rescans and uncarved rows", document.title
    refute document.metadata.key?("date"), "the volume's era label dates its works, not Migne's apparatus"

    apparatus = parse("urn:nabu:cgpg:pg101-residuum")
    assert_equal(%w[p14 p293], apparatus.passages.map { |p| p.urn.split(":").last })
    assert_equal(%w[apparatus apparatus], apparatus.passages.map { |p| p.annotations["residuum_class"] })
    assert_match(/prefatory matter/, apparatus.metadata["residual_note"])
  end

  def test_a_residuum_or_work_with_no_held_rows_is_skipped_by_rule
    error = assert_raises(Nabu::DocumentSkipped) { parse("urn:nabu:cgpg:pg123-residuum") }
    assert_match(/no held rows/, error.reason)
  end

  def test_unplanned_and_deferred_volumes_keep_the_volume_grain
    document = parse("urn:nabu:cgpg:pg153")
    assert_equal "PG 153 — John Cantacuzene (vol. 1): Historia Byzantina in 4 books (events from 1320–1354)",
                 document.title
    assert_equal ["urn:nabu:cgpg:pg153:p37"], document.passages.map(&:urn)
    metadata = document.metadata
    assert_equal "volume", metadata["carve"]
    assert_equal "not in the carve plan", metadata["carve_note"]
    assert_equal 230_239, metadata["words_advertised"]
    assert_equal({ "not_before" => 1301, "not_after" => 1400, "raw" => "14th century", "class" => "composition" },
                 metadata["date"])
    assert_equal "PG 153 - AI processed", metadata["doc_id"]

    deferred = parse("urn:nabu:cgpg:pg3").metadata
    assert_match(/deferred by the carve plan: every work range interleaves/, deferred["carve_note"])
  end

  # The kind fold's facet (CgpgTitleGenre): a carved work's genre head
  # cut from its plan title, raw = the title itself.
  def test_a_carved_work_carries_its_title_genre_head
    {
      "urn:nabu:cgpg:photius.amphilochia" => "Amphilochia",
      JOANNIS => "Enarratio",
      "urn:nabu:cgpg:theophylactus-achridensis.expositio-in-epistolam-ad-romanos" => "Expositio in",
      "urn:nabu:cgpg:joannes-zonaras.epitome-historiarum-lib-1-12" => "Historia",
      "urn:nabu:cgpg:isidorus-thessalonicensis.sermones-in-deiparam" => "Sermones",
      "urn:nabu:cgpg:joel.chronographia-compendiaria" => "Chronographia"
    }.each do |urn, head|
      document = parse(urn)
      assert_equal({ "genre" => { "value" => head, "raw" => document.metadata["work_title"] } },
                   document.metadata["facets"], urn)
    end
  end

  # A single-genre whole volume declares its head in VOLUMES (raw = the
  # volume's contents label); a mixed or deferred volume and every
  # residuum make no kind claim.
  def test_only_single_genre_volumes_claim_a_kind_and_residua_never_do
    metadata = parse("urn:nabu:cgpg:pg153").metadata
    assert_equal({ "genre" => { "value" => "Historia", "raw" => metadata["contents"] } }, metadata["facets"])
    refute parse("urn:nabu:cgpg:pg3").metadata.key?("facets"), "PG 3 interleaves Dionysius and Pachymeres"
    refute parse("urn:nabu:cgpg:pg8").metadata.key?("facets"), "Clement's Protrepticus, Paedagogus, Stromata"
    refute parse("urn:nabu:cgpg:pg134-residuum").metadata.key?("facets"), "apparatus is no genre"
    assert_equal({ "21" => "Apologia", "71" => "Commentarius", "73" => "Commentarius", "121" => "Historia",
                   "148" => "Historia", "153" => "Historia" },
                 Nabu::Adapters::Cgpg::VOLUMES.select { |_, entry| entry[:genre] }.transform_values { |e| e[:genre] })
  end

  # "Pre-Nicaean" names no century but has a crisp right edge — the
  # Council of Nicaea, 325: an OPEN-START envelope, upstream's label raw.
  def test_the_pre_nicaean_label_is_an_open_start_envelope
    metadata = parse("urn:nabu:cgpg:pg8").metadata
    assert_equal "Pre-Nicaean", metadata["period"]
    assert_equal({ "not_after" => 325, "raw" => "Pre-Nicaean", "class" => "composition" }, metadata["date"])
    assert_equal [nil, 325], Nabu::Adapters::Cgpg.period_band("Pre-Nicaean")
    assert_equal [1101, 1200], Nabu::Adapters::Cgpg.period_band("12th century"), "centuries band as before"
    assert_nil Nabu::Adapters::Cgpg.period_band("pre-nicaean"), "the label is matched verbatim"
  end

  def test_the_pre_nicaean_envelope_projects_with_an_open_start
    doc = { id: 1, metadata_json: JSON.generate(parse("urn:nabu:cgpg:pg8").metadata) }
    row = Nabu::Store::TimelineBuilder::MetadataDates.axis_row(doc, :structured)
    assert_equal [nil, 325, "Pre-Nicaean", "composition"],
                 row.values_at(:not_before, :not_after, :date_raw, :date_class)
  end

  def test_without_a_carve_plan_every_volume_keeps_the_volume_grain
    with_tree(plan: false) do |workdir|
      ids = adapter.discover(workdir).map(&:id)
      assert_equal %w[urn:nabu:cgpg:pg3 urn:nabu:cgpg:pg8 urn:nabu:cgpg:pg101 urn:nabu:cgpg:pg123
                      urn:nabu:cgpg:pg124 urn:nabu:cgpg:pg134 urn:nabu:cgpg:pg139 urn:nabu:cgpg:pg153], ids
      assert_equal 0, adapter.discovery_skips(workdir).skipped_by_rule, "no plan, so no plan volume to miss"
    end
  end

  # The plan quotes each work's opening; a page that does not carry it
  # means the ranges no longer fit the deposit — quarantine, never shift.
  def test_an_incipit_mismatch_quarantines_the_work
    with_tree(mutate: lambda do |raw|
      work = raw["volumes"].find { |v| v["volume"] == "PG139" && v["works"].any? }["works"].first
      work["incipit_checks"] = [{ "locus" => 167, "text" => "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν" }]
    end) do |workdir|
      error = assert_raises(Nabu::ParseError) do
        parse("urn:nabu:cgpg:nicetas-choniates.historia-xronikh-dih-ghsis", workdir: workdir)
      end
      assert_match(/incipit check at PG 139 locus 167/, error.message)
    end
  end

  def test_century_labels_band_to_centuries
    assert_equal [401, 500], Nabu::Adapters::Cgpg.century_band("5th century")
    assert_equal [1001, 1100], Nabu::Adapters::Cgpg.century_band("11th century")
    assert_equal [1, 100], Nabu::Adapters::Cgpg.century_band("1st century")
    assert_nil Nabu::Adapters::Cgpg.century_band("Pre-Nicaean")
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def test_fetch_verifies_both_pins_and_materializes_the_plan_beside_the_volumes
    body = stub_zip_body
    plan = File.binread(PLAN_FIXTURE)
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    stub_request(:get, PLAN_URL).to_return(status: 200, body: plan)
    Dir.mktmpdir do |workdir|
      fetcher = pinned_fetcher(body, plan)
      report = fetcher.fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal plan, File.binread(File.join(workdir, "carve", "cgpg_carve_plan.json"))
      assert_includes fetcher.discover(workdir).map(&:id), JOANNIS
      fetcher.fetch(workdir)
      assert File.file?(File.join(workdir, "carve", "cgpg_carve_plan.json")), "a re-fetch never dooms the plan"
    end
  end

  def test_fetch_aborts_on_a_zip_pin_mismatch_with_the_tree_untouched
    stub_request(:get, ZIP_URL).to_return(status: 200, body: stub_zip_body)
    stub_request(:get, PLAN_URL).to_return(status: 200, body: File.binread(PLAN_FIXTURE))
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Cgpg.new.fetch(workdir) }
      assert_match(/PG\.zip.*pin/, error.message)
      assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
    end
  end

  def test_fetch_aborts_on_a_carve_plan_pin_mismatch_with_the_tree_untouched
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    stub_request(:get, PLAN_URL).to_return(status: 200, body: "#{File.binread(PLAN_FIXTURE)} ")
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) do
        Nabu::Adapters::Cgpg.new(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      end
      assert_match(/carve plan.*pin/, error.message)
      assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
    end
  end

  def test_the_live_carve_plan_pin_is_the_tagged_file
    assert_equal "7c0fec3de35cfaa15c0d58abf283e782a3d85d7f22a37aa77269464da797228c",
                 Nabu::Adapters::Cgpg::CARVE_PLAN_SHA256
    assert_match(%r{/open-greek/open-greek-corpus/corpus-2026-10-28\.2/data/cgpg_carve_plan\.json\z}, PLAN_URL)
  end

  def test_fetch_wraps_http_failure
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::Cgpg.new.fetch(workdir) }
    end
  end

  # --- idempotency ---------------------------------------------------------------

  def test_loading_the_fixture_set_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "cgpg", name: "CGPG", adapter_class: "Nabu::Adapters::Cgpg",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 15, first.added
    assert_equal 1, first.skipped_by_rule, "pg123-residuum: every held PG 123 row is the John commentary"
    assert_equal 0, first.errored
    assert_equal 18, db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 15, second.skipped
    assert_equal 18, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  end

  private

  def pinned_fetcher(body, plan)
    Nabu::Adapters::Cgpg.new(pin: Digest::SHA256.hexdigest(body), carve_pin: Digest::SHA256.hexdigest(plan))
  end

  # A copy of the fixture tree, optionally without the plan or with it edited.
  def with_tree(plan: true, mutate: nil)
    Dir.mktmpdir do |workdir|
      Dir.glob(File.join(FIXTURES, "PG*")).each { |path| FileUtils.cp(path, workdir) }
      if plan
        FileUtils.mkdir_p(File.join(workdir, "carve"))
        raw = JSON.parse(File.read(PLAN_FIXTURE))
        mutate&.call(raw)
        File.write(File.join(workdir, "carve", "cgpg_carve_plan.json"), JSON.generate(raw))
      end
      yield workdir
    end
  end

  # The upstream layout: one top-level PG/ directory holding the members.
  def stub_zip_body
    Dir.mktmpdir do |dir|
      staging = File.join(dir, "staging", "PG")
      FileUtils.mkdir_p(staging)
      Dir.glob(File.join(FIXTURES, "PG*_tagged_text.*")).each { |path| FileUtils.cp(path, staging) }
      zip_path = File.join(dir, "PG.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "PG", chdir: File.join(dir, "staging"))
      return File.binread(zip_path)
    end
  end
end
