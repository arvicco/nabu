# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "nabu/adapters/ottoman_ocr"

# OttomanOcr adapter tests: the OttomanOCR-search repository (github.com/
# koras0ff/OttomanOCR-search, CC BY-NC 4.0) — machine OCR of printed
# Ottoman Turkish books. Fixture (test/fixtures/ottoman-ocr/README.md): the
# workdir as the sparse GitFetch lands it, three real works cut to 2–3
# pages each — Peçevî vol. 1 (a back-to-front scan: printed pp. 504, 502
# and an untranscribed page), Eşʿâr-ı Ziyâ (the colour-calibration chart,
# the title page, the first poems) and the Kanunname-i Âl-i Osman (two
# two-page spreads) — the manifest trimmed to those works, and the
# rejected root grain transcriptions_ziyapasa.json cut to one page.
class OttomanOcrTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ottoman-ocr")
  PREFIX = "urn:nabu:ottoman-ocr"
  PECEVI = "tarihipeevi01peuoft"
  ZIYA = "esariziyapasa"
  KANUN = "Kanunnamei_Ali_Osman"

  def conformance_adapter = Nabu::Adapters::OttomanOcr.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "ottoman-ocr"

  def adapter = Nabu::Adapters::OttomanOcr.new

  def document(id, workdir = FIXTURES)
    ref = adapter.discover(workdir).find { |r| r.id == "#{PREFIX}:#{id}" } || flunk("discover must yield #{id}")
    adapter.parse(ref)
  end

  # -- manifest + registry --------------------------------------------------------

  def test_manifest_records_the_noncommercial_grant_verbatim
    manifest = adapter.manifest
    assert_equal "ottoman-ocr", manifest.id
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "Creative Commons Attribution-NonCommercial 4.0 International (CC BY-NC 4.0)"
    assert_includes manifest.license, "The original images are in the public domain. The license applies to " \
                                      "the layout and OCR data."
    assert_equal "ottoman-ocr-js", manifest.parser_family
    assert_equal "https://github.com/koras0ff/OttomanOCR-search", manifest.upstream_url
  end

  def test_registry_row_is_wired_manual_on_the_turkic_and_arabic_desks
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["ottoman-ocr"]
    refute_nil entry, "config/sources/ must register ottoman-ocr"
    assert entry.wired, "wired after the verified first sync of 2026-11-28"
    assert_equal "manual", entry.sync_policy
    assert_equal %w[turkic arabic], entry.axes
    assert_equal "ottoman-ocr", entry.adapter_class.manifest.id
  end

  # -- discover: the delivery grains ------------------------------------------------

  def test_discover_takes_one_document_per_manifest_work_in_manifest_order
    assert_equal %W[#{PREFIX}:#{KANUN} #{PREFIX}:#{ZIYA} #{PREFIX}:#{PECEVI}], adapter.discover(FIXTURES).map(&:id)
  end

  def test_the_root_ziyapasa_transcription_is_skipped_by_rule
    skips = adapter.discovery_skips(FIXTURES)
    assert skips.clean?, skips.notes.inspect
    assert_equal 1, skips.skipped_by_rule
    assert(skips.notes.any? { |note| note.include?("transcriptions_ziyapasa.json") })
  end

  def test_a_work_file_the_manifest_does_not_list_is_unrecognized
    with_fixture_copy do |dir|
      FileUtils.cp(File.join(dir, "data", "#{ZIYA}.js"), File.join(dir, "data", "stray.js"))
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?("stray.js") })
    end
  end

  def test_a_manifest_work_without_its_file_is_unrecognized_and_never_yielded
    with_fixture_copy do |dir|
      FileUtils.rm(File.join(dir, "data", "#{KANUN}.js"))
      assert_equal %W[#{PREFIX}:#{ZIYA} #{PREFIX}:#{PECEVI}], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |note| note.include?(KANUN) })
    end
  end

  def test_an_empty_workdir_discovers_nothing
    Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
  end

  # -- parse: page passages ---------------------------------------------------------

  def test_one_passage_per_transcribed_page_cited_by_the_page_number
    pecevi = document(PECEVI)
    assert_equal "ota", pecevi.language
    assert_equal "Tarih-i Peçevî, vol1", pecevi.title
    assert_equal 2, pecevi.size, "pages 5 and 7; page 201 is segmented but untranscribed"
    assert_equal %W[#{PREFIX}:#{PECEVI}:5 #{PREFIX}:#{PECEVI}:7], pecevi.map(&:urn)
    first = pecevi.first
    assert first.text.start_with?("و نكاه بر یانلری اوزرینه دوشوب صلابت مرردن اول\nطرفلری كویا كه")
    assert first.text.end_with?("رحمهم الله تعالی\nتمام الجلد الاول و يليه الجلد الثانی")
    assert_equal({ "page" => "5", "image" => "page_5.jpg", "printed_page" => "— ٥٠٤ —" }, first.annotations)
  end

  def test_the_page_number_rides_the_annotation_never_the_text
    pecevi = document(PECEVI)
    pecevi.each { |passage| refute_includes passage.text, "—" }
    assert_equal "— ٥٠٢ —", pecevi.to_a.last.annotations["printed_page"]
  end

  def test_entries_join_by_newline_in_upstream_order_across_region_classes
    spread = document(KANUN).to_a.last
    assert_equal "#{PREFIX}:#{KANUN}:3-4", spread.urn, "the en-dash spread number cites with an ASCII hyphen"
    assert_equal "3–4", spread.annotations["page"], "the annotation keeps upstream's own page label"
    lines = spread.text.split("\n")
    assert_equal "قانوننامه‌ٔ آل عثمان", lines.first, "the running head comes first, as upstream orders it"
    assert lines.last.start_with?("فرمانزما استقامدە"), "the footnote closes the page"
    assert_equal "٤", spread.annotations["printed_page"]
  end

  def test_the_calibration_chart_mints_nothing_and_is_counted
    ziya = document(ZIYA)
    assert_equal %W[#{PREFIX}:#{ZIYA}:7 #{PREFIX}:#{ZIYA}:8], ziya.map(&:urn)
    assert_equal 1, ziya.metadata["calibration_pages"]
    assert_equal 3, ziya.metadata["pages"]
    assert_equal 2, ziya.metadata["text_pages"]
    assert_equal "اشعار ضیا\nنعوت شریفه\nبلای ماسوایه مبتلایم یا رسول الله",
                 ziya.to_a.last.text.lines.first(3).join.chomp
  end

  # -- document metadata: the OCR flag, the axes -------------------------------------

  def test_every_document_declares_uncorrected_machine_ocr
    adapter.discover(FIXTURES).each do |ref|
      meta = adapter.parse(ref).metadata
      assert_equal "uncorrected-ocr", meta["text_nature"], ref.id
      assert_includes meta["ocr_note"], "Ottoman-Print-OCR-Qwen4B"
      assert_kind_of Float, meta["ocr_latin_line_share"]
    end
  end

  def test_the_latin_line_share_is_measured_over_the_text_lines
    kanun = document(KANUN)
    lines = kanun.flat_map { |passage| passage.text.split("\n") }
    expected = (lines.count { |line| line.match?(/\p{Latin}/) }.to_f / lines.size).round(4)
    assert_equal expected, kanun.metadata["ocr_latin_line_share"]
  end

  def test_a_back_to_front_scan_is_declared_and_never_reordered
    pecevi = document(PECEVI)
    assert_equal "descending", pecevi.metadata["page_order"], "printed 504 then 502 in upstream's image order"
    assert_equal(%w[5 7], pecevi.map { |p| p.annotations["page"] })
    assert_nil document(KANUN).metadata["page_order"], "an ascending scan carries no flag"
  end

  def test_upstream_catalog_metadata_is_mined
    pecevi = document(PECEVI).metadata
    assert_equal PECEVI, pecevi["work"]
    assert_equal ["Peçevî, İbrahim, 1574-1649?"], pecevi["authors"]
    assert_equal "Matbaa-i Amire", pecevi["publisher"]
    assert_equal ["History"], pecevi["subjects"]
    assert_equal "book/printed material", pecevi["upstream_genre"]
    assert_equal "1866", pecevi["print_year"]
    assert_equal "https://archive.org/details/tarihipeevi01peuoft", pecevi["source_url"]
    assert_equal "https://huggingface.co/datasets/enesyila/ottoman-turkish-printed-pages/resolve/" \
                 "808f336a6ff103446ab4069d8fbc1b7321afb1b6/img/#{PECEVI}/", pecevi["image_base"]
    refute pecevi.key?("place"), "the press is an imprint, never the place claim"
    kanun = document(KANUN).metadata
    assert_equal ["http://viaf.org/viaf/263937854"], kanun["viaf"]
    assert_equal "1329", kanun["print_year_ah"]
  end

  def test_a_textbook_dated_work_carries_its_attributed_composition_era
    date = document(PECEVI).metadata["date"]
    assert_equal 1641, date["not_before"]
    assert_equal 1650, date["not_after"]
    assert_equal "composition", date["class"]
    assert date["raw"].start_with?("ATTRIBUTED"), date["raw"]
  end

  def test_the_kanunname_is_dated_by_its_own_preface_not_upstreams_author_field
    date = document(KANUN).metadata["date"]
    assert_equal [1477, 1481, "composition"], date.values_at("not_before", "not_after", "class")
    assert_includes date["raw"], "Mehmed II"
  end

  def test_an_undated_composition_keeps_the_print_year_as_an_edition_date
    assert_equal({ "not_before" => 1881, "not_after" => 1881, "class" => "edition", "raw" => "printed 1881" },
                 document(ZIYA).metadata["date"])
  end

  def test_print_dates_read_the_typed_years_then_the_hijri_label
    date = Nabu::Adapters::OttomanOcr.method(:print_date)
    span = { "year_g_label" => "1880/1881", "year_min" => 1880, "year_max" => 1881, "year_h_label" => "1298" }
    assert_equal({ "not_before" => 1880, "not_after" => 1881, "class" => "edition", "raw" => "printed 1880/1881" },
                 date.call(span))
    hijri = { "year_g_label" => "", "year_min" => nil, "year_max" => nil, "year_h_label" => "1317" }
    assert_equal({ "not_before" => 1899, "not_after" => 1900, "class" => "edition",
                   "raw" => "printed 1317 AH (upstream's Hijri year; 1899–1900 CE)" }, date.call(hijri))
    assert_nil date.call({ "year_g_label" => "", "year_min" => nil, "year_max" => nil, "year_h_label" => "" })
    assert_nil date.call({ "year_min" => nil, "year_max" => nil, "year_h_label" => "1294-1298" }),
               "a Hijri span is never guessed into CE"
  end

  def test_the_hijri_envelope_converts_whole_years
    envelope = Nabu::Adapters::OttomanOcr.method(:hijri_envelope)
    assert_equal [1899, 1900], envelope.call(1317)
    assert_equal [1902, 1903], envelope.call(1320)
    assert_equal [1911, 1911], envelope.call(1329), "1 Muḥarram 1329 = 2 January 1911"
    assert_equal [1922, 1923], envelope.call(1341)
    assert_equal [1728, 1729], envelope.call(1141)
  end

  def test_the_composition_table_names_census_works_with_a_reason_each
    table = Nabu::Adapters::OttomanOcr::COMPOSITION
    assert_equal 21, table.size
    table.each do |id, date|
      assert_operator date["not_before"], :<=, date["not_after"], id
      assert_equal "composition", date["class"], id
      assert date["raw"].start_with?("ATTRIBUTED: "), id
    end
    assert_equal (1..8).map { |n| format("evliyaelebisey%02devliuoft", n) },
                 table.keys.grep(/\Aevliya/).sort
  end

  # -- parse errors -----------------------------------------------------------------

  def test_a_work_file_without_its_js_wrapper_is_a_parse_error
    with_fixture_copy do |dir|
      path = File.join(dir, "data", "#{ZIYA}.js")
      File.write(path, File.read(path).sub("window.__W=", "var W="))
      ref = adapter.discover(dir).find { |r| r.id == "#{PREFIX}:#{ZIYA}" }
      assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    end
  end

  def test_a_malformed_manifest_discovers_nothing_and_is_loud
    with_fixture_copy do |dir|
      File.write(File.join(dir, "data", "manifest.js"), "window.__MANIFEST={broken")
      assert_raises(Nabu::ParseError) { adapter.discover(dir).to_a }
    end
  end

  # -- fetch (pinned commit; local repos, no network) ---------------------------------

  def test_fetch_accepts_the_pinned_commit_and_checks_out_the_sparse_cone
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        workdir = File.join(root, "work")
        report = Nabu::Adapters::OttomanOcr.new(repo_url: repo_url, pinned_sha: sha).fetch(workdir)
        assert_equal sha, report.sha
        assert File.file?(File.join(workdir, "data", "manifest.js"))
        assert File.file?(File.join(workdir, "transcriptions_ziyapasa.json"))
        refute File.exist?(File.join(workdir, "model.pt")), "the detection model never materializes"
      end
    end
  end

  def test_fetch_stops_loudly_when_upstream_drifts_from_the_pin
    with_local_upstream do |repo_url, sha|
      Dir.mktmpdir do |root|
        drifted = Nabu::Adapters::OttomanOcr.new(repo_url: repo_url, pinned_sha: "0" * 40)
        error = assert_raises(Nabu::FetchError) { drifted.fetch(File.join(root, "work")) }
        assert_includes error.message, sha[0, 12]
        assert_includes error.message, "pin"
      end
    end
  end

  def test_the_pin_is_the_census_head
    assert_equal "bac65b67166cd55033263c0d5f4b204b3d6d81e1", Nabu::Adapters::OttomanOcr::PINNED_SHA
  end

  private

  def with_fixture_copy
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "."), dir)
      yield dir
    end
  end

  # The fixture tree as a local upstream, plus an out-of-cone file standing
  # for the repository's YOLO model and viewer.
  def with_local_upstream
    with_fixture_copy do |upstream|
      File.write(File.join(upstream, "model.pt"), "weights")
      Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=main")
      Nabu::Shell.run("git", "-C", upstream, "add", ".")
      Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "ocr")
      yield upstream, Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
    end
  end
end
