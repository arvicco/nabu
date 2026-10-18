# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # pl-wikisource (P116-3, under the base-edition rule): the premodern Polish-
  # literature cone + Brückner's etymological dictionary (the declared
  # dictionary lane). Fixture envelopes are real api.php captures
  # (2026-10-10): Bogurodzica (pieśń) (a ProofreadPage transclusion of
  # Łoś's 1922 edition), Cyzjojan płocki (direct verse table with refs),
  # Na lipę II (Kochanowski, 1883) (a section transclusion, edition in
  # the title), Apologeticus …/Lavacrum conscientiae (the 1932 PAU
  # edition — EDITION_TAINT_POST_1930). Brückner: scan pages 084–085
  # whole + five entry stubs (córa spans the page break; gospoda's scan
  # is not held).
  class PlWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("pl-wikisource")

    def conformance_adapter = Nabu::Adapters::PlWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "pl-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def test_discovers_the_admitted_pages_and_censuses_the_taint
      assert_equal %w[urn:nabu:pl-wikisource:11208 urn:nabu:pl-wikisource:1481
                      urn:nabu:pl-wikisource:25521],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      refute(skips.notes.any? { |note| note.include?("bruckner/") }, "the bruckner/ tree is corpus, not strays")
      assert(skips.notes.any? { |note| note.include?("EDITION_TAINT_POST_1930") })
    end

    def test_the_1932_edition_is_excluded_by_rule
      adapter = conformance_adapter
      envelope = JSON.parse(File.read(File.join(FIXTURES, "pages", "1387443.json")))
      assert_equal :edition_taint, adapter.page_class(envelope)
      assert_includes adapter.edition_years(envelope["title"], envelope["wikitext"]), 1932
    end

    def test_language_and_verbatim_edition_statement
      bogurodzica = doc(1481)
      assert_equal "pol", bogurodzica.language
      assert_includes bogurodzica.metadata["base_edition"], "Na podstawie: Jan Łoś, M. Arct i S-ka, Lublin 1922",
                      "the Nagłówek adnotacje rides verbatim (owner ruling)"
      fraszka = doc(11_208)
      assert_equal "index: Fraszki (Jan Kochanowski) · title: Kochanowski, 1883",
                   fraszka.metadata["base_edition"], "the scan index + the title's dated parenthetical"
    end

    # The Dane tekstu header's author slot (autor, or autor1 on the
    # medieval songs) and the |pochodzenie= parent work — the same author
    # key the wikitext family (sl/hr/sr) mines.
    def test_author_and_parent_work_ride_metadata
      assert_equal "Jan Kochanowski", doc(11_208).metadata["author"]
      assert_equal "Anonim", doc(1481).metadata["author"]
      assert_nil doc(1481).metadata["work"], "a page without |pochodzenie= is its own work"
      apologeticus = JSON.parse(File.read(File.join(FIXTURES, "pages", "1387443.json")))
      assert_equal "anonimowy", conformance_adapter.header_author(apologeticus["wikitext"])
      assert_equal "Apologeticus to jest Obrona konfederacyej: przytym Seditio albo bunt kapłański na " \
                   "ewanieliki w Wilnie z wolej a łaski miłego Boga przed harapem wynurzony",
                   conformance_adapter.parent_work(apologeticus["wikitext"])
    end

    def test_author_slot_editorial_notes_and_list_templates
      adapter = conformance_adapter
      assert_equal "anonimowy",
                   adapter.header_author("{{Dane tekstu\n|autor=anonimowy<ref name=\"a\">{{Przypiswiki}} " \
                                         "przypis</ref>\n}}")
      assert_equal "Wojciech Stanisław Chrościński; Bolesław Erzepki",
                   adapter.header_author("{{Dane tekstu\n|autor={{Lista autorów|Wojciech Stanisław " \
                                         "Chrościński; [[Autor:Bolesław Erzepki|Bolesław Erzepki]]}}\n}}")
    end

    def test_era_band_follows_the_cone_category
      assert_equal({ "not_before" => 1401, "not_after" => 1500, "raw" => "Polska poezja świecka XV wieku" },
                   doc(25_521).metadata["era_band"])
      assert_equal [1500, 1620], doc(11_208).metadata["era_band"].values_at("not_before", "not_after")
    end

    def test_section_transclusion_renders_the_one_fraszka
      d = doc(11_208)
      assert_equal 1, d.passages.size
      assert d.passages.first.text.start_with?("Przypatrz się gościu! jako on list mój zielony")
    end

    def test_rules_census_title_shapes
      adapter = conformance_adapter
      header = "{{Dane tekstu\n|rok wydania = 1893\n}}"
      assert_equal :aggregate, adapter.wikitext_class("Setnik rymów duchownych/całość", header)
      assert_equal :apparatus, adapter.wikitext_class("Pamiętniki (Pasek)/Wstęp", header)
      assert_equal :apparatus,
                   adapter.wikitext_class("Mikołaja Reya z Nagłowic Figliki/Objaśnienia do „Figlików“/VI", header)
      assert_nil adapter.wikitext_class("Setnik rymów duchownych/C", header)
    end

    # -- Brückner: the dictionary lane ---------------------------------------

    def lane = Nabu::Adapters::PlWikisource.dictionary_lane

    def entries
      @entries ||= lane.discover(FIXTURES).flat_map { |ref| lane.parse(ref).entries.to_a }
    end

    def test_bruckner_is_the_declared_dictionary_lane
      assert_kind_of Nabu::Adapters::PlWikisourceBrucknerLane, lane
      documents = lane.discover(FIXTURES).map { |ref| lane.parse(ref) }
      assert_equal 1, documents.size
      assert_equal "bruckner", documents.first.slug
      assert_equal "pol", documents.first.language
    end

    def test_one_entry_per_stub_whose_section_is_held
      assert_equal %w[cmentarz co cuch córa], entries.map(&:entry_id).sort,
                   "gospoda's scan page is not held — no entry, never a guess"
    end

    def test_entry_spanning_a_page_break_joins_with_the_hyphenation_pair
      cora = entries.find { |entry| entry.entry_id == "córa" }
      assert cora.body.start_with?("córa, córka; w nagłosie d odpadło")
      assert_includes cora.body, "odbiegają postaci znaczniej od naszych: rus. docz",
                      "{{pp|na|szych}} + {{pk|na|szych}} rejoin the split word across 084→085"
      refute_match(/\{\{|\}\}|'''|<section/, cora.body, "no wiki markup survives")
      assert_equal "cora", cora.headword_folded
    end

    # -- load: idempotency (the house double-load rule) ----------------------

    def source_row
      Nabu::Store::Source.create(slug: "pl-wikisource", name: "Polish Wikisource",
                                 adapter_class: "Nabu::Adapters::PlWikisource", license_class: "attribution")
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = source_row
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 3, first.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    def test_bruckner_double_load_is_idempotent
      catalog = store_test_db
      loader = Nabu::Store::DictionaryLoader.new(db: catalog, source: source_row)
      first = loader.load_from(lane, workdir: FIXTURES)
      assert_equal 4, first.added
      second = loader.load_from(lane, workdir: FIXTURES)
      assert_equal 0, second.added
      assert_equal 4, catalog[:dictionary_entries].count
      assert_equal [1], catalog[:dictionary_entries].select_map(:revision).uniq
    end

    def test_an_unclosed_section_tag_never_leaks
      # The live census found ONE malformed close (kiermasz, the entry
      # continued onto scan pageid 197229):
      # `…biesiadą’.<section end="kiermasz" .<section end="kiermasz" />`.
      body = Nabu::Adapters::PlWikisourceBrucknerLane.clean(
        "z niem. ''Kirchmesse'', ''Kirmes''.<section end=\"kiermasz\" ."
      )
      assert_equal "z niem. Kirchmesse, Kirmes.", body
    end

    def test_links_keep_their_label
      cmentarz = entries.find { |entry| entry.entry_id == "cmentarz" }
      assert_includes cmentarz.body, "mylnie smętarz (niby od smętny)"
    end
  end
end
