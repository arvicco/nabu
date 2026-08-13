# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::Osta (P77-1) — the Old Spanish Textual Archive over
  # the new hsms family: document = one transcriptions/TEXT.xxx.txt (the
  # FILENAME siglum mints — the syriac-corpus precedent; the in-file
  # [XXX] header siglum rides metadata verbatim), passage = the HSMS
  # numbered section plus the honest `head` for pre-section text.
  # License nc under the №45-1 grant (CC BY-NC-SA 4.0, the Zenodo
  # record; the emailed "MIT" stays uncorroborated). The credit duty —
  # the Zenodo record citation + the per-text TEXT.xxx.txt identifier —
  # rides every document's metadata. Fixtures: two complete tiny real
  # transcriptions (test/fixtures/osta/manifest.yml).
  class OstaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("osta")

    def conformance_adapter
      Nabu::Adapters::Osta.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "osta"
    end

    # The documented hsms search-form derivation (conventions §9): a pure
    # function of the stored text, so the minted-form pin holds.
    def conformance_search_source(passage)
      Nabu::Adapters::HsmsParser.search_source(passage.text)
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_osta_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["osta"]
      refute_nil entry, "osta must be registered in config/sources.yml"
      refute entry.wired, "wired flips only after the owner-fired first sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal "osta", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_under_the_45_1_grant
      manifest = Nabu::Adapters::Osta.manifest
      assert_equal "nc", manifest.license_class,
                   "CC BY-NC-SA 4.0 — the Zenodo record is the sole declared grant (№45-1); " \
                   "the emailed MIT stays uncorroborated, nc governs"
      assert_includes manifest.license, "CC BY-NC-SA 4.0"
      assert_includes manifest.license, "zenodo"
      assert_equal "hsms", manifest.parser_family
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_transcription_in_siglum_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:osta:dac urn:nabu:osta:rhj], refs.map(&:id),
                   "the filename siglum IS the identity, lowercased"
      files = refs.map { |ref| ref.metadata["file"] }
      assert_equal %w[TEXT.DAC.txt TEXT.RHJ.txt], files
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_tree
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_discovery_skips_flag_non_matching_files_as_unrecognized
      Dir.mktmpdir do |dir|
        transcriptions = File.join(dir, "transcriptions")
        FileUtils.mkdir_p(transcriptions)
        FileUtils.cp(File.join(FIXTURES, "transcriptions", "TEXT.RHJ.txt"), transcriptions)
        File.write(File.join(transcriptions, "notes.txt"), "stray")
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert(skips.notes.any? { |note| note.include?("notes.txt") })
      end
    end

    # -- documents ------------------------------------------------------------

    def test_documents_carry_osp_the_header_lanes_and_the_45_1_citation
      document = parse_urn("urn:nabu:osta:rhj")
      assert_equal "osp", document.language
      assert_equal "Glosa al romance \"Rey que no hace justicia\"", document.title
      assert_equal "HSMS-0198", document.metadata["hsms_id"]
      assert_equal "RHJ", document.metadata["siglum"]
      citation = document.metadata["citation"]
      assert_includes citation, "TEXT.RHJ.txt",
                      "the per-text identifier — the №45-1 per-transcription citation form"
      assert_includes citation, "10.5281/zenodo.18931376",
                      "the Zenodo record citation rides every document (the №45-1 credit duty)"
    end

    def test_passages_are_head_plus_numbered_sections_in_osp
      document = parse_urn("urn:nabu:osta:rhj")
      assert_equal %w[urn:nabu:osta:rhj:head urn:nabu:osta:rhj:1], document.map(&:urn)
      assert(document.all? { |passage| passage.language == "osp" })
      section = document.to_a.last
      assert_includes section.text, "q<ue>brantarame", "pristine text keeps the diplomatic markup"
      assert_includes section.text_normalized, "quebrantarame",
                      "the search form resolves the expansions — recall over readable words"
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = osta_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 2, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def osta_source
      Nabu::Store::Source.create(
        slug: "osta", name: "OSTA — Old Spanish Textual Archive",
        adapter_class: "Nabu::Adapters::Osta", license_class: "nc"
      )
    end
  end
end
