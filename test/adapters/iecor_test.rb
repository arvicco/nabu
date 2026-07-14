# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The IE-CoR adapter (P18-5, docs/pie-survey.md §1): the cognacy-matrix
# dictionary shelf — one dictionary (slug iecor, language ine), one entry
# per cognate set through the cldf-csv parser family. Dictionary-shaped
# (no passage conformance suite; the wiktionary-recon precedent), plus the
# ZipFetch/sha-pin fetch choreography over the immutable Zenodo release
# artifact and the language-notes rider on the parsed document.
class IecorTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("iecor")

  def adapter(pin: nil)
    pin ? Nabu::Adapters::Iecor.new(pin: pin) : Nabu::Adapters::Iecor.new
  end

  # --- manifest + content kind ---------------------------------------------------

  def test_manifest_identifies_the_iecor_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "iecor", manifest.id
    assert_match(/CC BY 4\.0/, manifest.license)
    assert_equal "attribution", manifest.license_class
    assert_equal "cldf-csv", manifest.parser_family
    assert_match(/zenodo/, manifest.upstream_url)
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::Iecor.content_kind
  end

  def test_probe_is_http_zip_against_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Iecor.remote_probe_strategy
    targets = Nabu::Adapters::Iecor.http_probe_targets
    assert_equal 1, targets.size
    assert_equal Nabu::Adapters::Iecor::ZENODO_ZIP_URL, targets.first.zip_url
    assert_nil targets.first.metadata_url
  end

  # --- discover → parse ------------------------------------------------------------

  def test_discover_yields_one_ref_for_the_cldf_bundle
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["iecor:cldf"], refs.map(&:id)
    assert_equal %w[iecor], refs.map(&:source_id).uniq
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_iecor_dictionary_with_language_notes
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "iecor", document.slug
    assert_equal "ine", document.language
    assert_equal 5, document.size
    refute_empty document.language_notes
    assert(document.language_notes.all? { |note| note.kind == "iecor" && note.source == "iecor" })
  end

  def test_entry_ids_are_stable_across_independent_passes
    snapshot = -> { adapter.parse(adapter.discover(FIXTURES).first).map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
  end

  # --- loader round-trip: entries + reflexes + the notes rider ---------------------

  def test_loads_through_the_dictionary_loader_with_notes_accreted
    Dir.mktmpdir do |canonical_root|
      db = store_test_db
      ledger = ledger_test_db
      source = Nabu::Store::Source.create(
        slug: "iecor", name: "IE-CoR", adapter_class: "Nabu::Adapters::Iecor",
        license: "CC BY 4.0", license_class: "attribution",
        upstream_url: "https://zenodo.org", enabled: false
      )
      loader = Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger,
                                                 canonical_dir: canonical_root)
      report = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 5, report.added
      assert_equal 0, report.errored
      heart = db[:dictionary_entries].where(entry_id: "6458").first
      assert_equal "urn:nabu:dict:iecor:6458", heart[:urn]
      assert_equal "*k̑erd-", heart[:headword]
      reflexes = db[:dictionary_reflexes].where(dictionary_entry_id: heart[:id]).all
      assert_equal 12, reflexes.size, "11 witnesses, the hit stem alternant split into 2"
      # the loan-event set flags every member edge
      skin = db[:dictionary_entries].where(entry_id: "1171").first
      assert_equal [true],
                   db[:dictionary_reflexes].where(dictionary_entry_id: skin[:id]).select_map(:borrowed).uniq
      # the rider landed as dossier sections with iecor provenance (P19-1
      # redirect), and the derived records refreshed at accretion time
      shelf = Nabu::LanguageShelf.new(dir: Nabu::LanguageShelf.dir(canonical_root))
      chu = shelf.load("chu").section("iecor")
      assert_equal "iecor", chu.source
      assert_includes chu.body, "Old Church Slavonic"
      records = db[:language_records].where(kind: "iecor").all
      refute_empty records
      assert_equal ["iecor"], records.map { |r| r[:source] }.uniq
      # idempotency: a second full load appends nothing anywhere
      dossier_bytes = File.read(shelf.path_for("chu"))
      before = [db[:dictionary_entries].count, db[:dictionary_reflexes].count,
                db[:language_records].count]
      second = loader.load_from(adapter, workdir: FIXTURES)
      assert_equal 0, second.added + second.updated + second.withdrawn
      assert_equal before, [db[:dictionary_entries].count, db[:dictionary_reflexes].count,
                            db[:language_records].count]
      assert_equal dossier_bytes, File.read(shelf.path_for("chu")), "byte-identical dossier on re-load"
    end
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      tree = File.join(dir, "lexibank-iecor-test", "cldf")
      FileUtils.mkdir_p(tree)
      Dir.glob(File.join(FIXTURES, "cldf", "*.csv")).each { |csv| FileUtils.cp(csv, tree) }
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-iecor-test") }
      File.binread(zip)
    end
  end

  def stub_zenodo(body)
    stub_request(:get, Nabu::Adapters::Iecor::ZENODO_ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Mon, 12 Aug 2024 11:16:53 GMT" })
  end

  def test_fetch_pins_the_release_sha_and_unpacks_the_bundle
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      report = adapter(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert File.file?(File.join(workdir, "cldf", "cognatesets.csv")),
             "the single top-level release dir maps onto the workdir"
      refs = adapter.discover(workdir).to_a
      assert_equal ["iecor:cldf"], refs.map(&:id)
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_release_pin
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256/, error.message)
      assert_match(/#{Nabu::Adapters::Iecor::RELEASE_SHA256[0, 12]}/, error.message)
      refute File.exist?(File.join(workdir, "cldf")), "a refused fetch must leave the tree untouched"
    end
  end

  def test_fetch_wraps_http_failures_as_fetch_errors
    stub_request(:get, Nabu::Adapters::Iecor::ZENODO_ZIP_URL).to_return(status: 503)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end
end
