# frozen_string_literal: true

require "test_helper"
require "json"

module Adapters
  # Nabu::Adapters::EblAtfParser (P31-3) — the eBL-ATF dialect of the atf
  # family, exercised over real fragments from the checked-in Zenodo-snapshot
  # fixture slice (member objects byte-verbatim from fragments.json; see
  # test/fixtures/ebl/README.md). eBL policy (the %-shift language map, the
  # akk default) is passed exactly as the ebl adapter passes it, so these
  # tests pin the dialect seams — and the CDLI core's behavior is regression-
  # pinned separately in AtfParserTest.
  class EblAtfParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("ebl")

    def parser
      Nabu::Adapters::EblAtfParser.new(
        language_map: Nabu::Adapters::Ebl::SHIFT_LANGUAGES,
        default_language: "akk"
      )
    end

    # The fixture fragment's atf field, exactly as the adapter hands it over.
    def block(id)
      fragments = JSON.parse(File.read(File.join(FIXTURES, "fragments.json")))
      fragment = fragments.find { |f| f["_id"] == id }
      refute_nil fragment, "fixture fragment #{id} missing"
      fragment["atf"]
    end

    def parse(id)
      parser.parse(block(id), urn: Nabu::Adapters::Ebl.urn_for(id),
                              path: "/x/fragments.json", title_fallback: id)
    end

    # -- 1868,0523.2: #tr.en riders, #note apparatus, $ rulings ---------------

    def test_translation_and_note_riders_on_the_open_line
      document = parse("1868,0523.2")
      assert_equal "akk", document.language, "unshifted eBL-ATF defaults to Akkadian"
      first = document.passages.first
      assert_equal "urn:nabu:ebl:1868,0523.2:1'", first.urn
      assert_equal "[x x x x x x x x x x (x) {šim}{d}]nin#-urta [ina] KUŠ", first.text
      assert_equal ["Ln. 1' // BAM 470 ln. 21'."], first.annotations["notes"]
      assert first.annotations["tr"]["en"].start_with?("If DITTO, @i{mūṣu}-stone"),
             "the inline English translation rides the line keyed en, @i{} markup verbatim"
      # "$ single ruling" lands as a state on the NEXT line (core mechanics).
      second = document.passages[1]
      assert_equal ["single ruling"], second.annotations["states"]
    end

    # -- IM.61678: %sux shift language, translation extents, @date division --

    def test_first_shift_decides_document_language_and_extents_ride_verbatim
      document = parse("IM.61678")
      assert_equal "sux", document.language
      assert_equal "%sux", document.metadata["language_shift"]
      third = document.passages[2]
      assert_equal "urn:nabu:ebl:im.61678:obverse:3", third.urn
      assert_equal "Alla has received it from Lugalušur.", third.annotations["tr"]["en"]
      assert_equal({ "en" => "o 4" }, third.annotations["tr_extents"])
      # @date opens a division; the next minted line (reverse 1') carries it
      # plus both queued column states — the family's open-division mechanics.
      reverse_first = document.passages[5]
      assert_equal "urn:nabu:ebl:im.61678:reverse:1'", reverse_first.urn
      assert_equal "date", reverse_first.annotations["division"]
      assert_equal ["rest of column missing", "beginning of column missing"],
                   reverse_first.annotations["states"]
    end

    def test_extent_without_the_dot_still_parses_as_a_translation
      document = parse("IM.75911")
      with_extent = document.passages.find { |p| p.annotations.dig("tr_extents", "en") == "r i 4'" }
      refute_nil with_extent, "#tr.en.(r i 4'): must ride its line"
      no_dot = document.passages.find { |p| p.annotations.dig("tr_extents", "en") == "r i 8'" }
      refute_nil no_dot, "the #tr.en(r i 8'): spelling (no dot before the extent) must still land"
    end

    # -- // parallel lines ----------------------------------------------------

    def test_parallel_lines_ride_the_previous_text_line_verbatim
      document = parse("K.12174")
      second = document.passages[1]
      assert_equal "urn:nabu:ebl:k.12174:1:2'", second.urn
      assert_equal ["F K.2198+ 1'-2'"], second.annotations["parallels"]
    end

    def test_parallel_before_any_text_line_lands_in_document_metadata
      document = parse("K.2954")
      assert_equal ["(UḪ V 52)"], document.metadata["parallels"]
      second = document.passages[1]
      assert_equal ["(UḪ V 53)"], second.annotations["parallels"]
      # The first line is unshifted (interlinear Akkadian): akk by default.
      assert_equal "akk", document.language
    end

    # -- %es and the shift map ------------------------------------------------

    def test_emesal_shift_maps_to_sumerian
      document = parse("N.7458")
      assert_equal "sux", document.language
      assert_equal "%es", document.metadata["language_shift"]
      assert_equal "urn:nabu:ebl:n.7458:1'", document.passages.first.urn
    end

    def test_unmapped_shift_falls_to_the_default_and_keeps_the_verbatim_value
      block = <<~ATF
        1. %zz a-na
      ATF
      document = parser.parse(block, urn: "urn:nabu:ebl:x.1", path: "/x/fragments.json")
      assert_equal "akk", document.language
      assert_equal "%zz", document.metadata["language_raw"]
    end

    # -- #lem verbatim carry --------------------------------------------------

    def test_lem_lines_ride_the_open_line_verbatim
      document = parse("BM.47447")
      first = document.passages.first
      assert_equal 1, first.annotations["lem"].size
      assert first.annotations["lem"].first.start_with?("attallû[eclipse]N; iššakinma[take place]V"),
             "the #lem body is carried verbatim, never folded into the lemma index"
      # "$ obverse" is a state line, not structure: no face segment is minted.
      assert_equal "urn:nabu:ebl:bm.47447:1", first.urn
      assert_equal ["obverse"], first.annotations["states"]
    end

    # -- columns, sigla labels, structure statuses ----------------------------

    def test_columns_without_a_surface_keep_the_column_segment_only
      document = parse("K.5808")
      assert_equal 11, document.size
      assert_equal "urn:nabu:ebl:k.5808:1':1'", document.passages.first.urn
      assert_equal "urn:nabu:ebl:k.5808:2':1'", document.passages[6].urn
    end

    def test_sigla_prefixed_labels_and_note_riders
      document = parse("K.13942")
      assert_equal "sux", document.language
      first = document.passages.first
      assert_equal "urn:nabu:ebl:k.13942:obverse:1':1'", first.urn
      assert_equal ["(Instructions of Šuruppak 8)"], first.annotations["parallels"]
      siglum = document.passages.find { |p| p.urn.end_with?(":A+1'") }
      refute_nil siglum, "A+N' sigla labels are verbatim urn segments"
    end

    def test_structure_status_marks_classify_but_stay_verbatim_in_the_urn
      block = <<~ATF
        @obverse!
        1. a-na
      ATF
      document = parser.parse(block, urn: "urn:nabu:ebl:x.2", path: "/x/fragments.json")
      assert_equal ["urn:nabu:ebl:x.2:obverse!:1"], document.map(&:urn),
                   "the ! correction status must not demote @obverse! to a division"
    end

    # -- junk # directives stay comments, real junk still quarantines ---------

    def test_junk_translation_spellings_fall_to_comments_never_quarantine
      block = <<~ATF
        1. a-na
        #tren so wrong
        #traces visible
      ATF
      document = parser.parse(block, urn: "urn:nabu:ebl:x.3", path: "/x/fragments.json")
      first = document.passages.first
      assert_equal ["tren so wrong", "traces visible"], first.annotations["comments"]
      assert_nil first.annotations["tr"]
    end

    def test_unrecognized_lines_still_quarantine_with_path_and_urn
      error = assert_raises(Nabu::ParseError) do
        parser.parse("nonsense without a label\n", urn: "urn:nabu:ebl:x.4", path: "/x/fragments.json")
      end
      assert_match(%r{\A/x/fragments\.json:1: urn:nabu:ebl:x\.4: unrecognized line}, error.message)
    end
  end
end
