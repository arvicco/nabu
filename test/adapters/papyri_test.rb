# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Papyri.info (DDbDP + DCLP) adapter tests (P3-6; DCLP lane P104-3). The
# adapter composes DdbdpParser with the idp.data repo layout: discover
# walks DDB_EpiDoc_XML/<collection>/(<collection>.<volume>/)?*.xml — both
# nested (bgu/bgu.1/) and flat (c.epist.lat/) collections — peeking each
# header for ddb-hybrid/HGV/TM idnos, title and edition language, PLUS
# (P104-3) DCLP/<TM-thousand>/<TM>.xml — the literary-papyri tree of the
# SAME idp.data clone — peeking dclp-hybrid and skipping the
# metadata-only catalog stubs (12,571 of 14,842 upstream files carry a
# self-closed or text-less edition div); parse delegates to DdbdpParser
# (urn namespace dclp for DCLP refs); fetch clones/pulls the single
# upstream repo. Includes the shared AdapterConformance suite against the
# checked-in fixtures. No network: fetch runs against a local git repo in
# a tmpdir.
class PapyriTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ddbdp") # NABU_FIXTURE_DIR-aware (fixtures:check)

  # --- AdapterConformance hooks -------------------------------------------

  def conformance_adapter
    Nabu::Adapters::Papyri.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "papyri-ddbdp"
  end

  # --- manifest -----------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Papyri.manifest
    assert_equal "papyri-ddbdp", manifest.id
    assert_equal "Papyri.info — Duke Databank of Documentary Papyri + " \
                 "Digital Corpus of Literary Papyri",
                 manifest.name
    assert_equal "CC BY 3.0 (per-document availability)", manifest.license
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/papyri/idp.data", manifest.upstream_url
    assert_equal "ddbdp", manifest.parser_family
  end

  # --- discover -----------------------------------------------------------

  def test_discover_finds_both_nested_and_flat_collections_with_frozen_urn_minting
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:dclp:62952
      urn:nabu:dclp:64388
      urn:nabu:dclp:805566
      urn:nabu:ddbdp:bgu:1:100
      urn:nabu:ddbdp:bgu:1:102
      urn:nabu:ddbdp:c.epist.lat::10
    ], refs.map(&:id)
    refs.each do |ref|
      assert_equal "papyri-ddbdp", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path)
    end
  end

  def test_discover_metadata_carries_language_title_and_hgv_tm_crosslinks
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    bgu100, bgu102, cel10 = refs.select { |ref| ref.id.start_with?("urn:nabu:ddbdp:") }

    assert_equal({ "language" => "grc", "title" => "bgu.1.100", "hgv" => "8875", "tm" => "8875" },
                 bgu100.metadata)
    assert_equal({ "language" => "grc", "title" => "bgu.1.102", "hgv" => "8877", "tm" => "8877" },
                 bgu102.metadata)
    # Edition div says xml:lang="la"; our tags use ISO 639-3 lat.
    assert_equal({ "language" => "lat", "title" => "c.epist.lat.10", "hgv" => "78573", "tm" => "78573" },
                 cel10.metadata)
  end

  # --- the DCLP lane (P104-3) ----------------------------------------------

  def test_dclp_discover_mints_the_dclp_namespace_with_real_titles_and_tm
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
                                 .select { |ref| ref.id.start_with?("urn:nabu:dclp:") }
    claud, harris, praxidicae = refs

    # TM 62952 (dclp-hybrid o.claud;1;190); edition xml:lang="la" → lat.
    # Identity is the <idno type="dclp"> number, NOT the hybrid — the
    # hybrid is non-unique upstream (two Homer papyri, TM 60467 and
    # TM 61136, both claim p.hal;;5), while the dclp number is the
    # filename and papyri.info/dclp/<n> — unique across all 14,842 files
    # (census 2026-09-26).
    assert_equal "urn:nabu:dclp:62952", claud.id
    assert_equal "lat", claud.metadata["language"]
    assert_equal "Vergil, Aeneid I.1-3 and Two Unidentified Lines", claud.metadata["title"]
    assert_equal "62952", claud.metadata["tm"]

    # TM 64388 (dclp-hybrid p.harr;1;98) — textpart divs.
    assert_equal "urn:nabu:dclp:64388", harris.id
    assert_equal "grc", harris.metadata["language"]
    assert_equal "64388", harris.metadata["tm"]

    # TM 805566 — a tm;;-hybrid file (the shape 7,937 of 14,833 carry).
    assert_equal "urn:nabu:dclp:805566", praxidicae.id
    assert_equal "grc", praxidicae.metadata["language"]
    assert_equal "Invocantur Praxidicae", praxidicae.metadata["title"]
  end

  def test_dclp_discover_skips_metadata_only_stubs
    # DCLP/317/316777.xml is a real upstream catalog stub: dclp-hybrid and
    # a Coptic edition div, but the div is SELF-CLOSED — no transcription.
    # 12,571 of the 14,842 upstream DCLP files have this shape; they must
    # be skipped at discover, not quarantined at parse ("no citable
    # lines").
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    assert(refs.none? { |ref| ref.id.include?("316777") },
           "the self-closed-edition stub must not become a document ref")
    assert(refs.none? { |ref| ref.path.include?("316777") })
  end

  def test_dclp_parse_round_trips_the_vergil_ostracon
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:dclp:62952" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal "lat", document.language
    assert_equal "Vergil, Aeneid I.1-3 and Two Unidentified Lines", document.title
    # The ostracon opens with a lost line marked <lb n="1"/> + gap, then
    # RESTARTS at <lb n="1"/> — the P5-1 implicit block engages, so the
    # Aeneid lines live in block b2 (and the trailing lost-line lb n="5"
    # collides again into b3). Line 3 is "arma virumque…".
    aeneid = document.to_a.find { |p| p.urn == "urn:nabu:dclp:62952:b2:3" }
    refute_nil aeneid, "restart-block line 3 must mint under the dclp namespace " \
                       "(got #{document.to_a.map(&:urn).inspect})"
    assert_equal "arma virumque cano Troiae qui primus ab oris", aeneid.text
  end

  def test_dclp_parse_textparts_ride_in_the_urn_path
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:dclp:64388" }
    document = adapter.parse(ref)
    assert_equal "grc", document.language
    # Two textpart divs (n="1", n="2"), each restarting line numbering —
    # the textpart path disambiguates: part 1 line 1 and part 2 line 1.
    urns = document.to_a.map(&:urn)
    assert_includes urns, "urn:nabu:dclp:64388:1:1"
    assert_includes urns, "urn:nabu:dclp:64388:2:1"
    first = document.to_a.first
    assert_equal "καστορίου οὐγκία ἥμισυ", first.text, "expansions read expanded (Leiden policy)"
  end

  def test_discover_skips_files_without_a_ddb_hybrid_idno
    Dir.mktmpdir do |root|
      collection = File.join(root, "DDB_EpiDoc_XML", "bgu", "bgu.1")
      FileUtils.mkdir_p(collection)
      FileUtils.cp(File.join(FIXTURES, "DDB_EpiDoc_XML", "bgu", "bgu.1", "bgu.1.100.xml"), collection)
      # A stray non-DDbDP xml (no ddb-hybrid idno) must be skipped, not error.
      File.write(File.join(collection, "stray.xml"), "<TEI><teiHeader/></TEI>\n")
      refs = Nabu::Adapters::Papyri.new.discover(root).to_a
      assert_equal ["urn:nabu:ddbdp:bgu:1:100"], refs.map(&:id)
    end
  end

  # --- parse round-trip -----------------------------------------------------

  def test_parse_delegates_to_ddbdp_parser_and_urn_matches_ref
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ddbdp:bgu:1:100" }
    document = adapter.parse(ref)
    assert_equal ref.id, document.urn
    assert_equal 12, document.size
    assert_equal "grc", document.language
    assert_equal "bgu.1.100", document.title
  end

  def test_parse_latin_document_spot_check
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).to_a.last
    document = adapter.parse(ref)
    assert_equal "lat", document.language
    assert_equal "urn:nabu:ddbdp:c.epist.lat::10:r:7", document.to_a[6].urn
    assert_equal "qui de tam pusilla summa tam magnum lucrum facit", document.to_a[6].text
  end

  # --- fetch (local git only, no network) -----------------------------------

  def test_fetch_clones_then_pulls_and_returns_report
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_git_repo(upstream)
      workdir = File.join(root, "work")
      adapter = papyri_pointing_at(upstream)

      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_instance_of Time, report.fetched_at
      assert File.directory?(File.join(workdir, ".git")), "repo must be cloned"
      assert_equal git(upstream, "rev-parse", "HEAD"), report.sha

      # Second call → pull path, still succeeds and reports the same sha.
      assert_equal report.sha, adapter.fetch(workdir).sha
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      workdir = File.join(root, "work")
      adapter = papyri_pointing_at(File.join(root, "does-not-exist"))
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_papyri_ddbdp_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["papyri-ddbdp"]
    refute_nil entry, "papyri-ddbdp must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Papyri, entry.adapter_class
    assert_equal "papyri-ddbdp", entry.manifest.id
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::Papyri.manifest, entry.manifest
  end

  private

  # An adapter whose repo_url resolves to a local git tmpdir (house test
  # pattern), keeping fetch entirely off the network.
  def papyri_pointing_at(upstream)
    adapter = Nabu::Adapters::Papyri.new
    adapter.define_singleton_method(:repo_url) { upstream }
    adapter
  end

  def make_git_repo(dir)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q")
    File.write(File.join(dir, "readme.txt"), "idp.data\n")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
