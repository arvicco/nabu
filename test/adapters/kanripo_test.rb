# frozen_string_literal: true

require "test_helper"

require "tmpdir"
require "fileutils"

# Nabu::Adapters::Kanripo (P33-0; KR2 wave 2 P33-1): nabu's first many-repo
# source — the Kanseki Repository, one GitHub repo per text, discovered
# through the KR-Catalog index and parsed by the mandoku family. Fixtures
# are seventeen real texts (waves 1–3 fetched individually 2026-07-20, plus
# the two P43-r2 quarantine-recovery exemplars extracted from the local
# canonical snapshot 2026-07-23) and a trimmed KR-Catalog slice; see
# test/fixtures/kanripo/README.md.
class KanripoTest < Minitest::Test
  include AdapterConformance

  FIXTURES = File.expand_path("../fixtures/kanripo", __dir__)

  TEXT_IDS = %w[KR1a0149 KR1a0170 KR1h0004 KR2a0001 KR2a0038 KR2f0037
                KR2g0007 KR3a0001 KR3g0023 KR3i0042 KR4d0525 KR4j0026
                KR5a0001 KR5a0004 KR5c0091 KR5g0001 KR5i0030].freeze

  def conformance_adapter
    Nabu::Adapters::Kanripo.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "kanripo"
  end

  # -- manifest -------------------------------------------------------------

  def test_manifest_records_the_org_level_grant_verbatim
    manifest = Nabu::Adapters::Kanripo.manifest

    assert_includes manifest.license,
                    "Comprehensive collection of premodern Chinese texts. Licensed as CC BY SA 4.0."
    assert_equal "attribution", manifest.license_class
    assert_equal "mandoku", manifest.parser_family
  end

  def test_remote_probe_targets_the_catalog_repo_not_the_unprobeable_org
    assert_equal ["https://github.com/kanripo/KR-Catalog"],
                 Nabu::Adapters::Kanripo.upstream_repo_urls
  end

  # -- discover -------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_dir_sorted_with_class_metadata
    refs = conformance_adapter.discover(FIXTURES).to_a

    classes = refs.map { |ref| ref.metadata["class"] }
    assert_equal TEXT_IDS.map { |id| "urn:nabu:kanripo:#{id}" }, refs.map(&:id)
    assert_equal %w[KR1 KR1 KR1 KR2 KR2 KR2 KR2 KR3 KR3 KR3 KR4 KR4 KR5 KR5 KR5 KR5 KR5], classes
    refs.each { |ref| assert File.directory?(ref.path), "ref path must be the text dir" }
  end

  def test_discover_ignores_the_catalog_clone_and_fetch_ledger
    Dir.mktmpdir("nabu-kanripo") do |workdir|
      FileUtils.cp_r(File.join(FIXTURES, "KR1a0170"), File.join(workdir, "KR1a0170"))
      FileUtils.cp_r(File.join(FIXTURES, "KR-Catalog"), File.join(workdir, "KR-Catalog"))
      File.write(File.join(workdir, Nabu::KanripoFetch::LEDGER_FILE), "{}")

      refs = conformance_adapter.discover(workdir).to_a

      assert_equal ["urn:nabu:kanripo:KR1a0170"], refs.map(&:id)
    end
  end

  def test_classes_scope_acquisition_not_discovery
    # `classes:` scopes what fetch ACQUIRES; discovery ingests whatever is on
    # disk, so narrowing the config never mass-withdraws already-held texts.
    narrow = Nabu::Adapters::Kanripo.new(classes: ["KR1"])

    assert_equal conformance_adapter.discover(FIXTURES).to_a.map(&:id),
                 narrow.discover(FIXTURES).to_a.map(&:id)
  end

  def test_classes_are_validated_at_construction
    error = assert_raises(Nabu::ValidationError) { Nabu::Adapters::Kanripo.new(classes: ["KR7"]) }
    assert_match(/KR7/, error.message)
    assert_raises(Nabu::ValidationError) { Nabu::Adapters::Kanripo.new(classes: []) }
  end

  # -- parse ----------------------------------------------------------------

  def test_parses_the_analects_at_page_grain
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id.end_with?("KR1h0004") }
    document = adapter.parse(ref)

    assert_equal "論語", document.title
    assert_equal "lzh", document.language
    assert_equal "CHANT", document.metadata["edition"]
    assert_equal "KR1", document.metadata["class"]
    assert_equal 33, document.size
    first = document.passages.first
    assert_equal "urn:nabu:kanripo:KR1h0004:001:1a", first.urn
    assert_includes first.text, "學而時習之"
  end

  def test_fixture_corpus_parses_to_the_censused_passage_total
    adapter = conformance_adapter
    total = adapter.discover(FIXTURES).sum { |ref| adapter.parse(ref).size }

    # census: 253 (waves 1–2) + 177 KR5 (109 + 1 + 42 + 16 + 9 — P37-1) +
    # 129 P43-r2 recovery exemplars (53 KR2f0037 + 76 KR1a0149).
    assert_equal 559, total
  end

  # -- P43-r2 quarantine recovery (D42-c census: 75 duplicate-anchor + 26
  #    text-before-first-anchor texts recoverable of 133) --------------------

  def test_two_fascicle_duplicate_anchors_parse_with_disambiguated_urns
    # KR2f0037 juan 042 concatenates two source fascicles, each restarting
    # leaf-side pagination at 1a — pre-P43 a quarantine, now the second
    # sweep keys as #2 (see mandoku_parser_test for the family detail).
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id.end_with?("KR2f0037") }
    document = adapter.parse(ref)

    assert_equal "三朝名臣言行錄", document.title
    urns = document.map(&:urn)
    assert_includes urns, "urn:nabu:kanripo:KR2f0037:042:1a"
    assert_includes urns, "urn:nabu:kanripo:KR2f0037:042:1a#2"
    assert_equal urns, adapter.parse(ref).map(&:urn)
  end

  def test_text_before_the_first_anchor_parses_onto_a_front_matter_page
    # KR1a0149 juan 001 opens with prefatory print lines before the first
    # page anchor — pre-P43 a quarantine, now the synthetic front page.
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id.end_with?("KR1a0149") }
    document = adapter.parse(ref)

    assert_equal "易翼說", document.title
    front = document.passages.first
    assert_equal "urn:nabu:kanripo:KR1a0149:001:front", front.urn
    assert front.annotations["front_matter"]
    assert_equal document.map(&:urn), adapter.parse(ref).map(&:urn)
  end

  def test_wave_three_default_classes_include_the_daozang
    assert_equal %w[KR1 KR2 KR3 KR4 KR5], Nabu::Adapters::Kanripo::DEFAULT_CLASSES
  end

  def test_parses_a_daozang_witness_overlay_at_witness_page_grain
    # KR5a0001 度人經 (DZJY overlay): the witness edition CK-KZ is the
    # citable page structure; base-edition HFL pages ride annotations.
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |candidate| candidate.id.end_with?("KR5a0001") }
    document = adapter.parse(ref)

    assert_equal "元始無量度人上品妙經", document.title
    assert_equal "KR5", document.metadata["class"]
    assert_equal "witness", document.metadata["page_scheme"]
    assert_equal "CK-KZ", document.metadata["witness"]
    assert_equal "urn:nabu:kanripo:KR5a0001:01:001a", document.passages.first.urn
  end

  # -- fetch (local rig — no network, the house pattern) ---------------------

  def test_fetch_runs_the_catalog_scoped_wave_and_reports_the_catalog_pin
    Dir.mktmpdir("nabu-kanripo-fetch") do |root|
      upstream = File.join(root, "upstream")
      seed_repo(File.join(upstream, "KR-Catalog"),
                "KR/KR1a.txt" => fixture_bytes("KR-Catalog/KR/KR1a.txt"))
      seed_repo(File.join(upstream, "KR1a0170"),
                "KR1a0170_000.txt" => fixture_bytes("KR1a0170/KR1a0170_000.txt"),
                "KR1a0170_001.txt" => fixture_bytes("KR1a0170/KR1a0170_001.txt"))
      workdir = File.join(root, "work")

      adapter = Nabu::Adapters::Kanripo.new(classes: ["KR1"])
      adapter.define_singleton_method(:catalog_url) { File.join(upstream, "KR-Catalog") }
      adapter.define_singleton_method(:repo_base) { upstream }
      adapter.define_singleton_method(:fetch_delay) { 0 }

      report = adapter.fetch(workdir)

      assert_equal head(File.join(upstream, "KR-Catalog")), report.sha
      assert_match(/cloned 1/, report.notes)
      assert File.file?(File.join(workdir, "KR1a0170", "KR1a0170_001.txt"))
      refs = adapter.discover(workdir).to_a
      assert_equal ["urn:nabu:kanripo:KR1a0170"], refs.map(&:id)
    end
  end

  private

  def seed_repo(dir, files)
    FileUtils.mkdir_p(dir)
    Nabu::Shell.run("git", "-C", dir, "init", "-q")
    files.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
    Nabu::Shell.run("git", "-C", dir, "add", ".")
    Nabu::Shell.run("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
                    "commit", "-q", "-m", "seed")
  end

  def head(dir)
    Nabu::Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip
  end

  def fixture_bytes(rel)
    File.binread(File.join(FIXTURES, rel))
  end
end
