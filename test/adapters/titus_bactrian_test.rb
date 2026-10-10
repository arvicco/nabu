# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# TITUS Bactrian adapter tests: the Corpus of Bactrian Texts (N.
# Sims-Williams; TITUS version J. Gippert 2010), one document per text page
# (canonical/titus-bactrian/baktcNNN.htm), passages at the MANUSCRIPT LINE
# grain keyed off the `<!Level 4>` "Line" headers, the edition's own line
# labels kept verbatim.
#
# The fixture bytes are grant-gated (Gippert, by email 2026-10-06: one
# retrieval, local personal research only, NO redistribution), so they live
# under the gitignored local/fixtures/titus-bactrian/ and every data-bearing
# case SKIPs when absent (on the owner's box StrictSkips turns a skip into a
# failure). Ground truth (retrieved 2026-10-10, see that dir's README):
# baktc001 (corpus header + conventions, dated document A: 36 lines, the
# era formula, broken words, notes), baktc002 (Aa: the italic second copy,
# primed and parenthesized line labels — 9 lines), baktc046 (am, a tally
# list: 1A/5+6A/30+37 labels, "traces only" lines — 40 lines), baktc047
# (22 HEADERLESS lines, then letter bb — 37 lines), baktc122 (Buddhist text
# za — 20 lines). The first-sync regression pages (2026-10-10, copied from
# the banked canonical tree): baktc030 (W — a label-less Line header nested
# inside line (23)), baktc123 (zb — the page numeral "αʹ" at text level,
# before line 1), baktc037 / baktc117 / baktc121 (ae / xt / yd — illegible
# texts: a Level-3 header and an editorial verdict, no transcribed line;
# skipped by rule at discovery). No network: fetch is owner-run only
# (WebMock below).
class TitusBactrianTest < Minitest::Test
  include AdapterConformance

  SLUG = "titus-bactrian"
  FIXTURES = Nabu::TestSupport.local_fixtures(SLUG)
  ADAPTER = Nabu::Adapters::TitusBactrian
  PARSER = Nabu::Adapters::TitusBactrianParser

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
    assert_equal "titus_bactrian", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license, "the grant date is recorded")
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Gippert/, manifest.credit)
    assert_match(/Sims-Williams/, manifest.credit, "the corpus's editor is part of the display duty")
  end

  def test_single_probe_target_is_the_frameset_entry
    assert_equal :http_zip, ADAPTER.remote_probe_strategy
    target = only(ADAPTER.http_probe_targets)
    assert_equal "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/baktr/baktcorp/baktc.htm", target.zip_url
    assert_equal Nabu::TitusFetch::STATE_FILE, target.state_file
  end

  def test_page_pattern_admits_text_pages_only
    assert_match ADAPTER::PAGE_RE, "baktc001.htm"
    assert_match ADAPTER::PAGE_RE, "baktc126.htm"
    refute_match ADAPTER::PAGE_RE, "baktc.htm", "the frameset is not a text page"
    refute_match ADAPTER::PAGE_RE, "baktcx1.htm", "the index frames are not text pages"
    refute_match ADAPTER::PAGE_RE, "baktcxx.htm"
  end

  # --- the era formula (runs in CI, no bytes) ---------------------------------

  def test_era_formula_sums_the_greek_numerals
    assert_equal({ "formula" => "χϸονο ρʹ ιʹ", "era_year" => 110, "uncertain" => false },
                 ADAPTER.era_formula("χϸονο ρʹ ιʹ Αυρηζνο μα̅ο̅"))
  end

  def test_era_formula_keeps_restorations_and_flags_them_uncertain
    assert_equal({ "formula" => "[χ]ϸονο ρʹ λ̣ʹ δʹ", "era_year" => 134, "uncertain" => true },
                 ADAPTER.era_formula("[χ]ϸονο ρʹ λ̣ʹ δʹ δηματριγανο"))
  end

  def test_era_formula_needs_numerals
    assert_nil ADAPTER.era_formula("χϸονο Αυρηζνο")
    assert_nil ADAPTER.era_formula("αβο μο ρωβαγγο")
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_document_per_text_page
    ids = @adapter.discover(conformance_workdir).map(&:id).sort
    assert_equal %w[baktc001 baktc002 baktc030 baktc046 baktc047 baktc122 baktc123]
      .map { |s| "urn:nabu:titus-bactrian:#{s}" }, ids,
                 "the illegible-text pages (baktc037/117/121) are skipped by rule, not yielded"
  end

  def test_discovery_skips_count_the_illegible_text_pages
    skips = @adapter.discovery_skips(conformance_workdir)
    assert_equal 3, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal(%w[baktc037.htm baktc117.htm baktc121.htm], skips.notes.map { |note| note.split(":").first })
    assert_match(/text ae: no transcribed line/, skips.notes.first)
  end

  def test_a_page_without_any_bactrian_lane_is_skipped_by_rule
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "baktc001.htm"), line_page("<span id=gbbk16>αβο</span>"))
      File.write(File.join(dir, "baktc002.htm"), <<~HTML)
        <html><body><span id=h3><!Level 3>Text: ae<A NAME="Bactr.Corp._Doc.Fragm._ae">&nbsp;</A></sPAN>
        <span id=nc16>illegible</span></body></html>
      HTML
      assert_equal ["urn:nabu:titus-bactrian:baktc001"], @adapter.discover(dir).map(&:id)
      assert_equal 1, @adapter.discovery_skips(dir).skipped_by_rule
    end
  end

  def test_discover_ignores_framesets_and_index_frames
    Dir.mktmpdir do |dir|
      %w[baktc.htm baktcx1.htm baktcxx.htm baktc001.htm].each { |name| File.write(File.join(dir, name), "") }
      assert_equal ["urn:nabu:titus-bactrian:baktc001"], @adapter.discover(dir).map(&:id)
    end
  end

  # --- real pages --------------------------------------------------------------

  def test_line_counts_per_page
    counts = documents_by_page.transform_values { |document| document.passages.size }
    assert_equal({ "baktc001" => 36, "baktc002" => 9, "baktc030" => 188, "baktc046" => 40, "baktc047" => 37,
                   "baktc122" => 20, "baktc123" => 17 }, counts)
  end

  def test_dated_document_a_opens_with_the_era_formula
    line = passage("urn:nabu:titus-bactrian:baktc001:A.1")
    assert_equal "χϸονο ρʹ ιʹ Αυρηζνο μα̅ο̅ ̅σ̅α̅χ̅το Αβαμοχοινο ρωσο καλ̣δο νοβιχτο μο ολοβω-", line.text,
                 "footnote markers never leak; the broken word's first half ends the line"
    assert_equal({ "genre" => "Dat.Doc.", "line" => "1", "text" => "A", "line_end_word" => "ολοβωστογο" },
                 line.annotations)
    assert passage("urn:nabu:titus-bactrian:baktc001:A.2").text.start_with?("στογο μαλο αβο"),
           "the broken word's second half opens the next line"
  end

  def test_document_metadata_mines_genre_header_and_era_date
    metadata = documents_by_page.fetch("baktc001").metadata
    assert_equal ["A"], metadata["texts"]
    assert_equal "Dat.Doc.", metadata["genre"]
    assert_equal "Dated documents", metadata["genre_name"]
    assert_equal({ "genre" => { "value" => "Dated documents" } }, metadata["facets"])
    assert_equal "Corpus of Bactrian Texts", metadata["page_title"]
    assert_match(/Nicholas Sims-Williams/, metadata["data_entry"])
    assert_match(/Bactrian Documents from Northern Afghanistan/, metadata["bibliography"])
    assert_equal [{ "text" => "A", "formula" => "χϸονο ρʹ ιʹ", "era_year" => 110, "uncertain" => false }],
                 metadata["era_dates"]
    assert_equal "Bactrian — A (baktc001)", documents_by_page.fetch("baktc001").title
  end

  def test_the_intro_conventions_and_notes_mint_nothing
    document = documents_by_page.fetch("baktc001")
    assert_equal (1..36).map { |n| "urn:nabu:titus-bactrian:baktc001:A.#{n}" }, document.passages.map(&:urn),
                 "the intro's quoted forms (gbbkx12) and the na–ne note sections are apparatus"
    assert_equal "].....αν̣ολα̣..[", document.passages.last.text,
                 "the 'At the bottom of the page' caption is not text"
  end

  def test_double_document_keeps_the_italic_second_copy_and_its_labels
    document = documents_by_page.fetch("baktc002")
    assert_equal(%w[Aa.1 Aa.2 Aa.1' Aa.2' Aa.(2) Aa.3 Aa.4 Aa.(4) Aa.5],
                 document.passages.map { |p| p.urn.split(":").last })
    second = passage("urn:nabu:titus-bactrian:baktc002:Aa.1'")
    assert_equal "second", second.annotations["copy"]
    assert_equal "[. . . δ]η̣[μα]τρ[ι]\\[γανο", second.text
    assert_nil passage("urn:nabu:titus-bactrian:baktc002:Aa.1").annotations["copy"]
    assert_equal [{ "text" => "Aa", "formula" => "[χ]ϸονο ρʹ λ̣ʹ δʹ", "era_year" => 134, "uncertain" => true }],
                 document.metadata["era_dates"]
  end

  def test_tally_list_labels_ride_verbatim_and_traces_only_lines_mint_nothing
    tails = documents_by_page.fetch("baktc046").passages.map { |p| p.urn.split(":").last }
    assert_includes tails, "am.5+6A"
    assert_includes tails, "am.30+37"
    refute_includes tails, "am.5+6B", "a line carrying only the editorial 'traces only' is not text"
    assert_nil documents_by_page.fetch("baktc046").metadata["era_dates"], "lists carry no era formula"
    assert_equal "Lists and accounts", documents_by_page.fetch("baktc046").metadata["genre_name"]
  end

  def test_headerless_lines_mint_honestly_without_a_text_siglum
    document = documents_by_page.fetch("baktc047")
    first = passage("urn:nabu:titus-bactrian:baktc047:1")
    assert first.text.start_with?("Ασ̣ο̣ δοχτ̣[οα]ν̣ωϸο"), first.text
    assert_nil first.annotations["text"], "no text siglum is guessed"
    assert_equal 22, document.metadata["unheaded_lines"]
    assert_equal ["bb"], document.metadata["texts"]
    assert_equal "Bactrian — untitled lines, bb (baktc047)", document.title
    assert_equal "urn:nabu:titus-bactrian:baktc047:bb.15", document.passages.last.urn
  end

  def test_buddhist_text_line_end_word_carries_the_illegible_letter_sign
    line = passage("urn:nabu:titus-bactrian:baktc122:za.1")
    assert_equal "ναμωο σαρβοβοδδανο̣[ κι]δο τριϸτ[•]-", line.text
    assert_equal "τριϸτ#νδαγινδο", line.annotations["line_end_word"]
    assert_equal "Buddhist texts", documents_by_page.fetch("baktc122").metadata["genre_name"]
  end

  def test_a_label_less_line_header_continues_the_open_line
    # baktc030 (W), line (23): `<!Level 4>Line: ` with the TEXT's own anchor
    # (Bactr.Corp._Dat.Doc._W) nested inside the line's span, before its "--".
    urns = documents_by_page.fetch("baktc030").passages.map(&:urn)
    refute_includes urns, "urn:nabu:titus-bactrian:baktc030:W", "the label-less header opens no line"
    dash = documents_by_page.fetch("baktc030").passages.find { |p| p.text == "--" } || flunk("no '--' line")
    assert_equal "(23)", dash.annotations["line"]
    assert_equal "W", dash.annotations["text"]
  end

  def test_text_level_content_before_the_first_line_mints_under_the_text_anchor
    # baktc123 (zb): the page numeral "αʹ" ("Top left hand corner of the
    # page", note na) sits under the Level-3 anchor, before line 1.
    document = documents_by_page.fetch("baktc123")
    first = document.passages.first
    assert_equal "urn:nabu:titus-bactrian:baktc123:zb", first.urn
    assert_equal "αʹ", first.text
    assert_equal({ "genre" => "Buddh.T.", "text" => "zb" }, first.annotations, "no line label is invented")
    assert_equal "urn:nabu:titus-bactrian:baktc123:zb.1", document.passages[1].urn
    assert_equal ["zb"], document.metadata["texts"]
  end

  # --- lane families (synthetic, runs in CI) -----------------------------------

  def line_page(body)
    <<~HTML
      <html><body>
      <span id=h3><!Level 3>Text: Z<A NAME="Bactr.Corp._Lett._Z">&nbsp;</A></sPAN>
      <span id=h4><!Level 4>Line: 1<A NAME="Bactr.Corp._Lett._Z_1">&nbsp;</A></sPAN>
      #{body}
      </body></html>
    HTML
  end

  def test_lanes_classify_by_family_at_any_size
    html = line_page(<<~BODY)
      <span id=gbbk22>αβο</span> <span id=gbbkix16>μο</span>
      <span id=nc12>Or </span><span id=gbbkx12>ϸκαμινο</span><span id=nc12>, etc.</span>
      <span id=gbbkv16>λαδι-</span>
    BODY
    line = only(PARSER.parse(html))
    assert_equal "αβο μο", line.content, "any size / flavor combination of x and i is text; v and note quotes are not"
    assert_equal "second", line.copy
  end

  def test_an_unknown_bactrian_lane_quarantines_the_page
    error = assert_raises(Nabu::ParseError) { PARSER.parse(line_page("<span id=gbbkq16>αβο</span>")) }
    assert_match(/unknown content lane "gbbkq16"/, error.message)
    assert_raises(Nabu::ParseError) { PARSER.parse(line_page("<span id=gbbk>αβο</span>")) }
  end

  def test_a_small_run_outside_any_note_quarantines_the_page
    error = assert_raises(Nabu::ParseError) { PARSER.parse(line_page("<span id=gbbk12>αβο</span>")) }
    assert_match(/outside any editorial note/, error.message)
  end

  def test_lane_text_outside_any_text_quarantines_the_page
    # Before any header, or after a genre (Level 2) header: no anchor to
    # mint under. (Text-level content under a Level-3 anchor is baktc123's
    # real shape — it mints; see above.)
    assert_raises(Nabu::ParseError) { PARSER.parse("<html><body><span id=gbbk16>stray</span></body></html>") }
    html = <<~HTML
      <html><body><span id=h2><!Level 2>Genre: Lett.<A NAME="Bactr.Corp._Lett.">&nbsp;</A></sPAN>
      <span id=gbbk16>stray</span></body></html>
    HTML
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/outside any Line/, error.message)
  end

  def test_text_level_content_opens_a_line_less_section
    html = <<~HTML
      <html><body><span id=h3><!Level 3>Text: Z<A NAME="Bactr.Corp._Lett._Z">&nbsp;</A></sPAN>
      <span id=gbbk16>αʹ</span>
      <span id=h4><!Level 4>Line: 1<A NAME="Bactr.Corp._Lett._Z_1">&nbsp;</A></sPAN>
      <span id=gbbk16>αβο</span></body></html>
    HTML
    lines = PARSER.parse(html)
    assert_equal([["Z", "", "αʹ"], ["Z", "1", "αβο"]], lines.map { |l| [l.text, l.line, l.content] })
  end

  def test_a_label_less_header_naming_the_open_text_continues_its_line
    html = line_page(<<~BODY)
      <span id=gbbk16>αβο<span id=h4><!Level 4>Line: <A NAME="Bactr.Corp._Lett._Z">&nbsp;</A></sPAN></span>
      <span id=gbbk16>--</span>
    BODY
    assert_equal "αβο --", only(PARSER.parse(html)).content
  end

  def test_a_label_less_header_naming_another_text_quarantines_the_page
    html = line_page(<<~BODY)
      <span id=gbbk16>αβο</span><span id=h4><!Level 4>Line: <A NAME="Bactr.Corp._Lett._Y">&nbsp;</A></sPAN>
    BODY
    error = assert_raises(Nabu::ParseError) { PARSER.parse(html) }
    assert_match(/unexpected line anchor "Bactr.Corp._Lett._Y"/, error.message)
  end

  def test_a_foreign_line_anchor_quarantines_the_page
    html = <<~HTML
      <html><body><span id=h4><!Level 4>Line: 1<A NAME="Other_Lett._Z_1">&nbsp;</A></sPAN>
      <span id=gbbk16>αβο</span></body></html>
    HTML
    assert_raises(Nabu::ParseError) { PARSER.parse(html) }
  end

  def test_a_repeated_line_label_keys_by_occurrence
    html = line_page(<<~BODY)
      <span id=gbbk16>αβο</span>
      <span id=h4><!Level 4>Line: 1<A NAME="Bactr.Corp._Lett._Z_1">&nbsp;</A></sPAN>
      <span id=gbbk16>μο</span>
    BODY
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "baktc999.htm"), html)
      document = @adapter.parse(only(@adapter.discover(dir)))
      assert_equal(%w[Z.1 Z.1#2], document.passages.map { |p| p.urn.split(":").last })
      assert_equal 2, document.passages.last.annotations["occurrence"]
    end
  end

  def test_a_severed_utf8_page_is_read_through_the_pahlavi_repair
    # The titus-pahlavi first-sync incident shape: a multibyte sequence cut by
    # a tag. The adapter reads through TitusPahlaviParser.read_page.
    bytes = line_page("<span id=gbbk16>αβSEVERED</span>").b.sub("SEVERED".b, "\xCF</a>\x89".b + "ο".b)
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "baktc998.htm"), bytes)
      document = @adapter.parse(only(@adapter.discover(dir)))
      assert_equal "αβωο", only(document.passages).text
    end
  end

  # --- fetch: one polite TitusFetch walk (WebMock) -----------------------------

  def test_fetch_walks_the_next_part_chain
    base = "https://titus.uni-frankfurt.de/texte/etcs/iran/miran/baktr/baktcorp"
    stub_request(:get, "#{base}/baktc.htm")
      .to_return(body: '<frameset><frame src="baktc001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{base}/baktc001.htm").to_return(body: <<~HTML)
      #{line_page('<span id=gbbk16>αβο</span>')}
      <A HREF="/texte/etcs/iran/miran/baktr/baktcorp/baktc002.htm"><img src="/arribar.gif" alt="Next part"></A>
    HTML
    stub_request(:get, "#{base}/baktc002.htm").to_return(body: line_page("<span id=gbbk16>μο</span>"))
    adapter = ADAPTER.new(delay: 0)
    Dir.mktmpdir do |dir|
      report = adapter.fetch(dir)
      assert_equal %w[baktc001.htm baktc002.htm], Dir.children(dir).grep(/\.htm\z/).sort
      assert File.file?(File.join(dir, Nabu::TitusFetch::STATE_FILE))
      assert_match(/\A\h{64}\z/, report.sha)
      assert_equal 2, adapter.discover(dir).count
    end
  end

  # --- registry round-trip (runs in CI) --------------------------------------

  def test_registry_row_is_grant_gated_blocked_and_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "titus-bactrian must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired flips only after the owner-fired first retrieval is verified"
    assert_equal "manual", entry.sync_policy
    assert_predicate entry, :grant_required?
    assert_predicate entry, :blocked?
    assert_equal "2026-10-06", entry.grant.date
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/one retrieval/i, entry.grant.terms)
    assert_match(/no redistribution/i, entry.grant.terms)
    assert_match(/titus-bactrian: fetch requires a GRANT/, Nabu::GrantGate.notice(entry))
    assert_includes entry.axes, "iranian"
    assert_equal ADAPTER.manifest, entry.manifest
  end

  private

  def only(list)
    assert_equal 1, list.size, "expected exactly one, got #{list.size}"
    list.first
  end

  def require_fixtures!
    return if Nabu::TestSupport.local_fixtures?(SLUG)

    skip "#{SLUG} local fixtures absent (personal grant forbids redistribution — " \
         "bytes live in local/fixtures/, never in git)"
  end
end
