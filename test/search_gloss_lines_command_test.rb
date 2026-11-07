# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu search --gloss-lines QUERY`: content search over the passages'
# upstream token glosses (Store::GlossLineIndex — bhsa/achemenet English,
# aes/tlhdig German). An on-disk catalog loaded from the real fixtures,
# the reference index rebuild over it, then the rendered output. The desk
# law from both sides: hits come from the precompiled lane, and an absent
# lane is an honest hint, never a scan.
class SearchGlossLinesCommandTest < Minitest::Test
  DAN_2_4 = "urn:nabu:bhsa:dan:2.4"

  def test_a_gloss_query_finds_the_passage_and_names_the_word
    with_gloss_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["search", "--gloss-lines", "king eternity"]) }
      assert_nil status
      assert_match(/^#{Regexp.escape(DAN_2_4)} \[arc\] bhsa/, out, "the hit names the passage itself")
      assert_match(/  glosses: .*\[king\]/, out)
      assert_match(/  words: \S+ ‘king’/, out, "the matching token with its upstream gloss")
      assert_match(/‘eternity’/, out)
      assert_match(/  text: /, out)
      assert_match(/1 hit in token gloss lines/, out)
      assert_match(/nabu show <urn>/, out)
      assert_match(/gloss-lines index covers: achemenet 5 · aes \d+ · bhsa \d+ · ceipom 0 · tlhdig \d+/, out)
    end
  end

  def test_german_glosses_answer_an_accentless_query
    with_gloss_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --gloss-lines konig --source tlhdig]) }
      assert_nil status
      assert_match(/^urn:nabu:tlhdig:\S+ \[hit\] tlhdig/, out)
      assert_match(/‘König’/, out)
    end
  end

  def test_source_and_lang_filters_compose
    with_gloss_corpus do |config|
      out, = with_config(config) { run_cli(%w[search --gloss-lines eternity --source achemenet]) }
      assert_match(/no matches/, out)
      assert_match(/gloss-lines index covers:/, out, "a miss still names the lane's scope")

      out, = with_config(config) { run_cli(%w[search --gloss-lines king --lang akk]) }
      assert_match(/\[akk\] achemenet/, out)
      refute_match(/\[arc\]/, out)
    end
  end

  def test_gloss_lines_refuses_modes_it_does_not_compose_with
    with_gloss_corpus do |config|
      [%w[--fuzzy], %w[--exact], %w[--translations], %w[--annotations], %w[--gloss king]].each do |flags|
        _out, err, status = with_config(config) { run_cli(["search", "--gloss-lines", "king", *flags]) }
        assert_equal 1, status, flags.join(" ")
        assert_match(%r{--(gloss-lines|translations|annotations) .* composes with --lang/--source/--axis/--license},
                     err, flags.join(" "))
      end
    end
  end

  def test_the_sibling_lanes_refuse_gloss_lines
    with_gloss_corpus do |config|
      [%w[search --translations king --gloss-lines], %w[search --annotations king --gloss-lines],
       %w[search --gloss king --gloss-lines]].each do |argv|
        _out, err, status = with_config(config) { run_cli(argv) }
        assert_equal 1, status, argv.join(" ")
        assert_match(/not --gloss-lines/, err, argv.join(" "))
      end
    end
  end

  def test_gloss_lines_needs_a_query
    with_gloss_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --gloss-lines]) }
      assert_equal 1, status
      assert_match(/--gloss-lines needs a query/, err)
    end
  end

  def test_an_absent_lane_is_an_honest_hint
    with_gloss_corpus(lane: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --gloss-lines king]) }
      assert_equal 1, status
      assert_match(/no gloss-lines index .* rake index:gloss_lines/, err)
    end
  end

  private

  def with_gloss_corpus(lane: true)
    Dir.mktmpdir("nabu-gloss-lines-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      Nabu::TestSupport.load_gloss_corpus(catalog)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      unless lane
        fulltext.drop_table(Nabu::Store::GlossLineIndex::TABLE)
        fulltext.drop_table(Nabu::Store::GlossLineIndex::SCOPE_TABLE)
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
