# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Oracc (P10-1): discover walks <workdir>/<project>/
  # corpusjson/*.json (skipping the catalog-only EMPTY files — an upstream
  # norm, not damage), parse delegates to OraccJsonParser, fetch downloads and
  # unpacks the per-project HTTP zips via Nabu::ZipFetch. No network: fetch is
  # exercised against WebMock-stubbed zip responses ASSEMBLED IN THE TEST from
  # the real checked-in fixture files (the corpusjson/metadata/catalogue
  # payloads are genuine upstream data; only the zip envelope is built here —
  # ORACC serves `application/zip` with a `Last-Modified` header, the shape
  # recorded by the P9-5a scout and honestly reproduced below).
  class OraccTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("oracc")

    # The conformance instance is translations-enabled (the registry shape
    # once sources.yml carries `translations: true`), so the -en sibling
    # documents run the whole conformance gauntlet too. crawl_delay 0 keeps
    # the WebMock'd fetch tests instant.
    def conformance_adapter
      Nabu::Adapters::Oracc.new(translations: true, crawl_delay: 0)
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "oracc"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_tablets_and_their_translations_sorted_by_urn
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:oracc:etcsri:Q001299
        urn:nabu:oracc:etcsri:Q004151
        urn:nabu:oracc:rimanum:P405134
        urn:nabu:oracc:rimanum:P405134-en
        urn:nabu:oracc:rimanum:P405432
        urn:nabu:oracc:rimanum:P405432-en
        urn:nabu:oracc:saao-saa01:P224395
        urn:nabu:oracc:saao-saa01:P224395-en
      ], refs.map(&:id)
    end

    def test_discover_without_the_translations_flag_is_inert
      # The registry default (no `translations: true`) must behave exactly as
      # before P13-4: tablets only, even with html-en fixtures on disk.
      ids = Nabu::Adapters::Oracc.new.discover(FIXTURES).map(&:id)
      assert_equal %w[
        urn:nabu:oracc:etcsri:Q001299
        urn:nabu:oracc:etcsri:Q004151
        urn:nabu:oracc:rimanum:P405134
        urn:nabu:oracc:rimanum:P405432
        urn:nabu:oracc:saao-saa01:P224395
      ], ids
    end

    def test_discover_translation_refs_carry_kind_corpusjson_and_title
      ref = conformance_adapter.discover(FIXTURES)
                               .find { |r| r.id == "urn:nabu:oracc:saao-saa01:P224395-en" }
      assert_equal "translation", ref.metadata["kind"]
      assert_equal "saao-saa01", ref.metadata["project"]
      assert ref.metadata["corpusjson"].end_with?("saao-saa01/saa01/corpusjson/P224395.json"),
             "the ref must carry the sibling corpusjson path for ref→label alignment"
      assert_equal "SAA 01 175 (English translation)", ref.metadata["title"]
    end

    def test_discover_skips_orphan_html_without_a_live_corpusjson
      Dir.mktmpdir do |root|
        FileUtils.cp_r(File.join(FIXTURES, "rimanum"), File.join(root, "rimanum"))
        orphans = File.join(root, "html-en", "rimanum")
        FileUtils.mkdir_p(orphans)
        FileUtils.cp(File.join(FIXTURES, "html-en", "rimanum", "P405432.html"),
                     File.join(orphans, "P999999.html"))
        adapter = conformance_adapter
        ids = adapter.discover(root).map(&:id)
        refute_includes ids, "urn:nabu:oracc:rimanum:P999999-en",
                        "a translation without its tablet is unrenderable — skipped by rule"
        assert_operator adapter.discovery_skips(root).skipped_by_rule, :>, 0,
                        "the orphan must be counted, never silent"
      end
    end

    def test_discover_skips_catalog_only_empty_corpusjson_files
      ids = conformance_adapter.discover(FIXTURES).map(&:id)
      refute_includes ids, "urn:nabu:oracc:rimanum:P405254",
                      "the 0-byte catalog-only file must be skipped, not yielded"
    end

    def test_discover_resolves_titles_from_the_catalogue_designation
      refs = conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
      assert_equal "UF 10, 152 26", refs["urn:nabu:oracc:rimanum:P405432"].metadata["title"]
      assert_equal "Amar-Suena 2049add / CDLI Seals 000423",
                   refs["urn:nabu:oracc:etcsri:Q004151"].metadata["title"]
      assert_equal "rimanum", refs["urn:nabu:oracc:rimanum:P405432"].metadata["project"]
    end

    # -- P11-7 fix 1: subproject NESTED-ROOT discovery ------------------------

    # The saao/saa01 (and rinap/rinap1) zips unpack with a nested root —
    # <slug>/saa01/corpusjson, not <slug>/corpusjson — so discover found zero of
    # their texts and the sync reported success. discover must now find
    # corpusjson at either depth.
    DEFECTS = Nabu::TestSupport.fixtures("oracc_p11_7")

    def test_discover_finds_subproject_texts_under_a_nested_root
      ids = Nabu::Adapters::Oracc.new.discover(DEFECTS).map(&:id)
      assert_includes ids, "urn:nabu:oracc:saao-saa01:P334176",
                      "the nested saao-saa01/saa01/corpusjson text must be discovered"
    end

    # -- P11-7 fix 7: discovery accounting (the systemic skip-visibility fix) --

    def test_discovery_skips_counts_zero_byte_skeletons_by_rule
      skips = Nabu::Adapters::Oracc.new.discovery_skips(DEFECTS)
      assert_equal 1, skips.skipped_by_rule, "the 0-byte dcclt file is a by-rule skip"
      assert_equal 0, skips.unrecognized
      assert_predicate skips, :clean?
    end

    def test_discovery_flags_a_project_tree_with_no_corpusjson_loudly
      Dir.mktmpdir do |root|
        # rimanum is a registered project: give it a tree but NO corpusjson
        # (the nested-root/unpack signature) — that must be loud, never silent.
        FileUtils.mkdir_p(File.join(root, "rimanum"))
        skips = Nabu::Adapters::Oracc.new.discovery_skips(root)
        assert_equal 1, skips.unrecognized
        refute_predicate skips, :clean?
        assert_match(/rimanum.*no corpusjson/, skips.notes.first)
      end
    end

    # -- P14-9 fix 3: a proxy/portal corpus is a benign skip, not a loud zero --

    def test_discovery_recognizes_a_proxy_corpus_as_a_benign_skip
      # riao/ribo/dcclt-jena are PROXY corpora: corpus.json is `type:corpus`
      # with a `proxies` map, their texts hosted in out-of-scope sibling
      # subprojects (PROJECTS note). Owning no corpusjson is BY DESIGN, so the
      # discovery accounting must NOT flag them as an unpack/layout error.
      skips = Nabu::Adapters::Oracc.new.discovery_skips(Nabu::TestSupport.fixtures("oracc_p14_9"))
      assert_equal 0, skips.unrecognized, "a proxy corpus is not an unpack error"
      assert_predicate skips, :clean?
    end

    # -- P31-0: ario + the four epsd2 corpora (config expansion) ---------------
    #
    # Five new PROJECTS rows ride the existing machinery against their own
    # fixture tree (the oracc_p14_9 own-tree precedent — the main discover-
    # walked corpus stays byte-stable). What the tree pins:
    #   * ario (Achaemenid royal trilinguals): peo/elx/akk tagged per l-node
    #     UPSTREAM — Old Persian and Elamite enter as data, not config. ario
    #     labels lines by VERSION ("Persian 1" → Persian.1).
    #   * epsd2 subprojects unpack NESTED (epsd2/literary/…), and admin/ur3
    #     is DOUBLY nested (epsd2/admin/ur3/… — the real zip root, verified
    #     by ranged read 2026-07-19), which project_dir must resolve.
    #   * the license gate reads CC0 from every one of the five trees.
    EXPANSION = Nabu::TestSupport.fixtures("oracc_p31_0")

    EXPANSION_URNS = %w[
      urn:nabu:oracc:ario:Q007149
      urn:nabu:oracc:ario:Q007203
      urn:nabu:oracc:ario:Q007267
      urn:nabu:oracc:epsd2-admin-ur3:P119709
      urn:nabu:oracc:epsd2-admin-ur3:P133815
      urn:nabu:oracc:epsd2-earlylit:P010246
      urn:nabu:oracc:epsd2-earlylit:P323472
      urn:nabu:oracc:epsd2-literary:P411270
      urn:nabu:oracc:epsd2-literary:Q000553
      urn:nabu:oracc:epsd2-royal:Q001016
    ].freeze

    def test_projects_includes_the_p31_expansion_rows
      %w[ario epsd2/literary epsd2/royal epsd2/earlylit epsd2/admin/ur3].each do |project|
        assert_includes Nabu::Adapters::Oracc::PROJECTS, project
      end
    end

    def test_discover_finds_the_expansion_projects_including_the_doubly_nested_root
      ids = Nabu::Adapters::Oracc.new.discover(EXPANSION).map(&:id)
      assert_equal EXPANSION_URNS, ids
    end

    def test_discover_resolves_expansion_titles_from_the_catalogue
      refs = Nabu::Adapters::Oracc.new.discover(EXPANSION).to_h { |ref| [ref.id, ref] }
      assert_equal "Darius I  16", refs["urn:nabu:oracc:ario:Q007149"].metadata["title"]
      assert_equal "Ur-Nanše 01", refs["urn:nabu:oracc:epsd2-royal:Q001016"].metadata["title"]
      assert_equal "TÉL 297 = L ---", refs["urn:nabu:oracc:epsd2-admin-ur3:P133815"].metadata["title"]
    end

    def test_parse_derives_peo_and_elx_from_the_ario_data
      adapter = Nabu::Adapters::Oracc.new
      refs = adapter.discover(EXPANSION).to_h { |ref| [ref.id, ref] }

      # DPd (Darius I 16): pure Old Persian, version-named line labels.
      peo = adapter.parse(refs["urn:nabu:oracc:ario:Q007149"])
      assert_equal "peo", peo.language
      assert_equal "urn:nabu:oracc:ario:Q007149:Persian.1", peo.first.urn
      assert_equal "d-a-r-y-v-u-š", peo.first.text

      # A2Sa (Artaxerxes II 02): pure Elamite — elx tagged upstream, and
      # honestly UNLEMMATIZED (ario ships no gloss-elx; tokens carry lang
      # but no cf), so elx enters the library without lemma rows.
      elx = adapter.parse(refs["urn:nabu:oracc:ario:Q007267"])
      assert_equal "elx", elx.language
      assert_equal "{DIŠ}da-ri-ia-ma-u-iš x", elx.first.text
      assert_empty(elx.flat_map { |p| p.annotations["tokens"].filter_map { |t| t["lemma"] } })

      # DPa (Darius I 69): the royal trilingual — one text, three versions;
      # every token keeps its honest per-word tag, the majority base subtag
      # (akk, 4 tokens vs 3 peo / 3 elx) is the per-text primary.
      tri = adapter.parse(refs["urn:nabu:oracc:ario:Q007203"])
      assert_equal "akk", tri.language
      token_langs = tri.flat_map { |p| p.annotations["tokens"].filter_map { |t| t["lang"] } }.uniq.sort
      assert_equal %w[akk elx peo], token_langs
    end

    def test_parse_reads_the_epsd2_corpora_as_sumerian
      adapter = Nabu::Adapters::Oracc.new
      refs = adapter.discover(EXPANSION).to_h { |ref| [ref.id, ref] }

      royal = adapter.parse(refs["urn:nabu:oracc:epsd2-royal:Q001016"])
      assert_equal "sux", royal.language
      assert_equal "ur-{d}nanše", royal.first.text

      literary = adapter.parse(refs["urn:nabu:oracc:epsd2-literary:Q000553"])
      assert_equal "sux", literary.language
      assert_equal 8, literary.size

      admin = adapter.parse(refs["urn:nabu:oracc:epsd2-admin-ur3:P133815"])
      assert_equal "sux", admin.language
      assert_equal "urn:nabu:oracc:epsd2-admin-ur3:P133815:o.1", admin.first.urn
      assert_equal "4(u) gur ša₃-gal uz", admin.first.text
    end

    def test_parse_skips_the_expansion_catalog_only_skeletons_by_rule
      adapter = Nabu::Adapters::Oracc.new
      refs = adapter.discover(EXPANSION).to_h { |ref| [ref.id, ref] }
      # P119709 (admin/ur3) is an EMPTY-cdl skeleton, P010246 (earlylit) an
      # object/surface skeleton with no transcribed lines — both upstream
      # catalog-only norms, skipped by rule, never quarantined.
      %w[urn:nabu:oracc:epsd2-admin-ur3:P119709 urn:nabu:oracc:epsd2-earlylit:P010246].each do |urn|
        error = assert_raises(Nabu::DocumentSkipped) { adapter.parse(refs[urn]) }
        assert_equal "catalog-only (no content)", error.reason
      end
    end

    def test_expansion_fixture_load_produces_peo_lemma_rows
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      source = Nabu::Store::Source.create(
        slug: "oracc", name: "ORACC", adapter_class: "Nabu::Adapters::Oracc", license_class: "open"
      )
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(Nabu::Adapters::Oracc.new, workdir: EXPANSION, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      lemmas = fulltext[:passage_lemmas]
      # Old Persian citation forms flow through the unchanged cf plumbing:
      # xšāyaθiya- "king" (DPd Persian 2, surface XŠ — the logogram).
      assert_operator lemmas.where(language: "peo").count, :>, 0
      row = lemmas.where(language: "peo", lemma_raw: "xšāyaθiya-").first
      refute_nil row, "expected a passage_lemmas row for the peo lemma xšāyaθiya-"
      assert_equal "urn:nabu:oracc:ario:Q007149:Persian.2", row[:urn]
      assert_includes row[:surface_forms], "XŠ"
      # The trilingual indexes under its PRIMARY language (the standing
      # per-passage rule — Sumerian year-names inside Akkadian rimanum
      # texts ride under akk the same way): adam "I" (DPa Persian 1) lands
      # as an akk row, its per-word peo tag intact in the annotations.
      adam = lemmas.where(lemma_raw: "adam").first
      refute_nil adam, "expected a passage_lemmas row for the lemma adam"
      assert_equal %w[akk urn:nabu:oracc:ario:Q007203:Persian.1], [adam[:language], adam[:urn]]
      # Elamite is honestly lemma-less (no gloss-elx upstream)…
      assert_equal 0, lemmas.where(language: "elx").count
      # …while the epsd2 corpora contribute Sumerian rows (šaggal "fodder",
      # P133815 o 1 — the Ur III administrative mass is gold-lemmatized).
      assert_operator lemmas.where(language: "sux").count, :>, 0
      sux_row = lemmas.where(language: "sux", lemma_raw: "šaggal").first
      refute_nil sux_row, "expected a passage_lemmas row for the sux lemma šaggal"
      assert_equal "urn:nabu:oracc:epsd2-admin-ur3:P133815:o.1", sux_row[:urn]
    ensure
      fulltext&.disconnect
    end

    # -- license (read per project, never hardcoded) --------------------------

    def test_discover_accepts_the_machine_read_cc0_license
      refute_empty conformance_adapter.discover(FIXTURES).to_a
    end

    def test_discover_stops_on_a_license_that_does_not_map_to_the_declared_class
      with_doctored_license("released under the CC BY-SA 3.0 license") do |workdir|
        error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(workdir).to_a }
        assert_match(/license/i, error.message)
        assert_match(/attribution/, error.message,
                     "the mapped class must be named so the mismatch is actionable")
      end
    end

    def test_discover_stops_on_an_unknown_license
      with_doctored_license("some novel license nobody vetted") do |workdir|
        error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(workdir).to_a }
        assert_match(/unrecognized license/i, error.message)
      end
    end

    # -- parse ----------------------------------------------------------------

    def test_parse_delegates_to_the_oracc_json_parser_with_title
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id.end_with?("P405432") }
      document = adapter.parse(ref)
      assert_equal "UF 10, 152 26", document.title
      assert_equal "akk", document.language
      assert_equal "2(BARIG) ZI₃ US₂ a-na GEŠBUN", document.first.text
    end

    def test_parse_routes_translation_refs_to_the_translation_parser
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id.end_with?("P224395-en") }
      document = adapter.parse(ref)
      assert_equal "eng", document.language
      assert_equal "attribution", document.license_override,
                   "the prose is CC BY-SA project content, not the JSON build's CC0"
      assert_equal "SAA 01 175 (English translation)", document.title
      assert_equal "urn:nabu:oracc:saao-saa01:P224395-en:o.1", document.first.urn
      assert_includes document.first.text, "To the king, my lord"
    end

    def test_loaded_translation_documents_carry_the_attribution_override
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "oracc", name: "ORACC", adapter_class: "Nabu::Adapters::Oracc", license_class: "open"
      )
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      translation = catalog[:documents].where(urn: "urn:nabu:oracc:saao-saa01:P224395-en").first
      assert_equal "attribution", translation.fetch(:license_override)
      tablet = catalog[:documents].where(urn: "urn:nabu:oracc:saao-saa01:P224395").first
      assert_nil tablet.fetch(:license_override), "tablets inherit the source's open class"
    end

    # -- lemma plumbing (cf → passage_lemmas via the shared Indexer) ----------

    def test_fixture_load_produces_lemma_rows_for_citation_forms
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      source = Nabu::Store::Source.create(
        slug: "oracc", name: "ORACC", adapter_class: "Nabu::Adapters::Oracc", license_class: "open"
      )
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      lemmas = fulltext[:passage_lemmas]
      assert_operator lemmas.where(language: "akk").count, :>, 0
      assert_operator lemmas.where(language: "sux").count, :>, 0

      # qēmu "flour" (P405432 o 1) folds diacritic-insensitively; the pristine
      # surface form rides along for readable hits.
      row = lemmas.where(lemma_folded: Nabu::Normalize.search_form("qēmu", language: "akk")).first
      refute_nil row, "expected a passage_lemmas row for cf qēmu"
      assert_equal "qēmu", row[:lemma_raw]
      assert_equal "urn:nabu:oracc:rimanum:P405432:o.1", row[:urn]
      assert_includes row[:surface_forms], "ZI₃"

      # end to end: lemma search finds the Akkadian citation form
      hits = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext).run("qemu")
      assert_equal ["urn:nabu:oracc:rimanum:P405432:o.1"], hits.map(&:urn)
    ensure
      fulltext&.disconnect
    end

    # -- translation-crawl scope (stage 2) -------------------------------------

    def test_translation_crawl_scope_is_the_full_project_list
      # P14-4 stage 2 (owner-approved 2026-07-12, "Full crawl"): the crawl
      # serves EVERY in-scope project — the metadata tr-en gate keeps the
      # zero-English catalog hubs (riao, ribo, dcclt/jena) provably inert,
      # so the full list is exact, and new upstream tr-en is picked up free.
      assert_equal Nabu::Adapters::Oracc::PROJECTS,
                   Nabu::Adapters::Oracc::TRANSLATION_PROJECTS
    end

    # -- fetch (HTTP zip, no network: WebMock-stubbed) ------------------------

    RIMANUM_URL = "https://oracc.museum.upenn.edu/json/rimanum.zip"
    ETCSRI_URL = "https://oracc.museum.upenn.edu/json/etcsri.zip"

    # The three projects with checked-in corpus fixtures (saao/saa01 with its
    # REAL nested zip root — saao-saa01/saa01/corpusjson, the P11-7 shape);
    # the remaining in-scope projects are stubbed with a metadata-only
    # envelope (no cdl fixtures invented, 0 ingestible texts, formats REMOVED
    # so the translation crawl has nothing to request there) so fetch's
    # per-project plumbing is exercised across the full list.
    FIXTURED_PROJECTS = %w[rimanum etcsri saao/saa01].freeze

    # The crawl endpoints for the saao/saa01 fixture (its trimmed metadata
    # formats.tr-en lists exactly these two): P224395 serves the real
    # fragment, P224485 the recorded soft-404 shape (a 200 whose body is a
    # literal "404\n" — how ORACC answers for a missing per-text page).
    SAA_HTML_URL = "https://oracc.museum.upenn.edu/saao/saa01/P224395/html"
    SAA_MISSING_URL = "https://oracc.museum.upenn.edu/saao/saa01/P224485/html"

    # The stage-2 crawl endpoints (P14-4): the two rimanum texts with real
    # checked-in fragments. The staged rimanum metadata is trimmed to exactly
    # these (see stub_project_zips), so the non-saao crawl path is exercised
    # against real fragment payloads.
    RIM_HTML_URLS = %w[
      https://oracc.museum.upenn.edu/rimanum/P405134/html
      https://oracc.museum.upenn.edu/rimanum/P405432/html
    ].freeze

    def test_fetch_downloads_and_unpacks_both_project_zips
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")

        report = conformance_adapter.fetch(workdir)

        assert File.file?(File.join(workdir, "rimanum", "metadata.json"))
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json"))
        assert File.file?(File.join(workdir, "etcsri", "corpusjson", "Q004151.json"))
        assert File.file?(File.join(workdir, "saao-saa01", "saa01", "corpusjson", "P224395.json")),
               "the subproject zip unpacks with its real nested root"
        assert_match(/\A\h{64}\z/, report.sha, "sha pins the (last) zip's sha256")
        assert_match(/rimanum=\h{12}/, report.notes)
        assert_match(/etcsri=\h{12}/, report.notes)
        assert_match(/1 catalog-only \(empty\)/, report.notes,
                     "the empty-corpusjson count is the honest sync note")
        # Translation crawl (stage 2: full project list): the translated
        # fragments land OUTSIDE the zip-managed trees; the soft-404 text is
        # counted missing, its non-page never written. rimanum (non-saao)
        # proves the stage-2 scope; the formats-less envelope projects and
        # the tr-en-emptied etcsri stay silent (nothing to crawl).
        assert File.file?(File.join(workdir, "html-en", "saao-saa01", "P224395.html"))
        refute File.exist?(File.join(workdir, "html-en", "saao-saa01", "P224485.html"))
        assert_match(/saao-saa01 html-en: 1 fetched, 0 cached, 1 missing/, report.notes)
        assert File.file?(File.join(workdir, "html-en", "rimanum", "P405432.html"))
        assert_match(/rimanum html-en: 2 fetched, 0 cached, 0 missing/, report.notes)
        refute_match(/etcsri html-en/, report.notes, "an empty tr-en list crawls nothing")
        # repos pins every in-scope project by its zip URL, subproject
        # slash-paths hyphen-flattened (saao/saa01 → saao-saa01.zip).
        assert_equal Nabu::Adapters::Oracc::PROJECTS.map { |project|
          "https://oracc.museum.upenn.edu/json/#{project.tr('/', '-')}.zip"
        }, report.repos.keys
      end
    end

    def test_fetch_is_a_no_op_on_304_not_modified
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        first = conformance_adapter.fetch(workdir)

        stub_request(:get, RIMANUM_URL)
          .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
          .to_return(status: 304)
        stub_request(:get, ETCSRI_URL)
          .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
          .to_return(status: 304)
        stub_request(:get, "#{Nabu::Adapters::Oracc::ZIP_BASE_URL}/saao-saa01.zip")
          .with(headers: { "If-Modified-Since" => LAST_MODIFIED })
          .to_return(status: 304)

        second = conformance_adapter.fetch(workdir)
        assert_equal first.sha, second.sha, "an unchanged upstream keeps the pinned sha"
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json"))
        # Crawl resumability: an unchanged build re-fetches only what is
        # MISSING locally — the already-crawled fragment is cached (one GET
        # across both fetches), the soft-404 text is honestly retried.
        assert_requested :get, SAA_HTML_URL, times: 1
        assert_requested :get, SAA_MISSING_URL, times: 2
        assert_match(/saao-saa01 html-en: 0 fetched, 1 cached, 1 missing/, second.notes)
        RIM_HTML_URLS.each { |url| assert_requested :get, url, times: 1 }
        assert_match(/rimanum html-en: 0 fetched, 2 cached, 0 missing/, second.notes)
      end
    end

    def test_fetch_recrawls_translations_when_the_project_zip_changed
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        conformance_adapter.fetch(workdir)
        # Same stubs (200 + same Last-Modified replayed): ZipFetch re-downloads
        # (no 304), so the build counts as changed and the crawl refreshes the
        # fragment even though it exists locally.
        conformance_adapter.fetch(workdir)
        assert_requested :get, SAA_HTML_URL, times: 2
      end
    end

    def test_fetch_wraps_a_crawl_http_failure_in_fetch_error
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        stub_request(:get, SAA_HTML_URL).to_return(status: 500)
        assert_raises(Nabu::FetchError) { conformance_adapter.fetch(File.join(root, "work")) }
      end
    end

    def test_fetch_attics_files_dropped_from_a_fresh_zip
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        adapter = conformance_adapter
        adapter.fetch(workdir)

        # Upstream drops a NON-ingestible file (metadata stays, catalogue
        # vanishes): no breaker (discover does not ingest catalogues), but the
        # retention contract still attics it.
        stub_project_zips(root, drop: "rimanum/catalogue.json")
        adapter.fetch(workdir)

        attic = File.join(workdir, ".attic", "rimanum", "catalogue.json")
        assert File.file?(attic), "the dropped file must be preserved in the attic"
        refute File.file?(File.join(workdir, "rimanum", "catalogue.json"))
        manifest = JSON.parse(File.read(File.join(workdir, ".attic", "rimanum", ".attic.json")))
        assert_match(/\A\h{64}\z/, manifest.fetch("catalogue.json"))
      end
    end

    def test_fetch_trips_the_mass_deletion_breaker_before_any_tree_change
      Dir.mktmpdir do |root|
        stub_project_zips(root)
        workdir = File.join(root, "work")
        adapter = conformance_adapter
        adapter.fetch(workdir)

        # Post-crawl the tree holds 8 ingestible documents (5 tablets + the
        # 3 crawled -en siblings); dropping 2 = 25% > the 20% threshold.
        stub_project_zips(root, drop: ["rimanum/corpusjson/P405432.json",
                                       "rimanum/corpusjson/P405134.json"])
        assert_raises(Nabu::SyncAborted) { adapter.fetch(workdir) }
        assert File.file?(File.join(workdir, "rimanum", "corpusjson", "P405432.json")),
               "a tripped breaker must leave the tree byte-unchanged"

        # --force proceeds: the text is atticked and rediscovered as retained.
        report = adapter.fetch(workdir, force: true)
        assert_match(/atticked/, report.notes)
        attic_ref = adapter.discover_with_attic(workdir)
                           .find { |ref| ref.id == "urn:nabu:oracc:rimanum:P405432" }
        refute_nil attic_ref, "the atticked text must be rediscovered"
        assert attic_ref.metadata["retained"]
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      Dir.mktmpdir do |root|
        stub_request(:get, RIMANUM_URL).to_return(status: 500)
        assert_raises(Nabu::FetchError) { conformance_adapter.fetch(File.join(root, "work")) }
      end
    end

    # -- helpers ---------------------------------------------------------------

    LAST_MODIFIED = "Fri, 28 Jun 2024 12:46:36 GMT"

    # Zip the checked-in fixture projects (real upstream payloads) into
    # <root>/zips and stub every project URL with the recorded response shape
    # (200, application/zip, Last-Modified), plus the two stage-1 crawl
    # endpoints. +drop+ omits entries (path(s) relative to the zips root),
    # simulating upstream deletions in the next build.
    def stub_project_zips(root, drop: [])
      drops = Array(drop)
      zips = File.join(root, "zips-#{drops.empty? ? 'full' : 'dropped'}")
      Nabu::Adapters::Oracc::PROJECTS.each do |project|
        slug = project.tr("/", "-")
        staging = File.join(zips, slug)
        FileUtils.mkdir_p(File.dirname(staging))
        if FIXTURED_PROJECTS.include?(project)
          FileUtils.cp_r(File.join(FIXTURES, slug), staging)
          trim_tr_en!(staging, slug)
        else
          stub_envelope_project(staging)
        end
        drops.each { |dropped| FileUtils.rm_f(File.join(zips, dropped)) if dropped.start_with?("#{slug}/") }
        zip_path = File.join(zips, "#{slug}.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, slug, chdir: zips)
        stub_request(:get, "#{Nabu::Adapters::Oracc::ZIP_BASE_URL}/#{slug}.zip").to_return(
          status: 200, body: File.binread(zip_path),
          headers: { "Content-Type" => "application/zip", "Last-Modified" => LAST_MODIFIED }
        )
      end
      stub_request(:get, SAA_HTML_URL).to_return(
        status: 200, body: File.binread(File.join(FIXTURES, "html-en", "saao-saa01", "P224395.html")),
        headers: { "Content-Type" => "text/html; charset=utf-8" }
      )
      stub_request(:get, SAA_MISSING_URL).to_return(
        status: 200, body: "404\n", headers: { "Content-Type" => "text/html; charset=utf-8" }
      )
      RIM_HTML_URLS.each do |url|
        stub_request(:get, url).to_return(
          status: 200, body: File.binread(File.join(FIXTURES, "html-en", "rimanum", "#{url.split('/')[-2]}.html")),
          headers: { "Content-Type" => "text/html; charset=utf-8" }
        )
      end
    end

    # Stage-2 crawl scope (the full project list) meets the checked-in
    # fixtures: the PRISTINE rimanum/etcsri metadata carry their real
    # 378/1448-id tr-en lists, which the crawl would request wholesale. Test
    # plumbing (the same discipline as stub_envelope_project): the STAGED
    # copy's tr-en is trimmed to the texts with checked-in fragments —
    # rimanum to its two, etcsri to none (no etcsri fragments; nothing
    # invented). The checked-in fixtures stay real upstream samples; saa01's
    # was already trimmed at snapshot (P13-4).
    def trim_tr_en!(staging, slug)
      trims = { "rimanum" => %w[P405134 P405432], "etcsri" => [] }
      return unless trims.key?(slug)

      path = File.join(staging, "metadata.json")
      metadata = JSON.parse(File.read(path))
      metadata["formats"]["tr-en"] = trims.fetch(slug)
      File.write(path, JSON.generate(metadata))
    end

    # No corpus fixture: ship only a real CC0 metadata.json (the license gate
    # the adapter reads) with its formats lists REMOVED — a valid, empty
    # project envelope with nothing for the translation crawl to request; no
    # cdl data invented.
    def stub_envelope_project(staging)
      FileUtils.mkdir_p(staging)
      metadata = JSON.parse(File.read(File.join(FIXTURES, "rimanum", "metadata.json")))
      metadata.delete("formats")
      File.write(File.join(staging, "metadata.json"), JSON.generate(metadata))
    end

    # A workdir whose rimanum metadata.json declares +license+ instead of CC0.
    def with_doctored_license(license)
      Dir.mktmpdir do |root|
        workdir = File.join(root, "work")
        FileUtils.mkdir_p(workdir)
        FileUtils.cp_r(File.join(FIXTURES, "rimanum"), File.join(workdir, "rimanum"))
        FileUtils.cp_r(File.join(FIXTURES, "etcsri"), File.join(workdir, "etcsri"))
        metadata_path = File.join(workdir, "rimanum", "metadata.json")
        metadata = JSON.parse(File.read(metadata_path))
        metadata["license"] = license
        File.write(metadata_path, JSON.generate(metadata))
        yield workdir
      end
    end
  end
end
