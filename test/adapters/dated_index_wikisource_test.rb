# frozen_string_literal: true

require "test_helper"

module Adapters
  # The dated-Index wikisource cone base (P140), exercised through its jv
  # configuration with a stubbed api.php: the cone is drawn at fetch time
  # from EVERY Index page's stated year (or its file-name year), censused
  # EXTRA_INDEXES join past the band, Index subpages are not Indexes, and a
  # page drawn in by a dated Index but transcluding a later print is
  # excluded before any parse call.
  class DatedIndexWikisourceTest < Minitest::Test
    API = "https://jv.wikisource.org/w/api.php"
    ADAPTER = Nabu::Adapters::JvWikisource

    def api_page(pageid, title, wikitext, namespace: 0)
      { "pageid" => pageid, "ns" => namespace, "title" => title,
        "revisions" => [{ "revid" => pageid * 10, "timestamp" => "2026-10-21T00:00:00Z",
                          "slots" => { "main" => { "*" => wikitext } } }] }
    end

    def index_page(pageid, name, year, language: "jv")
      api_page(pageid, "Indhèks:#{name}", "{{:MediaWiki:Proofreadpage_index_template\n|Title=#{name}\n" \
                                          "|Language=#{language}\n|Year=#{year}\n|Progress=T\n}}", namespace: 252)
    end

    def query(request) = URI.decode_www_form(request.uri.query).to_h

    INDEXES = {
      "Serat Lawas 1848.pdf" => "1848",
      "Kajawen 1927.pdf" => "1927",
      "Serat Wulangreh.pdf" => "1929",
      "Wretansacaya (Kern 1875).pdf" => "",
      "Tanpa Taun.pdf" => ""
    }.freeze

    def stub_api
      indexes = INDEXES.each_with_index.map { |(name, year), i| index_page(100 + i, name, year) }
      pages = [
        api_page(1, "Serat Lawas", "{{header|title=Serat Lawas}}\n" \
                                   "<pages index=\"Serat Lawas 1848.pdf\" from=1 to=2 />"),
        api_page(2, "Serat Campur", "<pages index=\"Serat Lawas 1848.pdf\" from=3 to=3 />\n" \
                                    "<pages index=\"Kajawen 1927.pdf\" from=1 to=1 />"),
        api_page(3, "Serat Wulangreh", "<pages index=\"Serat Wulangreh.pdf\" from=1 to=9 />"),
        api_page(4, "Kakawin", "<pages index=\"Wretansacaya (Kern 1875).pdf\" from=1 to=4 />")
      ]
      all_names = INDEXES.keys + ["Serat Lawas 1848.pdf/styles.css"]
      listed = all_names.map { |name| { "ns" => 252, "title" => "Indhèks:#{name}" } }
      stub_request(:get, API).with(query: hash_including("list" => "allpages"))
                             .to_return(status: 200, body: JSON.generate("query" => { "allpages" => listed }))
      stub_request(:get, API).with(query: hash_including("list" => "embeddedin")).to_return do |request|
        embedded = { "Indhèks:Serat Lawas 1848.pdf" => ["Serat Lawas", "Serat Campur"],
                     "Indhèks:Serat Wulangreh.pdf" => ["Serat Wulangreh"],
                     "Indhèks:Wretansacaya (Kern 1875).pdf" => ["Kakawin"] }.fetch(query(request)["eititle"], [])
        rows = embedded.map { |title| { "ns" => 0, "title" => title } }
        { status: 200, body: JSON.generate("query" => { "embeddedin" => rows }) }
      end
      stub_request(:get, API).with(query: hash_including("prop" => "revisions")).to_return do |request|
        titles = query(request).fetch("titles").split("|")
        found = (pages + indexes).select { |page| titles.include?(page["title"]) }
        { status: 200, body: JSON.generate("query" => { "pages" => found.to_h { |p| [p["pageid"].to_s, p] } }) }
      end
      rendering = '<div class="mw-parser-output"><div class="prp-pages-output"><p>Punika serat lawas</p></div></div>'
      stub_request(:get, API).with(query: hash_including("action" => "parse"))
                             .to_return(status: 200, body: JSON.generate("parse" => { "text" => { "*" => rendering } }))
      stub_request(:get, API).with(query: hash_including("prop" => "templates"))
                             .to_return(status: 200, body: JSON.generate("query" => { "pages" => {} }))
    end

    def test_the_cone_is_drawn_from_every_index_year_at_fetch_time
      stub_api
      Dir.mktmpdir do |dir|
        ADAPTER.new(delay: 0).fetch(dir)
        envelopes = Dir.glob(File.join(dir, "pages", "*.json")).map { |path| JSON.parse(File.read(path)) }
        pages = envelopes.to_h { |page| [page["title"], page] }
        assert_equal ["Kakawin", "Serat Campur", "Serat Lawas", "Serat Wulangreh"], pages.keys.sort,
                     "1848 and the Kern-1875 file-name year are in the band; the censused 1929 Wulangreh " \
                     "print joins as an EXTRA; the 1927 and the year-less Index draw nothing"
        assert_includes pages["Serat Lawas"]["cone"], "index:Serat Lawas 1848.pdf"
        assert_includes pages["Serat Wulangreh"]["cone"], "index:Serat Wulangreh.pdf"

        adapter = ADAPTER.new
        assert_equal :after_cone, adapter.page_class(pages.fetch("Serat Campur")),
                     "a page drawn in by a dated Index that also transcludes a 1927 print is outside the cone"
        refute pages.fetch("Serat Campur").key?("html"), "excluded before any parse call"
        assert_equal :text, adapter.page_class(pages.fetch("Serat Lawas"))
        assert_equal :text, adapter.page_class(pages.fetch("Serat Wulangreh"))
        assert_requested :get, API, query: hash_including("action" => "parse"), times: 3
        refute_requested :get, API, query: hash_including("eititle" => "Indhèks:Serat Lawas 1848.pdf/styles.css")
      end
    end

    def test_cone_index_reads_the_stated_year_then_the_file_name
      adapter = ADAPTER.new
      assert adapter.cone_index?("A.pdf", { "Year" => "1866" })
      refute adapter.cone_index?("B.pdf", { "Year" => "1901" })
      assert adapter.cone_index?("Wretansacaya (Kern 1875).pdf", {})
      refute adapter.cone_index?("Tanpa Taun.pdf", { "Year" => "" })
      assert adapter.cone_index?("Serat Pararaton.pdf", { "Year" => "1912" }), "a censused EXTRA print"
      refute Nabu::Adapters::BrWikisource.new.cone_index?("Ar Vro, 1906.djvu", { "Year" => "1906" })
      assert Nabu::Adapters::BrWikisource.new.cone_index?("X.djvu", { "Year" => "Hep bloavezh embann. (war-dro 1823)" })
      refute Nabu::Adapters::CyWikisource.new.cone_index?("Y.djvu", { "Year" => "1801" }),
             "the Welsh band ends at 1800"
    end

    def test_the_foreign_share_separates_apparatus_from_text
      adapter = ADAPTER.new
      dutch = "De Javaansche taal is een van de rijkste talen die op het eiland worden gesproken en dat is bekend"
      javanese = "Punika serat babad ingkang kaanggit dening para pujangga ing karaton Surakarta"
      assert_operator adapter.foreign_share(dutch), :>=, Nabu::Adapters::DatedIndexWikisource::FOREIGN_SHARE
      assert_operator adapter.foreign_share(javanese), :<, Nabu::Adapters::DatedIndexWikisource::FOREIGN_SHARE
      assert_in_delta 0.0, Nabu::Adapters::CyWikisource.new.foreign_share(dutch), 1e-9, "cy measures nothing"
    end

    def test_fetch_failure_is_a_fetch_error
      stub_request(:get, /jv\.wikisource\.org/).to_return(status: 503)
      Dir.mktmpdir do |dir|
        assert_raises(Nabu::FetchError) { ADAPTER.new(delay: 0).fetch(dir) }
      end
    end
  end
end
