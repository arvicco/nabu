# frozen_string_literal: true

require "test_helper"

# Nabu::SefariaFetch (P30-3): the index-driven named-file fetch shape.
# Upstream is TWO surfaces — a monthly-regenerated books.json index (the git
# repo) and a public GCS bucket of per-version JSON files. One sync GETs the
# index (conditional on the stored Last-Modified), selects the caller's
# subset of version entries, GETs exactly those named files (each with its
# own conditional pin), and lands index + files in canonical — so the scope
# is reproducible from the pinned index. The GitFetch/ZipFetch/FileFetch
# retention contract holds verbatim: the guard sees would-be deletions
# BEFORE any tree mutation, deletions are atticked with a GitFetch-format
# manifest, and a 304 index means a byte-untouched tree. No network:
# WebMock stubs throughout.
class SefariaFetchTest < Minitest::Test
  INDEX_URL = "https://raw.example.org/Sefaria-Export/master/books.json"
  BASE = "https://storage.example.org/sefaria-export"
  LAST_MODIFIED = "Wed, 02 Jul 2026 07:03:07 GMT"

  OBADIAH_REL = "json/Tanakh/Targum/Targum Jonathan/Prophets/Targum Jonathan on Obadiah/Hebrew/Mikraot Gedolot.json"
  TAJ_REL = "json/Tanakh/Targum/Onkelos/Torah/Onkelos Genesis/Hebrew/" \
            "Targum Onkelos, vocalized according to the Yemenite Taj .json"
  OBADIAH_ENC = "#{BASE}/json/Tanakh/Targum/Targum%20Jonathan/Prophets/Targum%20Jonathan%20on%20Obadiah/" \
                "Hebrew/Mikraot%20Gedolot.json".freeze
  TAJ_ENC = "#{BASE}/json/Tanakh/Targum/Onkelos/Torah/Onkelos%20Genesis/Hebrew/" \
            "Targum%20Onkelos%2C%20vocalized%20according%20to%20the%20Yemenite%20Taj%20.json".freeze

  def setup
    @root = Dir.mktmpdir("sefaria-fetch-test")
    @dir = File.join(@root, "sefaria")
    @attic = File.join(@dir, ".attic")
  end

  def teardown
    FileUtils.remove_entry(@root)
    # webmock/minitest chains WebMock.reset! via alias_method :teardown — a
    # custom teardown MUST call super or the request registry accumulates.
    super
  end

  def entry(rel, title: "Targum", version: "V")
    { "title" => title, "language" => "Hebrew", "versionTitle" => version,
      "categories" => %w[Tanakh Targum], "json_url" => "#{BASE}/#{rel}" }
  end

  def index_body(entries)
    JSON.generate({ "generated_at" => "2026-07-02T07:03:07Z", "base_url" => BASE, "books" => entries })
  end

  def stub_index(entries, last_modified: LAST_MODIFIED)
    headers = { "Content-Type" => "application/json" }
    headers["Last-Modified"] = last_modified if last_modified
    stub_request(:get, INDEX_URL).to_return(status: 200, body: index_body(entries), headers: headers)
  end

  def stub_file(encoded_url, body, last_modified: "Tue, 01 Jul 2026 00:00:00 GMT")
    stub_request(:get, encoded_url)
      .to_return(status: 200, body: body, headers: { "Last-Modified" => last_modified })
  end

  # Everything with "Targum" in categories — the shape the adapter passes.
  def sync!(guard: nil, select: ->(e) { e["categories"].include?("Targum") })
    Nabu::SefariaFetch.sync!(index_url: INDEX_URL, dir: @dir, attic_dir: @attic,
                             select: select, guard: guard)
  end

  def test_fresh_sync_lands_index_and_selected_files_at_bucket_relative_paths
    stub_index([entry(OBADIAH_REL), entry(TAJ_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes")
    stub_file(TAJ_ENC, "taj-bytes")

    result = sync!
    assert_equal index_body([entry(OBADIAH_REL), entry(TAJ_REL)]),
                 File.read(File.join(@dir, "books.json")),
                 "the index rides in canonical — the scope stays reproducible"
    assert_equal "obadiah-bytes", File.read(File.join(@dir, OBADIAH_REL))
    assert_equal "taj-bytes", File.read(File.join(@dir, TAJ_REL)),
                 "upstream's trailing-space filename lands verbatim"
    assert_equal Digest::SHA256.hexdigest(index_body([entry(OBADIAH_REL), entry(TAJ_REL)])), result.sha,
                 "the pin is the index body — the sha that names the fetched scope"
    assert_equal 2, result.downloaded
    assert_empty result.atticked
    refute result.not_modified
  end

  def test_bucket_urls_are_percent_encoded_for_the_wire
    stub_index([entry(TAJ_REL)])
    stub_file(TAJ_ENC, "taj-bytes")
    sync!
    assert_requested :get, TAJ_ENC
  end

  def test_unselected_entries_are_never_requested
    merged = entry("json/Tanakh/Targum/X/Hebrew/merged.json", version: "merged")
    other = { "title" => "Genesis", "language" => "English", "versionTitle" => "W",
              "categories" => %w[Tanakh Torah], "json_url" => "#{BASE}/json/Tanakh/Torah/Genesis/English/W.json" }
    stub_index([entry(OBADIAH_REL), merged, other])
    stub_file(OBADIAH_ENC, "obadiah-bytes")

    sync!(select: ->(e) { e["categories"].include?("Targum") && e["versionTitle"] != "merged" })
    assert_requested :get, OBADIAH_ENC
    assert_not_requested :get, %r{#{Regexp.escape(BASE)}/json/Tanakh/Targum/X/}
    assert_not_requested :get, %r{#{Regexp.escape(BASE)}/json/Tanakh/Torah/}
  end

  def test_state_file_pins_index_and_per_file_last_modified_and_sha
    stub_index([entry(OBADIAH_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes", last_modified: "Tue, 01 Jul 2026 00:00:00 GMT")
    sync!
    state = JSON.parse(File.read(File.join(@dir, Nabu::SefariaFetch::STATE_FILE)))
    assert_equal LAST_MODIFIED, state.dig("index", "last_modified")
    assert_equal INDEX_URL, state.dig("index", "url")
    assert_equal "Tue, 01 Jul 2026 00:00:00 GMT", state.dig("files", OBADIAH_REL, "last_modified")
    assert_equal Digest::SHA256.hexdigest("obadiah-bytes"), state.dig("files", OBADIAH_REL, "sha256")
  end

  def test_a_304_index_means_a_byte_untouched_tree
    stub_index([entry(OBADIAH_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes")
    first = sync!

    stub_request(:get, INDEX_URL).with(headers: { "If-Modified-Since" => LAST_MODIFIED })
                                 .to_return(status: 304)
    result = sync!
    assert result.not_modified
    assert_equal first.sha, result.sha, "a 304 repeats the stored pin"
    assert_equal 0, result.downloaded
    assert_equal "obadiah-bytes", File.read(File.join(@dir, OBADIAH_REL))
    assert_not_requested :get, OBADIAH_ENC, times: 2
  end

  def test_per_file_304_keeps_the_file_and_its_pin
    stub_index([entry(OBADIAH_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes", last_modified: "Tue, 01 Jul 2026 00:00:00 GMT")
    sync!

    stub_index([entry(OBADIAH_REL)], last_modified: "Sat, 02 Aug 2026 07:03:07 GMT")
    stub_request(:get, OBADIAH_ENC)
      .with(headers: { "If-Modified-Since" => "Tue, 01 Jul 2026 00:00:00 GMT" })
      .to_return(status: 304)
    result = sync!
    refute result.not_modified, "the index itself changed"
    assert_equal 0, result.downloaded
    assert_equal "obadiah-bytes", File.read(File.join(@dir, OBADIAH_REL))
    state = JSON.parse(File.read(File.join(@dir, Nabu::SefariaFetch::STATE_FILE)))
    assert_equal Digest::SHA256.hexdigest("obadiah-bytes"), state.dig("files", OBADIAH_REL, "sha256")
  end

  def test_a_file_leaving_the_selected_scope_is_atticked_with_a_manifest
    stub_index([entry(OBADIAH_REL), entry(TAJ_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes")
    stub_file(TAJ_ENC, "taj-bytes")
    sync!

    stub_index([entry(OBADIAH_REL)], last_modified: "Sat, 02 Aug 2026 07:03:07 GMT")
    stub_request(:get, OBADIAH_ENC).to_return(status: 304)
    result = sync!
    assert_equal [TAJ_REL], result.atticked
    refute File.exist?(File.join(@dir, TAJ_REL))
    assert_equal "taj-bytes", File.read(File.join(@attic, TAJ_REL)), "first copy wins — the asset is retained"
    manifest = JSON.parse(File.read(File.join(@attic, Nabu::GitFetch::ATTIC_MANIFEST)))
    assert_equal result.sha, manifest[TAJ_REL], "the manifest records the index sha the file vanished at"
  end

  def test_guard_sees_doomed_paths_before_any_mutation_and_may_abort
    stub_index([entry(OBADIAH_REL), entry(TAJ_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes")
    stub_file(TAJ_ENC, "taj-bytes")
    sync!

    stub_index([entry(OBADIAH_REL)], last_modified: "Sat, 02 Aug 2026 07:03:07 GMT")
    seen = nil
    error = Class.new(StandardError)
    assert_raises(error) do
      sync!(guard: lambda { |doomed|
        seen = doomed
        raise error
      })
    end
    assert_equal [File.join(@dir, TAJ_REL)], seen
    assert_equal "taj-bytes", File.read(File.join(@dir, TAJ_REL)), "aborted → tree byte-unchanged"
    refute Dir.exist?(@attic), "aborted → no attic writes"
    assert_not_requested :get, OBADIAH_ENC, times: 2
  end

  def test_state_file_and_attic_are_never_reported_doomed
    stub_index([entry(OBADIAH_REL)])
    stub_file(OBADIAH_ENC, "obadiah-bytes")
    sync!
    FileUtils.mkdir_p(@attic)
    File.write(File.join(@attic, "retained.json"), "retained")

    stub_index([entry(OBADIAH_REL)], last_modified: "Sat, 02 Aug 2026 07:03:07 GMT")
    stub_request(:get, OBADIAH_ENC).to_return(status: 304)
    seen = nil
    sync!(guard: ->(doomed) { seen = doomed })
    assert_empty seen, "the index, state file and attic must never read as upstream deletions"
  end

  def test_malformed_index_json_raises
    stub_request(:get, INDEX_URL).to_return(status: 200, body: "{not json")
    assert_raises(Nabu::SefariaFetch::Error) { sync! }
  end

  def test_index_without_a_books_list_raises
    stub_request(:get, INDEX_URL).to_return(status: 200, body: JSON.generate({ "base_url" => BASE }))
    assert_raises(Nabu::SefariaFetch::Error) { sync! }
  end

  def test_selected_entry_outside_the_bucket_base_raises
    rogue = entry(OBADIAH_REL).merge("json_url" => "https://elsewhere.example.net/x.json")
    stub_request(:get, INDEX_URL).to_return(status: 200, body: index_body([rogue]))
    assert_raises(Nabu::SefariaFetch::Error) { sync! }
  end

  def test_http_failure_on_a_version_file_aborts_with_the_tree_untouched
    stub_index([entry(OBADIAH_REL)])
    stub_request(:get, OBADIAH_ENC).to_return(status: 500)
    assert_raises(Nabu::SefariaFetch::Error) { sync! }
    refute File.exist?(File.join(@dir, "books.json")), "a failed sync writes nothing"
  end

  def test_index_http_failure_raises
    stub_request(:get, INDEX_URL).to_return(status: 500)
    assert_raises(Nabu::SefariaFetch::Error) { sync! }
  end
end
