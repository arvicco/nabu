# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Wenhai adapter tests: The Digital Wenhai v1.1 "Phonology" (Beaudouin
# 2026, Zenodo 22817676, CC BY 4.0) — the native Tangut rhyme dictionary
# 文海 as one entry per source position, each joined to the fanqie
# statement that governs it. Fixture (test/fixtures/wenhai/README.md): the
# two taken CSVs cut to 22 records / 8 statements chosen for their shapes,
# plus the deposit's README and LICENSE (the rejected grain, skipped by
# rule). Dictionary-shaped, so it mirrors the passage conformance checks
# for the dictionary shape (the hdic stance) and adds the fetch pins, the
# DictionaryLoader contract and the registry row.
class WenhaiTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wenhai")
  ADAPTER = Nabu::Adapters::Wenhai

  FIXTURE_POSITIONS = [
    "05.131", "05.132", "05.141", "05.142", "06.272", "07.111", "07.112", "07.113",
    "16.262", "16.263", "16.271", "17.151*", "17.151a", "17.152a", "17.152b", "17.152c",
    "45.2~47.1", "79.151", "83.251", "84.232", "M09.111", "M11.222"
  ].freeze

  def adapter = ADAPTER.new

  def dictionary
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    adapter.parse(refs.first)
  end

  def entry(id) = dictionary.find { |e| e.entry_id == id } || flunk("no entry #{id}")

  # --- manifest + content kind -------------------------------------------------

  def test_manifest_records_the_cc_by_grant_and_the_record
    manifest = ADAPTER.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wenhai", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "cc-by-4.0", "the Zenodo record's license field, verbatim"
    assert_includes manifest.license, "Creative Commons Attribution 4.0 International Licence (CC BY 4.0)",
                    "LICENSE.txt, verbatim"
    assert_equal "https://doi.org/10.5281/zenodo.22817676", manifest.upstream_url
    assert_includes manifest.credit, "Beaudouin"
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, ADAPTER.content_kind
  end

  # --- discover / grains --------------------------------------------------------

  def test_discover_yields_the_record_table_only
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wenhai:01_wenhai.csv"], refs.map(&:id)
    assert_equal "wenhai", refs.first.source_id
    assert_equal "01_wenhai.csv", File.basename(refs.first.path)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_the_deposit_docs_are_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 2, skips.skipped_by_rule
    assert(skips.notes.any? { |note| note.include?("LICENSE.txt") && note.include?("README.md") })
    Dir.mktmpdir { |empty| assert_equal 0, adapter.discovery_skips(empty).skipped_by_rule }
  end

  # --- entries -------------------------------------------------------------------

  def test_one_tangut_dictionary_with_one_entry_per_position_in_upstream_order
    dict = dictionary
    assert_equal "wenhai", dict.slug
    assert_equal "txg", dict.language
    assert_equal FIXTURE_POSITIONS, dict.map(&:entry_id)
  end

  def test_entry_ids_are_unique_and_stable_across_two_parses
    first = snapshot
    assert_equal first.map(&:first).uniq, first.map(&:first)
    assert_equal first, snapshot, "a second independent parse mints identical ids and content hashes"
  end

  def test_entry_output_is_nfc_and_the_one_non_nfc_value_composes_at_the_boundary
    dictionary.each do |e|
      assert e.headword.unicode_normalized?(:nfc)
      assert e.body.unicode_normalized?(:nfc)
    end
    raw = File.read(File.join(FIXTURES, "01_wenhai", "01_wenhai.csv"), encoding: "UTF-8")
    assert_includes raw, "lʰjụ¹", "upstream writes u + U+0323 (the fixture keeps the bytes)"
    ghc = entry("M11.222").annotations.fetch("ghc")
    assert_equal "lʰjụ¹", ghc, "composed to U+1EE5 at the adapter boundary"
    assert_includes entry("M11.222").body, "lʰjụ¹"
  end

  def test_a_head_is_its_unicode_tangut_character_with_the_record_mined
    e = entry("05.131")
    assert_equal "𘀏", e.headword
    assert_equal 0x1800F, e.headword.ord, "U+1800F, the Unicode Tangut block"
    assert_equal "𘀏", e.key_raw
    assert_equal Nabu::Normalize.search_form("𘀏", language: "txg"), e.headword_folded
    assert_nil e.gloss, "v1.1 is the phonology release — no definitions in the deposit"
    assert_equal(
      { "position" => "05.131", "cycle" => "Major", "she" => "1", "subcycle" => "A", "grade" => "I",
        "tone_rhyme" => "1.01", "rhyme_name" => "𘁨", "li_fanwen" => "3909",
        "fanqie" => "𗈽𗒿𘈖𗥃", "fanqie_base" => "05.131", "fanqie_stated" => true,
        "upper_speller" => "𗈽", "lower_speller" => "𗒿",
        "initial_tyyj" => "I", "initial_chain" => "I-07", "rhyme_chain" => "R-087",
        "ghc" => "pu¹", "mb" => "pu̠¹" },
      e.annotations
    )
  end

  def test_the_body_carries_the_fanqie_chain_and_the_readings
    body = entry("05.131").body
    assert_includes body, "Wenhai 05.131"
    assert_includes body, "rhyme 𘁨 (ToneRhyme 1.01)"
    assert_includes body, "fanqie 𗈽𗒿𘈖𗥃 — upper speller 𗈽, lower speller 𗒿"
    assert_includes body, "initial chain I-07 (TYYJ I) · rhyme chain R-087"
    assert_includes body, "Gong Hwang-cherng pu¹ · Beaudouin pu̠¹"
    assert_includes body, "Li Fanwen 3909"
  end

  def test_governed_positions_inherit_the_statement_written_before_them
    e = entry("05.142")
    assert_equal "𗈽𗒿𘈖𗥃", e.annotations["fanqie"]
    assert_equal "05.131", e.annotations["fanqie_base"]
    assert_nil e.annotations["fanqie_stated"], "the cell is blank upstream — inherited, not stated here"
    assert_includes e.body, "fanqie 𗈽𗒿𘈖𗥃 (stated at 05.131)"
  end

  def test_the_spellers_are_crossrefs_into_the_same_dictionary
    refs = entry("05.131").crossrefs
    assert_equal %w[fanqie-upper fanqie-lower], refs.map(&:kind)
    assert_equal %w[𗈽 𗒿], refs.map(&:target)
    assert_equal [Nabu::Normalize.search_form("𗈽", language: "txg")], [refs.first.target_folded]
  end

  def test_unreadable_spellers_mint_no_crossref_and_no_chain
    e = entry("07.113")
    assert_equal "□□𘈖𗥃", e.annotations["fanqie"]
    assert_equal "06.272", e.annotations["fanqie_base"]
    assert_empty e.crossrefs
    assert_nil e.annotations["initial_chain"], "an unresolved set: upstream leaves the ClassID blank"
    assert_nil e.annotations["rhyme_chain"]
  end

  def test_a_split_node_keeps_its_suffix_as_the_node_and_the_bare_glyph_as_headword
    e = entry("16.262")
    assert_equal "𘅇a", e.key_raw
    assert_equal "𘅇", e.headword
    assert_equal "𘅇a", e.annotations["node"]
  end

  def test_suffixed_variant_positions_are_governed_through_their_unsuffixed_position
    %w[17.151* 17.151a 17.152a 17.152b 17.152c].each do |id|
      e = entry(id)
      assert_equal "17.142", e.annotations["fanqie_base"], id
      assert_equal "𗯴𗝠𘈖𘕕", e.annotations["fanqie"], id
    end
    assert_equal %w[42 4537], [entry("17.152a"), entry("17.152b")].map { |e| e.annotations["li_fanwen"] },
                 "one glyph, two Li Fanwen entries — two records"
  end

  def test_the_span_position_and_the_bracketed_head_are_honest
    span = entry("45.2~47.1")
    assert_equal "45.2 ~ 47.1", span.annotations["position"], "the position verbatim; the id drops the spaces"
    assert_nil span.annotations["fanqie"], "governed by no statement"
    bracket = entry("79.151")
    assert_equal "𗾌(𗣀)", bracket.key_raw
    assert_equal "𗾌", bracket.headword
    assert_equal "𗣀", bracket.annotations["variant"]
    assert_equal "79.141", bracket.annotations["fanqie_base"]
  end

  def test_a_recurring_head_stays_one_entry_per_position
    a = entry("83.251")
    b = entry("84.232")
    assert_equal [a.headword, b.headword], %w[𗭹 𗭹]
    assert_equal %w[𗪽𘂜 𗪽𗰊], [a.annotations["fanqie"], b.annotations["fanqie"]]
    assert_equal %w[R-024 R-024], [a.annotations["rhyme_chain"], b.annotations["rhyme_chain"]]
  end

  def test_a_mixed_tone_record_omits_the_blank_cycle_columns
    e = entry("M09.111")
    assert_equal "3.800", e.annotations["tone_rhyme"]
    refute e.annotations.key?("cycle")
    refute e.annotations.key?("rhyme_name")
    assert_nil e.annotations["fanqie"]
  end

  def test_a_schema_drift_is_a_parse_error
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      path = File.join(dir, "01_wenhai", "01_wenhai.csv")
      File.write(path, File.read(path).sub("GHC,MB", "GHC,MB,Gloss"))
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/columns/, error.message)
    end
  end

  # --- fetch -------------------------------------------------------------------

  def test_the_pins_name_the_full_deposit_files
    assert_equal "1f6741339bc2a6c83368a99747d3ba9d553ec69f5462d2d073477282d4dd204e",
                 ADAPTER::FILES.fetch("01_wenhai").fetch(:sha256)
    assert_equal "8e0a3699b65dbb8fbab7561d0c64d5528064aaba085eaed504a7c71fa8487b01",
                 ADAPTER::FILES.fetch("02b_fanqie_groups").fetch(:sha256)
    assert_equal 3_085, ADAPTER::RECORD_COUNT, "the record's own count, reconciled against the full 01 file"
    ADAPTER::FILES.each_key do |stem|
      assert_match %r{\Ahttps://zenodo\.org/api/records/22817676/files/[^/]+/content\z}, ADAPTER.url_for(stem)
    end
  end

  def test_fetch_lands_each_file_in_its_own_directory_and_verifies_the_pins
    bodies = fixture_bodies
    bodies.each { |stem, body| stub_request(:get, ADAPTER.url_for(stem)).to_return(status: 200, body: body) }
    pins = bodies.transform_values { |body| Digest::SHA256.hexdigest(body) }
    Dir.mktmpdir do |dir|
      report = ADAPTER.new(pins: pins).fetch(dir)
      ADAPTER::FILES.each do |stem, spec|
        assert_equal bodies.fetch(stem), File.binread(File.join(dir, stem, spec.fetch(:filename)))
      end
      refute_nil report.sha
      assert_equal 1, adapter.discover(dir).count
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    fixture_bodies.each { |stem, body| stub_request(:get, ADAPTER.url_for(stem)).to_return(status: 200, body: body) }
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(dir) }
      assert_match(/re-pin/, error.message)
      assert_empty Dir.glob(File.join(dir, "**", "*.csv"))
    end
  end

  # --- DictionaryLoader contract ------------------------------------------------

  def test_loading_the_fixture_twice_is_idempotent
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wenhai", name: "The Digital Wenhai", adapter_class: "Nabu::Adapters::Wenhai",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: "https://doi.org/10.5281/zenodo.22817676", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 22, first.added
    assert_equal 0, first.errored
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 22, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    row = db[:dictionary_entries].where(entry_id: "05.131").first
    assert_equal "urn:nabu:dict:wenhai:05.131", row[:urn]
    assert_equal "𘀏", row[:headword]
  end

  # --- registry ------------------------------------------------------------------

  def test_registry_row_exists_unwired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wenhai"]
    refute_nil entry, "config/sources.yml must register wenhai"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
    assert_equal "manual", entry.sync_policy
  end

  private

  def snapshot = dictionary.map { |e| [e.entry_id, Nabu::Store::ContentHash.dictionary_entry(e)] }

  def fixture_bodies
    ADAPTER::FILES.to_h do |stem, spec|
      [stem, File.binread(File.join(FIXTURES, stem, spec.fetch(:filename)))]
    end
  end
end
