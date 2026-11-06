# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::SroTeiParser — the sro-tei family: the Stationers'
  # Register Online's up-converted TEI, one <div type="entry"> per copy
  # entry with its <ab type="metadata"> block, streamed entry by entry.
  # Fixtures: real trimmed slices of the four CURRENT Register files.
  class SroTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("stationers-register")
    CURRENT = File.join(FIXTURES, "Register ", "CURRENT Register")

    def parser = Nabu::Adapters::SroTeiParser.new

    def register(liber) = File.join(CURRENT, "reg_#{liber}-updated.xml")

    def entry(liber, id)
      parser.parse_file(register(liber)).entries.find { |e| e.id == id } or flunk "#{id} not parsed"
    end

    # -- the streaming id pass -------------------------------------------------

    def test_entry_ids_stream_every_entry_div_in_file_order
      assert_equal %w[SRO1 SRO4 SRO8 SRO218], parser.entry_ids(register("A"))
      assert_equal %w[SRO8024 SRO9195 SRO10453], parser.entry_ids(register("D"))
    end

    # -- the header ------------------------------------------------------------

    def test_header_carries_the_file_title_licence_and_liber
      header = parser.parse_file(register("A")).header
      assert_equal "Copy entries in Stationers' Company Register A, 9 December 1554 to 2 August 1596", header.title
      assert_equal "http://creativecommons.org/licenses/by/4.0/", header.licence
      assert_equal "A", header.liber
      # Register D's header is the older Arber-volume shape (title "Volume 4 of
      # Arber's transcript…", licence text broken over two lines) — same target.
      d = parser.parse_file(register("D")).header
      assert_equal "http://creativecommons.org/licenses/by/4.0/", d.licence
      assert_equal "D", d.liber
    end

    # -- the metadata block ----------------------------------------------------

    def test_metadata_block_is_mined_whole
      e = entry("A", "SRO1")
      assert_equal "A", e.liber
      assert_equal 1, e.sro_number
      assert_equal "1557-07-19", e.sort_date
      assert_equal({ "not_before" => "1557-07-19", "not_after" => "1558-07-09",
                     "text" => "19 July 1557 - 9 July 1558" }, e.register_date)
      assert_equal 4, e.fee_pence
      assert_equal "Register A, f.21v", e.register_ref
      assert_equal "I. 74", e.arber_ref
      assert_equal "TSC-1-D-02-01_1554-1596_0071_f21v", e.register_id
      assert_equal 1, e.works
      assert_equal %w[entered incomplete], e.statuses
      assert_equal [{ "name" => "J. Cawood", "key" => "cawoodj", "role" => "warden" },
                    { "name" => "J. Walley", "key" => "walleyj", "role" => "warden" },
                    { "name" => "T. Dockwray", "key" => "dockwrayt", "role" => "master" }], e.officers
    end

    def test_a_dated_entry_carries_a_single_day_register_date
      e = entry("D", "SRO9195")
      assert_equal "1633-12-06", e.sort_date
      assert_equal({ "when" => "1633-12-06", "text" => "6 December 1633" }, e.register_date)
      assert_equal 12, e.fee_pence
      assert_equal 2, e.works
    end

    def test_metadata_apparatus_notes_ride_the_entry_never_the_text
      e = entry("A", "SRO8")
      assert_equal 120, e.fee_pence
      assert_equal 32, e.works
      assert_equal %w[entered shared annotated incomplete], e.statuses
      arber = e.notes.find { |n| n["resp"] == "#arber" && n["text"].start_with?("Arber: As there are") }
      refute_nil arber, "the metadata block's Arber note (the fee arithmetic) rides the entry"
      assert_includes arber["text"], "the exact amount should have been 10s. 4d.; not 10s."
    end

    # -- the reading text ------------------------------------------------------

    def test_a_one_paragraph_entry_reads_its_register_text
      e = entry("A", "SRO1")
      assert_equal 1, e.blocks.size
      block = e.blocks.first
      assert_equal "p", block.kind
      assert_equal "To William pekerynge a ballett Called a Ryse and wake iiijd", block.text
      assert_equal ["a Ryse and wake"], e.titles
      assert_equal [{ "name" => "William pekerynge", "key" => "pekeryngewilliam", "role" => "stationer enterer" }],
                   e.persons
    end

    def test_the_registers_own_note_reads_inline_and_arbers_rides_aside
      e = entry("A", "SRO218")
      assert_equal 1, e.blocks.size, "a head-only entry (no <p>) still reads"
      block = e.blocks.first
      assert_equal "head", block.kind
      assert_equal "Aldee for iij ballettes", block.text,
                   "the register's note is register text; <space><desc> is the editors' gap description"
      assert_equal [{ "resp" => "#arber",
                      "text" => "Arber: This is a rough memorandum, subsequently inserted and in another " \
                                "handwriting." }], block.notes
    end

    def test_a_paragraph_holding_only_an_apparatus_note_mints_no_block
      e = entry("A", "SRO8")
      texts = e.blocks.map(&:text)
      refute(texts.any? { |t| t.include?("Arber:") }, "Arber's notes never read as register text")
      assert(e.notes.any? { |n| n["text"].start_with?("Arber: These are evidently the two") },
             "the note-only paragraph's note moves to the entry")
      assert_equal "To master John Wallye and mistress Toye these ballettes folowynge that ys to saye", texts.first
      assert_includes texts, "a ballett of Wakefylde and agrene"
      wake = e.blocks.find { |b| b.text == "a ballett of Wakefylde and agrene" }
      assert_equal [{ "resp" => "#GB", "type" => "editorial",
                      "text" => "possibly a version of the ballad of the Pinder of Wakefield and George a Greene" }],
                   wake.notes
      assert_includes texts, "for all these as ys before wreten accordynge to the ordenaunces Recevyd the some of xs",
                      "a resp=#register note is the register's own sum line"
    end

    def test_choice_reads_the_original_and_records_the_correction
      e = entry("D", "SRO9195")
      head, para = e.blocks
      assert_equal "head", head.kind
      assert_equal "Thomas Lambert :", head.text
      assert_equal "Entred for his Copies 2. ballads called Cupids Whirligig &c and the Welch Infectory of the " \
                   "Coods xijd .", para.text
      assert_equal [{ "sic" => "Coods", "corr" => "Goods" }], para.corrections
      assert_equal ["Cupids Whirligig &c", "the Welch Infectory of the Coods"], e.titles
    end

    def test_deletions_ride_aside
      block = entry("A", "SRO4").blocks.first
      assert_equal "To Thomas marshe this boke Called the Rules and Ryghte ample Documentes Towchynge the vse and " \
                   "practise of the commen almanacke which ys caled ephemerydes iiijd", block.text
      assert_equal ["ys"], block.deletions
    end

    def test_a_cancelled_entry_keeps_its_struck_through_rend
      e = entry("B", "SRO1679")
      assert_equal %w[cancelled incomplete], e.statuses
      assert_equal 0, e.fee_pence
      assert_equal ["left struck-through", "struck-through"], e.blocks.map(&:rend)
      para = e.blocks.last
      assert_equal "Lycenced vnto him A great herball called Dodoneus herball / translated into Englishe by " \
                   "Henry Light esquire", para.text
      assert_equal [{ "resp" => "#arber", "text" => "No sum stated" }], para.notes
    end

    def test_marginal_desc_blocks_read_in_document_order
      e = entry("B", "SRO1688")
      assert_equal %w[head p desc p desc p], e.blocks.map(&:kind).first(6)
      assert_equal "Thomas man .", e.blocks.first.text
    end

    def test_place_and_person_mentions_are_collected
      e = entry("B", "SRO2203")
      assert_equal ["london"], e.places
      assert_includes e.persons, { "name" => "master bishop", "key" => "bishopmaster", "role" => "stationer enterer" }
      assert_includes e.persons, { "name" => "bishop of london", "key" => "londonbishopof" }
    end

    def test_foreign_spans_ride_the_block
      e = entry("C", "SRO5992")
      para = e.blocks.find { |b| b.kind == "p" }
      assert_equal 1, para.foreign.size
      assert para.foreign.first.start_with?("Placcaet van de Hooghe ende Mogende")
      assert_includes para.text, "Placcaet van de Hooghe ende Mogende"
    end

    def test_a_list_reads_as_one_block
      e = entry("C", "SRO4539")
      list = e.blocks.find { |b| b.kind == "list" }
      refute_nil list
      assert_equal "The charge of the clergie And the crowne of christians 2 sermons", list.text
    end

    # -- errors ----------------------------------------------------------------

    def test_malformed_xml_is_a_parse_error_naming_the_path
      Dir.mktmpdir do |dir|
        path = File.join(dir, "reg_A-updated.xml")
        File.write(path, File.read(register("A"))[0, 9000])
        error = assert_raises(Nabu::ParseError) { parser.parse_file(path) }
        assert_includes error.message, path
      end
    end
  end
end
