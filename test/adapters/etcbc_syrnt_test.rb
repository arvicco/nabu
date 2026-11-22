# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::EtcbcSyrnt — the Syriac New Testament (ETCBC/syrnt,
  # Text-Fabric tf/0.1, a SEDRA III export) over the text-fabric family:
  # document = book, passage = verse, syc text NFC at the boundary, every
  # word-grain feature on the tokens with upstream's "NA" fillers absent.
  # Fixtures are gap-anchored tf/0.1 slices — Matthew 1 clipped,
  # Philemon, 3 John and Jude whole — see test/fixtures/etcbc-syrnt/README.md.
  class EtcbcSyrntTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("etcbc-syrnt")
    URN = "urn:nabu:etcbc-syrnt:"

    def conformance_adapter
      Nabu::Adapters::EtcbcSyrnt.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "etcbc-syrnt"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_etcbc_syrnt_unwired_until_its_first_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
      entry = registry["etcbc-syrnt"]
      refute_nil entry, "etcbc-syrnt must be registered in config/sources/"
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal Nabu::Adapters::EtcbcSyrnt, entry.adapter_class
    end

    def test_manifest_is_nc_with_the_mit_software_grant_recorded
      manifest = Nabu::Adapters::EtcbcSyrnt.manifest
      assert_equal "nc", manifest.license_class,
                   "the MIT LICENSE covers the software; the SEDRA data carries no grant → nc conservatively"
      assert_includes manifest.license, "MIT License"
      assert_includes manifest.license, "a SEDRA database export made by George A. Kiraz and James W. Bennett"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census ---------------------------------------------------------------

    def test_the_whole_otype_census
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.1"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal({ "word" => 109_640, "book" => 27, "chapter" => 260, "lexeme" => 3038, "verse" => 7957 },
                   counts)
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_node
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[#{URN}3john #{URN}jude #{URN}matt #{URN}phlm], refs.map(&:id),
                   "book names downcased verbatim"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_the_checkout_file_is_skipped_by_rule_and_a_stray_is_unrecognized
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_match(%r{tf/0\.1/__checkout__\.txt: Text-Fabric release bookkeeping}, skips.notes.join("\n"))

      Dir.mktmpdir do |work|
        FileUtils.cp_r(File.join(FIXTURES, "tf"), work)
        File.write(File.join(work, "tf", "0.1", "notes.txt"), "stray\n")
        stray = conformance_adapter.discovery_skips(work)
        assert_equal 1, stray.unrecognized
        assert_match(/notes\.txt: not a \.tf feature file/, stray.notes.join("\n"))
      end
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_english_book_name_as_title
      matt = parse_urn("#{URN}matt")
      assert_equal "Matthew", matt.title
      assert_equal "syc", matt.language
      assert_equal({ "book" => "Matt", "book_en" => "Matthew" }, matt.metadata)
      assert_equal 25, matt.size, "the fixture clips Matthew to chapter 1"
      assert_equal "3 John", parse_urn("#{URN}3john").title, "book@en 3_John, underscore as a space"
      assert_equal 25, parse_urn("#{URN}phlm").size
      assert_equal 15, parse_urn("#{URN}3john").size
      assert_equal 25, parse_urn("#{URN}jude").size
    end

    def test_verse_text_is_the_words_single_space_joined
      passage = passage_at("#{URN}matt", "#{URN}matt:1.1")
      assert_equal "ܟܬܒܐ ܕܝܠܝܕܘܬܗ ܕܝܫܘܥ ܡܫܝܚܐ ܒܪܗ ܕܕܘܝܕ ܒܪܗ ܕܐܒܪܗܡ", passage.text
      assert_equal "syc", passage.language
      assert_equal "#{URN}jude:1.25", parse_urn("#{URN}jude").passages.last.urn
    end

    def test_tokens_carry_the_features_with_the_na_fillers_absent
      book, birth = passage_at("#{URN}matt", "#{URN}matt:1.1").annotations["tokens"].first(2)
      assert_equal 1, book["n"]
      assert_equal "ܟܬܒܐ", book["form"]
      assert_equal "KTB>", book["word_etcbc"]
      assert_equal "CTBA", book["word_sedra"]
      assert_equal "ܟܬܒ", book["root"]
      assert_equal "noun", book["sp"]
      assert_equal "emphatic", book["st"]
      refute book.key?("vs"), "NA is upstream's not-applicable filler — absent, never stored"
      refute book.key?("seyame"), "the 0 flag is absent"
      refute book.key?("prefix"), "an empty prefix is absent in the format itself"
      assert_equal "ܕ", birth["prefix"], "d-ilidutheh carries the proclitic d-"
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "etcbc-syrnt", name: "ETCBC SyrNT",
        adapter_class: "Nabu::Adapters::EtcbcSyrnt", license_class: "nc"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
      assert_equal 0, first.errored
      counts = [catalog[:documents].count, catalog[:passages].count]
      assert_equal [4, 90], counts
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    # -- the nt alignment hub ---------------------------------------------------

    def test_the_syriac_nt_joins_the_nt_hub_book_for_book
      registry = Nabu::AlignmentRegistry.load(File.expand_path("../../config/alignments.yml", __dir__))
      witness = registry.work("nt").witness_for("#{URN}matt")
      refute_nil witness, "etcbc-syrnt must be an nt witness"
      assert_equal "cts-verse", witness.extractor
      assert_equal 27, witness.documents.size
      assert_equal "1PET", witness.book_for("#{URN}1peter")
      assert_equal "JAS", witness.book_for("#{URN}james")
      assert_equal "REV", witness.book_for("#{URN}rev")
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
