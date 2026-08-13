# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Fornsvenska (P77-6) — Old Swedish over the NEW sparv
  # family: document = one <text> (a law, a chronicle), urn from the
  # title's ASCII slug; passage = one sentence at <paragraph>.<sentence>;
  # upstream's per-text dating attrs ride metadata verbatim. Language sv
  # (no ISO code for Old Swedish — the IcePaHC-under-`is` precedent; the
  # sv:old stage rule is №R-32). The automatic fsvm lemma candidate sets
  # are deliberately NOT ingested. Fixtures: two parts trimmed to their
  # first two texts (content verbatim, re-bzipped).
  class FornsvenskaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("fornsvenska")

    def conformance_adapter
      Nabu::Adapters::Fornsvenska.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "fornsvenska"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_fornsvenska_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["fornsvenska"]
      refute_nil entry, "fornsvenska must be registered in config/sources.yml"
      refute entry.wired
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "germanic"
    end

    def test_manifest_is_attribution_and_scopes_out_the_nysvensk_parts
      manifest = Nabu::Adapters::Fornsvenska.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC-BY-4.0"
      assert_equal "sparv", manifest.parser_family
      assert_equal 7, Nabu::Adapters::Fornsvenska::PARTS.size,
                   "the seven fornsvenska parts — the fsv-nysvensk* siblings are Early Modern " \
                   "Swedish, a different stage, deliberately out of the Old Swedish claim"
      assert(Nabu::Adapters::Fornsvenska::PARTS.none? { |part| part.include?("nysvensk") })
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_text_parts_in_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:fornsvenska:aldre-vastgotalagen
        urn:nabu:fornsvenska:bjarkoaratten
        urn:nabu:fornsvenska:erikskronikan-ur-spegelbergs-bok-codex-holm-d2
        urn:nabu:fornsvenska:karlskronikan
      ], refs.map(&:id), "titles slugify ASCII (the ren/rundata idiom); laws part before verser"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_files
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages -----------------------------------------------

    def test_documents_carry_the_upstream_dating_attrs_verbatim
      document = parse_urn("urn:nabu:fornsvenska:aldre-vastgotalagen")
      assert_equal "sv", document.language
      assert_equal "Äldre Västgötalagen", document.title
      assert_equal "fsv-aldrelagar", document.metadata["part"]
      assert_equal({ "part" => { "value" => "fsv-aldrelagar" } }, document.metadata["facets"],
                   "the part rides as a facet — the №R-32 sv:old rule's hook (rule lands with " \
                   "the nabu-lects sv mint)")
      assert_equal "1280–1290", document.metadata["date"], "upstream's own band, verbatim"
      assert_equal "12800101", document.metadata["datefrom"]
      assert_equal "12901231", document.metadata["dateto"]
    end

    def test_passages_are_sentences_at_paragraph_dot_sentence
      document = parse_urn("urn:nabu:fornsvenska:aldre-vastgotalagen")
      assert_equal %w[
        urn:nabu:fornsvenska:aldre-vastgotalagen:1.1
        urn:nabu:fornsvenska:aldre-vastgotalagen:2.1
        urn:nabu:fornsvenska:aldre-vastgotalagen:2.2
      ], document.map(&:urn)
      assert_equal "Kirkiu Bolkær", document.first.text,
                   "tokens rejoin with single spaces — upstream is tokenized, no layout layer"
      assert_equal "48fd8de-4846a90", document.first.annotations["sentence_id"],
                   "the opaque upstream id rides verbatim, never mints"
      third = document.to_a.last
      assert third.text.start_with?("Her byriarz laghbok"), "the automatic lemma attrs never leak into text"
    end

    def test_the_verser_part_parses_the_chronicles
      document = parse_urn("urn:nabu:fornsvenska:karlskronikan")
      assert_equal "Karlskrönikan", document.title
      assert_equal "1389–1452", document.metadata["date"]
      assert_equal 2, document.size
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = fornsvenska_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
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

    def fornsvenska_source
      Nabu::Store::Source.create(
        slug: "fornsvenska", name: "Fornsvenska textbanken",
        adapter_class: "Nabu::Adapters::Fornsvenska", license_class: "attribution"
      )
    end
  end
end
