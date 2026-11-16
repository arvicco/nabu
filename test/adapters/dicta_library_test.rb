# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Dicta's library (Dicta-Library-Download): the books.json manifest of AI-OCR'd
# rabbinic printed books, one per-page text zip per book at files.dicta.org.il.
# Document = book, passage = scanned page. The fixture is the fetched shape:
# the manifest trimmed to six real entries, each entry's sidecar, and the real
# book zips (three whole, three trimmed to their leading pages) — including the
# empty-text-zip books (one recovered from its vocalized zip, one with both
# zips empty) and the rejected grains (a held book's vocalized zip, its OCR
# HTML zip). No network: the crawl answers WebMock stubs, the manifest repo a
# local git repo.
class DictaLibraryTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("dicta-library")
  URN = "urn:nabu:dicta-library:"

  def conformance_adapter
    Nabu::Adapters::DictaLibrary.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "dicta-library"
  end

  def adapter = Nabu::Adapters::DictaLibrary.new

  def document(slug)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "#{URN}#{slug}" }
    refute_nil ref, "no ref for #{slug}"
    adapter.parse(ref)
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_is_attribution_with_the_readme_license_link
    manifest = Nabu::Adapters::DictaLibrary.manifest
    assert_equal "dicta-library", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "https://creativecommons.org/licenses/by-sa/4.0/"
    assert_includes manifest.credit, "Dicta"
    assert_equal "https://github.com/Dicta-Israel-Center-for-Text-Analysis/Dicta-Library-Download",
                 manifest.upstream_url
  end

  def test_the_books_dir_is_a_declared_materialization
    assert_equal ["books"], Nabu::Adapters::DictaLibrary.materialized_paths
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_with_a_text_witness
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %W[#{URN}birkatcohen #{URN}hilchotberakhotritba #{URN}maharamlublin
                    #{URN}rishonletziontaanit #{URN}sefatemetmoed1], refs.map(&:id)
    maharam = refs.find { |r| r.id.end_with?("maharamlublin") }
    assert maharam.path.end_with?("maharamlublin__nikud_meteg_files.zip"),
           "an empty text zip falls back to the vocalized zip"
  end

  def test_discovery_skips_count_every_rejected_grain_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule,
                 "chidusheiharadad (both zips empty) + birkatcohen's vocalized zip + its OCR HTML zip"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |n| n.include?("chidusheiharadad") && n.include?("empty") })
    assert(skips.notes.any? { |n| n.include?("birkatcohen__ocr_data_html_files.zip") })
    assert(skips.notes.any? { |n| n.include?("birkatcohen__nikud_meteg_files.zip") })
  end

  def test_a_listed_book_never_downloaded_is_unrecognized
    Dir.mktmpdir do |dir|
      books = File.join(dir, "books")
      FileUtils.mkdir_p(books)
      FileUtils.cp(File.join(FIXTURES, "books", "birkatcohen.json"), books)
      assert_empty adapter.discover(dir).to_a
      assert_equal 1, adapter.discovery_skips(dir).unrecognized
    end
  end

  def test_slug_collisions_are_refused_loudly_never_merged
    assert_equal "h-b-z-lt-hsrvn-h-lk-b-1573", Nabu::Adapters::DictaLibrary.slug("(h)b(z)lt_hsrvn-(h)lk_b=1573")
    Dir.mktmpdir do |dir|
      books = File.join(dir, "books")
      FileUtils.mkdir_p(books)
      %w[birkat_cohen birkat-cohen].each do |name|
        entry = JSON.parse(File.read(File.join(FIXTURES, "books", "birkatcohen.json"))).merge("fileName" => name)
        File.write(File.join(books, "#{name}.json"), JSON.generate(entry))
        FileUtils.cp(File.join(FIXTURES, "books", "birkatcohen__text_files.zip"),
                     File.join(books, "#{name}__text_files.zip"))
      end
      assert_equal 1, adapter.discover(dir).count
      assert(adapter.discovery_skips(dir).notes.any? { |n| n.include?("collides") })
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- parse ------------------------------------------------------------------

  def test_a_book_parses_at_page_grain
    doc = document("birkatcohen")
    assert_equal "Birkat Cohen", doc.title
    assert_equal "heb", doc.language
    assert_equal %W[#{URN}birkatcohen:4 #{URN}birkatcohen:5], doc.map(&:urn)
    assert doc.first.text.start_with?("הקדמה מבן המחבר אמר בן המחבר המביא לביה\"ד.")
    assert_equal 4, doc.first.annotations["page"]
  end

  def test_book_metadata_mines_every_manifest_axis
    meta = document("birkatcohen").metadata
    assert_equal "ברכת כהן", meta["he_title"]
    assert_equal "Rabbi Tuviah Gutman Rappoport", meta["author"]
    assert_equal "רבי טוביה גוטמן רפפורט", meta["author_he"]
    assert_equal({ "not_before" => 1908, "not_after" => 1908, "raw" => "1908", "class" => "edition" }, meta["date"])
    assert_equal "Piotrków", meta["place"]
    assert_equal "פיוטריקוב", meta["place_he"]
    assert_equal "Responsa -- Acharonim (West)", meta["genre"]
    assert_equal "שאלות ותשובות (שו\"ת) -- אחרונים - מערב", meta["genre_he"]
    assert_equal({ "value" => "acharonim", "raw" => "Acharonim (West)" }, meta.dig("facets", "era"))
    assert_equal({ "values" => ["Rabbi Tuviah Gutman Rappoport"] }, meta.dig("facets", "author"))
    assert_equal "machine-ocr", meta["text_nature"]
    assert_equal "plain", meta["text_layer"]
    assert_equal 2, meta["page_count"]
  end

  def test_a_print_year_range_widens_the_edition_envelope
    date = document("sefatemetmoed1").metadata["date"]
    assert_equal({ "not_before" => 1925, "not_after" => 1931, "raw" => "1925-1931", "class" => "edition" }, date)
  end

  def test_the_rishonim_subcategory_rides_the_era_facet
    meta = document("hilchotberakhotritba").metadata
    assert_equal "rishonim", meta.dig("facets", "era", "value")
    assert_equal "Halakha and Minhaggim -- Halakha Books - Rishonim", meta["genre"]
  end

  def test_the_vocalized_fallback_is_declared_and_normalized
    doc = document("maharamlublin")
    assert_equal "vocalized (the plain-text zip is empty upstream)", doc.metadata["text_layer"]
    assert_equal %W[#{URN}maharamlublin:9 #{URN}maharamlublin:10], doc.map(&:urn)
    assert(doc.all? { |p| p.text.unicode_normalized?(:nfc) }, "heb is not NFC-exempt: the boundary composes")
    assert doc.first.text.start_with?("שְׁאֵלָה א".unicode_normalize(:nfc))
  end

  def test_the_both_empty_book_is_skipped_by_rule_at_parse_too
    entry = File.join(FIXTURES, "books", "chidusheiharadad__text_files.zip")
    ref = Nabu::DocumentRef.new(source_id: "dicta-library", id: "#{URN}chidusheiharadad", path: entry,
                                metadata: { "sidecar" => File.join(FIXTURES, "books", "chidusheiharadad.json"),
                                            "layer" => "plain" })
    assert_raises(Nabu::DocumentSkipped) { adapter.parse(ref) }
  end

  def test_an_unreadable_zip_quarantines
    Dir.mktmpdir do |dir|
      books = File.join(dir, "books")
      FileUtils.mkdir_p(books)
      FileUtils.cp(File.join(FIXTURES, "books", "birkatcohen.json"), books)
      File.write(File.join(books, "birkatcohen__text_files.zip"), "#{'x' * 200}not a zip")
      ref = adapter.discover(dir).first
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (local git + WebMock, no network) -----------------------------------

  def test_fetch_clones_the_manifest_repo_then_crawls_the_book_zips
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      stub_book_zips
      workdir = File.join(root, "work")
      library = adapter_pointing_at(upstream)
      report = library.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/6 books/, report.notes)
      assert_equal 5, library.discover(workdir).count
      assert_equal 1, library.discovery_skips(workdir).skipped_by_rule, "only the both-empty book"
      second = library.fetch(workdir)
      assert_match(/0 downloaded/, second.notes)
    end
  end

  # --- registry round-trip -------------------------------------------------------

  def test_registry_resolves_dicta_library_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["dicta-library"]
    refute_nil entry
    assert_equal Nabu::Adapters::DictaLibrary, entry.adapter_class
    refute entry.wired, "wired: false until the first real sync is verified"
  end

  private

  def adapter_pointing_at(upstream)
    library = adapter
    library.define_singleton_method(:repo_url) { upstream }
    library.define_singleton_method(:crawl_delay) { 0 }
    library
  end

  def stub_book_zips
    books = File.join(FIXTURES, "books")
    JSON.parse(File.read(File.join(FIXTURES, "books.json"))).each do |entry|
      %w[textFileURL nikudMetegFileURL].each do |key|
        local = File.join(books, File.basename(entry[key]))
        next unless File.file?(local)

        stub_request(:get, entry[key]).to_return(status: 200, body: File.binread(local))
      end
    end
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    FileUtils.cp(File.join(FIXTURES, "books.json"), dir)
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
