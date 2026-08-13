# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Disco (P77-4) — the Diachronic Spanish Sonnet Corpus
  # over the small disco-tei family: document = one per-author file from
  # tei/all-periods-per-author/ (the corpus's own complete aggregation),
  # urn:nabu:disco:<id> from the filename's own id (disco001g → 001g);
  # passage = one sonnet, cited by the corpus's OWN sonnet ordinal
  # (s002g_0002 → :2 — the id space is corpus-wide per author, never
  # per-file-1-based). Lines keep their breaks; the automatic
  # met/rhyme/enjamb layers ride annotations, labeled. Language spa —
  # the code the derom/wold reflex lanes already hold.
  class DiscoTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("disco")

    def conformance_adapter
      Nabu::Adapters::Disco.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "disco"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_disco_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["disco"]
      refute_nil entry, "disco must be registered in config/sources.yml"
      refute entry.wired
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "romance"
    end

    def test_manifest_is_attribution_with_the_readme_grant
      manifest = Nabu::Adapters::Disco.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC-BY"
      assert_equal "disco-tei", manifest.parser_family
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_author_file_in_id_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:disco:001g urn:nabu:disco:002g urn:nabu:disco:002n],
                   refs.map(&:id), "the filename's own id mints, the disco prefix stripped"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_tree
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents ------------------------------------------------------------

    def test_documents_carry_author_period_and_source_metadata
      document = parse_urn("urn:nabu:disco:001g")
      assert_equal "spa", document.language
      assert_equal "Sonetos de Joseph Aragonés", document.title
      metadata = document.metadata
      assert_equal "Joseph Aragonés", metadata["author"]
      assert_equal "15th-17th", metadata["period"], "the id suffix letter maps to upstream's period dir"
      assert_equal "17", metadata["birth_century"]
      assert_equal "Valencia", metadata["birthplace"]
      assert_includes metadata["source"], "Biblioteca Cervantes Virtual"
      assert_equal "19th", parse_urn("urn:nabu:disco:002n").metadata["period"]
    end

    # -- passages: one sonnet each, upstream's own ordinals -------------------

    def test_sonnets_cite_the_corpus_own_ordinals_never_positional
      document = parse_urn("urn:nabu:disco:002g")
      assert_equal %w[urn:nabu:disco:002g:2 urn:nabu:disco:002g:3], document.map(&:urn),
                   "s002g_0002/s002g_0003 — the id space starts where upstream says"
      assert_equal "s002g_0002", document.first.annotations["sonnet_id"]
    end

    def test_sonnet_text_is_fourteen_lines_with_structure_riding_annotations
      sonnet = parse_urn("urn:nabu:disco:001g").first
      lines = sonnet.text.lines(chomp: true)
      assert_equal 14, lines.size
      assert_equal "Valencia insigne, patria venturosa,", lines.first,
                   "inline <w type=rhyme> marks flatten seamlessly"
      assert_equal "Con dicciones valencianas y castellanas", sonnet.annotations["title"]
      assert_equal [{ "type" => "cuarteto", "lines" => 4 }, { "type" => "cuarteto", "lines" => 4 },
                    { "type" => "terceto", "lines" => 3 }, { "type" => "terceto", "lines" => 3 }],
                   sonnet.annotations["stanzas"],
                   "sonnet architecture rides annotations, never blank lines in text"
      line_notes = sonnet.annotations["lines"]
      assert_equal 14, line_notes.size
      assert_equal "-+-+-+---+-", line_notes.first["met"], "ADSO scansion — automatic, labeled"
      assert_equal "A", line_notes.first["rhyme"]
      assert_equal "pb_adj_prep", line_notes[2]["enjamb"]
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = disco_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 3, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def disco_source
      Nabu::Store::Source.create(
        slug: "disco", name: "DISCO — Diachronic Spanish Sonnet Corpus",
        adapter_class: "Nabu::Adapters::Disco", license_class: "attribution"
      )
    end
  end
end
