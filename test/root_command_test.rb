# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu define --root ROOT` and `nabu show URN --roots`: the Quranic root →
# Lane link on the CLI. An on-disk catalog loaded from the REAL fixtures
# (Lane's sample shelf + the Quranic Arabic Corpus sample), the entry facets
# — the root keys included — built under the shipped facet_map rule.
class RootCommandTest < Minitest::Test
  LANE = Nabu::TestSupport.fixtures("lane-lexicon")
  QAC = Nabu::TestSupport.fixtures("quranic-corpus")
  FATIHA = "urn:nabu:quranic-corpus:1:1"

  # -- define --root -----------------------------------------------------------

  def test_define_root_prints_the_header_and_the_capped_entries
    with_root_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["define", "--root", "*mr"]) }
      assert_nil status
      assert_match(/^root \*mr \[buckwalter\] → ذمر: heading ذمر — 16 entries \(strict key\)$/, out)
      assert_equal 5, out.scan(/^\S.* \[ara\] — .*  urn:nabu:dict:lane:\S+$/).size, "five entry cards"
      assert_match(/… 11 more entries under this root \(--long shows all/, out)
    end
  end

  def test_define_root_reads_dmg_and_says_when_the_loose_key_answered
    with_root_corpus do |config|
      out, = with_config(config) { run_cli(["define", "--root", "ḏmr", "--limit", "1"]) }
      assert_match(/^root ḏmr \[dmg\] → ذمر: heading ذمر — 16 entries \(strict key\)$/, out)
      loose, = with_config(config) { run_cli(["define", "--root", "wtm"]) }
      assert_match(/→ وتم: heading يتم — 1 entry \(loose key — weak radicals/, loose)
    end
  end

  def test_define_root_misses_are_honest
    with_root_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["define", "--root", "ktb"]) }
      assert_nil status
      assert_match(/^root ktb \[dmg\] → كتب: no dictionary heading carries this root$/, out)
      unmapped, = with_config(config) { run_cli(["define", "--root", "ʾūl", "--scheme", "dmg"]) }
      assert_match(/^root ʾūl \[dmg\]: not a consonantal root in that notation \(unmapped: ū\)/, unmapped)
    end
  end

  def test_define_root_argument_errors
    with_root_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["define", "λόγος", "--root", "rHm"]) }
      assert_equal 1, status
      assert_match(/give a lemma or --root, not both/, err)
      _out, err, = with_config(config) { run_cli(["define", "λόγος", "--scheme", "dmg"]) }
      assert_match(/--scheme needs --root/, err)
    end
  end

  def test_define_root_on_an_unbuilt_surface_is_a_hint
    with_root_corpus(build: false) do |config|
      _out, err, status = with_config(config) { run_cli(["define", "--root", "rHm"]) }
      assert_equal 1, status
      assert_match(/root keys are not built in this catalog yet — run `bundle exec rake builders:refresh`/, err)
    end
  end

  # -- show --roots ------------------------------------------------------------

  def test_show_roots_lists_each_root_bearing_token
    with_root_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%W[show #{FATIHA} --roots]) }
      assert_nil status
      assert_match(/^roots \(4 tokens, 0 reaching a dictionary\):$/, out)
      assert_match(/^  r~aHiymi\s+rHm  → رحم  \(no dictionary heading\)$/, out)
      assert_match(/^  \{ll~ahi\s+Alh  → اله  \(no dictionary heading\)$/, out)
      assert_match(/nabu define --root ROOT/, out)
    end
  end

  # A token whose root Lane's sample holds steps to the article's first entry.
  def test_show_roots_steps_a_held_root_to_its_first_lane_entry
    with_root_corpus do |config|
      db = Nabu::Store.connect(config.catalog_path)
      row = db[:passages].where(urn: FATIHA)
      annotations = JSON.parse(row.get(:annotations_json))
      annotations["tokens"].find { |token| token["root"] == "smw" }["root"] = "ytm"
      row.update(annotations_json: JSON.generate(annotations))
      first = db[:dictionary_entries].where(Sequel.like(:urn, "urn:nabu:dict:lane:%"))
                                     .where(id: db[:entry_facets].where(
                                       value_id: db[:entry_facet_values].where(facet: "root", value: "يتم").select(:id)
                                     ).select(:entry_id)).order(:id).get(:urn)
      db.disconnect
      out, = with_config(config) { run_cli(%W[show #{FATIHA} --roots]) }
      assert_match(/^roots \(4 tokens, 1 reaching a dictionary\):$/, out)
      assert_match(/^  somi\s+ytm  → يتم  heading يتم — 1 entry \(strict key\)  #{Regexp.escape(first)}$/, out)
    end
  end

  def test_show_roots_on_a_document_groups_by_passage
    with_root_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:quranic-corpus:1 --roots]) }
      assert_nil status
      assert_match(/^roots \(\d+ tokens, 0 reaching a dictionary in \d+ passages\):$/, out)
      assert_match(/^  :1\n    somi\s+smw  → سمو/, out)
    end
  end

  def test_show_roots_on_a_source_without_a_root_scheme_says_so
    with_root_corpus do |config|
      db = Nabu::Store.connect(config.catalog_path)
      db[:sources].where(slug: "quranic-corpus").update(slug: "qac-renamed")
      db.disconnect
      out, = with_config(config) { run_cli(%W[show #{FATIHA} --roots]) }
      assert_match(/no token root scheme is declared for qac-renamed/, out)
    end
  end

  def test_show_roots_does_not_compose_with_random
    with_root_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random --roots]) }
      assert_equal 1, status
      assert_match(%r{--roots does not compose with --random/--parallel}, err)
    end
  end

  private

  def with_root_corpus(build: true)
    Dir.mktmpdir("nabu-root-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      FileUtils.mkdir_p([config.db_dir, config.config_dir])
      FileUtils.cp(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"), config.config_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      load_corpus(db, build: build)
      db.disconnect
      yield config
    end
  end

  def load_corpus(db, build:)
    lane = Nabu::Store::Source.create(slug: "lane-lexicon", name: "Lane", adapter_class: "Nabu::Adapters::LaneLexicon",
                                      license_class: "attribution")
    Nabu::Store::DictionaryLoader.new(db: db, source: lane).load_from(Nabu::Adapters::LaneLexicon.new, workdir: LANE)
    qac = Nabu::Store::Source.create(slug: "quranic-corpus", name: "QAC", adapter_class: "Nabu::Adapters::QuranicCorpus",
                                     license_class: "attribution")
    Nabu::Store::Loader.new(db: db, source: qac, ledger: nil).load_from(Nabu::Adapters::QuranicCorpus.new, workdir: QAC)
    return unless build

    map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
    Nabu::Store::EntryFacetBuilder.rebuild!(catalog: db, facet_map: map)
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
