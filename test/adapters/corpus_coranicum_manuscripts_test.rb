# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "tmpdir"

# Corpus Coranicum manuscripts adapter tests: one document per transcribed
# manuscript record of the shared corpus-coranicum clone, one passage per
# verse cited sura.verse, the metadata-only records skipped by rule, the axes
# mined from the msDesc (copying date, provenance — never the holding
# library — script style, material), and the network-free fetch that pins the
# clone. The fixtures are the corpus-coranicum fixture tree itself (the clone's
# own layout): three whole transcribed records, the metadata-only
# manuscript-02504 and the places.xml trim
# (test/fixtures/corpus-coranicum/README.md).
class CorpusCoranicumManuscriptsTest < Minitest::Test
  include AdapterConformance

  CLONE = Nabu::TestSupport.fixtures("corpus-coranicum")
  ADAPTER = Nabu::Adapters::CorpusCoranicumManuscripts
  PREFIX = "urn:nabu:corpus-coranicum-manuscripts:"
  RECORDS = %w[manuscript-00017 manuscript-00504 manuscript-01362].freeze

  def conformance_adapter = ADAPTER.new(clone_dir: CLONE)
  def conformance_workdir = CLONE
  def conformance_expected_source_id = "corpus-coranicum-manuscripts"

  def parse(record, clone: CLONE)
    adapter = ADAPTER.new(clone_dir: clone)
    adapter.parse(adapter.discover(clone).find { |ref| ref.id == "#{PREFIX}#{record}" })
  end

  def passage(document, tail) = document.find { |p| p.urn == "#{document.urn}:#{tail}" }

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_and_names_the_image_rights
    manifest = ADAPTER.manifest
    assert_equal "corpus-coranicum-manuscripts", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "Creative Commons CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/"
    assert_includes manifest.license, "images are not carried"
    assert_equal "corpus-coranicum-tei", manifest.parser_family
    assert_equal "https://github.com/telota/corpus-coranicum-tei", manifest.upstream_url
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_transcribed_record_of_the_clone
    refs = ADAPTER.new(clone_dir: CLONE).discover("ignored").to_a
    assert_equal(RECORDS.map { |record| "#{PREFIX}#{record}" }, refs.map(&:id))
    assert_equal File.join(File.expand_path(CLONE), "data", "quran_manuscripts", "manuscript-00017.xml"),
                 refs.first.path
  end

  def test_the_clone_is_read_beside_the_workdir_by_default
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "corpus-coranicum"), File.join(root, "corpus-coranicum-manuscripts")])
      FileUtils.cp_r(File.join(CLONE, "data"), File.join(root, "corpus-coranicum"))
      refs = ADAPTER.new.discover(File.join(root, "corpus-coranicum-manuscripts")).to_a
      assert_equal 3, refs.size
      clone = File.join(root, "corpus-coranicum", "data")
      assert(refs.all? { |ref| ref.path.start_with?(clone) }, "the refs point into the sibling clone")
    end
  end

  def test_discover_is_empty_without_the_clone
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new(clone_dir: dir).discover(dir).to_a }
  end

  def test_the_metadata_only_records_are_skipped_by_rule
    skips = ADAPTER.new(clone_dir: CLONE).discovery_skips("ignored")
    assert_equal 1, skips.skipped_by_rule, "manuscript-02504 (Rotterdam 96D17) carries no transcription"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.start_with?("data/quran_manuscripts/: 1 manuscript record without") })
  end

  def test_a_stray_file_in_the_directory_is_unrecognized
    with_clone_copy do |clone|
      File.write(File.join(clone, "data", "quran_manuscripts", "stray.xml"), "<TEI/>")
      skips = ADAPTER.new(clone_dir: clone).discovery_skips("ignored")
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("data/quran_manuscripts/stray.xml") })
    end
  end

  # --- documents --------------------------------------------------------------

  def test_one_passage_per_verse_cited_sura_dot_verse_in_manuscript_order
    document = parse("manuscript-00017")
    assert_equal 17, document.count
    assert_equal "#{PREFIX}manuscript-00017:97.4", document.first.urn
    assert_equal "Qurʾān — Chicago, Institute for the Study of Ancient Cultures, A 6990", document.title
    assert_equal "ara", document.language
    assert_equal 12, parse("manuscript-00504").count
    assert_equal 27, parse("manuscript-01362").count
  end

  def test_a_known_verse_with_its_leiden_layers
    verse = passage(parse("manuscript-00017"), "97.4")
    assert_equal "لٮله الٯدر حٮر مں الڡ سهر", verse.text
    assert_equal "[…]در […]", verse.annotations["extant"]
    assert_equal({ "supplied_chars" => 18, "unclear_chars" => 2 }, verse.annotations["leiden"])
    assert_equal ["۝٣"], verse.annotations["markers"]
    assert_equal ["1r.1"], verse.annotations["lines"]
    assert_equal({ "id" => "097-004-001", "form" => "لٮله", "extant" => "[…]", "supplied_chars" => 4 },
                 verse.annotations["tokens"].first)
  end

  def test_a_sura_heading_is_verse_zero
    heading = passage(parse("manuscript-00504"), "49.0")
    assert_equal "ٮسم ال‍له الرحمں الرحٮم", heading.text
    assert heading.annotations["heading"]
    assert_equal ["۝٠"], heading.annotations["markers"]
  end

  def test_deletions_render_in_double_brackets
    verse = passage(parse("manuscript-01362"), "38.79")
    assert verse.text.start_with?("⟦و⟧")
    assert verse.annotations["leiden"]["cancelled"]
    assert verse.annotations["tokens"].first["cancelled"]
  end

  # Real bytes (manuscript-00504, Q 48:27): the archaic dotless qāf ٯ U+066F
  # and dotless bāʾ ٮ U+066E survive the NFC boundary unchanged.
  def test_the_rasm_survives_nfc_byte_for_byte
    text = passage(parse("manuscript-00504"), "48.27").text
    assert text.start_with?("لٯد صدٯ ")
    assert_equal text, text.unicode_normalize(:nfc)
  end

  # --- axes -------------------------------------------------------------------

  def test_the_copying_date_the_provenance_and_the_repository
    metadata = parse("manuscript-00017").metadata
    assert_equal({ "not_before" => 650, "not_after" => 750, "raw" => "650-750" }, metadata["date"])
    assert_equal "al-Fusṭāṭ", metadata["place"]
    assert_equal "al-Fusṭāṭ", metadata["provenance"]
    assert_equal "Institute for the Study of Ancient Cultures", metadata["repository"]
    assert_equal "Chicago", metadata["repository_place"]
    assert_equal "US", metadata["repository_country"]
    assert_equal "4914512", metadata["repository_geonames"]
    assert_equal "kūfī B.Ia", metadata["script"]
    assert_equal "parchment", metadata["material"]
    assert_equal "A 6990", metadata["shelfmark"]
    assert_equal({ "width" => 120, "height" => 350, "unit" => "mm" }, metadata["dimensions"])
    assert_equal 6, metadata["lines_per_page"]
    assert_equal 1, metadata["folios"]
    assert_equal "Qurʾān", metadata["work"]
  end

  def test_before_750_is_an_open_start_date_and_the_library_is_never_the_place
    metadata = parse("manuscript-00504").metadata
    assert_equal({ "not_before" => nil, "not_after" => 750, "raw" => "-750" }, metadata["date"])
    assert_equal "ḥiǧāzī", metadata["script"]
    refute metadata.key?("place"), "no provenance recorded — Paris is where it is kept, not where it was made"
    assert_equal "Paris", metadata["repository_place"]
  end

  def test_the_counts_ride_the_metadata
    metadata = parse("manuscript-01362").metadata
    assert_equal 26, metadata["verses"]
    assert_equal 1, metadata["headings"]
    assert_equal 259, metadata["words"]
    assert_equal ["Image credits: Qatar National Library, Heritage Library."], metadata["image_credits"]
  end

  def test_a_record_whose_transcription_keys_no_verse_is_a_parse_error
    with_clone_copy do |clone|
      path = File.join(clone, "data", "quran_manuscripts", "manuscript-00017.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.gsub(/<w n="\d{3}-\d{3}-\d{3}"/, '<w n="000-000-000"'))
      error = assert_raises(Nabu::ParseError) { parse("manuscript-00017", clone: clone) }
      assert_includes error.message, "keys no verse"
    end
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_verifies_the_pinned_clone_and_records_the_pin
    with_git_clone do |root, sha|
      workdir = File.join(root, "corpus-coranicum-manuscripts")
      report = ADAPTER.new(pinned_sha: sha).fetch(workdir)
      assert_equal sha, report.sha
      pin = JSON.parse(File.read(File.join(workdir, "corpus-coranicum.pin.json")))
      assert_equal({ "source" => "corpus-coranicum", "sha" => sha }, pin)
      assert_equal ["corpus-coranicum.pin.json"], ADAPTER.materialized_paths
    end
  end

  def test_fetch_stops_loudly_on_a_clone_off_the_pin
    with_git_clone do |root, sha|
      error = assert_raises(Nabu::FetchError) do
        ADAPTER.new(pinned_sha: "0" * 40).fetch(File.join(root, "corpus-coranicum-manuscripts"))
      end
      assert_includes error.message, sha[0, 12]
      refute File.exist?(File.join(root, "corpus-coranicum-manuscripts", "corpus-coranicum.pin.json"))
    end
  end

  def test_fetch_without_the_clone_names_the_source_to_sync_first
    Dir.mktmpdir do |root|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(File.join(root, "corpus-coranicum-manuscripts")) }
      assert_includes error.message, "sync corpus-coranicum first"
    end
  end

  def test_registered_unwired_requiring_the_clone_source
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["corpus-coranicum-manuscripts"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired only after the verified first sync"
    assert_equal ["corpus-coranicum"], entry.requires
    assert_equal ADAPTER.manifest, entry.manifest
  end

  def test_the_pin_is_the_corpus_coranicum_pin
    assert_equal Nabu::Adapters::CorpusCoranicum::PINNED_SHA, ADAPTER.new.instance_variable_get(:@pinned_sha)
  end

  private

  def with_clone_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(CLONE, "data"), dir)
      yield dir
    end
  end

  def with_git_clone
    Dir.mktmpdir do |root|
      clone = File.join(root, "corpus-coranicum")
      FileUtils.mkdir_p(clone)
      FileUtils.cp_r(File.join(CLONE, "data"), clone)
      Nabu::Shell.run("git", "-C", clone, "init", "--quiet", "--initial-branch=main")
      Nabu::Shell.run("git", "-C", clone, "add", ".")
      Nabu::Shell.run("git", "-C", clone, "-c", "user.email=t@e.st", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "tei")
      yield root, Nabu::Shell.run("git", "-C", clone, "rev-parse", "HEAD").strip
    end
  end
end
