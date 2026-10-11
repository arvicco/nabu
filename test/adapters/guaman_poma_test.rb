# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # guaman-poma — the Royal Danish Library's Guaman Poma edition (P117-5):
  # document = one crawled XHTML page, passage = one transcription
  # paragraph (the poma-xhtml family). Fixture: four real pages, whole —
  # the title page (drawing 1, "[portada]"), p. 5 (gloss line, the Andean
  # terms line, commentary), p. 319 (the songs: Quechua and Aymara, the
  # editors' paragraph translations, the normalized songs line), p. 1189
  # (drawing 398, Guaman Poma's "s.n.").
  class GuamanPomaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("guaman-poma")
    URN = "urn:nabu:guaman-poma"

    def conformance_adapter = Nabu::Adapters::GuamanPoma.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "guaman-poma"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    def test_discovers_one_document_per_page_in_page_order
      assert_equal %w[titlepage 5 319 1189].map { |id| "#{URN}:#{id}" },
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_every_passage_is_spanish_declared_coarse
      assert(documents.all? { |d| d.language == "spa" && d.passages.all? { |p| p.language == "spa" } })
    end

    def test_the_title_page_carries_its_drawing_and_pagination
      d = doc("titlepage")
      assert_equal "Nueva corónica y buen gobierno, p. 0", d.title
      assert_equal({ "number" => 1, "caption" => "Guaman Poma, \"el autor Ayala\", de rodillas al lado del rey " \
                                                 "de España, ante el Papa de la Iglesia Romana" },
                   d.metadata["drawing"])
      assert_equal "[portada]", d.metadata["textdesc"]
      assert_equal %w[0 0], d.metadata.values_at("page", "gp_page")
      assert_equal "http://img.kb.dk/ha/manus/POMA/poma550/POMA0000.jpg", d.metadata["image"]
      assert d.passages.first.text.start_with?("EL PRIMER NVEVA CORÓNICA I BVEN GOBIERNO CONPVESTO POR DON " \
                                               "PHELIPE GVAMAN POMA DE AIALA, S[EÑ]OR I PRÍ[N]CIPE"),
             "note markers out, in-word editorial brackets kept"
      assert_equal ["1"], d.passages.first.annotations["notes"]
      assert_equal(%w[1 2], d.metadata["commentary"].map { |c| c["n"] })
    end

    def test_a_page_records_its_gloss_line_andean_terms_and_section
      d = doc("5")
      assert_equal "Nueva corónica y buen gobierno, p. 5 — Carta del padre del autor al rey, pág. 5", d.title
      assert_equal ["qhapaq apu", "qhapaq"], d.metadata["andean_terms"]
      assert_equal ["a señor poderoso | b poderoso"], d.metadata["glosses"]
      assert_equal ["#{URN}:5:1", "#{URN}:5:2", "#{URN}:5:3"], d.passages.map(&:urn)
      assert_equal "CARTA DEL [→]", d.passages.first.text
      assert_includes d.passages[1].annotations["italic"], "Guaman Mallque"
    end

    def test_editorial_insertions_leave_the_text_and_ride_as_annotations
      opening = doc("319").passages[1]
      assert opening.text.start_with?("Canciones y múcicas del Ynga y de los demás señores deste rreyno y de " \
                                      "los yndios llamado haraui y uanca, pingollo, quena quena en la lengua")
      assert opening.annotations["edition_text"].start_with?(
        "Canciones y múcicas del Ynga y de los demás señores deste rreyno y de los yndios llamado haraui " \
        "[canción de amor] y uanca [canción], pingollo [flauta]"
      )
      assert_includes opening.annotations["editorial"], { "type" => "trans", "text" => "[canción de amor]" }
    end

    def test_a_paragraph_long_translation_attaches_to_the_song_it_renders
      song = doc("319").passages[2]
      assert song.text.start_with?("Haray haraui Acoyraquicho Coya raquiriuanchic?")
      assert song.annotations["translation"].start_with?("[Cantar de amores ¿Es el infortunio, reina, que nos separa?")
      assert_includes song.annotations["italic"].first, "Haray haraui"
    end

    def test_the_normalized_songs_line_is_metadata_not_text
      d = doc("319")
      assert_equal %w[arawi wanka pinqullu], d.metadata["andean_terms"].first(3)
      assert d.metadata["andean_terms"][3].start_with?("Haray harawi, aquyrakichu quya rakiriwanchik?")
      refute(d.passages.any? { |p| p.text.include?("aquyrakichu") })
      assert_equal 7, d.passages.size
    end

    def test_an_unnumbered_page_says_s_n
      d = doc("1189")
      assert_equal "s.n.", d.metadata["gp_page"]
      assert_equal "1189", d.metadata["page"]
      assert_equal 398, d.metadata.dig("drawing", "number")
      assert_equal "CORONA REAL, EGO FVLCIO CVLLVMNAS EIVS.", d.passages.first.text,
                   "the gap left by the excised note marker and translation closes before the period"
    end

    def test_the_autographs_date_rides_the_structured_lane
      assert_equal 1615, doc("5").metadata.dig("date", "not_before")
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["guaman-poma"]
    end

    def test_manifest_records_the_kb_declaration_verbatim
      manifest = Nabu::Adapters::GuamanPoma.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "Esta obra ha sido identificada como libre de restricciones conocidas"
      assert_includes manifest.license, "publicdomain/mark/1.0"
      assert_includes doc("5").metadata["edition"], "Murra, Rolena Adorno and Jorge L. Urioste"
    end

    def test_registry_row_is_ready_unwired_and_manual_on_the_americas_axis
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["guaman-poma"]
      refute_nil entry
      assert entry.wired, "wired: true — first sync verified 2026-10-11 (1,189 docs / 5,911 passages)"
      assert_equal "manual", entry.sync_policy
      assert_equal ["americas"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "guaman-poma", name: "Guaman Poma",
                                          adapter_class: "Nabu::Adapters::GuamanPoma", license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      assert_equal 15, db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal 15, db[:passages].count
    ensure
      db&.disconnect
    end

    # -- fetch (WebMock only) -------------------------------------------------

    def test_fetch_crawls_into_the_workdir_and_discover_finds_the_pages
      stub_request(:get, "#{Nabu::Adapters::GuamanPoma::BASE_URL}/titlepage/es/text/")
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "titlepage.html")))
      stub_request(:get, %r{\A#{Regexp.escape(Nabu::Adapters::GuamanPoma::BASE_URL)}/\d+/es/text/\z})
        .to_return(status: 200, body: File.read(File.join(FIXTURES, "5.html")))
      Dir.mktmpdir do |workdir|
        report = conformance_adapter.fetch(workdir)
        assert_match(/\A\h{64}\z/, report.sha)
        assert_match(/1190 pages/, report.notes)
        assert_equal 1190, conformance_adapter.discover(workdir).count
      end
    end

    def test_fetch_wraps_failure_in_fetch_error
      stub_request(:get, "#{Nabu::Adapters::GuamanPoma::BASE_URL}/titlepage/es/text/").to_return(status: 404)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end
  end
end
