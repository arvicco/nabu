# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # tr-wikisource — the Orkhon inscriptions on Turkish Wikisource, under the
  # 2026-11-27 census. Fixture: the three admitted page envelopes (trimmed
  # real pages) and the rejected landing page, as the fetch writes them.
  class TrWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("tr-wikisource")
    KLASS = Nabu::Adapters::TrWikisource
    URN = "urn:nabu:tr-wikisource:"

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "tr-wikisource"

    def doc(key)
      @docs ||= {}
      @docs[key] ||= begin
        ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "#{URN}#{key}" } || flunk("#{key}?")
        conformance_adapter.parse(ref)
      end
    end

    def test_discovers_the_three_inscriptions
      assert_equal %w[kul-tigin bilge-kagan tonyukuk].map { |key| "#{URN}#{key}" },
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_the_landing_page_skips_by_rule_with_its_note
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_equal ["1 landing/disambiguation page(s) — navigation, no text of their own"], skips.notes
    end

    def test_an_uncensused_page_is_unrecognized_and_a_redirect_skips
      Dir.mktmpdir do |workdir|
        FileUtils.cp_r(File.join(FIXTURES, "pages"), workdir)
        landing = JSON.parse(File.read(File.join(workdir, "pages", "5338.json")))
        File.write(File.join(workdir, "pages", "9999.json"),
                   JSON.generate(landing.merge("pageid" => 9999, "title" => "Yeni Yazıt")))
        File.write(File.join(workdir, "pages", "17742.json"),
                   JSON.generate(landing.merge("pageid" => 17_742, "title" => "Orhun Abideleri (Kül Tigin)",
                                               "wikitext" => "#YÖNLENDİRME [[Orhun Yazıtları (Kül Tigin)]]")))
        skips = conformance_adapter.discovery_skips(workdir)
        assert_equal 1, skips.unrecognized
        assert_equal 2, skips.skipped_by_rule, "the landing page + the redirect"
        assert_includes skips.notes, "uncensused page: Yeni Yazıt (9999)"
        assert_includes skips.notes, "1 redirect page(s)"
        assert_equal 3, conformance_adapter.discover(workdir).count
      end
    end

    def test_the_census_tables
      assert_equal [5093, 5095, 5096], KLASS::WORK_BY_PAGE.keys
      assert_empty KLASS::WORK_BY_PAGE.keys & KLASS::REJECTED.keys
    end

    def test_passages_are_runiform_lines_cited_by_upstreams_own_numbering
      kt = doc("kul-tigin")
      assert_equal "otk", kt.language
      assert_equal(%w[G1 G2 KD1], kt.passages.map { |p| p.urn.delete_prefix("#{URN}kul-tigin:") })
      assert(kt.passages.all? { |p| p.language == "otk" && p.annotations["script"] == "Orkh" })
      assert_equal(%w[1-B1 1-B2 2-B1], doc("tonyukuk").passages.map { |p| p.urn.split(":").last })
    end

    # The NFC/encoding regression: real runiform bytes (Kül Tigin G1 opens
    # 𐱅𐰭𐰼𐰃 "teŋri" — U+10C45 U+10C2D U+10C3C U+10C03, astral, 4 bytes each)
    # survive the adapter boundary byte for byte.
    def test_runiform_bytes_are_pinned
      text = doc("kul-tigin").passages.first.text
      assert_equal [0x10C45, 0x10C2D, 0x10C3C, 0x10C03, 0x3A], text.codepoints.first(5)
      assert_equal "\xF0\x90\xB1\x85".b, text.b[0, 4]
      assert text.unicode_normalized?(:nfc)
    end

    def test_the_three_wiki_layers_ride_annotations
      g1 = doc("kul-tigin").passages.first
      assert_equal "kt-1-g-13-01", g1.annotations["row_id"]
      assert_equal "Güney Yüzü", g1.annotations["face"]
      assert g1.annotations["transliteration"].start_with?("tHri: tg: tHride:")
      assert g1.annotations["transcription"].start_with?("TeŊRİ: TeG: TeŊRİDE:")
      assert g1.annotations["translation"].start_with?("Tanrı gibi gökte olmuş Türk Bilge Kağan")
      assert_equal "tur", g1.annotations["translation_language"]
      assert_equal "Birinci Taş", doc("tonyukuk").passages.first.annotations["stone"]
      assert_equal [["translation", g1.annotations["translation"]]],
                   Nabu::TranslationKeys.layers(g1.annotations, Nabu::TranslationKeys.specs_for("tr-wikisource"))
      assert_equal [["transcription", g1.annotations["transcription"]]],
                   Nabu::AnnotationKeys.layers(g1.annotations, Nabu::AnnotationKeys.specs_for("tr-wikisource"))
    end

    def test_a_row_without_runiform_keeps_the_lacuna_marker_and_says_so
      b7, b8, b9, gb1 = doc("bilge-kagan").passages
      [b8, b9].each do |row|
        assert_equal "[...]:", row.text
        assert_equal %w[lacuna none], row.annotations.values_at("text_layer", "script")
      end
      assert_nil b7.annotations["text_layer"]
      assert_equal "Orkh", gb1.annotations["script"]
      assert_empty Nabu::TranslationKeys.layers(b8.annotations, Nabu::TranslationKeys.specs_for("tr-wikisource")),
                   "a letterless '[...]' translation mints nothing"
    end

    def test_work_metadata_carries_the_census_facts
      meta = doc("kul-tigin").metadata
      assert_equal "kul-tigin", meta["work"]
      assert_equal [732, 732], meta["date"].values_at("not_before", "not_after")
      refute meta["date"].key?("class"), "the stone's own date line — an artifact date"
      assert_includes meta["date"]["raw"], "biçin (monkey) year"
      assert_equal "Khöshöö Tsaidam, Orkhon valley (Mongolia)", meta["place"]
      assert_equal({ "genre" => { "value" => "royal memorial inscription" } }, meta["facets"])
      assert_includes meta["bibliography"].last, "Tekin, Talat (1995). Orhon Yazıtları"
      assert_equal({ "face" => "Güney Yüzü", "caption" => "Kül Tigin taşı, 1. yüz (güney) 13 dizi",
                     "declared_lines" => 13, "lines" => 2 }, meta["faces"].first)
      tonyukuk = doc("tonyukuk").metadata["date"]
      assert_equal [716, 726, "composition"], tonyukuk.values_at("not_before", "not_after", "class")
      assert_includes tonyukuk["raw"], "ATTRIBUTED"
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["tr-wikisource"]
    end

    def test_manifest_is_attribution_cc_by_sa
      manifest = KLASS.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "Creative Commons Atıf-BenzerPaylaşım Lisansı"
      assert_equal "orkhon-wikisource", manifest.parser_family
      assert_equal :http_zip, KLASS.remote_probe_strategy
    end

    def test_registry_row_is_registered_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
      entry = registry["tr-wikisource"]
      refute_nil entry
      assert entry.wired, "wired after the verified first sync"
      assert_equal "manual", entry.sync_policy
      assert_equal ["turkic"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "tr-wikisource", name: "tr ws", adapter_class: KLASS.name,
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 3, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def info_payload(pageids)
      pages = pageids.to_h do |id|
        e = envelope(id)
        [id.to_s, { "pageid" => id, "ns" => e["ns"], "title" => e["title"], "lastrevid" => e["revid"] }]
      end
      JSON.generate("batchcomplete" => "", "query" => { "pages" => pages })
    end

    def revisions_payload(pageids)
      pages = pageids.to_h do |id|
        e = envelope(id)
        [id.to_s, { "pageid" => id, "ns" => e["ns"], "title" => e["title"],
                    "categories" => e["categories"].map { |title| { "ns" => 14, "title" => title } },
                    "revisions" => [{ "revid" => e["revid"], "timestamp" => e["timestamp"],
                                      "slots" => { "main" => { "*" => e["wikitext"] } } }] }]
      end
      JSON.generate("query" => { "pages" => pages })
    end

    def test_fetch_lands_the_category_and_the_landing_page_and_skips_unchanged_pages
      stub_request(:get, KLASS::API_URL).with(query: hash_including("gcmtitle" => KLASS::CATEGORY))
                                        .to_return(status: 200, body: info_payload([5093, 5095, 5096]))
      stub_request(:get, KLASS::API_URL).with(query: hash_including("prop" => "info", "titles" => "Orhun Yazıtları"))
                                        .to_return(status: 200, body: info_payload([5338]))
      content = stub_request(:get, KLASS::API_URL).with(query: hash_including("prop" => "revisions|categories"))
                                                  .to_return(status: 200,
                                                             body: revisions_payload([5093, 5095, 5096, 5338]))
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0).fetch(workdir)
        assert_includes report.notes, "pages: 4 fetched, 0 cached"
        held = JSON.parse(File.read(File.join(workdir, "pages", "5093.json")))
        assert_equal ["Kategori:Orhun Abideleri"], held["categories"]
        assert_equal envelope(5093)["wikitext"], held["wikitext"]
        assert_equal 3, KLASS.new(delay: 0).discover(workdir).count
        second = KLASS.new(delay: 0).fetch(workdir)
        assert_includes second.notes, "pages: 0 fetched, 4 cached"
        assert_equal report.sha, second.sha
        assert_requested content, times: 1
      end
    end
  end
end
