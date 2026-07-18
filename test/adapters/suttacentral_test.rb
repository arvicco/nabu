# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# SuttaCentral adapter tests (P26-1): bilara-data, branch `published` — the
# whole Tipiṭaka in roman-script Pali (root/pli/ms, the Mahāsaṅgīti edition)
# plus the Patna Dhammapada (root/pra/pts), with English translations as
# `-en` sibling documents keyed by THE SAME segment ids (the ORACC/Damaskini
# precedent). The fixtures pin: the frozen urn grain (document per file stem,
# passage per segment), the range-stem citation rule, the per-publication
# license gate (138/140 CC0 + 1 PD + 1 CC BY-SA 3.0 — the pdhp outlier →
# license_override "attribution", P10-4), the translator-priority pick on
# double-covered stems, the sandbox/orphan/alternate skip census, and the
# root ↔ -en suffix-equality alignment. No network: fetch runs against a
# local fixture git repo whose branch is named `published`.
class SuttacentralTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("suttacentral")

  ROOT_URNS = %w[
    urn:nabu:suttacentral:dhp21-32
    urn:nabu:suttacentral:pdhp1-13
    urn:nabu:suttacentral:sn35.24
  ].freeze

  ALL_URNS = (ROOT_URNS + ROOT_URNS.map { |u| "#{u}-en" }).sort.freeze

  def conformance_adapter
    Nabu::Adapters::Suttacentral.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "suttacentral"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_suttacentral_source
    manifest = Nabu::Adapters::Suttacentral.manifest
    assert_equal "suttacentral", manifest.id
    assert_match(/Public Domain/, manifest.license, "the root text's own grant, verbatim")
    assert_match(/CC0/, manifest.license, "the translations' blanket grant")
    assert_equal "open", manifest.license_class
    assert_equal "https://github.com/suttacentral/bilara-data", manifest.upstream_url
    assert_equal "bilara-json", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_root_file_plus_en_siblings
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal ALL_URNS, refs.map(&:id), "sorted; -en siblings interleave after their roots"
    assert(refs.all? { |r| r.source_id == "suttacentral" })
  end

  def test_discover_without_translations_yields_roots_only
    refs = Nabu::Adapters::Suttacentral.new.discover(FIXTURES).to_a
    assert_equal ROOT_URNS, refs.map(&:id)
  end

  def test_discover_skips_the_upstream_sandbox_file
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_nil refs.find { |r| r.id.include?("xplayground") },
               "root/pli/ms/xplayground is upstream's own sandbox " \
               "(\"Do not commit this file…\"), never a document"
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert skips.clean?
    assert_equal 2, skips.skipped_by_rule,
                 "the sandbox file + the losing suddhaso alternate are censused rule skips"
  end

  def test_discover_reads_language_from_the_root_tree
    by_id = Nabu::Adapters::Suttacentral.new.discover(FIXTURES).to_h { |r| [r.id, r.metadata] }
    assert_equal "pli", by_id.fetch("urn:nabu:suttacentral:sn35.24")["language"]
    assert_equal "pra", by_id.fetch("urn:nabu:suttacentral:pdhp1-13")["language"],
                 "the Patna Dhammapada root is tagged pra by upstream — never relabeled pli"
  end

  def test_double_covered_stems_resolve_by_translator_priority
    ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:suttacentral:dhp21-32-en" }
    assert_equal "sujato", ref.metadata["translator"],
                 "dhp21-32 has both sujato and suddhaso — the frozen TRANSLATOR_PRIORITY picks sujato"
    assert ref.path.include?("/sujato/")
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  # --- the per-publication license gate (P10-4 override) ----------------------

  def test_the_pdhp_outlier_translation_carries_the_attribution_override
    document = parse_urn("urn:nabu:suttacentral:pdhp1-13-en")
    assert_equal "attribution", document.license_override,
                 "scpub69 is CC BY-SA 3.0 — the one non-open publication (censused 138 CC0 " \
                 "+ 1 PD + 1 BY-SA) — so its documents override the source's open class"
    assert_equal "scpub69", document.metadata["publication"]
  end

  def test_cc0_translations_and_roots_carry_no_override
    assert_nil parse_urn("urn:nabu:suttacentral:sn35.24-en").license_override,
               "scpub4 is CC0 — inherits the source class"
    assert_nil parse_urn("urn:nabu:suttacentral:sn35.24").license_override
    assert_nil parse_urn("urn:nabu:suttacentral:pdhp1-13").license_override,
               "the pra ROOT is an ancient text (the scpub64 doctrine); only the " \
               "translation carries the BY-SA grant"
  end

  def test_an_unmappable_publication_license_stops_discovery_loudly
    with_fixture_copy do |dir|
      rewrite_publication_license(dir, "scpub4", "Some Proprietary License v2")
      error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(dir).to_a }
      assert_match(/Some Proprietary License v2/, error.message)
      assert_match(/scpub4/, error.message)
    end
  end

  def test_without_publication_metadata_en_siblings_ride_the_blanket_grant
    # The ORACC precedent verbatim: gate only where the metadata file exists —
    # the base class also runs discover against .attic, which holds only the
    # files upstream DROPPED (no _publication.json). Attic texts were gated
    # while they were live.
    with_fixture_copy do |dir|
      FileUtils.rm(File.join(dir, "_publication.json"))
      adapter = conformance_adapter
      refs = adapter.discover(dir).to_a
      assert_equal ALL_URNS, refs.map(&:id), "retention never breaks discovery"
      document = adapter.parse(refs.find { |r| r.id.end_with?("sn35.24-en") })
      assert_nil document.license_override
      assert_nil document.metadata["publication"]
    end
  end

  def test_a_translation_without_a_publication_rides_the_repo_cc0_blanket
    with_fixture_copy do |dir|
      publications = JSON.parse(File.read(File.join(dir, "_publication.json")))
      publications.delete("scpub4")
      File.write(File.join(dir, "_publication.json"), JSON.generate(publications))
      adapter = conformance_adapter
      document = adapter.parse(adapter.discover(dir).find { |r| r.id.end_with?("sn35.24-en") })
      assert_nil document.license_override,
                 "LICENSE.md's blanket CC0 covers translation trees without their own record"
      assert_nil document.metadata["publication"]
    end
  end

  # --- parse: roots -----------------------------------------------------------

  def test_parse_yields_the_sutta_with_upstream_citations
    document = parse_urn("urn:nabu:suttacentral:sn35.24")
    assert_equal "pli", document.language
    assert_equal 12, document.size, "13 segments minus the empty sn35.24:1.5 (skip by rule)"
    assert_equal "urn:nabu:suttacentral:sn35.24:1.1",
                 document.find { |p| p.text.start_with?("“Sabbappahānāya") }.urn
    assert_equal "Saṁyutta Nikāya 35.24 — 3. Sabbavagga — Pahānasutta", document.title
  end

  def test_root_documents_carry_basket_and_collection_facets
    document = parse_urn("urn:nabu:suttacentral:sn35.24")
    assert_equal({ "value" => "sutta", "raw" => "sutta" }, document.metadata.dig("facets", "basket"))
    assert_equal({ "value" => "sn", "raw" => "sn" }, document.metadata.dig("facets", "collection"))
    assert_equal "ms", document.metadata["edition"]

    pdhp = parse_urn("urn:nabu:suttacentral:pdhp1-13")
    assert_equal({ "value" => "pdhp", "raw" => "pdhp" }, pdhp.metadata.dig("facets", "collection"))
    assert_equal "pts", pdhp.metadata["edition"]
  end

  # --- parse: -en siblings ----------------------------------------------------

  def test_en_sibling_shares_the_root_citation_suffixes
    original = parse_urn("urn:nabu:suttacentral:sn35.24")
    translation = parse_urn("urn:nabu:suttacentral:sn35.24-en")
    assert_equal "eng", translation.language
    assert_equal "translation", translation.metadata["kind"]
    original_suffixes = original.map { |p| p.urn.delete_prefix("#{original.urn}:") }
    translation_suffixes = translation.map { |p| p.urn.delete_prefix("#{translation.urn}:") }
    assert_equal %w[0.1 0.2 0.3 1.1 1.2 1.3 1.4 1.6 1.7 1.8 1.9],
                 original_suffixes & translation_suffixes,
                 "shared upstream segment ids align 1:1 — the Query::Parallel contract"
    # The honest asymmetry, both directions (upstream reality, pinned): the
    # translation expands the root's EMPTY 1.5 ellipsis segment, and leaves
    # the closing "Dutiyaṁ." (1.10) untranslated. Span grouping renders both
    # as one-sided rows, never a false pair.
    assert_includes translation_suffixes, "1.5"
    refute_includes original_suffixes, "1.5"
    assert_includes original_suffixes, "1.10"
    refute_includes translation_suffixes, "1.10"
    assert_equal "The ear … nose …", translation.find { |p| p.urn.end_with?(":1.5") }.text
    assert_equal "Linked Discourses 35.24 — 3. All — Giving Up", translation.title
    assert_equal "This is the principle for giving up the all.”",
                 translation.find { |p| p.urn.end_with?(":1.9") }.text
  end

  def test_range_stem_sibling_alignment_uses_full_segment_ids
    translation = parse_urn("urn:nabu:suttacentral:dhp21-32-en")
    passage = translation.find { |p| p.urn.end_with?("dhp21:1") }
    assert_equal "Heedfulness is the state free of death;", passage.text,
                 "sujato's rendering (the priority pick), cited by the per-verse segment id"
  end

  # --- fetch (local fixture repo, branch `published`; no network) -------------

  def test_fetch_clones_the_published_branch_then_pulls
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = suttacentral_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
      assert_equal "published", git(workdir, "rev-parse", "--abbrev-ref", "HEAD"),
                   "the sync is pinned to upstream's published branch, never master"
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      adapter = suttacentral_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_suttacentral_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["suttacentral"]
    refute_nil entry, "suttacentral must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Suttacentral, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-18: synced, parallel siblings eyeballed, flipped)"
    assert_equal "manual", entry.sync_policy
    assert entry.translations, "-en siblings are the point — the ORACC precedent"
    assert_equal Nabu::Adapters::Suttacentral.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def with_fixture_copy(&)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(Dir.glob(File.join(FIXTURES, "*")).reject { |p| p.end_with?("README.md", "manifest.yml") },
                     dir)
      yield dir
    end
  end

  def rewrite_publication_license(dir, key, license_type)
    path = File.join(dir, "_publication.json")
    publications = JSON.parse(File.read(path))
    publications[key]["license"] = { "license_type" => license_type,
                                     "license_abbreviation" => false, "license_url" => "" }
    File.write(path, JSON.generate(publications))
  end

  def suttacentral_pointing_at(upstream)
    adapter = Nabu::Adapters::Suttacentral.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  # A local stand-in for bilara-data: the branch must be named `published`
  # (the adapter pins its clone/fetch to it).
  def make_git_repo(dir)
    FileUtils.mkdir_p(File.join(dir, "root/pli/ms/sutta"))
    git(dir, "init", "-q", "-b", "published")
    File.write(File.join(dir, "root/pli/ms/sutta/x1_root-pli-ms.json"),
               JSON.generate({ "x1:1.1" => "evaṁ me sutaṁ" }))
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
