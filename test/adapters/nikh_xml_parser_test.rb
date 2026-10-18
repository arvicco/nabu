# frozen_string_literal: true

require "test_helper"

# Parser family "nikh-xml" (P78-1): the Korean History Database unified
# DTD (history.dtd ver 1.3, 2015-11-30 — SHIPPED IN EVERY DUMP ZIP) that
# carries the NIKH state corpora: sillok, sjw, goryeosa, bibyeonsa. One
# volume file = one level1- or level2-rooted tree of nested level2..5
# nodes; the LEAVES of that tree (the day articles, prefaces, appendix
# sections) are the citation units. Fixtures are three real sillok
# members (see test/fixtures/sillok/README.md) plus, for the P78-3
# family variance (the <item>-wrapped front-matter members and the
# 서기-less date apparatus), goryeosa/bibyeonsa members.
class NikhXmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("sillok")
  GORYEOSA_FIXTURES = Nabu::TestSupport.fixtures("goryeosa")
  BIBYEONSA_FIXTURES = Nabu::TestSupport.fixtures("bibyeonsa")

  def parser = Nabu::Adapters::NikhXmlParser.new

  def volume(name) = parser.parse_file(File.join(FIXTURES, name))

  # -- the anchor member: level2 root, level3→4→5 chain, full dates -------

  def test_volume_identity_comes_from_the_filename_not_the_root_id
    assert_equal "wzc_121", volume("2nd_wzc_121.xml").id
    # level1-rooted _000 members carry the REIGN id ("wqa") on the root;
    # only the filename id ("wqa_000") is unique across the corpus.
    assert_equal "wqa_000", volume("2nd_wqa_000.xml").id
  end

  def test_volume_title_and_year_come_from_the_root_front
    vol = volume("2nd_wzc_121.xml")
    assert_equal "純宗[附錄] 二十一年", vol.title
    assert_equal 1928, vol.year
  end

  def test_leaves_are_the_deepest_level_nodes_with_text
    vol = volume("2nd_wzc_121.xml")
    assert_equal %w[wzc_12105003_001 wzc_12107006_001], vol.leaves.map(&:id),
                 "the level5 articles leaf; the level2/3/4 header text blocks are navigation, not passages"
  end

  def test_the_level5_article_carries_its_own_apparatus
    article = volume("2nd_wzc_121.xml").leaves.first
    assert_equal "순명 황후의 휘호를 경현성휘로 정하다", article.title
    assert_equal "1928-05-03L0", article.date_raw
    assert_equal ["왕실-종사(宗社)", "왕실-비빈(妃嬪)"], article.subject_classes
    assert(article.sources.any? { |source| source.include?("純宗實錄[附錄] 8책 17권") })
  end

  def test_leaf_text_flattens_index_refs_and_keeps_original_annotations
    article = volume("2nd_wzc_121.xml").leaves.first
    assert_includes article.text, "純明皇后徽號望", "index elements flatten to their text"
    assert_includes article.text, "【陰曆戊辰三月十四日】",
                    "the 원주 interlinear note rides inline, brackets verbatim"
    refute_includes article.text, "<", "no markup survives into passage text"
  end

  # -- the appendix member: level3 leaves, no dates ------------------------

  def test_a_member_without_day_entries_leafs_at_level3
    vol = volume("2nd_waa_200.xml")
    assert_equal %w[waa_200001 waa_200002], vol.leaves.map(&:id)
    assert_nil vol.leaves.first.date_raw, "an undated section is honestly dateless"
    assert_includes vol.leaves.first.text, "河崙等, 奉敎撰進。"
  end

  # -- the level1-rooted preface member ------------------------------------

  def test_a_level1_rooted_member_leafs_at_its_level2
    vol = volume("2nd_wqa_000.xml")
    assert_equal "孝宗實錄", vol.title
    assert_equal %w[wqa_000], vol.leaves.map(&:id)
    assert_includes vol.leaves.first.text, "在位十年, 壽四十一。"
  end

  # -- the P78-3 variance: <item>-wrapped members, 서기-less dates ---------

  def test_an_item_wrapped_member_anchors_its_volume_front_on_the_first_level1
    vol = parser.parse_file(File.join(GORYEOSA_FIXTURES, "kr_000.xml"))
    # The goryeosa-family front-matter members wrap SIBLING level1
    # sections in an <item> root (DOCTYPE item — one such member per
    # zip, P78-3 census). The FIRST level1 anchors the volume front;
    # every sibling subtree contributes its leaves.
    assert_equal "kr_000", vol.id
    assert_equal "kr_$s01", vol.root_id
    assert_equal "『고려사』를 찬진하는 전", vol.title
    assert_equal 13, vol.leaves.size, "all four level1 siblings leaf"
    assert_equal %w[kr_$s01 kr_$s02_0010], vol.leaves.first(2).map(&:id)
  end

  def test_the_date_fallback_picks_the_first_machine_dated_calendar_entry
    # The P78-3 zips carry NO 서기 calendar line at all: goryeosa/jeoryo
    # lead with the lunar 음 entry (the solar 양 follows), bibyeonsa's
    # single machine date is UNTYPED. The first @date-bearing entry in
    # document order is upstream's own primary calendar.
    vol = parser.parse_file(File.join(GORYEOSA_FIXTURES, "kr_069.xml"))
    assert_equal "1048-02-16L0", vol.leaves.last.date_raw, "음 leads 양 in document order"
    bb = parser.parse_file(File.join(BIBYEONSA_FIXTURES, "bb_054.xml"))
    assert_equal "1704-01-00L0", bb.leaves.first.date_raw, "bibyeonsa's untyped machine date"
  end

  # -- the index markup: typed entity tags mined beside the text ----------

  SJW_FIXTURES = Nabu::TestSupport.fixtures("sjw")
  JEORYO_FIXTURES = Nabu::TestSupport.fixtures("goryeosa-jeoryo")

  def mining = Nabu::Adapters::NikhXmlParser.new(entities: true)

  def test_entity_mining_is_opt_in
    article = volume("2nd_wzc_121.xml").leaves.first
    assert_equal({}, article.entities, "a parser built without entities: mines nothing")
  end

  def test_sillok_persons_carry_their_m_ids_and_places_ride_bare
    vol = mining.parse_file(File.join(FIXTURES, "2nd_wzc_121.xml"))
    first, second = vol.leaves
    assert_equal({ "persons" => [{ "value" => "純明皇后", "ref" => "nikh:M_0006771" }] }, first.entities)
    assert_equal [{ "value" => "純宗", "ref" => "nikh:M_0062680" },
                  { "value" => "純明孝皇后", "ref" => "nikh:M_0006771" }],
                 second.entities["persons"], "document order; the alias shares its M_ id"
    assert_equal [{ "value" => "太廟" }, { "value" => "璿源殿" }], second.entities["places"],
                 "sillok places carry no ref — none is minted"
  end

  def test_mining_leaves_the_leaf_text_byte_identical
    %w[2nd_wzc_121.xml 2nd_waa_200.xml 2nd_wqa_000.xml].each do |name|
      plain = parser.parse_file(File.join(FIXTURES, name)).leaves.map(&:text)
      mined = mining.parse_file(File.join(FIXTURES, name)).leaves.map(&:text)
      assert_equal plain, mined, name
    end
    plain = parser.parse_file(File.join(SJW_FIXTURES, "2nd_F02.sjw.y.xml")).leaves.map(&:text)
    assert_equal plain, mining.parse_file(File.join(SJW_FIXTURES, "2nd_F02.sjw.y.xml")).leaves.map(&:text)
  end

  def test_eras_mine_and_the_m_id_wins_over_the_secondary_person_pid
    vol = mining.parse_file(File.join(FIXTURES, "2nd_waa_200.xml"))
    first, second = vol.leaves
    assert_equal [{ "value" => "永樂" }], first.entities["eras"]
    assert_equal [{ "value" => "晋山府院君", "ref" => "nikh:M_0059127" },
                  { "value" => "河崙", "ref" => "nikh:M_0059127" }], first.entities["persons"]
    # 鄭麟趾 carries ref="M_0005882" AND id="p17_000013_00" (the cross-
    # database person pid): the M_ ref is the tag's primary key.
    assert_equal [{ "value" => "鄭麟趾", "ref" => "nikh:M_0005882" }], second.entities["persons"]
  end

  def test_goryeosa_tags_map_every_type_with_their_kind_prefixed_ids
    vol = mining.parse_file(File.join(GORYEOSA_FIXTURES, "kr_118.xml"))
    entities = vol.leaves.first.entities
    assert_equal({ "value" => "趙浚", "ref" => "nikh:p094190" }, entities["persons"].first)
    assert_equal({ "value" => "明仲", "ref" => "nikh:p094190" }, entities["persons"][1],
                 "the courtesy name groups under the person's id")
    assert_equal({ "value" => "侍中", "ref" => "nikh:o005170" }, entities["offices"].first)
    assert_equal({ "value" => "旌善郡", "ref" => "nikh:t022420" }, entities["places"].first)
    whole = mining.parse_file(File.join(GORYEOSA_FIXTURES, "kr_000.xml")).leaves.flat_map(&:entities)
    kinds = whole.flat_map(&:keys).uniq.sort
    assert_equal %w[books offices orgs persons places], kinds
  end

  def test_sjw_persons_take_upstreams_normalized_name_as_value
    leaf = mining.parse_file(File.join(SJW_FIXTURES, "2nd_F02.sjw.y.xml")).leaves.first
    persons = leaf.entities["persons"]
    assert_equal({ "value" => "鄭亨益" }, persons.first, "name= equal to the surface: no surface field")
    assert_includes persons, { "value" => "李㙫", "surface" => "密平君㙫" },
                    "the normalized name= is the value; the differing surface rides beside it"
    assert_includes persons, { "value" => "黃梓", "ref" => "nikh:p17_100010_00", "surface" => "梓" },
                    "the person pid is the only id sjw carries"
    assert_includes persons, { "value" => "黃梓", "ref" => "nikh:p17_100010_00" }
    assert_includes persons, { "value" => "程子" }, "name=\"미결\" (unresolved): the surface stays the value"
    assert_includes leaf.entities["books"], { "value" => "孟子離婁上", "name" => "孟子" },
                    "books keep the surface-valued shape"
    assert_equal [{ "value" => "時敏堂" }], leaf.entities["places"]
  end

  def test_identical_records_dedupe_per_passage_in_first_seen_order
    leaf = mining.parse_file(File.join(SJW_FIXTURES, "2nd_F02.sjw.y.xml")).leaves.first
    leaf.entities.each_value { |records| assert_equal records.uniq, records }
    assert_equal 1, leaf.entities["persons"].count({ "value" => "許錫" }),
                 "許錫 is tagged 20+ times in the article — one record; repeats live in the text"
    assert_operator leaf.text.scan("許錫").size, :>, 10
    vol = mining.parse_file(File.join(GORYEOSA_FIXTURES, "kr_118.xml"))
    persons = vol.leaves.first.entities["persons"]
    assert_equal 1, persons.count({ "value" => "浚", "ref" => "nikh:p094190" })
    assert_equal [{ "value" => "趙浚", "ref" => "nikh:p094190" }, { "value" => "明仲", "ref" => "nikh:p094190" }],
                 persons.first(2), "first occurrence fixes the order"
  end

  def test_a_wrapper_index_around_one_same_typed_index_is_one_mention
    vol = mining.parse_file(File.join(BIBYEONSA_FIXTURES, "bb_248.xml"))
    # <index type="이름"><index id="p16_000058_00" type="이름">朴彭年</index></index>:
    # upstream double-tags the one mention; the inner tag's id survives.
    assert_equal [{ "value" => "朴彭年", "ref" => "nikh:p16_000058_00" }], vol.leaves.first.entities["persons"]
  end

  def test_untagged_ref_attributes_and_empty_tags_mint_nothing_spurious
    vol = mining.parse_file(File.join(JEORYO_FIXTURES, "kj_033.xml"))
    records = vol.leaves.flat_map { |leaf| leaf.entities.values.flatten }
    refute_empty records
    assert(records.all? { |record| !record["value"].strip.empty? }, "no empty-surface mention")
    assert(records.all? { |record| record["ref"].nil? || record["ref"].match?(/\Anikh:\S+\z/) },
           "a blank ref attr is no ref")
    assert(records.any? { |record| record["ref"].nil? }, "jeoryo carries id-less persons and offices")
  end

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "2nd_bad_000.xml")
      File.write(path, "<level2 id=\"bad_000\"><front>")
      assert_raises(Nabu::ParseError) { parser.parse_file(path) }
    end
  end
end
