# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Pahlavi adapter tests: the Zoroastrian Middle Persian book editions
# on TITUS (the Pahlavi books + the Zand), one document per text page under
# canonical/titus-pahlavi/<edition>/, passages at each edition's own deepest
# CITATION level (sentence / paragraph / verse) keyed off the
# `<!Level N>`-marked headers — never the physical `<!XLevel N>` page/line/
# manuscript-location headers, which ride as passage annotations.
#
# The fixture bytes are grant-gated (Gippert, by email 2026-10-06: one
# retrieval, local personal research only, NO redistribution), so they live
# under the gitignored local/fixtures/titus-pahlavi/ and every data-bearing
# case SKIPs when absent (the seal / corpus-oudnederlands mold). Ground truth
# (retrieved 2026-10-07, see that dir's README): arda001 (Ardā Wirāz ch. 1 —
# the chapter invocation + 22 sentences), bunda001 (Indian Bundahišn ch. I —
# heading + 54 sentences, manuscript locations, an Avestan quotation lane),
# mhd001 (Mādigān ch. 1 — transliteration, 8 paragraphs + 8 apparatus notes
# that mint nothing). No network: fetch is owner-run only (WebMock below).
class TitusPahlaviTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-pahlavi"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  ADAPTER = Nabu::Adapters::TitusPahlavi
  PARSER = Nabu::Adapters::TitusPahlaviParser

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
    assert_equal "titus_pahlavi", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Gippert/, manifest.credit)
    ADAPTER::EDITIONS.each_value do |edition|
      assert_includes manifest.credit, edition.credit_name, "the data-entry editors are part of the display duty"
      assert_includes edition.editors, edition.credit_name.split("/").first
    end
  end

  def test_edition_table_names_every_titus_book_edition_with_a_page_pattern
    assert_equal 24, ADAPTER::EDITIONS.size, "the 2026-10-07 census: 24 Pahlavi-book editions (Psalter excluded)"
    refute ADAPTER::EDITIONS.key?("psalter"), "the Christian Psalter is not a Zoroastrian Pahlavi book"
    arda = ADAPTER::EDITIONS.fetch("arda")
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/mpers/arda/arda.htm", arda.entry_url
    assert_match arda.page_re, "arda001.htm"
    refute_match arda.page_re, "arda.htm", "the frameset is not a text page"
    refute_match arda.page_re, "ardaxx.htm"
    assert_match ADAPTER::EDITIONS.fetch("vd-19p").page_re, "vd-19001.htm"
  end

  def test_one_probe_target_per_edition
    targets = ADAPTER.http_probe_targets
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert_equal ADAPTER::EDITIONS.keys, targets.map(&:state_subdir)
    assert(targets.all? { |t| t.state_file == Nabu::TitusFetch::STATE_FILE })
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_document_per_page_keyed_by_edition_and_page
    ids = @adapter.discover(conformance_workdir).map(&:id).sort
    assert_equal %w[urn:nabu:titus-pahlavi:andoshn.andos013 urn:nabu:titus-pahlavi:arda.arda001
                    urn:nabu:titus-pahlavi:bundahis.bunda001 urn:nabu:titus-pahlavi:dk6.dk6003
                    urn:nabu:titus-pahlavi:mhd.mhd001], ids
  end

  # --- the first-sync census fixes (2026-10-10, all 1,573 real pages) ---------

  def test_marked_x_flavor_words_are_running_text
    # dk6: the miphtsx16 lane (331 pages) marks "a'ōn" INSIDE the sentence.
    paragraph = passage("urn:nabu:titus-pahlavi:dk6.dk6003:Denk.VI.1A.a")
    assert_equal "pōryōtkēšān ī dānāgān pēšēnīgān a'ōn dāšt ku mardomān andar ox menišn-ē, " \
                 "ast yazd-ē gāh dārēd ud ast druz-ē rāh dārēd.", paragraph.text
  end

  def test_a_section_with_both_renderings_keeps_transcription_as_text
    sentence = passage("urn:nabu:titus-pahlavi:andoshn.andos013:Hand.Oshn.Dan.[13].53")
    assert sentence.text.start_with?("kē pad xrad kāmēd būdan, gōw kū: bunīg-menišn bawāy!"), sentence.text
    transliteration = sentence.annotations["transliteration"]
    assert transliteration.start_with?("MNW PWN hlt k՚myt bwtn' {YMRWN} +YMRRWN"), transliteration
    assert_includes transliteration, "š՚dynšn YCBENyt",
                    "the miphtlx16 marked word (with its <U> letter) is running text"
    assert_equal "transcription+transliteration", documents_by_page.fetch("andos013").metadata["representation"]
  end

  def test_small_lanes_inside_an_editorial_note_are_apparatus
    # andos013 closes sentence 53 with "[Anmerkung: <miphtlx12>YHWWN՚yh
    # </…> ließe sich eigentlich auch <miphtlx12>YHWWN՚š</…> lesen:
    # <miphtsx12>bāš</…> …]" — note-quoted forms, never text.
    sentence = passage("urn:nabu:titus-pahlavi:andoshn.andos013:Hand.Oshn.Dan.[13].53")
    refute_includes sentence.annotations["transliteration"], "YHWWN՚š"
    refute sentence.text.end_with?("bāš"), sentence.text
  end

  def test_an_apparatus_only_page_skips_at_discovery_with_accounting
    # The real vd-19p/vd-19050 shape: the Vidēvdād 19 critical apparatus —
    # every content lane a variant reading (miphtlv12, miphtlvx12,
    # miphtsv12, iijav12) among nc12 notes; no text to serve.
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vd-19p"))
      File.write(File.join(dir, "vd-19p", "vd-19050.htm"), <<~HTML)
        <span id=h5><!Level 5>Verse: 1<A NAME="Avesta-PT_Vd_19_Not._1">&nbsp;</A></sPAN></span>
        <span id=nc12>L4 </span><span id=miphtlv12>՚pt՚hlnymk</span><span id=iijav12>zaraϑušt </span>
      HTML
      File.write(File.join(dir, "vd-19p", "vd-19001.htm"), <<~HTML)
        <span id=h5><!Level 5>Verse: a<A NAME="Avesta-PT_Vd_19_1_a">&nbsp;</A></sPAN></span>
        <span id=miphts16>az abāxtar</span>
      HTML
      assert_equal(%w[vd-19001], @adapter.discover(dir).map { |ref| ref.metadata["page"] })
      skips = @adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert_match(/apparatus-only/, skips.notes.join(" "))
    end
  end

  def test_a_severed_utf8_sequence_is_rejoined_after_the_tag
    # The real snstrl/snstr002 run: "LCḎr̄'\xCC</a>\xB1 bym" (U+0331).
    bytes = File.binread(File.join(conformance_workdir, "severed", "snstr002-severed.bin"))
    refute bytes.dup.force_encoding("UTF-8").valid_encoding?, "the fixture carries the upstream defect"
    sections = PARSER.parse(PARSER.repair_severed(bytes))
    paragraph = sections.find { |s| s.components == %w[Sns MT 2 89] }
    assert_includes paragraph.text, "LCḎr̄'̱ bym BRA OZLWNt"
  end

  def test_a_severed_page_parses_whole_through_the_adapter
    # The real zwy/zwy005 run ("štr\xCA</a>\xBC1", U+02BC) as a page.
    bytes = File.binread(File.join(conformance_workdir, "severed", "zwy005-severed.bin"))
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "zwy"))
      File.binwrite(File.join(dir, "zwy", "zwy005.htm"), bytes)
      document = @adapter.parse(@adapter.discover(dir).first)
      assert_equal ["urn:nabu:titus-pahlavi:zwy.zwy005:ZWY.4.8"], document.passages.map(&:urn)
      assert_includes document.passages.first.text, "lwst՚k štrʼ1 W ZK"
    end
  end

  def test_unrepairable_invalid_utf8_quarantines_never_aborts
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "zwy"))
      File.binwrite(File.join(dir, "zwy", "zwy999.htm"),
                    "<span id=h3><!Level 3>Sentence: 1<A NAME=\"ZWY_1_1\">&nbsp;</A></sPAN>" \
                    "<span id=miphtl16>W \xFF\xFE ZK</span>".b)
      error = assert_raises(Nabu::ParseError) { @adapter.parse(@adapter.discover(dir).first) }
      assert_match(/zwy999\.htm is not valid UTF-8/, error.message)
    end
    assert_raises(Nabu::ParseError) { PARSER.parse("<span id=miphts16>\xFF</span>".dup.force_encoding("UTF-8")) }
  end

  def test_discover_ignores_framesets_and_unknown_directories
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "arda"))
      FileUtils.mkdir_p(File.join(dir, "stray"))
      File.write(File.join(dir, "arda", "arda.htm"), "<html></html>")
      File.write(File.join(dir, "stray", "stray001.htm"), "<html></html>")
      assert_empty @adapter.discover(dir).to_a
    end
  end

  # --- arda001: invocation + sentences across edition lines -------------------

  def test_arda_page_parses_the_invocation_and_twenty_two_sentences
    document = documents_by_page.fetch("arda001")
    assert_equal "pal", document.language
    assert_equal 23, document.passages.size, "the chapter-1 invocation + sentences 1-22"
    assert_equal "Pahlavi — Ardā-virāf-nāmag (arda001)", document.title
    invocation = document.passages.first
    assert_equal "urn:nabu:titus-pahlavi:arda.arda001:AV.1", invocation.urn
    assert_equal "pad nām ī yazdān", invocation.text
    assert_equal "Chapter", invocation.annotations["unit"]
  end

  def test_a_sentence_runs_across_lines_and_stops_at_the_next_sentence_header
    first = passage("urn:nabu:titus-pahlavi:arda.arda001:AV.1.1")
    assert_equal "ēdōn gōwēnd kū ēw-bār ahlaw zardušt dēn ī padīrift andar gēhān rawāg be kard", first.text
    assert_equal "Sentence", first.annotations["unit"]
    assert_equal "1", first.annotations["page"], "the full anchor's XLevel components: edition page 1"
    assert_equal "2", first.annotations["line"], "…line 2, where the sentence starts"
    second = passage("urn:nabu:titus-pahlavi:arda.arda001:AV.1.2")
    assert second.text.start_with?("tā bawandagīh [ī] sēsad sāl"), second.text
    refute_match(/Sentence/, second.text, "the nested header text is apparatus, never text")
    assert_equal "3", second.annotations["line"]
  end

  def test_the_page_footer_never_leaks_into_the_last_sentence
    # The last line's lane span is left unclosed upstream, so the footer
    # ("This text is part of the TITUS edition…") nests inside it.
    last = documents_by_page.fetch("arda001").passages.last
    assert_equal "urn:nabu:titus-pahlavi:arda.arda001:AV.1.22", last.urn
    assert last.text.end_with?("har se bār *nēzag ō wirāz āmad"), last.text
  end

  def test_document_metadata_mines_the_edition_header
    metadata = documents_by_page.fetch("arda001").metadata
    assert_equal "arda", metadata["edition"]
    assert_equal "Ardā-virāf-nāmag", metadata["edition_name"]
    assert_equal "P. Vavroušek (Praha)", metadata["editors"]
    assert_equal "Ardā Virāz Nāmag", metadata["page_title"]
    assert_match(/Data entry by P\. Vavroušek, Prague 1995/, metadata["data_entry"])
    assert_equal "transcription", metadata["representation"]
  end

  # --- bunda001: manuscript locations + the Avestan quotation lane ------------

  def test_bundahisn_page_parses_heading_and_fifty_four_sentences
    document = documents_by_page.fetch("bunda001")
    assert_equal 55, document.passages.size
    heading = passage("urn:nabu:titus-pahlavi:bundahis.bunda001:Bd.I")
    assert_equal "pad nām ī dādār ohrmazd", heading.text
    assert_equal "Bundahišn hindī, [ed.] Raqī Behzādī Tehran 1368", document.metadata["bibliography"]
  end

  def test_an_avestan_variant_with_in_word_marks_keeps_its_letters_together
    # `nā<SUP>̊</SUP>ŋhaiϑ-` — the <SUP> combining mark is part of the word.
    sentence = passage("urn:nabu:titus-pahlavi:bundahis.bunda001:Bd.I.53")
    assert_includes sentence.annotations["avestan"], "nā̊ŋhaiϑ-"
    assert_includes sentence.text, "nāghais {nānghaiϑ ̷ nā̊ŋhaiϑ- ?!} ud pas tariz"
  end

  def test_manuscript_locations_ride_each_sentence_from_its_full_anchor
    first = passage("urn:nabu:titus-pahlavi:bundahis.bunda001:Bd.I.1")
    assert first.text.start_with?("az zand-āgāhīh {!} nazdist abar bun-dahišnīh"), first.text
    assert_equal({ "page" => "1", "line" => "2", "ibd_location" => "1,1", "td1_location" => "3,7",
                   "td2_location" => "2,7", "dh_location" => "1,14" },
                 first.annotations.slice("page", "line", "ibd_location", "td1_location",
                                         "td2_location", "dh_location"))
  end

  def test_an_embedded_avestan_quotation_stays_in_the_text_and_is_annotated
    sentence = passage("urn:nabu:titus-pahlavi:bundahis.bunda001:Bd.I.41")
    assert_equal "pas ohrmazd ahunawar frāz srūd yaϑā ahū vairiiō-ē wišt ud ēk mārīg be guft.", sentence.text
    assert_equal "yaϑā ahū vairiiō", sentence.annotations["avestan"]
  end

  # --- mhd001: transliteration; apparatus note sections mint nothing ----------

  def test_mhd_transliteration_page_mints_only_its_eight_text_paragraphs
    document = documents_by_page.fetch("mhd001")
    assert_equal "transliteration", document.metadata["representation"]
    assert_equal (1..8).map { |n| "urn:nabu:titus-pahlavi:mhd.mhd001:MHD.1.#{n}" }, document.passages.map(&:urn)
    first = document.passages.first
    assert first.text.start_with?("(... ...)yh W bndgyh YHBWNyt"), first.text
    assert_equal "Paragraph", first.annotations["unit"]
  end

  def test_footnote_markers_inside_the_text_lane_are_excluded
    fifth = passage("urn:nabu:titus-pahlavi:mhd.mhd001:MHD.1.5")
    assert_match(/b\[w\]ndk' GBṞA/, fifth.text, "the fn '*' marker never enters the text")
  end

  # --- parser unit cases (inline HTML, run in CI) ----------------------------

  def test_a_short_anchor_header_continues_the_section_it_names
    # The real jamasp shape: "Sentence: _" anchored PT_Ay.Zar. (two
    # components under a Level 3 header) is the Text section itself.
    html = <<~HTML
      <html><body>
      <span id=h2><!Level 2>Text: Ay.Zar.<A NAME="PT_Ay.Zar.">&nbsp;</A></sPAN>
      <span id=miphts22>ayādgār ī zarērān</span>
      <span id=h3><!Level 3>Sentence: _<A NAME="PT_Ay.Zar.">&nbsp;</A></sPAN>
      <span id=miphtsc12>pad nām</span>
      <span id=h3><!Level 3>Sentence: 1<A NAME="PT_Ay.Zar._1">&nbsp;</A><A NAME="PT_Ay.Zar._1_200">&nbsp;</A></sPAN>
      <span id=h4><!XLevel 4>Page: 200<A NAME="PT_Ay.Zar._1_200">&nbsp;</A></sPAN>
      <span id=miphts16>ud pas</span>
      </body></html>
    HTML
    sections = PARSER.parse(html)
    assert_equal [%w[PT Ay.Zar.], %w[PT Ay.Zar. 1]], sections.map(&:components)
    assert_equal "ayādgār ī zarērān pad nām", sections.first.text
    assert_equal({ "page" => "200" }, sections.last.location)
  end

  def test_lanes_classify_by_family_at_any_size
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Sentence: 1<A NAME="X_1_1">&nbsp;</A></sPAN>
      <span id=miphts12>small gloss</span>
      <span id=iiaa16>ašə̄m vohū</span>
      <span id=miphts16>frawarane</span>
      <span id=nc12>prp. </span><span id=miphtlc12>bndgyh</span><span id=nc12> für Ms. </span>
      <span id=miphtsv12>frāz kart-nē.</span><span id=n16></span>
      <span id=iija12>ašəm.</span>
      </body></html>
    HTML
    section = PARSER.parse(html).first
    assert_equal "small gloss ašə̄m vohū frawarane ašəm.", section.text,
                 "small runs outside a note are text; a note-quoted form and a variant are not"
    assert_equal "ašə̄m vohū ašəm.", section.avestan
  end

  def test_an_unknown_pahlavi_lane_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Sentence: 1<A NAME="X_1_1">&nbsp;</A></sPAN>
      <span id=miphtq16>something</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/unknown content lane "miphtq16"/, error.message)
  end

  def test_lane_text_before_any_citation_header_quarantines_the_page
    html = "<html><body><span id=miphts16>stray words</span></body></html>"
    assert_raises(Nabu::ParseError) { PARSER.parse(html) }
  end

  def test_xlevel_headers_never_open_a_section
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Sentence: 1<A NAME="AV_1_1">&nbsp;</A></sPAN>
      <span id=miphts16>ēdōn gōwēnd</span>
      <span id=h5><!XLevel 5>Line of edition: 3<A NAME="AV_1_1_1_3">&nbsp;</A></sPAN>
      <span id=miphts16>kū</span>
      </body></html>
    HTML
    sections = PARSER.parse(html)
    assert_equal 1, sections.size
    assert_equal "ēdōn gōwēnd kū", sections.first.text
  end

  def test_a_re_anchored_citation_keys_by_occurrence_never_collides
    # The real jamasp shape (census 2026-10-07): after Ayādgār ī Zarērān
    # sentence 114 the colophon restarts at "Sentence: 2".
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Sentence: 2<A NAME="PT_Ay.Zar._2">&nbsp;</A><A NAME="PT_Ay.Zar._2_200">&nbsp;</A></sPAN>
      <span id=miphts16>ud pas</span>
      <span id=h3><!Level 3>Sentence: 114<A NAME="PT_Ay.Zar._114">&nbsp;</A></sPAN>
      <span id=miphts16>gōwēd</span>
      <span id=h3><!Level 3>Sentence: 2<A NAME="PT_Ay.Zar._2">&nbsp;</A><A NAME="PT_Ay.Zar._2_219">&nbsp;</A></sPAN>
      <span id=miphts16>harwīn wāspuhragān</span>
      </body></html>
    HTML
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "jamasp"))
      File.write(File.join(dir, "jamasp", "jamas999.htm"), html)
      document = @adapter.parse(@adapter.discover(dir).first)
      tails = document.passages.map { |p| p.urn.split(":").last }
      assert_equal %w[PT.Ay.Zar.2 PT.Ay.Zar.114 PT.Ay.Zar.2#2], tails
      assert_equal 2, document.passages.last.annotations["occurrence"]
      assert_equal "219", document.passages.last.annotations["xlevel_4"],
                   "a page declaring no XLevel 4 header keeps the raw level number"
    end
  end

  # --- fetch: one polite TitusFetch walk per edition (WebMock) ---------------

  def test_fetch_walks_each_edition_into_its_own_subdir
    base = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/mpers/arda"
    stub_request(:get, "#{base}/arda.htm")
      .to_return(body: '<frameset><frame src="arda001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{base}/arda001.htm").to_return(body: <<~HTML)
      <html><body><span id=h3><!Level 3>Sentence: 1<A NAME="AV_1_1">&nbsp;</A></sPAN>
      <span id=miphts16>ēdōn</span>
      <A HREF="/texte/etcs/iran/miran/mpers/arda/arda002.htm"><img src="/arribar.gif" alt="Next part"></A>
      </body></html>
    HTML
    stub_request(:get, "#{base}/arda002.htm").to_return(body: <<~HTML)
      <html><body><span id=h3><!Level 3>Sentence: 2<A NAME="AV_1_2">&nbsp;</A></sPAN>
      <span id=miphts16>gōwēnd</span></body></html>
    HTML
    adapter = ADAPTER.new(editions: ADAPTER::EDITIONS.slice("arda"), delay: 0)
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal %w[arda001.htm arda002.htm], Dir.children(File.join(dir, "arda")).grep(/\.htm\z/).sort
      assert File.file?(File.join(dir, "arda", Nabu::TitusFetch::STATE_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 2, adapter.discover(dir).count
    end
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_row_is_grant_gated_blocked_and_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "titus-pahlavi must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    assert entry.wired, "wired: true — the owner-fired first retrieval was verified 2026-10-10 " \
                        "(1,572 docs / 20,302 passages / 0 quarantines)"
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
