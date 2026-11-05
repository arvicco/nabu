# frozen_string_literal: true

require "test_helper"

module Adapters
  # The korpus16-html family against real Korpus 16 reading pages
  # (fran.si/korpus16, retrieved 2026-11-05, whole raw GETs): Trubar's
  # 1555 prayer (TM 1555 — an Italian epigraph on its title page, a blank
  # last page), Trubar's 1579 Psalm 1 (a German title block, catchwords),
  # Dalmatin's 1584 Bible page I,56a (running heads, marginal notes, a
  # column break), and the first pages of an edited hymnal (TPs 1567,
  # "(ur.)") and of the 1581–82 New Testament (a two-year siglum).
  class Korpus16PageParserTest < Minitest::Test
    BOOKS = File.join(Nabu::TestSupport.fixtures("korpus16"), "books")

    def page(book, number)
      html = File.read(File.join(BOOKS, book.to_s, format("%05d.html", number)), encoding: "UTF-8")
      Nabu::Adapters::Korpus16PageParser.new.parse(html)
    end

    def test_the_book_header_and_page_count_ride_every_page
      first = page(9, 1)
      assert_equal 7, first.page_count, "the pager's own max"
      header = first.header
      assert_equal ["TM 1555", "Primož Trubar", "ENA MOLITOV TIH KERSZHENIKOU", "Tübingen, 1555"],
                   [header.siglum, header.author, header.title, header.imprint]
      assert_equal 1565, page(58, 1).page_count
      assert_equal "Jurij Dalmatin", page(58, 200).header.author, "interior pages carry the header too"
    end

    def test_body_blocks_join_by_newline_and_inline_highlights_close_up
      first = page(9, 1)
      assert_equal 4, first.blocks.size, "head + three labels"
      assert first.text.start_with?("ENA MOLITOV TIH KERSzhenikou, kir ſo ſa volo te praue Vere"), first.text[0, 80]
      assert_includes first.text, "\nORATIONE DE PERſeguitati", "the Italian epigraph rides as upstream keyed it"
      second = page(9, 2)
      assert second.text.start_with?("Ozha nash kir ſi Vnebeſih."), "a roman initial + italic run is one word"
    end

    def test_upstream_markers_ride_verbatim
      assert_includes page(9, 3).text, "kraleuuſtu# tiga", "# marks an illegible spot (upstream's own sign)"
    end

    def test_a_page_with_no_body_text_is_blank
      last = page(9, 7)
      assert_empty last.blocks
      assert_equal "", last.text
    end

    def test_forme_work_leaves_the_text_for_annotations
      psalm = page(39, 2)
      assert_equal "Dobru", psalm.catchword
      refute_includes psalm.text, "Dobru"
      bible = page(58, 200)
      assert_equal "I,56a", bible.folio
      assert_equal "Kadilu BVQVE. Cap. 30.", bible.running_head
      refute_includes bible.text, "Cap. 30."
    end

    def test_marginal_notes_leave_the_running_text_in_order
      bible = page(58, 200)
      assert_equal "Kadilu.", bible.notes.first
      assert_includes bible.notes, "c Deſſet sapuvidi."
      assert_includes bible.notes, "Sobbota ali prasnik."
      refute_includes bible.text, "Deſſet sapuvidi"
      refute_includes bible.text, "*", "the note anchor is the portal's marker, not print text"
      assert_includes bible.text, "INu GOSPVD je rekàl k'Moseſſu: Vsami k'ſebi Shpeceryo"
      assert_includes bible.text, "pred Prizhovanje v'ti Vtti tiga prizhovanja", "anchors close up, single-spaced"
    end

    def test_the_editor_marker_and_a_two_year_siglum_are_upstream_header_text
      assert_equal "Primož Trubar (ur.)", page(25, 1).header.author
      nt = page(43, 1).header
      assert_equal ["TT 1581-82", "Tübingen, 1581"], [nt.siglum, nt.imprint]
    end

    def test_a_non_reading_page_is_recognized
      parser = Nabu::Adapters::Korpus16PageParser.new
      assert parser.reading_page?(File.read(File.join(BOOKS, "9", "00001.html"), encoding: "UTF-8"))
      portal = File.read(File.join(Nabu::TestSupport.fixtures("korpus16"), "map", "about-Info.html"),
                         encoding: "UTF-8")
      refute parser.reading_page?(portal)
    end
  end
end
