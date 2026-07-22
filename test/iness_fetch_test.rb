# frozen_string_literal: true

require "test_helper"

# Nabu::InessFetch (P40-2): the CLARINO INESS session-based REST fetch shape.
# Menotec is served ONLY through the INESS portal's ephemeral-session API
# (clarino.uib.no/iness/rest) — there is no git repo and no static raw GET, so
# neither GitFetch nor FileFetch/SefariaFetch applies. One sync walks the
# documented anonymous flow:
#
#   get-session -> list-resources (validate the configured treebanks exist +
#   capture their metadata for the ledger) -> per treebank get-treebank-documents
#   -> per (treebank, document) get-sentences -> write each per-sentence PROIEL-XML
#   stream VERBATIM to <dir>/<treebank>/<document>.xml.
#
# INESS gives no commit sha, so the FetchReport pin is an aggregate sha256 over
# the fetched (relpath, body-sha) set — a reproducible content pin. The
# GitFetch/FileFetch/SefariaFetch retention contract holds verbatim: version
# files staged in memory before any write (a mid-flight HTTP failure leaves the
# tree byte-unchanged), the guard sees would-be deletions BEFORE the tree
# mutates, and deletions are atticked with a GitFetch-format manifest.
#
# RESPONSE SHAPES. Only two facts are evidenced by the fixture README: the
# get-sentences payload lives at `sentences.data` (verbatim), and list-resources
# returns the 7 menotec dependency treebanks (all language "non", type
# "dependency"). The JSON ENVELOPES of get-session / list-resources /
# get-treebank-documents are NOT evidenced by a captured body — they are
# RECONSTRUCTED-FROM-FLOW here from the README's prose, and the fetcher is kept
# loud on every surprise (missing sessionId, a configured treebank absent from
# list-resources, a missing sentences.data). No network: WebMock throughout.
class InessFetchTest < Minitest::Test
  REST = "https://iness.example.org/rest"
  SESSION = "sess-xyz-ephemeral"

  # The fixture treebanks (the real trimmed get-sentences exports).
  PAMPHILUS = "non-pamphilus-dep"
  EDDA = "non-edda-regius-dep"
  FIXTURES = File.expand_path("fixtures/menotec", __dir__)

  def setup
    @root = Dir.mktmpdir("iness-fetch-test")
    @dir = File.join(@root, "menotec")
    @attic = File.join(@dir, ".attic")
    @pamphilus_xml = File.read(File.join(FIXTURES, PAMPHILUS, "ch1-head5.xml"))
    @edda_xml = File.read(File.join(FIXTURES, EDDA, "alvissmal-head5.xml"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super # webmock/minitest resets the request registry via aliased teardown
  end

  # --- canned responses (RECONSTRUCTED-FROM-FLOW envelopes) ----------------

  def json(body)
    { status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" } }
  end

  # get-session -> a sessionId. Field name reconstructed from the README wording.
  def stub_session(id: SESSION)
    stub_request(:get, REST).with(query: hash_including("command" => "get-session"))
                            .to_return(**json("sessionId" => id))
  end

  # list-resources&details=true -> the corpus list. The 7 menotec treebanks
  # (language "non", type "dependency") are evidenced; the {"resources":[...]}
  # envelope is reconstructed.
  def resource(id)
    { "id" => id, "language" => "non", "type" => "dependency", "name" => id.tr("-", " ") }
  end

  def stub_resources(ids: [PAMPHILUS, EDDA])
    stub_request(:get, REST).with(query: hash_including("command" => "list-resources"))
                            .to_return(**json("resources" => ids.map { |id| resource(id) }))
  end

  # get-treebank-documents -> the treebank's document list. Envelope reconstructed.
  def stub_documents(treebank, doc_ids)
    stub_request(:get, REST)
      .with(query: hash_including("command" => "get-treebank-documents", "treebank" => treebank))
      .to_return(**json("documents" => doc_ids.map { |d| { "id" => d } }))
  end

  # get-sentences -> the verbatim PROIEL-XML stream at sentences.data (EVIDENCED).
  def stub_sentences(treebank, document, data)
    stub_request(:get, REST)
      .with(query: hash_including("command" => "get-sentences", "treebank" => treebank,
                                  "document-id" => document))
      .to_return(**json("sentences" => { "data" => data }))
  end

  # The whole happy path: two treebanks, one document each.
  def stub_happy_path
    stub_session
    stub_resources
    stub_documents(PAMPHILUS, ["Ch. 1"])
    stub_documents(EDDA, ["Alvíssmál"])
    stub_sentences(PAMPHILUS, "Ch. 1", @pamphilus_xml)
    stub_sentences(EDDA, "Alvíssmál", @edda_xml)
  end

  def sync!(treebanks: [PAMPHILUS, EDDA], guard: nil)
    Nabu::InessFetch.sync!(base_url: REST, dir: @dir, attic_dir: @attic,
                           treebanks: treebanks, guard: guard)
  end

  # --- fresh sync ----------------------------------------------------------

  def test_fresh_sync_writes_each_document_verbatim_under_its_treebank_subdir
    stub_happy_path
    result = sync!

    pamphilus = File.join(@dir, PAMPHILUS, "Ch.-1.xml")
    edda = File.join(@dir, EDDA, "Alvíssmál.xml")
    assert_equal @pamphilus_xml, File.read(pamphilus), "the sentence stream lands verbatim"
    assert_equal @edda_xml, File.read(edda), "canonical is what upstream serves"
    assert_equal 2, result.documents
    assert_equal [EDDA, PAMPHILUS], result.treebanks
    assert_empty result.atticked
  end

  def test_the_pin_is_a_reproducible_content_sha_over_the_fetched_set
    stub_happy_path
    first = sync!
    refute_nil first.sha

    # A byte-identical re-sync mints the identical pin.
    stub_happy_path
    second = sync!
    assert_equal first.sha, second.sha, "the aggregate content pin is reproducible"
  end

  def test_the_ledger_records_session_date_resource_metadata_and_per_file_shas
    stub_happy_path
    sync!
    ledger = JSON.parse(File.read(File.join(@dir, Nabu::InessFetch::LEDGER_FILE)))
    assert ledger.dig("session", "fetched_at"), "the session date is the non-git pin analogue"
    assert_equal REST, ledger.dig("session", "base_url")
    assert_equal "non", ledger.dig("resources", PAMPHILUS, "language")
    assert_equal "dependency", ledger.dig("resources", EDDA, "type")
    assert_equal Digest::SHA256.hexdigest(@pamphilus_xml),
                 ledger.dig("files", "#{PAMPHILUS}/Ch.-1.xml", "sha256")
  end

  def test_the_session_id_is_threaded_into_every_command_after_get_session
    stub_happy_path
    sync!
    assert_requested :get, REST, times: 2,
                                 query: hash_including("command" => "get-sentences", "session-id" => SESSION)
    assert_requested :get, REST, times: 2,
                                 query: hash_including("command" => "get-treebank-documents", "session-id" => SESSION)
  end

  # --- retention: deletions atticked ---------------------------------------

  def test_a_document_leaving_upstream_is_atticked_with_a_manifest
    stub_happy_path
    sync!

    # Second sync: Pamphilus loses its "Ch. 1" document (empty document list).
    stub_session
    stub_resources
    stub_documents(PAMPHILUS, [])
    stub_documents(EDDA, ["Alvíssmál"])
    stub_sentences(EDDA, "Alvíssmál", @edda_xml)
    result = sync!

    rel = "#{PAMPHILUS}/Ch.-1.xml"
    assert_equal [rel], result.atticked
    refute File.exist?(File.join(@dir, rel)), "the doomed document leaves the live tree"
    assert_equal @pamphilus_xml, File.read(File.join(@attic, rel)), "first copy wins — the asset is retained"
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert_equal result.sha, manifest[rel], "the manifest records the pin the file vanished at"
  end

  def test_guard_sees_doomed_paths_before_any_mutation_and_may_abort
    stub_happy_path
    sync!

    stub_session
    stub_resources
    stub_documents(PAMPHILUS, [])
    stub_documents(EDDA, ["Alvíssmál"])
    stub_sentences(EDDA, "Alvíssmál", @edda_xml)

    seen = nil
    boom = Class.new(StandardError)
    assert_raises(boom) do
      sync!(guard: lambda { |doomed|
        seen = doomed
        raise boom
      })
    end
    assert_equal [File.join(@dir, PAMPHILUS, "Ch.-1.xml")], seen
    assert_equal @pamphilus_xml, File.read(File.join(@dir, PAMPHILUS, "Ch.-1.xml")),
                 "aborted -> tree byte-unchanged"
    refute Dir.exist?(@attic), "aborted -> no attic writes"
  end

  # --- loud failures -------------------------------------------------------

  def test_a_missing_session_id_raises
    stub_request(:get, REST).with(query: hash_including("command" => "get-session"))
                            .to_return(**json("no" => "session here"))
    assert_raises(Nabu::InessFetch::Error) { sync! }
  end

  def test_a_configured_treebank_absent_from_list_resources_raises_loudly
    stub_session
    stub_resources(ids: [EDDA]) # Pamphilus configured but not offered upstream
    assert_raises(Nabu::InessFetch::Error) { sync!(treebanks: [PAMPHILUS, EDDA]) }
  end

  def test_a_missing_sentences_data_payload_raises
    stub_session
    stub_resources(ids: [PAMPHILUS])
    stub_documents(PAMPHILUS, ["Ch. 1"])
    stub_request(:get, REST).with(query: hash_including("command" => "get-sentences"))
                            .to_return(**json("sentences" => { "wrong" => "shape" }))
    assert_raises(Nabu::InessFetch::Error) { sync!(treebanks: [PAMPHILUS]) }
  end

  def test_malformed_json_raises
    stub_request(:get, REST).with(query: hash_including("command" => "get-session"))
                            .to_return(status: 200, body: "{not json")
    assert_raises(Nabu::InessFetch::Error) { sync! }
  end

  def test_an_http_failure_aborts_with_the_tree_untouched
    stub_session
    stub_resources
    stub_documents(PAMPHILUS, ["Ch. 1"])
    stub_documents(EDDA, ["Alvíssmál"])
    stub_sentences(PAMPHILUS, "Ch. 1", @pamphilus_xml)
    stub_request(:get, REST).with(query: hash_including("command" => "get-sentences",
                                                        "treebank" => EDDA))
                            .to_return(status: 500)
    assert_raises(Nabu::InessFetch::Error) { sync! }
    refute Dir.exist?(File.join(@dir, PAMPHILUS)), "a failed sync writes nothing"
  end
end
