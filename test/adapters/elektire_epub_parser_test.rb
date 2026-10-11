# frozen_string_literal: true

require "test_helper"

module Adapters
  # The `elektire-epub` parser family (P117-2): eLektire books (Bulaja
  # naklada for CARNET). Pinned against real books re-packed without their
  # fonts and images (test/fixtures/elektire/epub/): Kaboga's Pjesme and
  # Pelegrinović's Jeđupka (v2 — Sigil from Word; Jeđupka with footnote
  # anchors carrying inline glosses), Šimunović's Duga (v3 — the CARNET
  # generation with glossary links and the didactic pages), Car Emin's
  # Mali od foguna (an author who died 1963) and Vitez's Izabrane pjesme
  # (no public-domain statement).
  class ElektireEpubParserTest < Minitest::Test
    FIXTURES = File.join(Nabu::TestSupport.fixtures("elektire"), "epub")

    def parser = Nabu::Adapters::ElektireEpubParser.new
    def parse(slug) = parser.parse(File.join(FIXTURES, "#{slug}.epub"))

    def test_the_impressum_statement_and_the_author_life_line_are_read
      rights = parse("pjesme-8").rights
      assert_equal "Autorska prava na djela Marina Kaboge su istekla, i ona su sada javno dobro koje se " \
                   "nesmetano može kopirati.", rights.statement
      assert_nil rights.reserved
      assert_equal [1505, 1582], [rights.author_birth, rights.author_death]
      assert_equal "978-953-328-213-8", rights.isbn
      assert_equal "Zvonimir Bulaja", rights.editor
      refute rights.anonymous
    end

    def test_the_v3_statement_form_and_a_late_death_and_a_missing_statement
      assert_equal "Djela Dinka Šimunovića su u javnoj domeni.", parse("duga").rights.statement
      assert_equal 1963, parse("mali-od-foguna").rights.author_death,
                   "the publisher calls Car Emin public domain; his life line says otherwise"
      assert_nil parse("izabrane-pjesme-16").rights.statement, "a living-memory author: no PD statement"
    end

    def test_rights_alone_matches_the_full_parse
      opf, rights = parser.rights(File.join(FIXTURES, "duga.epub"))
      book = parse("duga")
      assert_equal book.rights, rights
      assert_equal book.opf, opf
      assert_equal "Duga", opf.title
      assert_equal ["Dinko Šimunović"], opf.creators
    end

    def test_verse_lines_are_passages_cited_by_spine_position
      lines = parse("pjesme-8").lines
      assert_equal ["4.1", "head", "PJESAN O DINARU"], lines.first.to_h.values
      assert_equal "Čuj me svak što ću rit, od mlada do stara,", lines[1].text
      assert_equal "4.2", lines[1].citation
      assert_equal 56, lines.size
    end

    def test_footnote_anchors_and_inline_glosses_leave_no_residue
      lines = parse("jedupka").lines
      assert_includes lines.map(&:text), "kletva hoće, svit protiče,"
      refute(lines.any? { |l| l.text.include?("Prema legendi") }, "the editor's gloss is apparatus")
      refute(lines.any? { |l| l.text.match?(/govorim ti o plodu/) })
    end

    def test_source_newlines_inside_a_prose_paragraph_are_not_line_breaks
      lines = parse("duga").lines
      assert_equal ["7.1", "head", "Duga"], lines.first.to_h.values
      assert_equal "Odozdo rijeka Glibuša a odozgo klisure zarobile malu varoš Čardake na strmu obronku.",
                   lines[1].text
      assert(lines.any? { |l| l.text.include?("vidljivim sivkastim uzduhom i snom.") },
             "a glossary link keeps its word")
    end

    def test_apparatus_never_becomes_text
      texts = %w[pjesme-8 duga jedupka].flat_map { |slug| parse(slug).lines.map(&:text) }
      refute(texts.any? { |t| t.include?("Nakladnik") }, "the impressum")
      refute(texts.any? { |t| t.match?(/\A(Rječnik|Bilješka o autoru|Kviz|Metodički instrumentarij)\z/) })
      refute(texts.any? { |t| t.include?("Bulaja") })
    end
  end
end
