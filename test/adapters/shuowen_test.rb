# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Shuowen: the Shuowen Jiezi 說文解字 (Xu Shen, 100 CE) as
# the shuowen.org data repo serves it — one JSON record per head character,
# with Xu Xuan's fanqie, the 重文 variant forms, the Xu Xuan / Xu Kai notes
# and Duan Yucai's commentary. Dictionary-shaped, so it mirrors the
# conformance checks for the dictionary shape (the SlounikiNasovic mold):
# manifest, discover→parse round-trip, id uniqueness/stability, NFC, license
# class, the DictionaryLoader contract, plus the entry pins.
#
# Fixtures (test/fixtures/shuowen/, README there): nine WHOLE real records at
# upstream commit 6553a350 plus doc/FORMAT.md, the rejected documentation
# grain pinned beside them.
class ShuowenTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("shuowen")
  Shuowen = Nabu::Adapters::Shuowen

  def adapter = Shuowen.new

  def entries(id)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == "shuowen:#{id}" } || flunk("no #{id}")
    adapter.parse(ref).to_a
  end

  def head(id) = entries(id).first

  def test_manifest_and_content_kind
    manifest = Shuowen.manifest
    assert_equal "shuowen", manifest.id
    assert_equal "attribution", manifest.license_class, "Apache-2.0 → attribution (the monlam-lexicon precedent)"
    assert_match(/Apache License, Version 2\.0/, manifest.license)
    assert_match(/Copyright \[2019\] \[Shuowen\.org\]/, manifest.license)
    assert_match(/Xu Shen/, manifest.credit)
    assert_equal "shuowen-json", manifest.parser_family
    assert_equal :dictionary, Shuowen.content_kind
  end

  def test_discover_yields_one_ref_per_record_in_id_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %w[1 7 530 1000 1082 1214 4354 6558 7538].map { |id| "shuowen:#{id}" }, refs.map(&:id)
    assert(refs.all? { |ref| ref.source_id == "shuowen" })
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  # The rejected grain: the repo's doc/ tree (format + contribution guides,
  # screenshots) is documentation, not dictionary data — pinned by the real
  # FORMAT.md and skipped by rule with its note, never silently.
  def test_discovery_skips_counts_the_documentation_grain
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_match(%r{documentation.*doc/FORMAT\.md}, skips.notes.join("\n"))
    assert skips.clean?
  end

  def test_parse_yields_an_lzh_dictionary_document
    document = adapter.parse(adapter.discover(FIXTURES).first)
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "shuowen", document.slug
    assert_equal "lzh", document.language
  end

  def test_entry_ids_are_unique_stable_and_nfc
    snapshot = -> { adapter.discover(FIXTURES).flat_map { |ref| adapter.parse(ref).map(&:entry_id) } }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    adapter.discover(FIXTURES).each do |ref|
      adapter.parse(ref).each do |entry|
        assert entry.headword.unicode_normalized?(:nfc)
        assert entry.body.unicode_normalized?(:nfc)
        assert entry.gloss.unicode_normalized?(:nfc)
      end
    end
  end

  # 帝 — the FORMAT.md worked example: Xu Shen's gloss, Xu Xuan's fanqie,
  # the 540-radical placement, the components, one encoded 重文, and four
  # Duan commentary pairs.
  def test_the_format_example_carries_every_layer
    di = head(7)
    assert_equal "7", di.entry_id
    assert_equal "帝", di.headword
    assert_equal Nabu::Normalize.search_form("帝", language: "lzh"), di.headword_folded
    assert_equal "諦也。王天下之號也。从丄朿聲。", di.gloss, "Xu Shen's own explanation IS the gloss"
    body = di.body.lines.map(&:chomp)
    assert_equal "說文: 諦也。王天下之號也。从丄朿聲。", body.first
    assert_includes body, "反切: 都計切"
    assert_includes body, "拼音: dì"
    assert_includes body, "部首: 丄 · 卷01"
    assert_includes body, "構件: 一 上 朿"
    assert_includes body, "重文 𢂇: 古文帝。古文諸丄字皆从一，篆文皆从𠄞。𠄞，古文上字。䇂示辰龍童音章皆从古文丄。"
    assert_includes body, "段注〔諦也。〕見春秋元命苞、春秋運斗樞。毛詩故訓傳曰。審諦如帝。"
    assert_equal(4, body.count { |line| line.start_with?("段注") })
    refute_match(/丈/, di.body, "seal_character is a shuowen.org font-slot key, never a glyph claim — dropped")
  end

  def test_annotations_carry_the_structured_fields
    annotations = head(7).annotations
    assert_equal "丄", annotations["radical"]
    assert_equal "01", annotations["volume"]
    assert_equal "都計切", annotations["fanqie"]
    assert_equal "dì", annotations["pinyin"]
    assert_equal %w[一 上 朿], annotations["components"]
    assert_equal %w[帝 𢂇], annotations["indexes"]
    refute annotations.key?("seal_character")
  end

  def test_components_and_variants_ride_as_crossrefs
    crossrefs = head(7).crossrefs
    components = crossrefs.select { |ref| ref.kind == "component" }
    assert_equal %w[一 上 朿], components.map(&:target)
    assert_equal Nabu::Normalize.search_form("朿", language: "lzh"), components.last.target_folded
    variant = crossrefs.find { |ref| ref.kind == "chongwen" }
    assert_equal "𢂇", variant.target
    assert_equal "7-v1", variant.target_id, "the 重文 points at its own minted entry by id"
  end

  # The 重文 variant forms get their own entries so `define 弌` lands on
  # Xu Shen's "古文一" — pointing back at the head by upstream id.
  def test_an_encoded_variant_mints_its_own_entry
    yi = entries(1)
    assert_equal %w[1 1-v1], yi.map(&:entry_id)
    variant = yi.last
    assert_equal "弌", variant.headword
    assert_equal "古文一。", variant.gloss
    assert_match(/^重文 of 一 \(說文 entry 1\)$/, variant.body)
    back = variant.crossrefs.find { |ref| ref.kind == "chongwen-of" }
    assert_equal "一", back.target
    assert_equal "1", back.target_id
    assert_equal({ "chongwen_of" => "1", "position" => 1 }, variant.annotations)
  end

  # 雲: one encoded 重文 (云) and one whose glyph upstream never encoded
  # (empty wordhead) — the latter rides the head body with an honest
  # marker and mints no entry; ids stay positional.
  def test_an_unencoded_variant_stays_in_the_head_body_only
    yun = entries(7538)
    assert_equal %w[7538 7538-v1], yun.map(&:entry_id)
    assert_includes yun.first.body.lines.map(&:chomp), "重文 (glyph not encoded): 亦古文雲。"
    assert_equal(%w[云 雲], yun.first.annotations["indexes"], "empty and duplicate index keys are dropped")
  end

  def test_xu_xuan_and_xu_kai_notes_are_labeled
    assert_includes head(1214).body.lines.map(&:chomp), "徐鉉: 臣鉉等曰：或通用徦字。"
    xiu = head(4354)
    assert_includes xiu.body.lines.map(&:chomp), "徐鍇: 徐鍇曰：“禾，實也。有實之象，下垂也。”"
    refute_match(/段注/, xiu.body, "no Duan pair upstream — none invented")
  end

  def test_missing_volume_and_fanqie_are_absent_never_placeholders
    ci = head(1082)
    assert_equal "此", ci.headword
    refute ci.annotations.key?("volume")
    assert_includes ci.body.lines.map(&:chomp), "部首: #{ci.annotations['radical']}"
    cheng = head(6558)
    refute cheng.annotations.key?("fanqie")
    refute_match(/反切/, cheng.body)
  end

  # 蔇's Duan note writes 穊 as the CJK compatibility ideograph U+2F95A —
  # composed to the unified form at the adapter boundary (house NFC rule).
  def test_a_compatibility_ideograph_is_composed_at_the_boundary
    body = head(530).body
    assert_includes body, "穊"
    refute_includes body, "\u{2F95A}"
  end

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "shuowen", name: "Shuowen Jiezi",
                                        adapter_class: "Nabu::Adapters::Shuowen", license_class: "attribution")
    2.times do
      result = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 0, result.errored
      assert_equal 13, db[:dictionary_entries].count, "9 heads + 4 encoded 重文 (弌 𢂇 泟 云)"
    end
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:shuowen:7-v1"
  ensure
    db&.disconnect
  end

  def test_fetch_sparse_clones_the_data_cone
    Dir.mktmpdir("nabu-shuowen-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(FIXTURES, "data"), upstream)
      FileUtils.cp_r(File.join(FIXTURES, "doc"), upstream)
      FileUtils.mkdir_p(File.join(upstream, "doc", "img"))
      File.write(File.join(upstream, "doc", "img", "wechat.jpg"), "jpg")
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      work = File.join(root, "canonical")
      shuowen = adapter
      shuowen.define_singleton_method(:repo_url) { upstream }
      report = shuowen.fetch(work)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "data", "7.json"))
      assert File.file?(File.join(work, "doc", "FORMAT.md"))
      refute File.exist?(File.join(work, "doc", "img", "wechat.jpg")), "the screenshots stay outside the cone"
      assert_equal 9, shuowen.discover(work).count
    end
  end
end
