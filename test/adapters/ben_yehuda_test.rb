# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"

# Project Ben-Yehuda's public-domain dump, the pre-modern layer only: one
# document per manifestation from the txt/ (pointed) variant, one passage
# per blank-line block, the band cut read from the periods.json sidecar
# (upstream's own period taxonomy). The fixture holds five real txt files
# — two Yannai qerovot (ancient band), two Yehuda Halevi poems (medieval,
# one a translation from Arabic), one Rachel Bluwstein poem (out of band,
# skipped by rule) — the real catalogue rows for them, the dump's LICENSE
# and VERSION, one txt_stripped/ and one html/ specimen (rejected grains),
# the sidecar the period fetch wrote from the trimmed real browse pages
# under site/. No network: fetch runs against a local tagged git repo and
# WebMock answers the browse pages.
class BenYehudaTest < Minitest::Test
  include StoreTestDB
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ben-yehuda")
  ADAPTER = Nabu::Adapters::BenYehuda
  URN = "urn:nabu:ben-yehuda:"

  def conformance_adapter = ADAPTER.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "ben-yehuda"

  def adapter = ADAPTER.new

  def document(mid)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "#{URN}m#{mid}" }
    refute_nil ref, "no ref for m#{mid}"
    adapter.parse(ref)
  end

  # --- manifest ----------------------------------------------------------------

  def test_manifest_is_public_domain_with_the_requested_volunteers_credit
    manifest = ADAPTER.manifest
    assert_equal "ben-yehuda", manifest.id
    assert_equal "open", manifest.license_class
    license = File.read(File.join(FIXTURES, "LICENSE"))
    assert_includes license, "The data files in this repository are in the public domain"
    assert_includes manifest.license, "The data files in this repository are in the public domain"
    assert_includes manifest.credit, "Project Ben-Yehuda volunteers"
    assert_includes manifest.credit, "https://benyehuda.org"
    assert_equal "https://github.com/projectbenyehuda/public_domain_dump", manifest.upstream_url
  end

  def test_the_release_pin_and_the_declared_sidecar
    assert_equal "2026-03", ADAPTER::RELEASE_TAG
    assert_equal ["periods.json"], ADAPTER.materialized_paths
  end

  # --- discover / the band cut ----------------------------------------------------

  def test_discover_yields_only_the_pre_modern_bands
    refs = adapter.discover(FIXTURES).to_a
    assert_equal %W[#{URN}m2245 #{URN}m34421 #{URN}m34427 #{URN}m8750], refs.map(&:id)
    halevi = refs.first
    assert halevi.path.end_with?("txt/p161/m2245.txt")
    assert_equal "medieval", halevi.metadata["band"]
    assert_equal "ancient", refs[1].metadata["band"]
  end

  def test_an_out_of_band_work_and_the_rejected_variants_skip_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 3, skips.skipped_by_rule, "Rachel's poem (out of band) + the txt_stripped + the html specimen"
    assert_equal 0, skips.unrecognized
    assert(skips.notes.any? { |n| n.include?("1 catalogued work") && n.include?("outside") })
    assert(skips.notes.any? { |n| n.include?("txt_stripped/") })
    assert(skips.notes.any? { |n| n.include?("html/") })
    refute(adapter.discover(FIXTURES).any? { |r| r.id == "#{URN}m19" })
  end

  def test_a_workdir_without_the_sidecar_yields_nothing_and_says_why
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "txt"), dir)
      FileUtils.cp(File.join(FIXTURES, "pseudocatalogue.csv"), dir)
      assert_empty adapter.discover(dir).to_a
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(/periods\.json/, skips.notes.first)
    end
  end

  def test_an_in_band_catalogue_row_without_its_file_is_unrecognized_loudly
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      FileUtils.rm(File.join(dir, "txt", "p1470", "m34427.txt"))
      refute(adapter.discover(dir).any? { |r| r.id == "#{URN}m34427" })
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("m34427") })
    end
  end

  def test_a_txt_file_the_catalogue_never_names_is_unrecognized
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      FileUtils.cp(File.join(dir, "txt", "p161", "m2245.txt"), File.join(dir, "txt", "p161", "m99999.txt"))
      assert_equal 4, adapter.discover(dir).count
      assert_equal 1, adapter.discovery_skips(dir).unrecognized
    end
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # --- parse -------------------------------------------------------------------------

  def test_a_halevi_quatrain_parses_one_passage_per_block_without_the_footer
    doc = document("2245")
    assert_equal "hbo", doc.language
    assert_equal "[דוד מתקו מליו]", doc.title
    assert_equal 4, doc.size
    assert_equal %W[#{URN}m2245:1 #{URN}m2245:2 #{URN}m2245:3 #{URN}m2245:4], doc.map(&:urn)
    assert_equal nfc("דּוֹד מָתְקוּ מִלָּיו מְאֹד מִנֹּפֶת"), nfc(doc.first.text)
    assert_equal nfc("וּלְנֹדְך לִבִּי כְּמוֹקֵד תֹּפֶת."), nfc(doc.to_a.last.text)
    refute(doc.any? { |p| p.text.include?("הפיקו מתנדבי") }, "the volunteers' footer is boilerplate, not text")
    assert_equal "https://benyehuda.org/read/2245", doc.metadata["read_url"]
  end

  def test_nikud_bytes_round_trip_unmodified_on_the_nfc_exempt_code
    path = File.join(FIXTURES, "txt", "p161", "m2245.txt")
    raw = File.read(path, encoding: "UTF-8").lines.map(&:strip).reject(&:empty?)
    non_nfc = raw.reject { |line| line.unicode_normalized?(:nfc) }
    refute_empty non_nfc, "upstream's mark order is not NFC — the exemption is real here"
    texts = document("2245").map(&:text)
    non_nfc.each do |line|
      next if line == raw.first # the title line rides metadata, NFC'd

      assert_includes texts, line, "pointed text must be stored byte-verbatim"
    end
    assert(texts.any? { |t| !t.unicode_normalized?(:nfc) })
  end

  def test_a_yannai_qerova_keeps_its_superscription_and_its_verse_blocks
    doc = document("34427")
    assert_equal 7, doc.size, "the superscription + six verse blocks"
    assert_equal "לאחד הסדרים שבפרשת נח", doc.first.text
    assert nfc(doc.to_a[1].text).start_with?(nfc("יוֹדֵעַ מִנֶּפֶשׁ בַּהֲ[מוֹתָיו] / ט"))
    assert_equal "ancient", doc.metadata["band"]
  end

  def test_section_numerals_ride_the_following_passages_never_their_own
    doc = document("34421")
    refute(doc.any? { |p| p.text == "א" }, "a bare numeral line is a section label, not a passage")
    verse = doc.find { |p| nfc(p.text).start_with?(nfc("אָב לִבּוֹ כְּלִבָּךְ מָצָאתָה")) }
    refute_nil verse
    assert_equal "א", verse.annotations["section"]
    assert_nil doc.first.annotations["section"], "the superscription precedes the first section"
    sections = doc.filter_map { |p| p.annotations["section"] }.uniq
    assert_operator sections.size, :>, 1
  end

  def test_a_letterless_block_mints_no_passage_and_is_counted
    raw = File.read(File.join(FIXTURES, "txt", "p1470", "m34421.txt"), encoding: "UTF-8")
    assert_includes raw.lines.map(&:strip), "ֿ", "upstream's lone rafe on a line of its own"
    doc = document("34421")
    assert_equal 1, doc.metadata["stray_blocks"]
    refute(doc.any? { |p| p.text == "ֿ" })
    assert_nil document("2245").metadata["stray_blocks"]
  end

  def test_metadata_mines_the_catalogue_and_the_band
    meta = document("2245").metadata
    assert_equal "יהודה הלוי", meta["author"]
    assert_equal "https://wikidata.org/wiki/Q299200", meta["author_uris"]
    assert_equal "poetry", meta["genre"]
    assert_equal "Translation missing: he.poetry", meta["genre_raw"]
    assert_equal 2245, meta["benyehuda_id"]
    assert_equal "p161", meta["author_dir"]
    assert_equal "הלוי, יהודה", meta["site_author"]
    assert_equal "2026-03", meta["dump_release"]
    assert_equal({ "not_before" => 900, "not_after" => 1700, "raw" => "ימי הביניים והרנסאנס (900 עד 1700)",
                   "class" => "composition" }, meta["date"])
    assert_equal({ "value" => "medieval", "raw" => "ימי הביניים והרנסאנס (900 עד 1700)" },
                 meta.dig("facets", "period"))
    assert_equal({ "values" => ["יהודה הלוי"] }, meta.dig("facets", "author"))
  end

  def test_the_ancient_band_dates_with_an_open_lower_bound
    meta = document("34427").metadata
    assert_equal({ "not_before" => nil, "not_after" => 900, "raw" => "עת עתיקה ופיוט (עד 900 לספירה)",
                   "class" => "composition" }, meta["date"])
    assert_equal nfc("הוצאת שוקן, ברלין"), meta["source_edition"]
  end

  def test_a_translation_carries_its_translator_and_original_language
    meta = document("8750").metadata
    assert_equal "אלמוני/ת", meta["author"]
    assert_equal "יהודה הלוי", meta["translator"]
    assert_equal "ar", meta["original_language"]
    assert_equal({ "values" => ["אלמוני/ת"] }, meta.dig("facets", "author"))
  end

  def test_a_file_without_text_below_its_title_is_damage
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")), dir)
      File.write(File.join(dir, "txt", "p161", "m2245.txt"), "[דוד מתקו מליו]\n\t\n\n")
      ref = adapter.discover(dir).find { |r| r.id == "#{URN}m2245" }
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  # --- fetch (local git + WebMock, no network) ----------------------------------------

  def test_fetch_lands_the_band_cone_at_the_release_tag_and_the_sidecar
    Dir.mktmpdir do |root|
      upstream = make_tagged_repo(File.join(root, "upstream"))
      workdir = File.join(root, "canonical")
      stub_site
      by = adapter
      by.define_singleton_method(:repo_url) { upstream }
      report = by.fetch(workdir)
      tagged = Nabu::Shell.run("git", "-C", upstream, "rev-parse", "2026-03^{commit}").strip
      assert_equal tagged, report.sha, "fetch lands on the release tag, never the moving master"
      assert File.file?(File.join(workdir, "txt", "p161", "m2245.txt"))
      assert File.file?(File.join(workdir, "pseudocatalogue.csv"))
      refute File.exist?(File.join(workdir, "txt", "p141")), "out-of-band author dirs never materialize"
      refute File.exist?(File.join(workdir, "html")), "the rejected variants never materialize"
      refute File.exist?(File.join(workdir, "txt_stripped"))
      assert_equal 8, JSON.parse(File.read(File.join(workdir, "periods.json")))["authors"].size
      assert_equal 4, by.discover(workdir).count
      assert_match(/2 ancient \+ 6 medieval/, report.notes)
    end
  end

  def test_fetch_keeps_a_held_sidecar_when_the_site_is_down
    Dir.mktmpdir do |root|
      upstream = make_tagged_repo(File.join(root, "upstream"))
      workdir = File.join(root, "canonical")
      stub_site
      by = adapter
      by.define_singleton_method(:repo_url) { upstream }
      by.fetch(workdir)
      WebMock.reset!
      stub_request(:get, /benyehuda\.org/).to_return(status: 503)
      report = by.fetch(workdir)
      assert_match(/held periods\.json kept/, report.notes)
      assert_equal 4, by.discover(workdir).count
    end
  end

  def test_fetch_without_any_band_list_fails_before_cloning
    Dir.mktmpdir do |root|
      upstream = make_tagged_repo(File.join(root, "upstream"))
      workdir = File.join(root, "canonical")
      stub_request(:get, /benyehuda\.org/).to_return(status: 503)
      by = adapter
      by.define_singleton_method(:repo_url) { upstream }
      assert_raises(Nabu::FetchError) { by.fetch(workdir) }
      refute File.exist?(workdir)
    end
  end

  # --- idempotency + registry ------------------------------------------------------

  def test_double_load_is_idempotent
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "ben-yehuda", name: "Project Ben-Yehuda",
                                        adapter_class: "Nabu::Adapters::BenYehuda", license_class: "open")
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    counts = [catalog[:documents].count, catalog[:passages].count]
    revisions = catalog[:documents].select_hash(:urn, :revision)
    Nabu::Store::Loader.new(db: catalog, source: source)
                       .load_from(conformance_adapter, workdir: FIXTURES, full: true)
    assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
    assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
  end

  def test_registry_resolves_ben_yehuda_wired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["ben-yehuda"]
    refute_nil entry
    assert_equal ADAPTER, entry.adapter_class
    assert entry.wired, "wired after the verified first sync"
  end

  private

  def nfc(text) = text.unicode_normalize(:nfc)

  def stub_site
    fetch = Nabu::BenYehudaPeriodFetch
    page = ->(name) { File.read(File.join(FIXTURES, "site", "#{name}.html")) }
    stub_request(:get, fetch.page_url("ancient")).to_return(status: 200, body: page["authors-ancient"])
    stub_request(:get, fetch.page_url("medieval")).to_return(status: 200, body: page["authors-medieval-1"])
    { "authors-medieval-1" => "authors-medieval-2", "authors-medieval-2" => "authors-medieval-3" }.each do |from, to|
      cursor = fetch.parse_page(page[from]).next_cursor
      stub_request(:get, fetch.page_url("medieval", cursor)).to_return(status: 200, body: page[to])
    end
  end

  # A local upstream in the dump's layout: commit 1 tagged 2026-03, commit 2
  # ahead of it on the default branch (the pin must not follow master).
  def make_tagged_repo(dir)
    FileUtils.mkdir_p(dir)
    %w[txt txt_stripped html pseudocatalogue.csv LICENSE VERSION].each do |name|
      FileUtils.cp_r(File.join(FIXTURES, name), dir)
    end
    git(dir, "init", "-q")
    git(dir, "add", ".")
    commit(dir, "release")
    git(dir, "tag", "2026-03")
    File.write(File.join(dir, "VERSION"), "2026-09\n")
    git(dir, "add", ".")
    commit(dir, "after the release")
    dir
  end

  def commit(dir, message)
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", message)
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
