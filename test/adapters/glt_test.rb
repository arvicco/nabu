# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Glt: glt.goarch.org, the Greek Orthodox Archdiocese of
# America's Greek liturgical texts — one document per service page, one
# passage per page LINE (hymn, petition, prayer, verse, or rubric), the
# rubric distinction mined from the site's ink (GltHtmlParser).
#
# Fixtures (test/fixtures/glt/, README there; retrieved 2026-11-04):
# index.html + extra.htm WHOLE (the catalog — the crawl list), the
# Menaion page texts/Sep/Sep05.html WHOLE (the soup markup, melody
# recordings, tone rubrics), texts/Euch/Baptism.html trimmed (the
# Euchologion's blue/green/bold inks and inline rubric alternates),
# texts/Sep/14b.html trimmed (the LibreOffice-export variant); the rejected
# grains daily/Mon.html and misc/Prosomia.html, trimmed specimens.
class GltTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("glt")
  Glt = Nabu::Adapters::Glt

  def conformance_adapter = Glt.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "glt"

  def adapter = Glt.new

  def doc(urn)
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id == urn } or flunk("no ref #{urn}")
    adapter.parse(ref)
  end

  def passage(document, number)
    document.passages.find { |candidate| candidate.urn == "#{document.urn}:#{number}" } or
      flunk("no passage #{number} in #{document.urn}")
  end

  def sep05 = doc("urn:nabu:glt:sep.sep05")
  def baptism = doc("urn:nabu:glt:euch.baptism")

  # --- manifest ------------------------------------------------------------------

  def test_manifest_is_open_on_the_maintainers_own_grant
    manifest = Glt.manifest
    assert_equal "glt", manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "glt-html", manifest.parser_family
    assert_equal "https://glt.goarch.org/", manifest.upstream_url
    assert_match(/permission by email from the site maintainer \(Fr\. Leo Schefe\), 2026-11-02/, manifest.license)
    assert_match(/public domain/, manifest.license)
    assert_match(/"you are welcome to use them"/, manifest.license)
    assert_match(/glt\.goarch\.org/, manifest.credit)
  end

  # --- discovery and its accounting ---------------------------------------------------

  def test_discover_yields_the_three_service_pages
    assert_equal %w[urn:nabu:glt:euch.baptism urn:nabu:glt:sep.14b urn:nabu:glt:sep.sep05],
                 adapter.discover(FIXTURES).map(&:id)
  end

  def test_every_rejected_grain_skips_by_rule_and_nothing_is_unrecognized
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 4, skips.skipped_by_rule, "index.html + extra.htm + daily/Mon.html + misc/Prosomia.html"
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(/2 skipped by rule — the catalog pages/, notes)
    assert_match(/1 skipped by rule — the weekly-compiled daily services/, notes)
    assert_match(%r{1 skipped by rule — the misc/ shelf}, notes)
  end

  def test_non_html_renderings_skip_by_rule_and_an_unknown_shelf_is_unrecognized
    Dir.mktmpdir("glt-skips") do |work|
      FileUtils.cp_r(File.join(FIXTURES, "."), work)
      File.write(File.join(work, "texts", "Euch", "Funeral.rtf"), "{\\rtf1}")
      FileUtils.mkdir_p(File.join(work, "texts", "Foo"))
      FileUtils.cp(File.join(work, "texts", "Sep", "Sep05.html"), File.join(work, "texts", "Foo", "x.html"))

      skips = adapter.discovery_skips(work)
      assert_equal 5, skips.skipped_by_rule
      assert_equal 1, skips.unrecognized, "a shelf the census never saw is a defect to review, never a document"
      assert_includes skips.notes, "unrecognized file: texts/Foo/x.html"
      refute_includes adapter.discover(work).map(&:id), "urn:nabu:glt:foo.x"
    end
  end

  def test_urns_lowercase_the_shelf_and_page_and_dash_spaces
    assert_equal "urn:nabu:glt:oro.esperinos-sunday", Glt.urn_for("texts/Oro/Esperinos Sunday.html")
    assert_equal "urn:nabu:glt:oct.oct11_17", Glt.urn_for("texts/Oct/Oct11_17.html")
  end

  # --- documents ------------------------------------------------------------------------

  def test_a_menaion_page_carries_its_index_labels_and_commemoration
    document = sep05
    assert_equal "grc", document.language
    assert_equal "Μηναῖον — Σεπτέμβριος — 05", document.title
    assert_equal "Menaion", document.metadata["book"]
    assert_equal "texts/Sep/Sep05.html", document.metadata["page"]
    assert_equal "https://glt.goarch.org/texts/Sep/Sep05.html", document.metadata["url"]
    assert_equal "Sep 05", document.metadata["page_title"]
    assert_equal({ "list" => "index.html", "group" => "Σεπτέμβριος", "label" => "05" }, document.metadata["index"])
    assert_equal({ "month" => 9, "day" => 5 }, document.metadata["commemoration"])
  end

  def test_the_index_label_names_a_page_the_name_does_not
    document = doc("urn:nabu:glt:sep.14b")
    assert_equal "Μηναῖον — Σεπτέμβριος — Ακάθιστος", document.title,
                 "index.html files 14b under Σεπτέμβριος as the Akathist (first occurrence beats extra.htm's 14β)"
    assert_equal({ "month" => 9, "day" => 14 }, document.metadata["commemoration"])
  end

  def test_a_euchologion_page_has_no_commemoration
    document = baptism
    assert_equal "Εὐχολόγιον — Βάπτιση", document.title
    assert_equal "Euchologion", document.metadata["book"]
    refute document.metadata.key?("commemoration")
  end

  def test_a_tone_cycle_page_states_its_tone_and_weekday
    Dir.mktmpdir("glt-tone") do |work|
      FileUtils.mkdir_p(File.join(work, "texts", "Och"))
      FileUtils.cp(File.join(FIXTURES, "texts", "Sep", "Sep05.html"), File.join(work, "texts", "Och", "Tone7Sun.html"))
      document = adapter.parse(adapter.discover(work).first)
      assert_equal "urn:nabu:glt:och.tone7sun", document.urn
      assert_equal "Octoechos", document.metadata["book"]
      assert_equal 7, document.metadata["tone"]
      assert_equal "Sun", document.metadata["weekday"]
      assert_equal "Ὀκτώηχος — Sep 05", document.title, "no index on disk: the page <title> stands in"
    end
  end

  # --- passages: the line, its role, its mined layers ------------------------------------

  def test_passage_counts_per_page
    assert_equal 171, sep05.size
    assert_equal 45, baptism.size
    assert_equal 15, doc("urn:nabu:glt:sep.14b").size
  end

  def test_a_melody_rubric_drops_the_listen_link_and_keeps_the_recording
    melody = passage(sep05, 7)
    assert_equal "Ἔδωκας σημείωσιν", melody.text
    assert_equal "rubric", melody.annotations["role"]
    assert_equal ["music/4018.mp3"], melody.annotations["recordings"]
    refute(sep05.passages.any? { |p| p.text.include?("ΤΟ ΑΚΟΥΤΕ") }, "the mp3 link text is site chrome")
  end

  def test_a_hymn_is_text_with_its_tone_and_section
    hymn = passage(sep05, 8)
    assert hymn.text.start_with?("Χρῖσμα περικείμενος, στολήν τε θείαν ἀοίδιμε, Ζαχαρία ὡς ἄγγελος")
    assert_equal({ "role" => "text", "tone" => 4, "section" => "ΕΝ Τῼ ΕΣΠΕΡΙΝῼ" }, hymn.annotations)
  end

  def test_tones_fold_to_the_eight_modes_and_a_heading_clears_them
    assert_equal 8, passage(sep05, 14).annotations["tone"], "Ἦχος πλ. δ' is the eighth"
    assert_equal 2, passage(sep05, 36).annotations["tone"], "Ἦχος β'"
    assert_equal 3, passage(sep05, 112).annotations["tone"], "the kontakion's Ἦχος γ'"
    orthros = passage(sep05, 49)
    assert_equal "ΕΙΣ ΤΟΝ ΟΡΘΡΟΝ", orthros.text
    assert_equal({ "role" => "rubric", "section" => "ΕΙΣ ΤΟΝ ΟΡΘΡΟΝ" }, orthros.annotations,
                 "a section heading clears the tone in force")
    assert_nil passage(sep05, 51).annotations["tone"], "the acrostic precedes the canon's tone rubric"
  end

  def test_a_mixed_line_keeps_its_inline_rubrics_verbatim_and_lists_them
    verse = passage(sep05, 29)
    assert_equal "Στίχ. Εὐλογητὸς Κύριος ὁ Θεὸς τοῦ Ἰσραήλ, ὁ ποιῶν θαυμάσια μόνος.", verse.text
    assert_equal "mixed", verse.annotations["role"]
    assert_equal ["Στίχ."], verse.annotations["rubrics"]
  end

  def test_the_euchologion_inks_ride_annotations
    assert_equal({ "role" => "text", "ink" => "blue", "section" => "ΤΑΞΙΣ ΓΙΝΟΜΕΝΗ ΠΡΟ ΤΟΥ ΑΓΙΟΥ ΒΑΠΤΙΣΜΑΤΟΣ" },
                 passage(baptism, 7).annotations, "the deacon's petition")
    assert_equal "Τοῦ Κυρίου δεηθῶμεν.", passage(baptism, 7).text
    response = passage(baptism, 26)
    assert_equal "Ἀποτάσσομαι.", response.text
    assert_equal "green", response.annotations["ink"], "the people's response"
    alternates = passage(baptism, 8)
    assert_equal "mixed", alternates.annotations["role"]
    assert_equal ["(τὴν δούλην)", "(τόνδε)", "(τήνδε)"], alternates.annotations["rubrics"].first(3)
    assert_includes alternates.text, "ἐπὶ τὸν δοῦλον (τὴν δούλην) σου (τόνδε) (τήνδε)"
    assert_equal "ΑΦΟΡΚΙΣΜΟΣ Α'", passage(baptism, 10).annotations["section"]
  end

  def test_a_bold_line_is_flagged
    assert_equal({ "role" => "text", "bold" => true }, passage(sep05, 1).annotations)
    assert_equal "Τῌ Ε' ΤΟΥ ΑΥΤΟΥ ΜΗΝΟΣ ΣΕΠΤΕΜΒΡΙΟΥ", passage(sep05, 1).text
  end

  def test_the_libreoffice_variant_joins_its_word_runs_into_lines
    document = doc("urn:nabu:glt:sep.14b")
    kontakion = passage(document, 4)
    assert_equal "Κοντάκιον. Ἦχος πλ. δ´. Τῇ ὑπερμάχῳ.", kontakion.text
    assert_equal 8, kontakion.annotations["tone"]
    assert_equal "Χαῖρε Σταυρέ, οἰκουμένης φύλαξ·", passage(document, 8).text
    assert_equal ["(ἐκ γ´)"], passage(document, 7).annotations["rubrics"]
  end

  # The site keys polytonic Greek with the Greek Extended OXIA vowels
  # (U+1F77 GREEK SMALL LETTER IOTA WITH OXIA in the fixture's own bytes) and
  # ANO TELEIA; NFC folds them canonically to the tonos vowels and U+00B7.
  def test_oxia_and_ano_teleia_fold_to_nfc_at_the_boundary
    raw = File.binread(File.join(FIXTURES, "texts", "Sep", "Sep05.html")).force_encoding(Encoding::UTF_8)
    assert_includes raw, "ἀοίδιμε", "upstream bytes carry the oxia code point"
    assert_includes raw, "·", "upstream bytes carry ANO TELEIA"
    text = passage(sep05, 8).text
    assert_includes text, "ἀοίδιμε"
    refute_match(/[άέήίόύώ·]/, sep05.passages.map(&:text).join)
    assert(sep05.passages.any? { |p| p.text.include?("·") }, "ano teleia → middle dot")
  end

  # --- the crawl list (the fetch's catalog walk, on the real index pages) -----------------

  def catalog = Nabu::GltFetch::CATALOG_PAGES.to_h { |name| [name, File.read(File.join(FIXTURES, name))] }

  def test_the_crawl_list_is_the_725_service_pages_of_both_indexes
    listed = Nabu::GltFetch.crawl_list(catalog)
    assert_equal 725, listed.size
    shelves = listed.map { |page| page.rel.split("/")[1] }.tally
    assert_equal({ "Sep" => 41, "Oct" => 40, "Nov" => 36, "Dec" => 58, "Jan" => 44, "Feb" => 40, "Mar" => 33,
                   "Apr" => 30, "May" => 35, "Jun" => 32, "Jul" => 34, "Aug" => 35, "Synek" => 3, "Och" => 81,
                   "Tri" => 70, "Pen" => 60, "Oro" => 47, "Euch" => 6 }, shelves)
    rels = listed.map(&:rel)
    refute(rels.any? { |rel| rel.match?(%r{\A(daily|Lite|Athos|AthosJ|misc)/}) }, "the compiled and misc grains")
    refute(rels.any? { |rel| rel.match?(/\.(epub|pdf|rtf)\z/) }, "the non-HTML renderings")
    sunday = listed.find { |page| page.rel == "texts/Oro/Esperinos Sunday.html" }
    assert_equal "texts/Oro/Esperinos%20Sunday.html", sunday.href, "the request keeps upstream's escaping"
    assert_includes rels, "texts/Sep/01b.html", "extra.htm's ./-relative links join the list"
    assert_equal rels.size, rels.uniq.size
  end

  def test_every_crawled_shelf_is_a_known_book
    Nabu::GltFetch.crawl_list(catalog).each do |page|
      assert Glt::BOOKS.key?(page.rel.split("/")[1]), "#{page.rel}: a crawled shelf the adapter does not know"
    end
  end

  # --- store: idempotent double-load -------------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "glt", name: "GLT", adapter_class: Glt.name, license_class: "open")
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 171 + 45 + 15, db[:passages].count
    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped
    assert_equal 171 + 45 + 15, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  # --- fetch (WebMock: no network) ----------------------------------------------------------

  def test_fetch_wraps_crawl_failures_as_fetch_errors
    stub_request(:get, "https://glt.goarch.org/index.html").to_return(status: 404)
    Dir.mktmpdir("glt-fetch") do |work|
      fast = adapter.tap { |instance| instance.define_singleton_method(:fetch_delay) { 0 } }
      error = assert_raises(Nabu::FetchError) { fast.fetch(work) }
      assert_match(/glt fetch failed.*index\.html is missing/, error.message)
    end
  end
end
