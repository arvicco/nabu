# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::CorpusCorporumFetch (P80-2): the polite catalog-walk crawl for Corpus
# Córporum (mlat.uzh.ch) — an upstream that is neither a git repo nor a zip
# nor a bulk dump, but a navigate.php catalog tree (corpus → author → work →
# text idnos, namespaced XML) plus a per-text download.php endpoint. The
# ElephantineFetch mold: prepare! (catalog walk only, live tree untouched) →
# guard (mass-deletion breaker on texts the catalog no longer lists) →
# complete! (attic the vanished, download missing texts skip-on-disk, pin
# the ledger).
#
# Resumability is TWO-GRAIN: texts resume by file existence, and the walked
# catalog is checkpointed into the state file BEFORE downloads start, keyed
# per author by the corpus listing's texts_count — a re-sync re-walks only
# authors whose count drifted (PL is a closed 1844–1864 print corpus; the
# steady-state re-sync costs 2 catalog GETs, not ~6,700).
#
# A download.php refusal body ("We are sorry, this XML file doesn't exist or
# can't be downloaded.") is a RECORDED skip — censused in the result and the
# state, no file lands, the crawl continues; a systemic refusal rate aborts.
#
# Fixtures are REAL 2026-08-19 responses (catalog/*.xml, texts/*.xml,
# refusal.txt); corpus-38.xml is a documented trim to the three fixture
# authors. No network: WebMock throughout.
class CorpusCorporumFetchTest < Minitest::Test
  BASE = "https://cc.example"
  NAVIGATE = "#{BASE}/php_modules/navigate.php".freeze
  DOWNLOAD = "#{BASE}/php_modules/download.php".freeze
  FIXTURES = Nabu::TestSupport.fixtures("corpus-corporum")

  AUTHORS = { "2028" => "5420", "2034" => "5434", "2173" => "5783" }.freeze
  TEXTS = %w[10454 10468 10821].freeze
  TEXT_BY_WORK = { "5420" => "10454", "5434" => "10468", "5783" => "10821" }.freeze

  def setup
    @root = Dir.mktmpdir("corpus-corporum-fetch-test")
    @dir = File.join(@root, "corpus-corporum")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def fixture(*parts) = File.read(File.join(FIXTURES, *parts))

  def stub_navigate(path, body)
    stub_request(:get, NAVIGATE).with(query: { "path" => path })
                                .to_return(status: 200, body: body, headers: { "Content-Type" => "text/xml" })
  end

  def stub_catalog
    stub_navigate("/", fixture("catalog", "root.xml"))
    stub_navigate("/38", fixture("catalog", "corpus-38.xml"))
    AUTHORS.each do |author, work|
      stub_navigate("/38/#{author}", fixture("catalog", "author-#{author}.xml"))
      stub_navigate("/38/#{author}/#{work}", fixture("catalog", "work-#{work}.xml"))
    end
  end

  def stub_texts(except: [])
    (TEXTS - except).each do |idno|
      stub_request(:get, DOWNLOAD).with(query: { "idno" => idno, "type" => "file-xml" })
                                  .to_return(status: 200, body: fixture("texts", "#{idno}.xml"))
    end
  end

  def stub_refusal(idno)
    stub_request(:get, DOWNLOAD).with(query: { "idno" => idno, "type" => "file-xml" })
                                .to_return(status: 200, body: fixture("refusal.txt"))
  end

  def sync!(guard: nil)
    Nabu::CorpusCorporumFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic,
                                    delay: 0, guard: guard)
  end

  # --- URL construction ------------------------------------------------------

  def test_url_helpers_build_the_de_facto_api_urls
    assert_equal "#{BASE}/php_modules/navigate.php?path=/38",
                 Nabu::CorpusCorporumFetch.navigate_url(BASE, "/38")
    assert_equal "#{BASE}/php_modules/download.php?idno=10454&type=file-xml",
                 Nabu::CorpusCorporumFetch.download_url(BASE, "10454")
  end

  # --- the full walk ---------------------------------------------------------

  def test_sync_walks_the_catalog_and_lands_each_text_under_texts
    stub_catalog
    stub_texts
    result = sync!

    TEXTS.each do |idno|
      path = File.join(@dir, "texts", "#{idno}.xml")
      assert File.file?(path), "texts/#{idno}.xml must land"
      assert_equal fixture("texts", "#{idno}.xml"), File.read(path), "landed bytes are upstream bytes"
    end
    assert_equal 3, result.fetched
    assert_equal 0, result.cached
    assert_empty result.refused
    assert_equal 0, result.inaccessible
    assert_equal 3, result.texts
    assert_match(/\A[0-9a-f]{64}\z/, result.sha)

    census = result.corpora.find { |row| row["idno"] == "38" }
    assert_equal "Patrologia Latina", census["name"]
    assert_equal 5277, census["texts_count"], "the root listing's census rides the result"
    assert_equal 85_539_587, census["words_count"]
  end

  def test_sync_writes_a_state_file_with_the_catalog_checkpoint
    stub_catalog
    stub_texts
    result = sync!

    state = JSON.parse(File.read(File.join(@dir, Nabu::CorpusCorporumFetch::STATE_FILE)))
    assert_equal result.sha, state["sha256"]
    assert_equal BASE, state["url"]
    AUTHORS.each_key do |author|
      assert_equal 1, state.dig("catalog", author, "texts_count"), "author #{author} checkpointed"
    end
    assert_equal %w[10454 10468 10821],
                 state["catalog"].values.flat_map { |row| row["texts"].map { |t| t["idno"] } }.sort
  end

  # --- the dating capture (P81-1) --------------------------------------------
  #
  # The walked author/work listings carry time_data the crawl previously
  # discarded: per-author born/died events, per-work work_composition years.
  # Both pages are already requested — the capture costs zero extra GETs
  # and rides the same checkpoint, where the parser reads it at parse time.

  def test_the_walk_checkpoints_author_and_work_composition_years
    stub_catalog
    stub_texts
    sync!

    state = JSON.parse(File.read(File.join(@dir, Nabu::CorpusCorporumFetch::STATE_FILE)))
    assert_equal Nabu::CorpusCorporumFetch::CATALOG_SCHEMA, state["catalog_schema"]

    petrus = state.dig("catalog", "2028")
    assert_equal 850, petrus["born"], "author-page time_data event what='born'"
    assert_nil petrus["died"], "no died event — never guessed"
    assert_equal [892, 892], petrus["texts"].first["work_composition"],
                 "the work page's work_composition year rides the text row"

    wido = state.dig("catalog", "2034")
    assert_equal 992, wido["born"]
    assert_equal 1050, wido["died"], "the certainty='between' died event envelopes to its latest year"
    assert_equal [1000, 1000], wido["texts"].first["work_composition"]

    abbaudus = state.dig("catalog", "2173")
    assert_equal [1100, 1199], [abbaudus["born"], abbaudus["died"]]
    assert_equal [1130, 1130], abbaudus["texts"].first["work_composition"]
  end

  def test_a_pre_dating_checkpoint_is_not_reused
    stub_catalog
    stub_texts
    sync!

    # Rewrite the state as a schema-1 (pre-P81) checkpoint: no
    # catalog_schema key, no years — the walk must NOT reuse it, or the
    # dating lane would stay dark until texts_count drifts (PL is closed:
    # it never does).
    path = File.join(@dir, Nabu::CorpusCorporumFetch::STATE_FILE)
    state = JSON.parse(File.read(path))
    state.delete("catalog_schema")
    state["catalog"].each_value do |row|
      row.delete("born")
      row.delete("died")
      row["texts"].each { |t| t.delete("work_composition") }
    end
    File.write(path, JSON.pretty_generate(state))

    sync!
    AUTHORS.each do |author, work|
      assert_requested :get, NAVIGATE, query: { "path" => "/38/#{author}" }, times: 2
      assert_requested :get, NAVIGATE, query: { "path" => "/38/#{author}/#{work}" }, times: 2
    end
    refreshed = JSON.parse(File.read(path))
    assert_equal 850, refreshed.dig("catalog", "2028", "born"), "the re-walk captured the years"
  end

  # --- resume ----------------------------------------------------------------

  def test_a_text_already_on_disk_is_never_refetched
    stub_catalog
    stub_texts(except: ["10454"]) # no stub: a request for it would raise
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    FileUtils.cp(File.join(FIXTURES, "texts", "10454.xml"), File.join(@dir, "texts", "10454.xml"))

    result = sync!
    assert_equal 2, result.fetched
    assert_equal 1, result.cached
  end

  def test_a_resync_reuses_the_checkpointed_catalog_and_downloads_nothing
    stub_catalog
    stub_texts
    sync!
    result = sync!

    assert_equal 0, result.fetched
    assert_equal 3, result.cached
    # Root + corpus listings refresh every sync; author/work listings are
    # only re-walked when the corpus listing's per-author texts_count drifts.
    assert_requested :get, NAVIGATE, query: { "path" => "/" }, times: 2
    assert_requested :get, NAVIGATE, query: { "path" => "/38" }, times: 2
    AUTHORS.each do |author, work|
      assert_requested :get, NAVIGATE, query: { "path" => "/38/#{author}" }, times: 1
      assert_requested :get, NAVIGATE, query: { "path" => "/38/#{author}/#{work}" }, times: 1
    end
  end

  # --- the refusal body (a recorded skip, never a crash) ---------------------

  def test_a_refusal_body_is_censused_and_leaves_no_file_on_disk
    stub_catalog
    stub_texts(except: ["10468"])
    stub_refusal("10468")

    result = sync!
    assert_equal ["10468"], result.refused
    assert_equal 2, result.fetched
    refute File.exist?(File.join(@dir, "texts", "10468.xml")), "a refusal never lands as a file"
    state = JSON.parse(File.read(File.join(@dir, Nabu::CorpusCorporumFetch::STATE_FILE)))
    assert_equal ["10468"], state["refused"], "the recorded skip survives into the state"

    # The next sync re-attempts (upstream may unlock a text); it stays a
    # recorded skip while the refusal persists.
    result = sync!
    assert_equal ["10468"], result.refused
    assert_requested :get, DOWNLOAD, query: { "idno" => "10468", "type" => "file-xml" }, times: 2
  end

  # P80-r2 (the live 9-hour crawl death, 2026-08-20): after 3,485 clean
  # texts, ONE transient 200 body that was neither TEI nor the refusal
  # killed the whole run at idno 9740 — which served perfectly valid TEI
  # on re-probe. A wrong-shape 200 is now retried with backoff, and a
  # PERSISTENT one is a recorded malformed skip (the refusal mold,
  # re-attempted next sync) counted against the same systemic cap —
  # endpoint drift still aborts, one flake never does.
  def test_a_transient_garbage_body_is_retried_then_fetched
    stub_catalog
    stub_texts(except: ["10468"])
    stub_request(:get, DOWNLOAD).with(query: { "idno" => "10468", "type" => "file-xml" })
                                .to_return({ status: 200, body: "<html>gateway hiccup</html>" },
                                           { status: 200, body: fixture("texts", "10468.xml") })

    result = sync!
    assert_equal 3, result.fetched
    assert_empty result.malformed
    assert File.exist?(File.join(@dir, "texts", "10468.xml")), "the retry lands the real body"
    assert_requested :get, DOWNLOAD, query: { "idno" => "10468", "type" => "file-xml" }, times: 2
  end

  def test_a_persistent_garbage_body_is_a_recorded_malformed_skip
    stub_catalog
    stub_texts(except: ["10468"])
    stub_request(:get, DOWNLOAD).with(query: { "idno" => "10468", "type" => "file-xml" })
                                .to_return(status: 200, body: "<html>always broken</html>")

    result = sync!
    assert_equal ["10468"], result.malformed
    assert_equal 2, result.fetched, "the crawl continues past the malformed text"
    refute File.exist?(File.join(@dir, "texts", "10468.xml")), "garbage never lands as a file"
    state = JSON.parse(File.read(File.join(@dir, Nabu::CorpusCorporumFetch::STATE_FILE)))
    assert_equal ["10468"], state["malformed"], "the recorded skip survives into the state"
  end

  # --- the truncation / shape-drift defense ----------------------------------

  def test_a_walk_that_undercounts_the_corpus_listing_aborts_before_any_write
    stub_catalog
    # Real bytes, wrong shape: an author listing served where a work listing
    # was promised carries no <text> entries — the walk finds 2 of the 3
    # texts the corpus listing promises.
    stub_navigate("/38/2173/5783", fixture("catalog", "author-2173.xml"))
    stub_texts

    error = assert_raises(Nabu::CorpusCorporumFetch::Error) { sync! }
    assert_match(/2 of 3/, error.message)
    refute Dir.exist?(File.join(@dir, "texts")), "the defense aborts before any write"
  end

  # --- retention (attic + breaker) -------------------------------------------

  def test_a_text_the_catalog_no_longer_lists_is_atticked_not_deleted
    stub_catalog
    stub_texts
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    File.write(File.join(@dir, "texts", "99999.xml"), "<TEI>stray</TEI>")

    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [File.join(@dir, "texts", "99999.xml")], seen,
                 "the guard sees the doomed absolute paths between prepare! and complete!"
    assert_equal [File.join("texts", "99999.xml")], result.atticked
    refute File.exist?(File.join(@dir, "texts", "99999.xml"))
    assert_equal "<TEI>stray</TEI>", File.read(File.join(@attic, "texts", "99999.xml")),
                 "the attic preserves the vanished bytes"
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?(File.join("texts", "99999.xml")), "the attic manifest records the pin"
  end

  def test_a_raising_guard_aborts_with_the_tree_unchanged
    stub_catalog
    stub_texts
    FileUtils.mkdir_p(File.join(@dir, "texts"))
    File.write(File.join(@dir, "texts", "99999.xml"), "<TEI>stray</TEI>")

    breaker = lambda do |_doomed|
      raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
    end
    assert_raises(Nabu::SyncAborted) { sync!(guard: breaker) }
    assert File.file?(File.join(@dir, "texts", "99999.xml")), "the doomed file is untouched"
    refute File.exist?(File.join(@dir, "texts", "10454.xml")), "no download ran"
  end
end
