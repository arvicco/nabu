# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# MengguZiyun adapter tests (P88-A2, unblocked by nabu-lects v1.4.0's
# zho:oman ruling): nk2028/menggu-ziyun-data — the 蒙古字韻 (1308), the
# 'Phags-pa-script rhyme book of Old Mandarin, with unt's reconstructions
# and the ready-made 對應切韻音系音韻地位 join into the held guangyun
# shelf. Language honest-coarse `zho` (no ISO code for Old Mandarin — the
# registry's zho:oman stage refines; the en:early pattern). Fixture rows
# are byte-verbatim upstream (test/fixtures/menggu-ziyun/README.md).
class MengguZiyunTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("menggu-ziyun")

  def adapter
    Nabu::Adapters::MengguZiyun.new
  end

  # --- manifest / capabilities ----------------------------------------------

  def test_manifest_records_the_mit_grant
    manifest = Nabu::Adapters::MengguZiyun.manifest
    assert_equal "menggu-ziyun", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/MIT/, manifest.license)
    assert_match(/沈鍾偉|unt/, manifest.license, "the scholarship chain rides the credit line")
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::MengguZiyun.content_kind
  end

  # --- discover / parse -----------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "menggu-ziyun:data.tsv", refs.first.id
    adapter.parse(refs.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_character_row
    document = parsed
    assert_equal "menggu-ziyun", document.slug
    assert_equal "zho", document.language
    assert_equal 159, document.count
    assert_equal document.count, document.entries.map(&:entry_id).uniq.size,
                 "小韻號.ordinal is unique per row"
  end

  def test_plain_entry_carries_phagspa_reconstruction_and_the_guangyun_join
    gong = entries_by_id.fetch("1.1")
    assert_equal "公", gong.headword
    assert_nil gong.gloss, "an empty 釋義 is honestly nil (only 104 of 9,446 rows carry one)"
    assert_match(/八思巴字：ꡂꡟꡃ/, gong.body)
    assert_match(/聲調：平/, gong.body)
    assert_match(/韻部：一東/, gong.body)
    assert_match(/unt擬音：kuŋ（轉寫 kuŋ）/, gong.body)
    assert_match(/對應切韻音系音韻地位：見一東平/, gong.body,
                 "the ready-made join key into the held guangyun shelf")
  end

  def test_a_filled_shiyi_is_the_gloss
    qia = entries_by_id.fetch("1.8")
    assert_equal "㓚", qia.headword
    assert_equal "刈也", qia.gloss
  end

  def test_ids_headwords_and_correction_notes_ride_verbatim
    restored = parsed.entries.find { |entry| entry.headword == "𧄓" }
    refute_nil restored, "the plane-2 corrected headword mints"
    assert_match(/注釋：原卷作「⿰壴𰩨」/, restored.body,
                 "the IDS-sequence correction note rides verbatim — canonical means canonical")
  end

  def test_variant_and_deletion_verdicts_annotate_never_drop
    zhong = parsed.entries.find { |entry| entry.headword == "衆" }
    assert_match(/備選異體：眾/, zhong.body)
    fengs = parsed.entries.select { |entry| entry.headword == "唪" }
    assert_equal 2, fengs.size, "both 唪 rows mint — the 去-tone one carries the verdict"
    assert(fengs.any? { |entry| entry.body.include?("需作調整：此字當刪") },
           "a 此字當刪 row STILL MINTS, verdict in the body (the guangyun 應刪字 stance)")
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["menggu-ziyun"]
    refute_nil entry, "config/sources.yml must register menggu-ziyun"
    assert_equal Nabu::Adapters::MengguZiyun, entry.adapter_class
    refute entry.wired, "wired stays false until the owner-fired first sync verifies live"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
