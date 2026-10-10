# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Sogdian adapter tests: the two Sogdian corpora on TITUS — the Sogdian
# Corpus "arranged by texts" (N. Sims-Williams) and Morano's Stellung-Jesu
# hymns — one document per text page under canonical/titus-sogdian/<corpus>/,
# passages at the MANUSCRIPT LINE (the `Line of Manuscript` XLevel header),
# keyed by the header VALUES (never the unsplittable, stale-carrying anchors).
#
# The fixture bytes are grant-gated (Gippert, by email 2026-10-06: one
# retrieval, local personal research only, NO redistribution), so they live
# under the gitignored local/fixtures/titus-sogdian/ and every data-bearing
# case SKIPs when absent. Ground truth (retrieved 2026-10-10, see that dir's
# README): sogdm001 (Morano — the whole reachable corpus), and from the NSW
# corpus the header-only text openers 001/002/150/214/224/254/376, the unread
# entries 380/381, plus the content pages 003 (Christian, Syriac script), 119
# (BBB, Manichaean script), 156 (Tales — a Greek heading run), 165 (Magi —
# heading/rubric lanes), 222 (London — the lone "b" script code), 230 (Paris
# Buddhist — a Sanskrit heading run), 255 (Mug documents) and 377 (Ancient
# Letters — note-quoted forms).
# No network: fetch is owner-run only (WebMock below).
class TitusSogdianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-sogdian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  ADAPTER = Nabu::Adapters::TitusSogdian
  PARSER = Nabu::Adapters::TitusSogdianParser
  DOC = "urn:nabu:titus-sogdian"

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
    documents_by_page.values.flat_map(&:passages).find { |p| p.urn == urn } || flunk("no passage #{urn}")
  end

  # --- manifest: the grant's credit duty (runs in CI, no bytes) --------------

  def test_manifest_is_nc_and_credits_titus_and_the_editors
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_sogdian", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Gippert/, manifest.credit)
    ADAPTER::EDITIONS.each_value do |edition|
      assert_includes manifest.credit, edition.credit_name, "the editors are part of the display duty"
      assert_includes edition.editors, edition.credit_name
    end
  end

  def test_edition_table_names_the_two_titus_sogdian_corpora
    assert_equal %w[sogdnswc sogdmor], ADAPTER::EDITIONS.keys
    nsw = ADAPTER::EDITIONS.fetch("sogdnswc")
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/sogd/sogdnswc/sogdn.htm", nsw.entry_url
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/sogd/sogdmor/sogdm.htm",
                 ADAPTER::EDITIONS.fetch("sogdmor").entry_url
    assert_match nsw.page_re, "sogdn001.htm"
    refute_match nsw.page_re, "sogdn.htm", "the frameset is not a text page"
    refute_match nsw.page_re, "sogdnx12.htm", "the per-text index frames are not text pages"
  end

  def test_one_probe_target_per_corpus
    targets = ADAPTER.http_probe_targets
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    assert_equal ADAPTER::EDITIONS.keys, targets.map(&:state_subdir)
    assert(targets.all? { |t| t.state_file == Nabu::TitusFetch::STATE_FILE })
  end

  # --- discovery: content pages, header-only openers skip with accounting ----

  def test_discover_yields_one_document_per_content_page
    ids = @adapter.discover(conformance_workdir).map(&:id).sort
    assert_equal %W[#{DOC}:sogdmor.sogdm001 #{DOC}:sogdnswc.sogdn003 #{DOC}:sogdnswc.sogdn119
                    #{DOC}:sogdnswc.sogdn156 #{DOC}:sogdnswc.sogdn165 #{DOC}:sogdnswc.sogdn222
                    #{DOC}:sogdnswc.sogdn230 #{DOC}:sogdnswc.sogdn255 #{DOC}:sogdnswc.sogdn377], ids
  end

  def test_header_only_text_openers_skip_by_rule_with_accounting
    skips = @adapter.discovery_skips(conformance_workdir)
    assert_equal 9, skips.skipped_by_rule,
                 "sogdn001/002/150/214/224/254/376 carry a title block and no text row; " \
                 "sogdn380/381 are unread manuscript entries"
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join(" ")
    assert_match(/7 header-only page/, notes)
    assert_match(/2 unread page/, notes)
  end

  def test_an_unread_manuscript_entry_with_only_a_blank_line_skips_by_rule
    # sogdn380 / sogdn381 (Anc.Scr. L.A.II.v.028, L.L.018): a manuscript
    # header, the note "not yet read: NSW", one "Line of Manuscript: _" and
    # an issgtl16 lane holding only &nbsp; — no text, never a quarantine.
    pages = @adapter.discover(conformance_workdir).map { |ref| ref.metadata["page"] }
    refute_includes pages, "sogdn380"
    refute_includes pages, "sogdn381"
  end

  def test_a_page_inherits_its_text_from_the_latest_level_one_page
    refs = @adapter.discover(conformance_workdir).to_h { |ref| [ref.metadata["page"], ref.metadata] }
    assert_equal({ "edition" => "sogdnswc", "page" => "sogdn003", "text" => "C_1", "text_page" => "sogdn002" },
                 refs.fetch("sogdn003"))
    assert_equal "Par.", refs.fetch("sogdn230")["text"]
    assert_equal "sogdn119", refs.fetch("sogdn119")["text_page"], "a page carrying its own Level-1 header"
  end

  # --- metadata: the text opener's header block rides every page -------------

  def test_the_text_openers_header_block_rides_as_text_metadata
    metadata = documents_by_page.fetch("sogdn003").metadata
    assert_equal "C_1", metadata["text"]
    assert_equal ["Christian Texts", "C_1: Passion of St. Georg"], metadata["text_titles"]
    assert_match(/\AO\. Hansen, Berliner soghdische Texte I\./, metadata["text_bibliography"])
    assert_equal ["T_II_B_30", "C_1, 1: T_II_B_30.4 Vl"], metadata["subtitles"], "the page's own block"
    assert_equal ["Syrc"], metadata["scripts"]
    assert_match(/Sims-Williams/, metadata["editors"])
  end

  def test_a_sanskrit_heading_run_completes_its_subtitle_and_is_never_text
    document = documents_by_page.fetch("sogdn230")
    assert_includes document.metadata["subtitles"],
                    "Fragment of the Bhaiṣajyaguruvaiḍūryaprabhātatathāgatasūtra"
    refute(document.passages.any? { |p| p.text.include?("Bhaiṣajya") })
    assert(document.passages.all? { |p| p.language == "sog" })
  end

  def test_a_greek_heading_run_completes_its_subtitle_and_is_never_text
    # sogdn156 (Tales, item E): <subtitle>E: </subtitle><gr22>Βαγίστανον ὄρος</gr22>
    # — the Greek name of the tale's mountain, the corpus's only gr* span.
    document = documents_by_page.fetch("sogdn156")
    assert_includes document.metadata["subtitles"], "E: Βαγίστανον ὄρος"
    refute(document.passages.any? { |p| p.text.include?("Βαγίστανον") })
    assert(document.passages.all? { |p| p.language == "sog" })
    assert_equal "Tales", document.metadata["text"]
  end

  def test_a_greek_lane_outside_a_heading_quarantines
    html = <<~HTML
      <html><body>
      <span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME="X_1">&nbsp;</A></sPAN>&nbsp;
      </span><span id=gr22>ὄρος</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/unknown Greek lane "gr22" outside a heading/, error.message)
  end

  def test_the_lone_b_script_code_is_the_sogdian_script
    # sogdn222, London Frg. 28 (ed. S-W 1978): issgbl16 amid issgsbl16
    # siblings, transliterated consonantally with aleph — Sogdian script.
    document = documents_by_page.fetch("sogdn222")
    line = passage("#{DOC}:sogdnswc.sogdn222:Frg.28.Frg28.1")
    assert_equal "[ ՚](p)try", line.text
    assert_equal "Sogd", line.annotations["script"]
    assert_equal "Lond.", document.metadata["text"]
    assert_equal ["Sogd"], document.metadata["scripts"]
  end

  def test_the_page_footer_never_leaks_into_header_metadata
    # sogdn224's bibliogr span is left unclosed upstream; the footer nests in it.
    bibliography = documents_by_page.fetch("sogdn230").metadata["text_bibliography"]
    assert bibliography.end_with?("(Mission Pelliot en Asie Centrale, sér. in-quarto, IV)"), bibliography
  end

  # --- sogdn003: the Christian corpus (Syriac script), keyed from values ------

  def test_christian_line_is_keyed_by_header_values_with_its_location
    line = passage("#{DOC}:sogdnswc.sogdn003:1.1.T_II_B_30_.4.Vl.1")
    assert_equal "w՚n γwd՚[rt . . .", line.text
    assert_equal "sog", line.language
    assert_equal "Syrc", line.annotations["script"]
    assert_equal({ "chapter" => "1", "paragraph" => "1", "manuscript" => "T_II_B_30_.4",
                   "new_manuscript" => "011r", "page_of_manuscript" => "Vl", "line_of_manuscript" => "1",
                   "page_of_edition" => "9" },
                 line.annotations.slice("chapter", "paragraph", "manuscript", "new_manuscript",
                                        "page_of_manuscript", "line_of_manuscript", "page_of_edition"))
    assert_equal "C_1_1__T_II_B_30_.4_011r_Vl_1", line.annotations["titus_anchor"]
    assert_equal "Bulayïq", line.annotations["findspot"], "the Berlin T II B signature's site siglum"
  end

  # --- sogdn119: BBB, the Manichaean script ------------------------------------

  def test_manichaean_page_mints_one_passage_per_line
    document = documents_by_page.fetch("sogdn119")
    assert_equal "sog", document.language
    assert_equal 19, document.passages.size
    assert_equal (30..48).map { |n| "#{DOC}:sogdnswc.sogdn119:#{n}" }, document.passages.map(&:urn)
    first = document.passages.first
    assert_equal "[pw ՚zrmy՚ḫ]", first.text
    assert_equal "Mani", first.annotations["script"]
    assert_equal "Sogdian — Sogdian Corpus (NSW), arranged by texts: BBB (sogdn119)", document.title
    assert_equal ["A Manichæan Service Book"], document.metadata["titles"]
  end

  # --- sogdn165: heading + rubric lanes are running text ----------------------

  def test_heading_and_rubric_flavored_lanes_are_text
    heading = passage("#{DOC}:sogdnswc.sogdn165:So18248i.R._H")
    assert_equal "nγ՚wš՚k՚n՚k wyδβ՚γ . . .", heading.text, "issgsml22 + the r-flavored issgsmlr22"
    assert_equal "Sogd", heading.annotations["script"]
    assert_equal 117, documents_by_page.fetch("sogdn165").passages.size
  end

  # --- sogdn377: the Ancient Letters — note-quoted forms are apparatus --------

  def test_small_runs_quoted_inside_editorial_notes_are_apparatus
    line = passage("#{DOC}:sogdnswc.sogdn377:A.L.1.Or._8212_(92).R.9")
    assert_equal "nnyδt tys՚t ՚ḤRZY ՚zw՚m βyzβr՚k ՚pw nγ(՚)wδn ՚pw ՚zγ՚mk ՚ḤRZY x(wy)z՚m p՚(r)h", line.text
    letter2 = passage("#{DOC}:sogdnswc.sogdn377:A.L.2.Or._8212_(95).R.1")
    assert_equal "ՙD βγw xwt՚w *βrz՚kkw nnyδβ՚՚rw k՚n՚kk 1LP βrywr ŠLM", letter2.text,
                 "the MS reading βr՚kkw. (issgtl12 after a voc12 note) is not text"
    assert_equal 254, documents_by_page.fetch("sogdn377").passages.size
  end

  # --- sogdm001: Morano — the whole reachable corpus --------------------------

  def test_morano_page_splits_lines_at_mid_line_paragraphs
    document = documents_by_page.fetch("sogdm001")
    assert_equal 57, document.passages.size, "49 manuscript lines + 8 mid-line paragraph starts"
    first = document.passages.first
    assert_equal "#{DOC}:sogdmor.sogdm001:17-34.TM_351.R.1", first.urn
    assert_equal "pr xypδ m(...) oox/γw[", first.text
    assert_equal({ "editor_edition" => "WL.", "item_of_edition" => "i", "page_of_edition" => "93" },
                 first.annotations.slice("editor_edition", "item_of_edition", "page_of_edition"))
    tail = passage("#{DOC}:sogdmor.sogdm001:36.1.T_II_D_II_169.R.19")
    assert_equal "m'γ o", tail.text
    head = passage("#{DOC}:sogdmor.sogdm001:36.2.T_II_D_II_169.R.19")
    assert_equal "'nž'wny 'zrw' βγ'y fry z'ty", head.text, "paragraph 2 starts mid-line 19"
    assert_equal "Qočo", head.annotations["findspot"], "T II D = Qočo"
  end

  def test_an_embedded_parthian_run_stays_in_the_sogdian_line_and_is_annotated
    line = passage("#{DOC}:sogdmor.sogdm001:36.H.T_II_D_II_169.R.16")
    assert_equal "''γšt pwr kr'm γwβw 'yšw γwβty' oo", line.text
    assert_equal "sog", line.language
    assert_equal "pwr kr'm", line.annotations["embedded_xpr"]
  end

  def test_a_lacuna_row_without_its_own_line_header_continues_the_line
    line = passage("#{DOC}:sogdmor.sogdm001:17-34.TM_351.R.7")
    assert_equal "ptymt 'w ym' (??) (..)t //////////////////////////////////////", line.text
  end

  # --- parser unit cases (inline HTML from real page shapes, run in CI) ------

  def test_a_turkic_lane_claims_old_uyghur
    # The real sogdn200 M_1775 shape: "Turkic fragment." then mitktl16.
    html = <<~HTML
      <html><body>
      <span id=h4><!XLevel 4>Manuscript: M_1775<A NAME="Berl._M_1775">&nbsp;</A></sPAN>
      <span id=voc12>Turkic fragment.</span>
      <span id=h7><!XLevel 7>Line of Manuscript: 3<A NAME="Berl._M_1775_R_3">&nbsp;</A></sPAN>&nbsp;
      </span><span id=mitktl16>](k)y ṭwyrṭ ṭ(w)[yrṭ]</span>
      </body></html>
    HTML
    section = PARSER.parse(html).sections.first
    assert_equal "oui", section.language
    assert_equal "](k)y ṭwyrṭ ṭ(w)[yrṭ]", section.text
    assert_empty section.scripts, "no script is claimed for the Turkic lane"
  end

  def test_a_word_split_over_two_lines_keeps_its_x_flavor_halves
    # The real sogdn200 shape: "δc՚=" ending one line, "=pt" opening the next.
    html = <<~HTML
      <html><body>
      <span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME="M_1">&nbsp;</A></sPAN>&nbsp;
      </span><span id=issgmml16>xwt՚w </span><span id=issgmmlx16>δc՚=</span>
      <span id=h7><!XLevel 7>Line of Manuscript: 2<A NAME="M_2">&nbsp;</A></sPAN>&nbsp;
      </span><span id=issgmmlx16>=pt</span><span id=issgmml16> βγyy</span>
      </body></html>
    HTML
    assert_equal ["xwt՚w δc՚=", "=pt βγyy"], PARSER.parse(html).sections.map(&:text)
  end

  def test_an_unknown_lane_quarantines_the_page
    html = <<~HTML
      <html><body>
      <span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME="X_1">&nbsp;</A></sPAN>
      <span id=mipht16>something</span>
      </body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/unknown content lane "mipht16"/, error.message)
  end

  def test_an_unknown_script_code_or_flavor_in_a_known_family_quarantines
    line = '<span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME="X_1">&nbsp;</A></sPAN>'
    error = assert_raises(Nabu::ParseError) { PARSER.parse("#{line}<span id=issgql16>w</span>") }
    assert_match(/unknown script code "q"/, error.message)
    error = assert_raises(Nabu::ParseError) { PARSER.parse("#{line}<span id=issgtlv16>w</span>") }
    assert_match(/unknown flavor "v"/, error.message)
  end

  def test_lane_text_before_any_header_quarantines_the_page
    assert_raises(Nabu::ParseError) { PARSER.parse("<html><body><span id=issgtl16>stray</span></body></html>") }
  end

  def test_a_paragraph_header_before_the_lines_text_keeps_the_line_key
    # The real sogdn004 order: Line 1 header, then "Paragraph: 16", then text.
    html = <<~HTML
      <html><body>
      <span id=h2><!Level 2>Chapter: 2<A NAME="C_1_2">&nbsp;</A></sPAN>
      <span id=h6><!XLevel 6>Page of Manuscript: Rr<A NAME="C_1_2__Rr">&nbsp;</A></sPAN>
      <span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME="C_1_2__Rr_1">&nbsp;</A></sPAN>
      <span id=h3><!Level 3>Paragraph: 16<A NAME="C_1_2_16">&nbsp;</A></sPAN>&nbsp;
      </span><span id=issgcl16>[ ●●]՚[●●●]wq ܀ ՚t . . .</span>
      </body></html>
    HTML
    section = PARSER.parse(html).sections.first
    assert_equal "2.16.Rr.1", section.key
    assert_equal "C_1_2__Rr_1", section.anchor
  end

  def test_upper_indus_chapter_toponyms_and_unknown_sigla
    assert_equal "Shatial", ADAPTER.findspot_for({ "chapter" => "Shatial" }, text: "Upp.Ind.")
    assert_equal "Upper Indus", ADAPTER.findspot_for({ "chapter" => "UI" }, text: "Upp.Ind.")
    assert_nil ADAPTER.findspot_for({ "chapter" => "80TBI" }, text: "Upp.Ind."), "never guessed"
    assert_nil ADAPTER.findspot_for({ "chapter" => "Shatial" }, text: "BBB"), "only the inscription text"
    assert_nil ADAPTER.findspot_for({ "manuscript" => "T_III_X_1" }, text: "Berl."), "unknown siglum"
    assert_nil ADAPTER.findspot_for({ "manuscript" => "M_1775" }, text: "Berl.")
  end

  def test_a_severed_utf8_page_is_repaired_through_the_pahlavi_reader
    # The titus-pahlavi belt: a multibyte sequence cut by </a> is rejoined.
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sogdnswc"))
      File.binwrite(File.join(dir, "sogdnswc", "sogdn005.htm"),
                    "<span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME=\"C_1\">&nbsp;</A></sPAN>" \
                    "<span id=issgcl16><a id=issgcl16>γwd\xCC</a>\xB1</span>".b)
      document = @adapter.parse(@adapter.discover(dir).first)
      assert_equal "γw\u1E0F", document.passages.first.text
    end
  end

  def test_unrepairable_invalid_utf8_quarantines_never_aborts
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sogdnswc"))
      File.binwrite(File.join(dir, "sogdnswc", "sogdn005.htm"),
                    "<span id=h7><!XLevel 7>Line of Manuscript: 1<A NAME=\"C_1\">&nbsp;</A></sPAN>" \
                    "<span id=issgcl16>w \xFF\xFE</span>".b)
      error = assert_raises(Nabu::ParseError) { @adapter.parse(@adapter.discover(dir).first) }
      assert_match(/sogdn005\.htm is not valid UTF-8/, error.message)
    end
  end

  def test_discover_ignores_framesets_index_frames_and_unknown_directories
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sogdnswc"))
      FileUtils.mkdir_p(File.join(dir, "stray"))
      %w[sogdn.htm sogdnx.htm sogdnx3.htm sogdnxx.htm].each { |name| File.write(File.join(dir, "sogdnswc", name), "") }
      File.write(File.join(dir, "stray", "sogdn001.htm"), "<span id=issgtl16>w</span>")
      assert_empty @adapter.discover(dir).to_a
    end
  end

  # --- fetch: one polite TitusFetch walk per corpus (WebMock) ----------------

  def test_fetch_walks_each_corpus_into_its_own_subdir
    base = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/sogd/sogdmor"
    stub_request(:get, "#{base}/sogdm.htm")
      .to_return(body: '<frameset><frame src="sogdm001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{base}/sogdm001.htm").to_return(body: <<~HTML)
      <html><body><span id=h10><!XLevel 10>Line of Manuscript: 1<A NAME="WL._R_1">&nbsp;</A></sPAN>
      <span id=issgtl16>pr xypδ</span></body></html>
    HTML
    adapter = ADAPTER.new(editions: ADAPTER::EDITIONS.slice("sogdmor"), delay: 0)
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal %w[sogdm001.htm], Dir.children(File.join(dir, "sogdmor")).grep(/\.htm\z/)
      assert File.file?(File.join(dir, "sogdmor", Nabu::TitusFetch::STATE_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 1, adapter.discover(dir).count
    end
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_row_is_grant_gated_blocked_and_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "titus-sogdian must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired flips only after the owner-fired first retrieval is verified"
    assert_equal "manual", entry.sync_policy
    assert_predicate entry, :grant_required?
    assert_predicate entry, :blocked?
    assert_equal "2026-10-06", entry.grant.date
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/one retrieval/i, entry.grant.terms)
    assert_match(/no redistribution/i, entry.grant.terms)
    assert_match(/titus-sogdian: fetch requires a GRANT/, Nabu::GrantGate.notice(entry))
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
