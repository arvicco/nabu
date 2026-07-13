# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Coptic Scriptorium adapter tests (P17-1): the corpora repo's TT layer at
# the pinned release tag. Includes the shared AdapterConformance suite
# against the checked-in fixtures (five documents across four corpora — see
# test/fixtures/coptic-scriptorium/README.md). No network: fetch runs
# against a local git repo carrying the pinned tag.
class CopticScriptoriumTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("coptic-scriptorium")

  DOCUMENT_URNS = %w[
    urn:nabu:coptic-scriptorium:ap.4.monbeg
    urn:nabu:coptic-scriptorium:besa.food.monbbb
    urn:nabu:coptic-scriptorium:nt.mark.sahidica
    urn:nabu:coptic-scriptorium:nt.phlm.sahidica
    urn:nabu:coptic-scriptorium:papyri_info.tm82127.cpr_2_237
  ].freeze

  def conformance_adapter
    Nabu::Adapters::CopticScriptorium.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "coptic-scriptorium"
  end

  # The documented search-form derivation (conventions §9): the upstream
  # norm layer at word grain, recomputable from the stored row.
  def conformance_search_source(passage)
    Nabu::Adapters::CopticTtParser.search_source(passage.text, passage.annotations)
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_identifies_the_source_with_the_nc_posture
    manifest = Nabu::Adapters::CopticScriptorium.manifest
    assert_equal "coptic-scriptorium", manifest.id
    assert_equal "nc", manifest.license_class
    assert_equal "https://github.com/CopticScriptorium/corpora", manifest.upstream_url
    assert_equal "coptic-tt", manifest.parser_family
    assert_includes manifest.license, "academic use only"
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_document_with_chapter_files_merged_to_books
    refs = conformance_adapter.discover(FIXTURES).to_a
    assert_equal DOCUMENT_URNS, refs.map(&:id)
    assert(refs.all? { |r| r.metadata["language"] == "cop" })
  end

  def test_discover_reads_per_document_license_overrides_the_p10_4_mechanism
    overrides = conformance_adapter.discover(FIXTURES).to_h { |r| [r.id, r.metadata["license_override"]] }
    assert_equal "attribution", overrides.fetch("urn:nabu:coptic-scriptorium:besa.food.monbbb")
    assert_equal "attribution", overrides.fetch("urn:nabu:coptic-scriptorium:ap.4.monbeg")
    assert_equal "attribution", overrides.fetch("urn:nabu:coptic-scriptorium:papyri_info.tm82127.cpr_2_237")
    # the Wells NT stays at the source's own nc class — no override
    assert_nil overrides.fetch("urn:nabu:coptic-scriptorium:nt.mark.sahidica")
    assert_nil overrides.fetch("urn:nabu:coptic-scriptorium:nt.phlm.sahidica")
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  def test_discover_excludes_the_upstream_duplicate_treebank_collections_by_rule
    Dir.mktmpdir do |dir|
      # real bytes, placed under an excluded collection dir AND a live one
      %w[coptic-treebank/coptic.treebank_TT doc-papyri/doc.papyri_TT].each do |sub|
        FileUtils.mkdir_p(File.join(dir, sub))
        FileUtils.cp(File.join(FIXTURES, "doc-papyri", "doc.papyri_TT", "cpr.2.237.tt"),
                     File.join(dir, sub, "cpr.2.237.tt"))
      end
      adapter = conformance_adapter
      assert_equal ["urn:nabu:coptic-scriptorium:papyri_info.tm82127.cpr_2_237"],
                   adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.skipped_by_rule
      assert_predicate skips, :clean?
    end
  end

  def test_discovery_skips_are_clean_over_the_fixture_set
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 0, skips.skipped_by_rule
    assert_predicate skips, :clean?
  end

  # --- the license rule table (survey §3) --------------------------------------

  def test_license_classification_follows_the_censused_terms
    classify = Nabu::Adapters::CopticScriptorium.method(:license_class_of)
    assert_equal "attribution", classify.call("<a href='https://creativecommons.org/licenses/by/4.0/'>CC-BY 4.0</a>")
    assert_equal "attribution", classify.call("CC-BY-SA")
    assert_equal "attribution", classify.call("Text is in public domain. Annotations are CC-BY 4.0")
    assert_equal "nc", classify.call("(c)2000-2006 by J Warren Wells, for academic use only.")
    assert_equal "nc", classify.call("CC BY-NC-SA 4.0")
    assert_equal "nc", classify.call("all rights reserved") # unknown terms → most restrictive, never skipped
    assert_nil classify.call(nil) # the 3-doc license-less skip rule (book.bartholomew)
    assert_nil classify.call("  ")
  end

  # --- parse ------------------------------------------------------------------

  def test_parse_merges_zip_chapter_files_into_a_book_document
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:coptic-scriptorium:nt.mark.sahidica" }
    document = adapter.parse(ref)
    assert_equal "cop", document.language
    assert_equal 12, document.size
    assert_equal "urn:nabu:coptic-scriptorium:nt.mark.sahidica:1.1", document.first.urn
    assert_equal "urn:nabu:coptic-scriptorium:nt.mark.sahidica:1.12", document.passages.last.urn
    assert document.first.text.start_with?("ⲧⲁⲣⲭⲏ ⲙⲡⲉⲩⲁⲅⲅⲉⲗⲓⲟⲛ")
  end

  def test_parse_handles_the_single_chapter_book_edge_case
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:coptic-scriptorium:nt.phlm.sahidica" }
    document = adapter.parse(ref)
    assert_equal 25, document.size
    assert_equal "urn:nabu:coptic-scriptorium:nt.phlm.sahidica:1.25", document.passages.last.urn
  end

  def test_parse_carries_document_metadata_including_the_rosters
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:coptic-scriptorium:nt.mark.sahidica" }
    document = adapter.parse(ref)
    assert_includes document.metadata["people"], "John the Baptist"
    assert_equal "Sahidic Coptic", document.metadata["dialect"]
    assert_equal "urn:nabu:coptic-scriptorium:nt.mark.sahidica", document.urn
  end

  def test_parse_besa_keeps_diplomatic_text_and_mints_norm_derived_search_form
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:coptic-scriptorium:besa.food.monbbb" }
    document = adapter.parse(ref)
    assert_equal 2, document.size
    passage = document.first
    assert_equal "urn:nabu:coptic-scriptorium:besa.food.monbbb:1.1", passage.urn
    assert passage.text.start_with?("ⲉⲧⲉⲧ︤ⲛ︥ϣ︤ⲡ︥ϩⲓⲥⲉ") # strokes kept — the witness's spelling
    # queries hit the regularized layer: the norm-derived search form is
    # stroke-free and word-grain (folded through the ONE boundary)
    assert passage.text_normalized.start_with?("ⲉ ⲧⲉⲧⲛ ϣⲡϩⲓⲥⲉ")
    assert_equal "On Lack of Food", document.title
  end

  def test_parse_cpr_flags_ordinal_addressing_and_keeps_the_papyri_crossref
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:coptic-scriptorium:papyri_info.tm82127.cpr_2_237" }
    document = adapter.parse(ref)
    assert_equal 9, document.size
    assert_equal "translation-ordinal", document.first.annotations["addressing"]
    assert_equal "http://papyri.info/ddbdp/cpr;2;237", document.metadata["source"]
  end

  def test_gold_lemmas_reach_the_index_key_and_automatic_ones_do_not
    adapter = conformance_adapter
    by_id = adapter.discover(FIXTURES).to_h { |r| [r.id, r] }
    gold = adapter.parse(by_id.fetch("urn:nabu:coptic-scriptorium:besa.food.monbbb"))
    assert(gold.first.annotations["tokens"].any? { |t| t["lemma"] })
    automatic = adapter.parse(by_id.fetch("urn:nabu:coptic-scriptorium:nt.phlm.sahidica"))
    assert(automatic.first.annotations["tokens"].none? { |t| t["lemma"] })
    assert(automatic.first.annotations["tokens"].any? { |t| t["lemma_auto"] })
  end

  # --- fetch (local git only, no network) ---------------------------------------

  def test_fetch_clones_at_the_pinned_release_tag
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_tagged_repo(upstream)
      workdir = File.join(root, "canonical")
      adapter = conformance_adapter
      adapter.define_singleton_method(:repo_url) { upstream }
      report = adapter.fetch(workdir)
      assert File.file?(File.join(workdir, "README.md"))
      tagged = Nabu::Shell.run("git", "-C", upstream, "rev-parse",
                               "#{Nabu::Adapters::CopticScriptorium::RELEASE_TAG}^{commit}").strip
      assert_equal tagged, report.sha, "fetch must land on the pinned tag, not the moving default branch"
    end
  end

  private

  # A local upstream: commit 1 tagged with the pinned release tag, commit 2
  # ahead of it on the default branch (master moves between releases —
  # the pin must not follow it).
  def make_tagged_repo(dir)
    FileUtils.mkdir_p(dir)
    run = ->(*argv) { Nabu::Shell.run("git", "-C", dir, *argv) }
    Nabu::Shell.run("git", "init", "--quiet", dir)
    run.call("config", "user.email", "test@example.invalid")
    run.call("config", "user.name", "Test")
    File.write(File.join(dir, "README.md"), "corpora\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "release")
    run.call("tag", Nabu::Adapters::CopticScriptorium::RELEASE_TAG)
    File.write(File.join(dir, "README.md"), "corpora, moved on\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "post-release drift")
  end
end
