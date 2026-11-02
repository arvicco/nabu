# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::EtcbcSyriac — the ETCBC Syriac Corpus (Text-Fabric
  # tf/0.92, github.com/ETCBC/syriac) over the text-fabric family:
  # document = book, passage = verse, syc text NFC at the boundary, every
  # word-grain morphology feature verbatim on the tokens, discontiguous
  # verses rendered from their own slot ranges only. Fixtures are
  # gap-anchored tf/0.92 slices — Jonah, both Prayer-of-Manasseh versions
  # and the Apocalypse of Pseudo-Ezra whole, Deuteronomy 14 clipped (the
  # interleaved 14:16–17) — see test/fixtures/etcbc-syriac/README.md.
  class EtcbcSyriacTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("etcbc-syriac")
    URN = "urn:nabu:etcbc-syriac:"

    def conformance_adapter
      Nabu::Adapters::EtcbcSyriac.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "etcbc-syriac"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_etcbc_syriac_wired_on_its_first_sync_evidence
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["etcbc-syriac"]
      refute_nil entry, "etcbc-syriac must be registered in config/sources.yml"
      assert entry.wired, "wired on the first-sync evidence (landed exactly on census, 2026-11-02)"
      assert_equal "manual", entry.sync_policy
      assert_equal "etcbc-syriac", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_deliberately_over_the_zenodo_label
      manifest = Nabu::Adapters::EtcbcSyriac.manifest
      assert_equal "nc", manifest.license_class,
                   "README CC BY-NC 4.0 + the ETCBC directorate's 2026-10-15 statement outrank Zenodo's cc-by-4.0"
      assert_includes manifest.license, "Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)"
      assert_includes manifest.license, "cc-by-4.0", "the conflicting Zenodo label is recorded, not hidden"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census ---------------------------------------------------------------

    def test_the_whole_otype_census
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.92"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 407_319, counts["word"]
      assert_equal 31, counts["book"]
      assert_equal 807, counts["chapter"]
      assert_equal 18_132, counts["verse"]
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_node
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[#{URN}deuteronomy #{URN}jonah #{URN}ormana #{URN}ormanb #{URN}pse],
                   refs.map(&:id), "book names downcased verbatim"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_an_unknown_book_is_a_parse_error_never_a_guess
      assert_raises(Nabu::ParseError) { Nabu::Adapters::EtcbcSyriac.book_info("Tobit") }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_titles_and_the_corpus_grouping
      jonah = parse_urn("#{URN}jonah")
      assert_equal "Jonah", jonah.title
      assert_equal "syc", jonah.language
      assert_equal "Peshitta", jonah.metadata["corpus"]
      assert_equal 48, jonah.size
      pse = parse_urn("#{URN}pse")
      assert_equal "Apocalypse of Pseudo-Ezra", pse.title
      assert_equal "PsE", pse.metadata["book"], "upstream's book name verbatim"
      assert_equal 77, pse.size
      assert_equal "Prayer of Manasseh (A)", parse_urn("#{URN}ormana").title
    end

    def test_verse_text_is_the_corpus_own_word_trailer_rendering
      passage = passage_at("#{URN}jonah", "#{URN}jonah:1.1")
      assert_equal "ܘܗܘܐ ܦܬܓܡܗ ܕܡܪܝܐ ܥܠ ܝܘܢܢ ܒܪ ܡܬܝ ܠܡܐܡܪ", passage.text,
                   "otext text-orig-full = {g_cons_utf8}{trailer}, trailing whitespace stripped"
      assert_equal "syc", passage.language
    end

    def test_a_superscription_rides_as_verse_zero
      manasseh = parse_urn("#{URN}ormana")
      assert_equal "#{URN}ormana:1.0", manasseh.passages.first.urn
      assert_equal "ܨܠܘܬܐ ܕܡܢܫܐ", manasseh.passages.first.text
      refute_equal manasseh.passages.first.text, parse_urn("#{URN}ormanb").passages.first.text,
                   "the A and B versions are different texts — sibling documents, never merged"
    end

    def test_a_discontiguous_verse_renders_its_own_slots_only
      # Deut 14:16 and 14:17 interleave in the Syriac verse order
      # (16a 17a 16b 17b — README); each verse node is two slot ranges.
      verse16 = passage_at("#{URN}deuteronomy", "#{URN}deuteronomy:14.16")
      assert_equal "ܘܥܘܕܐ ܘܩܦܘܦܐ ܘܟܘܟܒܝ", verse16.text
      assert_equal([114_381, 114_382, 114_386, 114_387, 114_388, 114_389],
                   verse16.annotations["tokens"].map { |t| t["n"] })
      assert_equal [[114_381, 114_382], [114_386, 114_389]], verse16.annotations["slot_ranges"],
                   "the gap is recorded, not papered over"
      refute passage_at("#{URN}deuteronomy", "#{URN}deuteronomy:14.1").annotations.key?("slot_ranges")
    end

    def test_tokens_carry_the_morphology_verbatim
      passage = passage_at("#{URN}jonah", "#{URN}jonah:1.1")
      conj, verb = passage.annotations["tokens"].first(2)
      assert_equal 274_056, conj["n"]
      assert_equal "ܘ", conj["form"]
      refute conj.key?("trailer"), "a proclitic carries no trailer — absent, not empty"
      assert_equal "W", conj["lex"]
      assert_equal "and", conj["gloss"]
      assert_equal "conj", conj["sp"]
      assert_equal "ܗܘܐ", verb["form"]
      assert_equal "verb", verb["sp"]
      %w[vs vt ps gn nu].each { |key| assert verb.key?(key), "the verb carries #{key}" }
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "etcbc-syriac", name: "ETCBC Syriac Corpus",
        adapter_class: "Nabu::Adapters::EtcbcSyriac", license_class: "nc"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 5, first.added
      assert_equal 0, first.errored
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def passage_at(document_urn, passage_urn)
      passage = parse_urn(document_urn).find { |p| p.urn == passage_urn }
      refute_nil passage, "expected #{passage_urn} in #{document_urn}"
      passage
    end
  end
end
