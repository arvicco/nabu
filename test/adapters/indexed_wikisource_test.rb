# frozen_string_literal: true

require "test_helper"

module Adapters
  # The scan-indexed wikisource family base (P120-3), exercised through its
  # gu configuration with a stubbed api.php: the Index-embedding cone, the
  # Index evidence riding the envelope, rendering only the admitted pages,
  # and the ProofreadPage level histogram.
  class IndexedWikisourceTest < Minitest::Test
    API = "https://gu.wikisource.org/w/api.php"

    def api_page(pageid, title, wikitext)
      { "pageid" => pageid, "ns" => 0, "title" => title,
        "revisions" => [{ "revid" => pageid * 10, "timestamp" => "2026-10-12T00:00:00Z",
                          "slots" => { "main" => { "*" => wikitext } } }] }
    end

    def index_page(pageid, title, year)
      api_page(pageid, title, "{{:MediaWiki:Proofreadpage_index_template\n|શીર્ષક=ગ્રંથ\n|ભાષા=gu\n" \
                              "|સંપાદક=ઈચ્છારામ\n|વર્ષ=#{year}\n|પ્રગતિ=UP\n}}").merge("ns" => 106)
    end

    def query(request) = URI.decode_www_form(request.uri.query).to_h

    def stub_api
      stub_request(:get, API).with(query: hash_including("list" => "categorymembers"))
                             .to_return(status: 200, body: JSON.generate(
                               "query" => { "categorymembers" => [{ "ns" => 0, "title" => "લેખન પદ" }] }
                             ))
      stub_request(:get, API).with(query: hash_including("list" => "embeddedin"))
                             .to_return(status: 200, body: JSON.generate(
                               "query" => { "embeddedin" => [{ "ns" => 0, "title" => "દોહન પદ" }] }
                             ))
      pages = [
        api_page(1, "દોહન પદ", "{{header\n | author = અખો\n}}\n<pages index=\"Dohan.pdf\" from=1 to=1 />"),
        api_page(2, "લેખન પદ", "{{header|author=મીરાંબાઈ}}\n<pages index=\"Lekhan.pdf\" from=3 to=3 />"),
        index_page(10, "સૂચિ:Dohan 1908.pdf", "1908"),
        index_page(11, "સૂચિ:Lekhan.pdf", "")
      ]
      stub_request(:get, API).with(query: hash_including("prop" => "revisions")).to_return do |request|
        titles = query(request).fetch("titles").split("|")
        redirect = { "from" => "સૂચિ:Dohan.pdf", "to" => "સૂચિ:Dohan 1908.pdf" }
        redirects = titles.include?(redirect["from"]) ? [redirect] : []
        wanted = titles.map { |title| redirects.find { |row| row["from"] == title }&.fetch("to") || title }
        found = pages.select { |page| wanted.include?(page["title"]) }
        { status: 200, body: JSON.generate("query" => { "redirects" => redirects,
                                                        "pages" => found.to_h { |p| [p["pageid"].to_s, p] } }) }
      end
      rendering = '<div class="mw-parser-output"><div class="prp-pages-output"><p>અખા હરિ જાણે</p></div></div>'
      stub_request(:get, API).with(query: hash_including("action" => "parse"))
                             .to_return(status: 200, body: JSON.generate("parse" => { "text" => { "*" => rendering } }))
      stub_request(:get, API).with(query: hash_including("prop" => "templates"))
                             .to_return(status: 200, body: JSON.generate(
                               "query" => { "pages" => { "1" => { "title" => "દોહન પદ", "templates" => [
                                 { "ns" => 104, "title" => "પૃષ્ઠ:Dohan.pdf/1" },
                                 { "ns" => 104, "title" => "પૃષ્ઠ:Dohan.pdf/2" }
                               ] } } }
                             ))
      stub_request(:get, API).with(query: hash_including("prop" => "proofread"))
                             .to_return(status: 200, body: JSON.generate(
                               "query" => { "pages" => {
                                 "5" => { "title" => "પૃષ્ઠ:Dohan.pdf/1", "proofread" => { "quality" => 3 } },
                                 "-1" => { "title" => "પૃષ્ઠ:Dohan.pdf/2", "missing" => "" }
                               } }
                             ))
    end

    def test_fetch_attaches_the_index_and_renders_only_the_dated_edition
      stub_api
      Dir.mktmpdir do |dir|
        report = Nabu::Adapters::GuWikisource.new(delay: 0).fetch(dir)
        assert_match(/\A\h{64}\z/, report.sha)
        envelopes = Dir.glob(File.join(dir, "pages", "*.json")).map { |path| JSON.parse(File.read(path)) }
        pages = envelopes.to_h { |page| [page["title"], page] }
        assert_equal ["દોહન પદ", "લેખન પદ"], pages.keys.sort
        assert_includes pages["દોહન પદ"]["cone"], "index:Bruhad Kavyadohan Granth 1.pdf"

        dohan = pages.fetch("દોહન પદ")
        index = dohan.fetch("indexes").first
        assert_equal ["Dohan.pdf", "સૂચિ:Dohan 1908.pdf", 10], index.values_at("name", "title", "pageid"),
                     "the Index redirect is followed; the requested name is kept"
        assert_equal "1908", index.dig("fields", "વર્ષ")
        assert dohan.key?("html")
        assert_equal({ "3" => 1, "missing" => 1 }, dohan["page_quality"])

        lekhan = pages.fetch("લેખન પદ")
        refute lekhan.key?("html"), "a year-less edition is excluded before any parse call"
        assert_equal :edition_unstated, Nabu::Adapters::GuWikisource.new.page_class(lekhan)
        assert_requested :get, API, query: hash_including("action" => "parse"), times: 1
      end
    end

    def test_template_args_read_inline_and_multiline_headers
      adapter = Nabu::Adapters::MsWikisource.new
      inline = "<div>\n{{header|title=[[A|B]]|editor=محمد|year=1835|notes={{x|y}}}}<pages index=\"I.pdf\"/>"
      assert_equal({ "title" => "[[A|B]]", "editor" => "محمد", "year" => "1835", "notes" => "{{x|y}}" },
                   adapter.send(:template_args, inline, "header"))
      multiline = "{{header\n | title    = Hikayat Aceh\n | year     = abad ke-17\n}}"
      assert_equal "abad ke-17", adapter.send(:template_args, multiline, "header")["year"]
    end

    def test_fetch_failure_is_a_fetch_error
      stub_request(:get, /gu\.wikisource\.org/).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { Nabu::Adapters::GuWikisource.new(delay: 0).fetch(dir) }
      end
    end
  end
end
