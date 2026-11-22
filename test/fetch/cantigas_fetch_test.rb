# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::CantigasFetch (P55-1): the polite letter-index crawl for Cantigas
# Medievais Galego-Portuguesas — 23 alphabetical incipit indexes
# (listacantigas.asp?letra=A..Z, no K/W/Y) enumerate the SPARSE cdcant id
# space (letter A alone reaches 1713), then one page GET per cantiga
# (cantiga.asp?cdcant=N&semanotacoes=true). The ElephantineFetch/OtdoFetch
# mold: prepare! (indexes only, live tree untouched) → guard (mass-deletion
# breaker) → complete! (attic the vanished, land the 23 index sidecars,
# crawl the missing pages skip-on-disk, pin the ledger).
#
# The upstream answers an INVALID id with HTTP 500 (never 404), so a 500 on
# a LISTED id is a real error — retried, then fatal; it is never censused
# away and nothing lands on disk for it.
#
# Fixtures are REAL: fetch/listacantigas-A.html is the whole live letter-A
# index (326 links → 244 unique ids), fetch/listacantigas-Z.html the
# valid-but-empty page, fetch/cantiga-9999-500.html the IIS 500 body — see
# test/fixtures/cantigas/README.md. No network: WebMock throughout.
class CantigasFetchTest < Minitest::Test
  BASE = "https://cantigas.example"
  FIXTURES = Nabu::TestSupport.fixtures("cantigas")

  def setup
    @root = Dir.mktmpdir("cantigas-fetch-test")
    @dir = File.join(@root, "cantigas")
    @attic = File.join(@dir, ".attic")
    @letter_a = File.binread(File.join(FIXTURES, "fetch", "listacantigas-A.html"))
    @empty_letter = File.binread(File.join(FIXTURES, "fetch", "listacantigas-Z.html"))
    @error_body = File.binread(File.join(FIXTURES, "fetch", "cantiga-9999-500.html"))
  end

  def teardown
    FileUtils.remove_entry(@root)
    super # webmock/minitest resets the request registry via aliased teardown
  end

  # Letter A serves the real 244-id index; every other letter the real
  # valid-but-empty page (zero ids contributed honestly).
  def stub_indexes
    Nabu::CantigasFetch::LETTERS.each do |letter|
      body = letter == "A" ? @letter_a : @empty_letter
      stub_request(:get, "#{BASE}/listacantigas.asp?letra=#{letter}")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "text/html" })
    end
  end

  def stub_pages
    stub_request(:get, %r{#{BASE}/cantiga\.asp\?cdcant=\d+&semanotacoes=true})
      .to_return(status: 200, body: "<html>a cantiga page</html>",
                 headers: { "Content-Type" => "text/html" })
  end

  def sync!(guard: nil)
    Nabu::CantigasFetch.sync!(base_url: BASE, dir: @dir, attic_dir: @attic,
                              delay: 0, guard: guard)
  end

  # --- URLs, filenames, predicates -------------------------------------------

  def test_letters_are_the_23_incipit_indexes
    assert_equal 23, Nabu::CantigasFetch::LETTERS.size
    %w[K W Y].each { |letter| refute_includes Nabu::CantigasFetch::LETTERS, letter }
    assert_includes Nabu::CantigasFetch::LETTERS, "Z", "Z is valid-but-empty, still enumerated"
  end

  def test_record_url_rides_semanotacoes_and_drops_pv
    assert_equal "#{BASE}/cantiga.asp?cdcant=600&semanotacoes=true",
                 Nabu::CantigasFetch.record_url(BASE, 600),
                 "semanotacoes=true strips note apparatus, keeps metadata; pv is a cosmetic no-op"
    assert_equal "#{BASE}/listacantigas.asp?letra=A", Nabu::CantigasFetch.index_url(BASE, "A")
  end

  def test_filename_predicates_separate_records_from_index_sidecars
    assert Nabu::CantigasFetch.record?("cantiga-1713.html")
    refute Nabu::CantigasFetch.record?("listacantigas-A.html")
    refute Nabu::CantigasFetch.record?(Nabu::CantigasFetch::STATE_FILE)
    assert_equal "cantiga-600.html", Nabu::CantigasFetch.record_filename(600)
    assert_equal "listacantigas-Z.html", Nabu::CantigasFetch.index_filename("Z")
  end

  # --- the happy path --------------------------------------------------------

  def test_sync_lands_indexes_pages_and_ledger
    stub_indexes
    stub_pages
    result = sync!
    assert_equal 244, result.manifest_count, "the letter-A census: 244 unique cdcant ids"
    assert_equal 244, result.records
    assert_equal 244, result.fetched
    assert_equal 0, result.cached
    assert File.file?(File.join(@dir, "cantiga-1.html")), "min id of the census"
    assert File.file?(File.join(@dir, "cantiga-1713.html")),
           "max id — cdcant is SPARSE, enumeration comes from the indexes, never a sequential probe"
    Nabu::CantigasFetch::LETTERS.each do |letter|
      assert File.file?(File.join(@dir, "listacantigas-#{letter}.html")),
             "letter #{letter} index persists in canonical as a metadata sidecar"
    end
    state = JSON.parse(File.read(File.join(@dir, Nabu::CantigasFetch::STATE_FILE)))
    assert_equal 244, state["manifest_count"]
    assert_equal result.sha, state["sha256"]
  end

  def test_music_icon_duplicate_links_dedupe_by_cdcant
    stub_indexes
    stub_pages
    links = @letter_a.scan(/cantiga\.asp\?cdcant=(\d+)/n).flatten
    assert_equal 326, links.size, "the fixture's raw link count — incipit + music-icon duplicates"
    assert_equal 244, sync!.records, "dedupe proven: 326 links → 244 unique ids"
  end

  def test_sync_sha_ignores_the_index_sidecars
    stub_indexes
    stub_pages
    first = sync!
    # Re-stub letter A with mutated non-link bytes (the live app re-renders
    # per request); cached records are not refetched, so the pin holds.
    stub_request(:get, "#{BASE}/listacantigas.asp?letra=A")
      .to_return(status: 200, body: @letter_a + "<!-- fresh render -->".b)
    second = sync!
    assert_equal first.sha, second.sha, "index bytes stay out of the content pin"
    assert_equal 244, second.cached, "a re-sync re-fetches no page"
    assert_equal 0, second.fetched
  end

  # --- the empty-letter and shape defenses -----------------------------------

  def test_an_empty_letter_contributes_zero_ids_honestly
    stub_indexes
    stub_pages
    sync!
    assert File.file?(File.join(@dir, "listacantigas-Z.html")),
           "the empty page still persists — Z answered, it just lists nothing"
  end

  def test_a_linkless_page_without_the_empty_marker_aborts_before_any_write
    stub_indexes
    stub_request(:get, "#{BASE}/listacantigas.asp?letra=B")
      .to_return(status: 200, body: "<html><body>maintenance</body></html>")
    error = assert_raises(Nabu::CantigasFetch::Error) { sync! }
    assert_match(/letra=B/, error.message, "the abort names the letter")
    assert_match(/marker/, error.message)
    refute Dir.exist?(@dir), "no write happened"
  end

  def test_all_letters_empty_aborts_loudly
    Nabu::CantigasFetch::LETTERS.each do |letter|
      stub_request(:get, "#{BASE}/listacantigas.asp?letra=#{letter}")
        .to_return(status: 200, body: @empty_letter)
    end
    error = assert_raises(Nabu::CantigasFetch::Error) { sync! }
    assert_match(/zero cantiga ids/i, error.message)
  end

  # --- resume (skip-on-disk) -------------------------------------------------

  def test_pages_already_on_disk_are_not_refetched
    stub_indexes
    stub_pages
    FileUtils.mkdir_p(@dir)
    File.write(File.join(@dir, "cantiga-1.html"), "<html>already here</html>")
    result = sync!
    assert_equal 1, result.cached
    assert_equal 243, result.fetched
    assert_not_requested :get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true"
  end

  # --- retention (attic + guard) ---------------------------------------------

  def test_page_no_longer_listed_is_atticked_not_deleted
    stub_indexes
    stub_pages
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "cantiga-99999.html")
    File.write(vanished, "<html>gone upstream</html>")
    seen = nil
    result = sync!(guard: ->(doomed) { seen = doomed })
    assert_equal [vanished], seen, "the guard sees the doomed path BEFORE any mutation"
    refute File.exist?(vanished)
    attic_copy = File.join(@attic, "cantiga-99999.html")
    assert File.file?(attic_copy)
    assert_equal "<html>gone upstream</html>", File.read(attic_copy)
    assert_equal ["cantiga-99999.html"], result.atticked
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert manifest.key?("cantiga-99999.html")
  end

  def test_a_raising_guard_aborts_with_the_tree_byte_unchanged
    stub_indexes
    FileUtils.mkdir_p(@dir)
    vanished = File.join(@dir, "cantiga-99999.html")
    File.write(vanished, "<html>gone upstream</html>")
    assert_raises(Nabu::SyncAborted) do
      sync!(guard: lambda { |_doomed|
        raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
      })
    end
    assert File.file?(vanished), "the doomed file survives an aborted sync"
    assert_equal ["cantiga-99999.html"], Dir.children(@dir), "nothing else was written"
  end

  # --- the 500 posture (the packet's ground truth) ---------------------------

  def test_a_500_on_a_listed_id_is_a_real_error_after_retries_never_censused
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true")
      .to_return(status: 500, body: @error_body)
    error = assert_raises(Nabu::CantigasFetch::Error) { sync! }
    assert_match(/HTTP 500/, error.message)
    assert_match(/attempts/, error.message, "retried to the ceiling, then loud — an invalid id " \
                                            "answers 500 upstream, so a 500 on a LISTED id is real")
    assert_requested :get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true",
                     times: Nabu::CantigasFetch::MAX_ATTEMPTS
    refute File.exist?(File.join(@dir, "cantiga-1.html")), "the error body never lands as a page"
  end

  def test_a_transient_500_recovers_on_retry
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true")
      .to_return({ status: 500, body: @error_body },
                 { status: 200, body: "<html>a cantiga page</html>" })
    result = sync!
    assert_equal 244, result.fetched
    assert_requested :get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true", times: 2
  end

  def test_a_404_on_a_listed_id_is_censused_and_the_crawl_continues
    # Upstream 500s invalid ids today; the P47-i1 census posture still covers
    # a future 404 hole — a lone miss never kills a half-hour polite crawl.
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/cantiga.asp?cdcant=20&semanotacoes=true").to_return(status: 404)
    result = sync!
    assert_equal ["20"], result.missing
    assert_equal 243, result.fetched
    refute File.exist?(File.join(@dir, "cantiga-20.html"))
  end

  def test_a_systemic_miss_rate_still_aborts
    stub_indexes
    stub_request(:get, %r{#{BASE}/cantiga\.asp\?cdcant=\d+&semanotacoes=true})
      .to_return(status: 404)
    error = assert_raises(Nabu::CantigasFetch::Error) { sync! }
    assert_match(/systemic/i, error.message)
    assert_match(/244 of 244/, error.message, "the abort names the miss rate")
  end

  def test_a_transport_error_is_retried_with_backoff_then_succeeds
    stub_indexes
    stub_pages
    stub_request(:get, "#{BASE}/cantiga.asp?cdcant=1&semanotacoes=true")
      .to_raise(Faraday::ConnectionFailed.new("unexpected eof while reading"))
      .then.to_return(status: 200, body: "<html>a cantiga page</html>")
    result = sync!
    assert_equal 244, result.fetched, "one dropped handshake never kills the crawl"
  end

  def test_the_user_agent_names_the_grant
    assert_includes Nabu::CantigasFetch::USER_AGENT, "Littera",
                    "the crawl identifies itself under the grant it fetches by"
    assert_includes Nabu::CantigasFetch::USER_AGENT, "arvicco@nabu.ac"
  end
end
