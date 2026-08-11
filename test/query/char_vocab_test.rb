# frozen_string_literal: true

require "test_helper"

# Query::CharVocab (P72-4, Edubba FR-4): the per-document character
# frequency profile for unlemmatized CJK + the coverage instrument.
class CharVocabTest < Minitest::Test
  include StoreTestDB

  def setup
    @catalog = store_test_db
    source = Nabu::Store::Source.create(
      slug: "kanripo", name: "KR", adapter_class: "TestAdapter", license_class: "attribution"
    )
    @doc = Nabu::Store::Document.create(
      source_id: source.id, urn: "urn:nabu:kanripo:lunyu", title: "論語", language: "lzh",
      content_sha256: "x", revision: 1
    )
    %w[子曰學而 子曰不慍].each_with_index do |text, i|
      Nabu::Store::Passage.create(
        document_id: @doc.id, urn: "#{@doc.urn}:#{i}", sequence: i, language: "lzh",
        text: text, text_normalized: text, content_sha256: "x", revision: 1
      )
    end
    @vocab = Nabu::Query::CharVocab.new(catalog: @catalog)
  end

  def test_profiles_character_frequencies_with_hapax
    profile = @vocab.run(@doc.urn)
    assert_equal 8, profile.total
    assert_equal 6, profile.distinct
    assert_equal 2, profile.passages
    top = profile.top.first
    assert_includes %w[子 曰], top.char, "the recurring opener leads"
    assert_equal 2, top.count
    assert_equal 4, profile.hapax_count
    assert_includes profile.hapax, "學"
  end

  def test_coverage_names_the_share_and_the_strangers
    profile = @vocab.run(@doc.urn, coverage: "子曰")
    c = profile.coverage
    assert_equal 50.0, c.occurrence_pct, "4 of 8 occurrences inside {子,曰}"
    assert_equal 2, c.distinct_covered
    assert_equal 6, c.distinct_total
    assert_equal 4, c.strangers.size
    assert_includes c.strangers.map(&:char), "學"
  end

  def test_unknown_document_is_nil_and_hanless_coverage_refuses
    assert_nil @vocab.run("urn:nabu:nope")
    assert_raises(Nabu::Error) { @vocab.run(@doc.urn, coverage: "abc") }
  end

  def test_json_payload_mirrors_the_profile
    payload = Nabu::Query::CharVocab.json_payload(@doc.urn, @vocab.run(@doc.urn, coverage: "子曰"))
    assert_equal 8, payload.dig("profile", "total")
    assert_equal 50.0, payload.dig("profile", "coverage", "occurrence_pct")
    assert_equal "論語", payload.dig("profile", "title")
  end
end
