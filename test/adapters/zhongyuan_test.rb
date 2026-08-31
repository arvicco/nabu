# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Zhongyuan adapter tests (P88-R3 — the row-99 un-park, ruled by the same
# zho:oman stage as menggu-ziyun): nk2028/zhongyuan-data — the 中原音韻
# (Zhou Deqing, 1324), the arch-source of Old Mandarin phonology, with
# FOUR parallel scholarly reconstructions per row (楊耐思 1981 · 寧繼福
# 1985 · 薛鳳生 1990 phonemic · unt 2021 phonemic + transcription).
# Fixture rows are byte-verbatim upstream
# (test/fixtures/zhongyuan/README.md).
class ZhongyuanTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("zhongyuan")

  def adapter
    Nabu::Adapters::Zhongyuan.new
  end

  # --- manifest / capabilities ----------------------------------------------

  def test_manifest_records_the_cc0_dedication
    manifest = Nabu::Adapters::Zhongyuan.manifest
    assert_equal "zhongyuan", manifest.id
    assert_equal "open", manifest.license_class
    assert_match(/CC0 1\.0/, manifest.license)
    assert_match(/楊耐思|reconstruction/, manifest.license,
                 "the reconstruction scholarship chain rides the credit line")
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::Zhongyuan.content_kind
  end

  # --- discover / parse -----------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "zhongyuan:中原音韻.tsv", refs.first.id
    adapter.parse(refs.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_character_row
    document = parsed
    assert_equal "zhongyuan", document.slug
    assert_equal "zho", document.language
    assert_equal 79, document.count
    assert_equal document.count, document.entries.map(&:entry_id).uniq.size,
                 "小韻.ordinal is unique per row"
  end

  def test_entry_carries_the_four_reconstruction_lanes
    dong = entries_by_id.fetch("東.1")
    assert_equal "東", dong.headword
    assert_nil dong.gloss, "an empty 釋義 is honestly nil (13 of 5,877 rows carry one)"
    assert_match(/聲母：端/, dong.body)
    assert_match(/韻母：東鍾合/, dong.body)
    assert_match(/聲調：陰/, dong.body)
    assert_match(/楊耐思：tuŋ/, dong.body)
    assert_match(/寧繼福：tuŋ/, dong.body)
    assert_match(/薛鳳生（音位）：twoŋ/, dong.body)
    assert_match(/unt（音位）：tuŋ（轉寫 tuŋ）/, dong.body)
  end

  def test_a_filled_shiyi_is_the_gloss
    cong = parsed.entries.find { |entry| entry.headword == "囱" }
    assert_equal "煙突", cong.gloss
  end

  def test_correction_notes_ride_verbatim
    song = parsed.entries.find { |entry| entry.headword == "憽" }
    assert_match(/校註：原作“愡”，誤/, song.body,
                 "the editorial note rides verbatim — canonical means canonical")
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["zhongyuan"]
    refute_nil entry, "config/sources.yml must register zhongyuan"
    assert_equal Nabu::Adapters::Zhongyuan, entry.adapter_class
    assert entry.wired, "live (first sync verified + owner sign-off 2026-08-30; flipped 2026-08-31)"
    assert_equal "manual", entry.sync_policy
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
