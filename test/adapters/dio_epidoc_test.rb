# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"

# DIO EpiDoc adapter tests: discovery over the three unpacked volume zips
# (one dir per volume), the rejected grains (the RDF serializations of the
# same articles) and text-less articles skipped by rule, the dio-epidoc
# textpart grain end to end, the dated/placed axes, the CC BY 4.0 manifest,
# and the sha256-pinned three-zip fetch. Fixtures: three whole real articles,
# one per volume, + one specimen of each rejected serialization
# (test/fixtures/dio-epidoc/README.md).
class DioEpidocTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("dio-epidoc")
  ADAPTER = Nabu::Adapters::DioEpidoc

  URNS = %w[urn:nabu:dio-epidoc:di102-083 urn:nabu:dio-epidoc:di7-001 urn:nabu:dio-epidoc:di77-246].freeze

  def conformance_adapter = ADAPTER.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "dio-epidoc"

  def parse(urn)
    adapter = ADAPTER.new
    adapter.parse(adapter.discover(FIXTURES).find { |ref| ref.id == urn })
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_and_quotes_the_per_file_licence
    manifest = ADAPTER.manifest
    assert_equal "dio-epidoc", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY 4.0 for the text"
    assert_includes manifest.license, "linked images may be published under more restricted licenses"
    assert_equal "dio-epidoc", manifest.parser_family
    assert_equal "https://epigraf.inschriften.net/pages/dumps", manifest.upstream_url
    assert_match(/The German Inscriptions \(2025\)\. Structured Data Dumps \(Version 1\.0\)/, manifest.credit)
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_article_sorted
    refs = ADAPTER.new.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    assert_equal(%w[di102 di7 di77], refs.map { |ref| ref.metadata["volume"] })
    assert(refs.all? { |ref| File.file?(ref.path) })
  end

  def test_the_rdf_serializations_are_skipped_by_rule
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule, "one TTL, one RDF/XML, one JSON-LD specimen"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.include?("RDF serialization") })
  end

  def test_a_textless_article_is_skipped_by_rule_and_an_unknown_file_is_loud
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "di7"))
      xml = File.read(File.join(FIXTURES, "di7", "article-BSS-001-nsn~3212.xml"), encoding: "utf-8")
      File.write(File.join(dir, "di7", "article-BSS-001-nsn~3212.xml"),
                 xml.sub(%r{<ab type="block">M CXLV.*?</ab>}m, "<ab type=\"block\"/>"))
      File.write(File.join(dir, "di7", "stray.xml"), "<TEI/>")
      File.write(File.join(dir, "di7", ".zip-fetch.json"), "{}")
      adapter = ADAPTER.new
      assert_empty adapter.discover(dir).to_a
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("text-less") })
      assert(skips.notes.any? { |note| note.include?("stray.xml") })
    end
  end

  def test_attic_copies_are_never_discovered
    Dir.mktmpdir do |dir|
      source = File.join(FIXTURES, "di7", "article-BSS-001-nsn~3212.xml")
      [File.join(dir, "di7"), File.join(dir, ".attic", "di7")].each do |target|
        FileUtils.mkdir_p(target)
        FileUtils.cp(source, target)
      end
      assert_equal ["urn:nabu:dio-epidoc:di7-001"], ADAPTER.new.discover(dir).map(&:id)
    end
  end

  # --- documents --------------------------------------------------------------

  def test_passages_are_the_printed_inscriptions
    document = parse("urn:nabu:dio-epidoc:di77-246")
    assert_equal "Grabplatte für Christoph Michaelis", document.title
    assert_equal %w[urn:nabu:dio-epidoc:di77-246:A1 urn:nabu:dio-epidoc:di77-246:B1 urn:nabu:dio-epidoc:di77-246:C1],
                 document.map(&:urn)
    assert_equal "160", document.to_a.last.text
    assert_equal 1, parse("urn:nabu:dio-epidoc:di7-001").count
    assert_equal 3, parse("urn:nabu:dio-epidoc:di102-083").count
  end

  def test_a_known_snippet
    passage = parse("urn:nabu:dio-epidoc:di102-083").to_a[1]
    assert_equal "her hinrick Sten vnd sinen Eruen", passage.text
    assert_equal "gml", passage.language
  end

  def test_a_dated_and_placed_specimen
    metadata = parse("urn:nabu:dio-epidoc:di77-246").metadata
    assert_equal({ "not_before" => 1575, "not_after" => 1575, "raw" => "1575" }, metadata["date"])
    assert_equal "St. Nikolai, Greifswald", metadata.dig("place", "ancient")
    assert_equal "Greifswald", metadata.dig("place", "settlement")
    assert_equal "DI 77, Nr. 246", metadata["citation"]
    assert_equal({ "di" => 77, "title" => "Greifswald (hgw)" }, metadata["volume"])
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_unpacks_each_volume_zip_into_its_own_dir
    bodies = stub_volumes
    Dir.mktmpdir do |workdir|
      adapter = ADAPTER.new(pins: bodies.transform_values { |body| Digest::SHA256.hexdigest(body) })
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal URNS, adapter.discover(workdir).map(&:id)
      assert File.file?(File.join(workdir, "di77", "article-hgw-246-mv~477.xml"))
      assert_match(/di77=\h{12} \(1 articles\)/, report.notes)
    end
  end

  def test_fetch_refuses_a_zip_that_misses_its_pin_with_the_tree_untouched
    stub_volumes
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty(Dir.children(workdir).reject { |name| name.start_with?(".") })
    end
  end

  def test_fetch_wraps_http_failure
    ADAPTER::VOLUMES.each_value { |volume| stub_request(:get, volume[:url]).to_return(status: 500) }
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(workdir) }
    end
  end

  def test_the_pins_are_the_v1_dumps
    volumes = ADAPTER::VOLUMES
    assert_equal %w[di7 di77 di102], volumes.keys
    assert_equal([73, 448, 457], volumes.values.map { |volume| volume[:articles] })
    assert_equal "d93e775d3d4b28973489d40af8a52ea6ca992b97a2ce5a8cbb981dcbe321e8fc", volumes.dig("di7", :sha256)
    assert(volumes.values.all? { |volume| volume[:url].start_with?("https://epigraf.inschriften.net/files/download/") })
  end

  def test_probe_heads_every_volume_zip
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert_equal ADAPTER::VOLUMES.values.map { |volume| volume[:url] }, ADAPTER.http_probe_targets.map(&:zip_url)
    assert_equal %w[di7 di77 di102], ADAPTER.http_probe_targets.map(&:state_subdir)
  end

  private

  # Each volume's checked-in article zipped FLAT (the upstream layout).
  def stub_volumes
    ADAPTER::VOLUMES.to_h do |name, volume|
      body = zip_of(Dir.glob(File.join(FIXTURES, name, "*.xml")))
      stub_request(:get, volume[:url]).to_return(
        status: 200, body: body,
        headers: { "Content-Type" => "application/zip", "Last-Modified" => "Sun, 18 May 2025 00:00:00 GMT" }
      )
      [name, body]
    end
  end

  def zip_of(paths)
    Dir.mktmpdir do |dir|
      paths.each { |path| FileUtils.cp(path, dir) }
      zip_path = File.join(dir, "volume.zip")
      Nabu::Shell.run("zip", "-q", zip_path, *Dir.children(dir).sort, chdir: dir)
      return File.binread(zip_path)
    end
  end
end
