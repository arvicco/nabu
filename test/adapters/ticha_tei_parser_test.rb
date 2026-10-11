# frozen_string_literal: true

require "test_helper"

module Adapters
  # The ticha-tei parser family (P117-5) against real Ticha files: the
  # well-formed Córdova trim, and the upstream-malformed manuscripts and
  # Agüero excerpt whose defects the tag balancer repairs (unclosed <br>,
  # truncated files, stray </head>, add/note swaps, a bare <note> for
  # </note>, a start tag broken mid-attribute, a lost <choice>).
  class TichaTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("ticha")

    def parse(rel, default: "spa")
      Nabu::Adapters::TichaTeiParser.new.parse(File.join(FIXTURES, rel), default_language: default)
    end

    def page(result, number) = result.pages.find { |p| p.n == number } || flunk("no page #{number}")

    # -- well-formed: Córdova --------------------------------------------------

    def test_a_well_formed_file_is_read_verbatim_with_zero_repairs
      result = parse("cordova-arte/cordova-arte.xml")
      assert_equal 0, result.repairs
      assert_equal({ "es" => "Spanish", "xzp" => "Ancient Zapotec", "nah" => "Nahuatl", "lat" => "Latin" },
                   result.header_languages)
    end

    def test_cordovas_paired_pdf_breaks_join_the_arte_page
      result = parse("cordova-arte/cordova-arte.xml")
      assert_equal %w[4 6 1v 2r], result.pages.map(&:n)
      assert_equal ["http://archive.org/stream/arteenlenguazapo00juan#page/n4/mode/1up"], page(result, "4").facs
    end

    def test_outline_heads_and_forme_work_stay_out_of_the_text
      six = page(parse("cordova-arte/cordova-arte.xml"), "6")
      assert_equal ["[Licencias]", "Licencia del muy excelente señor Virrey [Don Martín Enriquez]."], six.outline
      assert_equal ["† 2 poteca,"], six.forme_work
      refute_includes six.text, "[Licencias]"
      assert six.text.start_with?("L I C E N C I A D E L\nmuy excellente ſeñor\nViſorey.")
    end

    def test_choice_splits_original_and_regularized_layers
      four = page(parse("cordova-arte/cordova-arte.xml"), "4")
      assert_includes four.text, "Fray Iuan"
      assert_includes four.regularized, "Fray Juan de Córdoba"
    end

    def test_foreign_spans_fold_the_encoders_cvz_to_zap
      one_v = page(parse("cordova-arte/cordova-arte.xml"), "1v")
      assert_includes one_v.foreign, { "lang" => "zap", "text" => "gönná" }
      assert_equal({ "spa" => 234, "lat" => 7, "zap" => 21 }, one_v.languages)
    end

    def test_div_level_language_is_inherited
      result = parse("levanto-cathecismo/levanto-cathecismo.xml")
      assert_equal({ "spa" => 69 }, page(result, "4").languages, "the esp-marked front matter div")
      assert_equal({ "spa" => 181, "zap" => 93 }, page(result, "33").languages)
      assert_includes page(result, "33").foreign, { "lang" => "zap", "text" => "Xii zeeloo ticha quella" }
    end

    # -- repair: the manuscripts -----------------------------------------------

    def test_unclosed_br_reads_as_a_line_break_and_truncation_closes
      result = parse("manuscripts/encoded/Al642T.xml")
      assert_equal 4, result.repairs, "2 <br> rewrites + the unclosed <text> and <TEI>"
      assert_equal %w[1 2 3], result.pages.map(&:n)
      assert result.pages.first.text.start_with?("Oy domingo a dos del mes de Junio de 1642 años")
      assert result.pages.first.regularized.start_with?("Hoy domingo a dos del mis de Junio")
    end

    def test_stray_end_heads_are_dropped_without_losing_text
      result = parse("manuscripts/encoded/Al698T.xml")
      assert_equal 1, result.pages.size
      assert result.pages.first.text.start_with?("Yo thomas gomes ynterprete.) general de la Jurisdición de esta")
      assert_equal word_count_of_source("manuscripts/encoded/Al698T.xml"), result.pages.first.languages.values.sum,
                   "every source word survives the repair"
    end

    def test_repaired_files_keep_every_source_word
      %w[manuscripts/encoded/Al642T.xml manuscripts/encoded/Fr720T.xml].each do |rel|
        result = parse(rel)
        assert_equal word_count_of_source(rel), result.pages.sum { |p| p.languages.values.sum }, rel
      end
    end

    def test_pages_without_n_number_by_sequence_and_header_titles_are_read
      result = parse("manuscripts/encoded/AGEO_Testaments_AGEO42.xml")
      assert_equal [nil, nil], result.pages.map(&:n)
      assert_equal "Testament AGEO 42", result.header_title
      assert_equal({ "spa" => "Early Modern Spanish" }, result.header_languages)
    end

    # -- repair: Agüero --------------------------------------------------------

    def test_aguero_add_note_swap_closes_the_open_add
      p345 = page(parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap"), "345")
      swapped = p345.apparatus.find { |a| a["text"].start_with?("1 Toda e- ſta mate- ria de pen ſamiētos,") }
      refute_nil swapped, "the <add> closed by </note> is one apparatus entry"
      assert_equal({ "type" => "add", "place" => "margin left" }, swapped.slice("type", "place"))
      assert swapped["text"].end_with?("à los Indios.")
      assert_includes p345.text, "chela acanaatini", "the text after the swapped </note> is main text again"
    end

    def test_a_bare_note_start_tag_reads_as_its_end_tag
      p394 = page(parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap"), "394")
      assert_includes p394.apparatus,
                      { "type" => "note", "place" => "margin right", "text" => "Hazimiē- to de gra- cias." }
      assert_includes p394.text, "xtennini looyoobi Dios niiaxtenni quizaa looquichiiño loo"
    end

    def test_a_start_tag_broken_mid_attribute_stays_as_text
      p362 = page(parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap"), "362")
      assert_includes p362.text, 'COGAA XIIBAA <add place="above" M[?] [Agra[?]bol?]llo f J. de sto Thomas'
    end

    def test_an_orphan_orig_and_reg_keep_their_own_layers
      p363 = page(parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap"), "363")
      assert_includes p363.text, "choice>Diſcipulo Copaallaxa"
      assert_includes p363.regularized, "choice>Discipulo Copaallaxa"
    end

    def test_an_unclosed_reg_closes_at_its_choice
      p395 = page(parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap"), "395")
      assert_includes p395.text, "Diſcipulo. Channahe, xij zooba loonija ticha"
      assert_includes p395.regularized, "Discipulo/reg>. Channahe", "upstream's typo stays verbatim in its layer"
    end

    def test_aguero_repairs_are_counted
      assert_equal 6, parse("aguero-miscelaneo/aguero-miscelaneo.xml", default: "zap").repairs
    end

    # -- the Zapotec original --------------------------------------------------

    def test_marginalia_ride_as_apparatus_and_prolog_comments_are_kept
      result = parse("Te744/Te744.xml", default: "zap")
      assert_equal ["encode the main language of this document", "Testament from San Sebastián Teitipac, 1744"],
                   result.prolog_comments
      first = result.pages.first
      assert_equal({ "zap" => 212 }, first.languages)
      assert_includes first.apparatus, { "type" => "note", "place" => "margin left",
                                         "text" => "layoo [cibetoo?] [?][amun?] por [ticea?] pesos" }
      refute_includes first.text, "cibetoo"
    end

    private

    # Words of the tag-stripped source after <text> — comments and the
    # <reg> alternatives dropped, i.e. the original-reading layer — the
    # census invariant the repair must keep (these manuscripts carry no
    # apparatus, outline or forme work).
    def word_count_of_source(rel)
      raw = File.read(File.join(FIXTURES, rel))
      body = raw.sub(/\A.*?<text[\s>]/m, "")
      body.gsub(/<!--.*?-->/m, " ").gsub(%r{<reg\b[^>]*>.*?</reg>}m, " ").gsub(/<[^>]*>/, " ").split.size
    end
  end
end
