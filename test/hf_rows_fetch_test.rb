# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::HfRowsFetch: the text-column projection of a Hugging Face dataset
# through the datasets-server /rows API. Runs against WebMock stubs serving
# REAL responses (test/fixtures/bdrc-transcriptions/fetch/ — two real
# 3-row pages of BDRC/berkeley-transcriptions with num_rows_total trimmed
# to 6 and the signed image-asset query strings trimmed); never the network.
class HfRowsFetchTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("bdrc-transcriptions"), "fetch")
  REPO = "BDRC/berkeley-transcriptions"
  REVISION = "ed7b6318146f00b48c01f5f15b7425ad3269489f"
  API_URL = "https://huggingface.co/api/datasets/#{REPO}".freeze
  ROWS_URL = "https://datasets-server.huggingface.co/rows"
  CARD_URL = "https://huggingface.co/datasets/#{REPO}/resolve/#{REVISION}/README.md".freeze
  SUBSET_URL = "https://huggingface.co/datasets/#{REPO}/resolve/#{REVISION}/subset_info.json".freeze

  # Group pages by the etext INSTANCE (IE…) so one file holds two rows —
  # the grouping and the in-file sort are both exercised.
  DOCUMENT_PATH = ->(row) { "#{row.fetch('id').split(':')[2]}.jsonl" }
  SORT_KEY = ->(row) { row.fetch("id").split(":").last }

  def fixture(name) = File.read(File.join(FIXTURES, name))

  def stub_dataset(revision: REVISION, page_revision: REVISION)
    api = fixture("api-dataset.json").sub(REVISION, revision)
    stub_request(:get, API_URL).to_return(status: 200, body: api, headers: { "Content-Type" => "application/json" })
    [0, 3].each do |offset|
      stub_request(:get, ROWS_URL)
        .with(query: { "dataset" => REPO, "config" => "default", "split" => "train",
                       "offset" => offset.to_s, "length" => "3" })
        .to_return(status: 200, body: fixture("rows-offset-#{offset}.json"),
                   headers: { "Content-Type" => "application/json", "X-Revision" => page_revision })
    end
    stub_request(:get, CARD_URL).to_return(status: 200, body: fixture("README.md"))
    stub_request(:get, SUBSET_URL).to_return(status: 200, body: fixture("subset_info.json"))
  end

  def sync(dir, **)
    Nabu::HfRowsFetch.sync!(repo: REPO, dir: dir, attic_dir: File.join(dir, ".attic"),
                            document_path: DOCUMENT_PATH, sort_key: SORT_KEY,
                            sidecars: %w[README.md subset_info.json], page_length: 3, delay: 0, **)
  end

  def test_projects_every_row_into_its_document_file_sorted_and_without_the_image_cell
    stub_dataset
    Dir.mktmpdir do |dir|
      result = sync(dir)
      assert_equal REVISION, result.revision
      assert_equal 6, result.rows
      assert_equal 5, result.documents, "6 pages over 5 etext instances (IE30498 holds two volumes' pages)"
      refute result.not_modified

      lines = File.readlines(File.join(dir, "IE30498_MA.jsonl")).map { |line| JSON.parse(line) }
      assert_equal(%w[I1CZ47920484.tif I1CZ48240174.tif], lines.map { |row| row["id"].split(":").last })
      lines.each do |row|
        refute row.key?("image"), "the Image feature never lands on disk"
        refute row.key?("row_idx"), "the API's shuffle-dependent row_idx is not part of the asset"
        assert row.fetch("transcription").start_with?("༄") || !row.fetch("transcription").empty?
      end
      refute_match(/cached-assets/, Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
                                      .select { |path| File.file?(path) }.map { |path| File.read(path) }.join)
      assert_equal fixture("README.md"), File.read(File.join(dir, "README.md")), "the dataset card is pinned"
      refute Dir.exist?(File.join(dir, Nabu::HfRowsFetch::STAGING_DIR)), "staging is cleared on completion"
    end
  end

  # The design guarantee: the fetch talks ONLY to the dataset API, the
  # rows endpoint and the revision-pinned sidecar files — never to an
  # image asset URL, even though every row response names one.
  def test_never_requests_an_image_asset
    stub_dataset
    Dir.mktmpdir do |dir|
      sync(dir)
      assert_not_requested :get, %r{datasets-server\.huggingface\.co/cached-assets}
      assert_not_requested :get, /\.parquet/
      assert_requested :get, ROWS_URL, query: hash_including("offset" => "0"), times: 1
      assert_requested :get, ROWS_URL, query: hash_including("offset" => "3"), times: 1
    end
  end

  def test_an_unchanged_revision_is_not_modified_and_requests_no_rows
    stub_dataset
    Dir.mktmpdir do |dir|
      first = sync(dir)
      second = sync(dir)
      assert second.not_modified
      assert_equal first.sha, second.sha
      assert_requested :get, ROWS_URL, query: hash_including("offset" => "0"), times: 1
    end
  end

  def test_a_revision_moving_mid_fetch_aborts_with_the_tree_untouched
    stub_dataset(page_revision: "0" * 40)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::HfRowsFetch::Error) { sync(dir) }
      assert_match(/revision/, error.message)
      assert_empty Dir.glob(File.join(dir, "*.jsonl"))
    end
  end

  def test_a_truncated_kept_cell_aborts
    body = JSON.parse(fixture("rows-offset-0.json"))
    body["rows"][0]["truncated_cells"] = ["transcription"]
    stub_dataset
    stub_request(:get, ROWS_URL).with(query: hash_including("offset" => "0"))
                                .to_return(status: 200, body: JSON.generate(body),
                                           headers: { "X-Revision" => REVISION })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::HfRowsFetch::Error) { sync(dir) }
      assert_match(/truncated/, error.message)
    end
  end

  def test_rate_limited_pages_retry_then_land
    stub_dataset
    stub_request(:get, ROWS_URL).with(query: hash_including("offset" => "3"))
                                .to_return({ status: 429, body: "" },
                                           { status: 200, body: fixture("rows-offset-3.json"),
                                             headers: { "X-Revision" => REVISION } })
    Dir.mktmpdir do |dir|
      assert_equal 6, sync(dir).rows
    end
  end

  # Resume at the page grain: an interrupted fetch keeps its staged pages
  # (keyed by revision) and the next run requests only the missing ones.
  def test_resumes_from_staged_pages
    stub_dataset
    stub_request(:get, ROWS_URL).with(query: hash_including("offset" => "3")).to_return(status: 500, body: "")
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::HfRowsFetch::Error) { sync(dir, max_attempts: 1) }
      WebMock.reset!
      stub_dataset
      assert_equal 6, sync(dir).rows
      assert_not_requested :get, ROWS_URL, query: hash_including("offset" => "0")
    end
  end

  def test_a_vanished_document_is_atticked_after_the_guard_sees_it
    stub_dataset
    Dir.mktmpdir do |dir|
      sync(dir)
      File.write(File.join(dir, "IE0GONE_MA.jsonl"), "{\"id\":\"x\"}\n")
      File.write(File.join(dir, Nabu::HfRowsFetch::STATE_FILE), "{}")
      seen = nil
      result = sync(dir, guard: ->(doomed) { seen = doomed })
      assert_equal [File.join(dir, "IE0GONE_MA.jsonl")], seen
      assert_equal ["IE0GONE_MA.jsonl"], result.atticked
      assert File.file?(File.join(dir, ".attic", "IE0GONE_MA.jsonl"))
      refute File.exist?(File.join(dir, "IE0GONE_MA.jsonl"))
    end
  end

  def test_a_tripped_guard_leaves_the_tree_byte_unchanged
    stub_dataset
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "IE0GONE_MA.jsonl"), "{\"id\":\"x\"}\n")
      assert_raises(Nabu::SyncAborted) do
        sync(dir, guard: lambda { |_doomed|
          raise Nabu::SyncAborted.new(existing_count: 1, would_withdraw_count: 1, threshold: 0.2)
        })
      end
      assert_equal ["IE0GONE_MA.jsonl"], Dir.children(dir).grep(/\.jsonl\z/)
    end
  end
end
