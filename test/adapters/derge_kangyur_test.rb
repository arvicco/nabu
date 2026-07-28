# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::DergeKangyur (P48-1) — the Digital Derge Kangyur
  # (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur), first
  # registrant of the `esukhia-text` family and of the `tibetan` axis.
  # Fixtures are real trimmed volume files at the pinned archival commit
  # (see test/fixtures/derge-kangyur/README.md).
  class DergeKangyurTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("derge-kangyur")

    def conformance_adapter
      Nabu::Adapters::DergeKangyur.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "derge-kangyur"
    end

    # toh1 is upstream's own structure: {D1} immediately followed by {D1-1}
    # — a zero-text container whose content lives in its dash subtexts.
    def conformance_metadata_only?(document)
      document.metadata["container"] == true
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_derge_kangyur_and_manifest_agrees
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["derge-kangyur"]
      refute_nil entry, "derge-kangyur must be registered in config/sources.yml"
      refute entry.wired, "wired stays false until the owner-fired first sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal %w[tibetan buddhist], entry.axes
      assert_equal "derge-kangyur", entry.adapter_class.manifest.id
      assert_equal "open", entry.adapter_class.manifest.license_class,
                   "README-only Public Domain declaration → open (recorded honestly in the manifest)"
      assert_includes entry.adapter_class.manifest.license, "mechanical reproduction of a Public Domain work"
      assert_includes entry.adapter_class.manifest.license, "no LICENSE file"
    end

    def test_the_tibetan_axis_is_minted_once_and_serves_both_derge_sources
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      axis = registry.axes.each_axis.find { |a| a.name == "tibetan" }
      refute_nil axis, "config/axes.yml must mint the tibetan axis"
      assert_includes axis.persona, "Tibetologist"
      members = registry.public_axis_members("tibetan")
      # The desk grew the same day it was minted (e84000/otdo/treebanks/mvp
      # packets merged alongside) — pin the canon's membership and the
      # single mint, never a closed list.
      assert_includes members, "derge-kangyur"
      assert_includes members, "derge-tengyur"
    end

    # -- discover: Toh-boundary splitting -------------------------------------

    def test_discover_yields_one_ref_per_toh_marker_in_corpus_order
      assert_equal %w[
        urn:nabu:derge-kangyur:toh1
        urn:nabu:derge-kangyur:toh1-1
        urn:nabu:derge-kangyur:toh1-2
        urn:nabu:derge-kangyur:toh1-6
        urn:nabu:derge-kangyur:toh846
        urn:nabu:derge-kangyur:toh846a
        urn:nabu:derge-kangyur:toh847
        urn:nabu:derge-kangyur:toh848
        urn:nabu:derge-kangyur:toh852
      ], conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_discover_yields_nothing_from_a_workdir_without_volumes
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_discovery_skips_is_clean_on_the_fixture_corpus
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 0, skips.skipped_by_rule, "the kangyur preamble lines are marker-only — no text skipped"
      assert_predicate skips, :clean?
    end

    # -- parse: the container -------------------------------------------------

    def test_toh1_is_a_zero_passage_container_with_its_subtexts_declared
      document = parse_urn("urn:nabu:derge-kangyur:toh1")
      assert_predicate document, :empty?
      assert document.metadata["container"]
      assert_equal %w[toh1-1 toh1-2 toh1-6], document.metadata["subtexts"]
    end

    # -- parse: passages at page.line grain -----------------------------------

    def test_toh1_1_passages_ride_page_line_refs
      document = parse_urn("urn:nabu:derge-kangyur:toh1-1")
      assert_equal "xct", document.language
      assert_equal 65, document.size
      first = document.first
      assert_equal "urn:nabu:derge-kangyur:toh1-1:1b.1", first.urn
      assert first.text.start_with?("༄༅༅། །རྒྱ་གར་སྐད་དུ། བི་ན་ཡ་བསྟུ།"),
             "the Vinayavastu opening after the {D1}{D1-1} markers"
      assert_equal "D1-1", document.metadata["marker"]
      assert_equal "toh1", document.metadata["parent"], "a dash subindex declares its parent Toh"
    end

    def test_a_mid_line_boundary_splits_one_line_between_two_documents
      # Real line [131a.4]: toh1-1's closing text, then {D1-2} mid-line.
      # Both documents mint a passage cited 131a.4 — same ref, different urn.
      last = parse_urn("urn:nabu:derge-kangyur:toh1-1").to_a.last
      assert_equal "urn:nabu:derge-kangyur:toh1-1:131a.4", last.urn
      assert last.text.end_with?("རྫོགས་སྷོ།། །།"), "toh1-1 keeps the text BEFORE the marker (archaic reading kept)"

      d12 = parse_urn("urn:nabu:derge-kangyur:toh1-2")
      assert_equal 13, d12.size
      assert_equal "urn:nabu:derge-kangyur:toh1-2:131a.4", d12.first.urn
      assert d12.first.text.start_with?("གསོ་སྦྱོང་གི་གཞིའི་སྡོམ་ལ།"), "toh1-2 starts AFTER the marker"
    end

    def test_a_bare_page_line_mints_no_passage
      # [49a] stands alone in the 001 trim — a page marker with no text.
      refute_includes parse_urn("urn:nabu:derge-kangyur:toh1-1").map(&:urn),
                      "urn:nabu:derge-kangyur:toh1-1:49a"
    end

    # -- parse: the multi-volume rule (STATED PROMINENTLY) --------------------
    #
    # Derge pagination restarts per physical volume, and a Toh text spans
    # whole volume files (vols 002/004 carry ZERO markers). page.line alone
    # is therefore NOT unique inside a multi-volume document, so: a document
    # spanning >1 volume file volume-prefixes EVERY passage ref
    # (`toh1-6:2.1b.3`); single-volume documents keep the contract's bare
    # `page.line`. Residual collisions take the house `:b2`.

    def test_toh1_6_spans_three_volume_files_with_volume_prefixed_refs
      document = parse_urn("urn:nabu:derge-kangyur:toh1-6")
      assert_equal [1, 2, 100], document.metadata["volumes"]
      assert_equal 33, document.size
      assert_equal "urn:nabu:derge-kangyur:toh1-6:1.277b.6", document.first.urn
      urns = document.map(&:urn)
      assert_includes urns, "urn:nabu:derge-kangyur:toh1-6:2.1a.1",
                      "volume 002 restarts pagination at 1a — the volume prefix is what keeps refs unique"
      assert_equal "urn:nabu:derge-kangyur:toh1-6:100.1a.1", urns.last
    end

    def test_a_volume_title_line_is_absorbed_by_the_spanning_document
      # Volume 002's [1a.1] title line (འདུལ་བ་ཁ་བཞུགས་སོ) belongs to the
      # text OPEN at the volume boundary — upstream's own export behaviour.
      document = parse_urn("urn:nabu:derge-kangyur:toh1-6")
      title_line = document.find { |p| p.urn.end_with?(":2.1a.1") }
      assert_includes title_line.text, "འདུལ་བ་ཁ་བཞུགས་སོ"
    end

    # -- parse: subtext suffixes ----------------------------------------------

    def test_letter_suffixed_toh846a_is_a_tohoku_gap_text_not_a_subindex
      document = parse_urn("urn:nabu:derge-kangyur:toh846a")
      assert_equal 6, document.size
      assert_equal "D846a", document.metadata["marker"]
      assert document.metadata["tohoku_gap"],
             "a letter suffix means missing-from-Tohoku (README), not a subdivision"
      assert_nil document.metadata["parent"]
      assert_equal "urn:nabu:derge-kangyur:toh846a:3b.1", document.first.urn
      assert document.first.text.start_with?("རྒྱུད་གསུམ་པ།")
    end

    def test_toh847_starts_mid_line_after_toh846a_ends
      document = parse_urn("urn:nabu:derge-kangyur:toh847")
      assert_equal 21, document.size
      assert_equal "urn:nabu:derge-kangyur:toh847:3b.6", document.first.urn
      assert document.first.text.start_with?("༄༅། །རྒྱ་གར་སྐད་དུ། ཨཱརྱ་རཏྣོལྐ་ནཱ་མ")
    end

    # -- parse: apparatus (original readings preserved verbatim) --------------

    def test_suggestion_pairs_keep_the_original_and_annotate_the_correction
      document = parse_urn("urn:nabu:derge-kangyur:toh852")
      first = document.first
      assert_equal "urn:nabu:derge-kangyur:toh852:65a.1", first.urn
      assert_includes first.text, "ཨཱརྱ་སཔྟ་པུདྡྷ་ཀཾ་", "the (པུ,བུ) pair keeps པུ — the carved reading"
      app = first.annotations["apparatus"].find { |a| a["kind"] == "suggestion" }
      assert_equal "པུ", app["original"]
      assert_equal "བུ", app["suggested"]
      assert_equal "པུ", first.text[app["offset"], app["original"].length]
    end

    def test_archaic_pairs_keep_the_archaic_spelling_and_annotate_the_modern
      last = parse_urn("urn:nabu:derge-kangyur:toh1-1").to_a.last
      app = last.annotations["apparatus"].find { |a| a["kind"] == "archaic" }
      assert_equal "སྷོ", app["original"]
      assert_equal "སོ", app["modern"]
    end

    # -- load: idempotency ----------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = derge_source(catalog)
      loader = Nabu::Store::Loader.new(db: catalog, source: source)
      first = loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 9, first.added, "8 content documents + the toh1 container"
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "an unchanged corpus must not fake content revisions"
    end

    # -- fetch (pinned commit; local repos, no network) -----------------------

    def test_fetch_accepts_the_pinned_commit
      with_local_upstream do |repo_url, sha|
        Dir.mktmpdir do |root|
          workdir = File.join(root, "work")
          adapter = Nabu::Adapters::DergeKangyur.new(repo_url: repo_url, pinned_sha: sha)
          report = adapter.fetch(workdir)
          assert_equal sha, report.sha
          assert File.file?(File.join(workdir, "text", "001_འདུལ་བ།_ཀ.txt"))
        end
      end
    end

    def test_fetch_stops_loudly_when_upstream_drifts_from_the_pin
      with_local_upstream do |repo_url, sha|
        Dir.mktmpdir do |root|
          adapter = Nabu::Adapters::DergeKangyur.new(repo_url: repo_url, pinned_sha: "0" * 40)
          error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
          assert_includes error.message, sha[0, 12], "the drift message names the fetched sha"
          assert_includes error.message, "pin", "…and points at the re-pin decision"
        end
      end
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def derge_source(_catalog)
      Nabu::Store::Source.create(
        slug: "derge-kangyur", name: "Digital Derge Kangyur",
        adapter_class: "Nabu::Adapters::DergeKangyur", license_class: "open"
      )
    end

    def with_local_upstream
      Dir.mktmpdir do |dir|
        upstream = File.join(dir, "upstream")
        FileUtils.mkdir_p(File.join(upstream, "text"))
        Dir.glob(File.join(FIXTURES, "text", "*.txt")).each do |file|
          FileUtils.cp(file, File.join(upstream, "text"))
        end
        Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=master")
        Nabu::Shell.run("git", "-C", upstream, "add", ".")
        Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                        "commit", "--quiet", "-m", "volumes")
        yield upstream, Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
      end
    end
  end
end
