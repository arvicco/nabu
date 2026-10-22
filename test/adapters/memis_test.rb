# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"

module Adapters
  # memis: MEMIS 1.0, the Epigraphic corpus of Medieval and Early Modern
  # inscriptions in Slovenia (Gregor Pobežin, ZRC SAZU; CLARIN.SI
  # 11356/1376) — the Latin inscriptions of Koper and Piran as ONE TEI
  # file. Fixture (retrieved 2026-10-22, test/fixtures/memis/README.md):
  # MEMIS.xml with the header and <front> whole and 14 of the 51
  # inscription divs byte-verbatim — 1 (the pseudo-inscription, undated),
  # 2 (dated 1269: damage/supplied/gap/corr/ex), 4 (two sides), 6 ("2.
  # pol. 15. stol."), 8 (a day date), 12 ("1581/2"), 16 ("ok. 1670"), 21
  # (a Roman stele, "1. stol. po Kr.", reusing upstream's duplicate idno),
  # 32 (a placeholder Greek transcription), 38 (two sides, "1591?"), 40
  # (a doubled, empty <lb n="2"/>), 46 ("?"), 50 and 51 (Piran).
  class MemisTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("memis")

    def conformance_adapter = Nabu::Adapters::Memis.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "memis"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(number) = documents.find { |d| d.urn == "urn:nabu:memis:#{number}" } || flunk("#{number} missing")

    def line(number, cite) = doc(number).passages.find { |p| p.urn == "urn:nabu:memis:#{number}:#{cite}" }

    def cites(document) = document.passages.map { |p| p.urn.delete_prefix("#{document.urn}:") }

    # -- discovery -----------------------------------------------------------

    def test_one_document_per_inscription_keyed_by_its_number
      ids = conformance_adapter.discover(FIXTURES).map { |ref| ref.id.delete_prefix("urn:nabu:memis:") }
      assert_equal %w[1 2 4 6 8 12 16 21 32 38 40 46 50 51], ids
    end

    def test_the_front_matter_grain_is_skipped_by_rule_never_dropped
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_equal ["edition front matter (the corpus introduction, prose), not an inscription: <front>"],
                   skips.notes
    end

    def test_a_stray_file_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "MEMIS.xml"), dir)
        File.write(File.join(dir, "notes.txt"), "x")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_includes skips.notes, "non-corpus file: notes.txt"
      end
    end

    def test_an_empty_workdir_discovers_nothing
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- the line grain ---------------------------------------------------------

    def test_lines_read_with_the_editor_expansions
      assert_equal "Dominus noster p sal pius", line(1, "1").text
      assert_equal "Per hanc scripturam omnibus compareat manifestum quod sub anno", line(2, "1").text
      assert_equal "domini MCCLXIX indicione XII nobilis vir dominus Marinus Mau", line(2, "2").text
      assert_equal "bensis fecit fieri in honorem […] civitatis et a mense Aprili usque ad", line(2, "4").text
      assert_equal %w[1 2 3 4 5 6 7 8 9 10 11], cites(doc(2))
      assert(doc(2).passages.all? { |p| p.language == "lat" })
    end

    def test_the_diplomatic_line_drops_what_the_editor_added
      assert_equal "D n p sal pius", line(1, "1").annotations["diplomatic"]
      assert_equal "+MCCCXXX", line(50, "1").text
      assert_equal "Natalis de Padua", line(50, "3").annotations["diplomatic"]
      assert_equal "quondam Natalis de Padua", line(50, "3").text
      assert_equal "v f", line(50, "5").annotations["diplomatic"]
    end

    def test_a_word_broken_across_lines_is_flagged_on_its_continuation
      assert_equal "no", line(2, "3").annotations["break"]
      assert_nil line(2, "2").annotations["break"]
    end

    def test_two_sided_inscriptions_cite_side_then_line
      assert_equal((1..13).map { |n| "A.#{n}" } + (1..13).map { |n| "B.#{n}" }, cites(doc(4)))
      assert_equal "Stran A", line(4, "A.1").annotations["section"]
      assert_equal "Andreae Iusti", line(4, "A.1").text
      assert_equal %w[A.1 B.1 B.2 B.3 B.4 B.5 B.6 B.7], cites(doc(38))
      assert_equal "Aloysius Superantius", line(38, "A.1").text
    end

    def test_a_placeholder_transcription_mints_no_passage
      assert_equal (1..11).map(&:to_s), cites(doc(32)), "the Greek '...' ab is upstream's empty placeholder"
      assert_equal 1, doc(32).metadata["placeholder_transcriptions"]
    end

    def test_an_empty_line_mints_nothing_and_is_counted
      assert_equal %w[1 2 3], cites(doc(40)), "upstream doubles <lb n=\"2\"/>; the empty first copy mints nothing"
      assert_equal ["2"], doc(40).metadata["empty_lines"]
      assert_equal "MDLXXX", line(40, "2").text
      assert_nil doc(2).metadata["empty_lines"]
    end

    # -- metadata: the mined axes ------------------------------------------------

    def test_dates_are_mined_from_the_typed_orig_date
      expected = {
        2 => [1269, 1269, "1269"], 6 => [1451, 1500, "2. pol. 15. stol."], 8 => [1578, 1578, "29. 8. 1578"],
        12 => [1581, 1582, "1581/2"], 16 => [1670, 1670, "ok. 1670"], 21 => [1, 100, "1. stol. po Kr."],
        38 => [1591, 1591, "1591?"], 50 => [1430, 1430, "1430"], 51 => [1709, 1709, "1709"]
      }
      expected.each do |number, (from, to, raw)|
        assert_equal({ "not_before" => from, "not_after" => to, "raw" => raw }, doc(number).metadata["date"],
                     "inscription #{number}")
      end
    end

    def test_undatable_values_mint_no_date_but_keep_the_raw
      assert_nil doc(46).metadata["date"]
      assert_equal "?", doc(46).metadata["orig_date"]
      assert_nil doc(1).metadata["date"]
      assert_nil doc(1).metadata["orig_date"]
    end

    def test_dates_written_in_the_text_ride_verbatim_beside_the_typed_date
      assert_equal ["MCCCXXX"], doc(50).metadata["text_dates"], "upstream's origDate says 1430 — both kept"
      assert_equal ["1222"], doc(21).metadata["text_dates"]
    end

    def test_the_place_is_the_orig_place_and_the_holding_is_metadata
      meta = doc(2).metadata
      assert_equal "Iustinopolis (Koper)", meta["place"]
      assert_equal "Koper", meta["settlement"]
      assert_equal "Pokrajinski muzej Koper", meta["repository"]
      assert_equal({ "found" => "Levji grad", "observed" => "Pokrajinski muzej Koper" }, meta["provenance"])
      assert_equal "Piran", doc(51).metadata["place"]
      assert_nil doc(1).metadata["place"], "the pseudo-inscription records no origPlace"
      assert_equal "Koper", doc(1).metadata["settlement"]
    end

    def test_titles_object_and_the_heading_facet
      assert_equal "Morosinijeva plošča", doc(2).title
      meta = doc(2).metadata
      assert_equal "Kamnita stela", meta["object_type"]
      assert_equal "I-1-002", meta["idno"]
      assert_equal "I-1-002", doc(21).metadata["idno"], "upstream's duplicate idno rides verbatim; identity is @n"
      assert_equal({ "heading" => { "values" => ["Morosinijeva plošča"] },
                     "object" => { "values" => ["Kamnita stela"] } }, meta["facets"])
    end

    def test_translation_and_bibliography_ride_as_metadata
      meta = doc(50).metadata
      assert_match(/\ANicolo de Bello, nekoč Natale di Padova, je dal postaviti to obeležje/, meta["translation_sl"])
      assert_equal 4, doc(1).metadata["bibliography"].size
      refute_match(/Carli, 1877/, doc(1).metadata["translation_sl"].to_s)
    end

    def test_the_heading_facet_folds_only_genre_bearing_headings
      kinds = Nabu::Kinds.load(
        classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
        map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml")
      )
      assert_equal ["building"], kinds.normalize("memis", doc(2).title)
      assert_equal ["honorific"], kinds.normalize("memis", doc(51).title)
      assert_equal ["honorific"], kinds.normalize("memis", doc(38).title)
      assert_equal ["funerary"], kinds.normalize("memis", doc(50).title)
      assert_empty kinds.normalize("memis", doc(1).title), "the pseudo-inscription is a declared non-claim"
      fold = kinds.fold("memis", doc(12).title)
      assert_empty fold.paths, "'Napis za …' names the honorand only — never guessed"
      assert_equal ["Napis za Giovannija Malipiera"], fold.uncovered
    end

    def test_the_metadata_dates_lane_is_registered
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["memis"]
    end

    # -- fetch ----------------------------------------------------------------

    def test_fetch_pins_the_one_bitstream
      body = File.binread(File.join(FIXTURES, "MEMIS.xml"))
      stub_request(:get, Nabu::Adapters::Memis::BITSTREAM_URL)
        .to_return(status: 200, body: body, headers: { "Last-Modified" => "Mon, 27 Mar 2023 17:01:19 GMT" })
      Dir.mktmpdir do |dir|
        report = conformance_adapter.fetch(dir)
        assert_equal body, File.binread(File.join(dir, "MEMIS.xml"))
        refute_nil report.sha
        assert_equal 14, conformance_adapter.discover(dir).count
      end
    end

    # -- registry ----------------------------------------------------------------

    def test_registry_row_is_unwired_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["memis"]
      refute_nil entry
      assert_equal Nabu::Adapters::Memis, entry.adapter_class
      assert entry.wired, "wired flipped at the first sync: 51 documents / 473 line passages"
      assert_equal "manual", entry.sync_policy
    end
  end
end
