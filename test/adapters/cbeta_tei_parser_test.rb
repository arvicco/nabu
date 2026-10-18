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
  T85_2831 = File.join(FIXTURES, "T", "T85", "T85n2831.xml")
  T10 = File.join(FIXTURES, "T", "T10", "T10n0285.xml")
  K05 = File.join(FIXTURES, "K", "K05", "K05n0016.xml")
  T01 = File.join(FIXTURES, "T", "T01", "T01n0001-xu.xml")
  X01 = File.join(FIXTURES, "X", "X01", "X01n0001.xml")
  X55 = File.join(FIXTURES, "X", "X55", "X55n0899.xml")
  J36 = File.join(FIXTURES, "J", "J36", "J36nB354.xml")
  N26 = File.join(FIXTURES, "N", "N26", "N26n0008.xml")
  N44 = File.join(FIXTURES, "N", "N44", "N44n0021-xu.xml")

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

  # --- the header byline harvest (P104-1, attributed-era dating) --------------
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

  # --- the body <byline> harvest: persons with typed roles -------------------
  #
  # Body bylines carry CBETA's typed role (cb:type author/Translator/editor/
  # Collector/other…) and name preface and sub-work authors the header
  # never does (T01's preface by 釋僧肇). Names ride verbatim (the reading
  # text of the byline, anchors transparent); the ASCII role folds case.

  def test_body_bylines_ride_as_persons_with_roles
    metadata = parse(T01).metadata
    assert_equal [{ "name" => "長安釋僧肇述", "role" => "author" },
                  { "name" => "後秦弘始年佛陀耶舍共竺佛念譯", "role" => "translator" }],
                 metadata["persons"]
    assert_nil metadata["byline_authors"], "the header names an author — no byline author facet"
  end

  def test_untyped_and_other_bylines_keep_their_claim
    assert_equal [{ "name" => "西晉月支三藏竺法護譯" }], parse(T10).metadata["persons"]
    assert_equal [{ "name" => "侍者超常記錄", "role" => "other" }], parse(J36).metadata["persons"]
    assert_equal [{ "name" => "唐三藏法師玄奘譯", "role" => "translator" }],
                 parse(K05).metadata["persons"]
  end

  def test_author_byline_feeds_the_author_field_when_the_header_is_silent
    metadata = parse(T85_2831).metadata
    assert_nil metadata["author"], "the header <author> is empty"
    assert_equal [{ "name" => "釋菩提達摩製", "role" => "author" }], metadata["persons"]
    assert_equal ["釋菩提達摩製"], metadata["byline_authors"]
  end

  def test_fileless_bylines_mint_no_persons
    assert_nil parse(T85).metadata["persons"]
    assert_nil parse(T85).metadata["byline_authors"]
  end

  def test_repeated_bylines_dedupe_per_name_and_role
    xml = File.read(K05).sub(%r{(<byline cb:type="translator">唐三藏法師玄奘譯</byline>)}, '\1\1')
    document = Nabu::Adapters::CbetaTeiParser.new.parse(
      StringIO.new(xml), urn: "urn:nabu:cbeta:K05n0016", canon: "K", canonical_path: K05
    )
    assert_equal [{ "name" => "唐三藏法師玄奘譯", "role" => "translator" }], document.metadata["persons"]
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

  # --- per-canon language: the J and N canons (P126) --------------------------
  #
  # J (嘉興藏, the Ming–Qing Jiaxing canon) is Literary Chinese like T/X/K
  # and rides lzh. N (漢譯南傳大藏經, Yuan Heng Temple edition) is a
  # 20th-century CHINESE translation of the Pāli Tipiṭaka (made from the
  # Japanese Nanden daizōkyō) — modern written Chinese, never the lzh claim:
  # it rides cmn (the classical-modern translation-sibling precedent) and
  # records its Pāli source in metadata.

  def test_language_is_assigned_per_canon
    language_for = Nabu::Adapters::CbetaTeiParser.method(:language_for)
    %w[T X K J].each { |canon| assert_equal "lzh", language_for.call(canon), canon }
    assert_equal "cmn", language_for.call("N")
  end

  def test_j_canon_rides_lzh_with_its_ming_byline
    document = parse(J36)
    assert_equal "lzh", document.language
    document.each { |passage| assert_equal "lzh", passage.language }
    assert_equal "錦屏破石卓禪師雜著", document.title
    assert_equal "明", document.metadata["dynasty"], "明 悟卓說　超常記錄　發林行狀 — the seat splits on U+3000 too"
    line = document.find { |p| p.urn.end_with?(":0545a04") }
    assert_equal "出欄群牧童兒犢，蹶矣酣兮無箇亍，快爽風雲得自", line.text
    assert_nil document.metadata["translated_from"], "J is native Chinese composition"
  end

  def test_n_canon_is_modern_chinese_translated_from_pali
    document = parse(N26)
    assert_equal "cmn", document.language
    document.each { |passage| assert_equal "cmn", passage.language }
    assert_equal "小誦經", document.title
    assert_equal "pli", document.metadata["translated_from"]
    assert_match(/南傳大藏經/, document.metadata["translation_basis"])
    assert_equal "悟醒", document.metadata["translator"]
    assert_nil document.metadata["dynasty"], "a modern translator byline carries no dynasty seat"
    line = document.find { |p| p.urn.end_with?(":0001a07") }
    assert_equal "我歸依佛，我歸依法，我歸依僧伽。我再歸依佛，我再歸依法，我再歸依僧伽。", line.text
  end

  # N files anchor their Pāli source with empty <ref cRef="PTS.Khp.1"/>
  # milestones (Pali Text Society page references) — carried verbatim per
  # line as the "cref" annotation, never reading text. Censused absent from
  # every held T/X/K file.
  def test_cref_milestones_ride_the_line_annotation
    document = parse(N26)
    line = document.find { |p| p.urn.end_with?(":0001a03") }
    assert_equal "歸命彼世尊應供等覺者", line.text
    assert_equal ["PTS.Khp.1"], line.annotations["cref"]
    head = parse(N44).find { |p| p.urn.end_with?(":0267a07") }
    assert_equal "第二 僧伽所行", head.text
    assert_equal ["PTS.Cp.74"], head.annotations["cref"]
    parse(T85).each { |passage| assert_nil passage.annotations["cref"] }
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
