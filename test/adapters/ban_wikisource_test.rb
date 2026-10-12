# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "test_helper"
require "support/adapter_conformance"
require "support/store_test_db"

module Adapters
  # ban-wikisource: the Balinese Wikisource lontar corpus. Fixture
  # envelopes are real api.php captures (ban.wikisource.org + Commons,
  # 2026-10-12) written through the adapter's own envelope methods — see
  # the README for the picks and the page trims.
  class BanWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("ban-wikisource")
    PREFIX = "urn:nabu:ban-wikisource:"

    DHARMA_USADA = 568      # Sukawati jpg, work category Lontar Basa Kawi, Gedong Kirtya Agama
    PAPARIKAN = 24_142      # IA scan, Palmleaf Bot import, 58 Page-ns pages (3 kept)
    RAJAPALA = 1985         # Tojan jpg, works claim Basa Bali AND Basa Kawi
    KIDUNG_LEIDEN = 28_568  # Leiden Or. 19.586, a romanized (Latin-script) copy

    def conformance_adapter = Nabu::Adapters::BanWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ban-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn == "#{PREFIX}#{pageid}" } || flunk("#{pageid} missing")

    def test_discover_admits_the_manuscript_indexes_only
      ids = conformance_adapter.discover(FIXTURES).map(&:id).sort
      expected = [DHARMA_USADA, PAPARIKAN, RAJAPALA, KIDUNG_LEIDEN].map { |id| "#{PREFIX}#{id}" }.sort
      assert_equal expected, ids
    end

    def test_the_written_rules_census_every_skip
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 4, skips.skipped_by_rule
      assert_equal ["non-corpus file: manifest.yml"], skips.notes.grep(/non-corpus/),
                   "only the fixture sentinel's manifest is foreign here — every envelope is recognized"
      notes = skips.notes.join("\n")
      assert_match(/1 redirect Index/, notes, "the renamed WLM Klungkung scan")
      assert_match(/1 printed edition\(s\) excluded by the year rule/, notes, "Geguritan Mladprana, Year=1992")
      assert_match(/1 printed edition\(s\) outside the manuscript-scan families \(no Year=\)/, notes,
                   "PEPARIKAN MAHABHARATA, a Balai Bahasa printing")
      assert_match(/1 manuscript Index\(es\) whose pages carry no transcription/, notes,
                   "Leiden Or. 20.297: level-0 pages only")
    end

    def test_the_year_rule_reads_index_metadata
      adapter = conformance_adapter
      printed = "{{:MediaWiki:Proofreadpage_index_template\n|Year=1994\n|Publisher=\n}}"
      campaign = "{{:MediaWiki:Proofreadpage_index_template\n|Year=2020\n|Publisher=Eka343\n}}"
      assert_equal :printed_dated, adapter.printed_class("Alih Aksara Lontar Kakawin Sutasoma.pdf", printed)
      assert_equal :printed_dated, adapter.printed_class("Bali-lontar-x.pdf", printed),
                   "a print year before the campaign floor overrides the family"
      assert_nil adapter.printed_class("Bali-lontar-Wanagiri-Dharma Usada.jpg", campaign),
                 "the family's Year= is the photography campaign, not a print"
      assert_equal :printed, adapter.printed_class("PEPARIKAN MAHABHARATA.pdf", "|Year=\n")
    end

    def test_kawi_lontar_carries_its_cone_classes
      d = doc(DHARMA_USADA)
      assert_equal "kaw-Bali", d.language, "the work category Lontar Basa Kawi refines the Index's ban"
      assert_equal "work category: Lontar Basa Kawi", d.metadata["language_basis"]
      assert_equal "ban-bali", d.metadata["language_field"]
      assert_equal ["Agama"], d.metadata["gedong_kirtya_class"]
      assert_includes d.metadata["collection"], "Lontar Sukawati"
      assert_equal ["Dharma Usada (Sukawati)"], d.metadata["works"]
      assert_equal ["self|cc-by-sa-4.0"], d.metadata.dig("scan", "licenses")
      assert_equal 1, d.passages.size
      first = d.passages.first
      assert_equal "#{PREFIX}#{DHARMA_USADA}:1", first.urn
      assert first.text.start_with?("᭛᭜᭛ᬅᬯᬶᬖ᭄ᬦᬫᬲ᭄ᬢᬸ᭛᭜᭛"), "Balinese script verbatim"
      assert_equal %w[depan belakang], first.annotations["leaves"], "leaf-face markers lift out of the text"
      refute_includes first.text, "[depan]"
      assert_includes first.text, "[rajah]", "inline editorial marks stay in the line"
      assert_equal 3, first.annotations["quality"]
    end

    def test_palmleaf_import_keeps_its_lines_and_leaf_numbers
      d = doc(PAPARIKAN)
      assert_equal "ban-Bali", d.language
      assert_equal "Paparikan Uwug Rusak Dwarawati", d.title, "the Index Title= display text ({{lang}} unwrapped)"
      assert_equal "Index Language=", d.metadata["language_basis"]
      assert_equal [1, 56, 57].map { |n| "#{PREFIX}#{PAPARIKAN}:#{n}" }, d.passages.map(&:urn),
                   "passages cite the Page-ns page number"
      page57 = d.passages.last
      assert_equal ["᭕᭖ 56B", "᭕᭗ 57A"], page57.annotations["leaves"]
      assert page57.text.lines.first.start_with?("᭕᭖"), "the leaf's own numeral is manuscript text"
      assert_operator page57.text.lines.size, :>, 5, "manuscript lines kept"
      assert_equal 58, d.metadata["pages_upstream"]
      assert_equal "paparikan-uwug-rusak-dwarawati", d.metadata.dig("scan", "ia_identifier")
      assert_equal ["PD-IDNoCopyright"], d.metadata.dig("scan", "licenses")
      assert_operator d.metadata["palmleaf_bot_pages"], :>=, 1
      assert_equal d.passages.size, d.metadata["quality"].values.sum
    end

    def test_conflicting_work_language_categories_fall_back_to_the_index
      d = doc(RAJAPALA)
      assert_equal "ban-Bali", d.language
      assert_match(%r{conflicting work categories: Lontar Basa Bali / Lontar Basa Kawi}, d.metadata["language_basis"])
      assert_equal ["Itihasa"], d.metadata["gedong_kirtya_class"]
      assert_equal "2020", d.metadata["index_year"], "the campaign year rides verbatim"
      assert_equal %w[awal akhir], d.passages.first.annotations["leaves"]
      assert_equal 4, d.passages.first.annotations["quality"], "validated"
    end

    def test_leiden_romanized_copy_is_tagged_latin
      d = doc(KIDUNG_LEIDEN)
      assert_equal "ban-Latn", d.language, "the script subtag is measured over the held text"
      assert_equal "Latn", d.metadata["script"]
      assert(d.passages.any? { |p| p.text.include?("Manghamulat erumning ukir,") })
      assert_equal "Or. 19.586", d.metadata.dig("scan", "shelfmark")
    end

    def test_unknown_index_language_quarantines_loudly
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "pages"), dir)
        path = File.join(dir, "pages", "#{PAPARIKAN}.json")
        envelope = JSON.parse(File.read(path))
        envelope["wikitext"] = envelope["wikitext"].sub(/\|Language=[^\n]*/, "|Language=jv")
        File.write(path, JSON.generate(envelope))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{PREFIX}#{PAPARIKAN}" }
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_match(/unknown Index Language= "jv"/, error.message)
      end
    end

    # Balinese has canonical compositions (ᬅ + ᬵ = ᬆ): decomposed input
    # must leave the adapter NFC.
    def test_decomposed_balinese_is_stored_nfc
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "pages"), dir)
        path = File.join(dir, "pages", "#{DHARMA_USADA}.json")
        envelope = JSON.parse(File.read(path))
        envelope["pages"][0]["wikitext"] = envelope["pages"][0]["wikitext"].sub("[depan]<br>", "[depan]<br>ᬆ<br>")
        File.write(path, JSON.generate(envelope))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{PREFIX}#{DHARMA_USADA}" }
        text = adapter.parse(ref).passages.first.text
        assert_equal "ᬆ", text.lines.first.chomp
      end
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "ban-wikisource", name: "ban", license_class: "attribution",
                                          adapter_class: "Nabu::Adapters::BanWikisource")
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 4, first.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    # -- fetch (WebMock'd api.php: the staging, the delta, the URL cap) -------

    API = "https://ban.wikisource.org/w/api.php"
    COMMONS = "https://commons.wikimedia.org/w/api.php"
    LONG = "Bali-lontar-Wanagiri-ᬓᬦ᭄ᬤᬧᬢ᭄ᬭᬭᬾᬓᬦ᭄ᬤᬧᬢ᭄ᬭᬭᬾ Kanda Pat Rare Kawisesan Panengen-NC 206.pdf"
    PRINTED = "Geguritan Mladprana.pdf"
    PAGE_TEXT = "<noinclude><pagequality level=\"3\" user=\"x\" /></noinclude>ᬅᬓ᭄ᬱᬭ"

    def page_titles = (1..60).map { |n| "Kaca:#{LONG}/#{n}" }

    def api_pages
      pages = page_titles.each_with_index.to_h do |title, i|
        [title, { "pageid" => 1000 + i, "ns" => 250, "title" => title, "lastrevid" => 5000 + i }]
      end
      pages["Kaca:#{PRINTED}/1"] = { "pageid" => 999, "ns" => 250, "title" => "Kaca:#{PRINTED}/1", "lastrevid" => 1 }
      pages
    end

    def revision(id, text)
      [{ "revid" => id, "timestamp" => "2026-10-12T00:00:00Z",
         "slots" => { "main" => { "*" => text } } }]
    end

    def stub_wiki(content_requests)
      stub_request(:get, /#{Regexp.escape(API)}/).to_return do |request|
        params = URI.decode_www_form(URI(request.uri.to_s).query).to_h
        { body: JSON.generate(api_answer(params, content_requests)) }
      end
      stub_request(:get, /#{Regexp.escape(COMMONS)}/).to_return do |request|
        titles = URI.decode_www_form(URI(request.uri.to_s).query).to_h.fetch("titles").split("|")
        pages = titles.to_h do |t|
          [t, { "pageid" => 77, "ns" => 6, "title" => t, "categories" => [{ "title" => "Category:Balinese lontar" }],
                "revisions" => revision(88, "{{Book\n| Source = {{IA|kanda-pat}}\n}}\n== {{int:license-header}} ==\n" \
                                            "{{PD-IDNoCopyright}}") }]
        end
        { body: JSON.generate("query" => { "pages" => pages }) }
      end
    end

    def api_answer(params, content_requests)
      return { "query" => { "namespaces" => { "250" => { "*" => "Kaca" }, "252" => { "*" => "Indéks" } } } } if
        params["meta"] == "siteinfo"

      if params["generator"] == "allpages"
        pages = params["gapnamespace"] == "250" ? api_pages.values : []
        return { "query" => { "pages" => pages.to_h { |p| [p["pageid"].to_s, p] } } }
      end

      titles = params.fetch("titles").split("|")
      content_requests << titles
      { "query" => { "pages" => titles.to_h { |t| [t, wiki_page(t)] } } }
    end

    def wiki_page(title)
      if title.start_with?("Indéks:")
        year = title.include?(PRINTED) ? "1992" : ""
        return { "pageid" => title.include?(PRINTED) ? 32_600 : 42, "ns" => 252, "title" => title,
                 "categories" => [{ "title" => "Kategori:Index" }],
                 "revisions" => revision(7, "{{:MediaWiki:Proofreadpage_index_template\n|Title=X\n" \
                                            "|Language=ban\n|Year=#{year}\n}}") }
      end
      page = api_pages.fetch(title)
      { "pageid" => page["pageid"], "ns" => 250, "title" => title, "categories" => [],
        "revisions" => revision(page["lastrevid"], PAGE_TEXT) }
    end

    def test_fetch_stages_the_manuscripts_under_the_url_cap_and_fetches_deltas_only
      Dir.mktmpdir do |workdir|
        first = []
        stub_wiki(first)
        Nabu::Adapters::BanWikisource.new(delay: 0).fetch(workdir)
        manuscript = JSON.parse(File.read(File.join(workdir, "pages", "42.json")))
        assert_equal 60, manuscript["pages"].size, "every Page-ns page lands"
        assert_equal "kanda-pat", manuscript.dig("scan", "wikitext")[/IA\|([^}]+)/, 1]
        printed = JSON.parse(File.read(File.join(workdir, "pages", "32600.json")))
        assert_nil printed["pages"], "a printed edition's pages are never fetched"
        assert_equal 1, printed["page_count"]
        refute(first.flatten.include?("Kaca:#{PRINTED}/1"))
        page_batches = first.select { |titles| titles.first.start_with?("Kaca:") }
        assert_operator page_batches.size, :>, 2, "the long titles force several batches"
        cap = Nabu::Adapters::SlavicWikisource::URL_BYTE_CAP - Nabu::Adapters::SlavicWikisource::CONTINUE_RESERVE
        page_batches.each do |titles|
          bytes = URI.encode_www_form("titles" => titles.join("|")).bytesize
          assert_operator bytes, :<, cap, "a batch overran the URL cap"
        end

        second = []
        WebMock.reset!
        stub_wiki(second)
        Nabu::Adapters::BanWikisource.new(delay: 0).fetch(workdir)
        refute(second.flatten.any? { |title| title.start_with?("Kaca:") }, "unchanged pages cost nothing")
        assert_equal 60, JSON.parse(File.read(File.join(workdir, "pages", "42.json")))["pages"].size
      end
    end
  end
end
