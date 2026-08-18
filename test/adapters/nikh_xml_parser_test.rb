# frozen_string_literal: true

require "test_helper"

# Parser family "nikh-xml" (P78-1): the Korean History Database unified
# DTD (history.dtd ver 1.3, 2015-11-30 — SHIPPED IN EVERY DUMP ZIP) that
# carries the NIKH state corpora: sillok, sjw, goryeosa, bibyeonsa. One
# volume file = one level1- or level2-rooted tree of nested level2..5
# nodes; the LEAVES of that tree (the day articles, prefaces, appendix
# sections) are the citation units. Fixtures are three real sillok
# members (see test/fixtures/sillok/README.md).
class NikhXmlParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("sillok")

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

  def test_malformed_xml_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "2nd_bad_000.xml")
      File.write(path, "<level2 id=\"bad_000\"><front>")
      assert_raises(Nabu::ParseError) { parser.parse_file(path) }
    end
  end
end
