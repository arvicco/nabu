# frozen_string_literal: true

require "test_helper"
require "digest"
require "tmpdir"

# BaxterSagart adapter tests (P32-3): the yawnoc TSV dump of the Baxter &
# Sagart 2014 Old Chinese reconstruction — ONE sha-pinned file, TWO
# dictionaries (the EDL one-file-two-shelves precedent): baxter-sagart-oc
# (och) and baxter-sagart-mc (ltc). Dictionary sources skip the passage
# conformance suite (the wiktionary-recon precedent); fixture rows are
# byte-verbatim upstream (test/fixtures/baxter-sagart/README.md).
class BaxterSagartTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("baxter-sagart")

  def adapter
    Nabu::Adapters::BaxterSagart.new
  end

  # --- manifest / capabilities ------------------------------------------------

  def test_manifest_carries_the_provenance_chain_verbatim
    manifest = Nabu::Adapters::BaxterSagart.manifest
    assert_equal "baxter-sagart", manifest.id
    assert_equal "attribution", manifest.license_class
    # the dead Michigan host's grant, via its wayback capture — verbatim
    assert_match(/are licensed under CC BY 4\.0/, manifest.license)
    assert_match(%r{web\.archive\.org/web/20250312164901}, manifest.license)
    assert_match(/Baxter/, manifest.license)
    assert_match(/Sagart/, manifest.license)
    assert_equal "flat-csv", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::BaxterSagart.content_kind
  end

  # --- discover / parse -------------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[baxter-sagart-oc:BaxterSagartOC2015-10-13.tsv
                    baxter-sagart-mc:BaxterSagartOC2015-10-13.tsv], refs.map(&:id)
    refs.map { |ref| adapter.parse(ref) }
  end

  def test_one_tsv_yields_the_two_reconstruction_lanes
    oc, mc = parsed
    assert_equal %w[baxter-sagart-oc baxter-sagart-mc], [oc.slug, mc.slug]
    assert_equal %w[och ltc], [oc.language, mc.language]
    assert_equal [9, 9], [oc.count, mc.count], "every TSV row mints an entry in each lane"
  end

  def test_oc_lane_leads_with_the_old_chinese_reconstruction
    oc, = parsed
    ai = oc.entries.find { |e| e.entry_id == "埃" } || flunk("埃 missing")
    assert_equal "埃", ai.headword
    assert_equal "dust", ai.gloss
    assert_match(/\AOC: \*qˤə$/, ai.body, "OC leads, trailing upstream space stripped")
    assert_match(/MC: 'oj \('- \+ -oj A\)/, ai.body, "the unnamed analysis column rides the MC line")
    assert_match(/pinyin: āi/, ai.body)
    assert_match(/GSR 0938b/, ai.body)
    assert_match(/U\+57C3/, ai.body)
  end

  def test_mc_lane_leads_with_the_middle_chinese_reading
    _, mc = parsed
    ai = mc.entries.find { |e| e.entry_id == "埃" } || flunk("埃 missing")
    assert_equal "ltc", ai.language
    assert_match(/\AMC: 'oj \('- \+ -oj A\)/, ai.body, "MC leads the ltc lane")
    assert_match(/OC: \*qˤə$/, ai.body)
  end

  def test_polyphonic_characters_stay_separate_entries_with_positional_ids
    oc, = parsed
    first = oc.entries.find { |e| e.entry_id == "隘" } || flunk("隘 missing")
    second = oc.entries.find { |e| e.entry_id == "隘:2" } || flunk("隘:2 missing")
    assert_equal %w[ài è], [first, second].map { |e| e.body[/pinyin: (\S+)/, 1] },
                 "the two readings of 隘 keep file order"
    assert_match(/OC: \*qˤ<r>\[i\]k-s$/, first.body)
    assert_match(/OC: \*qˤ<r>\[i\]k$/, second.body)
  end

  def test_non_nfc_upstream_gloss_is_normalized_at_the_boundary
    oc, = parsed
    ehuixuan = oc.entries.find { |e| e.entry_id == "阿:2" } || flunk("阿:2 missing")
    assert_match(/ābhāsvara/, ehuixuan.gloss)
    assert_equal ehuixuan.gloss, ehuixuan.gloss.unicode_normalize(:nfc), "NFC boundary holds"
  end

  def test_empty_pinyin_row_parses_with_an_honest_body
    oc, = parsed
    lan = oc.entries.find { |e| e.entry_id == "瀾" } || flunk("瀾 missing")
    refute_match(/pinyin:/, lan.body, "the one upstream py-less row omits the pinyin line")
    assert_equal "water in which rice has been washed", lan.gloss
  end

  def test_csv_quoted_gloss_decodes
    oc, = parsed
    xiu = oc.entries.find { |e| e.entry_id == "宿:2" } || flunk("宿:2 missing")
    assert_equal %("mansion" of the zodiac (where the moon is found on successive nights)),
                 xiu.gloss, "the Excel-style quoted TSV field decodes"
  end

  def test_headwords_fold_for_lookup
    oc, = parsed
    ai = oc.entries.find { |e| e.entry_id == "埃" }
    assert_equal Nabu::Normalize.search_form("埃", language: "och"), ai.headword_folded
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_lands_the_tsv_and_verifies_the_pin
    body = File.binread(File.join(FIXTURES, "BaxterSagartOC2015-10-13.tsv"))
    stub_request(:get, Nabu::Adapters::BaxterSagart::TSV_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::BaxterSagart.new(tsv_sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, "BaxterSagartOC2015-10-13.tsv"))
      refute_nil report.sha
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    body = File.binread(File.join(FIXTURES, "BaxterSagartOC2015-10-13.tsv"))
    stub_request(:get, Nabu::Adapters::BaxterSagart::TSV_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) do
        Nabu::Adapters::BaxterSagart.new(tsv_sha256: "0" * 64).fetch(dir)
      end
      assert_match(/re-pin/, error.message)
      refute File.exist?(File.join(dir, "BaxterSagartOC2015-10-13.tsv"))
    end
  end

  # --- registry ---------------------------------------------------------------

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["baxter-sagart"]
    refute_nil entry, "config/sources.yml must register baxter-sagart"
    assert_equal Nabu::Adapters::BaxterSagart, entry.adapter_class
    assert entry.enabled, "live (owner order 2026-07-20: P32+P33 sources flipped, post-P34 gate)"
    assert_equal "manual", entry.sync_policy
  end
end
