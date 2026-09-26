# frozen_string_literal: true

require "test_helper"
require "stringio"

# CbetaTeiParser (the `cbeta-tei` family, P33-2) against real T and X
# fixtures: print-line grain riding the lb/@n citation verbatim, own-canon
# lb stream only (witness R-edition streams never mint), stand-off <back>
# apparatus never read, gaiji/inline-note annotations, and the per-file
# availability license gate quoted byte-verbatim.
class CbetaTeiParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("cbeta")

  T85 = File.join(FIXTURES, "T", "T85", "T85n2884.xml")
  T01 = File.join(FIXTURES, "T", "T01", "T01n0001-xu.xml")
  X01 = File.join(FIXTURES, "X", "X01", "X01n0001.xml")
  X55 = File.join(FIXTURES, "X", "X55", "X55n0899.xml")

  def parse(path, urn: "urn:nabu:cbeta:#{File.basename(path, '.xml')}", canon: File.basename(path)[0])
    Nabu::Adapters::CbetaTeiParser.new.parse(path, urn: urn, canon: canon)
  end

  # --- the print-line grain: the Taishō citation rides free ------------------

  def test_t85n2884_mints_print_lines_under_the_lb_citation
    document = parse(T85)
    urns = document.map(&:urn)
    # 9 lb lines in the body; 3 are blank layout lines (a19/a20/a23) and
    # emit nothing.
    assert_equal %w[1390a21 1390a22 1390a24 1390a25 1390a26 1390a27]
      .map { |cite| "urn:nabu:cbeta:T85n2884:#{cite}" }, urns
    by_cite = document.to_h { |p| [p.urn.split(":").last, p] }
    assert_equal "若有善男子、善女人，不將澡豆洗手捉經，及", by_cite["1390a24"].text
    assert_equal "No. 2884", by_cite["1390a21"].text
    assert_equal "大威儀請問", by_cite["1390a22"].text
    document.each { |passage| assert_equal "lzh", passage.language }
  end

  def test_document_metadata_carries_title_grant_witnesses_and_idno
    document = parse(T85)
    assert_equal "大威儀請問", document.title
    assert_equal "lzh", document.language
    assert_equal Nabu::Adapters::CbetaTeiParser::AVAILABILITY_GRANT, document.metadata["license"]
    assert_equal ["【CB】", "【大】"], document.metadata["witnesses"]
    assert_equal %w[T 85 2884], document.metadata.values_at("canon", "vol", "no")
  end

  # --- the header byline harvest (P104-1, №R-70 grade 2) ---------------------
  #
  # The teiHeader <author> carries CBETA's own attribution byline —
  # "<dynasty seat> <person(s)><role char>" ("後秦 佛陀耶舍共竺佛念譯",
  # "明 洪恩輯") — which previously flowed nowhere: the dating posture sat
  # `undatable` while every text carried a translation-era claim.

  def test_header_author_byline_mints_dynasty_and_translator
    metadata = parse(T01).metadata
    assert_equal "後秦 佛陀耶舍共竺佛念譯", metadata["author"], "the byline rides verbatim"
    assert_equal "後秦", metadata["dynasty"]
    assert_equal "佛陀耶舍共竺佛念", metadata["translator"]
    assert_equal({ "value" => "後秦", "raw" => "後秦 佛陀耶舍共竺佛念譯" }, metadata["facets"]["dynasty"])
    assert_equal "佛陀耶舍共竺佛念", metadata["facets"]["translator"]["value"]
  end

  def test_header_author_compiler_byline_mints_dynasty_without_translator
    metadata = parse(X55).metadata
    assert_equal "明 洪恩輯", metadata["author"]
    assert_equal "明", metadata["dynasty"]
    assert_nil metadata["translator"], "輯 is a compiler, not a translator"
    assert_nil metadata["facets"]["translator"]
    assert_equal "明", metadata["facets"]["dynasty"]["value"]
  end

  def test_empty_or_absent_header_author_mints_no_attribution
    [T85, X01].each do |path|
      metadata = parse(path).metadata
      assert_nil metadata["author"]
      assert_nil metadata["dynasty"]
      assert_nil metadata["facets"], "#{File.basename(path)}: no byline — no claim invented"
    end
  end

  # The structural split on censused byline shapes (2026-09-26, whole-
  # corpus census over 3,707 headers): the dynasty is the short bare
  # token before the final role-suffixed token — an Indian master's
  # attribution (…造) is itself role-suffixed and never mistaken for a
  # seat; a lone 失譯 ("translator lost") claims nothing.
  def test_byline_attribution_split_shapes
    split = Nabu::Adapters::CbetaTeiParser.method(:byline_attribution)
    assert_equal({ dynasty: "陳", translator: "真諦" }, split.call("天親菩薩造 陳 真諦譯"))
    assert_equal({ dynasty: "唐", translator: "玄奘" }, split.call("唐 玄奘譯"))
    assert_equal({ dynasty: "宋", translator: "天竺三藏求那跋陀羅" },
                 split.call("宋 天竺三藏求那跋陀羅譯"))
    assert_equal "法賢", split.call("宋 法賢奉詔譯")[:translator], "the 奉詔 decree tail strips"
    assert_empty split.call("失譯")
    assert_empty split.call("龍樹菩薩造"), "an authored śāstra without a seat claims no era"
    assert_equal({ dynasty: "日本" }, split.call("日本 圓仁撰"),
                 "a country seat rides the facet; the band table honestly has no row for it")
  end

  # The in-file grant the gate pins, byte-verbatim (censused identical
  # across all sampled T and X files at upstream 2026.R1).
  def test_the_availability_grant_constant_is_the_censused_sentence
    assert_equal "Available for non-commercial use when distributed with this header intact.",
                 Nabu::Adapters::CbetaTeiParser::AVAILABILITY_GRANT
  end

  # --- gaiji: text kept, refs annotated verbatim, never resolved -------------

  def test_gaiji_text_stays_in_the_line_and_the_ref_rides_annotations
    passage = parse(T85).find { |p| p.urn.end_with?("1390a27") }
    assert_includes passage.text, "㖒", "the <g> element's Unicode text stays in the reading text"
    assert_equal ["#CB00762"], passage.annotations["gaiji"]
  end

  # --- the stand-off back matter is never read -------------------------------

  def test_back_matter_apparatus_and_notes_never_reach_passages
    all_text = parse(T85).map(&:text).join
    refute_includes all_text, "大英博物館", "the taisho-notes back division must not be read"
    xu = parse(T01)
    xu_text = xu.map(&:text).join
    refute_includes xu_text, "Dīrgha-āgama", "back cb:tt foot glosses must not be read"
    refute_includes xu_text, "校注", "the apparatus division head must not be read"
  end

  # T01n0001's apparatus is stand-off: the body byline carries the reading
  # text with anchors, transparently.
  def test_anchors_are_transparent_in_the_reading_text
    by_cite = parse(T01).to_h { |p| [p.urn.split(":").last, p] }
    assert_equal "長安釋僧肇述", by_cite["0001a04"].text
  end

  # --- verse: lg/l transparent at line grain, caesura contributes nothing ----

  def test_verse_lines_keep_their_own_print_citation
    by_cite = parse(T01).to_h { |p| [p.urn.split(":").last, p] }
    assert_equal "「比丘集法堂，講說賢聖論；", by_cite["0001c03"].text
    assert_equal "無上天人尊，記於過去佛。」", by_cite["0001c12"].text
    assert_equal "夫宗極絕於稱謂，賢聖以之沖默；玄旨非言", by_cite["0001a05"].text
  end

  def test_juan_annotation_tracks_the_fascicle_milestone
    document = parse(T01)
    assert_equal "1", document.first.annotations["juan"]
    assert_equal "長阿含經", document.title
  end

  # --- only the file's own canon siglum mints --------------------------------

  def test_witness_edition_lb_streams_never_mint
    document = parse(X01)
    urns = document.map(&:urn)
    assert_includes urns, "urn:nabu:cbeta:X01n0001:0001a06"
    refute(urns.any? { |urn| urn.include?("0705") },
           "the interleaved ed=\"R150\" 卍續藏經 stream is another print run's layout")
    by_cite = document.to_h { |p| [p.urn.split(":").last, p] }
    assert_equal "余嚮偶獲古宋本《大方廣圓覺修多羅了義經》下", by_cite["0001a06"].text
  end

  # --- interlinear notes: dropped from text, carried as annotations ----------

  def test_inline_notes_ride_annotations_not_the_reading_text
    by_cite = parse(X01).to_h { |p| [p.urn.split(":").last, p] }
    line = by_cite["0001a08"]
    assert_equal "閬巷內李三二郎印行」之記。今撿尋其文，「汝", line.text
    assert_equal %w[一行 二行], line.annotations["notes"]
  end

  # --- upstream attribute-order variance (censused, not assumed) -------------

  def test_ed_before_n_attribute_order_parses_identically
    by_cite = parse(X55).to_h { |p| [p.urn.split(":").last, p] }
    assert_equal "諸法本因曰正理，徹諸法本因曰正智。理由智顯，宗", by_cite["0471c08"].text
    # The cb:mulu TOC entry duplicating the <head> is dropped; the head's
    # own print lines keep their text.
    assert_equal "No. 899-A", by_cite["0471c05"].text
    assert_equal "因明入正理論題辭", by_cite["0471c06"].text
  end

  # --- the license gate and the canon identity check, both loud --------------

  def test_a_drifted_availability_grant_refuses_the_document
    drifted = File.read(T85).sub("Available for non-commercial use", "Available for any use")
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CbetaTeiParser.new.parse(
        StringIO.new(drifted), urn: "urn:nabu:cbeta:T85n2884", canon: "T", canonical_path: T85
      )
    end
    assert_match(/license gate/, error.message)
  end

  def test_a_canon_mismatch_refuses_the_document
    error = assert_raises(Nabu::ParseError) { parse(X01, canon: "T") }
    assert_match(/canon mismatch/, error.message)
  end

  def test_malformed_xml_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::CbetaTeiParser.new.parse(
        StringIO.new("<TEI><teiHeader>"), urn: "urn:nabu:cbeta:broken", canon: "T",
                                          canonical_path: "broken.xml"
      )
    end
    assert_match(/malformed XML|no <text><body>/, error.message)
  end
end
