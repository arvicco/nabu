# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TipitakaLkJsonParser (the `tipitaka-lk-json` family): one tipitaka.lk text
# file (public/static/text/<file>.json) — a list of printed BJT pages, each
# carrying a Pāli and a Sinhala column of entries that upstream's own build
# validates as index-aligned pairs. One parse yields ONE layer of the file
# (pali → pli, sinh → si); the passage citation is <pageNum>.<entry n>, the
# same on both layers, so the Sinhala sibling aligns to the Pāli by suffix.
#
# The inline markup is upstream's own (shared/markup.ts): **bold** __under__
# ~~strike~~ $$editorial$$ {fn} \n/↴ <hr/>; passage text is upstream's own
# plain rendering of it (tokensToPlain: markers dropped, footnote pointers
# dropped, line breaks kept), and the pointers resolve to the page's
# footnotes per passage.
class TipitakaLkJsonParserTest < Minitest::Test
  TEXT = File.join(Nabu::TestSupport.fixtures("tipitaka-lk"), "public/static/text")
  KHP = File.join(TEXT, "kn-khp.json")
  ATTA = File.join(TEXT, "atta-an-11.json")
  PAT = File.join(TEXT, "ap-pat-2-83.json")

  Markup = Nabu::Adapters::TipitakaLkJsonParser::Markup

  def parse(path, layer:, urn: "urn:nabu:tipitaka-lk:test")
    Nabu::Adapters::TipitakaLkJsonParser.new.parse(path, urn: urn, layer: layer)
  end

  def passage(document, suffix)
    document.find { |p| p.urn == "#{document.urn}:#{suffix}" } || flunk("no passage #{suffix} in #{document.urn}")
  end

  # -- the markup port (upstream's parseMarkup + tokensToPlain) ----------------

  def test_markup_plain_drops_markers_and_footnote_pointers
    rendered = Markup.render("**අත්ථෙන අත්ථො**ති අත්ථෙන{2} සද්ධිං")
    assert_equal "අත්ථෙන අත්ථොති අත්ථෙන සද්ධිං", rendered.text
    assert_equal ["අත්ථෙන අත්ථො"], rendered.bold
    assert_equal ["2"], rendered.footnote_refs
  end

  def test_markup_unbalanced_markers_render_literally
    assert_equal "a ** b", Markup.render("a ** b").text, "an unclosed pair is plain text (upstream rule)"
    assert_equal "x {} y", Markup.render("x {} y").text, "an empty brace is not a footnote pointer"
  end

  def test_markup_line_breaks_entities_and_dropped_tags
    assert_equal "a\nb\nc", Markup.render("a↴b<hr/>c").text
    assert_equal "<x> & y", Markup.render("&lt;x&gt; &amp; <b>y</b>").text
  end

  def test_markup_editorial_and_highlight_alone_still_render
    # Regression: each opener alone must leave the fast path (a "#$" in the
    # trigger class once interpolated a global and dropped both).
    assert_equal "ed x", Markup.render("$$ed$$ x").text
    assert_equal "hit", Markup.render("##hit##").text
    assert_equal "a # b $ c", Markup.render("a # b $ c").text
  end

  def test_markup_containers_nest_and_keep_their_content
    rendered = Markup.render("__u **b** u__ $$ed$$ ~~s~~")
    assert_equal "u b u ed s", rendered.text, "tokensToPlain keeps every container's content"
    assert_equal ["b"], rendered.bold
  end

  # -- the Pāli layer ----------------------------------------------------------

  def test_pali_layer_cites_page_and_entry_and_carries_the_entry_shape
    document = parse(KHP, layer: "pali")
    assert_equal "pli", document.language
    first = document.first
    assert_equal "urn:nabu:tipitaka-lk:test:2.1", first.urn, "printed BJT page 2, entry 1"
    assert_equal "සුත්තන්තපිටකෙ", first.text
    assert_equal({ "type" => "centered", "level" => 3, "page" => 2, "attribution" => "tipitaka.lk" },
                 first.annotations)
    assert_equal "බුද්ධං සරණං ගච්ඡාමි.", passage(document, "2.7").text
  end

  def test_footnote_pointers_resolve_to_the_pages_footnotes
    heading = passage(parse(KHP, layer: "pali"), "2.6")
    assert_equal "1. සරණගමනං", heading.text, "the {1} pointer leaves the reading text"
    assert_equal({ "1" => "සරණත්තයං – මඡසං" }, heading.annotations["footnotes"],
                 "the variant reading and its witness siglum, verbatim")
  end

  def test_gatha_line_breaks_survive_and_empty_entries_skip_by_rule
    document = parse(KHP, layer: "pali")
    verse = passage(document, "6.3")
    assert_equal "gatha", verse.annotations["type"]
    assert_equal "1. බහූ දෙවා මනුස්සා ච මඞ්ගලානි අචින්තයුං,\nආකඞ්ඛමානා සොත්ථානං බ්රූහි මඞ්ගලමුත්තමං.", verse.text
    assert_nil document.find { |p| p.urn.end_with?(":6.4") },
               "page 6 entry 4 is empty on the Pāli side — skipped, never renumbered"
    assert_equal 1, document.metadata["empty_entries_skipped"]
    assert_equal 66, document.size
  end

  def test_document_title_is_the_first_heading_and_metadata_is_upstreams
    document = parse(KHP, layer: "pali")
    assert_equal "ඛුද්දකපාඨපාළි", document.title
    metadata = document.metadata
    assert_equal "kn-khp", metadata["file"]
    assert_equal 28, metadata["book_id"]
    assert_equal [2, 18], metadata["pages"]
    assert_equal "tipitaka.lk", metadata["attribution"]
  end

  def test_bold_spans_ride_annotations_in_the_commentary
    paragraph = passage(parse(ATTA, layer: "pali"), "1.8")
    assert_equal ["අත්ථෙන අත්ථො", "බ්යඤ්ජනෙන බ්යඤ්ජන", "සංසන්දිස්සතී", "සමෙස්සතී",
                  "න විග්ගය්හිස්සතී", "අග්ගපදස්මි"], paragraph.annotations["bold"],
                 "the commentary's emphasized lemmata (upstream's ** spans)"
    assert paragraph.text.start_with?("සත්තමෙ අත්ථෙන අත්ථොති අත්ථෙන සද්ධිමත්ථො.")
  end

  def test_key_offset_rides_verbatim
    assert_equal 7, passage(parse(ATTA, layer: "pali"), "1.7").annotations["key_offset"]
  end

  # -- the Sinhala layer -------------------------------------------------------

  def test_sinhala_layer_aligns_by_the_same_suffix
    document = parse(KHP, layer: "sinh")
    assert_equal "si", document.language
    assert_equal "ඛුද්දකපාඨ පෙළ", document.title
    assert_equal "බුදුරජුන් සරණයෙමි (පිහිට යැ යි දැන ගණිමි.)", passage(document, "2.7").text
    assert_equal "[බුදුරජුහු වදාළහ:]", passage(document, "6.4").text,
                 "the Sinhala side keeps the entry the Pāli side leaves empty"
    assert_equal 67, document.size
  end

  def test_sinhala_footnotes_resolve_on_their_own_column
    entry = passage(parse(KHP, layer: "sinh"), "18.4")
    assert_match(/\A7\. චෛත්‍යය කෙරෙහිද/, entry.text)
    assert_match(/\Aඒ චෛත්‍යය වනාහි/, entry.annotations.fetch("footnotes").fetch("1"))
  end

  def test_pali_only_files_have_an_empty_sinhala_layer
    assert_equal 11, parse(PAT, layer: "pali").size
    assert_equal 0, parse(PAT, layer: "sinh").size, "the Paṭṭhāna is served Pāli-only upstream"
  end

  def test_malformed_json_raises_parse_error
    Dir.mktmpdir("nabu-tipitaka-bad") do |dir|
      path = File.join(dir, "kn-bad.json")
      File.write(path, "{\"pages\": [")
      assert_raises(Nabu::ParseError) { parse(path, layer: "pali") }
    end
  end
end
