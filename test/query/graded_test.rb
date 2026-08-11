# frozen_string_literal: true

require "test_helper"

# Query::Graded (P72-1, Edubba FR-1): the graded-reading lane — passages
# whose distinct Han chars ⊆ the charset (± N strangers), candidates from
# the passage_chars rarest-char index, exact-verified, cleanest-first.
class GradedTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @source = Nabu::Store::Source.create(
      slug: "cbeta", name: "CBETA", adapter_class: "TestAdapter", license_class: "open"
    )
    @doc = Nabu::Store::Document.create(
      source_id: @source.id, urn: "urn:d", title: "析津志", language: "lzh",
      content_sha256: "x", revision: 1
    )
    [
      ["urn:d:1", "子曰學而"], # 4 chars, one (學) folds to 学
      ["urn:d:2", "子曰"], # fully inside a {子,曰} set
      ["urn:d:3", "子曰不亦說乎"], # 4 strangers beyond {子,曰}
      ["urn:d:4", "天地"] # disjoint
    ].each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(
        document_id: @doc.id, urn: urn, sequence: i, language: "lzh",
        text: text, text_normalized: text, content_sha256: "x", revision: 1
      )
    end
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    @graded = Nabu::Query::Graded.new(catalog: @catalog, fulltext: @fulltext)
  end

  def teardown = @fulltext.disconnect

  def test_subset_hits_only_and_cleanest_first
    outcome = @graded.run(charset: "子曰學而天")
    assert_predicate outcome, :indexed
    assert_equal %w[urn:d:2 urn:d:1], outcome.results.map(&:urn),
                 "only full-coverage passages, shortest reading first"
    assert_equal [], outcome.results.first.foreign
  end

  def test_max_foreign_admits_and_names_the_strangers
    outcome = @graded.run(charset: "子曰", max_foreign: 2)
    urns = outcome.results.map(&:urn)
    assert_includes urns, "urn:d:2"
    assert_includes urns, "urn:d:1", "學而 are the two admitted strangers"
    refute_includes urns, "urn:d:3", "four strangers exceed the allowance"
    strangers = outcome.results.find { |r| r.urn == "urn:d:1" }.foreign
    assert_equal %w[學 而].sort, strangers.sort, "each hit names its strangers"
  end

  def test_charset_is_fold_aware_both_sides
    outcome = @graded.run(charset: "子曰学而")
    assert_includes outcome.results.map(&:urn), "urn:d:1",
                    "simplified 学 in the charset covers stored 學"
  end

  def test_max_foreign_ceiling_and_hanless_charset_refuse
    error = assert_raises(Nabu::Error) { @graded.run(charset: "子", max_foreign: 4) }
    assert_match(/0\.\.3/, error.message)
    assert_raises(Nabu::Error) { @graded.run(charset: "abc") }
  end

  def test_absent_index_is_an_honest_non_answer
    @fulltext.drop_table(Nabu::Store::Indexer::PASSAGE_CHARS_TABLE)
    outcome = @graded.run(charset: "子曰")
    refute_predicate outcome, :indexed
    assert_empty outcome.results
  end

  # The Edubba paper cut (2026-08-11): floor the cleanest-first order
  # above one-char fragments.
  def test_min_chars_floors_the_fragments
    outcome = @graded.run(charset: "子曰學而天地", min_chars: 3)
    assert_equal %w[urn:d:1], outcome.results.map(&:urn),
                 "the two-char 子曰 and 天地 fall below the floor; the 4-char reading stays"
  end

  def test_composes_with_a_text_query
    outcome = @graded.run("子曰", charset: "子曰學而說乎不亦")
    urns = outcome.results.map(&:urn)
    assert_includes urns, "urn:d:1"
    refute_includes urns, "urn:d:4", "the text query bounds the candidates"
  end
end
