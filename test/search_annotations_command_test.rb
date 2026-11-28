# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu search --annotations QUERY`: search the declared annotation
# layers (Store::AnnotationIndex — cantus' standardized spellings,
# korpus16's marginal notes). An on-disk catalog loaded from the real
# fixtures, the reference index rebuild over it, then the rendered output.
# The desk law from both sides: hits come from the precompiled lane, and
# an absent lane is an honest hint, never a scan.
class SearchAnnotationsCommandTest < Minitest::Test
  PRESUL = "urn:nabu:cantus:455843:1"

  def test_a_standardized_spelling_finds_the_manuscript_passage
    with_annotation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --annotations praesul]) }
      assert_nil status
      assert_match(/^#{Regexp.escape(PRESUL)} \[lat\]/, out, "the hit names the passage itself")
      assert_match(/  standardized: .*\[praesul\]/, out)
      assert_match(/  text: .*presul/, out, "the manuscript's own spelling rides under the layer")
      assert_match(/1 hit in declared annotation layers/, out)
      assert_match(/nabu show <urn>/, out)
      assert_match(/annotations index covers: cantus \d+ · korpus16 1/, out)
    end
  end

  def test_margin_notes_name_their_layer
    with_annotation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --annotations prasnik]) }
      assert_nil status
      assert_match(/^urn:nabu:korpus16:58:200 \[sl\]/, out)
      assert_match(/  notes: Sobbota ali \[prasnik\]/, out)
    end
  end

  def test_source_and_lang_filters_compose
    with_annotation_corpus do |config|
      out, = with_config(config) { run_cli(%w[search --annotations praesul --source korpus16]) }
      assert_match(/no matches/, out)
      assert_match(/annotations index covers:/, out, "a miss still names the lane's scope")

      out, = with_config(config) { run_cli(%w[search --annotations prasnik --lang sl]) }
      assert_match(/\[sl\]/, out)
    end
  end

  def test_annotations_refuses_modes_it_does_not_compose_with
    with_annotation_corpus do |config|
      %w[--fuzzy --exact --word --withdrawn --translations].each do |flag|
        _out, err, status = with_config(config) { run_cli(["search", "--annotations", "praesul", flag]) }
        assert_equal 1, status, flag
        assert_match(%r{--(annotations|translations) .* composes with --lang/--source/--axis/--license/--limit only},
                     err, flag)
      end
    end
  end

  def test_annotations_needs_a_query
    with_annotation_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --annotations]) }
      assert_equal 1, status
      assert_match(/--annotations needs a query/, err)
    end
  end

  def test_an_absent_lane_is_an_honest_hint
    with_annotation_corpus(lane: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --annotations praesul]) }
      assert_equal 1, status
      assert_match(/no annotations index .* rake index:annotations/, err)
    end
  end

  # The layer line's direction is the LAYER's script, never the passage's:
  # Kül Tigin G1's Latin transcription (tr-wikisource, real fixture bytes)
  # under its runiform otk passage renders without an RTL isolate, while
  # the passage text line keeps one; an Arabic-script layer under a Latin
  # passage gets the isolate it needs. The translations lane alike.
  RUNIFORM = "𐱅𐰭𐰼𐰃: 𐱅𐰏: 𐱅𐰭𐰼𐰃𐰓𐰀: 𐰉𐰆𐰞𐰢𐱁:"
  ARABIC = "أيا أخوينا عبد شمس ونوفلا"
  RLI = Nabu::Display::RLI

  def test_a_layer_line_takes_its_direction_from_its_own_script
    latin = annotation_result(language: "otk", layer: "transcription", snippet: "[TeŊRİ]: TeG: TeŊRİDE:",
                              text: RUNIFORM)
    arabic = annotation_result(language: "lat", layer: "notes", snippet: ARABIC, text: "praesul")
    out, = capture_io { Nabu::CLI.new.send(:print_annotation_results, [latin, arabic], scope: {}) }
    lines = out.lines
    assert_equal "  transcription: [TeŊRİ]: TeG: TeŊRİDE:\n", lines[1], "a Latin layer is never isolated"
    assert lines[2].start_with?("  text: #{RLI}"), "the runiform passage text keeps its isolate"
    assert_equal "  notes: #{RLI}#{ARABIC}#{Nabu::Display::PDI}\n", lines[4], "an Arabic layer is isolated"
    assert_equal "  text: praesul\n", lines[5]
  end

  def test_a_translation_line_takes_its_direction_from_its_own_script
    turkish = Nabu::Query::TranslationSearch::Result.new(
      urn: "urn:nabu:tr-wikisource:x:G1", language: "otk", text: RUNIFORM, layer: "translation",
      snippet: "Tanrı gibi gökte olmuş", document_title: nil, license_class: "attribution", credit: nil
    )
    arabic = turkish.with(urn: "urn:nabu:x:2", language: "lat", text: "praesul", snippet: ARABIC)
    out, = capture_io { Nabu::CLI.new.send(:print_translation_results, [turkish, arabic], scope: {}) }
    lines = out.lines
    assert_equal "  translation: Tanrı gibi gökte olmuş\n", lines[1]
    assert lines[2].start_with?("  original: #{RLI}")
    assert_equal "  translation: #{RLI}#{ARABIC}#{Nabu::Display::PDI}\n", lines[4],
                 "an RTL translation gets its isolate even though the lane renders it language-less"
  end

  private

  def annotation_result(language:, layer:, snippet:, text:)
    Nabu::Query::AnnotationSearch::Result.new(urn: "urn:nabu:x:#{layer}", language: language, text: text,
                                              layer: layer, snippet: snippet, document_title: nil,
                                              license_class: "attribution", credit: nil)
  end

  def with_annotation_corpus(lane: true)
    Dir.mktmpdir("nabu-annotations-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      Nabu::TestSupport.load_annotation_corpus(catalog)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      unless lane
        fulltext.drop_table(Nabu::Store::AnnotationIndex::TABLE)
        fulltext.drop_table(Nabu::Store::AnnotationIndex::SCOPE_TABLE)
      end
      fulltext.disconnect
      catalog.disconnect
      yield config
    end
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
