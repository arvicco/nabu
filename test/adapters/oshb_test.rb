# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Oshb (P26-3) — the Open Scriptures Hebrew Bible: the
  # Westminster Leningrad Codex as the alignment hub's Masoretic witness.
  # Fixtures are byte-verbatim slices of openscriptures/morphhb@3d15126f
  # (Gen 1+31, Ruth 1, Ps 23, Jer 10, plus a trimmed VerseMap.xml to pin
  # the non-book exclusion). The NFC-exemption seam itself is exercised by
  # the conformance suite running over these genuinely non-NFC fixtures.
  class OshbTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("oshb")

    def conformance_adapter
      Nabu::Adapters::Oshb.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "oshb"
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_oshb_and_manifest_agrees
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["oshb"]
      refute_nil entry, "oshb must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal "oshb", entry.adapter_class.manifest.id
    end

    def test_manifest_carries_both_license_layers_verbatim
      manifest = Nabu::Adapters::Oshb.manifest
      assert_equal "open", manifest.license_class, "WLC text is public domain — the governing class"
      assert_includes manifest.license, "public domain"
      assert_includes manifest.license, "Creative Commons Attribution 4.0",
                      "the morphology layer's CC BY grant rides the manifest"
      assert_includes manifest.license, "credit the Open Scriptures Hebrew Bible Project",
                      "the attribution credit is carried verbatim"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_sorted_and_excludes_the_verse_map
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:oshb:gen
        urn:nabu:oshb:jer
        urn:nabu:oshb:ps
        urn:nabu:oshb:ruth
      ], refs.map(&:id), "VerseMap.xml is upstream versification metadata, never a book"
      assert_equal(%w[Gen Jer Ps Ruth], refs.map { |ref| ref.metadata["book"] })
    end

    def test_discover_yields_nothing_from_a_workdir_without_wlc
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- the byte-verbatim storage + folded findability, end to end ----------

    def test_ruth_1_1_survives_the_load_byte_identical
      catalog = store_test_db
      loader = Nabu::Store::Loader.new(db: catalog, source: oshb_source)
      loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)

      stored = catalog[:passages].where(urn: "urn:nabu:oshb:ruth:1.1").first
      refute_nil stored
      refute stored[:text].unicode_normalized?(:nfc),
             "the stored bytes keep the WLC mark order NFC would rewrite"
      parsed = parse_urn("urn:nabu:oshb:ruth").passages.first.text
      assert_equal parsed.bytes, stored[:text].bytes, "storage is byte-transparent"
    end

    def test_folded_hebrew_lookup_finds_the_pointed_verse
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Loader.new(db: catalog, source: oshb_source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      # An unpointed modern query (bare letters) must find the pointed,
      # byte-verbatim Masoretic verse: search folds both sides through NFC +
      # mark strip, so the storage exemption never costs find-ability.
      hits = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext).run("בראשית")
      assert_includes hits.map(&:urn), "urn:nabu:oshb:gen:1.1"
    ensure
      fulltext&.disconnect
    end

    def test_strongs_lemmas_index_into_passage_lemmas_verbatim
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Loader.new(db: catalog, source: oshb_source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      # The lemma lane carries the augmented Strong's id verbatim (no
      # headword exists upstream to invent): Gen 1:1's first word is b/7225.
      row = fulltext[:passage_lemmas].where(lemma_raw: "b/7225").first
      refute_nil row, "expected a passage_lemmas row for the augmented Strong's id b/7225"
      assert_equal "urn:nabu:oshb:gen:1.1", row[:urn]
      assert_equal "hbo", row[:language]
      arc = fulltext[:passage_lemmas].where(language: "arc").count
      assert_operator arc, :>, 0, "Jer 10:11's Aramaic tokens index under arc"
    ensure
      fulltext&.disconnect
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = oshb_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged WLC books must not fake content revisions"
    end

    # -- languages ------------------------------------------------------------

    def test_documents_are_hebrew_with_the_native_book_code_as_title
      document = parse_urn("urn:nabu:oshb:ruth")
      assert_equal "hbo", document.language
      assert_equal "Ruth", document.title
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      adapter.parse(ref)
    end

    def oshb_source
      Nabu::Store::Source.create(
        slug: "oshb", name: "Open Scriptures Hebrew Bible",
        adapter_class: "Nabu::Adapters::Oshb", license_class: "open"
      )
    end
  end
end
