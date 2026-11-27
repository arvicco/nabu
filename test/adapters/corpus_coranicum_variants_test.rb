# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# Corpus Coranicum variant-readings adapter tests: one document per reader of
# the shared corpus-coranicum clone, one passage per verse the reader has
# readings in (cited sura.verse, the words keyed in the tokens), the unused
# source authority skipped by rule, the reader's death and residence as the
# axes, and the join of the word keys onto the held Cairo words. Fixtures:
# the corpus-coranicum fixture tree (the allvariants.xml trim to suras 111
# and 112 plus three specimens, reader.xml trimmed to the readers they cite,
# sources.xml whole; test/fixtures/corpus-coranicum/README.md).
class CorpusCoranicumVariantsTest < Minitest::Test
  include AdapterConformance

  CLONE = Nabu::TestSupport.fixtures("corpus-coranicum")
  ADAPTER = Nabu::Adapters::CorpusCoranicumVariants
  PREFIX = "urn:nabu:corpus-coranicum-variants:"

  def conformance_adapter = ADAPTER.new(clone_dir: CLONE)
  def conformance_workdir = CLONE
  def conformance_expected_source_id = "corpus-coranicum-variants"

  def refs(clone: CLONE) = ADAPTER.new(clone_dir: clone).discover("ignored").to_a

  def parse(stem, clone: CLONE)
    adapter = ADAPTER.new(clone_dir: clone)
    adapter.parse(adapter.discover("ignored").find { |ref| ref.id == "#{PREFIX}#{stem}" })
  end

  def passage(document, tail) = document.find { |p| p.urn == "#{document.urn}:#{tail}" }

  def test_manifest_is_attribution_from_the_readme
    manifest = ADAPTER.manifest
    assert_equal "corpus-coranicum-variants", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "© Berlin-Brandenburgische Akademie der Wissenschaften 2024"
    assert_equal "corpus-coranicum-tei", manifest.parser_family
    assert_includes manifest.credit, "Michael Marx"
  end

  # --- discover ---------------------------------------------------------------

  def test_one_ref_per_reader_in_authority_order_then_the_unattributed
    ids = refs.map(&:id)
    assert_equal 73, ids.size
    assert_equal "#{PREFIX}reader-1", ids.first
    assert_equal "#{PREFIX}unattributed", ids.last
    assert_equal ids.sort_by { |id| id[/reader-(\d+)/, 1].to_i.nonzero? || Float::INFINITY }, ids
    refute_includes ids, "#{PREFIX}reader-444", "reader 444 is cited only by an empty item"
  end

  def test_the_unused_source_authority_is_skipped_by_rule
    skips = ADAPTER.new(clone_dir: CLONE).discovery_skips("ignored")
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |note| note.start_with?("data/quran_variants/sources.xml: skipped by rule") })
  end

  def test_a_stray_file_is_unrecognized_and_no_clone_means_no_refs
    with_clone_copy do |clone|
      File.write(File.join(clone, "data", "quran_variants", "extra.xml"), "<TEI/>")
      assert_equal 1, ADAPTER.new(clone_dir: clone).discovery_skips("ignored").unrecognized
    end
    Dir.mktmpdir { |dir| assert_empty refs(clone: dir) }
  end

  # --- documents --------------------------------------------------------------

  def test_a_readers_document_one_passage_per_verse
    document = parse("reader-40")
    assert_equal "Qurʾān — the readings of Ibn Kaṯīr", document.title
    assert_equal "ara-Latn", document.language
    assert_equal(%w[111.1 111.4 112.1 112.2 112.4].map { |tail| "#{PREFIX}reader-40:#{tail}" }, document.map(&:urn))
    verse = passage(document, "111.1")
    assert_equal "lahbin; yadā ʾabī lahbin; yadā ʾabī lahbin", verse.text
    assert_equal({ "id" => "111:001:002", "form" => "yadā", "reading" => "variant_1702" },
                 verse.annotations["tokens"][1])
    assert_equal [{ "id" => "variant_1347", "with" => %w[reader-19 reader-44 reader-228] },
                  { "id" => "variant_1702" }, { "id" => "variant_1977" }], verse.annotations["readings"]
  end

  def test_the_reader_is_the_creator_dated_by_his_death_placed_by_his_city
    metadata = parse("reader-1").metadata
    assert_equal "ʿĀṣim", metadata["author"]
    assert_equal "1", metadata["reader"]
    assert_equal "0500", metadata["sigle"]
    assert_equal({ "not_before" => nil, "not_after" => 745, "raw" => "st. ca. 127 (744-5)", "class" => "composition" },
                 metadata["date"])
    assert_equal "Kufa", metadata["place"]
    assert_match(/al-Kūfī/, metadata["reader_full_name"])
    assert_equal "Qurʾān", metadata["work"]
  end

  def test_a_reader_without_a_death_or_a_residence_claims_neither
    metadata = parse("reader-29").metadata
    refute metadata.key?("date")
    refute metadata.key?("place")
  end

  def test_upstreams_non_places_place_nothing
    with_clone_copy do |clone|
      path = File.join(clone, "data", "quran_variants", "reader.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.sub("<residence>Kufa</residence>", "<residence>unbekannt</residence>"))
      metadata = parse("reader-1", clone: clone).metadata
      assert_equal "unbekannt", metadata["residence"]
      refute metadata.key?("place")
    end
  end

  def test_the_readings_ascribed_to_no_reader
    document = parse("unattributed")
    assert_equal ["#{PREFIX}unattributed:3.81"], document.map(&:urn)
    assert_equal "ʾuṣrī", document.first.text
    refute document.metadata.key?("author")
  end

  # Upstream's reader 328 is its own test record (main name "test", no display
  # name): an ascription to it names nobody, so the reading is unattributed.
  def test_an_ascription_to_upstreams_test_record_names_nobody
    with_clone_copy do |clone|
      path = File.join(clone, "data", "quran_variants", "reader.xml")
      xml = File.read(path, encoding: "utf-8")
      names = Regexp.new('(<person xml:id="variantsreader_29">\s*)<name type="main">[^<]*</name>' \
                         '\s*<name type="display">[^<]*</name>')
      File.write(path, xml.sub(names, '\1<name type="main">test</name><name type="display"/>'))
      ids = refs(clone: clone).map(&:id)
      refute_includes ids, "#{PREFIX}reader-29"
      readings = parse("reader-20", clone: clone).flat_map { |p| p.annotations["readings"] }
      refute(readings.any? { |reading| Array(reading["with"]).include?("reader-29") }, "never a co-reader either")
      assert_equal 1, parse("unattributed", clone: clone).count, "its reading keeps its four real readers"
    end
  end

  def test_a_reader_without_a_display_name_is_named_by_the_main_name
    with_clone_copy do |clone|
      path = File.join(clone, "data", "quran_variants", "reader.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.sub('<name type="display">Abū as-Sammāl</name>', '<name type="display"/>'))
      document = parse("reader-29", clone: clone)
      assert_equal "Abū as-Sammāl, Qaʿnab b. Abī Qaʿnab al-ʿAdawī al-Baṣrī", document.metadata["author"]
    end
  end

  def test_a_reader_missing_from_the_authority_is_a_parse_error
    with_clone_copy do |clone|
      path = File.join(clone, "data", "quran_variants", "allvariants.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.sub('key="variantreader_40"', 'key="variantreader_99999"'))
      error = assert_raises(Nabu::ParseError) { refs(clone: clone) }
      assert_includes error.message, "99999"
    end
  end

  # The join census both ways on the fixture: every word key of the trim's
  # suras 111/112 names a word of the held Cairo text except upstream's
  # 111:003:006 (ktasaba — past the four words of Q 111:3).
  def test_the_word_keys_join_the_cairo_words
    path = File.join(CLONE, "data", "cairo_quran", "cairoquran.xml")
    words = Nabu::Adapters::CorpusCoranicumCairoParser.new.suras(path).flat_map do |sura, verses|
      verses.flat_map { |v| v.words.map { |w| [sura, v.number, w.number].map { |n| n.to_s.rjust(3, "0") }.join(":") } }
    end
    adapter = ADAPTER.new(clone_dir: CLONE)
    keys = refs.flat_map { |ref| adapter.parse(ref).flat_map { |p| p.annotations["tokens"].map { |t| t["id"] } } }
    keys = keys.uniq.select { |key| key.start_with?("111:", "112:") }
    assert_equal ["111:003:006"], keys - words
  end

  def test_registered_unwired_requiring_the_clone_source
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["corpus-coranicum-variants"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired only after the verified first sync"
    assert_equal ["corpus-coranicum"], entry.requires
  end

  def test_fetch_is_the_shared_clone_check
    Dir.mktmpdir do |root|
      error = assert_raises(Nabu::FetchError) { ADAPTER.new.fetch(File.join(root, "corpus-coranicum-variants")) }
      assert_includes error.message, "corpus-coranicum-variants"
    end
    assert_equal ["corpus-coranicum.pin.json"], ADAPTER.materialized_paths
  end

  private

  def with_clone_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(CLONE, "data"), dir)
      yield dir
    end
  end
end
