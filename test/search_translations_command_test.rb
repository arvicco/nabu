# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu search --translations QUERY`: search the translations a source
# keeps inside its passages' annotations (Store::TranslationIndex). An
# on-disk catalog loaded from the real coptic-scriptorium and
# hittite-glossed fixtures, the reference index rebuild over it, then the
# rendered output. The desk law from both sides: hits come from the
# precompiled lane, and an absent lane is an honest hint, never a scan.
class SearchTranslationsCommandTest < Minitest::Test
  COPTIC_HIT = "urn:nabu:coptic-scriptorium:ap.100.monbeg:1.1"

  def test_a_translation_query_finds_the_original_passage
    with_translation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["search", "--translations", "brothers according"]) }
      assert_nil status
      assert_match(/^#{Regexp.escape(COPTIC_HIT)} \[cop\]/, out, "the hit names the ORIGINAL passage")
      assert_match(/  translation: Two \[brothers\] according to the flesh/, out)
      assert_match(/  original: \S/, out, "the original text rides under the rendering")
      assert_match(/\d+ hits? in annotation-held translations/, out)
      assert_match(/nabu show <urn>/, out, "the footer says how to jump to the original")
      assert_match(/translations index covers: coptic-scriptorium \d+ · hittite-glossed \d+/, out)
    end
  end

  def test_german_glosses_fold_and_name_their_layer
    with_translation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --translations wettergott --limit 3]) }
      assert_nil status
      assert_match(/urn:nabu:hittite-glossed:\S+ \[hit\]/, out)
      assert_match(/  trans_de: .*\[Wettergott\]/, out)
    end
  end

  def test_source_and_lang_filters_compose
    with_translation_corpus do |config|
      out, = with_config(config) { run_cli(%w[search --translations wettergott --source coptic-scriptorium]) }
      assert_match(/no matches/, out)
      assert_match(/translations index covers:/, out, "a miss still names the lane's scope")

      out, = with_config(config) { run_cli(%w[search --translations brothers --lang cop --limit 1]) }
      assert_match(/\[cop\]/, out)
    end
  end

  def test_unknown_source_is_refused
    with_translation_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --translations x --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
    end
  end

  def test_translations_refuses_modes_it_does_not_compose_with
    with_translation_corpus do |config|
      %w[--fuzzy --exact --word --scan --withdrawn].each do |flag|
        _out, err, status = with_config(config) { run_cli(["search", "--translations", "brothers", flag]) }
        assert_equal 1, status, flag
        assert_match(%r{--translations .* composes with --lang/--source/--axis/--license/--limit only}, err,
                     flag)
      end
      _out, err, status = with_config(config) { run_cli(%w[search --translations brothers --century 4]) }
      assert_equal 1, status
      assert_match(/--translations/, err)
    end
  end

  def test_translations_needs_a_query
    with_translation_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --translations]) }
      assert_equal 1, status
      assert_match(/--translations needs a query/, err)
    end
  end

  # Desk rule: no lane, no scan — the exact build command instead.
  def test_an_absent_lane_is_an_honest_hint
    with_translation_corpus(lane: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --translations brothers]) }
      assert_equal 1, status
      assert_match(/no translations index .* rake index:translations/, err)
    end
  end

  private

  def with_translation_corpus(lane: true)
    Dir.mktmpdir("nabu-translations-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      { "coptic-scriptorium" => Nabu::Adapters::CopticScriptorium,
        "hittite-glossed" => Nabu::Adapters::HittiteGlossed }.each do |slug, adapter|
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: adapter.name,
                                            license_class: "open")
        Nabu::Store::Loader.new(db: catalog, source: source)
                           .load_from(adapter.new, workdir: Nabu::TestSupport.fixtures(slug), full: true)
      end
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)
      unless lane
        fulltext.drop_table(Nabu::Store::TranslationIndex::TABLE)
        fulltext.drop_table(Nabu::Store::TranslationIndex::SCOPE_TABLE)
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
