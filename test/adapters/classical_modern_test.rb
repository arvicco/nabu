# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# ClassicalModern adapter tests (P88-A2): NiuTrans/Classical-Modern — the
# ~967k-pair Classical↔Modern Chinese parallel corpus at CHAPTER grain
# (双语数据/<book>[/<section>]/<chapter>/{source,target,bitext,数据来源}.txt;
# 97 books / 7,304 chapter units, censused 2026-08-29 via blobless clone).
# The nk2028 fork (frozen 2022) destroyed per-chapter identity — the
# canonical upstream is the source. Fixtures carry BOTH censused depths:
# a book/chapter unit (世说新语/仇隙, 39 pairs) and a book/section/chapter
# unit (三十六计/并战计/上屋抽梯, 2 pairs) — complete real files.
class ClassicalModernTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("classical-modern")

  SHISHUO = "urn:nabu:classical-modern:世说新语:仇隙"
  SANSHILIU = "urn:nabu:classical-modern:三十六计:并战计:上屋抽梯"

  def adapter
    Nabu::Adapters::ClassicalModern.new(translations: true)
  end

  # --- manifest / registry --------------------------------------------------

  def test_manifest_records_the_mit_grant_and_the_provenance_honesty
    manifest = Nabu::Adapters::ClassicalModern.manifest
    assert_equal "classical-modern", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_match(/MIT/, manifest.license)
    assert_match(/crawl/i, manifest.license,
                 "the web-crawled translation provenance is stated, never hidden")
    assert_equal "sentence-lines", manifest.parser_family
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["classical-modern"]
    refute_nil entry, "config/sources.yml must register classical-modern"
    assert_equal Nabu::Adapters::ClassicalModern, entry.adapter_class
    assert entry.wired, "live (first sync verified + owner sign-off 2026-08-30; flipped 2026-08-31)"
    assert_equal "manual", entry.sync_policy
    assert entry.translations, "the modern side is the point of a parallel corpus"
    assert_equal ["-cmn"], entry.siblings
  end

  # --- discover -------------------------------------------------------------

  def test_discover_yields_chapter_docs_and_cmn_siblings_sorted
    refs = adapter.discover(FIXTURES).to_a
    assert_equal [SANSHILIU, "#{SANSHILIU}-cmn", SHISHUO, "#{SHISHUO}-cmn"], refs.map(&:id),
                 "one lzh doc per chapter source.txt + its -cmn sibling over target.txt"
  end

  def test_translations_off_yields_only_the_lzh_side
    refs = Nabu::Adapters::ClassicalModern.new(translations: false).discover(FIXTURES).to_a
    assert_equal [SANSHILIU, SHISHUO], refs.map(&:id)
  end

  def test_bitext_and_provenance_files_are_censused_discovery_skips
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 4, skips.skipped_by_rule,
                 "bitext.txt (a rendition of source+target) and 数据来源.txt (a metadata " \
                 "rider) never become documents — 2 each across the two fixture chapters"
  end

  # --- parse ----------------------------------------------------------------

  def parse(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("no fixture ref #{urn}")
    adapter.parse(ref)
  end

  def test_the_lzh_side_parses_one_passage_per_sentence_line
    document = parse(SHISHUO)
    assert_equal "lzh", document.language
    assert_equal 39, document.passages.size
    first = document.passages.first
    assert_equal "#{SHISHUO}:1", first.urn
    assert_equal "孙秀既恨石崇不与绿珠，又憾潘岳昔遇之不以礼。", first.text
    assert_equal "世说新语", document.metadata.fetch("book")
    assert_equal "仇隙", document.metadata.fetch("chapter")
    refute document.metadata.key?("section"), "a depth-2 unit has no section"
    assert_match(/易文言/, document.metadata.fetch("provenance"),
                 "the per-chapter 数据来源 crawl sources ride metadata verbatim")
  end

  def test_the_cmn_sibling_parses_line_aligned
    document = parse("#{SHISHUO}-cmn")
    assert_equal "cmn", document.language
    assert_equal "translation", document.metadata.fetch("kind")
    assert_equal 39, document.passages.size, "line-aligned with the lzh side"
    assert_equal "#{SHISHUO}-cmn:1", document.passages.first.urn
    assert_match(/孙秀既恨石崇不把绿珠送给他/, document.passages.first.text)
  end

  def test_the_deeper_section_layout_parses_with_its_section
    document = parse(SANSHILIU)
    assert_equal 2, document.passages.size
    assert_equal "三十六计", document.metadata.fetch("book")
    assert_equal "并战计", document.metadata.fetch("section")
    assert_equal "上屋抽梯", document.metadata.fetch("chapter")
    assert_equal "假之以便，唆之使前，断其援应，陷之死地。", document.passages.first.text
  end

  def test_a_source_target_line_count_mismatch_is_a_parse_error
    Dir.mktmpdir do |dir|
      chapter = File.join(dir, "双语数据", "书", "章")
      FileUtils.mkdir_p(chapter)
      File.write(File.join(chapter, "source.txt"), "一\n二\n")
      File.write(File.join(chapter, "target.txt"), "one\n")
      ref = adapter.discover(dir).find { |r| r.id.end_with?("书:章") }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/line/, error.message, "equal line counts ARE the format (the aranese rule)")
    end
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end
end
