# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::DergeTengyur (P48-1) — the Digital Derge Tengyur riding
  # the same `esukhia-text` family as the Kangyur. Fixtures are real trimmed
  # volume files at the pinned commit (see
  # test/fixtures/derge-tengyur/README.md); they carry what the Kangyur
  # trims do not — the BOM, # peydurma note anchors, the one real [X] error
  # candidate, and the one real precomposed U+0F75.
  class DergeTengyurTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("derge-tengyur")

    def conformance_adapter
      Nabu::Adapters::DergeTengyur.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "derge-tengyur"
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_derge_tengyur_and_manifest_agrees
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["derge-tengyur"]
      refute_nil entry, "derge-tengyur must be registered in config/sources.yml"
      assert entry.wired, "flipped 2026-07-28 (owner ruling; first sync verified live)"
      assert_equal "manual", entry.sync_policy
      assert_equal %w[tibetan buddhist], entry.axes
      assert_equal "open", entry.adapter_class.manifest.license_class
      assert_includes entry.adapter_class.manifest.license, "mechanical reproduction of a Public domain work"
    end

    # -- discover: the Tengyur rides the same family --------------------------

    def test_discover_yields_one_ref_per_toh_marker_in_corpus_order
      assert_equal %w[
        urn:nabu:derge-tengyur:toh1109
        urn:nabu:derge-tengyur:toh1110
        urn:nabu:derge-tengyur:toh1113
        urn:nabu:derge-tengyur:toh4452
        urn:nabu:derge-tengyur:toh4453
      ], conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_tengyur_toh_numbers_are_disjoint_from_the_kangyur_range
      # Tohoku numbers the Kangyur 1–1108 and the Tengyur from 1109 — the
      # crosswalk key stays unambiguous across the two sources. Verified
      # here over the fixture corpus; the first real sync re-verifies at
      # scale (kangyur vol 101 ends at D1108, tengyur vol 001 opens D1109).
      numbers = conformance_adapter.discover(FIXTURES).map { |ref| ref.id[/toh(\d+)/, 1].to_i }
      assert numbers.all? { |n| n >= 1109 }, "every fixture Tengyur Toh number sits above the Kangyur range"
    end

    # -- parse: BOM + first passage -------------------------------------------

    def test_the_bom_is_stripped_and_the_first_passage_cites_folio_one_b
      document = parse_urn("urn:nabu:derge-tengyur:toh1109")
      assert_equal "xct", document.language
      assert_equal 45, document.size
      first = document.first
      assert_equal "urn:nabu:derge-tengyur:toh1109:1b.1", first.urn
      assert first.text.start_with?("༄༅༅། །རྒྱ་གར་སྐད་དུ། བི་ཤིཥྚ་སྟ་བཿ།")
      refute_includes first.text, "﻿"
    end

    # -- parse: the multi-volume rule on the Tengyur side ---------------------

    def test_toh1113_spans_both_volume_files_with_volume_prefixed_refs
      document = parse_urn("urn:nabu:derge-tengyur:toh1113")
      assert_equal [1, 212], document.metadata["volumes"]
      assert_equal 10, document.size
      assert_equal "urn:nabu:derge-tengyur:toh1113:1.45a.3", document.first.urn,
                   "a multi-volume document volume-prefixes every ref (pagination restarts per volume)"
      assert_equal "urn:nabu:derge-tengyur:toh1113:1.256b.1", document.to_a.last.urn
    end

    def test_toh1110_ends_where_toh1113_begins_on_the_same_line
      last = parse_urn("urn:nabu:derge-tengyur:toh1110").to_a.last
      assert_equal "urn:nabu:derge-tengyur:toh1110:45a.3", last.urn
      assert last.text.end_with?("གཏན་ལ་ཕབ་པའོ།། ")
    end

    # -- parse: peydurma note anchors -----------------------------------------

    def test_note_anchors_are_extracted_with_their_offsets
      first = parse_urn("urn:nabu:derge-tengyur:toh1113").first
      refute_includes first.text, "#"
      assert_equal [0], first.annotations["note_marks"],
                   "the real {D1113}#༄༅༅ line anchors a note at offset 0"
      assert first.text.start_with?("༄༅༅། །རྒྱ་གར་སྐད་དུ། དེ་ཝ་ཨ་ཏི་ཤ་ཡ")
    end

    # -- parse: the error candidate -------------------------------------------

    def test_the_error_candidate_keeps_its_reading_and_rides_the_apparatus
      document = parse_urn("urn:nabu:derge-tengyur:toh4453")
      passage = document.find { |p| p.urn.end_with?(":239a.5") }
      refute_nil passage
      refute_includes passage.text, "["
      app = passage.annotations["apparatus"].find { |a| a["kind"] == "error_candidate" }
      assert_equal "པུཥྦཱུ", app["reading"]
      assert_equal "པུཥྦཱུ", passage.text[app["offset"], app["reading"].length]
    end

    def test_suggestion_pairs_keep_the_original_reading
      document = parse_urn("urn:nabu:derge-tengyur:toh4453")
      passage = document.find { |p| p.urn.end_with?(":127b.2") }
      app = passage.annotations["apparatus"].find { |a| a["kind"] == "suggestion" }
      assert_equal "འཆིད", app["original"]
      assert_equal "འཆིང", app["suggested"]
      assert_includes passage.text, "འཆིད"
    end

    # -- NFC determinism (the U+0F75 regression) ------------------------------

    def test_the_real_precomposed_0f75_normalizes_deterministically
      # Upstream vol 001 line 4075 carries a raw U+0F75 (VOCALIC UU) —
      # composition-excluded, so NFC decomposes it to U+0F71 U+0F74. The
      # stored passage must hold the decomposed bytes, both parses identical.
      raw = File.read(Dir.glob(File.join(FIXTURES, "text", "001_*.txt")).fetch(0),
                      encoding: Encoding::UTF_8)
      assert_includes raw, "ཱུ", "the fixture must really carry the precomposed byte upstream shipped"
      passage = parse_urn("urn:nabu:derge-tengyur:toh1113")
                .find { |p| p.urn.end_with?(":1.256a.5") }
      refute_nil passage
      refute_includes passage.text, "ཱུ", "the precomposed form must not survive normalization"
      assert_includes passage.text, "ནཱུ", "the decomposed U+0F71 U+0F74 replaces it"
      again = parse_urn("urn:nabu:derge-tengyur:toh1113")
              .find { |p| p.urn.end_with?(":1.256a.5") }
      assert_equal passage.text, again.text, "byte-identical across independent parses"
    end

    def test_tibetan_precomposed_exclusions_decompose_under_the_standard_path
      # The survey's U+0F43 determinism spec, pinned as behaviour of the ONE
      # normalization boundary the adapter uses: every Tibetan precomposed
      # character is a composition exclusion, so NFC == NFD, decomposed and
      # idempotent: U+0F43 always stores as U+0F42 U+0FB7.
      assert_equal "གྷ", Nabu::Normalize.nfc("གྷ")
      assert_equal "གྷ", Nabu::Normalize.nfc("གྷ")
    end

    # -- load: idempotency ----------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = derge_source(catalog)
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

    def derge_source(_catalog)
      Nabu::Store::Source.create(
        slug: "derge-tengyur", name: "Digital Derge Tengyur",
        adapter_class: "Nabu::Adapters::DergeTengyur", license_class: "open"
      )
    end
  end
end
