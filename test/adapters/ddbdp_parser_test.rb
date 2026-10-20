# frozen_string_literal: true

require "test_helper"
require "stringio"
require "digest"
require "json"

# DdbdpParser unit tests against the three real DDbDP fixtures (P3-6):
# bgu.1.102 and bgu.1.100 (Greek, flat <ab>, heavy app/choice/subst markup)
# and c.epist.lat.10 (Latin, recto/verso textpart divs, expan/ex, middots).
# Every expected string below is derived from the fixture bytes under the
# Leiden text-extraction policy documented in the parser header (keep
# lem/reg/add/supplied/unclear/expan+ex/num, drop rdg/orig/note/figure,
# render del in Leiden double brackets ⟦…⟧ — owner-ruled 2026-08-10, conventions.md §5 —
# gap → "[…]" marker, line = passage).
class DdbdpParserTest < Minitest::Test
  # The upstream layout since the 2026-07 switchover (see the Papyri adapter
  # header): curated texts under DDbDP/<HGV-thousand>/<HGV>.xml, texts not
  # yet curated under Historical/<collection>/(<volume>/)?<number>.xml.
  FIXTURES = File.expand_path("../fixtures/ddbdp", __dir__)
  BGU102 = File.join(FIXTURES, "DDbDP", "8", "8877.xml")
  BGU100 = File.join(FIXTURES, "DDbDP", "8", "8875.xml")
  CEL10 = File.join(FIXTURES, "Historical", "c.epist.lat", "10.xml")

  BGU102_URN = "urn:nabu:ddbdp:bgu:1:102"
  BGU100_URN = "urn:nabu:ddbdp:bgu:1:100"
  # ddb-hybrid "c.epist.lat;;10" has an EMPTY volume segment; the frozen
  # ";"→":" minting rule preserves it as an empty urn segment ("::").
  CEL10_URN = "urn:nabu:ddbdp:c.epist.lat::10"

  # P5-1 fixtures (re-cut whole from the post-switchover upstream tree;
  # see test/fixtures/papyri-ddbdp/README.md): the line-number-restart
  # exemplar and a genuinely text-less cross-reference stub.
  PAPYRI_FIXTURES = File.expand_path("../fixtures/papyri-ddbdp", __dir__)
  AEG240 = File.join(PAPYRI_FIXTURES, "DDbDP", "25", "25457.xml")
  CW101 = File.join(PAPYRI_FIXTURES, "Historical", "chrest.wilck", "101.xml")

  AEG240_URN = "urn:nabu:ddbdp:aegyptus:89:240"
  CW101_URN = "urn:nabu:ddbdp:chrest.wilck::101"

  # P6-2 fixture (re-cut whole, same provenance as the others):
  # the cancelled-but-legible exemplar — every line of the edition sits
  # inside <del rend="erasure">. Under the original blanket drop-<del>
  # policy it quarantined; P6-2 recovered it via a document-scoped
  # fallback; the owner ruling of 2026-08-10 made the ⟦…⟧ rendering unconditional.
  OC457 = File.join(PAPYRI_FIXTURES, "DDbDP", "73", "73640.xml")
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
    # The rdg's gaps never reach the leiden certainty data; the rdg itself
    # survives only as the line's "apparatus" annotation (tested below).
    assert_equal({ "leiden" => { "supplied_chars" => 3, "unclear_chars" => 4 } },
                 line.annotations.except("apparatus"))
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

  def test_subst_renders_del_in_brackets_and_suppresses_its_duplicate_lb_copy
    # Lines 2-3 carry the scribe's correction:
    #   <subst><add place="inline"><choice><reg>πε<lb n="3" break="no"/>πρακέναι</reg>
    #     <orig>πε<lb n="3" break="no"/>πρακέν<add place="above">ε</add></orig></choice></add>
    #   <del rend="corrected">πε<lb n="3" break="no"/>πρακεν<del rend="erasure">αι</del></del></subst>
    # The del ruling (conventions.md §5): the <add> (final intent) is kept and its
    # <reg> read; the <del> now renders too, in Leiden double brackets —
    # its NESTED del nests its own pair (the two-stage correction: first
    # ⟦αι⟧ erased, then the whole word corrected). Upstream duplicates the
    # <lb> into BOTH subst branches so either branch reads alone
    # (bgu.1.100's revision history); with both branches kept, only the
    # <add> copy is a line boundary — the del branch's copy is the SAME
    # physical line break and must not fire (a second firing would collide
    # and re-mint frozen urns via the implicit-block machinery). The
    # <orig> branch still drops with its copy. break="no" splits the word
    # πεπρακέναι across the citable lines exactly as a print edition's
    # line numbers do.
    document = parse100.to_a
    assert_equal "Πεκύσι Ὥρου χαίρειν. ὁμολογῶ πε", document[1].text
    assert_equal "πρακέναι⟦πεπρακεν⟦αι⟧⟧ σοι κάμηλον θήλειαν δ", document[2].text
    assert_equal({}, document[1].annotations)
    assert_equal({ "leiden" => { "cancelled" => true } }, document[2].annotations)
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

  def test_standalone_del_renders_in_brackets_with_its_gap_marking
    # Recto line 9: <del rend="erasure">fidem … <gap reason="illegible" …/>
    # ista …</del> — the del ruling (conventions.md §5): erased-but-legible text IS
    # reading text, printed inside Leiden double brackets ⟦…⟧; the gap
    # INSIDE the kept del marks the text ("[…]ista", fused where the lost
    # letter sat) and lands in annotations like any other gap.
    line = parse_cel10.to_a[8]
    assert_equal "divom atque hominum ⟦fidem si tu […]ista non cuibis⟧", line.text
    assert_equal(
      { "leiden" => {
        "gaps" => [{ "reason" => "illegible", "quantity" => 1, "unit" => "character" }],
        "cancelled" => true
      } }, line.annotations
    )
  end

  def test_partial_del_renders_in_place_at_line_end
    # Recto line 3 ends "… loquor quam <del rend="erasure">no</del>" — the
    # partial cancellation (the scribe started "no(n)…", crossed it out and
    # restarted on line 4 "ne patiaris…") renders in place, and the line
    # carries the cancelled annotation.
    line = parse_cel10.to_a[2]
    assert_equal "de improbitate Epaphraes itaque nihil ultra loquor quam ⟦no⟧", line.text
    assert_equal({ "leiden" => { "cancelled" => true } }, line.annotations)
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

  # --- cancelled documents (P6-2 → the del ruling): whole-document <del> in ⟦⟧ --

  def parse_oc457
    parser.parse(OC457, urn: OC457_URN, language: "grc", title: "o.claud.3.457")
  end

  def test_cancelled_document_reads_in_leiden_double_brackets
    # o.claud.3.457: both lines sit inside per-line <del rend="erasure"> —
    # the whole document is an ancient cancellation, fully legible, and
    # print editions read it inside Leiden double brackets ⟦…⟧. Under the del ruling
    # every <del> renders that way in the single standard pass (the P6-2
    # document-scoped fallback is retired; its output for this class is
    # UNCHANGED — same urns, same text, same annotations). The keep/drop
    # policy still applies INSIDE the kept del: line 2's <app> keeps its
    # <lem> ("παρ", with an <unclear>ρ</unclear>) and drops its <rdg>.
    document = parse_oc457
    assert_equal ["#{OC457_URN}:1", "#{OC457_URN}:2"], document.map(&:urn)
    assert_equal "⟦Κύνων Ζήνωνος Εἰσίω-⟧", document.first.text
    assert_equal "⟦νι χαίρειν. ὁμολογῶ παρ⟧", document.to_a[1].text
  end

  def test_cancelled_lines_carry_the_cancelled_annotation
    document = parse_oc457.to_a
    assert_equal({ "leiden" => { "cancelled" => true } }, document[0].annotations)
    assert_equal({ "leiden" => { "unclear_chars" => 1, "cancelled" => true } },
                 document[1].annotations.except("apparatus"))
  end

  def test_app_inside_a_kept_cancellation_records_its_apparatus
    # Line 2's <app type="alternative"> sits inside the kept <del>: kept
    # content, so it is recorded; the del opened before the app, so its
    # bracket belongs to the line text, not to the lemma.
    assert_equal [{ "type" => "alternative", "lemma" => "παρ", "readings" => [{ "text" => "παι" }] }],
                 parse_oc457.to_a[1].annotations["apparatus"]
  end

  def test_cancelled_document_urns_and_text_stable_across_two_parses
    first = parse_oc457
    second = parse_oc457
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text), second.map(&:text)
  end

  def test_cancelled_document_parses_from_an_open_io
    # Single standard pass under the del ruling — no rewind, no retry — so an open
    # IO source works exactly as for any other document.
    document = File.open(OC457, "r") do |io|
      parser.parse(io, urn: OC457_URN, language: "grc", canonical_path: OC457)
    end
    assert_equal ["#{OC457_URN}:1", "#{OC457_URN}:2"], document.map(&:urn)
    assert_equal "⟦Κύνων Ζήνωνος Εἰσίω-⟧", document.first.text
  end

  # --- golden text regression (recaptured at the del ruling, P79-3a) ---------
  #
  # These sha256s (over the parsed passage texts joined with "\n") pin the
  # fixture output against accidental drift. bgu.1.100 and c.epist.lat.10
  # were deliberately re-captured for the 2026-08-10 del→⟦…⟧ migration (their
  # dels now render — THE ruled corpus revision, conventions.md §5);
  # bgu.1.102 and aegyptus.89.240 contain no <del> and remain byte-identical
  # to the pre-P6-2 capture, proving the migration touches only del-bearing
  # documents.
  GOLDEN_TEXT_SHA256 = {
    "bgu.1.102" => "64d39af962444877f338011edd6c5e4ce714706f17125fbc8b23735cd84ba793",
    "bgu.1.100" => "d6d22e9c6a3bd6c77b42d8eaf1c3710aa94889800309ec69b5f3e30ec3e2848d",
    "c.epist.lat.10" => "e8e50782f86a7fadbc6940001ea0ba23a4b8dc4da23e0465cc128dacd0a6fbf5",
    "aegyptus.89.240" => "ea17abe89429a38f6be6970de969ab4aa80393bf654635e755292a079a32f201"
  }.freeze

  def test_golden_text_sha256_of_fixtures_are_byte_identical
    {
      "bgu.1.102" => parse102, "bgu.1.100" => parse100,
      "c.epist.lat.10" => parse_cel10, "aegyptus.89.240" => parse_aeg240
    }.each do |name, document|
      sha = Digest::SHA256.hexdigest(document.map(&:text).join("\n"))
      assert_equal GOLDEN_TEXT_SHA256.fetch(name), sha,
                   "#{name}: passage text must be byte-identical to the recorded capture"
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

  def test_del_only_lines_are_citable_under_always_render
    # Before the del ruling a line whose only content sat in a <del> extracted empty
    # and was skipped; now the del renders, the line is citable — this is
    # the resurrection class the migration recovers (79-3b must expect NEW
    # passage urns, not just revised text, and sequence shifts after them).
    xml = File.read(BGU100).sub("</ab>", %(<lb n="13"/><del rend="erasure">νν</del></ab>))
    document = parser.parse(StringIO.new(xml), urn: BGU100_URN, language: "grc",
                                               canonical_path: "surgery.xml")
    assert_equal 13, document.size
    assert_equal "⟦νν⟧", document.to_a.last.text
    assert_equal "#{BGU100_URN}:13", document.to_a.last.urn
  end

  def test_lines_left_empty_after_extraction_are_skipped
    xml = File.read(BGU100).sub("</ab>", %(<lb n="13"/><note>editorial noise</note></ab>))
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

  # --- the apparatus layer: <app> → per-line "apparatus" annotations ---------
  #
  # The lemma stays the passage text exactly as before; every <app> in kept
  # content becomes one entry on the line where it opens: its @type, the
  # rendered lemma, the lemma's @resp, and each <rdg> rendered under the same
  # Leiden policy (gap → "[…]", reg over orig, del in ⟦…⟧, nested app → its
  # lem, with the nested app recorded on the reading) plus the reading's
  # @resp. Line breaks inside a lemma or reading render as " | " ("|" glued
  # for break="no").

  # p.select;;16 (DDbDP/35/35046.xml, whole) — multi-reading apps with
  # per-reading @resp, an empty <rdg/>, apps nested in lemmas and in
  # readings, and a lemma/reading pair spanning a line break.
  PSELECT16 = File.join(PAPYRI_FIXTURES, "DDbDP", "35", "35046.xml")
  PSELECT16_URN = "urn:nabu:ddbdp:p.select::16"
  # sb;30;17872 (DDbDP/135/135776.xml, whole) — a two-line alternative
  # whose lemma breaks plainly and whose reading breaks with break="no".
  SB30_17872 = File.join(PAPYRI_FIXTURES, "DDbDP", "135", "135776.xml")
  SB30_17872_URN = "urn:nabu:ddbdp:sb:30:17872"
  DCLP64388 = File.join(FIXTURES, "DCLP", "64", "64388.xml")

  def parse_pselect16
    parser.parse(PSELECT16, urn: PSELECT16_URN, language: "grc")
  end

  def line_of(document, number)
    document.find { |passage| passage.urn == "#{document.urn}:#{number}" }
  end

  def only(items)
    assert_equal 1, Array(items).size, "expected exactly one item, got #{items.inspect}"
    items.first
  end

  def test_apparatus_entry_carries_type_lemma_resp_and_rendered_reading
    # bgu.1.102 line 1: <lem resp="BL 1.20"> spells οἰκονόμου; the <rdg>
    # (ed.pr.) reads κ<unclear>ο</unclear> + three <gap>s.
    line = parse102.first
    assert_equal [{ "type" => "editorial", "lemma" => "οἰκονόμου", "resp" => "BL 1.20",
                    "readings" => [{ "text" => "κο[…][…][…]" }] }],
                 line.annotations["apparatus"]
  end

  def test_alternative_apparatus_without_resp_and_two_entries_on_one_line
    # aegyptus.89.240 line 4 carries two <app type="alternative"> side by side.
    entries = parse_aeg240.flat_map { |passage| Array(passage.annotations["apparatus"]) }
    assert_includes entries, { "type" => "alternative", "lemma" => "ὠνουμένη",
                               "readings" => [{ "text" => "ὠνουμένῃ" }] }
    assert_includes entries, { "type" => "alternative", "lemma" => "Ἰσαροῦς",
                               "readings" => [{ "text" => "Ἰσάριον" }] }
  end

  def test_reading_resp_is_recorded_per_reading_in_the_dclp_family
    document = Nabu::Adapters::DdbdpParser.new(idno_type: "dclp", urn_namespace: "dclp")
                                          .parse(DCLP64388, urn: "urn:nabu:dclp:64388", language: "grc")
    entries = document.flat_map { |passage| Array(passage.annotations["apparatus"]) }
    assert_equal [{ "type" => "editorial", "lemma" => "πεπέρεως", "resp" => "ed.alt.",
                    "readings" => [{ "text" => "πιπέρεως", "resp" => "ed.pr." }] }], entries
  end

  def test_multiple_readings_keep_order_resp_and_an_empty_reading
    # Line 16: lem (BL 12.114) against four readings — two attributed, one
    # bare "ed", and an empty <rdg/> (the reading omits the lemma).
    entry = only(line_of(parse_pselect16, 16).annotations["apparatus"])
    assert_equal "[…] χιλίων καὶ δισκάρια", entry["lemma"]
    assert_equal "BL 12.114", entry["resp"]
    assert_equal [{ "text" => "[…] δισκάρια", "resp" => "Original Edition" },
                  { "text" => "[…] δισκάρια", "resp" => "BL 7.99" },
                  { "text" => "ed" },
                  { "text" => "" }], entry["readings"]
  end

  def test_reading_renders_under_the_leiden_policy_and_records_its_nested_apparatus
    # Line 4: a reading's <choice> keeps reg (Ἑρμουπόλεως) and drops orig;
    # the BL 10.113 reading is itself an alternative app with an empty lem —
    # its text is that lemma (empty), its rdg rides as nested apparatus.
    entry = only(line_of(parse_pselect16, 4).annotations["apparatus"])
    assert_equal "ἀπὸ κώμης […] τοῦ Ἑρμουπολίτου νομοῦ", entry["lemma"]
    assert_equal "H. Maehler, ZPE 25 (1977) 193-194 (BL 7.99)", entry["resp"]
    assert_equal [
      { "text" => "[…] ἀπὸ τῆς Ἑρμουπόλεως", "resp" => "P.J. Sijpesteijn, ZPE 19 (1975) 270-271 (BL 7.99)" },
      { "text" => "[…]Ερμοπόλεως", "resp" => "Original Edition" },
      { "text" => "", "resp" => "BL 10.113",
        "apparatus" => [{ "type" => "alternative", "lemma" => "", "readings" => [{ "text" => "Ἑρμοπολίτου" }] }] }
    ], entry["readings"]
  end

  def test_doubly_nested_apparatus_inside_a_reading
    # Line 7: the reading nests an editorial app whose lemma nests an
    # alternative app — both recorded on the reading, in document order.
    entry = only(line_of(parse_pselect16, 7).annotations["apparatus"])
    assert_equal "καὶ φοίνιξιν διακείμενον ἐν πεδιάδι", entry["lemma"]
    reading = only(entry["readings"])
    assert_equal "καὶ φοίνιξιν ἐν πεδιάδι", reading["text"]
    assert_equal [{ "type" => "editorial", "lemma" => "ἐν πεδιάδι",
                    "resp" => "P.J. Sijpesteijn, ZPE 19 (1975) 271 (BL 7.99)",
                    "readings" => [{ "text" => "ἐν πεδίῳ περὶ" }] },
                  { "type" => "alternative", "lemma" => "ἐν πεδιάδι",
                    "readings" => [{ "text" => "ἐν τῷ λιβὶ" }] }], reading["apparatus"]
  end

  def test_app_nested_in_a_lemma_is_its_own_entry_after_the_outer_one
    entries = line_of(parse_pselect16, 9).annotations["apparatus"]
    assert_equal(["καλαμοστασίαν καὶ περίσκαψιν", "καλαμοστασίαν"], entries.map { |entry| entry["lemma"] })
    assert_equal [{ "text" => "[…] καὶ περίσκαψιν", "resp" => "P.J. Sijpesteijn, ZPE 19 (1975) 271 (BL 7.99)" },
                  { "text" => "[…] καλαμοστασίαν ἐμὴν" }], entries.first["readings"]
    assert_equal [{ "text" => "βοτανολογίαν" }], entries.last["readings"]
  end

  def test_line_spanning_apparatus_lands_on_its_opening_line_with_line_dividers
    document = parse_pselect16
    entry = only(line_of(document, 19).annotations["apparatus"])
    assert_equal "Αὐρήλιος Ταυρῖνος Γενναδίου ἀξιωθεὶς | ἔγραψα ὑπὲρ αὐτοῦ παρόντος γράμματα μὴ εἰδότος",
                 entry["lemma"]
    assert_equal [{ "text" => "Αὐρήλιος Ταυρῖνος Γενναδίου | ἔγραψα ὑπὲρ αὐτοῦ γράμματα μὴ εἰδότος" }],
                 entry["readings"]
    refute line_of(document, 20).annotations.key?("apparatus"), "the entry is recorded once, where it opens"
  end

  def test_break_no_line_divider_glues_and_plain_divider_spaces
    document = parser.parse(SB30_17872, urn: SB30_17872_URN, language: "grc")
    assert_equal ["[…]α", "ρια."], document.map(&:text)
    assert_equal [{ "type" => "alternative", "lemma" => "[…]α | ρια",
                    "readings" => [{ "text" => "Μα|κα|ρία" }] }],
                 document.first.annotations["apparatus"]
  end

  def test_lines_without_an_app_carry_no_apparatus_key
    refute line_of(parse_pselect16, 1).annotations.key?("apparatus")
    assert(parse_cel10.none? { |passage| passage.annotations.key?("apparatus") })
  end

  # The byte-identity proof: every fixture parses to the same urns, texts and
  # pre-existing annotations as the parser did before the apparatus layer
  # (digests captured from the pre-change parser; the "apparatus" key is the
  # only addition). Digest = SHA-256 of JSON [[urn, text, annotations−apparatus]…].
  PRE_APPARATUS_DIGESTS = {
    ["ddbdp/DCLP/62/62952.xml", "urn:nabu:dclp:62952", "lat"] =>
      [7, "4de9c583be2bcf7cd38101ee3cab0e96b8d7d6f9f0592cd9c48fba5214ea825d"],
    ["ddbdp/DCLP/64/64388.xml", "urn:nabu:dclp:64388", "grc"] =>
      [11, "a5782b7ad673ae584fe5ef2df1c8fc239a2a4df762aa06265a19b3f143fc06b3"],
    ["ddbdp/DCLP/805/805566.xml", "urn:nabu:dclp:805566", "grc"] =>
      [7, "2cfbe82c96db34e96c662a713af7297415f24c7cd06882a119629cdef201996b"],
    ["ddbdp/DDbDP/13/13581.xml", "urn:nabu:ddbdp:p.tebt:2:484v", "grc"] =>
      [2, "476fa9313eb60e242b0a087c9a1fd0c24677ebec7604d72bff16da989eaa394e"],
    ["ddbdp/DDbDP/2/2416.xml", "urn:nabu:ddbdp:p.ryl:4:560", "grc"] =>
      [7, "70728746812a8125c47cce7e12b7905616415ab306350f0b04fdbf0f5b6d1ef3"],
    ["ddbdp/DDbDP/8/8875.xml", BGU100_URN, "grc"] =>
      [12, "04901746a5e4349aca5842b9affd32ef841c2f95431aa9e4d5c7a53c67b21a0a"],
    ["ddbdp/DDbDP/8/8877.xml", BGU102_URN, "grc"] =>
      [9, "d3a534b5c6129d29960d9cb8a03fd39a38a3f40b1866fda480685cf2f2fc05fd"],
    ["ddbdp/Historical/c.epist.lat/10.xml", CEL10_URN, "lat"] =>
      [11, "f71e18fdb504c963ef29f02a9fb648e03c8bc100148c9eff1dd160cfc4cb22a8"],
    ["papyri-ddbdp/DDbDP/25/25457.xml", AEG240_URN, "grc"] =>
      [13, "88cfbbf454fbfd54d5824c4009d97db378c51a8383a3ecbc4da4b5e1e0585d34"],
    ["papyri-ddbdp/DDbDP/35/35046.xml", PSELECT16_URN, "grc"] =>
      [22, "e4760c4774a6d33ebd412862ad85529ee8a2a538db0492ce30e135ddfb7de012"],
    ["papyri-ddbdp/DDbDP/73/73640.xml", OC457_URN, "grc"] =>
      [2, "7e72c8b397779382273936a3513c465296886eb08367fb8beaa88fb335d0ddc3"],
    ["papyri-ddbdp/DDbDP/135/135776.xml", SB30_17872_URN, "grc"] =>
      [2, "977c0f9132c076d858763cc44839b249daa91184a04fcb95ed00473cb778a408"]
  }.freeze

  def test_apparatus_layer_leaves_passages_byte_identical_on_every_fixture
    PRE_APPARATUS_DIGESTS.each do |(relative, urn, language), (count, digest)|
      path = File.expand_path("../fixtures/#{relative}", __dir__)
      dclp = urn.start_with?("urn:nabu:dclp:")
      family = dclp ? Nabu::Adapters::DdbdpParser.new(idno_type: "dclp", urn_namespace: "dclp") : parser
      document = family.parse(path, urn: urn, language: language)
      payload = document.map do |passage|
        [passage.urn, passage.text, passage.annotations.except("apparatus")]
      end
      assert_equal count, document.size, "#{relative}: passage count must not change"
      assert_equal digest, Digest::SHA256.hexdigest(JSON.generate(payload)),
                   "#{relative}: urns, texts and pre-existing annotations must be byte-identical"
    end
  end
end
