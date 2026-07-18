# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"

# OpenEtruscan adapter tests (P29-0): the flat-csv corpus (Zenodo record
# 20075836 v1.0.0), the ocr_failed skip rule with discovery-skip
# accounting, the transliteration-derived search form, the -en translation
# siblings, and the WebMock'd two-artifact fetch with the frozen sha pins.
# Includes the shared AdapterConformance suite; fixtures are byte-verbatim
# upstream records (test/fixtures/open-etruscan/README.md).
class OpenEtruscanTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("open-etruscan")

  BASE_URNS = %w[
    urn:nabu:open-etruscan:cie-2609
    urn:nabu:open-etruscan:cie-2615
    urn:nabu:open-etruscan:cr-2.20
    urn:nabu:open-etruscan:ve-6.2
    urn:nabu:open-etruscan:etp-313
    urn:nabu:open-etruscan:etp-240
    urn:nabu:open-etruscan:etp-192
    urn:nabu:open-etruscan:cie-262
  ].freeze

  TRANSLATED_URNS = %w[
    urn:nabu:open-etruscan:cr-2.20-en
    urn:nabu:open-etruscan:ve-6.2-en
    urn:nabu:open-etruscan:etp-240-en
    urn:nabu:open-etruscan:etp-192-en
  ].freeze

  def conformance_adapter
    # translations: true — the registry row's posture; the -en siblings
    # must pass conformance too.
    Nabu::Adapters::OpenEtruscan.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "open-etruscan"
  end

  # P29-0: text_normalized is minted from the scholarly transliteration
  # column when the row carries one (the documented derivation — stored
  # verbatim in annotations, so it is recomputable from the stored passage
  # alone), else from the pristine text.
  def conformance_search_source(passage)
    Nabu::Adapters::OpenEtruscan.search_source(passage.text, passage.annotations)
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_pins_the_zenodo_deposit_and_the_flat_csv_family
    manifest = Nabu::Adapters::OpenEtruscan.manifest
    assert_equal "open-etruscan", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_match(/v1\.0\.0/, manifest.license, "the frozen deposit version is named")
    assert_equal "https://zenodo.org/records/20075836", manifest.upstream_url
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_remote_probe_heads_both_artifacts
    targets = Nabu::Adapters::OpenEtruscan.http_probe_targets
    assert_equal 2, targets.size
    assert_equal %w[corpus findspots], targets.map(&:state_subdir)
    assert(targets.all? { |t| t.state_file == Nabu::FileFetch::STATE_FILE })
    assert(targets.all? { |t| t.metadata_url.nil? }, "no probe-shaped license endpoint")
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_skips_ocr_failed_rows_and_mints_en_siblings
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal (BASE_URNS + TRANSLATED_URNS).sort, refs.map(&:id).sort
    refute_includes refs.map(&:id), "urn:nabu:open-etruscan:cie-2616",
                    "ocr_failed rows are skipped by rule, never minted"
    refute_includes refs.map(&:id), "urn:nabu:open-etruscan:cie-52a-b"
  end

  def test_discover_without_translations_flag_mints_base_refs_only
    refs = Nabu::Adapters::OpenEtruscan.new.discover(FIXTURES).to_a
    assert_equal BASE_URNS.sort, refs.map(&:id).sort
  end

  def test_discovery_skips_count_the_ocr_failed_rows
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule, "CIE 2616 + 'CIE 52a, b' are the fixture's ocr_failed rows"
    assert_equal 0, skips.unrecognized
    assert skips.clean?
  end

  # --- parse ------------------------------------------------------------------

  def parse_urn(urn)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "no ref for #{urn}"
    adapter.parse(ref)
  end

  def test_parse_keeps_the_carved_glyph_stream_and_the_layer_annotations
    document = parse_urn("urn:nabu:open-etruscan:cie-2609")
    assert_equal "ett", document.language
    assert_equal "CIE 2609", document.title
    assert_equal "clean", document.metadata.fetch("data_quality")
    assert_equal "1.000", document.metadata.fetch("intact_token_ratio")
    assert_equal 1, document.size
    passage = document.first
    assert_equal "urn:nabu:open-etruscan:cie-2609:1", passage.urn
    assert_equal "𐌅𐌄:𐌐𐌖𐌊𐌄:𐌅", passage.text, "raw_text verbatim — canonical means canonical"
    assert_equal "ve:puce:f", passage.annotations.fetch("transliterated")
    assert_equal "𐌅𐌄:𐌐𐌖𐌂𐌄:𐌚", passage.annotations.fetch("italic")
    assert_equal "ve puce f", passage.annotations.fetch("words")
  end

  def test_search_form_is_minted_from_the_transliteration_layer
    passage = parse_urn("urn:nabu:open-etruscan:cie-2609").first
    assert_equal Nabu::Normalize.search_form("ve:puce:f", language: "ett"), passage.text_normalized,
                 "Old Italic glyphs stay canonical; the SEARCH layer speaks the scholarly transliteration"
  end

  def test_needs_review_rows_mint_with_their_honest_quality_tag
    document = parse_urn("urn:nabu:open-etruscan:cie-262")
    assert_equal "needs_review", document.metadata.fetch("data_quality")
    assert_equal "IИAƧUƧVƎMVAJ IAN.ƆMƎJ", document.first.text,
                 "the raw mirror-glyph OCR stream stays canonical"
    assert_equal "InAsUsVeMVAJ IAN.cMeJ", document.first.annotations.fetch("transliterated"),
                 "upstream's deterministic mirror-glyph mapping rides the transliterated layer"
  end

  def test_bce_positive_years_are_carried_verbatim_in_metadata
    document = parse_urn("urn:nabu:open-etruscan:ve-6.2")
    assert_equal "650.0", document.metadata.fetch("year_from"),
                 "upstream's BCE-positive convention is canonical here; the SIGNED flip is the axis extractor's"
    assert_equal "625.0", document.metadata.fetch("year_to")
  end

  def test_en_siblings_carry_the_english_translation
    document = parse_urn("urn:nabu:open-etruscan:etp-192-en")
    assert_equal "eng", document.language
    assert_equal "translation", document.metadata.fetch("kind")
    assert_equal 1, document.size
    assert_equal "Laris Cleusinas, son of Laris.", document.first.text
    assert_equal "urn:nabu:open-etruscan:etp-192-en:1", document.first.urn
  end

  # --- fetch (WebMock'd two-artifact FileFetch) -------------------------------

  CORPUS_URL = Nabu::Adapters::OpenEtruscan::CORPUS_URL
  FINDSPOTS_URL = Nabu::Adapters::OpenEtruscan::FINDSPOTS_URL

  def fixture_bytes(*parts)
    File.binread(File.join(FIXTURES, *parts))
  end

  def stub_both(corpus:, findspots:)
    stub_request(:get, CORPUS_URL).to_return(status: 200, body: corpus)
    stub_request(:get, FINDSPOTS_URL).to_return(status: 200, body: findspots)
  end

  def pinned_adapter(corpus:, findspots:)
    Nabu::Adapters::OpenEtruscan.new(
      corpus_sha256: Digest::SHA256.hexdigest(corpus),
      findspots_sha256: Digest::SHA256.hexdigest(findspots)
    )
  end

  def test_fetch_lands_both_artifacts_under_their_subdirs
    corpus = fixture_bytes("corpus", "openetruscan_clean.csv")
    findspots = fixture_bytes("findspots", "Etruscan.csv")
    stub_both(corpus: corpus, findspots: findspots)
    Dir.mktmpdir do |dir|
      report = pinned_adapter(corpus: corpus, findspots: findspots).fetch(dir)
      assert_equal corpus, File.binread(File.join(dir, "corpus", "openetruscan_clean.csv"))
      assert_equal findspots, File.binread(File.join(dir, "findspots", "Etruscan.csv"))
      assert_match(/corpus/, report.notes)
      assert_match(/findspots/, report.notes)
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    corpus = fixture_bytes("corpus", "openetruscan_clean.csv")
    findspots = fixture_bytes("findspots", "Etruscan.csv")
    stub_both(corpus: corpus, findspots: findspots)
    Dir.mktmpdir do |dir|
      adapter = Nabu::Adapters::OpenEtruscan.new(
        corpus_sha256: "0" * 64,
        findspots_sha256: Digest::SHA256.hexdigest(findspots)
      )
      error = assert_raises(Nabu::FetchError) { adapter.fetch(dir) }
      assert_match(/re-pin/, error.message, "drift is an owner re-pin decision, named loudly")
      refute File.exist?(File.join(dir, "corpus", "openetruscan_clean.csv")),
             "the drifted artifact must never reach the tree"
    end
  end
end
