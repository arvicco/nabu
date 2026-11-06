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

  private

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
