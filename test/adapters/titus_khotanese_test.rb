# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Khotanese adapter tests: the TITUS Corpus of Khotanese Saka Texts
# (data entry R.E. Emmerick, corrections H. Kumamoto, TITUS version J.
# Gippert) — one document per text page under canonical/titus-khotanese/
# (khotsNNN.htm, khotNNNN.htm from page 1000), one passage per `<!Level 5>`
# Line (the manuscript line; in the Book of Zambasta the verse).
#
# The fixture bytes are grant-gated (Gippert, by email 2026-10-06: one
# retrieval, local personal research only, NO redistribution), so they live
# under the gitignored local/fixtures/titus-khotanese/ and every data-bearing
# case SKIPs when absent. Ground truth (retrieved 2026-10-10, see that dir's
# README): khots001 (KBT 1 — collection + book headers, Sanskrit title,
# manuscript references, 141 lines, a re-anchored line), khots006/007 and
# khots015/016 (KBT 6/7, 14/15 — each page's closing centered heading block
# names the NEXT text), khots050 (KT2 3, 48 lines), khots200 (KT3 53a, no
# Paragraph level, 5 lines), khot1000 (KT5 360/11.6a, 1 line), khot1625
# (Zambasta 1, 37 verses). No network: fetch is owner-run only (WebMock
# below).
class TitusKhotaneseTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-khotanese"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  ADAPTER = Nabu::Adapters::TitusKhotanese
  PARSER = Nabu::Adapters::TitusKhotaneseParser

  def conformance_adapter
    ADAPTER.new
  end

  def conformance_workdir
    require_fixtures!
    FIXTURES
  end

  def conformance_expected_source_id
    SLUG
  end

  def setup
    @adapter = ADAPTER.new
  end

  def documents_by_page
    require_fixtures!
    @documents_by_page ||= @adapter.discover(FIXTURES).to_h do |ref|
      [ref.metadata.fetch("page"), @adapter.parse(ref)]
    end
  end

  def passage(urn)
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn }
  end

  # --- manifest: the grant's credit duty (runs in CI, no bytes) --------------

  def test_manifest_is_nc_and_credits_titus_and_the_editors
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_khotanese", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    %w[TITUS Gippert Emmerick Kumamoto Bailey].each do |name|
      assert_includes manifest.credit, name, "the display duty names #{name}"
    end
  end

  def test_book_table_and_page_pattern
    assert_equal %w[KBT KT1 KT2 KT3 KT4 KT5 Zamb.], ADAPTER::BOOKS.keys
    assert_equal "Book of Zambasta", ADAPTER::BOOKS.fetch("Zamb.").name
    assert_match ADAPTER::PAGE_RE, "khots001.htm"
    assert_match ADAPTER::PAGE_RE, "khot1648.htm"
    refute_match ADAPTER::PAGE_RE, "khots.htm", "the frameset is not a text page"
    refute_match ADAPTER::PAGE_RE, "khotsx1.htm", "the index frames are not text pages"
    refute_match ADAPTER::PAGE_RE, "khotslex.htm"
  end

  def test_one_probe_target_for_the_corpus_entry
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    targets = ADAPTER.http_probe_targets
    assert_equal ["https://titus.uni-frankfurt.de/texte/etcs/iran/miran/khot/khotsak/khots.htm"],
                 targets.map(&:zip_url)
    assert_equal [Nabu::TitusFetch::STATE_FILE], targets.map(&:state_file)
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_document_per_page
    ids = @adapter.discover(conformance_workdir).map(&:id).sort
    assert_equal %w[urn:nabu:titus-khotanese:khot1000 urn:nabu:titus-khotanese:khot1625
                    urn:nabu:titus-khotanese:khots001 urn:nabu:titus-khotanese:khots006
                    urn:nabu:titus-khotanese:khots007 urn:nabu:titus-khotanese:khots015
                    urn:nabu:titus-khotanese:khots016 urn:nabu:titus-khotanese:khots050
                    urn:nabu:titus-khotanese:khots200], ids
  end

  def test_discover_ignores_framesets_and_index_frames
    Dir.mktmpdir do |dir|
      %w[khots.htm khotsx.htm khotsx1.htm khotsxx.htm khotslex.htm].each do |name|
        File.write(File.join(dir, name), "<html></html>")
      end
      assert_empty @adapter.discover(dir).to_a
    end
  end

  # --- khots001: KBT 1 — headers, lines, the re-anchor -----------------------

  def test_kbt_page_parses_one_passage_per_line
    document = documents_by_page.fetch("khots001")
    assert_equal "kho", document.language
    assert_equal 141, document.passages.size
    first = document.passages.first
    assert_equal "urn:nabu:titus-khotanese:khots001:KBT.1.134r.1", first.urn
    assert_equal "balysūñavūysānu", first.text
    assert_equal({ "unit" => "Line", "book" => "KBT", "text" => "1", "paragraph" => "134r", "line" => "1" },
                 first.annotations)
    second = passage("urn:nabu:titus-khotanese:khots001:KBT.1.134r.2")
    assert_equal "pracīya-saṃbuddhānu ṣāvānu aysu bäsīvrāṣā haṃkhīysgya hastamä dākṣiṇyānu hvatämä", second.text
  end

  def test_the_page_footer_and_closing_reference_never_leak_into_the_last_line
    last = documents_by_page.fetch("khots001").passages.last
    assert_equal "urn:nabu:titus-khotanese:khots001:KBT.1.148r.5", last.urn
    assert_equal "patätsāmato vätä aysmuī uysgrahāmatīnā päga' 6 agaundi parāhi vätä", last.text
  end

  def test_a_re_anchored_line_keys_by_occurrence_never_collides
    # Upstream anchors two distinct lines Khot._KBT_1_139v_4 (139r between).
    first = passage("urn:nabu:titus-khotanese:khots001:KBT.1.139v.4")
    assert first.text.start_with?("hastamo rraṣṭo balysūśtu"), first.text
    again = passage("urn:nabu:titus-khotanese:khots001:KBT.1.139v.4#2")
    assert_equal "cu häräna cu hvate ttu gyastä balysä se balysūñavūysei īskye pracīya-saṃbuddhu", again.text
    assert_equal 2, again.annotations["occurrence"]
  end

  def test_document_metadata_mines_the_headers_and_the_book_table
    document = documents_by_page.fetch("khots001")
    metadata = document.metadata
    assert_equal "KBT", metadata["book"]
    assert_equal "Buddhist Khotanese Texts", metadata["book_name"]
    assert_equal "H.W. Bailey, London 1951", metadata["edition_basis"]
    assert_equal "1", metadata["text"]
    assert_equal "Sūraṃgama-samādhi-sūtra", metadata["sanskrit_title"]
    assert_equal "Sūraṃgama-samādhi-sūtra", metadata["heading"]
    # The page's closing block ("Khadaliq 1. 306a") heads KBT 2 — never KBT 1's.
    assert_equal ["Khadaliq 1.13"], metadata["manuscripts"]
    assert_equal "Khadaliq", metadata["findspot"]
    assert_match(/Data entry by R\.E\. Emmerick/, metadata["data_entry"])
    assert_match(/corrections \(with some text improvements\) by H\. Kumamoto/, metadata["data_entry"])
    assert_equal "Khotanese — Buddhist Khotanese Texts 1: Sūraṃgama-samādhi-sūtra (khots001)", document.title
  end

  # --- the KBT heading blocks: each page closes with the NEXT text's heading ---
  #
  # Census 2026-10-10 (all 1,648 pages): KBT pages 1–35 end with a centered
  # block — the next text's title (Sanskrit `iosk22`, English `voc22`,
  # Khotanese names `isks16`, in reading order) and its manuscript siglum
  # (the block's last `voc22` run). khots001 alone also opens with its own.

  def test_a_closing_sanskrit_heading_is_not_line_text
    document = documents_by_page.fetch("khots006")
    assert_equal 12, document.passages.size
    last = document.passages.last
    assert_equal "urn:nabu:titus-khotanese:khots006:KBT.6.v.6", last.urn
    assert last.text.end_with?("aysmū śśūkä āgāśä"), last.text
    refute_includes last.text, "Sudhana"
    %w[heading sanskrit_title manuscripts].each do |key|
      refute document.metadata.key?(key), "khots006's own heading sits on khots005 (not a fixture): #{key}"
    end
  end

  def test_a_page_takes_its_heading_from_the_previous_pages_closing_block
    document = documents_by_page.fetch("khots007")
    assert_equal "Sudhana-Avadāna", document.metadata["heading"]
    assert_equal "Sudhana-Avadāna", document.metadata["sanskrit_title"]
    assert_equal ["P 2896"], document.metadata["manuscripts"], "khots006's siglum, not khots007's own P 2957"
    refute document.metadata.key?("findspot"), "a Pelliot siglum names no findspot"
    assert_equal "Khotanese — Buddhist Khotanese Texts 7: Sudhana-Avadāna (khots007)", document.title
  end

  def test_a_heading_joins_its_lanes_in_reading_order
    document = documents_by_page.fetch("khots016")
    assert_equal "Nanda the Merchant", document.metadata["heading"]
    assert_equal "Nanda", document.metadata["sanskrit_title"]
    assert_equal ["P 2834"], document.metadata["manuscripts"]
  end

  def test_a_khotanese_name_in_a_closing_heading_never_leaks_into_the_last_line
    document = documents_by_page.fetch("khots016")
    assert_equal 53, document.passages.size
    last = document.passages.last
    assert_equal "urn:nabu:titus-khotanese:khots016:KBT.15.58", last.urn
    assert_equal "hūña sa ca ṣi' hamāte", last.text, "Tcūṃ-Ttehi belongs to KBT 16's heading"
  end

  # --- the other books --------------------------------------------------------

  def test_a_continuation_page_carries_the_book_from_its_anchors
    document = documents_by_page.fetch("khots050")
    assert_equal 48, document.passages.size
    first = document.passages.first
    assert_equal "urn:nabu:titus-khotanese:khots050:KT2.3.1a.1", first.urn
    assert_equal "// ttā pāḍa pharṣṣa bara pyaṣṭi u braṃgalä", first.text
    assert_equal "Khotanese Texts II", document.metadata["book_name"]
    refute document.metadata.key?("findspot"), "no manuscript reference, no findspot"
  end

  def test_a_page_without_a_paragraph_level_drops_the_empty_component
    document = documents_by_page.fetch("khots200")
    assert_equal (1..5).map { |n| "urn:nabu:titus-khotanese:khots200:KT3.53a.#{n}" }, document.passages.map(&:urn)
    refute document.passages.first.annotations.key?("paragraph")
    assert document.passages.last.text.end_with?("buhu nä rakṣāmä biśīnda 7"), document.passages.last.text
  end

  def test_a_four_digit_page_and_a_slashed_text_id
    document = documents_by_page.fetch("khot1000")
    assert_equal ["urn:nabu:titus-khotanese:khot1000:KT5.360/11.6a.1"], document.passages.map(&:urn)
    assert_equal "hvāñumä", document.passages.first.text
    assert_equal "360/11.6a", document.metadata["text"]
  end

  def test_a_zambasta_verse_joins_its_unnumbered_second_line
    document = documents_by_page.fetch("khot1625")
    assert_equal 37, document.passages.size
    assert_equal "urn:nabu:titus-khotanese:khot1625:Zamb.1.31", document.passages.first.urn
    assert_equal "ju vā kūra samu nä saña bvāmata mulysdä", document.passages.first.text
    verse = passage("urn:nabu:titus-khotanese:khot1625:Zamb.1.187")
    assert_equal "kṣaṇvo biśśä kalpa ttuvāyīndä u parimāṇvo kṣettra " \
                 "panye kṣaṇä cakkru pravarttīndä parrījīndi uysnora", verse.text
    assert_equal "R.E. Emmerick, London 1966", document.metadata["edition_basis"]
  end

  # --- parser unit cases (inline HTML, run in CI) ----------------------------

  def line_html(lane)
    <<~HTML
      <html><body>
      <span id=h3><!Level 3>Text: 9<A NAME="Khot._KT4_9">&nbsp;</A></sPAN>
      <BR><span id=h5><!Level 5>Line: 1<A NAME="Khot._KT4_9__1">&nbsp;</A></sPAN>&nbsp;</span><span id=#{lane}><a id=#{lane} href="x">hvāñumä</a></span>
      </body></html>
    HTML
  end

  def test_khotanese_lanes_classify_by_family_at_any_size
    %w[isks16 isks12 isks22].each do |lane|
      lines = PARSER.parse(line_html(lane))
      assert_equal ["hvāñumä"], lines.map(&:text), lane
    end
  end

  def test_an_unknown_content_lane_quarantines_the_page
    %w[iskst16 iotoa16 iosbplc16].each do |lane|
      error = assert_raises(Nabu::ParseError) { PARSER.parse(line_html(lane)) }
      assert_match(/unknown content lane "#{lane}"/, error.message)
    end
  end

  def test_a_sanskrit_lane_inside_a_line_quarantines_the_page
    error = assert_raises(Nabu::ParseError) { PARSER.parse(line_html("iosk16")) }
    assert_match(/Sanskrit lane "iosk16" inside a line/, error.message)
  end

  def closing_heading_html(lane)
    line_html("isks16").sub("</body>", <<~HTML)
      <BR><DIV Align=CENTER>
      <BR></span><span id=#{lane}><a id=#{lane} href="x">Sudhana-Avadāna</a></span><span id=n16>
      <BR></span><span id=voc22>P 2896</span><span id=n16>
      </DIV></body>
    HTML
  end

  def test_a_centered_heading_block_after_the_last_line_is_not_text
    %w[iosk22 isks16].each do |lane|
      assert_equal ["hvāñumä"], PARSER.parse(closing_heading_html(lane)).map(&:text), lane
    end
  end

  def test_an_unknown_lane_inside_a_heading_block_still_quarantines
    error = assert_raises(Nabu::ParseError) { PARSER.parse(closing_heading_html("iotoa16")) }
    assert_match(/unknown content lane "iotoa16"/, error.message)
  end

  def test_lane_text_before_any_citation_header_quarantines_the_page
    html = "<html><body><span id=isks16>stray words</span></body></html>"
    assert_raises(Nabu::ParseError) { PARSER.parse(html) }
  end

  def test_unrepairable_invalid_utf8_quarantines_never_aborts
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "khots999.htm"),
                    "<span id=h5><!Level 5>Line: 1<A NAME=\"Khot._KT4_9__1\">&nbsp;</A></sPAN>" \
                    "<span id=isks16>hv \xFF\xFE ä</span>".b)
      error = assert_raises(Nabu::ParseError) { @adapter.parse(@adapter.discover(dir).first) }
      assert_match(/khots999\.htm is not valid UTF-8/, error.message)
    end
  end

  def test_a_severed_utf8_sequence_is_repaired_through_the_shared_reader
    Dir.mktmpdir do |dir|
      # "hvāñumä" with the ä (C3 A4) severed by </a> — the TITUS defect class.
      File.binwrite(File.join(dir, "khots998.htm"),
                    "<span id=h5><!Level 5>Line: 1<A NAME=\"Khot._KT4_9__1\">&nbsp;</A></sPAN>" \
                    "<span id=isks16><a id=isks16>hvāñum\xC3</a>\xA4</span>".b)
      document = @adapter.parse(@adapter.discover(dir).first)
      assert_equal ["hvāñumä"], document.passages.map(&:text)
    end
  end

  # --- fetch: one polite TitusFetch walk (WebMock) ---------------------------

  def test_fetch_walks_the_page_chain_across_the_four_digit_rename
    base = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/khot/khotsak"
    stub_request(:get, "#{base}/khots.htm")
      .to_return(body: '<frameset><frame src="khots001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{base}/khots001.htm").to_return(body: <<~HTML)
      <html><body><span id=h5><!Level 5>Line: 1<A NAME="Khot._KBT_1_1r_1">&nbsp;</A></sPAN>
      <span id=isks16>balysä</span>
      <A HREF="/texte/etcs/iran/miran/khot/khotsak/khot1000.htm"><img src="/arribar.gif" alt="Next part"></A>
      </body></html>
    HTML
    stub_request(:get, "#{base}/khot1000.htm").to_return(body: <<~HTML)
      <html><body><span id=h5><!Level 5>Line: 1<A NAME="Khot._KT5_1__1">&nbsp;</A></sPAN>
      <span id=isks16>hvāñumä</span></body></html>
    HTML
    adapter = ADAPTER.new(delay: 0)
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal %w[khot1000.htm khots001.htm], Dir.children(dir).grep(/\.htm\z/).sort
      assert File.file?(File.join(dir, Nabu::TitusFetch::STATE_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 2, adapter.discover(dir).count
    end
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_row_is_grant_gated_blocked_and_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "titus-khotanese must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the owner-fired first retrieval is verified"
    assert_equal "manual", entry.sync_policy
    assert_predicate entry, :grant_required?
    assert_predicate entry, :blocked?
    assert_equal "2026-10-06", entry.grant.date
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/one retrieval/i, entry.grant.terms)
    assert_match(/no redistribution/i, entry.grant.terms)
    assert_includes entry.axes, "iranian"
    assert_equal ADAPTER.manifest, entry.manifest
  end

  private

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (personal grant forbids redistribution — " \
         "bytes live in local/fixtures/, never in git)"
  end
end
