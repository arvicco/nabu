# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "zlib"

# The EDRDG adapter (P32-4): KANJIDIC2 + JMdict as one source, two
# dictionaries (the lexica precedent). Dictionary-shaped, so it mirrors the
# passage conformance checks for the dictionary shape and adds the
# nightly-upstream FileFetch path (two .gz files, one subdir each — WebMock
# only), the plain-or-gzip discover shapes, the probe targets, the
# DictionaryLoader contract and the registry row.
class EdrdgTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("edrdg")

  URLS = {
    "kanjidic2" => "http://ftp.edrdg.org/pub/Nihongo/kanjidic2.xml.gz",
    "jmdict" => "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
  }.freeze

  def adapter = Nabu::Adapters::Edrdg.new

  # --- manifest + content kind ----------------------------------------------------

  def test_manifest_identifies_edrdg_with_the_verbatim_licence_sentence
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "edrdg", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/The dictionary files are made available under a Creative Commons/, manifest.license,
                 "the licence page's grant sentence travels verbatim")
    assert_match(/Attribution-ShareAlike Licence \(V4\.0\)/, manifest.license)
    assert_equal "edrdg-xml", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Edrdg.content_kind
  end

  # --- discover → parse round-trip -------------------------------------------------

  def test_discover_yields_one_ref_per_dictionary_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["kanjidic2:kanjidic2.xml", "jmdict:JMdict_e.xml"], refs.map(&:id)
    assert_equal %w[edrdg edrdg], refs.map(&:source_id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("dictionary") == slug }
    adapter.parse(ref)
  end

  def test_parse_yields_two_jpn_dictionary_documents
    kanjidic2 = parse("kanjidic2")
    assert_kind_of Nabu::DictionaryDocument, kanjidic2
    assert_equal "kanjidic2", kanjidic2.slug
    assert_equal "jpn", kanjidic2.language
    assert_equal 10, kanjidic2.size

    jmdict = parse("jmdict")
    assert_equal "jmdict", jmdict.slug
    assert_equal "jpn", jmdict.language
    assert_equal 6, jmdict.size
  end

  def test_entry_ids_are_unique_and_stable_across_independent_passes
    %w[kanjidic2 jmdict].each do |slug|
      first = parse(slug).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parse(slug).map(&:entry_id)
    end
  end

  def test_kanjidic2_entry_ids_join_unihan_by_codepoint
    ids = parse("kanjidic2").map(&:entry_id)
    assert_includes ids, "U+4E00", "the same key shape Unihan mints — the bridge join"
    assert(ids.all? { |id| id.match?(/\AU\+\h{4,6}\z/) })
  end

  # --- the gzip canonical shape ----------------------------------------------------

  def gzip(bytes)
    io = StringIO.new(String.new(encoding: Encoding::BINARY))
    writer = Zlib::GzipWriter.new(io)
    writer.write(bytes)
    writer.close
    io.string
  end

  def test_discover_and_parse_read_the_post_fetch_gz_shape_under_the_same_ids
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "kanjidic2"))
      FileUtils.mkdir_p(File.join(workdir, "jmdict"))
      File.binwrite(File.join(workdir, "kanjidic2", "kanjidic2.xml.gz"),
                    gzip(File.binread(File.join(FIXTURES, "kanjidic2.xml"))))
      File.binwrite(File.join(workdir, "jmdict", "JMdict_e.gz"),
                    gzip(File.binread(File.join(FIXTURES, "JMdict_e.xml"))))
      refs = adapter.discover(workdir).to_a
      assert_equal ["kanjidic2:kanjidic2.xml", "jmdict:JMdict_e.xml"], refs.map(&:id),
                   "gz and plain shapes mint the SAME ref ids (the mw precedent)"
      assert_equal 10, adapter.parse(refs.first).size
      assert_equal 6, adapter.parse(refs.last).size
    end
  end

  def test_corrupt_gzip_raises_parse_error_not_a_bare_zlib_error
    Dir.mktmpdir do |workdir|
      FileUtils.mkdir_p(File.join(workdir, "kanjidic2"))
      File.binwrite(File.join(workdir, "kanjidic2", "kanjidic2.xml.gz"), "not gzip at all")
      ref = adapter.discover(workdir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (WebMock only) --------------------------------------------------------

  def test_fetch_downloads_both_gz_files_into_their_own_subdirs
    URLS.each_value do |url|
      stub_request(:get, url).to_return(
        status: 200, body: gzip("placeholder"),
        headers: { "Last-Modified" => "Sun, 19 Jul 2026 03:30:36 GMT" }
      )
    end
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal URLS.values.sort, report.repos.keys.sort, "per-file shas ride the report"
      assert File.file?(File.join(workdir, "kanjidic2", "kanjidic2.xml.gz"))
      assert File.file?(File.join(workdir, "jmdict", "JMdict_e.gz"))
      assert File.file?(File.join(workdir, "kanjidic2", Nabu::FileFetch::STATE_FILE)),
             "each dictionary keeps its own Last-Modified pin — the nightly-build dating"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, URLS.fetch("kanjidic2")).to_return(status: 500)
    Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { adapter.fetch(workdir) } }
  end

  # --- remote-health probe shape ---------------------------------------------------

  def test_probe_heads_each_gz_with_per_dictionary_state
    assert_equal :http_zip, Nabu::Adapters::Edrdg.remote_probe_strategy
    targets = Nabu::Adapters::Edrdg.http_probe_targets
    assert_equal URLS.values, targets.map(&:zip_url)
    assert_equal %w[kanjidic2 jmdict], targets.map(&:state_subdir)
    targets.each do |target|
      assert_nil target.metadata_url
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end
  end

  # --- DictionaryLoader contract ---------------------------------------------------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "edrdg", name: "EDRDG", adapter_class: "Nabu::Adapters::Edrdg",
      license: "CC BY-SA 4.0", license_class: "attribution",
      upstream_url: "http://ftp.edrdg.org/pub/Nihongo/", enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixture_twice_is_idempotent_across_both_dictionaries
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 16, first.added
    assert_equal 0, first.errored

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 16, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq

    asia = db[:dictionary_entries].where(entry_id: "U+4E9C").first
    assert_equal "urn:nabu:dict:kanjidic2:U+4E9C", asia[:urn]
    love = db[:dictionary_entries].where(entry_id: "1150410").first
    assert_equal "urn:nabu:dict:jmdict:1150410", love[:urn]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["edrdg"]
    refute_nil entry, "config/sources.yml must register edrdg"
    assert_equal Nabu::Adapters::Edrdg, entry.adapter_class
    refute entry.enabled, "enabled: false until the owner-fired first sync (CLAUDE.md checklist §6)"
    assert_equal "manual", entry.sync_policy
  end
end
