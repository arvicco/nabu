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

    # The documented hsms search-form derivations (conventions §9), per
    # lane: the verticalized lane derives from its stored "tokens"
    # annotation (the ccmh-txt contract), the transcription lane from
    # the stored text alone — both recomputable from the row.
    def conformance_search_source(passage)
      if passage.annotations.key?("tokens")
        Nabu::Adapters::HsmsVrtParser.search_source(passage.text, passage.annotations)
      else
        Nabu::Adapters::HsmsParser.search_source(passage.text)
      end
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

    def test_discover_yields_transcriptions_then_verticalized_in_siglum_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:osta:ace urn:nabu:osta:alc urn:nabu:osta:dac urn:nabu:osta:rhj
                      urn:nabu:osta:ac2-vrt urn:nabu:osta:bq1-vrt], refs.map(&:id),
                   "the filename siglum IS the identity, lowercased; the verticalized lane " \
                   "appends with the -vrt sibling tail (transcription positions stay fixed)"
      files = refs.map { |ref| ref.metadata["file"] }
      assert_equal %w[TEXT.ACE.txt TEXT.ALC.txt TEXT.DAC.txt TEXT.RHJ.txt TEXT.AC2.vrt.html
                      TEXT.BQ1.vrt.html], files
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

    def test_verticalized_documents_carry_the_silver_lemma_lane
      document = parse_urn("urn:nabu:osta:ac2-vrt")
      assert_equal "osp", document.language
      section = document.first
      tokens = section.annotations["tokens"]
      refute_nil tokens, "the tokens annotation is the Indexer's lemma contract"
      assert_includes tokens, { "form" => "fizo", "lemma" => "hacer", "pos" => "VMIS3S0" }
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      assert_equal "silver", registry.lemma_tiers["osta"],
                   "FreeLing + HSMS-app lemmatization (Gago Jover & Pueyo Mena, Scriptum " \
                   "Digital 7) is automatic — silver, the GLAUx precedent"
    end

    # -- the works-table lane (P77-r6, №R-30) ----------------------------------

    def test_documents_carry_their_works_table_rows_verbatim
      document = parse_urn("urn:nabu:osta:rhj")
      works = document.metadata["works"]
      assert_equal 1, works.size
      work = works.first
      assert_equal "HSMS-0198-0001", work["obra_id"]
      assert_equal "4776", work["beta_manid"]
      assert_equal "5590", work["beta_cnum"]
      assert_equal "desconocido", work["autor"]
      assert_includes work["titulo"], "Rey que no hace justicia"
      assert_equal "1510 ca. ad quem", work["opdt_fin"], "dates ride as upstream text, never parsed"
      assert_equal ["castellano"], work["lenguas"]
      assert_equal %w[narrativa romancero glosa], work["materias"]
      assert_nil document.metadata["codex"],
                 "RHJ has no tabla-codices row — an absent codex stays honestly absent"
      assert_equal({ "lengua" => "castellano" }, document.metadata["facets"],
                   "the raw lengua rides as a facet — the Coptic-dialect precedent, the future lect hook")
    end

    def test_documents_with_a_codex_row_carry_it
      document = parse_urn("urn:nabu:osta:dac")
      codex = document.metadata["codex"]
      refute_nil codex
      assert_includes codex["biblioteca"], "Archivo Histórico Nacional"
      assert_equal "1201 a quo", codex["spdt_inicio"], "the copy dating, upstream text verbatim"
      assert_equal "manuscrito", codex["formato"]
    end

    def test_the_vrt_sibling_carries_the_same_works_lane
      document = parse_urn("urn:nabu:osta:ac2-vrt")
      assert_equal "osp", document.language
      works = document.metadata["works"]
      refute_nil works, "the -vrt sibling is the same work — same table join"
      assert_equal "Leyes del estilo", works.first["titulo"]
    end

    def test_language_resolves_from_the_works_table_majority
      tables = Nabu::Adapters::OstaTables.load(File.join(FIXTURES, "tables"))
      refute_nil tables
      assert_equal "osp", tables.language_for("RHJ")
      assert_equal "osp", tables.language_for("FJZ"), "leonés minority: castellano 2 of 3 wins"
      assert_equal "osp", tables.language_for("FNG"),
                   "osp 2 vs arg 2 — a tie falls to the codex's earliest work in table order"
      assert_nil tables.language_for("ZZZ")
    end

    def test_lengua_codes_map_the_censused_vocabulary
      codes = Nabu::Adapters::OstaTables::LENGUA_CODES
      assert_equal "osp", codes["castellano"]
      assert_equal "ast", codes["leonés"]
      assert_equal "roa-opt", codes["gallego"]
      assert_equal "arg", codes["aragonés"]
      assert_equal "arg", codes["navarro-aragonés"]
      assert_equal "arg", codes["navarro"]
      assert_equal "lat", codes["latín"]
    end

    def test_a_workdir_without_tables_keeps_the_v1_osp_claim
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "transcriptions"))
        FileUtils.cp(File.join(FIXTURES, "transcriptions", "TEXT.RHJ.txt"),
                     File.join(dir, "transcriptions"))
        adapter = conformance_adapter
        document = adapter.parse(adapter.discover(dir).first)
        assert_equal "osp", document.language, "no tables → the honest v1 whole-source claim"
        assert_nil document.metadata["works"]
        assert_nil document.metadata["facets"]
      end
    end

    # -- the =-tag family (the ACE live-sync quarantine wave) ------------------

    def test_equals_carrying_tags_are_containers_not_stray_text
      document = parse_urn("urn:nabu:osta:ace")
      assert_equal "Libros de ajedrez, dados y tablas", document.title,
                   "the {MIN=.} group no longer steals the {CB1. container close"
      section = document.to_a.last
      assert_includes section.text, "POr que toda mane-ra de alegria".split.first,
                      "the column text flows"
      assert_includes section.annotations["columns"].to_a, "CB1"
      assert_includes section.annotations["columns"].to_a, "CB2"
      census = document.metadata["unrecognized_tags"].to_s
      assert_includes census, "MIN=",
                      "an =-tag is a censused unknown container — loud, never a crash"
    end

    def test_stray_braces_are_censused_defects_never_quarantines
      document = parse_urn("urn:nabu:osta:alc")
      assert_equal "Fuero de Alcaraz", document.title
      defects = document.metadata["brace_defects"]
      refute_nil defects, "the first-sync census: transcribers mix sibling-style and batched " \
                          "column closes, so braces genuinely do not balance in ~2% of files"
      assert(defects.any? { |note| note.include?("unmatched close brace") })
      assert(defects.any? { |note| note.include?("unclosed") }, "the EOF-open container is censused too")
      text = document.map(&:text).join(" ")
      assert_includes text, "seer tenida", "the text NEVER pays for a stray brace"
      assert_includes text, "ganados tengan el esculca", "text after the EOF-open container flows"
    end

    # -- the GRK tag-soup recovery (the BQ1 live-sync crash) -------------------

    def test_unescaped_grk_markup_in_the_token_stream_parses_without_crashing
      document = parse_urn("urn:nabu:osta:bq1-vrt")
      assert_equal "Crónica de 1344 segunda redacción", document.title
      section = document.to_a.last
      assert_includes section.text, "elleos",
                      "the Greek tokens inside a real <GRK> block ride like any others"
      forms = section.annotations["tokens"].map { |token| token["form"] }
      assert_includes forms, "<GRK",
                      "upstream tokenizes its own unescaped markup — the token rides verbatim " \
                      "even though HTML4 soup-parses its display text into phantom elements"
      refute_includes document.metadata["unrecognized_tags"].to_s, "GRK",
                      "GRK is a KNOWN structure tag (the HSMS Greek-script marker), not census noise"
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = osta_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 6, first.added
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
