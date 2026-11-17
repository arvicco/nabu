# frozen_string_literal: true

require "test_helper"

# The josephus-latin-tei parser family over the trimmed real deposit files
# (test/fixtures/josephus-latin/README.md): reading units, the reading-text
# rules (del kept as ⟦…⟧, gap as […], breaks silent) and the two
# manuscript-annotation layers.
class JosephusLatinTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("josephus-latin")

  def parse(rel)
    Nabu::Adapters::JosephusLatinTeiParser.new.parse(File.join(FIXTURES, "assets", "xml", rel))
  end

  def unit(rel, ref)
    parse(rel).units.find { |u| u.ref == ref } or flunk "no unit #{ref} in #{rel}"
  end

  def test_units_are_p_head_trailer_in_document_order_with_stripped_ids
    result = parse("antiquities/Latin/book-01.xml")
    assert_equal %w[p1 num27 num34 trailer1], result.units.map(&:ref),
                 "the id-less incipit is positional; p ids lose their latin-book01- prefix"
    assert_equal %w[p p p trailer], result.units.map(&:name)
    assert_equal "Bamberg Msc. Class. 78", result.witness, "the body-level note is the witness, not a unit"
  end

  def test_units_nested_in_argument_and_floating_text_are_read
    refs = parse("antiquities/Latin/book-11.xml").units.map(&:ref)
    assert_equal %w[head1 num1 num5 num8 trailer1], refs,
                 "Antiquities XI wraps its running text in argument/floatingText"
  end

  def test_an_empty_unit_is_not_emitted_but_keeps_its_ordinal
    refs = parse("antiquities/Latin/book-09.xml").units.map(&:ref)
    assert_equal %w[p2 num1], refs, "the break-only <p> (p1) has no reading text"
  end

  def test_del_is_kept_in_erasure_brackets_and_num_leaves_the_text
    num34 = unit("antiquities/Latin/book-01.xml", "num34")
    assert num34.text.start_with?("Post septima⟦m⟧ uero die⟦m⟧ coepit"), num34.text
    assert_includes num34.text, "nomina[tim] ⟦in⟧posuit", "upstream's own [add] brackets stay verbatim"
    refute_includes num34.text, "[I.ii.34]"
    assert_equal "I.ii.34", num34.annotations["citation"]
  end

  def test_gap_renders_the_house_lacuna_marker
    text = unit("antiquities/Latin/book-03.xml", "num239").text
    assert text.end_with?("et hedum pro peccatis.[…]"), text
  end

  def test_breaks_are_silent_and_collected
    num1 = unit("antiquities/Latin/preface.xml", "num1")
    assert num1.text.start_with?("Historiam conscribere disponentibus non unam"), num1.text
    assert_equal ["1r"], num1.annotations["pb"]
    assert_equal %w[2 3 4], num1.annotations["niese"]
    num2 = unit("deh/Latin/book-02.xml", "num2")
    assert_includes num2.text, "Caesari uel senatui", "a word-internal-safe pb adds no space"
    assert_equal %w[130 131 132], num2.annotations["pb"]
  end

  def test_inline_notes_and_standoff_readings_become_ms_annotations_once
    annotations = unit("antiquities/Latin/book-01.xml", "num34").annotations["ms_annotations"]
    assert_equal [
      { "witness" => "BernBBMs118", "type" => "certainty", "text" => "[¤2v] (§) dicit (@1) issa (#2 nota NT)" },
      { "witness" => "RomeBAVPalLat814", "text" => "[¤2r](¬1)mulier" }
    ], annotations, "the standOff copies of the inline notes fold once"
    num27 = unit("antiquities/Latin/book-01.xml", "num27").annotations["ms_annotations"]
    assert_includes num27, { "witness" => "BernBBMs118", "text" => "[¤2r] (@1 correction avec signe) lucem" },
                    "a standOff-only reading joins the inline notes"
    refute_includes unit("antiquities/Latin/book-01.xml", "num27").text, "arcam dicit"
  end

  def test_header_witness_list_is_returned
    witnesses = parse("antiquities/Latin/book-01.xml").witnesses
    assert_equal "Bern BB Ms. 50 (Ant. I–XII & Guerre)", witnesses["BernBBMs50"]
  end

  def test_malformed_xml_is_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "broken.xml")
      File.write(path, File.read(File.join(FIXTURES, "assets/xml/antiquities/Latin/preface.xml"))[0, 500])
      assert_raises(Nabu::ParseError) { Nabu::Adapters::JosephusLatinTeiParser.new.parse(path) }
    end
  end
end
