# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The lexibank-cldf intake, the Altaic-area pair: two CC BY dataset
# declarations over the family (lexibank_cldf_test.rb /
# lexibank_cldf_parser_test.rb pin the machinery). Per dataset: the
# declaration (slug, language, license grant, pinned Zenodo release), the
# real trimmed fixture's discover → parse round trip (entry ids, headwords,
# reflex count, rejected grains incl. a single-file grain), the loader's
# idempotency, the fetch arm and the unwired registry row. Fixture recipes:
# test/fixtures/<slug>/README.md.
class LexibankDatasetsAltaicTest < Minitest::Test
  include StoreTestDB

  Expect = Data.define(:klass, :language, :entry_ids, :headwords, :reflexes, :skips)

  EXPECTED = [
    Expect.new(klass: Nabu::Adapters::Savelyevturkic, language: "trk",
               entry_ids: %w[377 138 656 896],
               headwords: ["ask (v.)", "child (kin term) (n.)", "spin (v.)", "with"],
               reflexes: 11, skips: ["raw/", "turkic.nex"]),
    Expect.new(klass: Nabu::Adapters::Robbeetstriangulation, language: "tut",
               entry_ids: %w[24 60 529 3152],
               headwords: ["go (v.)", "2SG pronoun", "child (kin term) (n.)", "with"],
               reflexes: 11, skips: ["raw/", "plots/"])
  ].freeze

  def fixtures(expect) = Nabu::TestSupport.fixtures(expect.klass.dataset.slug)

  def parsed(expect)
    adapter = expect.klass.new
    adapter.parse(adapter.discover(fixtures(expect)).first)
  end

  def expect_for(klass) = EXPECTED.find { |e| e.klass == klass }

  def set(klass, id) = parsed(expect_for(klass)).find { |entry| entry.entry_id == id } || flunk("set #{id} missing")

  def by_name(entry) = entry.reflexes.to_h { |r| [r.lang_name, r] }

  def registry = @registry ||= Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))

  # --- declarations -------------------------------------------------------------------

  def test_each_declaration_is_a_cc_by_lexibank_cldf_dictionary_on_a_pinned_zenodo_record
    EXPECTED.each do |expect|
      manifest = expect.klass.manifest
      dataset = expect.klass.dataset
      slug = dataset.slug
      assert_equal slug, manifest.id
      assert_equal "lexibank-cldf", manifest.parser_family, slug
      assert_equal "attribution", manifest.license_class, slug
      assert_match(/\ACC BY 4\.0 \(README verbatim: "This dataset is licensed under a CC-BY-4\.0 license"/,
                   manifest.license, slug)
      assert_includes manifest.license, "Attribution 4.0 International", slug
      assert_equal :dictionary, expect.klass.content_kind
      assert expect.klass.reflex_bearing?, slug
      assert_equal expect.language, dataset.language, slug
      assert_equal :value, dataset.word_from, "#{slug}: Form is lexibank's rewrite — the source Value is the word"
      assert_equal({ "Root" => "root" }, dataset.judgment_notes, slug)
      release = dataset.release
      assert_kind_of Nabu::Adapters::LexibankCldf::ZenodoRelease, release, slug
      assert_match(/\A[0-9a-f]{64}\z/, release.sha256, slug)
      assert_match(%r{\Ahttps://zenodo\.org/api/records/#{release.record}/files/lexibank/#{slug}-}, release.url)
      assert_equal "https://doi.org/#{release.doi}", manifest.upstream_url, slug
      assert_equal :http_zip, expect.klass.remote_probe_strategy
    end
  end

  def test_the_renamed_repository_is_declared_under_its_current_name
    dataset = Nabu::Adapters::Robbeetstriangulation.dataset
    assert_equal "robbeetstriangulation", dataset.slug
    assert_includes dataset.release.url, "lexibank/robbeetstriangulation-v0.3.zip"
    refute_includes dataset.name, "robbeetsaltaic", "the former name is history, never the slug"
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
      assert(document.all? { |entry| entry.body.include?("no reconstruction in this dataset") }, slug)
      assert(document.all? { |entry| entry.body.unicode_normalized?(:nfc) }, slug)
      assert(document.all? { |entry| entry.reflexes.all? { |r| r.word.unicode_normalized?(:nfc) } }, slug)
    end
  end

  def test_rejected_grains_are_skipped_by_rule_with_their_specimens_pinned
    EXPECTED.each do |expect|
      skips = expect.klass.new.discovery_skips(fixtures(expect))
      slug = expect.klass.dataset.slug
      assert_equal expect.skips.size, skips.skipped_by_rule, slug
      assert_equal 0, skips.unrecognized
      assert_equal(expect.skips, skips.notes.map { |note| note.split("not ingested: ").last }, slug)
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

  def test_savelyevturkic_carries_old_turkic_and_maps_the_code_less_cuman_row_to_qwm
    with = set(Nabu::Adapters::Savelyevturkic, "896")
    cuman = by_name(with)["Cuman"]
    assert_equal %w[qwm qwm birla], [cuman.lang_code, cuman.language, cuman.word],
                 "upstream gives the Cuman row no code; its own name is ISO qwm"
    old_turkic = by_name(with)["Old Turkic"]
    assert_equal %w[oui oui birle], [old_turkic.lang_code, old_turkic.language, old_turkic.word],
                 "upstream's ISO rides verbatim"
    assert_includes with.body, "root: birle"
  end

  def test_savelyevturkic_reads_the_value_not_the_ipa_form
    spin = set(Nabu::Adapters::Savelyevturkic, "656")
    assert_includes spin.reflexes.map(&:word), "(yep) ilä", "Value verbatim; Form would be (jep) ilɛ"
    assert_includes spin.body, "root: jip; čijrat"
    ask = set(Nabu::Adapters::Savelyevturkic, "377")
    tatar = by_name(ask)["Kazan Tatar"]
    assert_equal ["midd1325", nil], [tatar.lang_code, tatar.language], "ISO-less: display-only"
  end

  def test_robbeetstriangulation_maps_the_historical_rows_onto_their_registry_codes
    pronoun = set(Nabu::Adapters::Robbeetstriangulation, "60")
    korean = by_name(pronoun)["(Late) Middle Korean"]
    assert_equal %w[okm okm ne], [korean.lang_code, korean.language, korean.word],
                 "upstream tags it kor (modern Korean); its own name and late1258 say Middle Korean"
    japanese = by_name(pronoun)["Old Japanese"]
    assert_equal ["ojp", "na ~ nare"], [japanese.language, japanese.word], "the variants ride in the Value"
    assert_includes pronoun.body, "root: *ne"
    go = set(Nabu::Adapters::Robbeetstriangulation, "24")
    assert_equal(%w[xng xng], go.reflexes.select { |r| r.lang_name.start_with?("Middle Mongolian") }
                                .map(&:language))
    oirat = by_name(go)["Oirat"]
    assert_equal ["robbeetstriangulation-Oirat", nil], [oirat.lang_code, oirat.language],
                 "no ISO, no Glottocode: namespaced"
  end

  def test_robbeetstriangulation_carries_cuman_on_upstreams_qwm
    with = set(Nabu::Adapters::Robbeetstriangulation, "3152")
    cuman = by_name(with)["CodexCumanicus"]
    assert_equal %w[qwm qwm birla], [cuman.lang_code, cuman.language, cuman.word]
    assert_equal "oui", by_name(with)["OldTurkic"].language
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

  # --- fetch arm --------------------------------------------------------------------------

  # A real zip of one fixture bundle — any body misses every real pin.
  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lexibank-test"))
      FileUtils.cp_r(File.join(Nabu::TestSupport.fixtures("savelyevturkic"), "cldf"),
                     File.join(dir, "lexibank-test"))
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-test") }
      File.binread(zip)
    end
  end

  def test_each_arm_fetches_its_pinned_record_and_refuses_a_pin_miss
    body = zip_body
    EXPECTED.each do |expect|
      release = expect.klass.dataset.release
      stub_request(:get, release.url).to_return(status: 200, body: body)
      Dir.mktmpdir do |workdir|
        error = assert_raises(Nabu::FetchError) { expect.klass.new.fetch(workdir) }
        assert_match(/sha256 pin/, error.message, expect.klass.dataset.slug)
        assert_empty(Dir.children(workdir).reject { |child| child.start_with?(".") })
      end
    end
  end

  # --- registry -------------------------------------------------------------------------------

  def test_each_dataset_is_registered_unwired_and_manual
    EXPECTED.each do |expect|
      slug = expect.klass.dataset.slug
      entry = registry[slug]
      refute_nil entry, "#{slug} must be registered in config/sources/"
      assert_equal expect.klass, entry.adapter_class
      refute entry.wired, "#{slug}: wired only after the verified first sync"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "etym", slug
      assert_includes entry.axes, "turkic", slug
    end
  end
end
