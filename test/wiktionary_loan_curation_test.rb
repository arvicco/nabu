# frozen_string_literal: true

require "test_helper"
require "json"

# The Wiktionary loan-category curation reader: turns the MediaWiki API's
# category-member lists and page revisions into the curated loan rows of
# config/etruscan_loans.yml (the sabellic-loans recipe, made replayable).
# Fixture: trimmed REAL API responses (test/fixtures/etruscan-loans/
# README.md) — ten Latin members covering every etymon shape the live
# curation met, plus the non-lemma members the reader excludes.
class WiktionaryLoanCurationTest < Minitest::Test
  API = File.join(Nabu::TestSupport.fixtures("etruscan-loans"), "api")

  def json(name) = JSON.parse(File.read(File.join(API, name)))

  def result
    @result ||= Nabu::WiktionaryLoanCuration.new(source_code: "ett").curate(
      borrowed: json("members-borrowed.json"), derived: json("members-derived.json"),
      revisions: json("revisions.json")
    )
  end

  def row(latin) = result.rows.find { |r| r.latin == latin } || flunk("#{latin} missing")

  def test_main_namespace_members_become_rows_in_title_order
    assert_equal %w[Ahala Annaeus Aprilis Aulus autumnus Caere capus Maso Roma titulo], result.rows.map(&:latin)
  end

  def test_borrowed_wins_where_the_categories_overlap_and_the_overlap_is_counted
    assert_equal %w[Annaeus Aulus capus Roma], result.rows.select { |r| r.relation == "borrowed" }.map(&:latin)
    assert_equal "derived", row("Caere").relation
    assert_equal 4, result.overlap, "every borrowed member also sits in the derived superset"
  end

  def test_non_lemma_members_are_excluded_and_named
    assert_equal ["Reconstruction:Latin/piltrum", "Category:Latin terms borrowed from Etruscan"], result.excluded
  end

  def test_the_classic_templates_give_the_etymon
    assert_equal "𐌀𐌅𐌋𐌄", row("Aulus").etymon
    assert_equal "𐌀𐌍𐌀𐌄", row("Annaeus").etymon, "{{bor+|nocap=1|la|ett|…}} — named params anywhere"
    assert_equal %w[𐌖𐌓𐌐𐌀 apru], [row("Aprilis").etymon, row("Aprilis").translit]
  end

  def test_the_ety_template_gives_the_etymon
    assert_equal "𐌊𐌀𐌉𐌔𐌓𐌀", row("Caere").etymon
    assert_equal %w[𐌌𐌀𐌔𐌖 Masu], [row("Maso").etymon, row("Maso").translit]
  end

  def test_the_first_stated_form_wins_over_an_earlier_dash
    assert_equal "𐌀𐌕𐌖𐌍𐌄", row("autumnus").etymon, "{{der|la|ett|-}} first, {{der|la|ett|𐌀𐌕𐌖𐌍𐌄}} after"
    assert_equal "𐌓𐌖𐌌𐌀", row("Roma").etymon, "{{bor|la|ett|-}} plus the ety template's ett:𐌓𐌖𐌌𐌀"
  end

  def test_an_unstated_etymon_is_declared_never_guessed
    assert_nil row("Ahala").etymon
    assert_equal "unstated", row("Ahala").no_etymon, "ett:- — Etruscan named, no form cited"
    assert_equal "unstated", row("capus").no_etymon, "a form hidden in an HTML comment is not cited"
  end

  def test_a_member_without_an_etruscan_etymology_template_is_declared
    assert_nil row("titulo").etymon
    assert_equal "no-template", row("titulo").no_etymon
  end
end
