# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexibank-cldf intake, wave 1: eight dataset declarations over the
# family (lexibank_cldf_test.rb / lexibank_cldf_parser_test.rb pin the
# machinery). Per dataset: the declaration (slug, language, license grant,
# pinned release), the real trimmed fixture's discover → parse round trip
# (entry ids, headwords, reflex count, rejected grains), the loader's
# idempotency, the fetch arm and the unwired registry row. Fixture recipes:
# test/fixtures/<slug>/README.md.
class LexibankDatasetsTest < Minitest::Test
  include StoreTestDB

  Expect = Data.define(:klass, :language, :arm, :entry_ids, :headwords, :reflexes, :skips)

  EXPECTED = [
    Expect.new(klass: Nabu::Adapters::Dyenindoeuropean, language: "ine", arm: :git,
               entry_ids: %w[001-004 001-005], headwords: %w[ALL ALL], reflexes: 12, skips: 0),
    Expect.new(klass: Nabu::Adapters::Saenkoromance, language: "roa", arm: :zenodo,
               entry_ids: %w[23 34 -456], headwords: %w[bite breast yellow], reflexes: 10, skips: 1),
    Expect.new(klass: Nabu::Adapters::Tlopo, language: "poz-oce", arm: :zenodo,
               entry_ids: %w[1-3-3-4-55-POc-sajaq-a 1-4-2-2-76-POc-burua-a 1-4-3-1-81-PEOc-ibe-a],
               headwords: %w[sasa buruŋ ibe], reflexes: 8, skips: 2),
    Expect.new(klass: Nabu::Adapters::Acd, language: "map", arm: :zenodo,
               entry_ids: %w[24748_1 25118_1 30578_1], headwords: %w[abag baNaw asaŋ₃], reflexes: 8, skips: 1),
    Expect.new(klass: Nabu::Adapters::Mcd, language: "poz-mic", arm: :zenodo,
               entry_ids: %w[2978 2979 3005], headwords: %w[ae ae amʷii], reflexes: 10, skips: 1),
    Expect.new(klass: Nabu::Adapters::Csd, language: "sio", arm: :git,
               entry_ids: %w[113 13 73 2], headwords: ["*í_kaʔ-", "*xi", "vermin (6)", "*sitó• (?)"],
               reflexes: 7, skips: 0),
    Expect.new(klass: Nabu::Adapters::Uralex, language: "urj", arm: :zenodo,
               entry_ids: %w[100-f 104-j 106-x], headwords: ["*kämä ?", "*śurmi̮", "bad"], reflexes: 6, skips: 1),
    Expect.new(klass: Nabu::Adapters::Sagartst, language: "sit", arm: :zenodo,
               entry_ids: %w[20-above 2526-thethunder 3827-thesea], headwords: ["above", "the thunder", "the sea"],
               reflexes: 11, skips: 1)
  ].freeze

  def fixtures(expect) = Nabu::TestSupport.fixtures(expect.klass.dataset.slug)

  def parsed(expect)
    adapter = expect.klass.new
    adapter.parse(adapter.discover(fixtures(expect)).first)
  end

  def registry = @registry ||= Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))

  # --- declarations -------------------------------------------------------------------

  def test_each_declaration_is_a_cc_by_lexibank_cldf_dictionary
    EXPECTED.each do |expect|
      manifest = expect.klass.manifest
      slug = expect.klass.dataset.slug
      assert_equal slug, manifest.id
      assert_equal "lexibank-cldf", manifest.parser_family, slug
      assert_equal "attribution", manifest.license_class, slug
      assert_match(/\ACC BY 4\.0 \(README verbatim: "This dataset is licensed under a /, manifest.license, slug)
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

  def test_reconstruction_maps_name_only_codes_the_lects_registry_resolves
    resolvable = %w[pqe-pro poz-oce-pro poz-pcc-pro poz-pol-pro poz-pnp-pro poz-pep-pro poz-mic-pro]
    EXPECTED.each do |expect|
      mapped = expect.klass.dataset.varieties.values
      assert_empty mapped - resolvable, "#{expect.klass.dataset.slug}: unresolvable proto codes stay unmapped"
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
      assert_equal expect.headwords.map { |h| Nabu::Normalize.nfc(h) }, document.map(&:headword), slug
      assert_equal expect.reflexes, document.sum { |entry| entry.reflexes.size }, slug
      assert(document.all? { |entry| entry.body.unicode_normalized?(:nfc) }, slug)
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

  def test_tlopo_maps_proto_oceanic_onto_the_registry_and_leaves_pmp_unmapped
    set = parsed(EXPECTED.find { |e| e.klass == Nabu::Adapters::Tlopo })
          .find { |entry| entry.entry_id == "1-3-3-4-55-POc-sajaq-a" }
    assert_includes set.body, "reconstruction: PMP sasa (level PMP)"
    poc = set.reflexes.find { |r| r.lang_name == "POc" }
    assert_equal %w[poz-oce-pro poz-oce-pro saja], [poc.lang_code, poc.language, poc.word]
  end

  def test_sagartst_reads_the_value_column_and_keeps_old_chinese_a_member
    set = parsed(EXPECTED.find { |e| e.klass == Nabu::Adapters::Sagartst }).first
    assert_equal %w[xct steŋ], [set.reflexes.first.language, set.reflexes.first.word]
    assert_includes set.reflexes.map(&:word), "*daŋʔ-s"
  end

  def test_saenko_reads_the_braced_orthography
    set = parsed(EXPECTED.find { |e| e.klass == Nabu::Adapters::Saenkoromance }).find { |e| e.entry_id == "-456" }
    assert_equal([%w[giallo ǯˈalː-ə], %w[ggiallo ǯːˈalː-ə]].map { |pair| pair.map { |t| Nabu::Normalize.nfc(t) } },
                 set.reflexes.map { |r| [r.word, r.roman] })
    assert(set.reflexes.all?(&:borrowed), "the Loan column flags the Neapolitan loan")
  end

  # --- loader round trip -------------------------------------------------------------------

  def test_each_dataset_loads_through_the_dictionary_loader_idempotently
    EXPECTED.each do |expect|
      Dir.mktmpdir do |canonical_root|
        db = store_test_db
        slug = expect.klass.dataset.slug
        source = Nabu::Store::Source.create(
          slug: slug, name: slug, adapter_class: expect.klass.name, license: "CC BY 4.0",
          license_class: "attribution", upstream_url: expect.klass.manifest.upstream_url, enabled: false
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
      FileUtils.cp_r(File.join(Nabu::TestSupport.fixtures("uralex"), "cldf"), File.join(dir, "lexibank-test"))
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
      refute_nil entry, "#{slug} must be registered in config/sources.yml"
      assert_equal expect.klass, entry.adapter_class
      refute entry.wired, "#{slug}: wired flips only after the first verified sync"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "etym", slug
    end
  end
end
