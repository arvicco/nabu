# frozen_string_literal: true

require "test_helper"

module Adapters
  # The theatre-classique-tei family against four real files of the
  # DraCor mirror (trimmed verse and prose plays, an un-trimmed dialogue
  # with the all-lowercase header statements, a <TEI.2>-rooted play).
  class TheatreClassiqueTeiParserTest < Minitest::Test
    DIR = File.join(Nabu::TestSupport.fixtures("theatre-classique"), "xml")

    def parser = Nabu::Adapters::TheatreClassiqueTeiParser.new

    def parsed(stem) = (@parsed ||= {})[stem] ||= parser.parse(File.join(DIR, "#{stem}.xml"))

    def block(stem, citation)
      parsed(stem).blocks.find { |b| b.citation == citation } || flunk("#{stem} #{citation} missing")
    end

    def test_header_reads_title_authors_rights_and_the_site_source_description
      header = parsed("MOLIERE_MISANTHROPE").header
      assert_equal "LE MISANTHROPE ou L'ATRABILAIRE AMOUREUX, COMÉDIE", header.title
      moliere = header.authors.first
      assert_equal "MOLIERE, Jean-Baptiste Poquelin dit", moliere.name
      assert_equal [1622, 1673, "texte", "0000 0001 2319 7131"],
                   [moliere.birth, moliere.death, moliere.role, moliere.isni]
      assert_equal "Creative Commons BY-NC-SA", header.rights
      assert_equal "MOLIERE_MISANTHROPE", header.idno
      assert_equal({ "genre" => "Comédie", "inspiration" => "moeurs", "structure" => "Cinq actes",
                     "form" => "vers", "periode" => "1661-1670", "size" => "1750-2000" }, header.source_desc)
      assert_equal({ "url" => "https://gallica.bnf.fr/ark:/12148/bpt6k1280468t",
                     "shelfmark" => "BnF ASP RESERVE 8-RF-3144" }, header.permalink, "whitespace runs squeeze")
      assert_equal [{ "type" => "theme", "value" => "Misanthropie" }], header.keywords
    end

    def test_header_tolerates_lowercase_statements_and_unknown_years
      header = parsed("BARY_BELLESMAINS").header
      assert_equal "DES BELLES MAINS, CONVERSATION.", header.title
      assert_equal "René BARY", header.authors.first.name
      assert_nil header.authors.first.death, "16..-16.. is no year"
      assert_equal "BARY_BELLESMAINS", header.idno
    end

    def test_a_tei2_root_without_a_lang_tag_still_parses
      header = parsed("ABEILLE_CORIOLAN").header
      assert_equal "TEI.2", header.root
      assert_nil header.lang_tag
      assert_equal "CORIOLAN, TRAGÉDIE.", header.title
    end

    def test_the_cheap_header_read_equals_the_full_parse
      %w[MOLIERE_MISANTHROPE SAND_MOLIERE ABEILLE_CORIOLAN BARY_BELLESMAINS].each do |stem|
        assert_equal parsed(stem).header, parser.header(File.join(DIR, "#{stem}.xml")), stem
      end
    end

    def test_front_metadata_reads_edition_premiere_imprint_and_setting
      front = parsed("MOLIERE_MISANTHROPE").front
      assert_equal "1667", front.doc_date_value
      assert_equal "M. DC. LXVII. AVEC PRIVILÈGE DU ROI.", front.doc_date_text
      assert_equal ["1666-06-04", "Théâtre du Palais-Royal"], [front.premiere_date, front.premiere_location]
      assert_match(/\AÀ PARIS, chez JEAN RIBOU/, front.printer)
      assert_equal({ "location" => "Paris", "country" => "France" }, front.setting)
      assert_match(/\AÀ PARIS, Chez CHARLES DE SERCY/, parsed("BARY_BELLESMAINS").front.printer,
                   "the docImprint editor carries the imprint when no printer does")
    end

    def test_verse_lines_carry_speaker_line_number_and_shared_line_part
      first = block("MOLIERE_MISANTHROPE", "1.1.2")
      assert_equal "Qu'est-ce donc ? Qu'avez-vous ?", first.text
      assert_equal ["l", "PHILINTE", "PHILINTE.", "1", "i"], [first.kind, first.who, first.speaker, first.n, first.part]
      reply = block("MOLIERE_MISANTHROPE", "1.1.3")
      assert_equal %w[ALCESTE 1 f], [reply.who, reply.n, reply.part]
      assert_equal ["head", "ACTE I"],
                   [block("MOLIERE_MISANTHROPE", "1.1").kind, block("MOLIERE_MISANTHROPE", "1.1").text]
      assert_equal "SCÈNE PREMIÈRE. Philinte, Alceste.", block("MOLIERE_MISANTHROPE", "1.1.1").text
    end

    def test_front_matter_is_text_with_its_own_kinds
      kinds = parsed("MOLIERE_MISANTHROPE").blocks.select { |b| b.citation.start_with?("f") }.map(&:kind).uniq
      assert_equal %w[titlePart docDate docAuthor head p acheveImprime printer premiere castItem set], kinds
      cast = parsed("MOLIERE_MISANTHROPE").blocks.find { |b| b.kind == "castItem" }
      assert_equal "ALCESTE, amant de Célimène.", cast.text
      assert_equal "f1.1", parsed("MOLIERE_MISANTHROPE").blocks.find { |b| b.text == "LE LIBRAIRE AU LECTEUR" }.citation
    end

    def test_prose_speeches_read_whole_and_loose_stage_text_is_its_own_block
      speech = parsed("SAND_MOLIERE").blocks.find { |b| b.kind == "p" && b.who == "ARMANDE" }
      assert_match(/\AJe méprise les injures ;.*la veulent prendre\.\z/, speech.text)
      loose = parsed("SAND_MOLIERE").blocks.find { |b| b.kind == "loose" }
      assert_equal "D'un ton impératif et repoussant Brécourt et Madeleine, qui veulent la retenir.", loose.text
      assert_equal "ARMANDE", loose.who
    end

    def test_citations_use_div_ordinals_not_upstreams_repeated_numbers
      # SAND_MOLIERE numbers both its first and second act n="1".
      heads = parsed("SAND_MOLIERE").blocks.select { |b| b.kind == "head" && b.text.start_with?("ACTE") }
      assert_equal([["1.1", "ACTE I"], ["2.1", "ACTE II"], ["3.1", "ACTE III"]], heads.map { |b| [b.citation, b.text] })
      parsed("SAND_MOLIERE").blocks.map(&:citation).tally.each { |c, n| assert_equal 1, n, c }
    end

    def test_notes_and_speaker_labels_mint_no_text
      texts = parsed("BARY_BELLESMAINS").blocks.map(&:text)
      refute(texts.any? { |t| t.include?("Texte extrait de") }, "the front <note> is apparatus")
      refute_includes texts, "HEROIDE."
      assert_includes texts.join(" "), "chef_d_oeuvre des mains de la Nature"
    end

    def test_malformed_xml_is_a_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "BROKEN.xml")
        File.write(path,
                   "<TEI><teiHeader><fileDesc><titleStmt><title>x</title></titleStmt></fileDesc></teiHeader><text>")
        error = assert_raises(Nabu::ParseError) { parser.parse(path) }
        assert_match(/malformed TEI/, error.message)
      end
    end
  end
end
