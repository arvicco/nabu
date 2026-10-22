# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Extrabiblical — the ETCBC extrabiblical corpus over the
  # text-fabric family: Iron Age Hebrew and Moabite epigraphy, the Deir
  # Alla plaster text, three Qumran Cave 1 scrolls and two rabbinic works,
  # with the ETCBC's morphology and clause/phrase constituency. Fixtures
  # are byte-verbatim tf/0.2 slices (Lachish, Mesa, Siloam whole) plus the
  # superseded tf/0.1 dataset's otype/book as the rejected-grain specimen
  # — see test/fixtures/extrabiblical/README.md for the trim recipe.
  class ExtrabiblicalTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("extrabiblical")
    ADAPTER = Nabu::Adapters::Extrabiblical

    # The 13 book nodes of upstream tf/0.2 (book.tf's book-grain block,
    # census 2026-10-22) — the corpus the per-book tables must cover.
    UPSTREAM_BOOKS = %w[
      B_1QHa B_1QM B_1QS Ajrud Arad Balaam Ketef_Hinnom Lachish Mesa
      Mesad_Hashavyahu Pirqe Shirata Siloam
    ].freeze

    def conformance_adapter
      ADAPTER.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "extrabiblical"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_extrabiblical_unwired_until_the_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["extrabiblical"]
      refute_nil entry, "extrabiblical must be registered in config/sources.yml"
      assert entry.wired, "wired flipped at the gate first sync: 13 documents / 1,800 passages"
      assert_equal "manual", entry.sync_policy
      assert_equal ADAPTER, entry.adapter_class
    end

    def test_manifest_is_nc_with_the_data_grant_and_its_confirmation
      manifest = ADAPTER.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license,
                      "Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)",
                      "the README's data grant, verbatim"
      assert_includes manifest.license, "2026-10-15", "the maintainers' confirmation, dated"
      assert_includes manifest.license, "MIT", "the repo LICENSE (MIT) covers the conversion code only"
      assert_equal "text-fabric", manifest.parser_family
      assert_equal "https://github.com/ETCBC/extrabiblical", manifest.upstream_url
    end

    # -- discover and the grain census ---------------------------------------

    def test_discover_yields_one_ref_per_pinned_book_node
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:extrabiblical:lachish
        urn:nabu:extrabiblical:mesa
        urn:nabu:extrabiblical:siloam
      ], refs.map(&:id)
      assert_equal(%w[Lachish Mesa Siloam], refs.map { |ref| ref.metadata["book"] })
      assert(refs.all? { |ref| ref.path.end_with?(File.join("tf", "0.2")) },
             "only the pinned dataset version is read — tf/0.1 never yields a document")
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_the_superseded_dataset_version_skips_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 10, skips.skipped_by_rule, "tf/0.1's otype declares 10 book nodes, each superseded"
      assert_equal 0, skips.unrecognized
      assert_includes skips.notes, "superseded dataset version tf/0.1 (tf/0.2 is pinned): Siloam"
      assert_equal 10, skips.notes.size
    end

    def test_a_newer_dataset_version_is_unrecognized_drift_never_silently_ignored
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "tf"), dir)
        FileUtils.mkdir_p(File.join(dir, "tf", "0.3"))
        FileUtils.cp(File.join(FIXTURES, "tf", "0.1", "otype.tf"), File.join(dir, "tf", "0.3"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 10, skips.skipped_by_rule
        assert_equal 1, skips.unrecognized, "a version above the pin is a re-pin decision, loud"
        assert(skips.notes.any? { |note| note.include?("tf/0.3") })
        refute skips.clean?
      end
    end

    def test_the_per_book_tables_cover_exactly_upstreams_thirteen_books
      assert_equal UPSTREAM_BOOKS.sort, ADAPTER::BOOKS.keys.sort,
                   "the urn/title/language/place table is fixed at the 13 tf/0.2 books"
      eras = Nabu::WorkEras.default
      assert_equal "book", eras.key_for("extrabiblical")
      assert_equal UPSTREAM_BOOKS.sort, eras.works("extrabiblical").sort,
                   "config/work_eras.yml dates every book (parity with the adapter table)"
      UPSTREAM_BOOKS.each do |book|
        era = eras.lookup("extrabiblical", book)
        refute_nil era, "#{book}: an attributed era, never a silent gap"
        assert_operator era.band[0], :<, era.band[1], "#{book}: the band runs forward"
        refute_empty eras.note("extrabiblical", book).strip, "#{book}: every row cites its reasoning"
      end
      kinds = Nabu::Kinds.load(
        classes_path: File.expand_path("../../config/kind_classes.yml", __dir__),
        map_path: File.expand_path("../../config/kind_map.yml", __dir__)
      )
      assert_equal ["book"], kinds.metadata_for("extrabiblical")
      UPSTREAM_BOOKS.each do |book|
        folded = kinds.normalize("extrabiblical", book)
        declared = kinds.deliberate_declarations.any? { |slug, value, _| slug == "extrabiblical" && value == book }
        refute_includes folded, "unmapped", "#{book}: the closed vocabulary leaves nothing unmapped"
        assert(!folded.empty? || declared, "#{book}: folded to a kind or declared deliberate in kind_map.yml")
      end
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_corpus_chapter_verse_grain
      assert_equal %w[3.1 4.1 5.1 6.1], suffixes("urn:nabu:extrabiblical:lachish"),
                   "Lachish letters 3-6, one undivided verse each"
      assert_equal((1..39).map { |line| "1.#{line}" }, suffixes("urn:nabu:extrabiblical:mesa"),
                   "the Mesha Stele's 39 lines")
      assert_equal %w[1.1], suffixes("urn:nabu:extrabiblical:siloam")
    end

    def test_verse_text_is_the_text_orig_full_rendering
      siloam = passage_at("urn:nabu:extrabiblical:siloam", "urn:nabu:extrabiblical:siloam:1.1")
      assert siloam.text.start_with?("דבר הנקבה וזה היה דבר הנקבה בעוד החצבם"),
             "{g_word_utf8}{g_suffix_utf8} per word"
      assert siloam.text.end_with?("היה גבה הצר על ראשׁ החצבם"), "trailing whitespace stripped"
      mesa = passage_at("urn:nabu:extrabiblical:mesa", "urn:nabu:extrabiblical:mesa:1.1")
      assert_equal "אנך משׁע בן כמשׁית מלך מאב הדיבני", mesa.text,
                   "the article joins its noun: ה carries no suffix space"
      lachish = passage_at("urn:nabu:extrabiblical:lachish", "urn:nabu:extrabiblical:lachish:4.1")
      assert lachish.text.end_with?("כי לא נראה את עזקה"), "Lachish 4: 'we cannot see Azekah'"
    end

    def test_languages_follow_the_per_book_table_with_the_upstream_claim_kept
      mesa = parse_urn("urn:nabu:extrabiblical:mesa")
      assert_equal "obm", mesa.language, "the Mesha Stele is Moabite"
      assert(mesa.passages.all? { |passage| passage.language == "obm" })
      assert(mesa.passages.all? { |passage| passage.text.unicode_normalized?(:nfc) },
             "obm is not NFC-exempt — the consonantal text is NFC-stable as shipped")
      assert_equal "Hebrew", mesa.metadata["etcbc_language"], "language.tf's own claim rides verbatim"
      assert_match(/Moabite/, mesa.metadata["language_basis"])
      %w[lachish siloam].each do |slug|
        document = parse_urn("urn:nabu:extrabiblical:#{slug}")
        assert_equal "hbo", document.language
        assert_nil document.metadata["language_basis"], "upstream's Hebrew claim stands as-is"
      end
    end

    def test_a_non_hebrew_language_value_is_a_parse_error_never_a_guess
      with_fixture_copy do |dir|
        path = File.join(dir, "tf", "0.2", "language.tf")
        File.write(path, File.read(path).sub("\nHebrew\n", "\nAramaic\n"))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "urn:nabu:extrabiblical:lachish" }
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_match(/Aramaic/, error.message)
      end
    end

    def test_an_unknown_book_name_is_a_parse_error
      with_fixture_copy do |dir|
        path = File.join(dir, "tf", "0.2", "book.tf")
        File.write(path, File.read(path).sub("\tLachish\n", "\tLakish\n"))
        error = assert_raises(Nabu::ParseError) { conformance_adapter.discover(dir).to_a }
        assert_match(/Lakish/, error.message)
      end
    end

    # -- tokens ----------------------------------------------------------------

    def test_tokens_carry_every_word_grain_feature_verbatim
      tokens = passage_at("urn:nabu:extrabiblical:mesa", "urn:nabu:extrabiblical:mesa:1.1").annotations["tokens"]
      assert_equal (24_171..24_178).to_a, tokens.map { |t| t["n"] }, "n = the stable TF slot number"
      mesha = tokens[1]
      {
        "form" => "משׁע", "trailer" => " ", "lex" => "MJC<", "lex_utf8" => "מישׁע", "sp" => "nmpr",
        "gn" => "m", "nu" => "sg", "ps" => "NA", "st" => "a", "g_word" => "MC<", "number" => 2,
        "vs" => "NA", "vt" => "NA"
      }.each { |name, value| assert_equal value, mesha[name], "#{name} rides verbatim" }
      article = tokens[6]
      assert_equal "ה", article["form"]
      refute article.key?("trailer"), "an empty suffix is absent, never an empty string"
      refute mesha.key?("nme"), "absent upstream = absent here"
    end

    def test_empty_form_slots_keep_their_token_place
      tokens = parse_urn("urn:nabu:extrabiblical:lachish").passages.flat_map { |p| p.annotations["tokens"] }
      elided = tokens.find { |t| t["n"] == 23_809 }
      refute_nil elided, "the elided article keeps its slot"
      refute elided.key?("form")
      assert_equal "H", elided["lex"]
      assert_equal 391, tokens.size, "Lachish 3-6 carry 391 word slots"
    end

    def test_declared_features_never_ride_tokens
      declined = ADAPTER::DECLINED_TOKEN_FEATURES
      assert_empty declined.keys & ADAPTER::TOKEN_FEATURES, "a feature is ridden or declined, never both"
      assert(declined.values.all? { |reason| reason.is_a?(String) && !reason.empty? })
      tokens = parse_urn("urn:nabu:extrabiblical:siloam").passages.flat_map { |p| p.annotations["tokens"] }
      keys = tokens.flat_map(&:keys).uniq
      %w[language lexeme_count g_suffix g_word_utf8 qere kind function].each do |name|
        refute_includes keys, name
      end
    end

    # -- constituency spans ---------------------------------------------------

    def test_clause_and_phrase_spans_ride_the_bhsa_shape
      document = parse_urn("urn:nabu:extrabiblical:mesa")
      spans = document.passages.flat_map { |p| p.annotations.fetch("spans", []) }
      clauses = spans.select { |s| s["type"] == "clause" }
      phrases = spans.select { |s| s["type"] == "phrase" }
      refute_empty clauses
      refute_empty phrases
      first = document.passages.first.annotations["spans"]
      assert_equal "clause", first.first["type"], "clauses before phrases at a tie (containment order)"
      first.each do |span|
        assert_kind_of Integer, span["node"]
        span["ranges"].each { |a, b| assert_operator a, :<=, b }
      end
      assert(clauses.all? { |s| s.key?("kind") && s.key?("typ") }, "clause features ride verbatim")
      assert(phrases.all? { |s| s.key?("function") }, "phrase function rides verbatim")
    end

    def test_the_slice_carries_every_upstream_constituent_once_per_verse
      nodes = %w[lachish mesa siloam].flat_map do |slug|
        parse_urn("urn:nabu:extrabiblical:#{slug}").passages.flat_map { |p| p.annotations.fetch("spans", []) }
      end
      assert_equal 173, nodes.count { |s| s["type"] == "clause" }, "the 173 slice clauses (oslots census)"
      assert_equal 560, nodes.count { |s| s["type"] == "phrase" }, "the 560 slice phrases"
    end

    def test_mother_edges_ride_as_integer_node_ids
      spans = %w[lachish mesa siloam].flat_map do |slug|
        parse_urn("urn:nabu:extrabiblical:#{slug}").passages.flat_map { |p| p.annotations.fetch("spans", []) }
      end
      mothered = spans.select { |s| s.key?("mother") }
      refute_empty mothered
      assert(mothered.all? { |s| s["mother"].is_a?(Integer) })
    end

    # -- the axes: dating, place, kind ----------------------------------------

    def test_documents_carry_the_book_key_and_the_find_site
      lachish = parse_urn("urn:nabu:extrabiblical:lachish")
      assert_equal "Lachish", lachish.metadata["book"], "the key the work_eras and kind_map tables read"
      assert_equal({ "ancient" => "Lachish", "pleiades" => "687951" }, lachish.metadata["place"])
      assert_equal "Lachish letters", lachish.title
      assert_equal "Lachish", lachish.metadata["book_en"], "book@en rides verbatim"
      mesa = parse_urn("urn:nabu:extrabiblical:mesa")
      assert_equal({ "ancient" => "Dibon", "pleiades" => "697654" }, mesa.metadata["place"],
                   "found at Dhiban (ancient Dibon) in 1868")
      assert_equal "Mesha_Stela", mesa.metadata["book_en"]
      assert_equal "0.2", mesa.metadata["dataset_version"]
    end

    def test_unplaced_works_carry_no_place_claim
      assert_nil ADAPTER::BOOKS.fetch("Pirqe")[:place], "a rabbinic work has no find-site"
      assert_nil ADAPTER::BOOKS.fetch("Shirata")[:place]
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = extrabiblical_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 3, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal 44, counts.last, "4 + 39 + 1 passages"
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in discover"
      adapter.parse(ref)
    end

    def suffixes(urn)
      parse_urn(urn).passages.map { |p| p.urn.delete_prefix("#{urn}:") }
    end

    def passage_at(document_urn, passage_urn)
      passage = parse_urn(document_urn).find { |p| p.urn == passage_urn }
      refute_nil passage, "expected #{passage_urn} in #{document_urn}"
      passage
    end

    def with_fixture_copy
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "tf"), dir)
        yield dir
      end
    end

    def extrabiblical_source
      Nabu::Store::Source.create(
        slug: "extrabiblical", name: "ETCBC extrabiblical",
        adapter_class: "Nabu::Adapters::Extrabiblical", license_class: "nc"
      )
    end
  end
end
