# frozen_string_literal: true

require "test_helper"

module Adapters
  # The grand-tour-tei family over trimmed real journals of the HAB's
  # Grand Tour digital deposit (test/fixtures/grand-tour/README.md): the
  # transcription/regularized layers, the apparatus kept aside, and the
  # register joins.
  class GrandTourTeiParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("grand-tour")
    P = Nabu::Adapters::GrandTourTeiParser

    def register
      @register ||= P::Register.new(
        places: P.load_register(File.join(FIXTURES, "register", "listPlace_grand_tour.xml"), entry: "place"),
        persons: P.load_register(File.join(FIXTURES, "register", "listPerson_grand_tour.xml"), entry: "person"),
        orgs: P.load_register(File.join(FIXTURES, "register", "listOrg_grand_tour.xml"), entry: "org")
      )
    end

    def parse(stem) = P.new(register: register).parse(File.join(FIXTURES, "Reiseberichte", "#{stem}.xml"))

    def test_lines_follow_lb_and_the_w_lemma_joins_only_the_regularized_layer
      page = parse("cod_guelf_89_blank").pages.first
      assert_includes page.text, "wir d. 12. hujus. aldar an. Wir Lo-\ngierten bey einem Kaufmann"
      assert_includes page.regularized, "Wir Logierten bey einem Kaufmann"
    end

    def test_deletions_leave_the_text_and_additions_stay_in_it
      page = parse("cod_guelf_89_blank").pages.first
      assert_includes page.text, "reyse so von hier", "the struck 'bet' is gone"
      assert_includes page.deletions, "bet"
      assert_includes page.text, "6. Personen als wie folget", "<add place='above'>als</add> reads inline"
      assert_includes page.text, "Nachdeme wir nun", "<subst><del>D</del><add>N</add></subst> → N"
    end

    def test_choice_keeps_the_transcription_and_regularizes_beside
      page = parse("cod_guelf_89_blank").pages[2]
      assert_includes page.text, "D. 25. hegten wir ab"
      assert_includes page.regularized, "D. 25. legten wir ab"
    end

    def test_the_editors_notes_and_the_writers_marginalia_ride_aside
      pages = parse("cod_guelf_89_blank").pages
      assert_equal [{ "type" => "annotation", "text" => "\"D\" durch Überschreiben zu \"N\" verbessert." }],
                   pages.first.editorial_notes
      refute_includes pages.first.text, "Überschreiben"
      assert_includes pages.last.marginalia, { "place" => "margin-left", "text" => "Febr." }
    end

    def test_the_apparatus_keeps_the_lemma_and_sets_the_readings_aside
      page = parse("cod_guelf_149_14_extrav").pages.first
      assert page.text.start_with?("Heinrich Ferdinand u. Ernst\nHerz. Zu Braunschw. u. Luneb.")
      refute_includes page.text, "Jtineraire", "the French copy's reading is not the text"
      assert_equal %w[h1 h2 h3], page.variants.map { |v| v["wit"] }.uniq.first(3)
      french = page.variants.find { |v| v["wit"] == "h3" }
      assert_includes french["text"], "Jtineraire De Leurs Altesses Serenissimes"
    end

    def test_pages_are_cut_at_pb_and_empty_leaves_are_counted
      result = parse("cod_guelf_221_extrav")
      assert_equal 4, result.pages.size
      assert_equal 6, result.blank_pages
      assert_equal "#mss_221-extrav_00007", result.pages.first.facs
      assert_equal %w[90r 90v 91r 91v], parse("cod_guelf_89_blank").pages.map(&:n)
    end

    def test_rs_resolves_through_the_register
      places = parse("cod_guelf_89_blank").pages.first.places
      assert_equal({ "value" => "Dänemark, Königreich", "ref" => "https://d-nb.info/gnd/4010877-6",
                     "id" => "daenemark_koenigreich" }, places.first)
      assert(places.any? { |p| p["ref"] == "https://www.geonames.org/2945024/braunschweig.html" })
      persons = parse("cod_guelf_89_blank").pages.first.persons
      assert_equal "http://d-nb.info/gnd/131463896", persons.first["ref"]
    end

    def test_an_unlinked_or_unknown_ref_keeps_its_surface_unresolved
      places = parse("cod_guelf_221_extrav").pages[2].places
      assert_includes places, { "value" => "Homburg", "unresolved" => true }, "#homburg is not in the register"
      assert_includes places, { "value" => "Wisnhusen", "unresolved" => true }, "an empty # ref"
      assert_includes places, { "value" => "Darmstadt", "ref" => "https://www.geonames.org/2938913/darmstadt.html",
                                "id" => "darmstadt" }
    end

    def test_dates_are_collected_per_page
      pages = parse("cod_guelf_89_blank").pages
      assert_equal %w[1689 1689-01-09 1689-01-12 1689-01-15 1689-01-16 1689-01-19], pages.first.dates
    end

    def test_the_header
      header = parse("cod_guelf_221_extrav").header
      assert_equal "Cod. Guelf. 221 Extrav.", header.shelfmark
      assert_equal "Christian August von Schleswig-Holstein-Norburg: Reisetagebuch (Cod. Guelf. 221 Extrav.)",
                   header.title
      assert_equal 3, header.statements.size
      assert_equal "Christian August von Schleswig-Holstein-Norburg (1639–1687)", header.publication_note
    end

    def test_a_register_reads_display_names
      persons = P.load_register(File.join(FIXTURES, "register", "listPerson_grand_tour.xml"), entry: "person")
      assert_equal "Imhoff, Rudolph Christian von", persons.dig("imhoff_rudolph_christian", "value")
      assert_equal({}, P.load_register(File.join(FIXTURES, "register", "absent.xml"), entry: "person"))
    end

    def test_a_malformed_journal_quarantines
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.xml")
        File.write(path, "<TEI><text><body><p>offen</body></TEI>")
        assert_raises(Nabu::ParseError) { P.new.parse(path) }
      end
    end
  end
end
