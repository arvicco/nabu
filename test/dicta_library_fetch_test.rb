# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::DictaLibraryFetch: the per-book crawl behind dicta-library — the
# manifest (the real trimmed books.json fixture) names each book's zips; the
# crawl writes a sidecar + the text zip per book at once (resumable), adds the
# vocalized zip only when the text zip is empty, censuses 404s, aborts on a
# systemic miss or a malformed manifest before any write. WebMock answers with
# the real fixture zips.
class DictaLibraryFetchTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("dicta-library")
  MANIFEST = File.join(FIXTURES, "books.json")

  def setup
    @root = Dir.mktmpdir("dicta-library-fetch-test")
    @dir = File.join(@root, "books")
  end

  def teardown
    FileUtils.remove_entry(@root)
    super
  end

  def entries = JSON.parse(File.read(MANIFEST))

  def stub_all
    entries.each do |entry|
      %w[textFileURL nikudMetegFileURL].each do |key|
        local = File.join(FIXTURES, "books", File.basename(entry[key]))
        stub_request(:get, entry[key]).to_return(status: 200, body: File.binread(local)) if File.file?(local)
      end
    end
  end

  def sync!(manifest = MANIFEST)
    Nabu::DictaLibraryFetch.sync!(manifest_path: manifest, dir: @dir, delay: 0)
  end

  def test_a_first_sync_lands_sidecars_text_zips_and_the_empty_text_fallbacks
    stub_all
    result = sync!
    assert_equal 6, result.books
    assert_equal 8, result.fetched, "6 text zips + 2 vocalized fallbacks (maharamlublin, chidusheiharadad)"
    assert_equal %w[maharamlublin chidusheiharadad], result.fallbacks
    assert_empty result.missing
    assert File.file?(File.join(@dir, "birkatcohen.json"))
    assert_equal File.binread(File.join(FIXTURES, "books", "birkatcohen__text_files.zip")),
                 File.binread(File.join(@dir, "birkatcohen__text_files.zip"))
    refute File.exist?(File.join(@dir, "birkatcohen__nikud_meteg_files.zip")),
           "the vocalized layer of a held text is never fetched"
    sidecar = JSON.parse(File.read(File.join(@dir, "sefatemetmoed1.json")))
    assert_equal "1925-1931", sidecar["printYear"]
    state = JSON.parse(File.read(File.join(@dir, Nabu::DictaLibraryFetch::STATE_FILE)))
    assert_equal 6, state["books"]
  end

  def test_a_resync_downloads_nothing
    stub_all
    sync!
    second = sync!
    assert_equal 0, second.fetched
    assert_equal 8, second.cached
  end

  def test_an_interrupted_crawl_resumes_at_the_book_grain
    FileUtils.mkdir_p(@dir)
    File.binwrite(File.join(@dir, "birkatcohen__text_files.zip"),
                  File.binread(File.join(FIXTURES, "books", "birkatcohen__text_files.zip")))
    stub_all
    result = sync!
    assert_equal 7, result.fetched
    assert_not_requested :get, entries.first["textFileURL"]
  end

  def test_a_lone_404_is_censused_and_the_crawl_continues
    stub_all
    gone = entries.find { |e| e["fileName"] == "rishonletziontaanit" }["textFileURL"]
    stub_request(:get, gone).to_return(status: 404)
    result = sync!
    assert_equal ["rishonletziontaanit"], result.missing
    assert File.file?(File.join(@dir, "birkatcohen__text_files.zip"))
  end

  def test_a_systemic_miss_aborts
    stub_request(:get, /files\.dicta\.org\.il/).to_return(status: 404)
    six = Array.new(6) { |i| entries.first.merge("fileName" => "book#{i}") }.map do |entry|
      name = entry["fileName"]
      entry.merge("textFileURL" => "https://files.dicta.org.il/library-1-0/#{name}/#{name}__text_files.zip",
                  "nikudMetegFileURL" => "https://files.dicta.org.il/library-1-0/#{name}/#{name}__nikud_meteg_files.zip")
    end
    manifest = File.join(@root, "books.json")
    File.write(manifest, JSON.generate(six))
    error = assert_raises(Nabu::DictaLibraryFetch::Error) { sync!(manifest) }
    assert_match(/systemic miss/, error.message)
  end

  def test_a_5xx_retries_then_succeeds
    stub_all
    url = entries.first["textFileURL"]
    stub_request(:get, url).to_return({ status: 503 }, { status: 200, body: File.binread(
      File.join(FIXTURES, "books", "birkatcohen__text_files.zip")
    ) })
    assert_equal 8, sync!.fetched
  end

  def test_a_malformed_manifest_aborts_before_any_write
    manifest = File.join(@root, "books.json")
    bad = entries.first.merge("fileName" => "../escape")
    File.write(manifest, JSON.generate([bad]))
    assert_raises(Nabu::DictaLibraryFetch::Error) { sync!(manifest) }
    refute Dir.exist?(@dir)

    File.write(manifest, JSON.generate([entries.first.merge("textFileURL" => "https://elsewhere.example/x.zip")]))
    assert_raises(Nabu::DictaLibraryFetch::Error) { sync!(manifest) }
    File.write(manifest, "{")
    assert_raises(Nabu::DictaLibraryFetch::Error) { sync!(manifest) }
  end

  def test_a_changed_manifest_entry_rewrites_its_sidecar_never_deletes
    stub_all
    sync!
    manifest = File.join(@root, "books.json")
    changed = entries.drop(1).map { |e| e["fileName"] == "rishonletziontaanit" ? e.merge("printYear" => 1916) : e }
    File.write(manifest, JSON.generate(changed))
    sync!(manifest)
    assert_equal 1916, JSON.parse(File.read(File.join(@dir, "rishonletziontaanit.json")))["printYear"]
    assert File.file?(File.join(@dir, "birkatcohen.json")), "a book upstream drops keeps its sidecar (additive)"
  end

  def test_empty_zip_reads_only_tiny_files
    assert Nabu::DictaLibraryFetch.empty_zip?(File.join(FIXTURES, "books", "maharamlublin__text_files.zip"))
    refute Nabu::DictaLibraryFetch.empty_zip?(File.join(FIXTURES, "books", "birkatcohen__text_files.zip"))
  end
end
