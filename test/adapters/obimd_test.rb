# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

# Nabu::Adapters::Obimd: the Oracle Bone Inscriptions Multi-modal Dataset
# (Anyang Normal University / Xiamen University; Hugging Face KLOBIP/OBIMD,
# CC BY 4.0) — Shang oracle-bone inscriptions from the Heji and Huadong
# corpora as character-annotated, reading-ordered inscription groups. The
# text layer is upstream's reference modern character per glyph UID.
#
# Fixtures (test/fixtures/obimd/, README there): a RECORD-SPLICE of the real
# data.json (8 whole records, upstream bytes and CRLF layout), the
# Main-character.json map trimmed to the 25 UIDs those records use, and the
# real dataset card (README.md) — the rejected card grain.
class ObimdTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("obimd")
  Obimd = Nabu::Adapters::Obimd
  REV = Obimd::REVISION
  DATA_URL = "https://huggingface.co/datasets/KLOBIP/OBIMD/resolve/#{REV}/data.json".freeze
  CHARS_URL = "https://huggingface.co/datasets/KLOBIP/OBIMD/resolve/#{REV}/" \
              "Hierarchical%20Character%20Metadata%20Supplement/Main-character.json".freeze
  CARD_URL = "https://huggingface.co/datasets/KLOBIP/OBIMD/resolve/#{REV}/README.md".freeze

  def conformance_adapter = Obimd.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "obimd"

  def adapter = conformance_adapter

  def parse(name)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "urn:nabu:obimd:#{name}" }
    refute_nil ref, "fixture record #{name} must be discovered"
    adapter.parse(ref)
  end

  def texts(name) = parse(name).map(&:text)

  # --- manifest / registry ----------------------------------------------------

  def test_manifest_records_the_dataset_card_license_verbatim
    manifest = Obimd.manifest
    assert_equal "attribution", manifest.license_class
    assert_match(/license: cc-by-4\.0/, manifest.license)
    assert_match(/Creative Commons Attribution 4\.0 International/, manifest.license)
    assert_match(/MIT/, manifest.license, "the Zenodo record's MIT covers the CODE release — recorded")
    assert_match(/Li, Bang/, manifest.credit)
  end

  def test_registry_resolves_obimd_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["obimd"]
    refute_nil entry
    assert_equal Obimd, entry.adapter_class
    assert entry.wired, "wired since the verified first sync (2026-10-21)"
    assert_equal Obimd.manifest, entry.manifest
  end

  # --- discovery ----------------------------------------------------------------

  def test_discover_yields_one_ref_per_rubbing_in_file_order
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[H2 H224 H4413 H8342 H9830 H14717 H17138 HD514].map { |n| "urn:nabu:obimd:#{n}" }, ids
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  # The rejected grain: the dataset card (README.md — the license stamp's
  # home) lands beside the data and is counted by rule, never silently.
  def test_discovery_skips_count_the_dataset_card
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_match(%r{dataset card.*card/README\.md}, skips.notes.join("\n"))
    assert skips.clean?
  end

  # --- documents ----------------------------------------------------------------

  def test_a_heji_rubbing_is_one_och_document
    document = parse("H2")
    assert_equal "urn:nabu:obimd:H2", document.urn
    assert_equal "och", document.language
    assert_equal "合集 2", document.title
    metadata = document.metadata
    assert_equal "甲骨文合集", metadata["collection"]
    assert_equal "2", metadata["number"]
    assert_equal "rubbing/h00002.jpg", metadata["rubbing_image"]
    assert_equal "facsimile/h00002.jpg", metadata["facsimile_image"]
    assert_equal({ "value" => "甲骨文合集" }, metadata.dig("facets", "collection"))
  end

  def test_a_huadong_rubbing_names_its_collection
    document = parse("HD514")
    assert_equal "花東 514", document.title
    assert_equal "殷墟花園莊東地甲骨", document.metadata["collection"]
  end

  # --- passages: one inscription group each ------------------------------------

  def test_groups_become_passages_in_reading_order
    document = parse("H224")
    assert_equal %w[urn:nabu:obimd:H224:1 urn:nabu:obimd:H224:2 urn:nabu:obimd:H224:3], document.map(&:urn)
    assert_equal ["□卜亘貞敢羌", "二三二一", "⬚二告二告"], document.map(&:text)
    assert_equal(%w[InscriptionSentence1 OracleSequence OracleOutcome1],
                 document.map { |passage| passage.annotations["group"] })
    assert_equal(%w[inscription oracle-sequence oracle-outcome],
                 document.map { |passage| passage.annotations["group_type"] })
  end

  # A PUA glyph whose transcription is a multi-character ligature reading
  # (合文 十一月) renders as that reading; a missing position (SeatFont 1)
  # is □.
  def test_a_ligature_glyph_renders_its_transcription
    assert_equal ["曰協田其受年十一月"], texts("H2")
  end

  def test_unrenderable_glyphs_are_the_gaiji_box_never_dropped
    assert_equal ["□在⬚"], texts("H8342"), "a UID absent from the character map is ⬚"
    uncertain = parse("H17138").passages.last
    assert_equal "⬚", uncertain.text, "an annotated glyph with no category label is ⬚"
    assert_equal "uncertain", uncertain.annotations["group_type"]
  end

  def test_labels_ride_annotations_with_placeholders_as_nil
    first = parse("H224").first
    labels = first.annotations["labels"]
    assert_equal 6, labels.size
    assert_nil labels.first, "the □ position carries no UID"
    assert(labels.drop(1).all? { |uid| uid.match?(/\A[0-9a-z]{10}\z/) })
  end

  def test_mark_codes_ride_annotations_by_position
    passage = parse("H14717").first
    assert_equal "□□于季", passage.text
    assert_equal({ "1" => 2 }, passage.annotations["marks"],
                 "Mark 2: on the rubbing only — doubt whether it is a glyph (upstream legend)")
    assert_equal({ "0" => 0 }, parse("H17138").passages.last.annotations["marks"],
                 "Mark 0: damaged, cannot be identified")
    refute parse("H2").first.annotations.key?("marks"), "-1 (normal) is the default and stays out"
  end

  def test_shared_order_numbers_keep_upstream_array_order
    assert_equal ["□令夫□"], texts("H4413"), "two glyphs at order 2 — stable by array position"
  end

  def test_duplicate_group_labels_still_mint_distinct_urns
    document = parse("H9830")
    assert_equal(%w[InscriptionSentence2 InscriptionSentence2 OracleSequence2],
                 document.map { |passage| passage.annotations["group"] })
    assert_equal 3, document.map(&:urn).uniq.size
  end

  # --- damage is loud ---------------------------------------------------------

  def test_a_record_whose_name_drifted_from_its_ref_is_a_parse_error
    ref = adapter.discover(FIXTURES).first
    forged = Nabu::DocumentRef.new(source_id: ref.source_id, id: "urn:nabu:obimd:H3", path: ref.path,
                                   metadata: ref.metadata)
    assert_raises(Nabu::ParseError) { adapter.parse(forged) }
  end

  # --- fetch (WebMock only) -----------------------------------------------------

  def test_fetch_lands_the_three_pinned_files
    stub_files
    Dir.mktmpdir do |workdir|
      pinned = Obimd.new(pins: fixture_pins)
      report = pinned.fetch(workdir)
      assert_match(/\A\h{64}\z/, report.sha)
      assert File.file?(File.join(workdir, "data", "data.json"))
      assert File.file?(File.join(workdir, "chars", "Main-character.json"))
      assert File.file?(File.join(workdir, "card", "README.md"))
      assert_equal 8, pinned.discover(workdir).count
    end
  end

  def test_fetch_refuses_a_body_that_drifted_from_its_pin
    stub_files
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Obimd.new(pins: fixture_pins.merge("data" => "0" * 64)).fetch(workdir) }
      assert_match(/drifted/, error.message)
      refute File.exist?(File.join(workdir, "data", "data.json")), "the tree stays untouched on a pin miss"
    end
  end

  def test_probe_heads_the_three_resolve_urls
    assert_equal :http_zip, Obimd.remote_probe_strategy
    assert_equal [DATA_URL, CHARS_URL, CARD_URL], Obimd.http_probe_targets.map(&:zip_url)
  end

  # --- store ------------------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "obimd", name: "OBIMD", adapter_class: "Nabu::Adapters::Obimd",
                                        license_class: "attribution")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 8, first.added
    assert_equal 0, first.errored
    assert_equal 14, db[:passages].count, "1+3+1+1+3+1+2+2 inscription groups"
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 8, second.skipped
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def fixture_pins
    {
      "data" => Digest::SHA256.file(File.join(FIXTURES, "data", "data.json")).hexdigest,
      "chars" => Digest::SHA256.file(File.join(FIXTURES, "chars", "Main-character.json")).hexdigest,
      "card" => Digest::SHA256.file(File.join(FIXTURES, "card", "README.md")).hexdigest
    }
  end

  def stub_files
    { DATA_URL => %w[data data.json], CHARS_URL => %w[chars Main-character.json],
      CARD_URL => %w[card README.md] }.each do |url, (subdir, name)|
      stub_request(:get, url).to_return(status: 200, body: File.binread(File.join(FIXTURES, subdir, name)))
    end
  end
end
