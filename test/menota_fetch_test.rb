# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::MenotaFetch (P82-1): the polite session-based crawl for the Menota
# archive — the Corpuscle (korpuskel) REST API behind the catalogue SPA at
# clarino.uib.no/menota/catalogue/menota. Flow: get-session →
# list-catalogue-documents (paged) → per-document download-document
# ({"data": "<TEI …>"}), plus the menota.org MUFI entity table the DOCTYPE
# of every text pulls. The CorpusCorporumFetch mold: prepare! (catalogue
# walk only, live tree untouched) → guard (mass-deletion breaker on texts
# the catalogue no longer lists) → complete! (attic the vanished,
# checkpoint the catalogue, download missing texts skip-on-disk, pin the
# ledger).
#
# The №77-1 grant's promises are REQUIREMENTS tested here: sequential
# rate-limited requests, honest User-Agent, once-per-text caching (a text
# on disk is never re-requested).
#
# Fixtures are REAL 2026-08-23 captures (catalogue/*.json, texts/*.xml,
# menota-entities.txt); catalogue pages beyond the envelope-shape pin are
# doctored in-test from the real rows. No network: WebMock throughout.
class MenotaFetchTest < Minitest::Test
  BASE = "https://korpuskel.example"
  REST = "#{BASE}/rest".freeze
  ENTITIES_URL = "https://entities.example/menota-entities.txt"
  FIXTURES = Nabu::TestSupport.fixtures("menota")

  DOCUMENTS = %w[AM-1056-IX-4to Holm-A-80 NRA-norrfragm-60-A].freeze

  def setup
    @root = Dir.mktmpdir("menota-fetch-test")
    @dir = File.join(@root, "menota")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def fixture(*parts) = File.read(File.join(FIXTURES, *parts))

  def session_id = JSON.parse(fixture("catalogue", "get-session.json"))["sessionId"]

  def stub_session
    stub_request(:get, REST).with(query: { "command" => "get-session" })
                            .to_return(status: 200, body: fixture("catalogue", "get-session.json"))
  end

  # A one-page catalogue built from the REAL page-fixture rows: the three
  # fixture documents, documentCount matching (test doctoring of real rows —
  # the fixture envelope itself is pinned by the shape test below).
  def catalogue_body(ids: DOCUMENTS)
    rows = JSON.parse(fixture("catalogue", "list-page-0-2.json"))["documents"]
    rows_by_id = rows.to_h { |row| [row["documentId"], row] }
    kept = ids.map do |id|
      rows_by_id[id] || rows_by_id["AM-1056-IX-4to"].merge("documentId" => id)
    end
    JSON.generate({ "documents" => kept, "documentCount" => kept.size })
  end

  def stub_catalogue(body: catalogue_body, start: 0)
    stub_request(:get, REST)
      .with(query: { "command" => "list-catalogue-documents", "session-id" => session_id,
                     "corpus" => "menota", "start" => start.to_s,
                     "end" => (start + Nabu::MenotaFetch::PAGE_SIZE - 1).to_s })
      .to_return(status: 200, body: body)
  end

  def stub_downloads(except: [])
    (DOCUMENTS - except).each do |id|
      stub_request(:get, REST)
        .with(query: { "command" => "download-document", "session-id" => session_id,
                       "corpus" => "menota", "document-id" => id })
        .to_return(status: 200, body: JSON.generate({ "data" => fixture("texts", "#{id}.xml") }))
    end
  end

  def stub_entities
    stub_request(:get, ENTITIES_URL)
      .to_return(status: 200, body: fixture("menota-entities.txt"))
  end

  def stub_all
    stub_session
    stub_catalogue
    stub_downloads
    stub_entities
  end

  def sync!(guard: nil)
    Nabu::MenotaFetch.sync!(base_url: BASE, entities_url: ENTITIES_URL, dir: @dir,
                            attic_dir: @attic, delay: 0, guard: guard)
  end

  # --- URL construction ------------------------------------------------------

  def test_rest_url_builds_the_command_urls
    assert_equal "#{REST}?command=get-session", Nabu::MenotaFetch.rest_url(BASE, "get-session")
    assert_equal "#{REST}?command=download-document&session-id=1&corpus=menota&document-id=AM-1056-IX-4to",
                 Nabu::MenotaFetch.rest_url(BASE, "download-document", "session-id" => "1",
                                                                       "corpus" => "menota",
                                                                       "document-id" => "AM-1056-IX-4to")
  end

  # --- the full crawl --------------------------------------------------------

  def test_sync_lands_each_text_and_the_entity_table
    stub_all
    result = sync!

    DOCUMENTS.each do |id|
      path = File.join(@dir, "texts", "#{id}.xml")
      assert File.file?(path), "texts/#{id}.xml must land"
      assert_equal fixture("texts", "#{id}.xml"), File.read(path),
                   "landed bytes are the envelope's data string verbatim"
    end
    assert File.file?(File.join(@dir, "menota-entities.txt")),
           "the MUFI entity table lands beside texts/ (the DOCTYPE dependency)"
    assert_equal 3, result.fetched
    assert_equal 0, result.cached
    assert_empty result.refused
    assert_empty result.malformed
    assert_equal 3, result.documents
    assert_match(/\A[0-9a-f]{64}\z/, result.sha)
  end

  def test_the_real_catalogue_envelope_parses_and_documentcount_rules_the_walk
    # The REAL page fixture: 3 rows, documentCount 91 — a walk whose later
    # pages come back empty is TRUNCATED and aborts before any write.
    stub_session
    stub_catalogue(body: fixture("catalogue", "list-page-0-2.json"))
    stub_catalogue(body: JSON.generate({ "documents" => [], "documentCount" => 91 }),
                   start: 3) # paging resumes at the rows walked so far
    error = assert_raises(Nabu::MenotaFetch::Error) { sync! }
    assert_match(/TRUNCATED/i, error.message)
    refute Dir.exist?(File.join(@dir, "texts")), "no write before the walk completes"
  end

  def test_the_real_download_envelope_shape_is_the_data_field
    stub_session
    stub_catalogue(body: catalogue_body(ids: ["AM-1056-IX-4to"]))
    stub_entities
    stub_request(:get, REST)
      .with(query: { "command" => "download-document", "session-id" => session_id,
                     "corpus" => "menota", "document-id" => "AM-1056-IX-4to" })
      .to_return(status: 200, body: fixture("catalogue", "download-AM-1056-IX-4to.json"))
    sync!
    assert_equal fixture("texts", "AM-1056-IX-4to.xml"),
                 File.read(File.join(@dir, "texts", "AM-1056-IX-4to.xml")),
                 "the real envelope's decoded data field is the landed fixture byte-for-byte"
  end

  def test_requests_carry_the_honest_user_agent
    stub_all
    sync!
    assert_requested(:get, REST, query: hash_including("command" => "get-session"),
                                 headers: { "User-Agent" => Nabu::MenotaFetch::USER_AGENT })
    assert_match(/nabu/, Nabu::MenotaFetch::USER_AGENT)
    assert_match(%r{github\.com/arvicco/nabu}, Nabu::MenotaFetch::USER_AGENT)
  end

  # --- once-per-text caching (the grant promise) -----------------------------

  def test_a_second_sync_downloads_nothing_already_on_disk
    stub_all
    sync!
    WebMock.reset!
    stub_session
    stub_catalogue
    result = sync!
    assert_equal 0, result.fetched
    assert_equal 3, result.cached, "texts resume by file existence — never re-requested"
  end

  def test_the_entity_table_is_fetched_once
    stub_all
    sync!
    WebMock.reset!
    stub_session
    stub_catalogue
    sync! # no stub_entities: a re-request would raise WebMock::NetConnectNotAllowedError
    assert File.file?(File.join(@dir, "menota-entities.txt"))
  end

  # --- the state file --------------------------------------------------------

  def test_sync_writes_the_catalogue_checkpoint_state
    stub_all
    result = sync!
    state = JSON.parse(File.read(File.join(@dir, Nabu::MenotaFetch::STATE_FILE)))
    assert_equal BASE, state["url"]
    assert_equal result.sha, state["sha256"]
    assert_equal 3, state["documents"]
    rows = state["catalogue"]
    assert_equal DOCUMENTS.sort, rows.map { |row| row["documentId"] }.sort
    row = rows.find { |r| r["documentId"] == "AM-1056-IX-4to" }
    assert_equal "CC-BY-SA 4.0", row["license"], "the quotable license column rides the ledger"
    assert_equal "nor", row["language"]
    assert_equal "c. 1300", row["origDate"]
  end

  def test_sha_is_stable_across_syncs_with_unchanged_texts
    stub_all
    first = sync!
    WebMock.reset!
    stub_session
    stub_catalogue
    assert_equal first.sha, sync!.sha
  end

  # --- error envelopes -------------------------------------------------------

  def test_an_error_envelope_on_download_is_a_recorded_skip_after_a_session_refresh
    stub_session
    stub_catalogue
    stub_entities
    stub_downloads(except: ["Holm-A-80"])
    stub_request(:get, REST)
      .with(query: { "command" => "download-document", "session-id" => session_id,
                     "corpus" => "menota", "document-id" => "Holm-A-80" })
      .to_return(status: 200, body: JSON.generate({ "error" => "No such file or directory" }))
    result = sync!
    assert_equal 2, result.fetched
    assert_equal ["Holm-A-80"], result.refused, "an error envelope is a recorded skip, not an abort"
    refute File.exist?(File.join(@dir, "texts", "Holm-A-80.xml"))
    state = JSON.parse(File.read(File.join(@dir, Nabu::MenotaFetch::STATE_FILE)))
    assert_equal ["Holm-A-80"], state["refused"], "re-attempted next sync (no file on disk)"
  end

  def test_a_systemic_refusal_rate_aborts
    stub_session
    stub_catalogue
    stub_entities
    DOCUMENTS.each do |id|
      stub_request(:get, REST)
        .with(query: { "command" => "download-document", "session-id" => session_id,
                       "corpus" => "menota", "document-id" => id })
        .to_return(status: 200, body: JSON.generate({ "error" => "boom" }))
    end
    error = assert_raises(Nabu::MenotaFetch::Error) { sync! }
    assert_match(/systemic/i, error.message)
  end

  def test_a_get_session_error_envelope_aborts
    stub_request(:get, REST).with(query: { "command" => "get-session" })
                            .to_return(status: 200, body: JSON.generate({ "error" => "down" }))
    assert_raises(Nabu::MenotaFetch::Error) { sync! }
  end

  # --- retention: attic + breaker --------------------------------------------

  def test_a_delisted_text_is_atticked_behind_the_guard
    stub_all
    sync!
    WebMock.reset!
    stub_session
    stub_catalogue(body: catalogue_body(ids: DOCUMENTS - ["NRA-norrfragm-60-A"]))
    guarded = nil
    result = Nabu::MenotaFetch.sync!(base_url: BASE, entities_url: ENTITIES_URL, dir: @dir,
                                     attic_dir: @attic, delay: 0,
                                     guard: ->(doomed) { guarded = doomed })
    assert_equal [File.join(@dir, "texts", "NRA-norrfragm-60-A.xml")], guarded,
                 "the guard sees the doomed absolute paths before any deletion"
    assert_equal ["texts/NRA-norrfragm-60-A.xml"], result.atticked
    assert File.file?(File.join(@attic, "texts", "NRA-norrfragm-60-A.xml")),
           "the delisted text is preserved under the attic"
    refute File.exist?(File.join(@dir, "texts", "NRA-norrfragm-60-A.xml"))
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("texts/NRA-norrfragm-60-A.xml")
  end

  def test_a_raising_guard_aborts_with_the_tree_unchanged
    stub_all
    sync!
    WebMock.reset!
    stub_session
    stub_catalogue(body: catalogue_body(ids: ["AM-1056-IX-4to"]))
    assert_raises(RuntimeError) do
      Nabu::MenotaFetch.sync!(base_url: BASE, entities_url: ENTITIES_URL, dir: @dir,
                              attic_dir: @attic, delay: 0,
                              guard: ->(_doomed) { raise "breaker" })
    end
    DOCUMENTS.each do |id|
      assert File.file?(File.join(@dir, "texts", "#{id}.xml")), "tree byte-unchanged on abort"
    end
  end
end
