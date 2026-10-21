# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# --verbose on the composite commands: a green intro before the work and a
# one-line explanation before each stage, on the progress channel
# (stderr), from the one registry (Nabu::Ops::StageGuide). A plain run
# carries none of it; NO_COLOR / a piped stream keep the text and drop
# the color.
class VerboseModeTest < Minitest::Test
  GUIDE = Nabu::Ops::StageGuide

  def test_verbose_rebuild_explains_the_command_and_each_stage_exactly_once
    out, err = rebuild_run(%w[rebuild --verbose])
    assert_equal 1, err.scan(GUIDE.intro(:rebuild)).size, "the intro prints once, before the work"
    assert_operator err.index(GUIDE.intro(:rebuild)), :<, err.index(GUIDE.fetch(:source_replay).text)
    stages = %i[source_replay honkoku_ndl_catalog timeline silver_dates place_apply facets kind_axis
                passage_facets entity_index entry_facets hiero_postings lect_journal lect_facets dictionary_stats
                derge_titles aes_titles artifact_scripts source_stats fulltext_index lemma_rollups
                links analyze]
    stages.each do |key|
      assert_equal 1, err.scan(GUIDE.fetch(key).text).size, "#{key} explains exactly once"
    end
    assert_operator err.index(GUIDE.fetch(:timeline).text), :<, err.index("  timeline…"),
                    "the explanation precedes its stage's line"
    refute_includes out, GUIDE.fetch(:timeline).text, "narration never pollutes stdout"
    assert_match(/indexed 3 passages/, out, "the operational report is unchanged")
  end

  def test_plain_rebuild_carries_no_explanation
    out, err = rebuild_run(%w[rebuild])
    transcript = out + err
    GUIDE.stages.each { |entry| refute_includes transcript, entry.text, "#{entry.key} leaked into a plain run" }
    GUIDE.commands.each_value { |text| refute_includes transcript, text }
  end

  def test_color_is_green_when_forced_and_dropped_under_no_color_text_kept
    _out, err = with_env("NABU_COLOR" => "1", "NO_COLOR" => nil) { rebuild_run(%w[rebuild --verbose]) }
    assert_includes err, "\e[32m» #{GUIDE.intro(:rebuild)}\e[0m"
    assert_includes err, "\e[32m» #{GUIDE.fetch(:timeline).text}\e[0m"

    _out, err = with_env("NABU_COLOR" => "1", "NO_COLOR" => "1") { rebuild_run(%w[rebuild --verbose]) }
    refute_match(/\e\[/, err, "NO_COLOR: no ANSI codes at all")
    assert_includes err, "» #{GUIDE.fetch(:timeline).text}", "NO_COLOR keeps the text"

    _out, err = with_env("NABU_COLOR" => nil, "NO_COLOR" => nil) { rebuild_run(%w[rebuild --verbose]) }
    refute_match(/\e\[/, err, "a non-tty stream stays colorless by default")
    assert_includes err, GUIDE.fetch(:timeline).text
  end

  def test_verbose_incremental_rebuild_explains_its_own_intro_and_the_verdict_pass
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      _out, err, status = with_config(config) { run_cli(%w[rebuild --incremental --verbose]) }
      assert_nil status
      assert_equal 1, err.scan(GUIDE.intro(:rebuild_incremental)).size
      refute_includes err, GUIDE.intro(:rebuild), "the incremental flavor has its own intro"
      assert_equal 1, err.scan(GUIDE.fetch(:verdict).text).size
      assert_equal 1, err.scan(GUIDE.fetch(:pinning_code_identities).text).size
    end
  end

  def test_verbose_parse_only_sync_explains_load_index_and_lanes
    with_sync_env do |config|
      _out, err, = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      GUIDE.stages.each { |entry| refute_includes err, entry.text, "#{entry.key} leaked into a plain sync" }
      GUIDE.commands.each_value { |text| refute_includes err, text }

      # A changed passage, so the second (verbose) sync rewrites its index
      # slice instead of the first sync's from-scratch index build.
      File.write(File.join(config.canonical_dir, "corpus", "two.txt"), "Odyssey\nἄνδρα μοι\n")
      out, err, status = with_config(config) { run_cli(%w[sync corpus --parse-only --verbose]) }
      assert_nil status, err
      assert_equal 1, err.scan(GUIDE.intro(:sync_parse_only)).size
      %i[sync_load index_slice post_load_lanes].each do |key|
        assert_equal 1, err.scan(GUIDE.fetch(key).text).size, "#{key} explains exactly once"
      end
      refute_includes out, GUIDE.fetch(:sync_load).text
    end
  end

  def test_verbose_builders_refresh_narrator_explains_every_builder_stage
    io = StringIO.new
    narrator = GUIDE::Narrator.new(io: io, color: false)
    labels = []
    reporter = Nabu::ProgressReporter.new(on_explain: narrator, on_stage: ->(label, _eta) { labels << label })
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      catalog = Nabu::Store.connect(config.catalog_path)
      narrator.intro(:builders_refresh)
      Nabu::Ops::BuilderRefresh.run(catalog: catalog, config: config, progress: reporter)
      catalog.disconnect
    end
    assert_includes io.string, GUIDE.intro(:builders_refresh)
    labels.each do |label|
      entry = GUIDE.lookup(label)
      refute_nil entry, "builders:refresh stage #{label.inspect} is unexplained"
      assert_equal 1, io.string.scan(entry.text).size, "#{label} explains once"
    end
  end

  private

  def rebuild_run(argv)
    with_rebuild_env do |config|
      out, err, status = with_config(config) { run_cli(argv) }
      assert_nil status, err
      [out, err]
    end
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      Nabu::CLI.start(argv)
    rescue SystemExit => e
      status = e.status
    end
    [out, err, status]
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def with_rebuild_env(&)
    corpus_env("wired: true\n", &)
  end

  def with_sync_env(&)
    corpus_env("wired: true\n  sync_policy: auto\n", &)
  end

  def corpus_env(extra)
    Dir.mktmpdir("nabu-verbose") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  #{extra}")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: File.join(root, "config", "nabu.yml")
      )
    end
  end

  def with_env(pairs)
    saved = pairs.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    pairs.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
