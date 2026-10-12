# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Shabados (P122-3): the Shabad OS database's Gurmukhī
# PRIMARY text — Guru Granth Sahib, Dasam Granth, Bhāī Gurdās, Bhāī Nand
# Lāl, Ardās — document = section, passage = line (upstream line id),
# translations and notes never read.
#
# Fixtures: a trimmed real tree of shabados/shabados database/collections
# (retrieved 2026-10-12, see the fixture README): Ardās whole; the Granth's
# Jap, the Dasam Granth's Jaap and Zafarnāmā each trimmed to their first
# line group; the referenced authors and assets whole. The line records
# keep their primary entries only (the translations riding the same
# records carry no grant, so they are not redistributed here).
class ShabadosTest < Minitest::Test
  include AdapterConformance

  SLUG = "shabados"
  ARDAS = "urn:nabu:shabados:ARDS.TVPK"
  JAP = "urn:nabu:shabados:SGGS.1DSA"
  JAAP = "urn:nabu:shabados:SDGR.3HWM"
  ZAFARNAMA = "urn:nabu:shabados:SDGR.546R"

  def conformance_adapter = Nabu::Adapters::Shabados.new

  def conformance_workdir = Nabu::TestSupport.fixtures(SLUG)

  def conformance_expected_source_id = SLUG

  def adapter = Nabu::Adapters::Shabados.new

  def workdir = conformance_workdir

  def parse(urn)
    adapter.parse(adapter.discover(workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}"))
  end

  def test_manifest_is_open_on_the_public_domain_mark
    manifest = Nabu::Adapters::Shabados.manifest
    assert_equal SLUG, manifest.id
    assert_equal "open", manifest.license_class
    assert_equal "shabados-toml", manifest.parser_family
    assert_equal "https://github.com/shabados/shabados", manifest.upstream_url
    assert_match(/Public Domain Mark 1\.0/, manifest.license)
    assert_match(/translations and notes .* stay out/, manifest.license)
  end

  def test_discover_yields_one_document_per_section_in_database_order
    refs = adapter.discover(workdir).to_a
    assert_equal [ARDAS, JAAP, ZAFARNAMA, JAP], refs.map(&:id),
                 "sources alphabetical, sections in each source's own order"
    assert_equal({ "source" => "SDGR", "section" => "546R", "section_order" => 2 }, refs[2].metadata)
    assert_equal 0, adapter.discovery_skips(workdir).unrecognized
  end

  def test_the_granth_opens_with_the_mul_mantar_at_ang_one
    document = parse(JAP)
    assert_equal "pan", document.language
    assert_equal "gurū granth sāhib — Jap", document.title
    assert_equal 10, document.passages.size
    first = document.passages.first
    assert_equal "#{JAP}:0NVY", first.urn, "the upstream line id is the citation"
    assert_equal "ੴ ਸਤਿ ਨਾਮੁ ਕਰਤਾ ਪੁਰਖੁ ਨਿਰਭਉ ਨਿਰਵੈਰੁ ਅਕਾਲ ਮੂਰਤਿ ਅਜੂਨੀ ਸੈਭੰ ਗੁਰ ਪ੍ਰਸਾਦਿ ॥", first.text
    assert_equal({ "line_group" => "DMP", "author" => "Guru Nanak", "page" => 1, "page_line" => 1,
                   "sttm2" => 1, "assets" => ["SSA2"] }, first.annotations)
    assert_equal "ਆਦਿ ਸਚੁ; ਜੁਗਾਦਿ ਸਚੁ ॥", document.passages[2].text, "vishrām marks stay verbatim"
    meta = document.metadata
    assert_equal ["Guru Nanak"], meta["authors"]
    assert_equal({ "SSA2" => "Shabadaarth" }, meta["primary_sources"])
    assert_equal "ਗੁਰੂ ਗ੍ਰੰਥ ਸਾਹਿਬ", meta["source_name_guru"]
  end

  def test_a_second_primary_rides_as_a_variant
    document = parse(JAAP)
    assert_equal "bra-Guru", document.language
    first = document.passages.first
    assert_equal "ੴ ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥", first.text, "the first primary is the text"
    assert_equal [{ "assets" => ["DDTK"], "text" => "ੴ; ਸਤਿਗੁਰ ਪ੍ਰਸਾਦਿ ॥ ਸ੍ਰੀ ਵਾਹਿਗੁਰੂ ਜੀ ਕੀ; ਫਤਹ ॥" }],
                 first.annotations["variants"]
    agreed = document.passages[1]
    assert_equal %w[DGDG DDTK], agreed.annotations["assets"], "two printed sources agreeing on one reading"
    refute agreed.annotations.key?("variants")
    assert_equal({ "DGDG" => "Das Granthi", "DDTK" => "Sundar Gutka Damdami Taksal" },
                 document.metadata["primary_sources"])
  end

  def test_section_language_overrides_the_source_default
    assert_equal "fas-Guru", parse(ZAFARNAMA).language, "the Persian Zafarnāmā inside the Braj Dasam Granth"
    assert_equal "ਜ਼ਫ਼ਰਨਾਮਹ ॥", parse(ZAFARNAMA).passages[2].text
    assert_equal "pan", parse(ARDAS).language
  end

  def test_translations_and_notes_are_never_read
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(workdir, "database"), dir)
      line = File.join(dir, "database", "collections", "lines", "0", "0N", "0NVY.toml")
      File.write(line, File.read(line) + <<~TOML)

        [[content]]
        assets = ["SBMS"]
        type = "translation"
        language = "en"
        data = "One Universal Creator God."
      TOML
      document = adapter.parse(adapter.discover(dir).find { |ref| ref.id == JAP })
      first = document.passages.first
      refute_match(/Creator/, first.text)
      refute first.annotations.key?("variants"), "a translation is never a variant reading"
    end
  end

  def test_an_unclassified_source_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(workdir, "database"), dir)
      sources = File.join(dir, "database", "collections", "sources")
      FileUtils.mv(File.join(sources, "ARDS.toml"), File.join(sources, "XNEW.toml"))
      ref = adapter.discover(dir).find { |candidate| candidate.id == "urn:nabu:shabados:XNEW.TVPK" }
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/XNEW has no language classification/, error.message)
    end
  end

  def test_a_section_listed_by_no_source_is_censused
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(workdir, "database"), dir)
      sections = File.join(dir, "database", "collections", "sections")
      FileUtils.cp(File.join(sections, "1DSA.toml"), File.join(sections, "ZZZZ.toml"))
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_equal ["sections/ZZZZ.toml: listed by no source"], skips.notes
    end
  end

  def test_the_language_table_classifies_every_censused_source
    assert_equal %w[ARDS GJNL GZNL JBNL KSBG SDGR SGGS SRBL VBGJ ZNNL],
                 Nabu::Adapters::Shabados::SOURCE_LANGUAGES.keys.sort,
                 "the ten sources of the 2026-10-12 census"
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_sparse_clones_only_the_collections_cone
    Dir.mktmpdir("nabu-shabados-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      FileUtils.cp_r(File.join(workdir, "database"), upstream)
      FileUtils.mkdir_p(File.join(upstream, "database", "collections", "banis"))
      File.write(File.join(upstream, "database", "collections", "banis", "X.toml"), "lines = []\n")
      FileUtils.mkdir_p(File.join(upstream, "apps", "desktop"))
      File.write(File.join(upstream, "apps", "desktop", "index.ts"), "app")
      File.write(File.join(upstream, "database", "README.md"), "readme")
      Nabu::Shell.run("git", "init", "-q", upstream)
      git(upstream, "add", ".")
      # gc.auto=0: a detached auto-gc repacking the seed's loose objects
      # races the local clone's object copy ("failed to copy file").
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "gc.auto=0",
          "-c", "maintenance.auto=false", "commit", "-q", "-m", "seed")

      work = File.join(root, "canonical")
      shabados = adapter
      shabados.define_singleton_method(:repo_url) { upstream }
      report = shabados.fetch(work)

      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      assert File.file?(File.join(work, "database", "collections", "lines", "0", "0N", "0NVY.toml"))
      assert File.file?(File.join(work, "database", "README.md"))
      refute File.exist?(File.join(work, "apps")), "the app code stays out"
      refute File.exist?(File.join(work, "database", "collections", "banis")), "and the bani lists"
      assert_equal [ARDAS, JAAP, ZAFARNAMA, JAP], shabados.discover(work).map(&:id)
    end
  end

  private

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
