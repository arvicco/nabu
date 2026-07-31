# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"
require "json"

module Adapters
  # Nabu::Adapters::Rsti (P55-2): conformance + source specifics over trimmed
  # real API responses (see test/fixtures/rsti/README.md). The corpus verdict
  # the fixture mirrors: INVENTORY-FIRST, text exceptional — most documents
  # are zero-passage metadata records; RS 1.001 is the one witnessed full
  # edition (four parallel renderings), RS 1.004 the shell, RS 1.003+ the
  # {"result":[]} tombstone.
  class RstiTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("rsti")
    SEASON01 = "2a414954-e077-496b-8b06-a9d0cd417eba"
    RAS_IBN_HANI = "a7a3a86e-8cdb-4ea9-92fe-6dc31d07dcbc"

    def conformance_adapter
      Nabu::Adapters::Rsti.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "rsti"
    end

    # ~99% of the corpus: inventory records with no published text — honest
    # zero-passage metadata documents (the ebl/local-library precedent).
    def conformance_metadata_only?(document)
      document.metadata["text_layer"] == "none"
    end

    def adapter = conformance_adapter

    def refs
      adapter.discover(FIXTURES).to_a
    end

    def parse(urn)
      ref = refs.find { |r| r.id == urn }
      refute_nil ref, "no ref #{urn}"
      adapter.parse(ref)
    end

    # -- manifest: the granted nc posture -------------------------------------

    def test_manifest_is_nc_with_the_grant_and_the_teo_credit_verbatim
      manifest = Nabu::Adapters::Rsti.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "CC BY-NC-SA 4.0"
      assert_includes manifest.license, "№23",
                      "the granted basis (Miller Prosser, U. Chicago CORPUS/OCHRE, 2026-07-27) must ride verbatim"
      assert_includes manifest.license, "Bordreuil and Pardee (1989)",
                      "the menu-level availability credit must ride verbatim"
      assert_equal "ochre-json", manifest.parser_family
      assert_includes manifest.credit, "Ras Shamra Tablet Inventory",
                      "attribution is a grant condition — the credit seam must render it"
    end

    # -- THE urn slugging rule, pinned on every witnessed label shape ---------
    # NFC, strip, lowercase, whitespace runs → "-", every other character
    # (. + / [ ] ,) verbatim — minimal transformation (the ebl precedent),
    # collision-safe: "RS 74.[001]" can never collide with a plain
    # "RS 74.001", brackets and join marks stay distinct.

    def test_urn_slugging_is_pinned_on_the_witnessed_label_variants
      {
        "RS 1.001" => "urn:nabu:rsti:rs-1.001",
        "RS 1.009 [A]" => "urn:nabu:rsti:rs-1.009-[a]",
        "RS 1.003+" => "urn:nabu:rsti:rs-1.003+",
        "RS 74.[001]" => "urn:nabu:rsti:rs-74.[001]",
        "RIH 77/02A+" => "urn:nabu:rsti:rih-77/02a+",
        "RIH 84/ [31,10]" => "urn:nabu:rsti:rih-84/-[31,10]"
      }.each do |label, urn|
        assert_equal urn, Nabu::Adapters::Rsti.urn_for(label)
      end
    end

    # -- discovery ------------------------------------------------------------

    def test_discover_yields_one_ref_per_inventory_record_sorted_by_urn
      all = refs
      assert_equal ["urn:nabu:rsti:rih-77/01",
                    "urn:nabu:rsti:rih-84/-[31,10]",
                    "urn:nabu:rsti:rs-1.001",
                    "urn:nabu:rsti:rs-1.003+",
                    "urn:nabu:rsti:rs-1.004",
                    "urn:nabu:rsti:rs-1.009-[a]",
                    "urn:nabu:rsti:rs-17.009"], all.map(&:id)
      assert(all.all? { |r| File.dirname(r.path).end_with?("sets") })
      assert_predicate adapter.discovery_skips(FIXTURES), :clean?
    end

    def test_discover_of_an_unfetched_workdir_yields_nothing
      Dir.mktmpdir do |dir|
        assert_empty Nabu::Adapters::Rsti.new.discover(dir).to_a
      end
    end

    # The menu's "Season 1-11" style aggregate sets may re-list records the
    # per-season sets already carry: a urn seen in an earlier set file wins,
    # the duplicate is censused, never an error (the ebl first-wins rule).
    def test_a_record_duplicated_across_set_files_is_first_wins_and_censused
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "sets"))
        source = File.join(FIXTURES, "sets", "#{SEASON01}.json")
        FileUtils.cp(source, File.join(dir, "sets", "#{SEASON01}.json"))
        FileUtils.cp(source, File.join(dir, "sets", "ffffffff-aaaa-bbbb-cccc-000000000000.json"))
        fresh = Nabu::Adapters::Rsti.new
        assert_equal 5, fresh.discover(dir).to_a.size, "each record once, first set file wins"
        skips = fresh.discovery_skips(dir)
        assert_equal 5, skips.skipped_by_rule
        assert_predicate skips, :clean?
      end
    end

    # -- the full edition: RS 1.001 -------------------------------------------

    def test_rs_1_001_parses_to_line_passages_per_surface
      document = parse("urn:nabu:rsti:rs-1.001")
      assert_equal "uga", document.language
      assert_equal "Ritual for a day and a night", document.title
      assert_equal 22, document.size, "17 Recto + 2 Lower edge + 3 Verso lines"
      assert_equal "edition", document.metadata["text_status"]
      refute document.metadata.key?("text_layer")
      first = document.passages.fetch(0)
      assert_equal "urn:nabu:rsti:rs-1.001:recto.1", first.urn
      assert_equal "dqt . ṯʿ . ynt . ṯʿm . dqt . ṯʿm", first.text
      assert_equal "Recto", first.annotations["surface"]
      assert_equal "1", first.annotations["line"]
      urns = document.map(&:urn)
      assert_includes urns, "urn:nabu:rsti:rs-1.001:lower-edge.18"
      assert_includes urns, "urn:nabu:rsti:rs-1.001:verso.22"
    end

    def test_rs_1_001_lines_carry_the_parallel_renderings_as_annotations
      document = parse("urn:nabu:rsti:rs-1.001")
      first = document.passages.fetch(0)
      assert_equal "dqt ṯʿ yônatu ṯʿm dqt ṯʿm", first.annotations["phonemic"]
      # The graphemic entity-decode regression: literal "&#x10384;…" strings
      # become real U+10380-block codepoints, never entity text.
      assert first.annotations["graphemic"].start_with?("\u{10384}\u{10396}\u{1039A}")
      refute_includes first.annotations["graphemic"], "&#x"
      assert_equal 17, first.annotations["graphemic"].each_char.count
      assert_equal [".", ".", ".", ".", "."], first.annotations["graphemic_marks"]
      refute first.annotations.key?("translation"), "RS 1.001's translation rendering is {} upstream"
      last = document.passages.fetch(21)
      assert_equal "l ı͗nš ı͗lm", last.text
      refute last.annotations.key?("graphemic_marks"), "Verso 22 ships supplementary only"
    end

    def test_rs_1_001_metadata_carries_the_inventory_record_and_concordances
      document = parse("urn:nabu:rsti:rs-1.001")
      metadata = document.metadata
      assert_equal "RS 1.001", metadata["rs_label"]
      assert_equal ["CTA 34", "KTU 1.39", "RSO XII 1", "UT 1"], metadata["concordances"],
                   "the KTU/CTA/RSO/UT aliases are the interop keys Ugaritologists actually use"
      assert_equal "Tablet, Alphabetic Ugaritic", metadata["description"]
      assert_equal "Tablet", metadata["object_type"]
      assert_equal "M8214 = A2714 (AO 12.015)", metadata["museum_number"]
      assert_equal "Acropole, Maison du Gr. Prêtre «nid de tablettes» (= p.t. 300)",
                   metadata["findspot"], "the French findspot rides verbatim, NBSP included"
      assert_equal "Alphabetic", metadata["script"]
      assert_equal ["Ugaritic"], metadata["languages"]
      assert_equal "110 x 140 x 35", metadata["size"]
      assert_equal "TEO Season 01", metadata["set"]
      assert_equal "Ritual", metadata["genre"]
      assert_equal "alphabetic", metadata["text_type"]
      assert_equal "de32293f-9b4b-435e-bf02-c4894863035b", metadata["text_uuid"]
    end

    # -- the three no-text shapes ---------------------------------------------

    def test_the_tombstone_is_a_metadata_document_not_an_error
      document = parse("urn:nabu:rsti:rs-1.003+")
      assert_equal 0, document.size
      assert_equal "none", document.metadata["text_layer"]
      assert_equal "unpublished", document.metadata["text_status"]
      assert_equal "uga", document.language, "record-side Language property when no text item"
      assert_equal ["CTA 35", "KTU 1.41", "RSO XII 3", "UT 3"], document.metadata["concordances"]
      assert_equal ["RS 1.003+2.[005]"], document.metadata["aliases"]
      assert_equal "Sacrificial list for the month of Raʾšu-yêni", document.title
    end

    def test_the_shell_resolves_but_yields_no_passages
      document = parse("urn:nabu:rsti:rs-1.004")
      assert_equal 0, document.size
      assert_equal "none", document.metadata["text_layer"]
      assert_equal "shell", document.metadata["text_status"]
      assert_equal "xhu", document.language, "the text item's own language field (Hurrian) governs"
      assert_equal ["CTA 166", "KTU 1.42", "UT 4"], document.metadata["concordances"]
    end

    def test_an_unfetched_text_detail_is_an_unfetched_metadata_document
      document = parse("urn:nabu:rsti:rs-1.009-[a]")
      assert_equal 0, document.size
      assert_equal "unfetched", document.metadata["text_status"]
      assert_equal "Small fragment with ritual vocabulary", document.title
    end

    def test_an_empty_dict_associated_uuid_is_a_no_text_metadata_document
      document = parse("urn:nabu:rsti:rs-17.009")
      assert_equal 0, document.size
      assert_equal "no-text", document.metadata["text_status"],
                   "associated_uuid: {} (the XML self-closing form, witnessed live on Season 17 " \
                   "at first real sync 2026-07-31) means NO text record exists upstream — " \
                   "distinct from an unfetched one; a resync must not chase it"
    end

    def test_the_empty_description_dict_never_becomes_a_metadata_key
      document = parse("urn:nabu:rsti:rih-77/01")
      refute document.metadata.key?("description"), "RIH 77/01 ships description: {}"
      assert_equal "Un serviteur s’adresse à son maître le roi", document.title
      assert_equal "uga", document.language
      assert_equal ["KTU 2.77"], document.metadata["concordances"]
    end

    # -- language honesty -----------------------------------------------------

    def test_the_language_map_covers_the_witnessed_vocabulary_and_stops_loud_on_unknown
      { "Ugaritic" => "uga", "Akkadian" => "akk", "Hurrian" => "xhu", "Sumerian" => "sux",
        "Egyptian" => "egy", "Hittite" => "hit", "Latin" => "lat", "Phoenician" => "phn",
        "Cypro-Minoan" => "und" }.each do |name, code|
        assert_equal code, Nabu::Adapters::Rsti.language_code!(name, context: "test")
      end
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::Rsti.language_code!("Greek", context: "RS 0.000")
      end
      assert_match(/unknown RSTI language/, error.message)
    end

    def test_document_language_falls_back_honestly
      assert_equal "und", Nabu::Adapters::Rsti.document_language([], context: "test"),
                   "121 sampled records carry NO Language property — und, never a guess"
      assert_equal "xhu", Nabu::Adapters::Rsti.document_language(%w[Hurrian Ugaritic], context: "test"),
                   "multi-language records take the first listed; the full list rides metadata"
    end

    # -- fetch (WebMock; no network ever) -------------------------------------

    def stub_crawl
      menu = JSON.parse(File.read(File.join(FIXTURES, "menu.json")))
      keep = [SEASON01, RAS_IBN_HANI]
      menu["ochre"]["set"]["items"]["set"].select! { |s| keep.include?(s["uuid"]) }
      stub_request(:get, Nabu::OchreFetch.item_url(Nabu::Adapters::Rsti::MENU_UUID))
        .to_return(status: 200, body: JSON.generate(menu))
      keep.each do |uuid|
        stub_request(:get, Nabu::OchreFetch.item_url(uuid))
          .to_return(status: 200, body: File.read(File.join(FIXTURES, "sets", "#{uuid}.json")))
      end
      tombstone = File.read(File.join(FIXTURES, "texts", "223fa8f2-a5a6-47b0-9f82-80b159c1e23c.json"))
      text_uuids.each do |uuid|
        fixture = File.join(FIXTURES, "texts", "#{uuid}.json")
        body = File.file?(fixture) ? File.read(fixture) : tombstone
        stub_request(:get, Nabu::OchreFetch.item_url(uuid)).to_return(status: 200, body: body)
      end
    end

    def text_uuids
      %w[de32293f-9b4b-435e-bf02-c4894863035b 223fa8f2-a5a6-47b0-9f82-80b159c1e23c
         3e80daf3-a394-4a0e-9f00-dd76392b3834 b8e6a1c9-d0f5-4576-aab6-3b96905fe5ba
         e8e93bf6-c133-410c-9be2-9827d0db913c c033b607-489b-42bf-8b10-931ebc6c7404]
    end

    def test_fetch_stages_menu_sets_then_text_details_and_persists_tombstones
      stub_crawl
      Dir.mktmpdir do |dir|
        report = Nabu::Adapters::Rsti.new(delay: 0).fetch(dir)
        assert File.file?(File.join(dir, "menu.json"))
        assert_equal 2, Dir.children(File.join(dir, "sets")).size
        assert_equal 6, Dir.children(File.join(dir, "texts")).size
        assert_equal '{"result":[]}',
                     File.read(File.join(dir, "texts", "b8e6a1c9-d0f5-4576-aab6-3b96905fe5ba.json")),
                     "the API's not-published answer is PERSISTED as-is — a tombstone, never an error"
        assert_match(/6 text details fetched/, report.notes)
        assert_equal 7, Nabu::Adapters::Rsti.new.discover(dir).to_a.size
      end
    end

    def test_fetch_resumes_text_details_already_on_disk
      stub_crawl
      Dir.mktmpdir do |dir|
        Nabu::Adapters::Rsti.new(delay: 0).fetch(dir)
        report = Nabu::Adapters::Rsti.new(delay: 0).fetch(dir)
        assert_match(/0 text details fetched, 6 already present/, report.notes)
        text_uuids.each do |uuid|
          assert_requested :get, Nabu::OchreFetch.item_url(uuid), times: 1
        end
        assert_requested :get, Nabu::OchreFetch.item_url(Nabu::Adapters::Rsti::MENU_UUID), times: 2
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, Nabu::OchreFetch.item_url(Nabu::Adapters::Rsti::MENU_UUID))
        .to_return(status: 500)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::Rsti.new(delay: 0).fetch(dir) }
      end
    end

    # -- remote-health probe shape --------------------------------------------

    def test_remote_probe_heads_the_menu_resolver
      assert_equal :http_zip, Nabu::Adapters::Rsti.remote_probe_strategy
      target = Nabu::Adapters::Rsti.http_probe_targets.fetch(0)
      assert_equal Nabu::OchreFetch.item_url(Nabu::Adapters::Rsti::MENU_UUID), target.zip_url
      assert_nil target.metadata_url
      assert_equal Nabu::OchreFetch::STATE_FILE, target.state_file
    end
  end
end
