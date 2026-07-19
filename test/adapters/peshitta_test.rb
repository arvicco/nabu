# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Peshitta (P31-4) — the ETCBC Peshitta OT over the
  # text-fabric family: FOURTH registrant, document = book, passage =
  # verse, syc text NFC-normalized at the boundary (house rule — syc is
  # not on the exemption list), the A/B manuscript recensions as honest
  # sibling documents. Fixtures are byte-verbatim tf/0.2 slices (Obadiah,
  # Jonah, Ruth, both Prayer-of-Manasseh recensions) at upstream commit
  # 9850f5ad — see test/fixtures/peshitta/README.md for the trim recipe.
  class PeshittaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("peshitta")

    def conformance_adapter
      Nabu::Adapters::Peshitta.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "peshitta"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_peshitta_disabled_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["peshitta"]
      refute_nil entry, "peshitta must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "peshitta", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_the_about_md_grant_verbatim
      manifest = Nabu::Adapters::Peshitta.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license,
                      "The plain text of the Peshitta, its conversion to Text-Fabric format, " \
                      "is subject to the CC-BY-NC license",
                      "the docs/about.md grant, verbatim"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census (otype.tf rides the fixture WHOLE — the census of record) -----

    def test_the_whole_otype_census_matches_the_briefed_numbers_exactly
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.2"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 426_835, counts["word"]
      assert_equal 65, counts["book"], "incl. the deuterocanon and the A/B recension pairs"
      assert_equal 1_269, counts["chapter"]
      assert_equal 31_341, counts["verse"]
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_node
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:peshitta:jon
        urn:nabu:peshitta:ob
        urn:nabu:peshitta:orm_a
        urn:nabu:peshitta:orm_b
        urn:nabu:peshitta:ru
      ], refs.map(&:id), "book sigla downcased verbatim, underscores and all"
      assert_equal "Jon", refs.first.metadata["book"]
      assert_equal "Jonah", refs.first.metadata["book_en"]
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_book_chapter_verse_grain
      jonah = parse_urn("urn:nabu:peshitta:jon")
      assert_equal 48, jonah.size
      assert_equal "Jonah", jonah.title, "book@en names the document"
      assert_equal "syc", jonah.language
      assert_equal 21, parse_urn("urn:nabu:peshitta:ob").size, "Obadiah — one chapter, 21 verses"
      assert_equal 86, parse_urn("urn:nabu:peshitta:ru").size
    end

    def test_the_versification_is_masoretic_measured_not_assumed
      jonah = parse_urn("urn:nabu:peshitta:jon")
      chapter1 = jonah.count { |p| p.urn.start_with?("urn:nabu:peshitta:jon:1.") }
      chapter2 = jonah.count { |p| p.urn.start_with?("urn:nabu:peshitta:jon:2.") }
      assert_equal [16, 11], [chapter1, chapter2],
                   "Jonah 1:16 + 2:11 — the MT split (English bibles say 1:17/2:10); " \
                   "the ot-hub seventh leg rests on this measurement"
    end

    def test_verse_text_is_the_corpus_own_word_trailer_rendering
      passage = passage_at("urn:nabu:peshitta:jon", "urn:nabu:peshitta:jon:1.1")
      assert_equal "ܘܗܘܐ ܦܬܓܡܗ ܕܡܪܝܐ ܥܠ ܝܘܢܢ ܒܪ ܡܬܝ ܠܡܐܡܪ", passage.text,
                   "otext's text-orig-full = {word}{trailer}, trailing whitespace stripped"
      assert_equal "syc", passage.language
    end

    def test_syriac_text_is_nfc_normalized_at_the_boundary
      # Ruth carries 8 of upstream's ~492 non-NFC word forms (seyame +
      # point in non-canonical combining order). syc is NOT on the NFC
      # exemption list (that is hbo/arc only, the Masoretic ruling), so the
      # house rule applies: NFC at the adapter boundary.
      upstream = "ܒܥܠܗ̣̇" # Ru 1:5, word slot 282789, bytes as shipped
      refute upstream.unicode_normalized?(:nfc), "the fixture must carry the offending bytes"
      passage = passage_at("urn:nabu:peshitta:ru", "urn:nabu:peshitta:ru:1.5")
      assert passage.text.unicode_normalized?(:nfc)
      assert_includes passage.text, Nabu::Normalize.nfc(upstream),
                      "the word is present in canonical combining order, not dropped"
      token = passage.annotations["tokens"].find { |t| t["n"] == 282_789 }
      assert_equal Nabu::Normalize.nfc(upstream), token["form"], "token forms ride the same NFC boundary"
    end

    def test_tokens_carry_the_word_and_transliteration_lanes
      passage = passage_at("urn:nabu:peshitta:jon", "urn:nabu:peshitta:jon:1.1")
      token = passage.annotations["tokens"].first
      assert_equal "ܘܗܘܐ", token["form"]
      assert_equal " ", token["trailer"], "interword material verbatim"
      assert_equal "WHW>", token["etcbc"], "the ETCBC transliteration lane rides beside the script"
      assert_equal 266_425, token["n"], "the stable TF slot number"
    end

    # -- the A/B manuscript recensions ---------------------------------------

    def test_recension_books_are_sibling_documents_with_the_witness_letter
      manasseh_a = parse_urn("urn:nabu:peshitta:orm_a")
      manasseh_b = parse_urn("urn:nabu:peshitta:orm_b")
      assert_equal "A", manasseh_a.metadata["witness"], "witness.tf book-grain value, verbatim"
      assert_equal "B", manasseh_b.metadata["witness"]
      assert_equal 16, manasseh_a.size
      assert_equal 16, manasseh_b.size
      refute_equal manasseh_a.passages.first.text, manasseh_b.passages.first.text,
                   "the two recensions carry genuinely different text — never merged"
      assert_equal "A", manasseh_a.passages.first.annotations["witness"],
                   "the verse-grain witness stamp rides annotations verbatim"
      refute parse_urn("urn:nabu:peshitta:jon").metadata.key?("witness"),
             "a single-recension book carries no witness key — absent is absent"
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = peshitta_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 5, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged books must not fake content revisions"
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

    def peshitta_source
      Nabu::Store::Source.create(
        slug: "peshitta", name: "Peshitta OT (ETCBC)",
        adapter_class: "Nabu::Adapters::Peshitta", license_class: "nc"
      )
    end
  end
end
