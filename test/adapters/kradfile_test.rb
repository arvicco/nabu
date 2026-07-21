# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"

# The KRADFILE adapter (P37-4): the EDRDG kanji→component decomposition index
# behind Jisho's multi-radical search. Dictionary-shaped (one entry per
# kanji, keyed on the glyph), single sha-pinned EUC-JP file (gz canonical).
# Mirrors the dictionary-shape conformance checks + the EUC-JP decode
# regression + the FileFetch path (WebMock only).
class KradfileTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("kradfile")
  URL = "http://ftp.edrdg.org/pub/Nihongo/kradfile.gz"

  def adapter = Nabu::Adapters::Kradfile.new

  # --- manifest + content kind -----------------------------------------------------

  def test_manifest_cites_the_edrdg_row_licence_verbatim
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "kradfile", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/The dictionary files are made available under a Creative Commons/, manifest.license,
                 "the SAME EDRDG grant sentence the edrdg row quotes")
    assert_match(/Attribution-ShareAlike Licence \(V4\.0\)/, manifest.license)
    assert_equal "radkfile", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Kradfile.content_kind
  end

  # --- discover → parse round-trip (EUC-JP decode) ---------------------------------

  def test_discover_yields_one_ref_anchored_on_kradfile
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["kradfile:kradfile"], refs.map(&:id)
    assert_equal ["kradfile"], refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse = adapter.parse(adapter.discover(FIXTURES).first)

  def test_parse_decodes_euc_jp_into_one_jpn_dictionary_document
    document = parse
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "kradfile", document.slug
    assert_equal "jpn", document.language
    assert_equal 10, document.size, "the 10 trimmed kanji lines"
  end

  def test_the_qi_entry_lists_its_components_including_the_tree_radical
    qi = parse.find { |e| e.headword == "棄" }
    refute_nil qi, "棄 survives the EUC-JP → UTF-8 NFC decode"
    assert_equal "U+68C4", format("U+%04X", qi.headword.ord)
    assert_equal "components: 一 木 亠 凵 厶", qi.body
  end

  def test_entry_ids_are_the_glyphs_unique_and_stable
    ids = parse.map(&:entry_id)
    assert_includes ids, "棄"
    assert_equal ids.uniq, ids
    assert_equal ids, parse.map(&:entry_id)
  end

  def test_components_helper_splits_a_raw_line
    assert_equal %w[一 木 亠 凵 厶], Nabu::Adapters::KradfileParser.components("棄 : 一 木 亠 凵 厶")
    assert_nil Nabu::Adapters::KradfileParser.components("# a comment")
  end

  # --- the gzip canonical shape (EUC-JP inside the gz) -----------------------------

  def gzip(bytes)
    io = StringIO.new(String.new(encoding: Encoding::BINARY))
    writer = Zlib::GzipWriter.new(io)
    writer.write(bytes)
    writer.close
    io.string
  end

  def test_discover_and_parse_read_the_post_fetch_gz_shape_under_the_same_id
    Dir.mktmpdir do |workdir|
      File.binwrite(File.join(workdir, "kradfile.gz"),
                    gzip(File.binread(File.join(FIXTURES, "kradfile"))))
      refs = adapter.discover(workdir).to_a
      assert_equal ["kradfile:kradfile"], refs.map(&:id), "gz and plain shapes mint the same ref id"
      document = adapter.parse(refs.first)
      assert_equal 10, document.size
      assert_equal "components: 一 木 亠 凵 厶", document.find { |e| e.headword == "棄" }.body
    end
  end

  def test_corrupt_gzip_raises_parse_error_not_a_bare_zlib_error
    Dir.mktmpdir do |workdir|
      File.binwrite(File.join(workdir, "kradfile.gz"), "not gzip at all")
      ref = adapter.discover(workdir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  def test_fetch_downloads_the_gz_and_pins_it
    stub_request(:get, URL).to_return(
      status: 200, body: gzip(File.binread(File.join(FIXTURES, "kradfile"))),
      headers: { "Last-Modified" => "Sun, 01 Aug 2021 00:00:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert File.file?(File.join(workdir, "kradfile.gz"))
      assert File.file?(File.join(workdir, Nabu::FileFetch::STATE_FILE))
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, URL).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  def test_probe_heads_the_gz_with_root_state
    assert_equal :http_zip, Nabu::Adapters::Kradfile.remote_probe_strategy
    target = Nabu::Adapters::Kradfile.http_probe_targets.first
    assert_equal URL, target.zip_url
    assert_equal "", target.state_subdir
    assert_nil target.metadata_url
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "kradfile", name: "KRADFILE", adapter_class: "Nabu::Adapters::Kradfile",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: URL, enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 10, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 10, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    qi = db[:dictionary_entries].where(entry_id: "棄").first
    assert_equal "urn:nabu:dict:kradfile:棄", qi[:urn]
  end

  def test_registry_row_exists_enabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["kradfile"]
    refute_nil entry, "config/sources.yml must register kradfile"
    assert_equal Nabu::Adapters::Kradfile, entry.adapter_class
    assert entry.enabled, "owner-fired first sync verified + flipped 2026-07-21"
    assert_equal "manual", entry.sync_policy
  end
end
