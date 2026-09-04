# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::PerseusFarsilit (P95-4): classical Persian — Hafez's
# Divan. The namespace delta plus the slug/code split: upstream slugs
# are perseus-far<n>, the house language code is "fas" (the
# openiti/kitab convention). Proper CTS upstream (__cts__.xml + 4-deep
# cRefPattern), so no legacy accommodations — the ger1 translation
# stays out by the eng-only house rule.
class PerseusFarsilitTest < Minitest::Test
  include AdapterConformance

  WORKDIR = Nabu::TestSupport.fixtures("perseus-farsilit")
  DIVAN = "urn:cts:farsiLit:hafez.divan.perseus-far1"
  DIVAN_ENG = "urn:cts:farsiLit:hafez.divan.perseus-eng1"

  def conformance_adapter
    Nabu::Adapters::PerseusFarsilit.new
  end

  def conformance_workdir
    WORKDIR
  end

  def conformance_expected_source_id
    "perseus-farsilit"
  end

  def test_manifest_is_the_farsilit_manifest
    manifest = Nabu::Adapters::PerseusFarsilit.manifest
    assert_equal "perseus-farsilit", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PerseusDL/canonical-farsiLit", manifest.upstream_url
  end

  def test_default_discover_yields_the_persian_original_only
    ids = Nabu::Adapters::PerseusFarsilit.new.discover(WORKDIR).map(&:id)
    assert_equal [DIVAN], ids, "perseus-far<n> slugs are the original; ger/eng stay out flag-off"
  end

  def test_translations_flag_adds_english_never_german
    ids = Nabu::Adapters::PerseusFarsilit.new(translations: true).discover(WORKDIR).map(&:id)
    assert_equal [DIVAN_ENG, DIVAN].sort, ids.sort,
                 "eng joins behind the flag; ger1 stays out (the eng-only house rule)"
  end

  def test_divan_parses_with_fas_language_and_cts_title
    adapter = Nabu::Adapters::PerseusFarsilit.new
    ref = adapter.discover(WORKDIR).find { |r| r.id == DIVAN }
    document = adapter.parse(ref)
    assert_equal "fas", document.language, "house code fas, not the slug's far"
    assert_operator document.count, :>=, 20, "seg-grain citations across the first chapters"
    assert_match(/دل|عشق|ساقی|الا/, document.map(&:text).join(" "),
                 "the Divan's Persian text is served")
  end
end
