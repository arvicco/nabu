# frozen_string_literal: true

require "test_helper"

module Adapters
  # The `nkjp-tei` parser family (P116-1): the National Corpus of Polish
  # TEI P5 package as KorBa ships it — one directory per text holding
  # header.xml, text.xml (the transcription, <ab> blocks), and the stand-off
  # layers ann_segmentation.xml (segments as string-ranges into text.xml,
  # segmentation alternatives as <choice> with nkjp:rejected segs) and
  # ann_morphosyntax.xml (orth/translit, the candidate interpretations and
  # the disamb choice). Pinned against three real KorBa texts trimmed to
  # their first block(s) consistently across the three layers.
  class NkjpTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("korba")

    def parse(name) = Nabu::Adapters::NkjpTeiParser.new.parse(File.join(FIXTURES, name))

    def test_blocks_come_from_text_xml_with_whitespace_collapsed
      text = parse("AkZbrojGęb")
      assert_equal %w[txt_1.1-ab txt_1.2-ab txt_1.3-ab], text.blocks.map(&:id)
      assert_equal "txt_2.1.22.4-p", text.blocks.first.n
      assert_equal "1692, d. 24 Januarii accessit z Jaworowa działo spiżowe, wielkie, 36-funtowe, " \
                   "gładkie, bez napisu i lawetu. Długie na łokci.", text.blocks.first.text
    end

    def test_page_breaks_ride_as_the_pages_a_block_touches
      text = parse("AkZbrojGęb")
      assert_equal ["132"], text.blocks.first.pages
      assert_equal ["132"], text.blocks[1].pages, "the page in force carries into the next block"
    end

    def test_foreign_and_uncertain_spans_are_recorded
      block = parse("AndPiekBoh").blocks.first
      assert_equal [{ "lang" => "la",
                      "text" => "Quod mens sua sponte divinat, idem subiscit ratio baud fallax" }],
                   block.foreign
      assert_equal [{ "reason" => "unreadable", "text" => "subiscit" }], block.uncertain
    end

    def test_tokens_carry_translit_form_modern_orth_lemma_and_tag
      block = parse("AkDziec").blocks.first
      assert_equal "X", block.tokens.first["form"]
      jezeli = block.tokens.find { |t| t["form"] == "Ieżeli" }
      assert_equal "Jeżeli", jezeli["orth"], "orth is the modernized spelling, form the transcribed one"
      assert_equal "jeżeli", jezeli["lemma"]
      refute_nil jezeli["xpos"]
    end

    def test_rejected_segmentation_alternatives_never_become_tokens
      forms = parse("AkDziec").blocks.first.tokens.map { |t| t["form"] }
      assert_includes forms, "uczynić"
      refute_includes forms, "uczyni", "the nkjp:rejected split is an alternative, not a token"
    end

    def test_untagged_foreign_tokens_keep_their_form_and_language_only
      tokens = parse("AndPiekBoh").blocks.first.tokens
      quod = tokens.find { |t| t["form"] == "Quod" }
      assert_equal({ "form" => "Quod", "orth" => "Quod", "lang" => "la" }, quod)
      subiscit = tokens.find { |t| t["form"] == "subiscit" }
      assert_equal "la", subiscit["lang"], "an uncertain span inside a foreign span inherits its language"
    end

    def test_every_morph_token_lands_on_its_block_in_order
      text = parse("AkZbrojGęb")
      assert_equal 74, text.blocks.sum { |b| b.tokens.size }, "76 segs − 2 rejected"
      assert_equal "1692", text.blocks.first.tokens.first["form"]
    end

    def test_xpos_joins_ctag_and_the_chosen_msd
      tokens = parse("AkZbrojGęb").blocks.first.tokens
      assert_equal "dig", tokens.first["xpos"], "an empty msd leaves the bare ctag"
      dzialo = tokens.find { |t| t["form"] == "działo" }
      assert_equal "działo", dzialo["lemma"]
      assert_match(/\Asubst:sg:/, dzialo["xpos"])
    end

    def test_header_axes
      header = parse("AkZbrojGęb").header
      assert_equal "Inwentarz akcesyjny zbrojowni zamku Żółkiewskiego", header["title"]
      assert_equal "Anonim", header["author"]
      assert_equal "Żółkiew", header["place"]
      assert_equal "Ziemie Ruskie", header["region"]
      assert_equal({ "not_before" => 1690, "not_after" => 1693, "raw" => "między 1690 a 1693" },
                   header["date"])
      assert_equal({ "text" => ["proza"], "genre" => ["kanc"], "kind" => ["inwentarze"],
                     "subject" => ["wojskowość"], "ironic" => ["nie"] }, header["classes"])
      assert_equal "KORBA_AkZbrojGęb", header["idno"]
      assert_equal "restricted", header["availability"]
      assert_equal "free", parse("AkDziec").header["availability"]
      edition = header["modernized_edition"]
      assert_equal "Materiały źródłowe do dziejów kultury i sztuki XVI-XVIII w.", edition["title"]
      assert_equal "Mieczysław Gębarowicz", edition["editor"]
      assert_equal "1973", edition["date"]
    end

    def test_a_when_date_is_a_one_year_envelope
      header = parse("AkDziec").header
      assert_equal({ "not_before" => 1761, "not_after" => 1761, "raw" => "1761" }, header["date"])
      assert_equal "Drukarnia JKM i Rzeczypospolitej Scholarum Piarum", header["publisher"]
      assert_nil header["modernized_edition"]
    end

    def test_a_multi_target_cat_ref_yields_every_code
      assert_equal %w[historia wojskowość], parse("HumListRzecz").header.dig("classes", "subject")
    end

    def test_range_less_placeholder_segs_mint_no_token
      # LubJMan's first block carries two <seg type="g"/> join markers (no
      # string-range, no <w>) — the censused shape in 8 texts.
      text = parse("LubJMan")
      assert_equal 1, text.blocks.size
      refute_empty text.blocks.first.tokens
      assert(text.blocks.first.tokens.all? { |t| t["form"] && !t["form"].empty? })
    end

    def test_a_missing_layer_raises_parse_error
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "AkDziec", "header.xml"), dir)
        assert_raises(Nabu::ParseError) { Nabu::Adapters::NkjpTeiParser.new.parse(dir) }
      end
    end
  end
end
