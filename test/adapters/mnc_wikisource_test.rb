# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # mnc-wikisource — the Manchu texts on Multilingual Wikisource, under the
  # 2026-11-08 provenance census. Fixture: thirteen real page envelopes as
  # the fetch writes them (pages/<pageid>.json) — seven admitted pages
  # (Nerchinsk, a Kangxi poem, Lunyu ch. 1, 清文啓蒙 juan 1, the Manchu
  # Sunzi, 清語老乞大 juan 1, MYK juan 2) and one specimen of every
  # rejected class (modern, landing, unattested, out-of-lect,
  # other-namespace — the last twice-categorized).
  class MncWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("mnc-wikisource")
    KLASS = Nabu::Adapters::MncWikisource
    URN = "urn:nabu:mnc-wikisource:"
    ADMITTED = [64_127, 64_132, 84_446, 152_894, 153_207, 168_826, 260_168].freeze

    def conformance_adapter = KLASS.new(delay: 0)
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "mnc-wikisource"

    def doc(pageid)
      @docs ||= {}
      @docs[pageid] ||= begin
        ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "#{URN}#{pageid}" } || flunk("#{pageid}?")
        conformance_adapter.parse(ref)
      end
    end

    def test_discovers_exactly_the_admitted_census_pages
      assert_equal(ADMITTED.map { |id| "#{URN}#{id}" }, conformance_adapter.discover(FIXTURES).map(&:id))
    end

    def test_every_rejected_class_skips_by_rule_with_its_note
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 6, skips.skipped_by_rule, "modern, landing, unattested, out-of-lect, 2 other-namespace"
      assert_equal 0, skips.unrecognized
      assert_includes skips.notes, "1 modern composition(s) — not texts of the period"
      assert_includes skips.notes, "1 Sibe-orthography page(s) (lang=sjo) — not Manchu"
      assert_includes skips.notes,
                      "2 non-main-namespace member(s) (Index/Page/Template/Category/Wikisource)"
    end

    def test_an_uncensused_main_namespace_page_is_unrecognized
      Dir.mktmpdir do |workdir|
        FileUtils.cp_r(File.join(FIXTURES, "pages"), workdir)
        envelope = JSON.parse(File.read(File.join(workdir, "pages", "64129.json")))
        envelope["pageid"] = 999_999
        File.write(File.join(workdir, "pages", "999999.json"), JSON.generate(envelope))
        skips = conformance_adapter.discovery_skips(workdir)
        assert_equal 1, skips.unrecognized
        assert_includes skips.notes, "uncensused page: Usiha be toloro jui (999999)"
        refute_includes conformance_adapter.discover(workdir).map(&:id), "#{URN}999999"
      end
    end

    def test_census_tables_are_disjoint_and_cover_every_census_page
      admitted = KLASS::WORK_BY_PAGE.keys
      assert_equal 21, admitted.size, "21 admitted pages"
      assert_equal 13, KLASS::WORKS.size, "13 works"
      assert_equal 13, KLASS::REJECTED.size
      assert_empty admitted & KLASS::REJECTED.keys
      assert_equal 34, admitted.size + KLASS::REJECTED.size, "the 34 main-namespace member pages"
    end

    def test_passages_claim_mnc_and_the_works_chinese_layer
      lunyu = doc(64_127)
      assert_equal "mnc", lunyu.language
      first, second = lunyu.passages.first(2)
      assert_equal %w[mnc Latn], [first.language, first.annotations["script"]]
      assert_equal %w[lzh Hani], [second.language, second.annotations["script"]]
      cwkm = doc(152_894)
      assert_includes cwkm.passages.map(&:language), "zho", "清文啓蒙's Qing vernacular glosses"
      assert(doc(84_446).passages.all? { |p| p.language == "mnc" && p.annotations["script"] == "Mong" })
    end

    def test_the_sunzi_starts_at_the_text_dropping_the_bibliographic_lines
      sunzi = doc(153_207)
      assert sunzi.passages.first.text.start_with?("(263) sun dz i coohai doro bithe.")
      assert_includes sunzi.metadata["base_edition"], "Sino-Platonic Papers 178"
    end

    def test_work_metadata_carries_the_census_facts
      meta = doc(168_826).metadata
      assert_equal "nibcu-i-boji-bithe", meta["work"]
      assert_equal({ "not_before" => 1689, "not_after" => 1689, "class" => "composition",
                     "raw" => "1689 (elhe taifin i orin jakūci aniya — Kangxi 28 — the text's own date line)" },
                   meta["date"])
      assert_equal({ "genre" => { "value" => "treaty" } }, meta["facets"])
      assert_equal "Fyodor Alexeyevich Golovin, Songgotu", meta["wiki_author"]
      myk = doc(260_168).metadata
      assert_equal [2, 4], [myk["page_part"], myk["work_pages"]]
      assert_includes myk["base_edition"], "依照中華書局影印本"
    end

    def test_the_long_myk_juan_reads_at_sentence_grain
      myk = doc(260_168)
      assert_operator myk.passages.size, :>, 100
      assert(myk.passages.all? { |p| p.language == "mnc" })
    end

    def test_scripts_helper
      assert_equal "Mong+Hani", KLASS.scripts("ᠰᠠᡳᠶᡡᠨ字念薩衣切雍。")
      assert_equal "Latn", KLASS.scripts("elhe taifin")
    end

    def test_the_metadata_dates_lane_reads_the_structured_shape
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["mnc-wikisource"]
    end

    def test_manifest_is_attribution_cc_by_sa
      manifest = KLASS.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "Creative Commons Attribution-ShareAlike License"
      assert_equal "manchu-wikisource", manifest.parser_family
    end

    def test_registry_row_is_registered_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["mnc-wikisource"]
      refute_nil entry
      assert entry.wired, "flipped live after the verified first sync (P164)"
      assert_equal "manual", entry.sync_policy
      assert_equal ["mongolic"], entry.axes
    end

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "mnc-wikisource", name: "mnc ws", adapter_class: KLASS.name,
                                          license_class: "attribution")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 7, first.added
      passages = db[:passages].count
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 7, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only) ------------------------------------------------

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def members_payload(pageids)
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
                    "revisions" => [{ "revid" => e["revid"], "timestamp" => e["timestamp"],
                                      "slots" => { "main" => { "*" => e["wikitext"] } } }] }]
      end
      JSON.generate("query" => { "pages" => pages })
    end

    def test_fetch_lands_pageid_envelopes_and_skips_unchanged_pages
      members = { "ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ" => [168_826, 64_120], "Manchu" => [64_120], KLASS::CATEGORIES.last => [] }
      members.each do |category, ids|
        stub_request(:get, KLASS::API_URL).with(query: hash_including("gcmtitle" => "Category:#{category}"))
                                          .to_return(status: 200, body: members_payload(ids))
      end
      content = stub_request(:get, KLASS::API_URL).with(query: hash_including("prop" => "revisions"))
                                                  .to_return(status: 200, body: revisions_payload([168_826, 64_120]))
      Dir.mktmpdir do |workdir|
        report = KLASS.new(delay: 0).fetch(workdir)
        assert_includes report.notes, "pages: 2 fetched, 0 cached (2 members across 3 categories)"
        held = JSON.parse(File.read(File.join(workdir, "pages", "64120.json")))
        assert_equal ["Manchu", "ᠮᠠᠨᠵᡠ ᡤᡳᠰᡠᠨ"], held["categories"]
        second = KLASS.new(delay: 0).fetch(workdir)
        assert_includes second.notes, "pages: 0 fetched, 2 cached"
        assert_equal report.sha, second.sha
        assert_requested content, times: 1
      end
    end

    def test_title_batches_respect_the_encoded_byte_cap
      titles = Array.new(40) { |i| "ᠮᠠᠨᠵᡠ ᡳ ᠶᠠᡵᡤᡳᠶᠠᠨ ᡴᠣᠣᠯᡳ/#{i}" }
      batches = KLASS.new(delay: 0).title_batches(titles)
      assert_operator batches.size, :>, 1
      assert_equal titles, batches.flatten
      assert(batches.all? { |b| b.sum { |t| URI.encode_www_form_component(t).bytesize + 3 } <= 5_000 })
    end
  end
end
