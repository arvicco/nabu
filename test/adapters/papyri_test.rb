# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Papyri.info (DDbDP + DCLP) adapter tests (P3-6; DCLP lane P104-3;
# post-switchover layout 2026-10). The adapter composes DdbdpParser with the
# idp.data repo layout: discover walks the curated DDbDP/<HGV-thousand>/
# <HGV>.xml tree, falls back to Historical/<collection>/(<volume>/)?<n>.xml
# for editions the curated tree does not (yet) carry as text, skips
# text-less stubs (no <lb> in the edition) in both, and walks
# DCLP/<dclp-thousand>/<dclp>.xml — the literary-papyri tree of the SAME
# idp.data clone — skipping its metadata-only catalog stubs; parse
# delegates to DdbdpParser (urn namespace dclp for DCLP refs); fetch
# clones/pulls the single upstream repo. Includes the shared
# AdapterConformance suite against the checked-in fixtures, plus the
# layout-migration proof: the same documents cut from the pre-switchover
# tree (test/fixtures/ddbdp/pre-switchover/) parse to identical urns and
# passages. No network: fetch runs against a local git repo in a tmpdir.
class PapyriTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("ddbdp") # NABU_FIXTURE_DIR-aware (fixtures:check)
  # The P5-1/P6-2 exemplars, re-cut in the new layout: aegyptus;89;240 is
  # text-bearing in BOTH DDbDP/25/25457.xml and Historical/aegyptus/89/240.xml.
  EXEMPLARS = File.expand_path("../fixtures/papyri-ddbdp", __dir__)
  # The same documents as cut from the pre-switchover tree (upstream commit
  # 0eec6593, byte-identical to its blobs), old path => new path.
  PRE_SWITCHOVER = File.join(FIXTURES, "pre-switchover")
  RELOCATED = {
    "DDB_EpiDoc_XML/bgu/bgu.1/bgu.1.100.xml" => "DDbDP/8/8875.xml",
    "DDB_EpiDoc_XML/bgu/bgu.1/bgu.1.102.xml" => "DDbDP/8/8877.xml",
    "DDB_EpiDoc_XML/c.epist.lat/c.epist.lat.10.xml" => "Historical/c.epist.lat/10.xml",
    "DCLP/63/62952.xml" => "DCLP/62/62952.xml",
    "DCLP/65/64388.xml" => "DCLP/64/64388.xml",
    "DCLP/806/805566.xml" => "DCLP/805/805566.xml"
  }.freeze

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

  def test_discover_walks_the_post_switchover_layout_with_frozen_urn_minting
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    assert_equal %w[
      urn:nabu:dclp:62952
      urn:nabu:dclp:64388
      urn:nabu:dclp:805566
      urn:nabu:ddbdp:bgu:1:100
      urn:nabu:ddbdp:bgu:1:102
      urn:nabu:ddbdp:c.epist.lat::10
      urn:nabu:ddbdp:p.ryl:4:560
    ], refs.map(&:id)
    refs.each do |ref|
      assert_equal "papyri-ddbdp", ref.source_id
      assert File.absolute_path?(ref.path), "path must be absolute: #{ref.path.inspect}"
      assert File.file?(ref.path)
    end
    # The urn comes from the in-file idno, never the path: the curated tree
    # names files by HGV number (DDbDP/8/8875.xml), the historical tree by
    # collection/volume/number, and neither shape leaks into the identity.
    paths = refs.to_h { |ref| [ref.id, ref.path.delete_prefix("#{FIXTURES}/")] }
    assert_equal "DDbDP/8/8875.xml", paths["urn:nabu:ddbdp:bgu:1:100"]
    assert_equal "DDbDP/8/8877.xml", paths["urn:nabu:ddbdp:bgu:1:102"]
    assert_equal "Historical/c.epist.lat/10.xml", paths["urn:nabu:ddbdp:c.epist.lat::10"]
    assert_equal "DCLP/62/62952.xml", paths["urn:nabu:dclp:62952"]
  end

  def test_discover_skips_curated_stubs_that_share_a_hybrid_with_a_historical_text
    # DDbDP/78/78573.xml is a real upstream stub generated from HGV: it carries
    # ddb-hybrid c.epist.lat;;10 (and a grc edition div) but only a "not yet
    # added" note over an empty <ab/>. The text of c.epist.lat;;10 lives in
    # Historical/c.epist.lat/10.xml (Latin). The stub must neither become a
    # ref nor shadow the historical text.
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    cel = refs.select { |ref| ref.id == "urn:nabu:ddbdp:c.epist.lat::10" }
    assert_equal 1, cel.size, "exactly one ref per urn"
    assert cel.first.path.end_with?("Historical/c.epist.lat/10.xml")
    assert_equal "lat", cel.first.metadata["language"]
    assert(refs.none? { |ref| ref.path.include?("78573") })
  end

  def test_discover_skips_historical_stubs_of_curated_texts
    # Historical/bgu/1/100.xml is upstream's "historical edition has not been
    # added" stub (empty <ab/>) for a text the curated tree carries.
    refs = Nabu::Adapters::Papyri.new.discover(FIXTURES).to_a
    assert(refs.none? { |ref| ref.path.include?("Historical/bgu") })
  end

  def test_discover_prefers_the_curated_tree_when_both_trees_carry_the_text
    # aegyptus;89;240 is text-bearing in both DDbDP/25/25457.xml and
    # Historical/aegyptus/89/240.xml; chrest.wilck;;101 survives only as a
    # text-less Historical stub (skipped, as it quarantined before).
    refs = Nabu::Adapters::Papyri.new.discover(EXEMPLARS).to_a
    assert_equal %w[urn:nabu:ddbdp:aegyptus:89:240 urn:nabu:ddbdp:o.claud:3:457], refs.map(&:id)
    assert refs.first.path.end_with?("DDbDP/25/25457.xml")
  end

  def test_discover_no_longer_walks_the_pre_switchover_layout
    # The single-layout decision: DDB_EpiDoc_XML/ is gone upstream and is not
    # tolerated as a further root. (The DCLP/ root kept its name — only its
    # bucketing changed — so the old DCLP files are still walked.)
    refs = Nabu::Adapters::Papyri.new.discover(PRE_SWITCHOVER).to_a
    assert(refs.none? { |ref| ref.id.start_with?("urn:nabu:ddbdp:") },
           "no documentary ref may come from DDB_EpiDoc_XML/")
    assert_equal %w[urn:nabu:dclp:62952 urn:nabu:dclp:64388 urn:nabu:dclp:805566], refs.map(&:id)
  end

  # --- the layout migration: identity is idno-minted, not path-minted ---------

  def test_relocated_documents_parse_to_identical_urns_and_passages_from_either_tree
    adapter = Nabu::Adapters::Papyri.new
    refs = adapter.discover(FIXTURES).to_h { |ref| [ref.path.delete_prefix("#{FIXTURES}/"), ref] }
    RELOCATED.each do |old_path, new_path|
      ref = refs.fetch(new_path)
      new_document = adapter.parse(ref)
      # The parser cross-checks the caller urn against the file's own idno,
      # so a clean parse of the OLD blob under the NEW ref's urn proves the
      # old file mints the same identity.
      old_document = adapter.parse(ref.with(path: File.join(PRE_SWITCHOVER, old_path)))
      assert_equal new_document.urn, old_document.urn, old_path
      assert_equal old_document.to_a.map { |p| [p.urn, p.text, p.annotations] },
                   new_document.to_a.map { |p| [p.urn, p.text, p.annotations] },
                   "#{old_path} -> #{new_path}: passages must re-mint byte-identically"
      refute_empty new_document.to_a
    end
  end

  def test_dclp_stale_bucket_duplicate_yields_to_the_canonical_bucket
    # Upstream re-sharded DCLP from the old bucket (<n>/1000 + 1) to
    # <n>/1000, but three ids (62441, 62509, 65542) still also exist at their
    # old-bucket path. One urn, one ref: the <n>/1000 bucket wins.
    Dir.mktmpdir do |root|
      %w[62 63].each do |bucket|
        FileUtils.mkdir_p(File.join(root, "DCLP", bucket))
        FileUtils.cp(File.join(FIXTURES, "DCLP", "62", "62952.xml"), File.join(root, "DCLP", bucket))
      end
      refs = Nabu::Adapters::Papyri.new.discover(root).to_a
      assert_equal ["urn:nabu:dclp:62952"], refs.map(&:id)
      assert refs.first.path.end_with?("DCLP/62/62952.xml")
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
    # DCLP/316/316777.xml is a real upstream catalog stub: dclp-hybrid and
    # a Coptic edition div, but the div is SELF-CLOSED — no transcription.
    # 12,567 of the 14,845 upstream DCLP files have this shape; they must
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
      collection = File.join(root, "DDbDP", "8")
      FileUtils.mkdir_p(collection)
      FileUtils.cp(File.join(FIXTURES, "DDbDP", "8", "8875.xml"), collection)
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

  # P104-1 (the aggressive-mining law, owner-ruled 2026-09-26): the HGV/TM idnos were peeked at discover
  # but never persisted — document metadata_json was {} on all 61,414
  # docs. They now ride as tm_nr/hgv verbatim plus a "tm:<n>" related
  # edge per numeric TM token (the P25-1 scheme rule; HGV has no ruled
  # edge scheme and stays metadata-only).
  def test_parse_persists_the_idnos_and_the_tm_related_edge
    adapter = Nabu::Adapters::Papyri.new
    # Named ref, not discovery order: the DCLP fixtures share this tree,
    # so `.first` is no longer guaranteed to be a DDbDP document.
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ddbdp:bgu:1:100" }
    document = adapter.parse(ref)
    assert_equal "8875", document.metadata["tm_nr"]
    assert_equal "8875", document.metadata["hgv"]
    assert_equal ["tm:8875"], document.metadata["related"]
  end

  # --- header mining: the HGV record beside each DDbDP text ------------------

  # The HGV metadata record (HGV_meta_EpiDoc/HGV<n/1000+1>/<hgv>.xml, the
  # same clone) carries what the edition file does not: P.Ryl. 4 560 is
  # "Apollonios an Zenon" in its LATER keyword terms (the leading term is
  # the text type the kind lane reads), "Gehört zum Zenon - Archiv" in its
  # commentary, and one date the text MENTIONS (line 5).
  def ryl560
    adapter = Nabu::Adapters::Papyri.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ddbdp:p.ryl:4:560" })
  end

  def test_parse_mines_the_hgv_sender_addressee_persons
    assert_equal [
      { "name" => "Apollonios", "role" => "sender", "term" => "Apollonios an Zenon" },
      { "name" => "Zenon", "role" => "addressee", "term" => "Apollonios an Zenon" }
    ], ryl560.metadata["persons"]
  end

  def test_parse_mines_the_hgv_archive_membership
    assert_equal ["Zenon - Archiv"], ryl560.metadata["archive"]
  end

  def test_parse_carries_mentioned_dates_as_their_own_class_never_the_origin_date
    meta = ryl560.metadata
    assert_equal [{ "ref" => "Z. 5", "when" => "-0256-10-04", "not_before" => -256,
                    "not_after" => -256, "raw" => "4. Okt. 256 v.Chr." }], meta["mentioned_dates"]
    refute meta.key?("date"), "the origin date (3 Oct 256 BCE) stays the HGV timeline lane's — " \
                              "a mentioned date is never the document's date"
  end

  def test_an_hgv_record_without_the_extras_adds_nothing
    adapter = Nabu::Adapters::Papyri.new
    document = adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ddbdp:bgu:1:100" })
    assert_equal %w[hgv related tm_nr], document.metadata.keys.sort
  end

  # Values verbatim from the live HGV census (2026-10-18): "NN"/"N.N." is
  # HGV's unnamed-party placeholder — a side carrying it is not a person;
  # designations ("den König") are upstream's own label and ride verbatim;
  # a document-act noun on the left ("Eingabe an …", "Lieferung (Öl) an
  # …") names the act, not a sender — only its addressee is a party.
  def test_keyword_persons_drop_placeholders_and_act_nouns
    persons = Nabu::Adapters::PapyriHeader.keyword_persons(
      ["Eingabe an den Strategen", "NN an NN", "N.N. an den König", "Eingabe an den Strategen",
       "Lieferung (Öl) an Zenon"]
    )
    assert_equal [{ "name" => "den König", "role" => "addressee", "term" => "N.N. an den König" },
                  { "name" => "den Strategen", "role" => "addressee", "term" => "Eingabe an den Strategen" },
                  { "name" => "Zenon", "role" => "addressee", "term" => "Lieferung (Öl) an Zenon" }],
                 persons, "the leading term is the text type, never mined; NN sides and act nouns drop"
  end

  # --- header mining: the DCLP header ---------------------------------------

  def dclp(id)
    adapter = Nabu::Adapters::Papyri.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:dclp:#{id}" }).metadata
  end

  def test_dclp_header_date_place_and_keywords_reach_the_metadata
    meta = dclp("62952")
    assert_equal({ "not_before" => 100, "not_after" => 120, "raw" => "100 - 120" }, meta["date"])
    assert_equal({ "ancient" => "Fundort: Claudianus Mons (Eastern desert, Egypt); " \
                                "Schreibort: Claudianus Mons (Eastern desert, Egypt)",
                   "ref" => "https://www.trismegistos.org/place/2783" }, meta["place"])
    assert_equal %w[verse epic classical literature poetry], meta["keywords"], "deduped, upstream order"
  end

  def test_dclp_place_refs_take_the_findspot_settlement_before_its_nome
    meta = dclp("64388")
    assert_equal({ "not_before" => 300, "not_after" => 399, "raw" => "300 - 399" }, meta["date"])
    assert_equal "https://www.trismegistos.org/place/1524 https://www.trismegistos.org/place/2722",
                 meta.dig("place", "ref")
    assert_equal ["medicine", "science", "list of spices, pharmaceutical prescriptions"], meta["keywords"]
  end

  def test_dclp_undated_header_mints_no_date_but_keeps_the_place
    meta = dclp("805566")
    refute meta.key?("date"), "origDate unbekannt is no date"
    assert_equal({ "ancient" => "Attica" }, meta["place"])
    assert_equal ["Magic", "prayer for justice"], meta["keywords"]
  end

  def test_reference_producer_records_under_the_source_name
    assert_predicate Nabu::Adapters::Papyri, :reference_edges?
    producer = Nabu::Adapters::Papyri.reference_producer(catalog: nil, journal: nil)
    assert_equal "papyri-ddbdp", producer.producer
  end

  def test_parse_latin_document_spot_check
    adapter = Nabu::Adapters::Papyri.new
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:ddbdp:c.epist.lat::10" }
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
    assert_equal "auto", entry.sync_policy, "re-promoted to the auto sweep after the switchover migration"
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
