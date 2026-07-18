# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::WikiFetch (P29-3): the MediaWiki api.php category crawl — member
# map + revid-driven page batches, under the ZipFetch retention phases.
# All HTTP is WebMock-stubbed; response shapes are the ones api.php 1.38
# actually served in the 2026-07-18 probes.
class WikiFetchTest < Minitest::Test
  API = "https://wiki.test/api.php"

  def http
    Faraday.new
  end

  def build(dir, categories: ["Inscription"], delay: 0)
    Nabu::WikiFetch.new(
      api_url: API, categories: categories, dir: dir,
      attic_dir: File.join(dir, ".attic"), http: http, delay: delay
    )
  end

  def stub_members(pages, category: "Inscription", continued: nil)
    body = { "query" => { "pages" => pages } }
    body["continue"] = continued if continued
    stub_request(:get, API)
      .with(query: hash_including("generator" => "categorymembers", "gcmtitle" => "Category:#{category}"))
      .to_return(status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" })
  end

  def member(pageid, title, revid)
    [pageid.to_s, { "pageid" => pageid, "ns" => 0, "title" => title, "lastrevid" => revid }]
  end

  def stub_content(pages)
    stub_request(:get, API)
      .with(query: hash_including("prop" => "revisions"))
      .to_return(status: 200, body: JSON.generate({ "query" => { "pages" => pages } }),
                 headers: { "Content-Type" => "application/json" })
  end

  def content_page(pageid, title, revid, wikitext)
    [pageid.to_s, {
      "pageid" => pageid, "ns" => 0, "title" => title,
      "revisions" => [{ "revid" => revid, "timestamp" => "2026-07-18T12:00:00Z",
                        "slots" => { "main" => { "*" => wikitext } } }]
    }]
  end

  # --- fresh crawl ----------------------------------------------------------

  def test_fresh_crawl_writes_map_pages_and_state
    Dir.mktmpdir do |dir|
      stub_members([member(1, "AO·1.1", 11), member(2, "Bozen / Bolzano", 22)].to_h)
      stub_content([content_page(1, "AO·1.1", 11, "{{inscription\n|reading=ap\n}}"),
                    content_page(2, "Bozen / Bolzano", 22, "{{site\n|sigla=BZ\n}}")].to_h)

      result = Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"],
                                     dir: dir, attic_dir: File.join(dir, ".attic"),
                                     http: http, delay: 0)

      assert_equal 2, result.fetched
      assert_equal 0, result.cached
      assert_equal 2, result.member_count

      map = JSON.parse(File.read(File.join(dir, "map", "Inscription.json")))
      assert_equal "Inscription", map["category"]
      assert_equal(["AO·1.1", "Bozen / Bolzano"], map["members"].map { |m| m["title"] })

      page = JSON.parse(File.read(File.join(dir, "pages", "Inscription", "AO%C2%B71.1.json")))
      assert_equal "AO·1.1", page["title"]
      assert_equal 11, page["revid"]
      assert_equal "{{inscription\n|reading=ap\n}}", page["wikitext"]

      assert File.file?(File.join(dir, "pages", "Inscription", "Bozen%20%2F%20Bolzano.json")),
             "the slash-bearing title percent-encodes into a clean filename"
      state = JSON.parse(File.read(File.join(dir, Nabu::WikiFetch::STATE_FILE)))
      assert_equal result.sha, state["sha256"]
      assert_equal API, state["url"]
    end
  end

  def test_member_pagination_follows_gcmcontinue
    Dir.mktmpdir do |dir|
      first = { "query" => { "pages" => [member(1, "A", 11)].to_h },
                "continue" => { "gcmcontinue" => "tok", "continue" => "gcmcontinue||" } }
      second = { "query" => { "pages" => [member(2, "B", 22)].to_h } }
      stub_request(:get, API)
        .with(query: hash_including("generator" => "categorymembers"))
        .to_return({ status: 200, body: JSON.generate(first) },
                   { status: 200, body: JSON.generate(second) })
      stub_content([content_page(1, "A", 11, "a"), content_page(2, "B", 22, "b")].to_h)

      fetch = build(dir)
      fetch.prepare!
      assert_equal 2, fetch.member_count
      assert_requested :get, API, query: hash_including("gcmcontinue" => "tok"), times: 1
    end
  end

  # --- revid-driven change detection ---------------------------------------

  def test_unchanged_pages_are_not_refetched
    Dir.mktmpdir do |dir|
      stub_members([member(1, "A", 11)].to_h)
      stub_content([content_page(1, "A", 11, "body")].to_h)
      Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                            attic_dir: File.join(dir, ".attic"), http: http, delay: 0)

      result = Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                                     attic_dir: File.join(dir, ".attic"), http: http, delay: 0)
      assert_equal 0, result.fetched
      assert_equal 1, result.cached
      assert_requested :get, API, query: hash_including("prop" => "revisions"), times: 1
    end
  end

  def test_a_bumped_revid_refetches_the_page
    Dir.mktmpdir do |dir|
      stub_members([member(1, "A", 11)].to_h)
      stub_content([content_page(1, "A", 11, "old")].to_h)
      Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                            attic_dir: File.join(dir, ".attic"), http: http, delay: 0)

      stub_members([member(1, "A", 12)].to_h)
      stub_content([content_page(1, "A", 12, "new")].to_h)
      result = Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                                     attic_dir: File.join(dir, ".attic"), http: http, delay: 0)
      assert_equal 1, result.fetched
      assert_equal "new", JSON.parse(File.read(File.join(dir, "pages", "Inscription", "A.json")))["wikitext"]
    end
  end

  # --- retention ------------------------------------------------------------

  def test_vanished_members_are_atticked_before_deletion
    Dir.mktmpdir do |dir|
      stub_members([member(1, "A", 11), member(2, "B", 22)].to_h)
      stub_content([content_page(1, "A", 11, "a-body"), content_page(2, "B", 22, "b-body")].to_h)
      Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                            attic_dir: File.join(dir, ".attic"), http: http, delay: 0)

      stub_members([member(1, "A", 11)].to_h)
      result = Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                                     attic_dir: File.join(dir, ".attic"), http: http, delay: 0)

      assert_equal ["pages/Inscription/B.json"], result.atticked
      refute File.exist?(File.join(dir, "pages", "Inscription", "B.json"))
      atticked = File.join(dir, ".attic", "pages", "Inscription", "B.json")
      assert_equal "b-body", JSON.parse(File.read(atticked))["wikitext"]
      manifest = JSON.parse(File.read(File.join(dir, ".attic", Nabu::GitFetch::ATTIC_MANIFEST)))
      assert_equal result.sha, manifest["pages/Inscription/B.json"]
    end
  end

  def test_guard_abort_leaves_the_tree_untouched
    Dir.mktmpdir do |dir|
      stub_members([member(1, "A", 11), member(2, "B", 22)].to_h)
      stub_content([content_page(1, "A", 11, "a"), content_page(2, "B", 22, "b")].to_h)
      Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                            attic_dir: File.join(dir, ".attic"), http: http, delay: 0)

      stub_members([member(1, "A", 11)].to_h)
      assert_raises(Nabu::SyncAborted) do
        Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                              attic_dir: File.join(dir, ".attic"), http: http, delay: 0,
                              guard: lambda { |doomed|
                                raise Nabu::SyncAborted.new(existing_count: 2, would_withdraw_count: doomed.size,
                                                            threshold: 0.2)
                              })
      end
      assert File.file?(File.join(dir, "pages", "Inscription", "B.json")),
             "an aborted sync must leave the doomed page in place"
      refute Dir.exist?(File.join(dir, ".attic")), "no attic writes before the guard passes"
    end
  end

  # --- failure honesty ------------------------------------------------------

  def test_api_error_payloads_raise
    Dir.mktmpdir do |dir|
      stub_request(:get, API)
        .with(query: hash_including("generator" => "categorymembers"))
        .to_return(status: 200, body: JSON.generate({ "error" => { "code" => "readapidenied" } }))
      assert_raises(Nabu::WikiFetch::Error) { build(dir).prepare! }
    end
  end

  def test_http_failures_raise
    Dir.mktmpdir do |dir|
      stub_request(:get, API)
        .with(query: hash_including("generator" => "categorymembers"))
        .to_return(status: 503)
      assert_raises(Nabu::WikiFetch::Error) { build(dir).prepare! }
    end
  end

  def test_requests_carry_the_nabu_user_agent
    Dir.mktmpdir do |dir|
      stub_members([member(1, "A", 11)].to_h)
      stub_content([content_page(1, "A", 11, "a")].to_h)
      Nabu::WikiFetch.sync!(api_url: API, categories: ["Inscription"], dir: dir,
                            attic_dir: File.join(dir, ".attic"), http: http, delay: 0)
      assert_requested :get, API, query: hash_including("generator" => "categorymembers"),
                                  headers: { "User-Agent" => Nabu::WikiFetch::USER_AGENT }, times: 1
    end
  end
end
