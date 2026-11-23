# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexibank-cldf intake, wave 2: three CC BY-NC dataset declarations
# over the family (lexibank_cldf_test.rb / lexibank_cldf_parser_test.rb pin
# the machinery; lexibank_datasets_test.rb the CC BY wave 1). Per dataset:
# the declaration (slug, language, nc license grant, pinned release), the
# real trimmed fixture's discover → parse round trip (entry ids, headwords,
# reflex count, rejected grains), the loader's idempotency, the fetch arm
# and the unwired registry row. Fixture recipes: test/fixtures/<slug>/README.md.
class LexibankDatasetsNcTest < Minitest::Test
  include StoreTestDB

  Expect = Data.define(:klass, :language, :arm, :entry_ids, :headwords, :reflexes, :skips)

  EXPECTED = [
    Expect.new(klass: Nabu::Adapters::Kitchensemitic, language: "sem", arm: :zenodo,
               entry_ids: %w[1_all-B 2_ashes-F 17_dog-A], headwords: %w[All Ashes Dog], reflexes: 14, skips: 1),
    Expect.new(klass: Nabu::Adapters::Zhangrgyalrong, language: "sit", arm: :git,
               entry_ids: %w[1 14 22], headwords: ["the axe", "the bovine", "to protect"], reflexes: 15, skips: 0),
    Expect.new(klass: Nabu::Adapters::Peirosst, language: "sit", arm: :git,
               entry_ids: %w[1-2693 1--1 3-262], headwords: %w[all all bark], reflexes: 14, skips: 0)
  ].freeze

  def fixtures(expect) = Nabu::TestSupport.fixtures(expect.klass.dataset.slug)

  def parsed(expect)
    adapter = expect.klass.new
    adapter.parse(adapter.discover(fixtures(expect)).first)
  end

  def expect_for(klass) = EXPECTED.find { |e| e.klass == klass }

  def set(klass, id) = parsed(expect_for(klass)).find { |entry| entry.entry_id == id } || flunk("set #{id} missing")

  def registry = @registry ||= Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))

  # --- declarations -------------------------------------------------------------------

  def test_each_declaration_is_a_cc_by_nc_lexibank_cldf_dictionary
    EXPECTED.each do |expect|
      manifest = expect.klass.manifest
      slug = expect.klass.dataset.slug
      assert_equal slug, manifest.id
      assert_equal "lexibank-cldf", manifest.parser_family, slug
      assert_equal "nc", manifest.license_class, slug
      assert_match(/\ACC BY-NC 4\.0 \(README verbatim: "This dataset is licensed under a /, manifest.license, slug)
      assert_includes manifest.license, "Attribution-NonCommercial 4.0 International", slug
      refute_match(/NoDerivatives|BY-NC-ND/, manifest.license, slug)
      assert_equal :dictionary, expect.klass.content_kind
      assert expect.klass.reflex_bearing?, slug
      assert_equal expect.language, expect.klass.dataset.language, slug
    end
  end

  def test_zenodo_arms_pin_a_versioned_record_and_git_arms_record_the_observed_commit
    EXPECTED.each do |expect|
      release = expect.klass.dataset.release
      slug = expect.klass.dataset.slug
      if expect.arm == :zenodo
        assert_kind_of Nabu::Adapters::LexibankCldf::ZenodoRelease, release, slug
        assert_match(/\A[0-9a-f]{64}\z/, release.sha256, slug)
        assert_match(%r{\Ahttps://zenodo\.org/api/records/#{release.record}/files/}, release.url, slug)
        assert_equal "https://doi.org/#{release.doi}", expect.klass.manifest.upstream_url, slug
        assert_equal :http_zip, expect.klass.remote_probe_strategy
      else
        assert_kind_of Nabu::Adapters::LexibankCldf::GitRepository, release, slug
        assert_match(/\A[0-9a-f]{40}\z/, release.commit, slug)
        assert_nil release.ref, "#{slug}: upstream has never tagged a release"
        assert_equal :git, expect.klass.remote_probe_strategy
      end
    end
  end

  def test_no_variety_is_mapped_none_carries_a_reconstruction
    EXPECTED.each do |expect|
      assert_empty expect.klass.dataset.varieties, expect.klass.dataset.slug
      assert_empty expect.klass.dataset.proto_varieties, expect.klass.dataset.slug
    end
  end

  # --- fixtures: discover → parse ---------------------------------------------------------

  def test_each_fixture_discovers_one_bundle_and_parses_its_sets
    EXPECTED.each do |expect|
      slug = expect.klass.dataset.slug
      refs = expect.klass.new.discover(fixtures(expect)).to_a
      assert_equal ["#{slug}:cldf"], refs.map(&:id)
      document = parsed(expect)
      assert_equal slug, document.slug
      assert_equal expect.language, document.language
      assert_equal expect.entry_ids, document.map(&:entry_id), slug
      assert_equal expect.headwords, document.map(&:headword), slug
      assert_equal expect.reflexes, document.sum { |entry| entry.reflexes.size }, slug
      assert(document.all? { |entry| entry.body.unicode_normalized?(:nfc) }, slug)
      assert(document.all? { |entry| entry.reflexes.all? { |r| r.word.unicode_normalized?(:nfc) } }, slug)
    end
  end

  def test_rejected_grains_are_skipped_by_rule_with_their_specimens_pinned
    EXPECTED.each do |expect|
      skips = expect.klass.new.discovery_skips(fixtures(expect))
      assert_equal expect.skips, skips.skipped_by_rule, expect.klass.dataset.slug
      assert_equal 0, skips.unrecognized
      assert(skips.notes.all? { |note| note.include?("not ingested") })
    end
  end

  def test_entry_ids_are_unique_and_stable_across_two_parses
    EXPECTED.each do |expect|
      first = parsed(expect).map(&:entry_id)
      assert_equal first.uniq, first
      assert_equal first, parsed(expect).map(&:entry_id)
    end
  end

  # --- dataset-specific spot checks ---------------------------------------------------

  def test_kitchensemitic_carries_the_ancient_semitic_rows_on_their_iso_codes
    dog = set(Nabu::Adapters::Kitchensemitic, "17_dog-A")
    by_name = dog.reflexes.to_h { |r| [r.lang_name, [r.language, r.word]] }
    assert_equal %w[akk kalbu], by_name["Akkadian"]
    assert_equal %w[uga klb], by_name["Ugaritic"]
    assert_equal ["heb", Nabu::Normalize.nfc("keleβ")], by_name["Hebrew"]
    assert_equal %w[oar kalba:], by_name["Aramaic"], "upstream's oar rides verbatim"
    ogaden = dog.reflexes.find { |r| r.lang_name == "Ogadɛn Arabic" }
    assert_equal ["ogad1238", nil], [ogaden.lang_code, ogaden.language], "ISO-less: display-only"
    assert_includes dog.body, "no reconstruction in this dataset — the concept heads the set"
  end

  def test_kitchensemitic_counts_the_unjudged_second_variant
    expect = expect_for(Nabu::Adapters::Kitchensemitic)
    adapter = expect.klass.new
    census = adapter.census(adapter.discover(fixtures(expect)).first)
    assert_equal({ sets_minted: 3, forms_unjudged: 1 }, census)
    refute_includes set(Nabu::Adapters::Kitchensemitic, "2_ashes-F").reflexes.map(&:word), "dikme:nu"
  end

  def test_zhangrgyalrong_reads_the_value_and_carries_the_chinese_character
    axe = set(Nabu::Adapters::Zhangrgyalrong, "1")
    assert_equal ["pjuX", "*praʔ", "ʃa-rpâ", "ɕa-rpiɛ̂", "tɯ-rpa"].map { |w| Nabu::Normalize.nfc(w) },
                 axe.reflexes.map(&:word), "Value verbatim — the asterisk and the prefix hyphen kept"
    assert_includes axe.body, "Chinese character: 斧", "Gloss_in_Source decoded from its list literal"
    old_chinese = axe.reflexes.find { |r| r.lang_name == "Old Chinese" }
    assert_equal %w[och och], [old_chinese.lang_code, old_chinese.language]
    assert_equal "praʔ", old_chinese.word_folded, "the fold drops the reconstruction asterisk"
    japhug = axe.reflexes.find { |r| r.lang_name == "Japhug" }
    assert_equal ["dgon1234", nil], [japhug.lang_code, japhug.language]
  end

  def test_peirosst_reads_the_database_cell_and_keeps_the_non_positive_class
    bark = set(Nabu::Adapters::Peirosst, "3-262")
    old_chinese = bark.reflexes.find { |r| r.lang_name == "Old Chinese" }
    assert_equal ["och", "bhaj 皮"], [old_chinese.language, old_chinese.word], "Value, the character kept"
    chn = bark.reflexes.find { |r| r.lang_name == "CHN" }
    assert_equal ["peirosst-CHN", nil], [chn.lang_code, chn.language], "no ISO, no Glottocode: namespaced"
    minus_one = set(Nabu::Adapters::Peirosst, "1--1")
    assert_equal 8, minus_one.reflexes.size
    assert_includes minus_one.reflexes.map(&:word), "kurup (Tib.?)"
    refute(minus_one.reflexes.any?(&:borrowed), "upstream's loan tags are prose — no flag inferred")
  end

  # --- loader round trip -------------------------------------------------------------------

  def test_each_dataset_loads_through_the_dictionary_loader_idempotently
    EXPECTED.each do |expect|
      Dir.mktmpdir do |canonical_root|
        db = store_test_db
        slug = expect.klass.dataset.slug
        source = Nabu::Store::Source.create(
          slug: slug, name: slug, adapter_class: expect.klass.name, license: "CC BY-NC 4.0",
          license_class: "nc", upstream_url: expect.klass.manifest.upstream_url, enabled: false
        )
        loader = Nabu::Store::DictionaryLoader.new(
          db: db, source: source, ledger: ledger_test_db,
          language_shelf_dir: File.join(canonical_root, Nabu::LanguageShelf::SLUG)
        )
        adapter = expect.klass.new
        report = loader.load_from(adapter, workdir: fixtures(expect))
        assert_equal expect.entry_ids.size, report.added, slug
        assert_equal 0, report.errored, slug
        assert_equal expect.reflexes, db[:dictionary_reflexes].count, slug
        second = loader.load_from(adapter, workdir: fixtures(expect))
        assert_equal 0, second.added + second.updated + second.withdrawn, slug
        assert_equal expect.reflexes, db[:dictionary_reflexes].count, slug
      end
    end
  end

  # --- fetch arms -------------------------------------------------------------------------

  # A real zip of one fixture bundle — any body misses every real pin.
  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexibank-test"))
      FileUtils.cp_r(File.join(Nabu::TestSupport.fixtures("kitchensemitic"), "cldf"), File.join(dir, "lexibank-test"))
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-test") }
      File.binread(zip)
    end
  end

  def test_zenodo_arms_fetch_their_pinned_record_and_refuse_a_pin_miss
    body = zip_body
    EXPECTED.select { |e| e.arm == :zenodo }.each do |expect|
      release = expect.klass.dataset.release
      stub_request(:get, release.url).to_return(status: 200, body: body)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { expect.klass.new.fetch(workdir) }
        assert_match(/sha256 pin/, error.message, expect.klass.dataset.slug)
        assert_empty(Dir.children(workdir).reject { |child| child.start_with?(".") })
      end
    end
  end

  def test_git_arms_fetch_the_sparse_repository
    EXPECTED.select { |e| e.arm == :git }.each do |expect|
      captured = nil
      adapter = expect.klass.new
      adapter.define_singleton_method(:git_fetch!) { |**kw| captured = kw }
      adapter.fetch("/tmp/nowhere")
      assert_equal expect.klass.dataset.release.repo_url, captured[:repo_url]
      assert_equal %w[cldf LICENSE README.md], captured[:sparse]
    end
  end

  # --- registry -------------------------------------------------------------------------------

  def test_each_dataset_is_registered_unwired_and_manual
    EXPECTED.each do |expect|
      slug = expect.klass.dataset.slug
      entry = registry[slug]
      refute_nil entry, "#{slug} must be registered in config/sources/"
      assert_equal expect.klass, entry.adapter_class
      refute entry.wired, "#{slug}: wired flips only after the verified first sync"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "etym", slug
    end
  end
end
