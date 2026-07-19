# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::SropheTeiParser (P31-4, parser family "srophe-tei"):
  # the Srophe/Digital Syriac Corpus TEI application — their own schema,
  # NOT EpiDoc. Format concerns only; everything corpus-policy (urn
  # minting, license class, language mapping) lives in the SyriacCorpus
  # adapter. Fixtures are six WHOLE real files at upstream commit
  # 833adc14 — see test/fixtures/syriac-corpus/README.md.
  class SropheTeiParserTest < Minitest::Test
    FIXTURES = File.join(Nabu::TestSupport.fixtures("syriac-corpus"), "data", "tei")

    def parse(name)
      Nabu::Adapters::SropheTeiParser.parse(File.join(FIXTURES, name))
    end

    # -- header extraction ----------------------------------------------------

    def test_header_carries_identity_license_and_provenance
      edition = parse("1.xml")
      assert_equal "https://syriaccorpus.org/1", edition.idno
      assert_equal "http://creativecommons.org/licenses/by/4.0/", edition.license_target
      assert_includes edition.license_text, "Creative Commons — Attribution 4.0 International — CC BY 4.0"
      assert_includes edition.title, "Demonstration 1: On Faith"
      assert_includes edition.title, "ܬܚܘܝܬܐ", "the inline Syriac title rides the flattened title"
      assert_equal "Aphrahat", edition.author
      assert_equal "http://syriaca.org/person/10", edition.author_ref
      assert_equal "http://syriaca.org/work/8503", edition.work_ref,
                   "the syriaca.org work URI — the concordance lane"
      assert_equal "uncorrectedTranscription", edition.status
      assert_equal "0337", edition.orig_date["when"]
      assert_equal "composition", edition.orig_date["type"]
    end

    def test_a_file_without_optional_header_fields_parses_honestly
      edition = parse("170.xml")
      assert_equal "https://syriaccorpus.org/170", edition.idno
      assert_equal "http://creativecommons.org/licenses/by/4.0/", edition.license_target
    end

    # -- block extraction -----------------------------------------------------

    def test_prose_blocks_are_flattened_with_collapsed_whitespace
      edition = parse("1.xml")
      assert_equal 41, edition.blocks.size, "title ab + 20 sections of head + p"
      first = edition.blocks.first
      assert_equal "ab", first.tag
      assert_equal [%w[title 0]], first.divs
      assert_equal "syr", first.lang
      assert_equal "ܬܚܘܝܬܐ ܕܗܝܡܢܘܬܐ", first.text
      head = edition.blocks[1]
      assert_equal %w[head 1], [head.tag, head.text], "editorial section-number heads are real blocks"
      section = edition.blocks[2]
      assert_equal "p", section.tag
      assert_equal [%w[section 1]], section.divs
      assert section.text.start_with?("ܐܓܪܬܟ ܚܒܝܒܝ܃ ܩܒܠܬ܂"),
             "the TEI's pretty-print indentation collapses to single spaces"
      refute_includes section.text, "\n"
    end

    def test_verse_lines_are_blocks_and_lg_stanzas_join_lines_with_newlines
      memra = parse("116.xml")
      assert_equal 129, memra.blocks.size, "title ab + 2 rubric lines + 126 memra lines"
      line = memra.blocks.find { |b| b.n == "1" }
      assert_equal "l", line.tag
      assert_equal [["text", nil]], line.divs
      assert_equal "ܬܰܪܥܳܐ ܪܰܒܳܐ ܦܼܬܰܚ ܠܺܝ ܝܰܘܣܶܦ ܕܰܫܟܰܚ̈ܳܬ݂ܳܐ", line.text

      hymn = parse("170.xml")
      lg = hymn.blocks.find { |b| b.tag == "lg" && b.n == "1" }
      assert_equal "ܦܶܫܿܛܶܬ ܐܻܝ̈ܕܰܝ܆\nܘܩܰܕܫܷܿܬ ܠܡܳܪܝ.", lg.text,
                   "a stanza's lines join with newlines — the line break is real structure"
      heads = hymn.blocks.select { |b| b.tag == "head" }
      assert_equal %w[1 2 3], heads.first(3).map(&:text), "heads INSIDE lg are hoisted before their stanza"
    end

    def test_numbered_ab_blocks_carry_their_upstream_numbers
      johannine = parse("142.xml")
      verse = johannine.blocks.find { |b| b.tag == "ab" && b.n == "1" }
      refute_nil verse
      assert_equal [%w[chapter 1]], verse.divs
      chapter_head = johannine.blocks.find { |b| b.tag == "head" }
      assert_equal "Chapter 1", chapter_head.text
      assert_equal "en", chapter_head.lang, "block xml:lang rides resolved (en here)"
    end

    def test_language_resolves_by_nearest_ancestor
      letter = parse("687.xml")
      translation = letter.blocks.select { |b| b.divs.first == ["translation", nil] }
      refute_empty translation
      english = translation.select { |b| b.lang == "en" }
      refute_empty english, "the translation body's paragraphs inherit/carry en"
      syriac = letter.blocks.select { |b| b.lang == "syr" }
      refute_empty syriac
    end

    def test_front_matter_is_skipped_and_notes_ride_beside_the_text
      letter = parse("687.xml")
      assert(letter.blocks.none? { |b| b.text.include?("Letter of the queen Helena to Papa") },
             "the <front> summary is editorial front matter, not the transcription")
      noted = letter.blocks.select { |b| b.notes.any? }
      assert_equal 2, noted.size
      noted.each do |block|
        block.notes.each { |note| refute_includes block.text, note, "apparatus notes never pollute text" }
      end
    end

    def test_malformed_xml_raises_parse_error
      Dir.mktmpdir do |dir|
        path = File.join(dir, "broken.xml")
        File.write(path, "<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><text><body>")
        error = assert_raises(Nabu::ParseError) { Nabu::Adapters::SropheTeiParser.parse(path) }
        assert_includes error.message, "broken.xml"
      end
    end
  end
end
