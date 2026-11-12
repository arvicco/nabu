# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::LaneCoverage — the doctor's lane check: config flags vs
  # the lane's built scope vs per-source row presence. The Nov 2026
  # crash-loss incident left the cjk lane EMPTY with an empty scope for
  # days while every flag stood; nothing compared the three, so the loss
  # read as "no substring search for those sources" instead of a finding.
  class LaneCoverageTest < Minitest::Test
    include StoreTestDB

    Coverage = Nabu::Store::LaneCoverage
    Indexer = Nabu::Store::Indexer

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @han = source("han", "時乘六龍以御天")
      @bare = source("bare", "ascii only text")
    end

    def teardown
      @fulltext.disconnect
    end

    def source(slug, text)
      src = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "open")
      doc = Nabu::Store::Document.create(source_id: src.id, urn: "urn:#{slug}", title: "t", language: "lzh",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "urn:#{slug}:1", sequence: 0, language: "lzh",
                                  text: text, text_normalized: text, content_sha256: "x", revision: 1,
                                  withdrawn: false, annotations_json: "{}")
      src
    end

    def build!(cjk: [], fuzzy: [])
      Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, cjk_slugs: cjk, fuzzy_slugs: fuzzy)
    end

    def findings(cjk: [], fuzzy: [])
      Coverage.findings(catalog: @catalog, fulltext: @fulltext, cjk_slugs: cjk, fuzzy_slugs: fuzzy)
              .map { |finding| Triple.new(finding) }
    end

    # A finding as [lane, slug, problem], its message still at hand.
    Triple = Struct.new(:finding) do
      def to_triple = [finding.lane, finding.slug, finding.problem]
      def message = finding.message
    end

    def test_a_lane_built_to_its_flags_with_rows_is_clean
      build!(cjk: %w[han], fuzzy: %w[han])
      assert_empty findings(cjk: %w[han], fuzzy: %w[han])
    end

    def test_a_flag_missing_from_the_built_scope_is_a_finding
      build!(cjk: [])
      found = findings(cjk: %w[han])
      assert_equal [[:cjk, "han", :unbuilt]], found.map(&:to_triple)
      assert_match(/flagged but absent from the built scope/, found.first.message)
    end

    def test_a_scope_row_without_its_flag_is_a_finding
      build!(fuzzy: %w[han])
      assert_equal [[:trigram, "han", :deflagged]], findings.map(&:to_triple)
    end

    def test_a_flagged_in_scope_source_with_zero_rows_is_loud
      build!(cjk: %w[han bare], fuzzy: %w[bare])
      @fulltext[Indexer::TRIGRAM_TABLE].delete # the trigram lane emptied under its scope row

      found = findings(cjk: %w[han bare], fuzzy: %w[bare])
      assert_equal [[:cjk, "bare", :empty], [:trigram, "bare", :empty]].sort,
                   found.map(&:to_triple).sort
      assert_match(/ZERO lane rows/, found.first.message)
    end

    def test_an_absent_lane_with_flags_is_a_finding_per_flag
      build!(cjk: %w[han])
      @fulltext.drop_table(Indexer::CJK_TABLE)
      @fulltext.drop_table(Indexer::CJK_SCOPE_TABLE)

      assert_equal [[:cjk, "han", :absent]], findings(cjk: %w[han]).map(&:to_triple)
    end

    def test_an_absent_lane_without_flags_is_honest_silence
      @fulltext.disconnect
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      assert_empty findings
    end
  end
end
