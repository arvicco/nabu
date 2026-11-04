# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # ninjal-textdb — NINJAL's Text Data Sets for Research on the History of
  # Japanese, the Kirishitan slice: the Amakusa Feiqe (1592), the Amakusa
  # Esopo (1593) and the HAB Contemptus Mundi (1596) as passage documents
  # (document = work volume, passage = the print's line, cited page.line),
  # plus the Nippo Jisho (1603) entry-word data as the dictionary lane.
  # Fixtures: trimmed real files per layer shape (README.md there).
  class NinjalTextdbTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ninjal-textdb")
    Adapter = Nabu::Adapters::NinjalTextdb
    URN = "urn:nabu:ninjal-textdb"

    def conformance_adapter = Adapter.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ninjal-textdb"

    # The documented search-form derivation: long ſ folds to s before the
    # per-language fold (the class note), recomputable from the text alone.
    def conformance_search_source(passage) = passage.text.tr("ſ", "s")

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    def passage(stem, cite)
      doc(stem).passages.find { |p| p.urn == "#{URN}:#{stem}:#{cite}" } || flunk("#{stem}:#{cite} missing")
    end

    # The fixture dir minus its README/manifest — the tree as it lands.
    def landed_tree
      Dir.mktmpdir do |dir|
        Dir.glob("*/**/*.txt", base: FIXTURES).each do |rel|
          FileUtils.mkdir_p(File.join(dir, File.dirname(rel)))
          FileUtils.cp(File.join(FIXTURES, rel), File.join(dir, rel))
        end
        yield dir
      end
    end

    # -- discovery -------------------------------------------------------------

    def test_discovers_the_three_kirishitan_texts
      assert_equal %w[amhk-001 amis-001 cmhab-001].map { |s| "#{URN}:#{s}" },
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_the_census_takes_exactly_the_kirishitan_slice
      census = Adapter::DATASETS
      assert_equal 24, census.size, "the 24 dataset directories the index links (2026-11-04)"
      assert_equal %w[amhk amis cmhab nipp], census.select(&:taken?).map(&:dir)
      assert(census.reject(&:taken?).all? { |set| set.reason.to_s.strip != "" })
    end

    def test_rejected_grains_and_out_of_slice_sets_skip_by_rule
      landed_tree do |dir|
        File.write(File.join(dir, "nipp", "ew-nippo-202510.xlsx"), "")
        File.write(File.join(dir, "nipp", Nabu::ZipFetch::STATE_FILE), "{}")
        skips = conformance_adapter.discovery_skips(dir)
        assert skips.clean?, skips.notes.join("\n")
        assert_equal 20 + 4, skips.skipped_by_rule, "20 out-of-slice sets + rk + readme + xlsx + state pin"
        assert(skips.notes.any? { |n| n.start_with?("amhk-rk-001.txt:") })
        assert(skips.notes.any? { |n| n.start_with?("brsk:") })
      end
    end

    def test_an_unknown_file_is_unrecognized
      landed_tree do |dir|
        File.write(File.join(dir, "amhk", "notes.txt"), "?")
        refute conformance_adapter.discovery_skips(dir).clean?
      end
    end

    # -- passages ----------------------------------------------------------------

    def test_passages_are_lines_cited_page_dot_line
      assert_equal 128, doc("amhk-001").size
      assert_equal 46, doc("amis-001").size
      assert_equal 107, doc("cmhab-001").size
      assert_equal "#{URN}:amhk-001:tobira.1", doc("amhk-001").passages.first.urn
      assert passage("amhk-001", "jo1.1")
      assert passage("amis-001", "jo.1")
      assert_equal "ESOPO GA XO-", passage("amis-001", "409.1").text
    end

    def test_the_feiqe_opening_keeps_the_romanization_verbatim
      assert_equal "VManojô.Qẽgueônobŏ,Feiqe no yurai ga qi", passage("amhk-001", "3.9").text
      assert_equal "Hiſtoria uo narai xiran to", passage("amhk-001", "tobira.3").text
    end

    def test_the_kanji_kana_layer_rides_each_line
      line = passage("amhk-001", "3.9")
      assert_equal "右馬の判官．検校の坊，平家の由来が聞", line.annotations["kanji_kana"]
      assert_equal({ "page" => "3", "line" => "9" }, line.annotations.slice("page", "line"))
      assert_equal "ＥＳＯＰＯの", passage("amis-001", "tobira.1").annotations["kanji_kana"]
    end

    def test_a_mis_keyed_line_number_re_mints_b_and_keeps_its_layer
      repeat = passage("amhk-001", "8.1-b")
      assert_equal "1", repeat.annotations["line"], "upstream's number stays verbatim"
      assert repeat.annotations["line_repeat"]
      assert_equal "この事は何とと，御尋ね有ったれば，忠", repeat.annotations["kanji_kana"]
      refute passage("amhk-001", "8.1").annotations.key?("line_repeat")
    end

    def test_cmhab_citations_and_the_normalized_layer
      assert_equal "CONTEMPTVS", passage("cmhab-001", "t001.01").text
      first = passage("cmhab-001", "001.01")
      assert_equal "DOCVIVNO FI-", first.text
      assert_equal "<DOCVIVNO FI-", first.annotations["normalized"]
      assert_equal "001", first.annotations["page"]
      assert passage("cmhab-001", "205=206.01")
      glossary = passage("cmhab-001", "s445a.01")
      assert_equal "[445]a", glossary.annotations["page"]
      assert_nil glossary.annotations["normalized"], "the normalized version omits the 言葉の和らげ"
    end

    def test_long_s_folds_for_search
      assert_equal "historia uo narai xiran to", passage("amhk-001", "tobira.3").text_normalized
    end

    def test_documents_carry_the_print_year_place_and_colophon
      feiqe = doc("amhk-001")
      assert_equal({ "not_before" => 1592, "not_after" => 1592, "raw" => "Publication Date 1592",
                     "class" => "edition" }, feiqe.metadata["date"])
      assert_equal "Amakusa", feiqe.metadata["place"]
      assert_equal "jpn", feiqe.language
      assert_equal "大英図書館蔵本（Or.59.aa.1)", feiqe.metadata["base_text"]
      assert_equal 128, feiqe.metadata.dig("layers", "kanji_kana", "aligned")
      assert_equal 1593, doc("amis-001").metadata.dig("date", "not_before")
      contemptus = doc("cmhab-001")
      assert_equal 1596, contemptus.metadata.dig("date", "not_before")
      assert_nil contemptus.metadata["place"], "the HAB title page names no imprint place"
      assert_equal({ "aligned" => 49, "unmatched" => 58 }, contemptus.metadata.dig("layers", "normalized")
                                                                     .slice("aligned", "unmatched"))
      assert_includes contemptus.metadata["transcribers"], "宮川創"
    end

    def test_a_missing_companion_layer_still_parses
      landed_tree do |dir|
        FileUtils.rm_rf(File.join(dir, "amis", "amis-k-001"))
        ref = conformance_adapter.discover(dir).find { |r| r.id == "#{URN}:amis-001" }
        document = conformance_adapter.parse(ref)
        assert_equal 46, document.size
        assert_nil document.passages.first.annotations["kanji_kana"]
      end
    end

    # -- the Nippo Jisho dictionary lane -------------------------------------------

    def lane = Adapter.dictionary_lane

    def nippo
      ref = lane.discover(FIXTURES).first or flunk("no nippo ref")
      lane.parse(ref)
    end

    def entry(id) = nippo.entries.find { |e| e.entry_id == id } || flunk("entry #{id} missing")

    def test_nippo_entries_extract_the_headword
      assert_equal "nippo-jisho", nippo.slug
      assert_equal 9, nippo.size
      vel = entry("001a03")
      assert_equal "Aara.|,ara.", vel.headword
      assert_equal "aara", vel.headword_folded, "the first form, its closing period dropped"
      assert_equal "アアラ.|,アラ", vel.annotations["katakana"]
      assert_equal %w[200200004631IzulFGEL 200200245d81Ten2TA5h], vel.annotations["nikkoku_ids"]
      assert_includes vel.body, "f. 001a"
    end

    def test_nippo_verbs_notes_and_the_supplement
      verb = entry("001a06")
      assert_equal "abaqi", verb.headword_folded
      assert_equal "アバク", verb.annotations["verb_modern"]
      assert_equal "原本ではaburamigaqiの語釈内にある。", entry("001c12").annotations["note"]
      supplement = entry("332a01")
      assert_equal "supplement", supplement.annotations["part"]
      assert_nil supplement.annotations["bnf_image"], "the Paris copy lacks the supplement"
      assert_equal "main", entry("001a01").annotations["part"]
    end

    def test_nippo_loads_idempotently_through_the_lane
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "ninjal-textdb", name: "NINJAL", adapter_class: Adapter.name,
                                          license_class: "attribution")
      2.times do
        result = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(lane, workdir: FIXTURES)
        assert_equal 0, result.errored
        assert_equal 9, db[:dictionary_entries].count
      end
    ensure
      db&.disconnect
    end

    # -- registry, lect, dates -------------------------------------------------------

    def test_the_lect_resolves_to_romanized_late_middle_japanese
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                               overrides_path: File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal "jpn:lmj~latn", lects.resolve("jpn", source: "ninjal-textdb")
    end

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["ninjal-textdb"]
      refute_nil entry
      assert_equal Adapter, entry.adapter_class
      assert entry.wired, "wired after the verified first sync (3 docs / 22,105 passages + 32,878 entries)"
      assert_equal "manual", entry.sync_policy
    end

    def test_the_timeline_reads_the_structured_date
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ninjal-textdb"]
    end

    # -- fetch (WebMock only) ----------------------------------------------------------

    def fast_adapter = Adapter.new.tap { |a| a.define_singleton_method(:fetch_delay) { 0 } }

    def test_fetch_lays_out_one_dir_per_layer_file_and_unpacks_the_nippo_zip
      Adapter::FILES.each do |file|
        stub_request(:get, Adapter.txt_url(file))
          .to_return(status: 200, body: File.binread(File.join(FIXTURES, file.split("-").first, file, "#{file}.txt")))
      end
      stub_request(:get, Adapter::NIPPO_ZIP_URL).to_return(status: 200, body: nippo_zip)
      Dir.mktmpdir do |workdir|
        report = fast_adapter.fetch(workdir)
        assert_match(/\A[0-9a-f]{64}\z/, report.sha)
        assert_equal %w[amhk-001 amis-001 cmhab-001].map { |s| "#{URN}:#{s}" },
                     conformance_adapter.discover(workdir).map(&:id)
        assert File.file?(File.join(workdir, "nipp", "ew-nippo-202510.txt"))
        refute File.exist?(File.join(workdir, "amhk", "amhk-rk-001")), "the r+k juxtaposition is never fetched"
        assert conformance_adapter.discovery_skips(workdir).clean?
      end
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, /www2\.ninjal\.ac\.jp/).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { fast_adapter.fetch(workdir) } }
    end

    def test_the_probe_heads_every_fetched_file
      assert_equal :http_zip, Adapter.remote_probe_strategy
      urls = Adapter.http_probe_targets.map(&:zip_url)
      assert_includes urls, Adapter::NIPPO_ZIP_URL
      assert_equal Adapter::FILES.size + 1, urls.size
    end

    private

    def nippo_zip
      Dir.mktmpdir do |dir|
        top = File.join(dir, "ew-nippo-202510")
        FileUtils.mkdir_p(top)
        %w[ew-nippo-202510.txt readme_ew-nippo-202510.txt].each do |n|
          FileUtils.cp(File.join(FIXTURES, "nipp", n), top)
        end
        zip_path = File.join(dir, "nippo.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, "ew-nippo-202510", chdir: dir)
        return File.binread(zip_path)
      end
    end
  end
end
