# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu sense TERM` and `nabu show --senses`: the readers of the DCS gold
# tokens' WordSem sense ids. An on-disk catalog loaded from the REAL dcs
# fixtures (chapters + the dcs-senses shelf), the sense facet pairs built
# under the shipped facet_map rule, then the rendered output. The desk law
# from both sides: the desk answers from the index; an unbuilt index is an
# honest hint, never a scan.
class SenseCommandTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("dcs")
  ANGULA = "urn:nabu:dcs:5:3363:2612"
  OPENING = "urn:nabu:dcs:5:3363:2588"

  # -- nabu sense --------------------------------------------------------------

  def test_sense_by_name_lists_the_sense_and_its_citing_tokens
    with_sense_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[sense finger]) }
      assert_nil status
      assert_match(/sense "finger": 1 sense · 1 passage/, out)
      assert_match(/59344\s+finger — the length of breadth of a finger used as a linear measure\s+1 passage/, out)
      assert_match(/^#{Regexp.escape(ANGULA)}  aṅgula ×11 \[59344\] · aṅgulam \(aṅgula\) ×4 \[59344\]/, out)
    end
  end

  def test_sense_by_id_keeps_a_multi_id_tokens_other_sense
    with_sense_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[sense 25258]) }
      assert_nil status
      assert_match(/25258\s+thickness — /, out)
      assert_match(/sthaulyāni \(sthaulya\) \[25248,25258\]/, out)
    end
  end

  def test_sense_gloss_mode_and_unresolved_ids
    with_sense_corpus do |config|
      out, = with_config(config) { run_cli(["sense", "physician of the gods", "--gloss"]) }
      assert_match(/128218\s+Dhanvantari — the physician of the gods/, out)
      unheld, = with_config(config) { run_cli(%w[sense 88425]) }
      assert_match(/88425\s+\(not in dcs-senses\)\s+1 passage/, unheld)
      assert_match(/^#{Regexp.escape(OPENING)}  vyākhyāsyāmaḥ \(vyākhyā\) \[88425\]/, unheld)
    end
  end

  def test_sense_limit_announces_truncation_and_census_without_a_term
    with_sense_corpus do |config|
      out, = with_config(config) { run_cli(%w[sense % --limit 1]) }
      assert_match(/showing 1 of 3 passages — raise --limit/, out)
      census, _err, status = with_config(config) { run_cli(%w[sense]) }
      assert_nil status
      assert_match(/sense index: 121 senses across 1 source/, census)
      assert_match(/dcs\s+121 senses\s+5 passages\s+121 pairs/, census)
    end
  end

  def test_sense_on_an_unbuilt_index_is_an_honest_hint
    with_sense_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[sense finger]) }
      assert_equal 1, status
      assert_match(/sense: the sense index is not built yet — run `bundle exec rake builders:refresh`/, err)
    end
  end

  # -- nabu show --senses ------------------------------------------------------

  def test_show_senses_lists_each_citing_token_with_its_resolved_senses
    with_sense_corpus(build: false) do |config|
      out, _err, status = with_config(config) { run_cli(%W[show #{OPENING} --senses]) }
      assert_nil status
      assert_match(/senses \(3 tokens\):/, out)
      opening = /^  āturopakramaṇīyam \(āturopakramaṇīya\)\s+128793 Āturopakramaṇīya — name of Suśrutasaṃhitā, Sū. 35$/
      assert_match(opening, out)
      assert_match(/^  adhyāyam \(adhyāya\)\s+30125 chapter — a subdivision of a written work/, out)
      assert_match(/^  vyākhyāsyāmaḥ \(vyākhyā\)\s+88425 \(not in dcs-senses\)$/, out)
    end
  end

  def test_show_senses_prints_every_id_of_a_multi_id_token
    with_sense_corpus(build: false) do |config|
      out, = with_config(config) { run_cli(%W[show #{ANGULA} --senses]) }
      assert_match(/^  sthaulyāni \(sthaulya\)\s+25248 circumference — .*\n\s+25258 thickness — /, out)
    end
  end

  def test_show_senses_on_a_document_groups_by_passage
    with_sense_corpus(build: false) do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:dcs:5:3363 --senses]) }
      assert_nil status
      assert_match(/senses \(214 tokens in 4 passages\):/, out)
      assert_match(/^  :2589\n    dhanvantariḥ \(dhanvantari\)\s+128218 Dhanvantari — /, out)
    end
  end

  def test_show_senses_on_an_unruled_source_says_so
    with_sense_corpus(build: false) do |config|
      db = Nabu::Store.connect(config.catalog_path)
      db[:sources].where(slug: "dcs").update(slug: "dcs-renamed")
      db.disconnect
      out, = with_config(config) { run_cli(%W[show #{OPENING} --senses]) }
      assert_match(/no token senses are ruled for dcs-renamed/, out)
    end
  end

  def test_show_senses_does_not_compose_with_random
    with_sense_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random --senses]) }
      assert_equal 1, status
      assert_match(%r{--senses does not compose with --random/--parallel}, err)
    end
  end

  private

  def with_sense_corpus(build: true)
    Dir.mktmpdir("nabu-sense-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      FileUtils.mkdir_p([config.db_dir, config.config_dir])
      FileUtils.cp(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"), config.config_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      load_dcs(db, build: build)
      db.disconnect
      yield config
    end
  end

  def load_dcs(db, build:)
    source = Nabu::Store::Source.create(slug: "dcs", name: "DCS", adapter_class: "Nabu::Adapters::Dcs",
                                        license_class: "attribution")
    Nabu::Store::Loader.new(db: db, source: source, ledger: nil).load_from(Nabu::Adapters::Dcs.new, workdir: FIXTURES)
    Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                 .load_from(Nabu::Adapters::DcsLexiconLane.new, workdir: FIXTURES)
    return unless build

    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    Nabu::Store::PassageFacetBuilder.rebuild!(catalog: db, facet_map: map)
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
