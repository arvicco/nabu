# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::AtfParser (P31-2) — the atf family core, exercised over
  # real blocks from the checked-in CDLI fixture slice (trimmed byte-verbatim
  # from cdliatf_unblocked.atf; see test/fixtures/cdli/README.md). CDLI
  # policy (the language map, related-target minting) is passed in exactly
  # as the cdli adapter passes it, so these tests pin the family seams too.
  class AtfParserTest < Minitest::Test
    FIXTURE = File.expand_path("../fixtures/cdli/cdliatf_unblocked.atf", __dir__)

    LANGUAGE_MAP = Nabu::Adapters::Cdli::ATF_LANGUAGES

    def parser
      Nabu::Adapters::AtfParser.new(
        language_map: LANGUAGE_MAP,
        related_target: ->(id) { "urn:nabu:cdli:#{id.downcase}" }
      )
    end

    # The fixture block for one P-number (header line through the next
    # header), exactly as the adapter's offset slicing yields it.
    def block(p_number)
      blocks = File.read(FIXTURE).split(/^(?=&)/)
      found = blocks.find { |b| b.match?(/\A&\s*#{p_number}\b/) }
      refute_nil found, "fixture block #{p_number} missing"
      found
    end

    def parse(p_number, **)
      parser.parse(block(p_number), urn: "urn:nabu:cdli:#{p_number.downcase}",
                                    path: FIXTURE, **)
    end

    # -- P000001: proto-cuneiform, columns, direct >>Q links ------------------

    def test_p000001_structure_language_and_composite_links
      document = parse("P000001")
      assert_equal "qpc", document.language
      assert_equal "CDLI Lexical 000002, ex. 065", document.title
      assert_equal "CDLI Lexical 000002, ex. 065", document.metadata["designation"]

      # obverse has 3 columns of 3 lines; reverse one line — 10 passages.
      assert_equal 10, document.size
      first = document.passages.first
      assert_equal "urn:nabu:cdli:p000001:obverse:1:1'", first.urn
      assert_equal "1(N01) , [...]", first.text
      assert_equal ["beginning broken"], first.annotations["states"]
      assert_equal [{ "target" => "Q000002", "line" => "014" }], first.annotations["links"]

      last = document.passages.last
      assert_equal "urn:nabu:cdli:p000001:reverse:1", last.urn
      assert_equal [{ "target" => "Q000002", "line" => "colophon" }], last.annotations["links"]

      assert_equal ["urn:nabu:cdli:q000002"], document.metadata["related"]
    end

    # -- P000725: >>A letters resolved through "#atf def linktext" ------------

    def test_p000725_letter_links_resolve_through_the_older_def_spelling
      document = parse("P000725")
      assert_equal "qpc", document.language
      first = document.passages.first
      assert_equal [{ "target" => "Q000002", "line" => "21" }], first.annotations["links"]
      assert_equal ["urn:nabu:cdli:q000002"], document.metadata["related"]
    end

    # -- P225015: lexical use, || parallels, #link: def -----------------------

    def test_p225015_parallel_riders_and_atf_use
      document = parse("P225015")
      assert_equal ["lexical"], document.metadata["atf_use"]
      assert_equal 3, document.size
      first = document.passages.first
      assert_equal "sze ba", first.text
      assert_equal [{ "target" => "Q000047", "line" => "791" }], first.annotations["parallels"]
      # The "obverse?" face is kept verbatim — never invented-corrected.
      assert_equal "urn:nabu:cdli:p225015:obverse?:1", first.urn
      # No #atf lang line: the fallback rules.
      assert_equal "und", document.language
      fallback = parser.parse(block("P225015"), urn: "urn:nabu:cdli:p225015",
                                                path: FIXTURE, language_fallback: "sux")
      assert_equal "sux", fallback.language
    end

    # -- P480562: #tr.en on an @object weight / @surface a --------------------

    def test_p480562_translation_annotation_and_surface_segment
      document = parse("P480562")
      assert_equal 1, document.size
      passage = document.passages.first
      assert_equal "urn:nabu:cdli:p480562:a:1", passage.urn
      assert_equal "1/3(disz) ma-na", passage.text
      assert_equal({ "en" => "one-third mina" }, passage.annotations["tr"])
    end

    # -- P519727: stray-space header, #tr-en variant, $ states ----------------

    def test_p519727_tolerates_the_stray_space_header_and_tr_hyphen_variant
      document = parse("P519727")
      assert_equal "akk", document.language
      assert_equal "RINAP 2, Sargon II 05 composite", document.title
      assert_equal 3, document.size
      first = document.passages.first
      assert_equal ["beginning broken"], first.annotations["states"]
      assert_equal [{ "target" => "Q006486", "line" => "001'" }], first.annotations["links"]
      assert first.annotations["tr"].key?("en"), "the #tr-en: spelling must land under en"
      last = document.passages.last
      assert_equal ["rest broken"], last.annotations["states_after"]
      assert_equal ["urn:nabu:cdli:q006486"], document.metadata["related"]
    end

    # -- P323717: tablet + envelope + seal, comments, states ------------------

    def test_p323717_multi_object_blocks_keep_object_segments
      document = parse("P323717")
      # tablet and envelope are both lineless; the four lines sit on seal 1.
      assert_equal 4, document.size
      first = document.passages.first
      # Two objects declared (tablet + envelope) → the object segment joins
      # the path; the seal rides the envelope it was rolled over.
      assert_equal "urn:nabu:cdli:p323717:envelope:seal.1:1", first.urn
      assert_equal %w[lost fragment].map { |s| "(#{s})" }, first.annotations["states"]
      last = document.passages.last
      assert_equal ["(following Mayr)"], last.annotations["states_after"]
    end

    # -- P469841: same-label lines under one face disambiguate ----------------

    def test_duplicate_labels_take_the_positional_block_suffix
      duplicated = <<~ATF
        &P999999 = synthetic collision check over real line shapes
        #atf: lang sux
        @tablet
        @obverse
        1. 3(u) sa gi
        1. 3(u) sa gi
      ATF
      document = parser.parse(duplicated, urn: "urn:nabu:cdli:p999999", path: FIXTURE)
      assert_equal %w[urn:nabu:cdli:p999999:obverse:1 urn:nabu:cdli:p999999:obverse:1:b2],
                   document.map(&:urn)
    end

    def test_zero_line_block_parses_to_a_marked_metadata_only_document
      stub = <<~ATF
        &P999998 = uninscribed object
        #atf: lang sux
        @tablet
        $ (lost)
      ATF
      document = parser.parse(stub, urn: "urn:nabu:cdli:p999998", path: FIXTURE)
      assert_equal 0, document.size
      assert_equal "none", document.metadata["text_layer"]
      assert_equal ["(lost)"], document.metadata["states"]
    end

    def test_junk_line_quarantines_with_path_line_and_urn
      junk = <<~ATF
        &P999997 = junk carrier
        #atf: lang sux
        @tablet
        @obverse
        2 dub-sar
      ATF
      error = assert_raises(Nabu::ParseError) do
        parser.parse(junk, urn: "urn:nabu:cdli:p999997", path: "/x/cdliatf_unblocked.atf")
      end
      assert_match(%r{\A/x/cdliatf_unblocked\.atf:5: urn:nabu:cdli:p999997: unrecognized line},
                   error.message)
    end

    def test_unmapped_language_falls_to_und_and_keeps_the_verbatim_value
      block = <<~ATF
        &P999996 = language drift carrier
        #atf: lang sux&akk
        @tablet
        @obverse
        1. a-na
      ATF
      document = parser.parse(block, urn: "urn:nabu:cdli:p999996", path: FIXTURE)
      assert_equal "sux", document.language, "first code of a multi-language value wins"
      assert_equal "sux&akk", document.metadata["language_raw"]
    end

    def test_empty_text_labels_mint_nothing
      block = <<~ATF
        &P999995 = empty label carrier
        #atf: lang sux
        @tablet
        @obverse
        1'.#{'  '}
        2'. a-na
      ATF
      document = parser.parse(block, urn: "urn:nabu:cdli:p999995", path: FIXTURE)
      assert_equal ["urn:nabu:cdli:p999995:obverse:2'"], document.map(&:urn)
    end
  end
end
