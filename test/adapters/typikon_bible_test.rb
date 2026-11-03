# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

module Adapters
  # Nabu::Adapters::TypikonBible — the Bible layer of the typikon.info
  # "Уставные чтения" corpus dump (2026-09-21; Zenodo 10.5281/zenodo.22883965):
  # the edition-gated verse files. Admitted: ro-1688 (the 1688 Bucharest
  # Bible in Romanian Cyrillic, typeset by the project, CC BY 4.0 under the
  # layer license), and — owner-ruled 2026-11-03 under the dump's PD
  # marking — cs-eliz (the Elizabeth Bible, Church Cyrillic) and ka-mcxeta
  # (the Old Georgian Bible). Document = edition × book, passage = verse
  # in the edition's own numbering, the Slavonic canonical address riding
  # annotations. Fixtures: byte-verbatim JSONL lines of the dump files,
  # trimmed by book and re-gzipped — see test/fixtures/typikon-bible/README.md.
  class TypikonBibleTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("typikon-bible")
    URN = "urn:nabu:typikon-bible:ro-1688:"
    CS = "urn:nabu:typikon-bible:cs-eliz:"
    KA = "urn:nabu:typikon-bible:ka-mcxeta:"
    ALL_IDS = %W[#{URN}ioilya #{URN}avdiya #{URN}pesn-trekh-otrokov
                 #{CS}avdiya #{CS}1-petra #{KA}avdiya #{KA}filimonu].freeze

    def conformance_adapter
      Nabu::Adapters::TypikonBible.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "typikon-bible"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_typikon_bible_wired_on_its_first_sync_evidence
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["typikon-bible"]
      refute_nil entry, "typikon-bible must be registered in config/sources.yml"
      assert entry.wired, "wired on the first-sync evidence (landed exactly on census, 2026-11-02)"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_attribution_with_the_layer_grant
      manifest = Nabu::Adapters::TypikonBible.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "CC BY 4.0"
      assert_includes manifest.license, "Румынскую кириллицу 1688 и китайский Новый Завет 1910 набирали мы"
      assert_includes manifest.license, "Public Domain Mark 1.0", "the cs-eliz and ka-mcxeta file marking"
      assert_includes manifest.license, "owner-ruled 2026-11-03"
    end

    def test_admitted_editions_are_the_ruled_three
      assert_equal %w[ro-1688 cs-eliz ka-mcxeta], Nabu::Adapters::TypikonBible::ADMITTED.keys
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_admitted_edition_book
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal ALL_IDS, refs.map(&:id),
                   "editions in ruled order, each in its own book order (ro-1688: Joel 31, Obadiah 32, " \
                   "the Song 44; cs-eliz: Obadiah 37, 1 Peter 57; ka-mcxeta: Obadiah 38, Philemon 71)"
    end

    def test_rejected_grains_are_skipped_by_rule_and_named
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule,
                   "the ro-1914 verse file (an edition outside the ruled set) + the concordance instrument"
      assert(skips.notes.any? { |note| note.include?("ro-1914") })
      assert(skips.notes.any? { |note| note.include?("bible-concordance") })
      assert_equal 0, skips.unrecognized
    end

    def test_discover_yields_nothing_from_an_empty_workdir
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_edition_and_book
      joel = parse_urn("#{URN}ioilya")
      assert_equal "ron-Cyrl", joel.language
      assert_equal "І҆ѡ́иль (Иоиля) - І҆ѠИ́ЛЬ", joel.title, "the dump's own book name, verbatim"
      assert_equal "ro-1688", joel.metadata["edition"]
      assert_equal "Сфънта Скриптура (Библия на румынской кириллице, 1688)", joel.metadata["edition_title"]
      assert_equal({ "not_before" => 1688, "not_after" => 1688, "class" => "edition",
                     "raw" => "1688 — the edition year the dump records (bible-editions year)" },
                   joel.metadata["date"])
      assert_equal 73, joel.size
    end

    def test_passages_keep_the_editions_own_numbering_with_the_canonical_address
      joel = parse_urn("#{URN}ioilya")
      verse = joel.find { |p| p.urn == "#{URN}ioilya:4.6" }
      refute_nil verse, "the 1688 print numbers Joel in four chapters (the Hebrew division)"
      assert_equal "ioilya.3.6", verse.annotations["canon_ref"], "the Slavonic canonical address"
      song = parse_urn("#{URN}pesn-trekh-otrokov").passages.first
      assert_equal "#{URN}pesn-trekh-otrokov:1.1", song.urn
      assert_equal "daniila.3.24", song.annotations["canon_ref"],
                   "the Song of the Three Youths is its own book in 1688 and Dan 3:24–90 in the canon"
    end

    def test_verse_text_is_the_dump_content_nfc
      obadiah = parse_urn("#{URN}avdiya")
      first = obadiah.passages.first
      assert_equal "#{URN}avdiya:1.1", first.urn
      assert first.text.start_with?("Веденїѧ лꙋ́й А҆в꙽ді́е.")
      assert first.text.unicode_normalized?(:nfc), "ron is not NFC-exempt; upstream ships non-NFC combining order"
      assert_equal 21, obadiah.size
    end

    def test_the_elizabeth_bible_witness_in_church_cyrillic
      obadiah = parse_urn("#{CS}avdiya")
      assert_equal "chu", obadiah.language
      assert_equal "Авдия", obadiah.title
      assert_equal "cs-eliz", obadiah.metadata["edition"]
      assert_equal "Библия (церковнославянский, Елизаветинская)", obadiah.metadata["edition_title"]
      assert_equal({ "not_before" => 1751, "not_after" => 1751, "class" => "edition",
                     "raw" => "1751 — the edition year the dump records (bible-editions year)" },
                   obadiah.metadata["date"])
      assert_equal "PD", obadiah.metadata["text_license"]
      assert_includes obadiah.metadata["text_attribution"],
                      "Елизаветинская Библия (ред. 1751/1900), оцифровка bible.by/elzs"
      assert_equal 21, obadiah.size
      first = obadiah.passages.first
      assert_equal "#{CS}avdiya:1.1", first.urn
      assert first.text.start_with?("Видѣ́нїе а҆вді́ино: сїѧ̑ гл҃етъ гдⷭ҇ь бг҃ъ"), "titla and accents kept as printed"
      assert_equal "avdiya.1.1", first.annotations["canon_ref"], "cs-eliz IS the canon: identity addresses"
    end

    def test_the_church_slavonic_text_is_nfc_at_the_boundary
      peter = parse_urn("#{CS}1-petra")
      verse = peter.find { |p| p.urn == "#{CS}1-petra:1.10" }
      refute_nil verse
      assert verse.text.unicode_normalized?(:nfc), "1 Pet 1:10 ships one non-NFC combining sequence (и҆̀же)"
      assert_equal 105, peter.size
    end

    def test_the_georgian_witness_is_old_georgian_dated_by_testament
      obadiah = parse_urn("#{KA}avdiya")
      assert_equal "oge", obadiah.language, "the edition's own title: ბიბლია ძველი ქართულით (in Old Georgian)"
      assert_equal "აბდია წინასწარმეტყველი", obadiah.title
      assert_equal "PD", obadiah.metadata["text_license"]
      assert_equal({ "not_before" => 1601, "not_after" => 1800,
                     "raw" => "XVII–XVIII c. — the Mtskheta manuscript the dump names for the Old Testament " \
                              "(\"Мцхетская рукопись XVII–XVIII века\")" },
                   obadiah.metadata["date"], "the witness date, class-less: the dump records no edition year")
      assert obadiah.passages.first.text.start_with?("ხილვაჲ აბდიასი")
      assert_equal 21, obadiah.size
      philemon = parse_urn("#{KA}filimonu")
      assert_equal({ "not_before" => 1001, "not_after" => 1100, "class" => "composition",
                     "raw" => "XI c. — the Athonite translation of Euthymius and George the dump names for " \
                              "the New Testament (\"перевод Святогорцев — XI\")" },
                   philemon.metadata["date"])
      assert_equal 23, philemon.size, "the Georgian Philemon numbers 23 verses against the canon's 25"
    end

    def test_a_pd_edition_whose_file_marking_changes_is_a_parse_error
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
        path = File.join(dir, "manifest", "manifest.json")
        data = JSON.parse(File.read(path))
        files = data["layers"].find { |layer| layer["id"] == "bible" }["files"]
        files.find { |f| f["path"] == "bible/bible-verses-ka-mcxeta.jsonl.gz" }["license"]["id"] = "CC-BY-NC-4.0"
        File.write(path, JSON.generate(data))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{KA}avdiya" }
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_includes error.message, "CC-BY-NC-4.0"
        refute_empty adapter.parse(adapter.discover(dir).first), "ro-1688 still parses on its own grant"
      end
    end

    def test_a_layer_license_drift_is_a_parse_error
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
        path = File.join(dir, "manifest", "manifest.json")
        data = JSON.parse(File.read(path))
        data["layers"].find { |layer| layer["id"] == "bible" }["license"]["id"] = "CC-BY-NC-4.0"
        File.write(path, JSON.generate(data))
        adapter = conformance_adapter
        ref = adapter.discover(dir).first
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_includes error.message, "CC-BY-NC-4.0"
      end
    end

    # -- fetch ------------------------------------------------------------------

    def test_fetch_lands_each_file_in_its_own_subdir
      Nabu::Adapters::TypikonBible::FILES.each do |subdir, (url, filename)|
        stub_request(:get, url).to_return(status: 200, body: File.binread(File.join(FIXTURES, subdir, filename)))
      end
      Dir.mktmpdir do |dir|
        report = conformance_adapter.fetch(dir)
        refute_nil report.sha
        assert_equal ALL_IDS, conformance_adapter.discover(dir).map(&:id)
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, /typikon\.info/).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { conformance_adapter.fetch(dir) }
      end
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "typikon-bible", name: "typikon.info Bible layer",
        adapter_class: "Nabu::Adapters::TypikonBible", license_class: "attribution"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 7, first.added
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
  end
end
