# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# Corpus Coranicum adapter tests: the Cairo 1924 text as one document per
# sura and one passage per verse (cited sura.verse), the Talmon concordance
# joined onto its words as tokens, the rejected grains (commentary,
# intertexts, manuscripts, variants) skipped by rule, the CC BY-SA 4.0
# manifest, and the pinned git fetch. Fixtures: a verbatim cut of suras 1,
# 111 and 112 from cairoquran.xml, their three whole concordance files, one
# whole specimen per rejected grain — the manuscripts and variants
# directories holding the sibling sources' fixtures — (test/fixtures/
# corpus-coranicum/README.md).
class CorpusCoranicumTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("corpus-coranicum")
  ADAPTER = Nabu::Adapters::CorpusCoranicum
  PREFIX = "urn:nabu:corpus-coranicum:"
  URNS = %w[sura-001 sura-111 sura-112].map { |stem| "#{PREFIX}#{stem}" }.freeze

  def conformance_adapter = ADAPTER.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "corpus-coranicum"

  def parse(urn, workdir: FIXTURES)
    adapter = ADAPTER.new
    adapter.parse(adapter.discover(workdir).find { |ref| ref.id == urn })
  end

  def passage(document, tail) = document.find { |p| p.urn == "#{document.urn}:#{tail}" }

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_and_quotes_the_readme_licence
    manifest = ADAPTER.manifest
    assert_equal "corpus-coranicum", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "© Berlin-Brandenburgische Akademie der Wissenschaften 2024"
    assert_includes manifest.license, "Creative Commons CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0/"
    assert_equal "corpus-coranicum-tei", manifest.parser_family
    assert_equal "https://github.com/telota/corpus-coranicum-tei", manifest.upstream_url
    assert_includes manifest.credit, "Corpus Coranicum Project, ed. Michael Marx"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_sura_of_the_cairo_text
    refs = ADAPTER.new.discover(FIXTURES).to_a
    assert_equal URNS, refs.map(&:id)
    assert_equal([1, 111, 112], refs.map { |ref| ref.metadata["sura"] })
    cairo = File.join(File.expand_path(FIXTURES), "data", "cairo_quran", "cairoquran.xml")
    assert(refs.all? { |ref| ref.path == cairo })
  end

  def test_discover_is_empty_without_the_cairo_file
    Dir.mktmpdir { |dir| assert_empty ADAPTER.new.discover(dir).to_a }
  end

  def test_the_rejected_grains_are_skipped_by_rule
    skips = ADAPTER.new.discovery_skips(FIXTURES)
    # One specimen each of commentary and intertexts; the manuscripts and
    # variants directories carry the sibling sources' fixtures (four records
    # + places.xml; the three variants files), still none of this source's.
    assert_equal 10, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    { "quran_commentary" => "1 file ", "quran_intertexts" => "1 file ", "quran_manuscripts" => "5 files",
      "quran_variants" => "3 files" }.each do |dir, count|
      assert(skips.notes.any? { |note| note.start_with?("data/#{dir}/: #{count}") }, "a note for #{dir}")
    end
    assert(skips.notes.any? { |note| note.include?("corpus-coranicum-manuscripts source") })
  end

  def test_a_stray_file_and_an_orphan_concordance_file_are_loud
    with_fixture_copy do |dir|
      File.write(File.join(dir, "data", "stray.xml"), "<TEI/>")
      FileUtils.cp(File.join(dir, "data", "quran_concordance", "sura112.xml"),
                   File.join(dir, "data", "quran_concordance", "sura113.xml"))
      FileUtils.mkdir_p(File.join(dir, ".attic", "data"))
      File.write(File.join(dir, ".attic", "data", "old.xml"), "<TEI/>")
      skips = ADAPTER.new.discovery_skips(dir)
      assert_equal 2, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("data/stray.xml") })
      assert(skips.notes.any? { |note| note.include?("sura113.xml") && note.include?("no sura 113") })
    end
  end

  # --- documents --------------------------------------------------------------

  def test_one_passage_per_verse_cited_sura_dot_verse
    document = parse("#{PREFIX}sura-112")
    assert_equal %w[112.1 112.2 112.3 112.4].map { |tail| "#{PREFIX}sura-112:#{tail}" }, document.map(&:urn)
    assert_equal "Qurʾān — Sura 112", document.title
    assert_equal "ara", document.language
    assert_equal 7, parse("#{PREFIX}sura-001").count
    assert_equal 5, parse("#{PREFIX}sura-111").count
  end

  def test_a_known_verse
    verse = passage(parse("#{PREFIX}sura-112"), "112.1")
    assert_equal "قُلۡ هُوَ ٱللَّهُ أَحَدٌ", verse.text
    assert_equal "ara", verse.language
    assert_equal "826", verse.annotations["page"]
  end

  def test_the_document_names_the_work_and_the_edition
    metadata = parse("#{PREFIX}sura-001").metadata
    assert_equal "Qurʾān", metadata["work"], "the work_eras key"
    assert_equal 1, metadata["sura"]
    assert_equal 1924, metadata["edition_year"]
    assert_equal 29, metadata["words"]
    assert_match(/Ḥafṣ/, metadata["edition"])
  end

  def test_the_work_is_banded_by_the_ruled_era_table
    era = Nabu::WorkEras.default.lookup("corpus-coranicum", "Qurʾān")
    assert_equal [610, 632], era.band
  end

  # --- the concordance as tokens ----------------------------------------------

  def test_every_word_carries_its_concordance_analysis
    verse = passage(parse("#{PREFIX}sura-112"), "112.1")
    tokens = verse.annotations["tokens"]
    assert_equal(%w[w-112-001-001 w-112-001-002 w-112-001-003 w-112-001-004], tokens.map { |t| t["id"] })
    qul = tokens.first
    assert_equal "قُلۡ", qul["form"]
    assert_equal "qul", qul["translit"]
    assert_equal "qul", qul["lemma"]
    assert_equal "qwl", qul["root"]
    assert_equal "Verb", qul["pos"]
    assert_equal "Imperative", qul["aspect"]
    assert_equal "2P", qul["person"]
    assert_equal "Stem1", qul["pattern"]
    assert_equal "qwl", qul["root_rafi_talmon"]
    assert_equal "qwl+Verb+Stem1+Imperative+2P+Sg+Masc+NonEnergicus", qul["full_analyse"]
    %w[sura verse word_number created_at updated_at mood].each { |key| refute qul.key?(key), key }
  end

  def test_a_known_root_in_the_basmala
    rahman = passage(parse("#{PREFIX}sura-001"), "1.1").annotations["tokens"][2]
    assert_equal "rḥm", rahman["root"]
    assert_equal "rHm", rahman["root_rafi_talmon"]
    assert_equal "raḥmān", rahman["lemma"]
    assert_equal "fa&laan", rahman["pattern"]
    assert_equal "Noun", rahman["pos"]
  end

  def test_further_analyses_ride_as_alternatives
    rabbi = passage(parse("#{PREFIX}sura-001"), "1.2").annotations["tokens"][2]
    assert_equal "1", rabbi["analysis"]
    alternatives = rabbi.fetch("alternatives")
    assert_equal 1, alternatives.size
    assert_equal "2", alternatives.first["analysis"]
    assert_equal "rbb", alternatives.first["root"]
    refute alternatives.first.key?("form"), "the word's form rides the token once"
  end

  def test_a_word_without_a_concordance_row_is_a_parse_error
    with_fixture_copy do |dir|
      path = File.join(dir, "data", "quran_concordance", "sura112.xml")
      xml = File.read(path, encoding: "utf-8")
      row = %r{<w>\s*<seg type="sura">112</seg>\s*<seg type="verse">4</seg>\s*<seg type="word_number">5</seg>.*?</w>}m
      File.write(path, xml.sub(row, ""))
      error = assert_raises(Nabu::ParseError) { parse("#{PREFIX}sura-112", workdir: dir) }
      assert_includes error.message, "w-112-004-005"
    end
  end

  def test_a_missing_concordance_file_is_a_parse_error
    with_fixture_copy do |dir|
      FileUtils.rm(File.join(dir, "data", "quran_concordance", "sura112.xml"))
      error = assert_raises(Nabu::ParseError) { parse("#{PREFIX}sura-112", workdir: dir) }
      assert_includes error.message, "sura112.xml"
    end
  end

  def test_a_concordance_row_without_a_cairo_word_is_a_parse_error
    with_fixture_copy do |dir|
      path = File.join(dir, "data", "quran_concordance", "sura112.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.sub('<seg type="word_number">5</seg>', '<seg type="word_number">6</seg>'))
      error = assert_raises(Nabu::ParseError) { parse("#{PREFIX}sura-112", workdir: dir) }
      assert_includes error.message, "112:4:6"
    end
  end

  # NFC at the adapter boundary: 7 of upstream's 77,432 words are not NFC
  # (six write shadda before its vowel). The bytes of w-011-080-003 (أَنَّ,
  # written alef-hamza fatha nun SHADDA FATHA) stand in for one fixture word.
  def test_the_text_and_forms_are_nfc_normalized
    raw = [0x0623, 0x064E, 0x0646, 0x0651, 0x064E].pack("U*")
    refute_equal raw, raw.unicode_normalize(:nfc), "the upstream bytes are not NFC"
    with_fixture_copy do |dir|
      path = File.join(dir, "data", "cairo_quran", "cairoquran.xml")
      xml = File.read(path, encoding: "utf-8")
      File.write(path, xml.sub('<w xml:id="w-112-001-002">هُوَ</w>', "<w xml:id=\"w-112-001-002\">#{raw}</w>"))
      verse = passage(parse("#{PREFIX}sura-112", workdir: dir), "112.1")
      assert_equal raw.unicode_normalize(:nfc), verse.annotations["tokens"][1]["form"]
      assert_includes verse.text, raw.unicode_normalize(:nfc)
    end
  end

  def test_the_translations_and_the_transcription_are_not_carried
    document = parse("#{PREFIX}sura-001")
    refute(document.any? { |p| p.text.match?(/[A-Za-z]/) }, "the Arabic text only")
    refute(document.any? { |p| p.annotations.key?("translation") })
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_accepts_the_pinned_commit
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        workdir = File.join(root, "work")
        report = ADAPTER.new(repo_url: repo_url, pinned_sha: sha).fetch(workdir)
        assert_equal sha, report.sha
        assert File.file?(File.join(workdir, "data", "cairo_quran", "cairoquran.xml"))
      end
    end
  end

  def test_fetch_stops_loudly_when_upstream_drifts_from_the_pin
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        adapter = ADAPTER.new(repo_url: repo_url, pinned_sha: "0" * 40)
        error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
        assert_includes error.message, sha[0, 12]
        assert_includes error.message, "pin"
      end
    end
  end

  def test_the_pin_is_the_frozen_upstream_commit
    assert_equal "57cb2b7be321ecfba100cb5f7988974f47864a14", ADAPTER::PINNED_SHA
  end

  private

  def with_fixture_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "data"), dir)
      yield dir
    end
  end

  def with_local_upstream
    with_fixture_copy do |upstream|
      Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=main")
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "tei")
      yield upstream, Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
    end
  end
end
