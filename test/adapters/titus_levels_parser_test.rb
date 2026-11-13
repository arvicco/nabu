# frozen_string_literal: true

require "test_helper"

# The titus_levels parser family's own rules, on minimal pages in the
# family's exact markup (the real-page behaviour is pinned by the three
# adapter tests against their restricted local fixtures): which headers
# open a unit, how the lanes classify, and the quarantine rules.
class TitusLevelsParserTest < Minitest::Test
  PARSER = Nabu::Adapters::TitusLevelsParser
  LANES = PARSER::Lanes.new(prefixes: %w[bpal baal], text_flavors: "bijklrx", others: { /\Awela/ => "latin" })

  def parse(body, lanes: LANES)
    PARSER.parse("<html><body>#{body}</body></html>", lanes: lanes, label: "test")
  end

  def line(number, anchor, kind: "XLevel 5")
    %(<span id=h5><!#{kind}>Line: #{number}<A NAME="#{anchor}">&nbsp;</A></sPAN>&nbsp;)
  end

  def test_an_xlevel_line_opens_a_unit_but_an_xlevel_page_does_not
    units = parse(<<~HTML)
      <span id=h3><!Level 3>Part: I._Decal.<A NAME="Mazv._Cat._I._Decal.">&nbsp;</A></sPAN><BR>
      #{line(9, 'Mazv._Cat._I._Decal._18/22_9')}<span id=bpal16>Pirma</span><BR>
      <span id=h4><!XLevel 4>Page: 19/23<A NAME="Mazv._Cat._I._Decal._19/23">&nbsp;</A></sPAN><BR>
      #{line(1, 'Mazv._Cat._I._Decal._19/23_1')}<span id=bpal16>Antras</span>
    HTML
    assert_equal %w[Mazv._Cat._I._Decal._18/22_9 Mazv._Cat._I._Decal._19/23_1], units.map(&:anchor)
    assert_equal %w[Pirma Antras], units.map(&:text)
    assert_equal({}, units.first.location)
    assert_equal({ "page" => "19/23" }, units.last.location, "the page header runs on to the next unit")
  end

  def test_a_level_header_without_text_is_no_unit
    units = parse(<<~HTML)
      <span id=h3><!Level 3>Page: 1r<A NAME="WP_1r">&nbsp;</A></sPAN><BR>
      #{line(1, 'WP_1r_1', kind: 'Level 4')}<span id=bpal16>NEDEELIAN</span>
    HTML
    assert_equal ["WP_1r_1"], units.map(&:anchor)
    assert_equal({ "page" => "1r" }, units.first.location)
  end

  def test_a_reference_belongs_to_its_own_unit_only
    units = parse(<<~HTML)
      #{line(5, 'WP_1r_5', kind: 'Level 4')}<span id=bpal16>Ewangelista</span>
      <span id=nc16><span id=h5><!XLevel 5>Reference: Mt._21_1<A NAME="WP_1r_5_Mt._21_1">&nbsp;</A></sPAN> </span>
      <span id=bpalk16>Ir kad</span><BR>
      #{line(6, 'WP_1r_6', kind: 'Level 4')}<span id=bpal16>priſsiartino</span>
    HTML
    assert_equal({ "reference" => "Mt._21_1" }, units.first.location)
    assert_equal "Ewangelista Ir kad", units.first.text, "the quotation-class flavor k is text"
    assert_equal({}, units.last.location)
  end

  def test_other_language_lanes_ride_annotations_and_never_make_a_unit
    units = parse(<<~HTML)
      #{line(1, 'X_1', kind: 'Level 4')}<span id=wela16>CAPITVLVM</span><BR>
      #{line(2, 'X_2', kind: 'Level 4')}<span id=wela16>Bernhardus </span><span id=bpal16>iſchraſcha</span>
    HTML
    assert_equal ["X_2"], units.map(&:anchor), "a Latin-only line is not a passage"
    assert_equal "iſchraſcha", units.first.text
    assert_equal({ "latin" => "Bernhardus" }, units.first.others)
  end

  def test_apparatus_flavors_footnotes_and_note_quotations_are_not_text
    units = parse(<<~HTML)
      #{line(1, 'X_1', kind: 'Level 4')}<span id=bpal16>Ir</span><span id=bpalv16><a><span id="fn"><sup>*</sup></span></a></span>
      <span id=baalf12>a footnote</span><span id=nc12>Special signs:</span><span id=bpalx12>ξ</span><span id=nc12> = th</span>
    HTML
    assert_equal ["Ir"], units.map(&:text)
  end

  def test_a_typographic_mark_stays_in_the_running_text
    runs = "<span id=bpal16>Pſ: 109 </span><span id=tm16>&amp;</span><span id=bpal16> 131.</span>"
    units = parse("#{line(1, 'X_1', kind: 'Level 4')}#{runs}")
    assert_equal "Pſ: 109 & 131.", units.first.text
  end

  def test_a_flavor_annotation_lane_rides_its_own_key
    lanes = PARSER::Lanes.new(prefixes: %w[bual], text_flavors: "bx", flavor_annotations: { "i" => "interpretation" })
    body = "#{line(1, 'M_1', kind: 'Level 5')}<span id=bual16>EMBSUAME</span><BR><span id=buali16>Mbësuame</span>"
    units = parse(body, lanes: lanes)
    assert_equal "EMBSUAME", units.first.text
    assert_equal({ "interpretation" => "Mbësuame" }, units.first.extras)
  end

  def test_a_header_reopening_the_open_anchor_continues_the_unit
    units = parse(<<~HTML)
      <span id=h3><!Level 3>Sentence: 1<A NAME="Brokm._1_1">&nbsp;</A></sPAN><span id=bpal16>Thit ist</span>
      <span id=h3><!Level 3>Sentence: 1<A NAME="Brokm._1_1">&nbsp;</A></sPAN><span id=bpal16>thiu kere</span>
    HTML
    assert_equal ["Thit ist thiu kere"], units.map(&:text)
  end

  # --- quarantines ----------------------------------------------------------

  def test_an_unknown_content_lane_quarantines
    error = assert_raises(Nabu::ParseError) { parse(%(#{line(1, 'X_1', kind: 'Level 4')}<span id=roit16>Italiano</span>)) }
    assert_match(/unknown content lane "roit16"/, error.message)
  end

  def test_an_unknown_flavor_of_the_language_lane_quarantines
    error = assert_raises(Nabu::ParseError) { parse(%(#{line(1, 'X_1', kind: 'Level 4')}<span id=bpalq16>?</span>)) }
    assert_match(/unknown lane flavor "bpalq16"/, error.message)
  end

  def test_language_text_before_any_unit_header_quarantines
    error = assert_raises(Nabu::ParseError) { parse("<span id=bpal16>stray words</span>") }
    assert_match(/before any unit header/, error.message)
  end

  def test_the_discovery_needle_sees_text_flavors_but_not_footnote_lanes
    assert_match LANES.needle, "<span id=bpalx16>"
    assert_match LANES.needle, "<span id=baalr16>"
    refute_match LANES.needle, "<span id=baalf12>"
    refute_match LANES.needle, "<span id=bpalv16>"
  end
end
