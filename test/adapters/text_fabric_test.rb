# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::TextFabric (P30-4) — the .tf format family, exercised
  # against the byte-verbatim BHSA tf/2021 fixture slices (the honest-path
  # bytes) plus inline Tempfile strings for the format's error paths and the
  # escape rules the BHSA files happen not to carry (documenting the TF
  # spec, not inventing upstream data — the fixture README pins that BHSA
  # 2021 ships zero escapes).
  class TextFabricTest < Minitest::Test
    FIXTURE_DIR = File.join(Nabu::TestSupport.fixtures("bhsa"), "tf", "2021")

    def dataset
      Nabu::Adapters::TextFabric::Dataset.new(FIXTURE_DIR)
    end

    def load_feature(name)
      Nabu::Adapters::TextFabric::Feature.load(File.join(FIXTURE_DIR, "#{name}.tf"))
    end

    # -- header ---------------------------------------------------------------

    def test_header_meta_and_kinds
      otype = load_feature("otype")
      assert_equal :node, otype.kind
      assert_equal "BHSA", otype.meta["dataset"]
      assert_equal "2021", otype.meta["version"]
      assert_equal :str, otype.value_type

      assert_equal :edge, load_feature("oslots").kind
      assert_predicate load_feature("otext"), :config?
    end

    def test_int_value_type_converts
      chapter = load_feature("chapter")
      assert_equal :int, chapter.value_type
      assert_equal 2, chapter.fetch(1_434_819), "Dan 2:4's verse node carries chapter 2 as an Integer"
    end

    # -- data: anchors, ranges, implicit increment ----------------------------

    def test_range_anchor_types_a_whole_block
      otype = load_feature("otype")
      assert_equal "word", otype.fetch(1)
      assert_equal "word", otype.fetch(426_590)
      assert_equal "book", otype.fetch(426_591)
      assert_equal "lex", otype.fetch(1_446_831)
      assert_nil otype.fetch(1_446_832)
    end

    def test_explicit_anchor_then_implicit_increment
      book = load_feature("book")
      # book.tf's fixture data: four anchored book nodes, then anchored
      # verse-grain runs continuing implicitly.
      assert_equal "Jona", book.fetch(426_609)
      assert_nil book.fetch(426_610), "trimmed-away book nodes are absent, not guessed"
      assert_equal "Ruth", book.fetch(426_620)
      assert_equal "Jona", book.fetch(1_428_925)
      assert_equal "Jona", book.fetch(1_428_926), "the line after an anchor is anchor+1"
    end

    def test_each_pair_expands_runs_in_ascending_order
      verse = load_feature("verse")
      pairs = verse.each_pair.to_a
      assert_equal pairs.map(&:first), pairs.map(&:first).sort
      assert_equal [1_428_925, 1], pairs.first, "Jona 1:1"
      assert_includes pairs, [1_434_822, 7], "Dan 2:7"
    end

    def test_sparse_feature_reads_only_its_anchored_nodes
      qere = load_feature("qere_utf8")
      assert_equal "יַ֣עַשׂ", qere.fetch(355_959),
                   "Ruth 1:8's qere, byte-verbatim (upstream ships the FB2B presentation-form śin)"
      assert_nil qere.fetch(355_958)
      assert_nil qere.fetch(298_558), "Jona has no ketiv/qere"
    end

    def test_empty_values_advance_the_cursor_but_stay_absent
      hybrid = load_feature("kq_hybrid_utf8")
      # kq_hybrid_utf8 is word-grain: most fixture slots carry EMPTY lines
      # (absent), the ketiv/qere slots carry the hybrid — the implicit node
      # counter must step over every empty line for the anchored bytes to
      # land on the right slots.
      assert_nil hybrid.fetch(355_958)
      assert_equal "\u05D9\u05B7\u05A3\u05E2\u05B7\u05E9\u05C2\u05D4", hybrid.fetch(355_959),
                   "Ruth 1:8's ketiv-qere hybrid"
    end

    # -- oslots / Dataset -----------------------------------------------------

    def test_dataset_type_ranges_carry_the_full_census
      counts = {
        "word" => 426_590, "book" => 39, "chapter" => 929, "verse" => 23_213,
        "clause" => 88_131, "phrase" => 253_203, "lex" => 9_230
      }
      counts.each do |type, expected|
        assert_equal expected, dataset.type_count(type), "otype census for #{type}"
      end
      assert_equal 426_590, dataset.max_slot
    end

    def test_slot_ranges_for_slots_edges_and_discontinuous_constituents
      data = dataset
      assert_equal [[5, 5]], data.slot_ranges(5), "a slot's range is itself"
      assert_equal [[298_558, 298_565]], data.slot_ranges(487_411), "Jona 1:1's first clause"
      assert_equal [[298_646, 298_650], [298_655, 298_657]], data.slot_ranges(487_432),
                   "a genuinely discontinuous BHSA clause keeps both pieces"
      assert_nil data.slot_ranges(515_690), "a node oslots does not cover is absent"
    end

    def test_parse_ranges
      assert_equal [[3, 3]], Nabu::Adapters::TextFabric.parse_ranges("3")
      assert_equal [[1, 5], [9, 9], [12, 14]], Nabu::Adapters::TextFabric.parse_ranges("1-5,9,12-14")
      assert_raises(Nabu::ParseError) { Nabu::Adapters::TextFabric.parse_ranges("x-3") }
    end

    # -- error paths and the escape rule (inline bytes — format spec, not
    #    upstream fixtures) ---------------------------------------------------

    def test_escapes_unescape_per_the_tf_spec
      feature = tf_feature("@node\n@valueType=str\n\nab\\tcd\\ne\\\\f\n")
      assert_equal "ab\tcd\ne\\f", feature.fetch(1)
    end

    def test_malformed_header_raises
      error = assert_raises(Nabu::ParseError) { tf_feature("nonsense\n\n1\tx\n") }
      assert_match(/opens with @node, @edge or @config/, error.message)
      assert_raises(Nabu::ParseError) { tf_feature("@node\nno-at-sign\n\nx\n") }
    end

    def test_descending_anchor_is_damage
      error = assert_raises(Nabu::ParseError) { tf_feature("@node\n\n5\tx\n3\ty\n") }
      assert_match(/does not ascend/, error.message)
    end

    def test_edge_values_are_refused
      error = assert_raises(Nabu::ParseError) { tf_feature("@edge\n@edgeValues\n\n1\t2\tvalue\n") }
      assert_match(/@edgeValues/, error.message)
    end

    def test_config_with_data_raises
      assert_raises(Nabu::ParseError) { tf_feature("@config\n\nstray\n") }
    end

    def test_missing_file_raises
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::TextFabric::Feature.load(File.join(FIXTURE_DIR, "no_such.tf"))
      end
      assert_match(/no such \.tf file/, error.message)
    end

    private

    def tf_feature(content)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "inline.tf")
        File.write(path, content)
        return Nabu::Adapters::TextFabric::Feature.load(path)
      end
    end
  end
end
