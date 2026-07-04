# frozen_string_literal: true

require "test_helper"
require "stringio"
require "digest"

# DdbdpParser unit tests against the three real DDbDP fixtures (P3-6):
# bgu.1.102 and bgu.1.100 (Greek, flat <ab>, heavy app/choice/subst markup)
# and c.epist.lat.10 (Latin, recto/verso textpart divs, expan/ex, middots).
# Every expected string below is derived from the fixture bytes under the
# Leiden text-extraction policy documented in the parser header (keep
# lem/reg/add/supplied/unclear/expan+ex/num, drop rdg/orig/del/note/figure,
# gap → "[…]" marker, line = passage).
class DdbdpParserTest < Minitest::Test
  FIXTURES = File.expand_path("../fixtures/ddbdp/DDB_EpiDoc_XML", __dir__)
  BGU102 = File.join(FIXTURES, "bgu", "bgu.1", "bgu.1.102.xml")
  BGU100 = File.join(FIXTURES, "bgu", "bgu.1", "bgu.1.100.xml")
  CEL10 = File.join(FIXTURES, "c.epist.lat", "c.epist.lat.10.xml")

  BGU102_URN = "urn:nabu:ddbdp:bgu:1:102"
  BGU100_URN = "urn:nabu:ddbdp:bgu:1:100"
  # ddb-hybrid "c.epist.lat;;10" has an EMPTY volume segment; the frozen
  # ";"→":" minting rule preserves it as an empty urn segment ("::").
  CEL10_URN = "urn:nabu:ddbdp:c.epist.lat::10"

  # P5-1 fixtures (copied whole 2026-07-04 from the locally synced snapshot;
  # see test/fixtures/papyri-ddbdp/README.md): the line-number-restart
  # exemplar and a genuinely text-less cross-reference stub.
  PAPYRI_FIXTURES = File.expand_path("../fixtures/papyri-ddbdp/DDB_EpiDoc_XML", __dir__)
  AEG240 = File.join(PAPYRI_FIXTURES, "aegyptus", "aegyptus.89", "aegyptus.89.240.xml")
  CW101 = File.join(PAPYRI_FIXTURES, "chrest.wilck", "chrest.wilck.101.xml")

  AEG240_URN = "urn:nabu:ddbdp:aegyptus:89:240"
  CW101_URN = "urn:nabu:ddbdp:chrest.wilck::101"

  # P6-2 fixture (copied whole 2026-07-04, same provenance as the others):
  # the cancelled-but-legible exemplar — every line of the edition sits
  # inside <del rend="erasure">, so the blanket drop-<del> policy extracts
  # zero citable lines and the document quarantined.
  OC457 = File.join(PAPYRI_FIXTURES, "o.claud", "o.claud.3", "o.claud.3.457.xml")
  OC457_URN = "urn:nabu:ddbdp:o.claud:3:457"

  def parser
    Nabu::Adapters::DdbdpParser.new
  end

  def parse102
    parser.parse(BGU102, urn: BGU102_URN, language: "grc", title: "bgu.1.102")
  end

  def parse100
    parser.parse(BGU100, urn: BGU100_URN, language: "grc", title: "bgu.1.100")
  end

  def parse_cel10
    parser.parse(CEL10, urn: CEL10_URN, language: "lat", title: "c.epist.lat.10")
  end

  # --- document + line minting (bgu.1.102) ---------------------------------

  def test_document_fields
    document = parse102
    assert_equal BGU102_URN, document.urn
    assert_equal "grc", document.language
    assert_equal "bgu.1.102", document.title
    assert_equal BGU102, document.canonical_path
  end

  def test_bgu102_nine_lb_milestones_become_nine_line_passages
    # The fixture has exactly nine <lb> milestones (n="1"…"9"), all in kept
    # content and none extracting empty, so nine passages.
    document = parse102
    assert_equal 9, document.size
    assert_equal (1..9).map { |n| "#{BGU102_URN}:#{n}" }, document.map(&:urn)
    assert_equal (0..8).to_a, document.map(&:sequence)
  end

  # --- app/lem/rdg: lem kept, rdg dropped (bgu.1.102 line 1) ---------------

  def test_app_keeps_lem_and_drops_rdg_entirely
    # Line 1: <app type="editorial"> whose <lem resp="BL 1.20"> spells
    # οἰκονόμου out of unclear+supplied fragments and whose <rdg> holds the
    # ed.pr. reading κο plus three <gap>s. Policy: lem IS the reading text;
    # rdg vanishes INCLUDING its gaps — no "[…]" may leak out of a dropped
    # subtree.
    line = parse102.first
    assert_equal "Θεόφιλος Λουκιφέρου Καίσαρος οἰκονόμου οὐικάριος", line.text
    refute_includes line.text, "[…]"
    # lem content: <unclear>ο κ ν μ</unclear> → 4, <supplied>ἰ ό ο</supplied> → 3.
    assert_equal({ "leiden" => { "supplied_chars" => 3, "unclear_chars" => 4 } }, line.annotations)
  end

  # --- choice/reg/orig: hand-verified line (bgu.1.102 line 2) --------------

  def test_choice_keeps_reg_and_drops_orig_hand_verified
    # Fixture bytes for line 2 (bgu.1.102):
    #   <lb n="2"/>διεγράφην παρὰ <choice><reg>πρεσβυτέρων</reg>
    #     <orig>προσβυτέρω<supplied reason="lost">ν</supplied></orig></choice>
    #   καὶ <choice><reg>κωμογραμματέως</reg><orig>κωμογραμματαίος</orig></choice>
    # Policy application, worked by hand:
    #   keep "διεγράφην παρὰ " · keep reg "πρεσβυτέρων" · drop orig
    #   "προσβυτέρω[ν]" wholesale (the <supplied>ν</supplied> inside it drops
    #   TOO, so supplied_chars stays 0) · keep " καὶ " · keep reg
    #   "κωμογραμματέως" · drop orig "κωμογραμματαίος" · collapse + strip.
    line = parse102.to_a[1]
    assert_equal "διεγράφην παρὰ πρεσβυτέρων καὶ κωμογραμματέως", line.text
    assert_equal({}, line.annotations, "supplied inside a dropped <orig> must not be counted")
  end

  def test_choice_inside_lem_inside_app_nested_keep_stack
    # Line 3 nests <choice><reg> INSIDE <app><lem> (Σοκνοπαίων), plus a
    # supplied-wrapped <expan><ex>ἔτους</ex></expan> and <num>α</num>.
    assert_equal "κώμης Σοκνοπαίων Νήσου φόρου προβάτων ἔτους α", parse102.to_a[2].text
  end

  # --- gap marker + annotations ---------------------------------------------

  def test_gap_contributes_a_single_marker_and_length_data_goes_to_annotations
    # Line 6 ends <num value="8">η</num> <gap reason="illegible" quantity="3"
    # unit="character"/> inside the kept <lem>: one "[…]" regardless of
    # quantity; the length data lives in annotations only.
    line = parse102.to_a[5]
    assert_equal "καὶ Οὐήρου τῶν κυρίων Σεβαστῶν Ἐπεὶφ η […]", line.text
    assert_equal [{ "reason" => "illegible", "quantity" => 3, "unit" => "character" }],
                 line.annotations.dig("leiden", "gaps")
  end

  def test_mid_word_gap_stays_fused_and_handshift_is_annotation_only
    # Line 7: <handShift new="m2"/> then Αἴλιος <gap reason="lost"
    # quantity="2" unit="character"/>θως … — the marker replaces the lost
    # letters IN PLACE (no space invented: "[…]θως"), and the hand change is
    # metadata, not text.
    line = parse102.to_a[6]
    assert_equal "Αἴλιος […]θως ἐπηκολούθησα ταῖς τοῦ ἀργυρίου", line.text
    assert_equal(
      { "leiden" => {
        "gaps" => [{ "reason" => "lost", "quantity" => 2, "unit" => "character" }],
        "supplied_chars" => 1,
        "hands" => ["m2"]
      } }, line.annotations
    )
  end

  # --- text_normalized -------------------------------------------------------

  def test_text_normalized_is_the_minted_search_form
    line = parse102.first
    # Boundary-minted (P6-4): marks stripped, downcased, final sigma → σ.
    assert_equal "θεοφιλοσ λουκιφερου καισαροσ οικονομου ουικαριοσ", line.text_normalized
    assert line.text_normalized.unicode_normalized?(:nfc)
  end

  # --- subst/add/del: the πεπρακέναι correction (bgu.1.100 lines 2-3) -------

  def test_bgu100_twelve_lines
    document = parse100
    assert_equal 12, document.size
    assert_equal (1..12).map { |n| "#{BGU100_URN}:#{n}" }, document.map(&:urn)
  end

  def test_subst_keeps_add_and_drops_del_across_the_line_boundary
    # Lines 2-3 carry the scribe's correction:
    #   <subst><add place="inline"><choice><reg>πε<lb n="3" break="no"/>πρακέναι</reg>
    #     <orig>πε<lb n="3" break="no"/>πρακέν<add place="above">ε</add></orig></choice></add>
    #   <del rend="corrected">πε<lb n="3" break="no"/>πρακεν<del rend="erasure">αι</del></del></subst>
    # Policy: the <add> (final intent) is kept and its <reg> read; the <del>
    # (with its NESTED del) drops wholesale. Only the KEPT branch's
    # <lb n="3" break="no"/> is a line boundary — the copies inside <orig>
    # and <del> are dropped with their subtrees, or line 3 would be minted
    # three times. break="no" splits the word πεπρακέναι across the citable
    # lines exactly as a print edition's line numbers do.
    document = parse100.to_a
    assert_equal "Πεκύσι Ὥρου χαίρειν. ὁμολογῶ πε", document[1].text
    assert_equal "πρακέναι σοι κάμηλον θήλειαν δ", document[2].text
    assert_equal({}, document[1].annotations)
  end

  def test_empty_num_element_contributes_nothing
    # Line 9: τα <num value="780"/> καὶ … — the empty <num> milestone (its
    # value is metadata) must not leave a hole or a marker.
    assert_equal "τα καὶ βεβαιώσω πάσῃ βεβαιώσει.", parse100.to_a[8].text
    assert_equal "Τῦβι η.", parse100.to_a[11].text
  end

  # --- c.epist.lat.10: Latin, textparts, expan/ex, <g> middots --------------

  def test_cel10_textpart_paths_in_urns
    # div type="textpart" n="r" (10 lines) and n="v" (1 line): the textpart
    # path joins the urn between document urn and line number.
    document = parse_cel10
    assert_equal "lat", document.language
    assert_equal 11, document.size
    assert_equal (1..10).map { |n| "#{CEL10_URN}:r:#{n}" } + ["#{CEL10_URN}:v:1"],
                 document.map(&:urn)
  end

  def test_expansions_read_expanded_and_middot_glyphs_vanish
    # Recto line 1: <expan>plur<ex>imam</ex></expan> → "plurimam" etc.;
    # <g type="middot"/> interpuncts contribute nothing (word boundaries come
    # from the editorial spacing already present in the text nodes).
    assert_equal "Syneros Chio suo plurimam salutem si vales bene est Theo adduxit ad me Ohapim",
                 parse_cel10.first.text
  end

  def test_standalone_add_is_kept_and_in_word_middot_does_not_split
    # Recto line 5: <add place="above">vel … maxima</add> outside any <subst>
    # is a scribal insertion — reading text. And <reg>de<g type="middot"/>
    # monstrabit</reg> must yield "demonstrabit": if <g> contributed a space
    # the regularized word would be torn apart.
    line = parse_cel10.to_a[4]
    assert_equal "pernicies hominibus est vel maxima deinde ipse tibi demonstrabit", line.text
    assert_equal({ "leiden" => { "supplied_chars" => 1, "unclear_chars" => 2 } }, line.annotations)
  end

  def test_standalone_del_drops_with_its_gap
    # Recto line 9: <del rend="erasure">fidem … <gap reason="illegible" …/>
    # ista …</del> — erased text is not reading text; the gap INSIDE the del
    # neither marks the text nor lands in annotations.
    line = parse_cel10.to_a[8]
    assert_equal "divom atque hominum", line.text
    assert_equal({}, line.annotations)
  end

  def test_verso_line
    assert_equal "Chio Caesaris", parse_cel10.to_a.last.text
  end

  # --- restart-aware minting (P5-1): implicit blocks on urn collision -------

  def parse_aeg240
    parser.parse(AEG240, urn: AEG240_URN, language: "grc", title: "aegyptus.89.240")
  end

  def test_restart_document_parses_with_unique_block_indexed_urns
    # aegyptus.89.240: one flat <ab>, NO textpart divs, and the line
    # numbering restarts twice — <lb n="1"/> appears twice (a lost-line
    # marker block, then the main text 1..11) and <lb n="11"/> appears twice
    # (line 11, then a trailing lost-line marker block). Before P5-1 this
    # was the duplicate-passage-urn quarantine class (12,288 docs in the
    # 2026-07-04 sync). Policy: the first collision opens implicit block
    # "b2", the next one "b3" — every line from a collision on carries its
    # block segment between textpart path and line number.
    document = parse_aeg240
    expected = ["#{AEG240_URN}:1"] +
               (1..11).map { |n| "#{AEG240_URN}:b2:#{n}" } +
               ["#{AEG240_URN}:b3:11"]
    assert_equal expected, document.map(&:urn)
    assert_equal document.map(&:urn), document.map(&:urn).uniq, "urns must be unique"
  end

  def test_restart_document_line_texts_spot_checks
    document = parse_aeg240.to_a
    # Both restart blocks are lost-line markers: a single <gap unit="line"/>.
    assert_equal "[…]", document.first.text
    assert_equal "[…]", document.last.text
    # A real text line from the main block (b2, line 5), derived from the
    # fixture bytes: plain text + one <supplied reason="lost"> restoration.
    line5 = document.find { |passage| passage.urn == "#{AEG240_URN}:b2:5" }
    assert_equal "θώτου, λιβὸς δημοσία ῥύμη ἐν ᾗ εἴσοδος καὶ ἔξοδος τῆς οἰκίας δεῖνος", line5.text
  end

  def test_restart_urns_are_stable_across_two_independent_parses
    assert_equal parse_aeg240.map(&:urn), parse_aeg240.map(&:urn)
  end

  # --- golden regression (P5-1 frozen-urn safety) ----------------------------
  #
  # Restart-aware minting must leave every document that parsed cleanly
  # before P5-1 byte-identical: block segments appear ONLY after a
  # within-document urn collision, which by definition never happens in a
  # cleanly parsed document. These three lists are the complete known-good
  # urns of all pre-P5-1 papyri fixtures, captured before the change.
  def test_golden_urn_lists_of_pre_existing_fixtures_are_byte_identical
    assert_equal (1..9).map { |n| "#{BGU102_URN}:#{n}" }, parse102.map(&:urn),
                 "bgu.1.102 (flat, no restarts) urns must be unchanged by restart-aware minting"
    assert_equal (1..12).map { |n| "#{BGU100_URN}:#{n}" }, parse100.map(&:urn),
                 "bgu.1.100 (flat, no restarts) urns must be unchanged by restart-aware minting"
    assert_equal (1..10).map { |n| "#{CEL10_URN}:r:#{n}" } + ["#{CEL10_URN}:v:1"], parse_cel10.map(&:urn),
                 "c.epist.lat.10 (textpart divs) urns must be unchanged by restart-aware minting"
  end

  # --- cancelled-document fallback (P6-2): whole-document <del> in ⟦⟧ --------

  def parse_oc457
    parser.parse(OC457, urn: OC457_URN, language: "grc", title: "o.claud.3.457")
  end

  def test_cancelled_document_recovers_with_leiden_double_brackets
    # o.claud.3.457: both lines sit inside per-line <del rend="erasure"> —
    # under the standard drop-<del> policy the document extracts ZERO citable
    # lines. The P6-2 fallback re-reads exactly that class with <del> kept,
    # wrapped in Leiden double brackets ⟦…⟧ (ancient cancellation, fully
    # legible — print editions read it). The standard keep/drop policy still
    # applies INSIDE the kept del: line 2's <app> keeps its <lem> ("παρ",
    # with an <unclear>ρ</unclear>) and drops its <rdg>.
    document = parse_oc457
    assert_equal ["#{OC457_URN}:1", "#{OC457_URN}:2"], document.map(&:urn)
    assert_equal "⟦Κύνων Ζήνωνος Εἰσίω-⟧", document.first.text
    assert_equal "⟦νι χαίρειν. ὁμολογῶ παρ⟧", document.to_a[1].text
  end

  def test_cancelled_lines_carry_the_cancelled_annotation
    document = parse_oc457.to_a
    assert_equal({ "leiden" => { "cancelled" => true } }, document[0].annotations)
    assert_equal({ "leiden" => { "unclear_chars" => 1, "cancelled" => true } },
                 document[1].annotations)
  end

  def test_cancelled_document_urns_and_text_stable_across_two_parses
    first = parse_oc457
    second = parse_oc457
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
  end

  def test_cancelled_document_fallback_rewinds_and_works_from_an_open_io
    # The fallback is a second Reader pass over the same source; when the
    # source is an IO (not a path) it must rewind before re-reading.
    document = File.open(OC457, "r") do |io|
      parser.parse(io, urn: OC457_URN, language: "grc", canonical_path: OC457)
    end
    assert_equal ["#{OC457_URN}:1", "#{OC457_URN}:2"], document.map(&:urn)
    assert_equal "⟦Κύνων Ζήνωνος Εἰσίω-⟧", document.first.text
  end

  def test_partial_dels_in_documents_with_citable_lines_never_gain_brackets
    # The fallback is DOCUMENT-scoped: it engages only when the standard
    # policy leaves zero citable lines. c.epist.lat.10 has partial dels
    # (recto line 9's erasure) AND citable text, so its dels keep dropping —
    # no ⟦⟧ may appear anywhere in it, byte-frozen behavior.
    document = parse_cel10
    document.each do |passage|
      refute_match(/[⟦⟧]/, passage.text, "#{passage.urn} must not gain cancellation brackets")
    end
    assert_equal "divom atque hominum", document.to_a[8].text
  end

  # --- golden text regression (P6-2 frozen-text safety) ----------------------
  #
  # The cancelled-document fallback must leave every document that extracts
  # at least one citable line byte-identical — the fallback pass runs ONLY
  # when the standard pass yields zero lines, which by definition never
  # happens for a loaded document. These sha256s (over the parsed passage
  # texts joined with "\n") were captured from the pre-P6-2 parser.
  GOLDEN_TEXT_SHA256 = {
    "bgu.1.102" => "64d39af962444877f338011edd6c5e4ce714706f17125fbc8b23735cd84ba793",
    "bgu.1.100" => "edff3565f13448c65e35220334c7b2a5ea5c8f9327e69ab9b4083ec1f4d5040f",
    "c.epist.lat.10" => "b40ef5143bcdd47a1fb22146d2d81e1a358ea70511cccc68ea70a9682cbd610b",
    "aegyptus.89.240" => "ea17abe89429a38f6be6970de969ab4aa80393bf654635e755292a079a32f201"
  }.freeze

  def test_golden_text_sha256_of_pre_existing_fixtures_are_byte_identical
    {
      "bgu.1.102" => parse102, "bgu.1.100" => parse100,
      "c.epist.lat.10" => parse_cel10, "aegyptus.89.240" => parse_aeg240
    }.each do |name, document|
      sha = Digest::SHA256.hexdigest(document.map(&:text).join("\n"))
      assert_equal GOLDEN_TEXT_SHA256.fetch(name), sha,
                   "#{name}: passage text must be byte-identical to the pre-P6-2 parse"
    end
  end

  # --- text-less stubs still quarantine (P5-1) -------------------------------

  def test_text_less_stub_still_quarantines_with_a_clear_message
    # chrest.wilck.101 is a cross-reference stub (empty <ab/>; the header
    # points at the reprint, P.Enteux. 13). It must keep quarantining — the
    # restart fix must not widen what counts as citable.
    error = assert_raises(Nabu::ParseError) do
      parser.parse(CW101, urn: CW101_URN, language: "grc", title: "chrest.wilck.101")
    end
    assert_match(/no citable lines/, error.message)
    assert_includes error.message, CW101, "the message must name the offending file"
  end

  # --- inline language annotation (string surgery; none in the fixtures) ----

  def test_inline_xml_lang_differing_from_document_language_is_annotated
    xml = File.read(BGU100).sub("Ἡρακλείτου", %(<foreign xml:lang="la">Ἡρακλείτου</foreign>))
    document = parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc",
                                               canonical_path: "surgery.xml")
    line = document.first
    assert_equal "Κόμων Μουσαίου τοῦ Ἡρακλείτου", line.text
    assert_equal ["lat"], line.annotations["languages"], "inline la must be recorded mapped to lat"
    assert_nil parse100.first.annotations["languages"], "unmodified fixture has no inline languages"
  end

  # --- lines that extract empty are skipped ----------------------------------

  def test_lines_left_empty_after_extraction_are_skipped
    xml = File.read(BGU100).sub("</ab>", %(<lb n="13"/><del rend="erasure">νν</del></ab>))
    document = parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc",
                                               canonical_path: "surgery.xml")
    assert_equal 12, document.size
    refute_includes document.map(&:urn), "#{BGU100_URN}:13"
  end

  # --- error paths ------------------------------------------------------------

  def test_missing_ddb_hybrid_idno_raises_parse_error
    xml = File.read(BGU100).sub(%r{<idno type="ddb-hybrid">[^<]*</idno>}, "")
    error = assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc", canonical_path: "surgery.xml")
    end
    assert_match(/ddb-hybrid/, error.message)
  end

  def test_urn_not_matching_ddb_hybrid_minting_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parser.parse(BGU100, urn: "urn:nabu:ddbdp:bgu:1:999", language: "grc")
    end
    assert_match(/urn mismatch/, error.message)
  end

  def test_language_mismatch_raises_parse_error
    error = assert_raises(Nabu::ParseError) do
      parser.parse(BGU100, urn: BGU100_URN, language: "lat")
    end
    assert_match(/language mismatch/, error.message)
  end

  def test_edition_language_la_maps_to_lat_for_the_cross_check
    # c.epist.lat.10's edition div says xml:lang="la"; the caller (adapter)
    # says "lat". The la→lat mapping must make these agree, not error.
    assert_equal "lat", parse_cel10.language
  end

  def test_zero_citable_lines_raises_parse_error
    xml = File.read(BGU100).sub(%r{<ab>.*</ab>}m, "<ab>\n</ab>")
    error = assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc", canonical_path: "surgery.xml")
    end
    assert_match(/no citable lines/, error.message)
  end

  def test_lb_without_n_raises_parse_error
    xml = File.read(BGU100).sub('<lb n="1"/>', "<lb/>")
    error = assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc", canonical_path: "surgery.xml")
    end
    assert_match(/<lb>.*missing.*@n/, error.message)
  end

  def test_malformed_xml_raises_parse_error
    xml = File.read(BGU100)[0, 400]
    assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc", canonical_path: "surgery.xml")
    end
  end

  # --- io + streaming discipline ----------------------------------------------

  def test_parses_from_an_open_io_with_explicit_canonical_path
    document = File.open(BGU102, "r") do |io|
      parser.parse(io, urn: BGU102_URN, language: "grc", canonical_path: BGU102)
    end
    assert_equal 9, document.size
    assert_equal BGU102, document.canonical_path
  end

  def test_io_without_path_requires_canonical_path
    assert_raises(ArgumentError) do
      parser.parse(StringIO.new("<x/>"), urn: BGU102_URN, language: "grc")
    end
  end

  def test_implementation_streams_and_never_builds_a_full_document_dom
    source = File.read(File.expand_path("../../lib/nabu/adapters/ddbdp_parser.rb", __dir__))
    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end
end
