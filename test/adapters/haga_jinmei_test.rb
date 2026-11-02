# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# HagaJinmei adapter tests: the NIHU Haga Jinmei Dictionary Dataset
# (Zenodo 23804456, v0.1.0, CC0 1.0) — 芳賀矢一編『日本人名辞典』(1914) as
# one row per printed entry. Fixture (test/fixtures/haga-jinmei/README.md):
# the deposit's tree as ZipFetch lands it (top directory stripped), its
# CSV cut to seven real rows chosen for their shapes — plain entries, a ⇒
# cross-reference, a blank full_name, the one CSV-quoted row (a stray
# description fragment in full_name), the multi-person 式佐（岸沢） entry
# and a blank description — plus the deposit's own docs, manifest and
# schema (the rejected grains, skipped by rule).
class HagaJinmeiTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("haga-jinmei")

  def adapter = Nabu::Adapters::HagaJinmei.new

  def dictionary
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    adapter.parse(refs.first)
  end

  def entry(id) = dictionary.find { |e| e.entry_id == id } || flunk("no entry #{id}")

  def test_manifest_records_the_cc0_dedication
    manifest = adapter.manifest
    assert_equal "haga-jinmei", manifest.id
    assert_equal "open", manifest.license_class
    assert_includes manifest.license, "CC0 1.0"
    assert_includes manifest.license, "National Institutes for the Humanities"
    assert_equal "https://zenodo.org/records/23804456", manifest.upstream_url
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::HagaJinmei.content_kind
  end

  def test_one_dictionary_document_with_one_entry_per_row
    dict = dictionary
    assert_equal "haga-jinmei", dict.slug
    assert_equal "jpn", dict.language
    assert_equal %w[000001 000002 000005 000357 002562 017048 035816], dict.map(&:entry_id)
  end

  def test_the_printed_heading_is_the_headword_and_the_columns_ride_annotations
    e = entry("000002")
    assert_equal "【靄崖（高久）】", e.key_raw
    assert_equal "靄崖（高久）", e.headword
    assert_equal Nabu::Normalize.search_form("靄崖（高久）", language: "jpn"), e.headword_folded
    assert_equal "文人画家。下野国黒羽の人。名は徴、字は子遠、通称秋輔、疎外史とも号す。谷文晁に学び、江戸薬研堀に歿す。年六十。",
                 e.body
    assert_equal({ "reading" => "アイガイ", "full_name" => "高久靄崖", "page" => 1 }, e.annotations)
  end

  def test_a_bare_arrow_entry_is_a_see_reference_by_reading
    e = entry("000005")
    assert_equal "⇒ユウザン", e.body, "the printed text stays verbatim"
    assert_equal 1, e.crossrefs.size
    ref = e.crossrefs.first
    assert_equal "see", ref.kind
    assert_equal "ユウザン", ref.target
    assert_equal true, e.annotations["redirect"]
  end

  def test_blank_and_stray_columns_are_honest
    assert_nil entry("000357").annotations["full_name"], "a blank full_name is omitted"
    assert_equal "幕末-明治時代の司法官,画家。", entry("002562").annotations["full_name"],
                 "the one quoted row: upstream's full_name cell holds a description fragment — kept verbatim"
    assert_equal "雨谷（川村）", entry("002562").headword
    blank = entry("035816")
    assert_equal "【西八条太政大臣】", blank.body, "a blank description falls back to the printed heading"
    assert_equal true, blank.annotations["description_blank"]
  end

  def test_a_multi_person_entry_stays_one_entry
    e = entry("017048")
    assert_equal "式佐（岸沢）", e.headword
    assert_equal 3, e.body.scan(/〔[六七八]世〕/).size
  end

  def test_the_deposit_docs_are_skipped_by_rule_and_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 10, skips.skipped_by_rule, "the deposit's docs, manifest and schema present in the fixture"
    assert(skips.notes.any? { |note| note.include?("release_manifest.json") })
  end

  def test_discover_yields_nothing_before_the_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_fetch_pins_the_deposit_sha256
    assert_equal "410c05fa1d8e111edf6b1fbe724a991675fc3b969cc9b7034cd85a2916f1deec",
                 Nabu::Adapters::HagaJinmei::ZIP_SHA256
    assert_match %r{\Ahttps://zenodo\.org/api/records/23804456/files/}, Nabu::Adapters::HagaJinmei::ZIP_URL
  end
end
