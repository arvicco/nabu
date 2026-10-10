# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Manichaica adapter tests: the three TITUS Manichaean corpora (the
# Manichaean Reader, the Corpus of Manichaean Texts arranged by editions,
# the Sermon of the Soul), one document per text page under
# canonical/titus-manichaica/<corpus>/, passages at the deepest CITATION
# level (`<!Level N>`) a page reaches — keyed by the headers' own VALUES,
# never by splitting anchors (manuscript sigla like M_7984 and item ids like
# Huy._I carry underscores). The physical `<!XLevel N>` headers (manuscript,
# page, line, the Reader cross-references) ride as passage annotations.
#
# The fixture bytes are grant-gated (Gippert, by email 2026-10-06: one
# retrieval per corpus, local personal research only, NO redistribution), so
# they live under the gitignored local/fixtures/titus-manichaica/ and every
# data-bearing case SKIPs when absent (the titus-pahlavi mold). Ground truth
# (retrieved 2026-10-10, see that dir's README). No network: fetch is
# owner-run only (WebMock below).
class TitusManichaicaTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-manichaica"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  ADAPTER = Nabu::Adapters::TitusManichaica
  PARSER = Nabu::Adapters::TitusManichaicaParser

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
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn } or flunk "no passage #{urn}"
  end

  # --- manifest: the grant's credit duty (runs in CI, no bytes) --------------

  def test_manifest_is_nc_and_credits_titus_and_the_editors
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_manichaica", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Gippert/, manifest.credit)
    ADAPTER::CORPORA.each_value do |corpus|
      assert_includes manifest.credit, corpus.credit_name, "the editors are part of the display duty"
    end
  end

  def test_corpus_table_names_the_three_manichaean_corpora_with_page_patterns
    assert_equal %w[manreadc mirmankb sermseel], ADAPTER::CORPORA.keys
    reader = ADAPTER::CORPORA.fetch("manreadc")
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/manich/manreadc/manre.htm", reader.entry_url
    assert_match reader.page_re, "manre001.htm"
    refute_match reader.page_re, "manre.htm", "the frameset is not a text page"
    refute_match reader.page_re, "manrex1.htm", "index pages are not text pages"
    assert_match ADAPTER::CORPORA.fetch("mirmankb").page_re, "mirma430.htm"
    assert_match ADAPTER::CORPORA.fetch("sermseel").page_re, "serms023.htm"
  end

  def test_one_probe_target_per_corpus
    targets = ADAPTER.http_probe_targets
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert_equal ADAPTER::CORPORA.keys, targets.map(&:state_subdir)
    assert(targets.all? { |t| t.state_file == Nabu::TitusFetch::STATE_FILE })
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_document_per_page_keyed_by_corpus_and_page
    ids = @adapter.discover(conformance_workdir).map(&:id).sort
    assert_equal %w[manreadc.manre001 manreadc.manre090 mirmankb.mirma017 mirmankb.mirma200 mirmankb.mirma398
                    mirmankb.mirma424 sermseel.serms001 sermseel.serms013 sermseel.serms023]
      .map { |tail| "urn:nabu:titus-manichaica:#{tail}" }, ids,
                 "the four header-only Corpus pages (mirma016/040/052/328) are no documents"
  end

  # --- header-only pages: skipped by rule, counted (first-sync census) -------
  #
  # The first retrieval's 41 quarantines (2026-10-10) were all mirmankb item
  # pages carrying NO content lane at all — only the item header block: 7
  # openers of items whose text sits on the following sub-item pages
  # (mirma016 "App. b" → b_I_A …), 8 non-Iranian testimonia cited by
  # reference only (mirma040 "Giants, Text L (Coptic) Kephalaia 171"), 16
  # concordance pointers to the text's home elsewhere (mirma052 "M_8280 >
  # KPT 20"), 10 editorial notes on untranscribed items (mirma328
  # "Huyadagmān Vc — Sogdian only").

  def test_header_only_pages_skip_by_rule_and_are_counted
    skips = @adapter.discovery_skips(conformance_workdir)
    assert_equal 4, skips.skipped_by_rule, "mirma016 / mirma040 / mirma052 / mirma328"
    assert_equal 0, skips.unrecognized
    assert_match(/4 header-only page\(s\) skipped/, skips.notes.join)
  end

  def test_an_item_openers_header_block_rides_its_sub_item_pages
    # mirma016 opens item "b" (subtitle "App. b" + its three manuscripts);
    # the text is on mirma017 "b_I_A" — the opener's block rides it.
    metadata = documents_by_page.fetch("mirma017").metadata
    assert_equal "mirma016", metadata["item_page"]
    assert_equal ["App. b", "M_131 (= I), M_395 and T_II_D_138 (= II)"], metadata["item_subtitles"]
    assert_equal ["M_131 = App. b, Fragment I A"], metadata["subtitles"], "the page's own block stays its own"
    refute metadata.key?("findspot"), "the opener's find signatures name the whole item — no page claim"
    assert_equal ["urn:nabu:titus-manichaica:mirmankb.mirma017:BBB.b_I_A.43"],
                 documents_by_page.fetch("mirma017").passages.map(&:urn)
  end

  def test_a_reference_only_items_header_rides_nothing
    # mirma040 / mirma052 / mirma328 are self-contained items with no text;
    # the next content page (mirma200, MKG item 8) is not inside any of them.
    refute documents_by_page.fetch("mirma200").metadata.key?("item_page")
  end

  def test_header_only_rule_in_ci_counts_lane_less_pages_and_keeps_lane_pages
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "mirmankb"))
      File.write(File.join(dir, "mirmankb", "mirma001.htm"),
                 '<span id=h2><!Level 2>Item of Ed.: b<A NAME="BBB_b">&nbsp;</A></sPAN>' \
                 "<span id=subtitle>App. b</span>")
      File.write(File.join(dir, "mirmankb", "mirma002.htm"),
                 '<span id=h2><!Level 2>Item of Ed.: b_I<A NAME="BBB_b_I">&nbsp;</A></sPAN>' \
                 "<span id=issgtl16>rty</span>")
      File.write(File.join(dir, "mirmankb", "mirma003.htm"),
                 '<span id=h2><!Level 2>Item of Ed.: c<A NAME="BBB_c">&nbsp;</A></sPAN>' \
                 "<span id=issgtl16>prw</span>")
      refs = @adapter.discover(dir)
      assert_equal(%w[mirma002 mirma003], refs.map { |r| r.metadata["page"] })
      assert_equal %w[mirma001], refs.map { |r| r.metadata["item_page"] }.compact,
                   "b_I sits inside opener b; c does not"
      assert_equal 1, @adapter.discovery_skips(dir).skipped_by_rule
      assert_equal ["App. b"], @adapter.parse(refs.first).metadata["item_subtitles"]
    end
  end

  def test_discover_ignores_framesets_indexes_and_unknown_directories
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "manreadc"))
      FileUtils.mkdir_p(File.join(dir, "stray"))
      File.write(File.join(dir, "manreadc", "manre.htm"), "<html></html>")
      File.write(File.join(dir, "manreadc", "manrex1.htm"), "<html></html>")
      File.write(File.join(dir, "stray", "stray001.htm"), "<html></html>")
      assert_empty @adapter.discover(dir).to_a
    end
  end

  # --- manre001: the Reader — transcription text, transliteration annotation -

  def test_reader_page_mints_its_ten_paragraphs
    document = documents_by_page.fetch("manre001")
    assert_equal "pal", document.language
    assert_equal 10, document.passages.size, "chapters 1-5: 3 + 4 + 1 + 1 + 1 paragraphs"
    assert_equal "Manichaean Reader (arr. by texts) (manre001)", document.title
    assert(document.passages.all? { |p| p.urn.start_with?("urn:nabu:titus-manichaica:manreadc.manre001:Reader.a.") })
  end

  def test_reader_paragraph_keeps_transcription_as_text_and_transliteration_as_annotation
    paragraph = passage("urn:nabu:titus-manichaica:manreadc.manre001:Reader.a.1.1")
    assert_equal "pal", paragraph.language
    assert_equal "dēn īg man wizīd az abārīgān dēn ī pēšēnagān pad dah xīr frāy ud wehdar ast.", paragraph.text
    assert_equal "dyn ՙyg mn wcyd ՚c ՚b՚ryg՚n dyn ՙy pyšyng՚n pd dẖ xyr fr՚y ՚wd wyhdr ՚st.",
                 paragraph.annotations["transliteration"]
    assert_equal "Paragraph", paragraph.annotations["unit"]
  end

  def test_reader_locations_come_from_the_xlevel_headers_in_force
    first = passage("urn:nabu:titus-manichaica:manreadc.manre001:Reader.a.1.1")
    assert_equal({ "editor_edition" => "Mir.Man.", "item_of_edition" => "ii", "ms" => "M_5794_I",
                   "page_of_edition" => "295", "page_of_ms" => "R", "line_of_ms" => "4_[1]_(2208)" },
                 first.annotations.slice("editor_edition", "item_of_edition", "ms", "page_of_edition",
                                         "page_of_ms", "line_of_ms"))
    turned = passage("urn:nabu:titus-manichaica:manreadc.manre001:Reader.a.2.4")
    assert_equal %w[296 V 2_(2211)], turned.annotations.values_at("page_of_edition", "page_of_ms", "line_of_ms"),
                 "the verso and the next edition page are in force when paragraph 2.4 starts"
  end

  def test_reader_document_metadata_mines_the_corpus_header
    metadata = documents_by_page.fetch("manre001").metadata
    assert_equal "manreadc", metadata["corpus"]
    assert_equal "Middle Persian and Parthian Manichæan Texts … Prose Texts Concerning Mani and " \
                 "The History of His Church", metadata["page_title"], "the collection title, then the text's own"
    assert_match(/entered by Jost Gippert, 1989/, metadata["data_entry"])
    assert_match(/Mary Boyce/, metadata["bibliography"])
    assert_equal "transcription+transliteration", metadata["representation"]
    assert_equal %w[pal], metadata["languages"]
  end

  def test_a_berlin_turfan_find_signature_mines_the_findspot
    # manre001's manuscript subtitle "M_5794_I (= T_II_D_126_I)": the T II D
    # signature's site siglum D is Qočo (the titus-tocharian-a SITE_SIGLA).
    metadata = documents_by_page.fetch("manre001").metadata
    assert_equal %w[T_II_D_126_I], metadata["find_signatures"]
    assert_equal "Qočo", metadata["findspot"]
    refute documents_by_page.fetch("manre090").metadata.key?("findspot"),
           "a page naming only the M-number carries no findspot key at all"
  end

  def test_findspot_is_minted_only_when_every_resolved_siglum_agrees
    assert_equal({ "find_signatures" => %w[T_II_D_126_I T_III_Š_72] },
                 ADAPTER.find_metadata(["M_1 (= T_II_D_126_I)", "M_2 (= T_III_Š_72)"]),
                 "two sites on one page: the signatures ride, no single findspot is claimed")
    assert_equal({ "find_signatures" => %w[T_II_K_5] }, ADAPTER.find_metadata(["M_3 (= T_II_K_5)"]),
                 "an uncensused siglum mints no place")
    assert_empty ADAPTER.find_metadata(["M_224_I"])
  end

  def test_a_text_level_heading_is_its_own_passage
    # manre090: "Text: cl" carries the hymn's heading lines (mimptl22 /
    # mimpts22) before chapter 1 — text a Level-2 section owns directly.
    document = documents_by_page.fetch("manre090")
    heading = document.passages.first
    assert_equal "urn:nabu:titus-manichaica:manreadc.manre090:Reader.cl", heading.urn
    assert_equal "āfurišn īg frēstag rōšn.", heading.text
    assert_equal "Text", heading.annotations["unit"]
    assert_equal 7, document.passages.size, "the heading + six paragraphs"
  end

  # --- mirmankb: page-start ancestors, Level-2-only items, mixed languages ---

  def test_an_item_page_without_a_level_one_header_seeds_its_edition_from_the_anchor
    # mirma200 opens at "Item of Ed.: 8" (anchor MKG_8) — the page never
    # repeats the "Edition: MKG" header, and the item has no deeper level.
    document = documents_by_page.fetch("mirma200")
    assert_equal ["urn:nabu:titus-manichaica:mirmankb.mirma200:MKG.8"], document.passages.map(&:urn)
    item = document.passages.first
    assert_equal "xpr", item.language
    assert item.text.start_with?("[...](b)yd kd fry[štg ......] [p](r)x՚št ẅ p(d) wy(՚)g [.......] " \
                                 "(՚w)d hnd<y>ny(q՚n) cy [w](x)yb(yy) w(jy)[d]"), item.text
    assert_equal({ "ms" => "M_1608", "page_of_ms" => "A", "line_of_ms" => "1_(1562)" },
                 item.annotations.slice("ms", "part_of_ms", "page_of_ms", "line_of_ms"),
                 "an emptied XLevel (Part of Ms.) is absent, never an empty string")
  end

  def test_each_edition_page_claims_the_language_of_its_own_lanes
    # mirma398, Henning's "Two Manichaean Magical Texts": edition page 40 is
    # Middle Persian (mimptl16), page 50 Parthian (mipttl16).
    mp = passage("urn:nabu:titus-manichaica:mirmankb.mirma398:Sogd.Tales.Mag.T.40")
    pt = passage("urn:nabu:titus-manichaica:mirmankb.mirma398:Sogd.Tales.Mag.T.50")
    assert_equal "pal", mp.language
    assert_equal "xpr", pt.language
    assert_equal "Page of Ed.", mp.annotations["unit"]
    assert_equal "dr", mp.annotations["text_in_reader"], "the Reader cross-reference rides along"
    assert_includes pt.text, "p]d n՚m mrym՚[ny] ՚njywg yzd՚n"
    assert_equal %w[pal xpr], documents_by_page.fetch("mirma398").metadata["languages"]
  end

  def test_a_mixed_language_item_takes_its_predominant_lane_and_lists_the_rest
    # mirma424, Colditz's Parthian parable fragments: M_44 switches to the
    # Sogdian lane (issgtl16) for its last lines.
    item = passage("urn:nabu:titus-manichaica:mirmankb.mirma424:IC.BMPP")
    assert_equal "xpr", item.language
    assert_equal %w[sog xpr], item.annotations["languages"]
    assert_includes item.text, "pryβyy myϑq[r]yy ՚sṭyy"
    assert_equal "_H", item.annotations["line_of_ms"], "the heading-line value verbatim, underscore kept"
    metadata = documents_by_page.fetch("mirma424").metadata
    assert_match(/Iris Colditz/, metadata["bibliography"])
    assert_includes metadata["subtitles"], "(Parthian)"
  end

  # --- sermseel: reconstructed text vs manuscript witnesses; Sogdian; Turkic -

  def test_sermon_parts_keep_the_reconstructed_line_and_drop_the_witnesses
    document = documents_by_page.fetch("serms001")
    assert_equal (1..4).map { |n| "urn:nabu:titus-manichaica:sermseel.serms001:SS.H.#{n}" },
                 document.passages.map(&:urn), "the 'Part: 1_n.1' note sections mint nothing"
    first = document.passages.first
    assert_equal "gy՚n wyfr՚s", first.text, "the fn marker is no break; witness lines (v) are apparatus"
    assert_equal "xpr", first.language
    assert_equal "Part", first.annotations["unit"]
  end

  def test_sogdian_sermon_fragment_claims_sog
    document = documents_by_page.fetch("serms013")
    assert_equal "sog", document.language
    assert_equal (127..131).map { |n| "urn:nabu:titus-manichaica:sermseel.serms013:SS.2.#{n}" },
                 document.passages.map(&:urn)
    part = passage("urn:nabu:titus-manichaica:sermseel.serms013:SS.2.128")
    assert_equal "rty prw 'z-prtw βws'nt'kw ZY rwc'(y)kw ZKw δ'mh c(nn pnc)[w] mrδ'sp'nty βγyšty δβ'yš 'wr'm'ty",
                 part.text
    # Part 128 starts MID-line: its first words close manuscript line 2,
    # before the "Line of Ms.: 3" header — the location is where it starts.
    assert_equal({ "ms" => "So_10650(2)_+_So_18131", "part_of_ms" => "bb", "line_of_ms" => "2" },
                 part.annotations.slice("ms", "part_of_ms", "line_of_ms"))
  end

  def test_turkic_appendix_fragment_claims_old_uyghur_with_both_renderings
    document = documents_by_page.fetch("serms023")
    assert_equal "oui", document.language
    first = passage("urn:nabu:titus-manichaica:sermseel.serms023:SS.OT.1")
    assert_equal "... sütdän; ymä [suvuγ] sorγun tartar [...]", first.text
    assert_includes first.annotations["transliteration"], "swytδ՚n .. ym՚"
  end

  # --- parser unit cases (inline HTML, run in CI) ----------------------------

  def test_lanes_classify_by_family_at_any_size
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Part: 1<A NAME="SS_H_1">&nbsp;</A></sPAN>
      <span id=mipttl22>heading</span><BR>
      <span id=mipttl16>body</span><span id=mipttlv12>witness</span>
      <span id=nc12>Var. </span><span id=mipttsv12>noted</span><BR>
      <span id=mitktl12>small text</span>
      </body></html>
    HTML
    section = PARSER.parse(html).first
    assert_equal "heading body small text", section.text,
                 "non-variant runs are text at any size; v-flavor runs (witnesses, note-quoted forms) are not"
    assert_equal %w[SS H 1], section.components, "levels 1-2 seeded from the page-start anchor SS_H_1"
    assert_equal "xpr", section.language, "the lane carrying most of the text"
    assert_equal %w[oui xpr], section.languages
  end

  def test_an_unknown_lane_language_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Part: 1<A NAME="SS_H_1">&nbsp;</A></sPAN>
      <span id=mizzts16>something</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/unknown content lane "mizzts16"/, error.message)
  end

  def test_an_unknown_content_prefix_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h3><!Level 3>Part: 1<A NAME="SS_H_1">&nbsp;</A></sPAN>
      <span id=iijaq16>something</span>
      </body></html>
    HTML
    assert_raises(Nabu::ParseError) { PARSER.parse(html) }
  end

  def test_lane_text_before_any_citation_header_quarantines_the_page
    html = "<html><body><span id=mimptl16>stray words</span></body></html>"
    assert_raises(Nabu::ParseError) { PARSER.parse(html) }
  end

  def test_header_values_key_sections_even_when_anchors_carry_underscores
    # MHC item "Huy._I" anchors MHC_Huy._I — a positional anchor split would
    # read item "Huy." (a DIFFERENT item); the header's own value is exact.
    html = <<~HTML
      <html><body>
      <span id=h2><!Level 2>Item of Ed.: Huy._I<A NAME="MHC_Huy._I">&nbsp;</A></sPAN>
      <span id=h7><!XLevel 7>Manuscript: M_7984<A NAME="MHC_Huy._I_M_7984">&nbsp;</A></sPAN>
      <span id=mipttl16>first</span>
      <span id=h3><!Level 3>Page of Ed.: 70<A NAME="MHC_Huy._I_70">&nbsp;</A></sPAN>
      <span id=mipttl16>second</span>
      </body></html>
    HTML
    sections = PARSER.parse(html)
    assert_equal [%w[MHC Huy._I], %w[MHC Huy._I 70]], sections.map(&:components)
    assert_equal({ "ms" => "M_7984" }, sections.first.location)
  end

  def test_a_re_anchored_citation_keys_by_occurrence_never_collides
    html = <<~HTML
      <html><body>
      <span id=h1><!Level 1>Text: SS<A NAME="SS">&nbsp;</A></sPAN>
      <span id=h3><!Level 3>Part: 2<A NAME="SS_2">&nbsp;</A></sPAN>
      <span id=issgtl16>rty</span>
      <span id=h3><!Level 3>Part: 3<A NAME="SS_3">&nbsp;</A></sPAN>
      <span id=issgtl16>prw</span>
      <span id=h3><!Level 3>Part: 2<A NAME="SS_2">&nbsp;</A></sPAN>
      <span id=issgtl16>again</span>
      </body></html>
    HTML
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sermseel"))
      File.write(File.join(dir, "sermseel", "serms999.htm"), html)
      document = @adapter.parse(@adapter.discover(dir).first)
      tails = document.passages.map { |p| p.urn.split(":").last }
      assert_equal %w[SS.2 SS.3 SS.2#2], tails
      assert_equal 2, document.passages.last.annotations["occurrence"]
    end
  end

  def test_a_severed_utf8_sequence_is_repaired_through_the_pahlavi_reader
    # The titus-pahlavi first-sync defect class (a multibyte sequence cut by
    # a tag): the shared read_page repair applies to every TITUS family.
    bytes = "<span id=h3><!Level 3>Part: 1<A NAME=\"SS_H_1\">&nbsp;</A></sPAN>" \
            "<span id=mipttl16><a href=x>wyfr\xCA</a>\xBCs</span>".b
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sermseel"))
      File.binwrite(File.join(dir, "sermseel", "serms998.htm"), bytes)
      document = @adapter.parse(@adapter.discover(dir).first)
      assert_equal "wyfrʼs", document.passages.first.text
    end
  end

  def test_unrepairable_invalid_utf8_quarantines_never_aborts
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sermseel"))
      File.binwrite(File.join(dir, "sermseel", "serms997.htm"),
                    "<span id=h3><!Level 3>Part: 1<A NAME=\"SS_1\">&nbsp;</A></sPAN>" \
                    "<span id=mipttl16>W \xFF\xFE ZK</span>".b)
      error = assert_raises(Nabu::ParseError) { @adapter.parse(@adapter.discover(dir).first) }
      assert_match(/serms997\.htm is not valid UTF-8/, error.message)
    end
  end

  def test_a_content_page_with_no_text_sections_quarantines
    # A page naming a lane is a content page (discovered); if every lane run
    # is apparatus, no section survives — a structural failure, not a skip.
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sermseel"))
      File.write(File.join(dir, "sermseel", "serms996.htm"),
                 "<span id=h3><!Level 3>Part: 1_n.1<A NAME=\"SS_1_n.1\">&nbsp;</A></sPAN><span id=nc12>Var.</span>" \
                 "<span id=mipttlv12>witness</span>")
      error = assert_raises(Nabu::ParseError) { @adapter.parse(@adapter.discover(dir).first) }
      assert_match(/no text sections in .*serms996\.htm/, error.message)
    end
  end

  # --- fetch: one polite TitusFetch walk per corpus (WebMock) ----------------

  def test_fetch_walks_each_corpus_into_its_own_subdir
    base = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/manich/sermseel"
    stub_request(:get, "#{base}/serms.htm")
      .to_return(body: '<frameset><frame src="serms001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{base}/serms001.htm").to_return(body: <<~HTML)
      <html><body><span id=h3><!Level 3>Part: 1<A NAME="SS_H_1">&nbsp;</A></sPAN>
      <span id=mipttl16>gy՚n</span>
      <A HREF="/texte/etcs/iran/miran/manich/sermseel/serms002.htm"><img src="/arribar.gif" alt="Next part"></A>
      </body></html>
    HTML
    stub_request(:get, "#{base}/serms002.htm").to_return(body: <<~HTML)
      <html><body><span id=h3><!Level 3>Part: 2<A NAME="SS_H_2">&nbsp;</A></sPAN>
      <span id=mipttl16>wyfr՚s</span></body></html>
    HTML
    adapter = ADAPTER.new(corpora: ADAPTER::CORPORA.slice("sermseel"), delay: 0)
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal %w[serms001.htm serms002.htm], Dir.children(File.join(dir, "sermseel")).grep(/\.htm\z/).sort
      assert File.file?(File.join(dir, "sermseel", Nabu::TitusFetch::STATE_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 2, adapter.discover(dir).count
    end
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_row_is_grant_gated_blocked_and_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "titus-manichaica must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the owner-fired first retrieval is verified"
    assert_equal "manual", entry.sync_policy
    assert_predicate entry, :grant_required?
    assert_predicate entry, :blocked?
    assert_equal "2026-10-06", entry.grant.date
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/one retrieval per corpus/i, entry.grant.terms)
    assert_match(/no redistribution/i, entry.grant.terms)
    assert_match(/titus-manichaica: fetch requires a GRANT/, Nabu::GrantGate.notice(entry))
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
