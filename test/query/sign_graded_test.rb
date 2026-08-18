# frozen_string_literal: true

require "test_helper"

# Query::SignGraded (P77-r16, sign-learning survey P-3): the
# sign-coverage graded lane — ATF passages whose resolved OSL sign
# inventory ⊆ the taught set (± N strangers), candidates from the
# passage_signs rarest-sign index, exact-verified, cleanest-first.
# The rig uses the REAL OSL fixture (ŠEŠ carries ses/sis…, AK carries
# ak/ag…, |A.BARA₂| carries idₓ), source slug cdli — one of the
# SIGN_SOURCES the index scopes to.
class SignGradedTest < Minitest::Test
  include StoreTestDB

  OSL_FIXTURE = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")

  def setup
    @catalog = store_test_db
    @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    @sign_list = Nabu::SignList.load(OSL_FIXTURE)
    @source = Nabu::Store::Source.create(
      slug: "cdli", name: "CDLI", adapter_class: "TestAdapter", license_class: "open"
    )
    @outside = Nabu::Store::Source.create(
      slug: "kanripo", name: "Kanripo", adapter_class: "TestAdapter", license_class: "open"
    )
    @doc = Nabu::Store::Document.create(
      source_id: @source.id, urn: "urn:d", title: "Tablet", language: "sux",
      content_sha256: "x", revision: 1
    )
    [
      ["urn:d:1", "ses"],            # ŠEŠ alone — the cleanest reading
      ["urn:d:2", "ses ak"],         # ŠEŠ + AK
      ["urn:d:3", "ses idx(|A.BARA2|)"], # ŠEŠ + |A.BARA₂| via a qualified valueₓ(SIGN)
      ["urn:d:4", "ses x-ak"],       # broken token — a stray, never graded
      ["urn:d:5", "3(disz) ses"]     # numbers are readable, not strays
    ].each_with_index do |(urn, text), i|
      Nabu::Store::Passage.create(
        document_id: @doc.id, urn: urn, sequence: i, language: "sux",
        text: text, text_normalized: text, content_sha256: "x", revision: 1
      )
    end
    outside_doc = Nabu::Store::Document.create(
      source_id: @outside.id, urn: "urn:k", title: "外", language: "lzh",
      content_sha256: "x", revision: 1
    )
    Nabu::Store::Passage.create(
      document_id: outside_doc.id, urn: "urn:k:1", sequence: 0, language: "lzh",
      text: "ses", text_normalized: "ses", content_sha256: "x", revision: 1
    )
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, sign_list: @sign_list)
    @graded = Nabu::Query::SignGraded.new(catalog: @catalog, fulltext: @fulltext,
                                          sign_list: @sign_list)
  end

  def teardown = @fulltext.disconnect

  def test_subset_hits_only_and_cleanest_first
    outcome = @graded.run(signset: "ŠEŠ, AK")
    assert_predicate outcome, :indexed
    assert_equal %w[urn:d:1 urn:d:5 urn:d:2], outcome.results.map(&:urn),
                 "full-coverage passages only, fewest-signs first; numbers ride free"
    assert_equal [], outcome.results.first.foreign
  end

  def test_values_expand_to_their_signs
    # Teaching the READING `ses` implies knowing ŠEŠ — the value expands.
    outcome = @graded.run(signset: "ses ak")
    assert_includes outcome.results.map(&:urn), "urn:d:2"
  end

  def test_max_foreign_admits_and_names_the_strangers
    outcome = @graded.run(signset: "ŠEŠ", max_foreign: 1)
    with_ak = outcome.results.find { |r| r.urn == "urn:d:2" }
    refute_nil with_ak, "one stranger admitted under --max-foreign 1"
    assert_equal ["AK"], with_ak.foreign, "the stranger is NAMED — it is the lesson"
    assert_includes outcome.results.map(&:urn), "urn:d:3", "|A.BARA₂| is the other one-stranger hit"
  end

  def test_broken_passages_never_grade
    outcome = @graded.run(signset: "ŠEŠ, AK", max_foreign: 3)
    refute_includes outcome.results.map(&:urn), "urn:d:4",
                    "a stray (broken x-) token disqualifies the passage — damaged text is not a drill"
  end

  def test_only_sign_sources_are_indexed
    outcome = @graded.run(signset: "ŠEŠ")
    refute_includes outcome.results.map(&:urn), "urn:k:1",
                    "a non-SIGN_SOURCES passage never enters the sign index"
  end

  def test_unknown_signset_entries_error_loudly
    error = assert_raises(Nabu::Error) { @graded.run(signset: "ŠEŠ, NOPESIGN") }
    assert_includes error.message, "NOPESIGN", "a curriculum typo must never silently shrink coverage"
  end

  def test_absent_index_is_an_honest_non_answer
    @fulltext.drop_table(Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE)
    outcome = @graded.run(signset: "ŠEŠ")
    refute_predicate outcome, :indexed
    assert_empty outcome.results
  end

  # P77-r16b (the 2026-08-18 live "hang" — a burman-concordance sync
  # silently began tokenizing the whole ATF corpus): the heavy sign
  # bootstrap fires ONLY on a sign corpus's own refresh, never on an
  # unrelated source's sync.
  def test_the_sign_bootstrap_never_fires_on_a_non_sign_source_refresh
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext)
    Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: fulltext,
                                         slug: "kanripo", sign_list: @sign_list)
    refute fulltext.table_exists?(Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE),
           "an unrelated sync must never be ambushed by hours of sign indexing"
  ensure
    fulltext&.disconnect
  end

  def test_the_sign_bootstrap_fires_on_a_sign_sources_own_refresh
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext)
    Nabu::Store::Indexer.refresh_source!(catalog: @catalog, fulltext: fulltext,
                                         slug: "cdli", sign_list: @sign_list)
    assert fulltext.table_exists?(Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE),
           "the sign corpora pay their own indexing cost"
    assert_operator fulltext[Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE].count, :>, 0
  ensure
    fulltext&.disconnect
  end

  def test_rebuild_without_a_sign_list_builds_no_sign_tables
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: fulltext)
    refute fulltext.table_exists?(Nabu::Store::Indexer::PASSAGE_SIGNS_TABLE),
           "no osl = no sign index — the honest absent answer, never a guess"
    refute fulltext.table_exists?(Nabu::Store::Indexer::SIGN_POSTINGS_TABLE)
  ensure
    fulltext&.disconnect
  end
end
