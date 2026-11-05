# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu search --gloss WORD` with no --lemma: every word some source
# glosses WORD, across lemmas (Store::GlossIndex). An on-disk catalog
# loaded from the real bhsa and achemenet fixtures, the reference index
# rebuild over it, then the rendered output. The desk law from both
# sides: hits come from the precompiled lane, and an absent lane is an
# honest hint, never a scan.
class SearchGlossCommandTest < Minitest::Test
  def test_a_gloss_finds_words_across_lemmas_and_sources
    with_gloss_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --gloss king]) }
      assert_nil status
      assert_match(/^מלך ‘king’ \[hbo\] bhsa — \d+ tokens? in \d+ passages?$/, out)
      assert_match(/^šarru ‘king’ \[akk\] achemenet — \d+ tokens? in \d+ passages?$/, out)
      assert_match(/^  e\.g\. urn:nabu:achemenet:\S+ \(\S+\)$/, out, "the first attestation, with its form")
      assert_match(/\d+ words glossed ‘king’ .*nabu search --lemma <lemma> --gloss <word>/, out)
      assert_match(/gloss index covers: achemenet \d+ words · bhsa \d+ words/, out)
    end
  end

  def test_source_and_lang_filters_compose
    with_gloss_corpus do |config|
      out, = with_config(config) { run_cli(%w[search --gloss king --source achemenet]) }
      refute_match(/bhsa —/, out)
      assert_match(/šarru/, out)

      out, = with_config(config) { run_cli(%w[search --gloss king --lang arc]) }
      assert_match(/^מלך ‘king’ \[arc\] bhsa/, out)
      refute_match(/šarru/, out)

      out, = with_config(config) { run_cli(%w[search --gloss zzyzx]) }
      assert_match(/no matches/, out)
      assert_match(/gloss index covers:/, out, "a miss still names the lane's scope")
    end
  end

  def test_the_gloss_lane_refuses_what_it_does_not_compose_with
    with_gloss_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --gloss king --fuzzy]) }
      assert_equal 1, status
      assert_match(%r{--gloss .* composes with --lang/--source/--axis/--license/--limit only}, err)
      _out, err, status = with_config(config) { run_cli(%w[search šarru --gloss king]) }
      assert_equal 1, status
      assert_match(/--gloss WORD .* requires --lemma/, err, "a text query + --gloss stays a usage error")
    end
  end

  def test_an_absent_lane_is_an_honest_hint
    with_gloss_corpus(lane: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --gloss king]) }
      assert_equal 1, status
      assert_match(/no token-gloss index .* rake index:glosses/, err)
    end
  end

  private

  def with_gloss_corpus(lane: true)
    Dir.mktmpdir("nabu-gloss-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      { "bhsa" => Nabu::Adapters::Bhsa, "achemenet" => Nabu::Adapters::Achemenet }.each do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      fulltext.drop_table(Nabu::Store::GlossIndex::TABLE) unless lane
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
